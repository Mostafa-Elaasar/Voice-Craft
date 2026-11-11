class_name ClientCharacter
extends Node2D
## Cartoon client drawn entirely in code. No art assets needed.
## Usage: see the patch notes for main.gd.

enum Mood { NORMAL, HAPPY, ANGRY }

var mood: Mood = Mood.NORMAL
var skin_color: Color = Color8(255, 220, 177)
var shirt_color: Color = Color8(60, 120, 255)
var hair_color: Color = Color8(40, 25, 15)
var hat_type: int = 0  # 0 none, 1 cap, 2 top hat, 3 beanie

var _t: float = 0.0
var _target_x: float = 0.0
var _tween: Tween

const SKINS := [Color8(255, 220, 177), Color8(224, 172, 105), Color8(141, 85, 36), Color8(198, 134, 66)]
const SHIRTS := [Color8(60, 120, 255), Color8(255, 90, 90), Color8(80, 200, 120), Color8(255, 190, 40), Color8(180, 90, 255)]
const HAIRS := [Color8(40, 25, 15), Color8(120, 70, 20), Color8(230, 200, 90), Color8(20, 20, 20), Color8(200, 60, 60)]


func _ready() -> void:
	_target_x = position.x


func randomize_look(seed_text: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()  # different look every visit, even for the same client name
	skin_color = SKINS[rng.randi() % SKINS.size()]
	shirt_color = SHIRTS[rng.randi() % SHIRTS.size()]
	hair_color = HAIRS[rng.randi() % HAIRS.size()]
	hat_type = rng.randi() % 4
	mood = Mood.NORMAL


func enter() -> void:
	## Walk in from the left side of the screen.
	if _tween:
		_tween.kill()
	position.x = _target_x - 300.0
	scale = Vector2.ONE
	mood = Mood.NORMAL
	_tween = create_tween()
	_tween.tween_property(self, "position:x", _target_x, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func react(happy: bool) -> void:
	if _tween:
		_tween.kill()
	mood = Mood.HAPPY if happy else Mood.ANGRY
	_tween = create_tween()
	if happy:
		# Happy jump
		_tween.tween_property(self, "position:y", position.y - 30.0, 0.15)
		_tween.tween_property(self, "position:y", position.y, 0.15)
	else:
		# Angry shake
		for i in 4:
			_tween.tween_property(self, "position:x", _target_x + 10.0, 0.04)
			_tween.tween_property(self, "position:x", _target_x - 10.0, 0.04)
		_tween.tween_property(self, "position:x", _target_x, 0.04)


func leave() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position:x", _target_x + 400.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var bob := sin(_t * 5.0) * 3.0
	var outline := Color8(20, 15, 30)

	# Body
	draw_rect(Rect2(-32, 38 + bob, 64, 50), shirt_color)
	draw_rect(Rect2(-32, 38 + bob, 64, 50), outline, false, 3.0)
	# Head
	draw_circle(Vector2(0, bob), 46, outline)
	draw_circle(Vector2(0, bob), 43, skin_color)

	# Hair / hat
	match hat_type:
		0:
			draw_arc(Vector2(0, bob), 43, PI * 1.05, PI * 1.95, 20, hair_color, 10.0)
		1:  # cap
			draw_rect(Rect2(-40, -48 + bob, 80, 22), Color8(220, 50, 50))
			draw_rect(Rect2(-40, -30 + bob, 80, 8), Color8(160, 30, 30))
			draw_rect(Rect2(10, -30 + bob, 45, 8), Color8(160, 30, 30))
		2:  # top hat
			draw_rect(Rect2(-45, -50 + bob, 90, 8), Color8(30, 30, 30))
			draw_rect(Rect2(-28, -95 + bob, 56, 48), Color8(30, 30, 30))
			draw_rect(Rect2(-28, -62 + bob, 56, 8), Color8(200, 50, 80))
		3:  # beanie
			draw_circle(Vector2(0, -30 + bob), 36, Color8(255, 150, 50))
			draw_rect(Rect2(-40, -34 + bob, 80, 14), Color8(230, 120, 30))
			draw_circle(Vector2(0, -68 + bob), 9, Color.WHITE)

	# Eyes (blink every ~3 seconds)
	var blinking := fmod(_t, 3.0) < 0.12
	for ex in [-16.0, 16.0]:
		var ep := Vector2(ex, -6 + bob)
		if blinking:
			draw_line(ep + Vector2(-8, 0), ep + Vector2(8, 0), outline, 3.0)
		else:
			draw_circle(ep, 10, Color.WHITE)
			draw_circle(ep + Vector2(sin(_t * 1.5) * 2.0, 0), 5, outline)

	# Eyebrows + mouth by mood
	match mood:
		Mood.NORMAL:
			draw_line(Vector2(-12, 22 + bob), Vector2(12, 22 + bob), outline, 3.0)
		Mood.HAPPY:
			draw_arc(Vector2(0, 14 + bob), 18, 0.1, PI - 0.1, 16, outline, 4.0)
			draw_circle(Vector2(-28, 12 + bob), 7, Color(1, 0.4, 0.5, 0.5))
			draw_circle(Vector2(28, 12 + bob), 7, Color(1, 0.4, 0.5, 0.5))
		Mood.ANGRY:
			draw_arc(Vector2(0, 34 + bob), 16, PI + 0.2, TAU - 0.2, 16, outline, 4.0)
			draw_line(Vector2(-28, -22 + bob), Vector2(-6, -14 + bob), outline, 4.0)
			draw_line(Vector2(28, -22 + bob), Vector2(6, -14 + bob), outline, 4.0)
