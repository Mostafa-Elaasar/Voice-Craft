extends Node

signal economy_updated
signal order_changed(order: Dictionary)
signal order_expired(order: Dictionary)
signal rank_up(rank_name: String)

const SAVE_PATH := "user://voicecraft_save.cfg"
const FILTERS := ["Chipmunk", "Monster", "Retro 8-Bit", "Telephonic"]
const AUTO_LEVEL := 6  # engineer salary level where he applies filters himself
const RANKS := [[0, "Garage Newbie"], [50, "Bedroom Producer"], [150, "Indie Studio"], [400, "Pro Studio"], [900, "Hit Factory"], [2000, "Voice Legend"]]
const UPGRADES := {
	"engineer": {"title": "Sound Engineer Salary", "icon": "💼", "desc": "+$3/sec. Lv1-4 unlock filters, Lv6 = he applies them for you", "base_cost": 100, "growth": 1.6, "max": 10},
	"mic": {"title": "Pro Microphone", "icon": "🎙️", "desc": "+15% payout", "base_cost": 150, "growth": 1.8, "max": 10},
	"coffee": {"title": "Coffee Machine", "icon": "☕", "desc": "Clients are 10% more patient", "base_cost": 120, "growth": 1.7, "max": 10},
	"decor": {"title": "Cool Decor", "icon": "🪩", "desc": "+20% reputation", "base_cost": 200, "growth": 1.9, "max": 10},
}

var cash: int = 50
var reputation: int = 0
var orders_done: int = 0
var levels: Dictionary = {"engineer": 0, "mic": 0, "coffee": 0, "decor": 0}
var baseline: Dictionary = {}
var current_order: Dictionary = {}
var patience_paused: bool = false
var passive_income_rate: float = 0.0
var _seen: Array = []
var _ticks: int = 0


func _ready() -> void:
	load_game()
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_on_tick)
	add_child(t)
	generate_order()


func _process(delta: float) -> void:
	if current_order.is_empty() or patience_paused or current_order["calibration"]:
		return
	current_order["patience_left"] -= delta
	if current_order["patience_left"] <= 0.0:
		var o := current_order
		current_order = {}
		reputation = maxi(0, reputation - 5)
		order_expired.emit(o)
		economy_updated.emit()


func _on_tick() -> void:
	if passive_income_rate > 0.0:
		add_cash(int(passive_income_rate))
	_ticks += 1
	if _ticks % 10 == 0:
		save_game()


func add_cash(n: int) -> void:
	cash += n
	economy_updated.emit()


# ------------------------------------------------------------ engineer / filters
func unlocked_filters() -> Array:
	return FILTERS.slice(0, mini(get_level("engineer"), FILTERS.size()))


func is_auto() -> bool:
	return get_level("engineer") >= AUTO_LEVEL


# ------------------------------------------------------------ ranks
func get_rank_index() -> int:
	var idx := 0
	for i in RANKS.size():
		if reputation >= int(RANKS[i][0]):
			idx = i
	return idx


func get_rank_name() -> String:
	return RANKS[get_rank_index()][1]


# ------------------------------------------------------------ orders
func start_calibration() -> void:
	current_order = _order_base(true, "Studio Manager", "Hello! Welcome to my voice studio, nice to meet you.", {}, 0)
	order_changed.emit(current_order)


func _order_base(calib: bool, client: String, line: String, traits: Dictionary, tier: int) -> Dictionary:
	var patience := maxf(30.0, 70.0 - get_rank_index() * 4.0) * (1.0 + 0.1 * get_level("coffee"))
	return {"calibration": calib, "client": client, "line": line, "traits": traits, "tier": tier, "filter": "",
		"syll": PromptLibrary.syllables(line), "reward": 0, "attempts": 0, "patience_max": patience, "patience_left": patience}


func generate_order() -> void:
	if baseline.is_empty():
		start_calibration()
		return
	var max_tier := clampi(get_rank_index() + (1 if orders_done >= 3 else 0), 0, 3)
	var p: Array = PromptLibrary.PROMPTS[_pick_prompt(max_tier)]
	var o := _order_base(false, p[2], p[3], p[4], int(p[0]))
	o["reward"] = int(40 + int(p[0]) * 35 + reputation * 0.3)
	var unlocked := unlocked_filters()
	if not unlocked.is_empty() and int(p[0]) >= 1 and randf() < 0.5:
		o["filter"] = unlocked.pick_random()
		o["reward"] = int(o["reward"] * 1.3)
	current_order = o
	order_changed.emit(o)


