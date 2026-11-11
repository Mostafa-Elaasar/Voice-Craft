extends Node2D
## VoiceCraft main scene. Portrait + landscape (phone, PC, web). Needs ClientCharacter (client_character.gd).

@onready var record_manager = $RecordManager
@onready var economy_manager = $EconomyManager

signal judge_closed

const GOLD := Color8(255, 210, 60)
const REASONS := {
	"silence": "🔇 I can't hear you! Hold the button and speak up.",
	"too_short": "⏱️ Too short! Say the whole line.",
	"not_voice": "🙉 That didn't sound like a voice...",
	"format": "Recording format not supported.",
}

var root: Control
var content: BoxContainer
var desk: PanelContainer
var studio: Control
var client_char: ClientCharacter
var bubble: RichTextLabel
var patience: ProgressBar
var cash_label: Label
var rank_label: Label
var meter: ProgressBar
var status: Label
var filter_row: HBoxContainer
var record_btn: Button
var play_btn: Button
var submit_btn: Button
var judge: Control
var judge_label: Label
var judge_btn: Button
var shop: Control
var shop_list: VBoxContainer
var sfx: Dictionary = {}
var selected_filter: String = "Normal"
var is_recording: bool = false
var busy: bool = false
var t0: int = 0
var _rank_up_pending: bool = false


