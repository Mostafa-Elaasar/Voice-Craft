extends Node
## Pure-voice recording. Filters only exist as an engineer feature (used on playback).

signal auto_stopped

const MAX_SECONDS := 8.0

var audio_player: AudioStreamPlayer
var mic_player: AudioStreamPlayer
var record_effect: AudioEffectRecord
var recorded_sample: AudioStreamWAV = null
var recorded_length: float = 0.0
var is_recording: bool = false
var _t0: int = 0
var _rec_idx: int = -1
var _analyzer := VoiceAnalyzer.new()


func _ready() -> void:
	if OS.get_name() == "Android":
		OS.request_permissions()
	var sil := _bus("RecSilent")
	AudioServer.set_bus_mute(sil, true)
	_rec_idx = _bus("Record")
	# A bus can only send to a bus BELOW it, so Record must sit after RecSilent.
	if _rec_idx < sil:
		AudioServer.move_bus(_rec_idx, AudioServer.bus_count - 1)
		_rec_idx = AudioServer.get_bus_index("Record")
	AudioServer.set_bus_mute(_rec_idx, false)
	AudioServer.set_bus_send(_rec_idx, "RecSilent")  # recorded + metered, never heard
	for i in AudioServer.get_bus_effect_count(_rec_idx):
		var fx := AudioServer.get_bus_effect(_rec_idx, i)
		if fx is AudioEffectRecord:
			record_effect = fx
	if record_effect == null:
		record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(_rec_idx, record_effect)
	_bus("Playback")

	audio_player = AudioStreamPlayer.new()
	audio_player.bus = "Playback"
	add_child(audio_player)
	mic_player = AudioStreamPlayer.new()
	mic_player.stream = AudioStreamMicrophone.new()
	mic_player.bus = "Record"
	add_child(mic_player)  # the mic only runs while you hold record


func _bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _process(_d: float) -> void:
	if is_recording and (Time.get_ticks_msec() - _t0) / 1000.0 > MAX_SECONDS:
		stop_recording()
		auto_stopped.emit()


func get_live_level() -> float:
	var db := maxf(AudioServer.get_bus_peak_volume_left_db(_rec_idx, 0), AudioServer.get_bus_peak_volume_right_db(_rec_idx, 0))
	return clampf((db + 55.0) / 55.0, 0.0, 1.0)


func start_recording() -> void:
	if not mic_player.playing:
		mic_player.play()
	if record_effect and not record_effect.is_recording_active():
		record_effect.set_recording_active(true)
		is_recording = true
		_t0 = Time.get_ticks_msec()


func stop_recording() -> void:
	if not is_recording:
		return
	is_recording = false
	record_effect.set_recording_active(false)
	var s := record_effect.get_recording()
	mic_player.stop()
	if s != null and s.data.size() > 0:
		recorded_sample = s
		recorded_length = s.get_length()
	else:
		clear_recording()


func clear_recording() -> void:
	recorded_sample = null
	recorded_length = 0.0


func analyze() -> Dictionary:
	return await _analyzer.analyze(recorded_sample, get_tree())


## Plays your recording. "Normal" = pure voice. Other filters are the engineer's work.
func play(filter_type: String = "Normal") -> void:
	if recorded_sample == null:
		return
	audio_player.stop()
	audio_player.stream = recorded_sample
	audio_player.volume_db = 4.0
	var bus := AudioServer.get_bus_index("Playback")
	while AudioServer.get_bus_effect_count(bus) > 0:
		AudioServer.remove_bus_effect(bus, 0)
	audio_player.pitch_scale = 1.0
	match filter_type:
		"Chipmunk":
			audio_player.pitch_scale = 1.6
		"Monster":
			audio_player.pitch_scale = 0.55
			var od := AudioEffectDistortion.new()
			od.mode = AudioEffectDistortion.MODE_OVERDRIVE
			od.drive = 0.3
			AudioServer.add_bus_effect(bus, od)
		"Retro 8-Bit":
			var lofi := AudioEffectDistortion.new()
			lofi.mode = AudioEffectDistortion.MODE_LOFI
			lofi.drive = 0.4
			AudioServer.add_bus_effect(bus, lofi)
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 1800.0
			AudioServer.add_bus_effect(bus, lp)
		"Telephonic":
			var bp := AudioEffectBandPassFilter.new()
			bp.cutoff_hz = 1800.0
			AudioServer.add_bus_effect(bus, bp)
	audio_player.play()