func _pick_prompt(max_tier: int) -> int:
	var pool: Array = []
	for i in PromptLibrary.PROMPTS.size():
		if int(PromptLibrary.PROMPTS[i][0]) <= max_tier and not _seen.has(i):
			pool.append(i)
	if pool.is_empty():
		_seen.clear()
		return _pick_prompt(max_tier)
	var top: Array = pool.filter(func(i): return int(PromptLibrary.PROMPTS[i][0]) == max_tier)
	var pick: int = top.pick_random() if (not top.is_empty() and randf() < 0.5) else pool.pick_random()
	_seen.append(pick)
	return pick


func get_pass_mark() -> int:
	return 45 + 2 * get_rank_index()


func _penalty(frac: float) -> void:
	current_order["patience_left"] = maxf(1.0, float(current_order["patience_left"]) - float(current_order["patience_max"]) * frac)


## result: none | invalid | calibrated | wrong_filter | fail | success
func evaluate(m: Dictionary, used_filter: String) -> Dictionary:
	if current_order.is_empty():
		return {"result": "none"}
	var o := current_order
	if not m.get("ok", false):
		if not o["calibration"]:
			_penalty(0.06)
		return {"result": "invalid", "reason": m.get("reason", "silence")}
	var syll: int = o["syll"]
	var span: float = m["span"]

	if o["calibration"]:
		if span < 0.8:
			return {"result": "invalid", "reason": "too_short"}
		baseline = {"pitch_hz": m["pitch_hz"], "level_db": m["level_db"], "rate": clampf(float(syll) / span, 1.5, 9.0)}
		current_order = {}
		add_cash(50)
		save_game()
		return {"result": "calibrated"}

	if span < float(syll) / float(baseline["rate"]) * 0.4:
		_penalty(0.06)
		return {"result": "invalid", "reason": "too_short"}

	var need: String = o["filter"]
	if need != "" and not is_auto() and used_filter != need:
		_penalty(0.15)
		return {"result": "wrong_filter", "need": need}

	var sc: Dictionary = VoiceAnalyzer.score(m, baseline, o["traits"], syll)
	var pass_mark := get_pass_mark()
	sc["pass"] = pass_mark
	o["attempts"] += 1
	var score: float = sc["score"]
	if score < pass_mark:
		_penalty(0.15)
		sc["result"] = "fail"
		return sc

	var stars := 1 + int(score >= pass_mark + 20) + int(score >= pass_mark + 38)
	var reward := int(float(o["reward"]) * [0.0, 0.8, 1.0, 1.3][stars] * (1.0 + 0.15 * get_level("mic")) * (1.0 - 0.1 * minf(float(o["attempts"] - 1), 3.0)))
	var rep := int(round(stars * 4 * (1.0 + 0.2 * get_level("decor"))))
	current_order = {}
	orders_done += 1
	var old_rank := get_rank_index()
	reputation += rep
	add_cash(reward)
	if get_rank_index() > old_rank:
		rank_up.emit(get_rank_name())
	save_game()
	sc["result"] = "success"
	sc["stars"] = stars
	sc["reward"] = reward
	sc["rep"] = rep
	return sc


# ------------------------------------------------------------ upgrades
func get_upgrade_ids() -> Array:
	return UPGRADES.keys()


func get_upgrade_info(id: String) -> Dictionary:
	return UPGRADES[id]


func get_level(id: String) -> int:
	return int(levels[id])


func is_maxed(id: String) -> bool:
	return get_level(id) >= int(UPGRADES[id]["max"])


func get_upgrade_cost(id: String) -> int:
	return int(float(UPGRADES[id]["base_cost"]) * pow(float(UPGRADES[id]["growth"]), float(get_level(id))))


func buy_upgrade(id: String) -> bool:
	var cost := get_upgrade_cost(id)
	if is_maxed(id) or cash < cost:
		return false
	cash -= cost
	levels[id] = get_level(id) + 1
	passive_income_rate = get_level("engineer") * 3.0
	economy_updated.emit()
	save_game()
	return true


# ------------------------------------------------------------ saving
func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "cash", cash)
	cfg.set_value("game", "reputation", reputation)
	cfg.set_value("game", "orders_done", orders_done)
	for id in levels.keys():
		cfg.set_value("upgrades", id, levels[id])
	for k in baseline.keys():
		cfg.set_value("baseline", k, baseline[k])
	cfg.save(SAVE_PATH)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		cash = int(cfg.get_value("game", "cash", 50))
		reputation = int(cfg.get_value("game", "reputation", 0))
		orders_done = int(cfg.get_value("game", "orders_done", 0))
		for id in levels.keys():
			levels[id] = int(cfg.get_value("upgrades", id, 0))
		if cfg.has_section("baseline"):
			for k in cfg.get_section_keys("baseline"):
				baseline[k] = float(cfg.get_value("baseline", k))
	passive_income_rate = get_level("engineer") * 3.0