# ============================================================ helpers
func _sb(col: Color, radius: int = 0, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	s.border_color = border
	return s


func _lbl(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _btn(text: String, col: Color, h: float = 60.0, fs: int = 22, dark_text: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	var fc := Color8(30, 20, 50) if dark_text else Color.WHITE
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(c, fc)
	b.add_theme_stylebox_override("normal", _sb(col, 12))
	b.add_theme_stylebox_override("hover", _sb(col.lightened(0.1), 12))
	b.add_theme_stylebox_override("pressed", _sb(col.darkened(0.3), 12))
	b.add_theme_stylebox_override("disabled", _sb(col.darkened(0.55), 12))
	return b


func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _margin(child: Control, px: int) -> MarginContainer:
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, px)
	m.add_child(child)
	return m


# ============================================================ build
func _ready() -> void:
	var win := get_window()
	win.content_scale_size = Vector2i(720, 720)
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND  # any shape: portrait or landscape
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR)

	var old := get_node_or_null("CanvasLayer")
	if old:
		old.queue_free()
	var ui := CanvasLayer.new()
	add_child(ui)
	root = Control.new()
	_full(root)
	ui.add_child(root)
	var vb := VBoxContainer.new()
	_full(vb)
	vb.add_theme_constant_override("separation", 0)
	root.add_child(vb)

	var hud := PanelContainer.new()
	hud.custom_minimum_size = Vector2(0, 64)
	hud.add_theme_stylebox_override("panel", _sb(Color8(12, 10, 30)))
	var hb := HBoxContainer.new()
	cash_label = _lbl("", 30, Color8(0, 255, 180))
	cash_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank_label = _lbl("", 22, GOLD)
	hb.add_child(cash_label)
	hb.add_child(rank_label)
	hud.add_child(_margin(hb, 12))
	vb.add_child(hud)

	content = BoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	vb.add_child(content)
	_build_studio()
	_build_desk()
	content.add_child(studio)
	content.add_child(desk)
	_build_judge()
	_build_shop()
	_build_sfx()

	get_viewport().size_changed.connect(_on_resized)
	studio.resized.connect(_on_studio_resized)
	record_manager.auto_stopped.connect(_stop_rec)
	economy_manager.economy_updated.connect(_on_economy)
	economy_manager.order_changed.connect(func(_o): _show_new_client())
	economy_manager.order_expired.connect(_on_expired)
	economy_manager.rank_up.connect(func(n): _rank_up_pending = true; _sfx("win"); _toast("🎉 RANK UP: " + n))
	_on_resized()
	_on_economy()
	if economy_manager.current_order.is_empty():
		economy_manager.generate_order()
	else:
		_show_new_client()


func _build_studio() -> void:
	studio = Control.new()
	studio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	studio.size_flags_vertical = Control.SIZE_EXPAND_FILL
	studio.custom_minimum_size = Vector2(300, 250)
	studio.clip_contents = true
	var layers := [[0.0, 1.0, Color8(52, 40, 92)], [0.68, 1.0, Color8(60, 40, 28)]]
	for l in layers:
		var r := ColorRect.new()
		_full(r)
		r.anchor_top = l[0]
		r.color = l[2]
		studio.add_child(r)
	client_char = ClientCharacter.new()
	client_char.position = Vector2(150, 300)
	studio.add_child(client_char)
	for l in [[0.74, 0.8, Color8(214, 160, 98)], [0.8, 1.0, Color8(110, 70, 38)]]:  # counter (drawn over the client)
		var r := ColorRect.new()
		_full(r)
		r.anchor_top = l[0]
		r.anchor_bottom = l[1]
		r.color = l[2]
		studio.add_child(r)
	var bp := Panel.new()
	_full(bp)
	bp.anchor_left = 0.4
	bp.anchor_right = 0.97
	bp.anchor_top = 0.04
	bp.anchor_bottom = 0.44
	bp.add_theme_stylebox_override("panel", _sb(Color8(30, 25, 60), 16, GOLD, 3))
	studio.add_child(bp)
	bubble = RichTextLabel.new()
	_full(bubble)
	bubble.bbcode_enabled = true
	bubble.add_theme_font_size_override("normal_font_size", 21)
	bubble.add_theme_font_size_override("bold_font_size", 23)
	bubble.offset_left = 12
	bubble.offset_top = 8
	bubble.offset_right = -12
	bubble.offset_bottom = -8
	bp.add_child(bubble)
	patience = ProgressBar.new()
	_full(patience)
	patience.anchor_left = 0.4
	patience.anchor_right = 0.97
	patience.anchor_top = 0.46
	patience.anchor_bottom = 0.46
	patience.offset_bottom = 16
	patience.show_percentage = false
	patience.add_theme_stylebox_override("fill", _sb(Color8(60, 220, 110), 8))
	patience.add_theme_stylebox_override("background", _sb(Color8(10, 8, 25), 8))
	studio.add_child(patience)


func _build_desk() -> void:
	desk = PanelContainer.new()
	desk.add_theme_stylebox_override("panel", _sb(Color8(20, 20, 45)))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	desk.add_child(_margin(v, 12))
	status = _lbl("", 17, Color8(150, 240, 255))
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(0, 44)
	v.add_child(status)
	meter = ProgressBar.new()
	meter.show_percentage = false
	meter.custom_minimum_size = Vector2(0, 16)
	v.add_child(meter)
	filter_row = HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 6)
	v.add_child(filter_row)
	record_btn = _btn("🔴 HOLD TO RECORD", Color8(255, 40, 80), 96, 26)
	record_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	record_btn.button_down.connect(_start_rec)
	record_btn.button_up.connect(_stop_rec)
	v.add_child(record_btn)
	var r1 := HBoxContainer.new()
	play_btn = _btn("▶️ PLAY BACK", Color8(50, 130, 255), 60, 20)
	submit_btn = _btn("🚀 SUBMIT", Color8(150, 50, 255), 60, 20)
	play_btn.pressed.connect(_on_play)
	submit_btn.pressed.connect(_on_submit)
	r1.add_child(play_btn)
	r1.add_child(submit_btn)
	v.add_child(r1)
	var r2 := HBoxContainer.new()
	var shop_btn := _btn("🛒 SHOP", Color8(40, 170, 100), 50, 18)
	var check_btn := _btn("🎤 VOICE CHECK", Color8(90, 90, 140), 50, 18)
	shop_btn.pressed.connect(func(): if not busy: _refresh_shop(); shop.visible = true; economy_manager.patience_paused = true)
	check_btn.pressed.connect(func(): if not busy and not is_recording: economy_manager.start_calibration())
	r2.add_child(shop_btn)
	r2.add_child(check_btn)
	v.add_child(r2)
	_update_status()


func _overlay() -> Control:
	var o := Control.new()
	_full(o)
	o.visible = false
	var dim := ColorRect.new()
	_full(dim)
	dim.color = Color(0, 0, 0, 0.88)
	o.add_child(dim)
	root.add_child(o)
	return o


