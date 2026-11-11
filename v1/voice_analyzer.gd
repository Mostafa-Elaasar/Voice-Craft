class_name VoiceAnalyzer
extends RefCounted
## Measures a raw recording (pitch, loudness, pace, expressiveness, "is it a voice?")
## and scores it against what the client asked for.
## Everything is compared with the player's own VOICE CHECK baseline, so it works
## for any voice (deep or high) and any microphone.

const MAX_SECONDS := 8.0


## Coroutine: call with `await`. Returns metrics, or {"ok": false, "reason": ...}.
func analyze(sample: AudioStreamWAV, tree: SceneTree) -> Dictionary:
	var fail := {"ok": false, "reason": "silence"}
	if sample == null or sample.data.size() < 2000:
		return fail
	if sample.format != AudioStreamWAV.FORMAT_16_BITS:
		fail["reason"] = "format"
		return fail

	var channels: int = 2 if sample.stereo else 1
	var rate: int = sample.mix_rate
	var data: PackedByteArray = sample.data
	var step_bytes: int = 2 * channels
	var frames_total: int = data.size() / step_bytes
	var dec: int = maxi(1, int(round(float(rate) / 4000.0)))
	var er: float = float(rate) / float(dec)  # analysis sample rate (~4 kHz)
	var n_out: int = mini(frames_total / dec, int(er * MAX_SECONDS))

	# ---- 1. decode -> mono, downsample, high-pass ----
	var x := PackedFloat32Array()
	x.resize(n_out)
	var clipped := 0
	var raw_count := 0
	var hp_in := 0.0
	var hp_out := 0.0
	for o in n_out:
		var acc := 0.0
		var base := o * dec
		for k in dec:
			var s := float(data.decode_s16((base + k) * step_bytes)) / 32768.0
			acc += s
			if absf(s) >= 0.98:
				clipped += 1
			raw_count += 1
		var v := acc / float(dec)
		var y := v - hp_in + 0.97 * hp_out
		hp_in = v
		hp_out = y
		x[o] = y
		if o % 5000 == 4999:
			await tree.process_frame

	# ---- 2. frame loudness ----
	var fl: int = int(er * 0.032)
	var hop: int = int(er * 0.016)
	var n_frames: int = (n_out - fl) / hop
	if n_frames < 12:
		fail["reason"] = "too_short"
		return fail
	var db := PackedFloat32Array()
	db.resize(n_frames)
	for f in n_frames:
		var s0 := f * hop
		var e := 0.0
		for i in fl:
			var v := x[s0 + i]
			e += v * v
		db[f] = linear_to_db(sqrt(e / float(fl)) + 1e-6)

	var sorted_db: Array = Array(db)
	sorted_db.sort()
	var floor_db: float = _pct(sorted_db, 0.10)
	var peak_db: float = sorted_db[sorted_db.size() - 1]
	if peak_db < -50.0:
		return fail  # nothing audible
	var gate: float = minf(maxf(floor_db + 9.0, peak_db - 32.0), peak_db - 10.0)

	var first := -1
	var last := -1
	var active_dbs: Array = []
	for f in n_frames:
		if db[f] >= gate:
			if first == -1:
				first = f
			last = f
			active_dbs.append(db[f])
	if active_dbs.size() < 8:
		fail["reason"] = "too_short"
		return fail

	# ---- 3. pitch (autocorrelation) on active frames ----
	var min_lag: int = int(er / 400.0)
	var max_lag: int = int(er / 75.0)
	var r := PackedFloat32Array()
	r.resize(max_lag + 3)
	var contour: Array = []
	var done := 0
	for f in range(first, last + 1):
		if db[f] < gate:
			continue
		var s0 := f * hop
		var r0 := 0.0
		for i in fl:
			r0 += x[s0 + i] * x[s0 + i]
		if r0 < 1e-9:
			continue
		var best := 0.0
		var best_lag := 0
		for lag in range(min_lag, max_lag + 1):
			var acc := 0.0
			var lim := fl - lag
			for i in range(0, lim, 2):
				acc += x[s0 + i] * x[s0 + i + lag]
			var norm := (acc * 2.0 / r0) * (float(fl) / float(lim))
			r[lag] = norm
			if norm > best:
				best = norm
				best_lag = lag
		if best >= 0.42 and best_lag > 0:
			var pick := best_lag
			for lag in range(min_lag + 1, best_lag):
				if r[lag] >= 0.88 * best and r[lag] >= r[lag - 1] and r[lag] >= r[lag + 1]:
					pick = lag
					break
			var lag_f := float(pick)
			if pick > min_lag and pick < max_lag:
				var a := r[pick - 1]
				var b := r[pick]
				var c := r[pick + 1]
				var denom := a - 2.0 * b + c
				if absf(denom) > 1e-9:
					lag_f += clampf(0.5 * (a - c) / denom, -1.0, 1.0)
			contour.append(er / lag_f)
		done += 1
		if done % 12 == 0:
			await tree.process_frame

	var voiced_ratio: float = float(contour.size()) / float(active_dbs.size())
	if contour.size() < 6 or voiced_ratio < 0.28:
		return {"ok": false, "reason": "not_voice"}

	# smooth the contour (3-point median) and convert to semitones
	var st: Array = []
	for i in contour.size():
		var tri: Array = [contour[maxi(i - 1, 0)], contour[i], contour[mini(i + 1, contour.size() - 1)]]
		tri.sort()
		st.append(12.0 * log(float(tri[1]) / 100.0) / log(2.0))
	var st_sorted: Array = st.duplicate()
	st_sorted.sort()
	var med_st: float = _pct(st_sorted, 0.5)
	var pitch_range: float = _pct(st_sorted, 0.9) - _pct(st_sorted, 0.1)
	var pitch_hz: float = 100.0 * pow(2.0, med_st / 12.0)

	# ---- 4. loudness stats ----
	active_dbs.sort()
	var level_db: float = _pct(active_dbs, 0.75)
	var dyn_db: float = _pct(active_dbs, 0.90) - _pct(active_dbs, 0.25)

	# ---- 5. syllable-ish peaks in the loudness contour ----
	var sm := PackedFloat32Array()
	sm.resize(n_frames)
	for f in n_frames:
		sm[f] = (db[maxi(f - 1, 0)] + db[f] + db[mini(f + 1, n_frames - 1)]) / 3.0
	var peaks := 0
	var last_peak := -100
	for f in range(first + 1, last):
		if sm[f] > gate + 5.0 and sm[f] >= sm[f - 1] and sm[f] > sm[f + 1] and f - last_peak >= 7:
			var lo := sm[f]
			for k in range(maxi(f - 7, first), mini(f + 8, last + 1)):
				lo = minf(lo, sm[k])
			if sm[f] - lo >= 2.5:
				peaks += 1
				last_peak = f

	var span: float = float(last - first + 1) * float(hop) / er
	return {
		"ok": true,
		"duration": float(n_out) / er,
		"span": span,
		"peak_db": peak_db,
		"level_db": level_db,
		"dyn_db": dyn_db,
		"voiced_ratio": voiced_ratio,
		"pitch_hz": pitch_hz,
		"pitch_range": pitch_range,
		"peaks": peaks,
		"clip_ratio": float(clipped) / float(maxi(raw_count, 1)),
	}


