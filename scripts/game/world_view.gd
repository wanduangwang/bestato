extends Node2D

enum Mark { MATERIAL, FRUIT, CRATE, SPAWN, SHOT, HOSTILE, BLAST }

const STRIDE := 6
const INK := Color("#38272d")

var _frame := PackedFloat32Array()
var _age := 0.0
var _clock := 0.0
var _replica := false
var _notices: Array[Dictionary] = []


func update_frame(frame: PackedFloat32Array, replica := false) -> void:
	_frame = frame
	_age = 0.0
	_replica = replica


func notice(point: Vector2, value: String, tint: Color, bold := false) -> void:
	if _notices.size() >= 44:
		_notices.pop_front()
	_notices.append({"point": point, "label": value, "tint": tint, "life": 0.55,
		"size": 20 if bold else 15})


func clear_notices() -> void:
	_notices.clear()


func _process(delta: float) -> void:
	_clock += delta
	_age += delta
	for i in range(_notices.size() - 1, -1, -1):
		_notices[i]["life"] -= delta
		if _notices[i]["life"] <= 0.0:
			_notices.remove_at(i)
	queue_redraw()


func _draw() -> void:
	for i in range(0, _frame.size(), STRIDE):
		var mark := int(_frame[i])
		var point := Vector2(_frame[i + 1], _frame[i + 2])
		var info := _frame[i + 3]
		match mark:
			Mark.MATERIAL, Mark.FRUIT, Mark.CRATE:
				_draw_pickup(point, mark, info)
			Mark.SPAWN:
				_draw_warning(point, maxf(0.0, info - _age))
			Mark.SHOT, Mark.HOSTILE:
				var velocity := Vector2(info, _frame[i + 4])
				if _replica:
					point += velocity * minf(_age, 0.075)
				_draw_bolt(point, mark, velocity, int(_frame[i + 5]))
			Mark.BLAST:
				var color := Color(1.0, 0.70, 0.36, _frame[i + 4] * 2.3)
				draw_arc(point, info * (1.0 - _frame[i + 4]), 0.0, TAU, 24, color, 4.0, true)
	var font := Settings.ui_font()
	for item in _notices:
		var point: Vector2 = item["point"] + Vector2(0, -20.0 - (0.55 - item["life"]) * 45.0)
		var tint: Color = item["tint"]
		tint.a = clampf(item["life"] * 4.0, 0.0, 1.0)
		var label := tr(item["label"])
		var points: int = item["size"]
		point.x -= font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x * 0.5
		draw_string_outline(font, point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, points, 4, INK)
		draw_string(font, point, label, HORIZONTAL_ALIGNMENT_LEFT, -1, points, tint)


func _draw_pickup(point: Vector2, mark: int, amount: float) -> void:
	var lift := sin(_clock * 6.0 + point.x * 0.07) * 2.1
	draw_line(point + Vector2(-4, 4), point + Vector2(4, 4), Color(0.18, 0.11, 0.14, 0.38), 3.0, true)
	point.y += lift
	match mark:
		Mark.MATERIAL:
			var size := 5.8 + minf(2.5, amount * 0.47)
			var shape := PackedVector2Array([point + Vector2(-size, 1), point + Vector2(-size * 0.4, -size),
				point + Vector2(size * 0.6, -size * 0.73), point + Vector2(size, 1),
				point + Vector2(0, size), point + Vector2(-size, 1)])
			draw_colored_polygon(shape, Color("#b6e486") if amount < 2 else Color("#ddf49c"))
			draw_polyline(shape, Color("#4a5f43"), 1.7, true)
			draw_line(point + Vector2(-3, 0), point + Vector2(1, -3), Color("#effac7"), 1.4, true)
		Mark.FRUIT:
			draw_circle(point, 7.6, INK, true, -1.0, true)
			draw_circle(point, 6.0, Color("#f3ad75"), true, -1.0, true)
			draw_line(point + Vector2(0, -5), point + Vector2(4, -9), Color("#b6dd7b"), 2.6, true)
		Mark.CRATE:
			draw_rect(Rect2(point - Vector2(10, 8), Vector2(20, 17)), INK)
			draw_rect(Rect2(point - Vector2(8, 6), Vector2(16, 13)), Color("#f4cb86"))
			draw_line(point + Vector2(-6, 6), point + Vector2(6, -5), Color("#9e6d4b"), 2.8, true)


func _draw_warning(point: Vector2, time_left: float) -> void:
	var tint := Color(1.0, 0.35, 0.36, 0.65 + sin(_clock * 22.0) * 0.24)
	var size := 5.0 + time_left * 8.0
	draw_arc(point, size + 5.0, 0.0, TAU, 18, tint, 1.5, true)
	draw_line(point + Vector2(-size, -size), point + Vector2(size, size), tint, 2.4, true)
	draw_line(point + Vector2(size, -size), point + Vector2(-size, size), tint, 2.4, true)


func _draw_bolt(point: Vector2, mark: int, velocity: Vector2, style: int) -> void:
	if mark == Mark.HOSTILE:
		draw_circle(point, 7.1, INK, true, -1.0, true)
		draw_circle(point, 5.3, Color("#ff7b86"), true, -1.0, true)
		draw_circle(point + Vector2(-1, -1), 2.3, Color("#ffe3ad"))
		return
	var tint := Color("#fff0b0")
	if style == 1:
		tint = Color("#ffad68")
	elif style == 2:
		tint = Color("#ffa87f")
	var length := 11.0 if style != 2 else 17.0
	var tail := point - velocity.normalized() * length
	draw_line(tail, point, INK, 4.6, true)
	draw_line(tail, point, tint, 2.7, true)