func _build_judge() -> void:
	judge = _overlay()
	var c := CenterContainer.new()
	_full(c)
	judge.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(560, 0)
	p.add_theme_stylebox_override("panel", _sb(Color8(24, 22, 54), 20, GOLD, 4))
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(_margin(v, 20))
	judge_label = _lbl("", 22, Color.WHITE)
	judge_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(judge_label)
	judge_btn = _btn("", Color8(40, 190, 100), 64, 24)
	judge_btn.pressed.connect(func(): judge.visible = false; judge_closed.emit())
	v.add_child(judge_btn)


func _build_shop() -> void:
	shop = _overlay()
	var v := VBoxContainer.new()
	_full(v)
	v.offset_left = 16
	v.offset_right = -16
	v.offset_top = 16
	v.offset_bottom = -16
	shop.add_child(v)
	v.add_child(_lbl("🛒 STUDIO UPGRADES", 32, GOLD))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	shop_list = VBoxContainer.new()
	shop_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_list.add_theme_constant_override("separation", 10)
	sc.add_child(shop_list)
	var close := _btn("✖ CLOSE", Color8(200, 50, 70), 60, 24)
	close.pressed.connect(func(): shop.visible = false; economy_manager.patience_paused = false)
	v.add_child(close)


func _refresh_shop() -> void:
	for c in shop_list.get_children():
		c.queue_free()
	for id in economy_manager.get_upgrade_ids():
		var info: Dictionary = economy_manager.get_upgrade_info(id)
		var row := HBoxContainer.new()
		var l := _lbl("%s %s  (Lv %d/%d)\n%s" % [info["icon"], info["title"], economy_manager.get_level(id), info["max"], info["desc"]], 18, Color.WHITE)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var cost: int = economy_manager.get_upgrade_cost(id)
		var b := _btn("MAX" if economy_manager.is_maxed(id) else "$%d" % cost, Color8(40, 170, 100), 64, 20)
		b.custom_minimum_size = Vector2(120, 64)
		b.size_flags_horizontal = 0
		b.disabled = economy_manager.is_maxed(id) or economy_manager.cash < cost
		b.pressed.connect(func(): if economy_manager.buy_upgrade(id): _sfx("coin"))
		row.add_child(b)
		shop_list.add_child(row)


# ============================================================ layout / HUD
func _on_resized() -> void:
	var vs := get_viewport_rect().size
	var portrait := vs.y > vs.x
	content.vertical = portrait
	desk.custom_minimum_size = Vector2(0, 400) if portrait else Vector2(440, 0)


func _on_studio_resized() -> void:
	var s := studio.size
	var u := clampf(minf(s.x, s.y) / 480.0, 0.8, 1.7)
	client_char.scale = Vector2(u, u)
	client_char.position = Vector2(s.x * 0.2, s.y * 0.6)
	client_char._target_x = client_char.position.x


func _on_economy() -> void:
	cash_label.text = "💰 $%d   ⚡ $%d/s" % [economy_manager.cash, int(economy_manager.passive_income_rate)]
	rank_label.text = "🏆 %s  ⭐%d" % [economy_manager.get_rank_name(), economy_manager.reputation]
	_refresh_filters()
	if shop.visible:
		_refresh_shop()


func _refresh_filters() -> void:
	for c in filter_row.get_children():
		c.queue_free()
	if economy_manager.is_auto():
		filter_row.add_child(_lbl("🎛️ Your engineer applies filters automatically!", 16, GOLD))
		return
	var names: Array = ["Normal"] + economy_manager.unlocked_filters()
	if names.size() == 1:
		filter_row.add_child(_lbl("🎛️ Pay the sound engineer more to unlock voice filters", 15, Color8(170, 170, 220)))
		selected_filter = "Normal"
		return
	if not names.has(selected_filter):
		selected_filter = "Normal"
	for n in names:
		var on: bool = n == selected_filter
		var b := _btn(n, GOLD if on else Color8(40, 50, 110), 44, 14, on)
		b.pressed.connect(func(): selected_filter = n; _refresh_filters())
		filter_row.add_child(b)