func _pct(sorted_arr: Array, p: float) -> float:
	if sorted_arr.is_empty():
		return 0.0
	return float(sorted_arr[clampi(int(p * float(sorted_arr.size() - 1)), 0, sorted_arr.size() - 1)])


## Scores metrics against the client's traits, relative to the player's baseline.
static func score(m: Dictionary, base: Dictionary, traits: Dictionary, syll: int) -> Dictionary:
	var rows: Array = []
	var st_diff: float = 12.0 * log(maxf(float(m["pitch_hz"]), 50.0) / maxf(float(base["pitch_hz"]), 50.0)) / log(2.0)
	var d_level: float = float(m["level_db"]) - float(base["level_db"])
	var rate_est: float = float(syll) / maxf(float(m["span"]), 0.25)
	var ratio: float = rate_est / maxf(float(base["rate"]), 0.5)
	var range_st: float = float(m["pitch_range"])
	var dyn: float = float(m["dyn_db"])

	if traits.has("pitch"):
		var high: bool = traits["pitch"] == "high"
		var target: float = 4.5 if high else -4.0
		var s: float = clampf(1.0 - absf(st_diff - target) / 6.0, 0.0, 1.0)
		rows.append({
			"key": "pitch", "icon": "🎵", "name": "HIGH PITCH" if high else "DEEP PITCH", "score": s,
			"hint": "Go HIGHER! Squeak it up!" if high else "Go DEEPER! Rumble from your chest.",
		})
	if traits.has("level"):
		var loud: bool = traits["level"] == "loud"
		var target: float = 8.0 if loud else -8.0
		var s: float = clampf(1.0 - absf(d_level - target) / 10.0, 0.0, 1.0)
		rows.append({
			"key": "level", "icon": "🔊" if loud else "🤫", "name": "LOUD" if loud else "SOFT", "score": s,
			"hint": "LOUDER! Project your voice!" if loud else "Softer... a gentle, quiet voice.",
		})
	if traits.has("pace"):
		var fast: bool = traits["pace"] == "fast"
		var target: float = 1.4 if fast else 0.65
		var s: float = clampf(1.0 - absf(log(maxf(ratio, 0.05) / target)) / log(1.8), 0.0, 1.0)
		rows.append({
			"key": "pace", "icon": "⚡" if fast else "🐢", "name": "FAST" if fast else "SLOW", "score": s,
			"hint": "Talk FASTER! Barely breathe!" if fast else "Slooow dowwwn. Stretch every word.",
		})
	if traits.has("expr"):
		var dramatic: bool = traits["expr"] == "dramatic"
		var s: float
		if dramatic:
			s = 0.65 * clampf((range_st - 3.0) / 7.0, 0.0, 1.0) + 0.35 * clampf((dyn - 6.0) / 10.0, 0.0, 1.0)
		else:
			s = 0.7 * clampf(1.0 - (range_st - 2.5) / 5.0, 0.0, 1.0) + 0.3 * clampf(1.0 - (dyn - 6.0) / 8.0, 0.0, 1.0)
		rows.append({
			"key": "expr", "icon": "🎭" if dramatic else "🤖", "name": "DRAMATIC" if dramatic else "FLAT", "score": s,
			"hint": "More EMOTION! Act it out!" if dramatic else "Too much melody. Stay flat like a robot.",
		})

	var clarity: float = 0.5 * clampf((float(m["voiced_ratio"]) - 0.25) / 0.35, 0.0, 1.0)
	clarity += 0.5 * clampf(float(m["peaks"]) / maxf(0.5 * float(syll), 1.0), 0.0, 1.0)
	rows.append({"key": "clarity", "icon": "🎙️", "name": "CLEAR VOICE", "score": clarity, "hint": "Speak clearly and say the whole line!"})

	var wsum := 0.0
	var acc := 0.0
	var worst: Dictionary = rows[0]
	for row in rows:
		var w: float = 0.7 if row["key"] == "clarity" else 1.0
		wsum += w
		acc += w * float(row["score"])
		if float(row["score"]) < float(worst["score"]):
			worst = row
	var total: float = acc / wsum * 100.0

	var clipped: bool = float(m["clip_ratio"]) > 0.03
	if clipped:
		total *= 1.0 - minf(0.3, (float(m["clip_ratio"]) - 0.03) * 6.0)

	var hint: String = worst["hint"] if float(worst["score"]) < 0.7 else "Great delivery!"
	if clipped:
		hint = "Too close to the mic - your voice is distorted!"
	var debug := "You: pitch %+.1f st  •  volume %+.1f dB  •  pace x%.2f  •  melody %.1f st" % [st_diff, d_level, ratio, range_st]
	return {"score": total, "rows": rows, "hint": hint, "debug": debug}