func _update_status() -> void:
	if is_recording:
		return
	if record_manager.recorded_sample == null:
		status.text = "🎤 Hold the red button and read the line out loud (pure voice, no effects)."
	else:
		status.text = "✅ Recorded %.1fs - play it back or SUBMIT." % record_manager.recorded_length


func _process(_d: float) -> void:
	var o: Dictionary = economy_manager.current_order
	patience.visible = not o.is_empty() and not o["calibration"]
	if patience.visible:
		var ratio: float = float(o["patience_left"]) / float(o["patience_max"])
		patience.value = ratio * 100.0
		(patience.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color8(60, 220, 110) if ratio > 0.5 else (Color8(255, 200, 40) if ratio > 0.25 else Color8(255, 60, 70))
	if is_recording:
		meter.value = record_manager.get_live_level() * 100.0
		record_btn.text = "🎙️ RECORDING %.1fs" % ((Time.get_ticks_msec() - t0) / 1000.0)
	else:
		meter.value = 0.0


func _unhandled_input(e: InputEvent) -> void:  # SPACE = record (handy on web / PC)
	if e is InputEventKey and e.keycode == KEY_SPACE and not e.echo:
		if e.pressed:
			_start_rec()
		else:
			_stop_rec()


# ============================================================ clients
func _show_new_client() -> void:
	var o: Dictionary = economy_manager.current_order
	if o.is_empty():
		return
	client_char.randomize_look(o["client"])
	client_char.enter()
	_refresh_bubble()
	_refresh_filters()
	_update_status()


func _refresh_bubble() -> void:
	var o: Dictionary = economy_manager.current_order
	if o.is_empty():
		return
	if o["calibration"]:
		bubble.text = "[b]🎤 VOICE CHECK[/b]\nSay this in your NORMAL voice:\n“%s”" % o["line"]
		return
	var extra := ""
	if o["filter"] != "":
		extra = "\n🎛️ Effect: [color=#f9f]%s[/color]%s" % [o["filter"], " (engineer does it)" if economy_manager.is_auto() else ""]
	bubble.text = "[b][color=#ffd23c]%s[/color][/b]\n“%s”\n[color=#7ff]%s[/color]%s\n💵 $%d   🎯 need %d+" % [o["client"], o["line"], PromptLibrary.tags_for(o["traits"]), extra, o["reward"], economy_manager.get_pass_mark()]


func _on_expired(_o: Dictionary) -> void:
	busy = true
	_stop_rec()
	client_char.react(false)
	_sfx("error")
	bubble.text = "😡 Too slow! I'm leaving!"
	await get_tree().create_timer(1.3).timeout
	client_char.leave()
	await get_tree().create_timer(0.6).timeout
	busy = false
	economy_manager.generate_order()


# ============================================================ recording / submit
func _start_rec() -> void:
	if busy or is_recording or shop.visible or economy_manager.current_order.is_empty():
		return
	is_recording = true
	t0 = Time.get_ticks_msec()
	record_manager.start_recording()
	_sfx("coin")


func _stop_rec() -> void:
	if not is_recording:
		return
	is_recording = false
	record_manager.stop_recording()
	record_btn.text = "🔴 HOLD TO RECORD"
	_update_status()


func _on_play() -> void:
	if record_manager.recorded_sample == null:
		_toast("🎙️ Record something first!")
		return
	var o: Dictionary = economy_manager.current_order
	var f := selected_filter
	if economy_manager.is_auto() and not o.is_empty() and o["filter"] != "":
		f = o["filter"]
	record_manager.play(f)


func _unlock() -> void:
	busy = false
	economy_manager.patience_paused = false
	_refresh_bubble()


func _on_submit() -> void:
	if busy or is_recording or economy_manager.current_order.is_empty():
		return
	if record_manager.recorded_sample == null:
		_toast("🎙️ Record your voice first!")
		return
	busy = true
	economy_manager.patience_paused = true
	bubble.text = "🤔 [i]Listening carefully...[/i]"
	var m: Dictionary = await record_manager.analyze()
	var res: Dictionary = economy_manager.evaluate(m, selected_filter)
	match res["result"]:
		"invalid":
			_sfx("error")
			_toast(REASONS.get(res["reason"], "Try again!"))
			_unlock()
		"wrong_filter":
			_sfx("error")
			client_char.react(false)
			_toast("Wrong effect! The client wants: %s" % res["need"])
			_unlock()
		"calibrated":
			_sfx("win")
			client_char.react(true)
			_toast("✅ Voice saved! Now let's work.")
			record_manager.clear_recording()
			await get_tree().create_timer(1.4).timeout
			client_char.leave()
			await get_tree().create_timer(0.6).timeout
			_update_status()
			_unlock()
			economy_manager.generate_order()
		"fail":
			_sfx("error")
			client_char.react(false)
			await _show_judge(res)
			record_manager.clear_recording()
			_update_status()
			_unlock()
		"success":
			_sfx("win")
			if _rank_up_pending:
				_rank_up_pending = false
				_buzz_long()
			else:
				_buzz_short()
			client_char.react(true)
			await _show_judge(res)
			client_char.leave()
			record_manager.clear_recording()
			_update_status()
			await get_tree().create_timer(0.7).timeout
			_unlock()
			economy_manager.generate_order()
		_:
			_unlock()


func _show_judge(res: Dictionary) -> void:
	var win: bool = res["result"] == "success"
	var txt := ("🎉 CLIENT LOVED IT!" if win else "😕 NOT QUITE...") + "\n\nSCORE %d   (need %d)" % [int(res["score"]), int(res["pass"])]
	if win:
		txt += "   " + "⭐".repeat(int(res["stars"]))
	txt += "\n"
	for r in res["rows"]:
		var n := int(round(float(r["score"]) * 10.0))
		txt += "\n%s %s   %s%s  %d%%" % [r["icon"], r["name"], "█".repeat(n), "░".repeat(10 - n), int(float(r["score"]) * 100.0)]
	txt += "\n\n💡 " + String(res["hint"]) + "\n" + String(res["debug"])
	if win:
		txt += "\n\n💰 +$%d    ⭐ +%d REP" % [res["reward"], res["rep"]]
	judge_label.text = txt
	judge_btn.text = "NEXT CLIENT ▶" if win else "TRY AGAIN 🎙️"
	judge.visible = true
	await judge_closed


# ============================================================ toast + generated sounds
func _toast(text: String) -> void:
	var l := _lbl(text, 26, Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(get_viewport_rect().size.x, 40)
	l.position = Vector2(0, get_viewport_rect().size.y * 0.45)
	root.add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 1.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.9)
	tw.chain().tween_callback(l.queue_free)


func _build_sfx() -> void:
	for k in {"coin": [[988.0, 1319.0], 0.08], "win": [[523.0, 659.0, 784.0, 1047.0], 0.1], "error": [[220.0, 160.0], 0.14]}.keys():
		pass
	var defs := {"coin": [[988.0, 1319.0], 0.08], "win": [[523.0, 659.0, 784.0, 1047.0], 0.1], "error": [[220.0, 160.0], 0.14]}
	for k in defs.keys():
		var p := AudioStreamPlayer.new()
		p.stream = _tone(defs[k][0], defs[k][1])
		p.volume_db = -6.0
		add_child(p)
		sfx[k] = p


func _sfx(n: String) -> void:
	if sfx.has(n):
		sfx[n].play()


func _tone(freqs: Array, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var per := int(rate * dur)
	var data := PackedByteArray()
	data.resize(per * freqs.size() * 2)
	var idx := 0
	for f in freqs:
		var ph := 0.0
		for i in per:
			ph += TAU * float(f) / rate
			data.encode_s16(idx * 2, int(clampf(sin(ph) * (1.0 - float(i) / per) * 0.35, -1.0, 1.0) * 32767.0))
			idx += 1
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w


# ============================================================ vibration
func _buzz_short() -> void:  # quick double tap, Duolingo-style
	Input.vibrate_handheld(70)
	await get_tree().create_timer(0.13).timeout
	Input.vibrate_handheld(70)


func _buzz_long() -> void:  # rank up
	Input.vibrate_handheld(700)


func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED) and economy_manager:
		economy_manager.save_game()
