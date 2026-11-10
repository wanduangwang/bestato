extends Node2D

enum Kind { CHASER, RUNNER, SHOOTER, TANK, CHARGER, NEST, ELITE, BOSS, TREE }
enum Mode { MOVE, WINDUP, DASH }
enum Attack { NONE, AIMED, RING, HATCH }

const TINTS := [Color("#b88cca"), Color("#e38eb9"), Color("#a092d9"), Color("#8b75ad"),
	Color("#ce82c2"), Color("#86a8a2"), Color("#d577a8"), Color("#ad679e"), Color("#7fa456")]
const RADII := [12.0, 9.0, 13.0, 19.0, 14.0, 17.0, 25.0, 33.0, 21.0]
const SPEEDS := [79.0, 151.0, 73.0, 53.0, 91.0, 32.0, 104.0, 76.0, 0.0]
const BASE_HP := [3, 4, 8, 24, 12, 22, 370, 2090, 6]
const HP_PER_WAVE := [1.7, 1.45, 2.0, 5.7, 3.0, 4.0, 19.0, 65.0, 1.4]
const BASE_DAMAGE := [2, 2, 3, 4, 4, 2, 7, 10, 0]
const MATERIALS := [1, 1, 2, 3, 2, 3, 20, 40, 0]
const INK := Color("#342735")

var kind: int = Kind.CHASER
var hp := 3
var max_hp := 3
var radius := 12.0
var speed := 80.0
var contact_damage := 2
var reward := 1
var mode: int = Mode.MOVE
var aim := Vector2.RIGHT
var is_replica := false
var goal_position := Vector2.ZERO
var hit_flash := 0.0
var burn_ticks := 0
var burn_amount := 0
var burn_clock := 0.0
var burn_owner := 0
var _ability := 0.0
var _use_ring := true
var _animation := 0.0


func configure(enemy_kind: int, wave: int, team: int, strength := 1.0) -> void:
	kind = enemy_kind
	radius = RADII[kind]
	speed = SPEEDS[kind] * (1.0 + mini(wave - 1, 14) * 0.018)
	var scaling := (1.0 + (team - 1) * 0.30) * strength
	var late_health := pow(maxi(0, wave - 8), 2.0) * 0.63 if kind != Kind.TREE else 0.0
	hp = roundi((BASE_HP[kind] + (wave - 1) * HP_PER_WAVE[kind] + late_health) * scaling)
	max_hp = hp
	contact_damage = roundi((BASE_DAMAGE[kind] + (wave - 1) * 0.43) * (1.0 + (team - 1) * 0.08) * strength)
	if kind == Kind.TREE:
		contact_damage = 0
	reward = MATERIALS[kind]
	_ability = randf_range(0.85, 2.0)


func simulate(target: Vector2, delta: float, bounds: Rect2) -> int:
	if kind == Kind.TREE:
		return Attack.NONE
	_ability -= delta
	var distance := position.distance_to(target)
	if mode == Mode.DASH:
		position = (position + aim * (speed + 240.0) * delta).clamp(bounds.position, bounds.end)
		if _ability <= 0.0:
			mode = Mode.MOVE
			_ability = 1.2
		return Attack.NONE
	if mode == Mode.WINDUP:
		if _ability > 0.0:
			return Attack.NONE
		if kind == Kind.CHARGER or ((kind == Kind.ELITE or kind == Kind.BOSS) and not _use_ring):
			mode = Mode.DASH
			_ability = 0.50 if kind == Kind.BOSS else 0.39
			_use_ring = true
			return Attack.NONE
		mode = Mode.MOVE
		_ability = randf_range(1.20, 1.95)
		if kind == Kind.BOSS and hp < max_hp * 0.5:
			_ability *= 0.68
		_use_ring = false
		return Attack.AIMED if kind == Kind.SHOOTER else Attack.RING

	aim = position.direction_to(target)
	if kind == Kind.SHOOTER:
		if distance > 212.0:
			position += aim * speed * delta
		elif distance < 138.0:
			position -= aim * speed * delta
		if _ability <= 0.0 and distance < 385.0:
			_wind_up(0.49)
	elif kind in [Kind.CHARGER, Kind.ELITE, Kind.BOSS]:
		position += aim * speed * delta
		if _ability <= 0.0 and distance < (600.0 if kind == Kind.BOSS else 390.0):
			_wind_up(0.67 if kind == Kind.CHARGER else 0.58)
	else:
		position = position.move_toward(target, speed * delta)
		if kind == Kind.NEST and _ability <= 0.0:
			_ability = 3.2
			return Attack.HATCH
	position = position.clamp(bounds.position, bounds.end)
	return Attack.NONE


func _wind_up(seconds: float) -> void:
	mode = Mode.WINDUP
	_ability = seconds


func hit(amount: int) -> void:
	hp -= amount
	hit_flash = 0.10


func ignite(amount: int, owner_id: int) -> void:
	if amount >= burn_amount or burn_ticks == 0:
		burn_amount = amount
		burn_owner = owner_id
	if burn_ticks == 0:
		burn_clock = 0.36
	burn_ticks = 3


func _process(delta: float) -> void:
	if is_replica:
		position = position.lerp(goal_position, 1.0 - exp(-20.0 * delta))
	hit_flash = maxf(0.0, hit_flash - delta)
	_animation += delta
	queue_redraw()


func _draw() -> void:
	if kind == Kind.TREE:
		_draw_tree()
		return
	var tint: Color = TINTS[kind]
	if hit_flash > 0.0:
		tint = tint.lightened(0.7)
	draw_set_transform(Vector2(1, radius * 0.72), 0.0, Vector2(1.05, 0.43))
	draw_circle(Vector2.ZERO, radius, Color(0.16, 0.10, 0.17, 0.39))
	draw_set_transform(Vector2.ZERO)
	if mode == Mode.WINDUP:
		var danger := Color(1.0, 0.34, 0.28, 0.74)
		draw_arc(Vector2.ZERO, radius + 5, 0.0, TAU, 24, danger, 2.4, true)
		if kind != Kind.BOSS and kind != Kind.ELITE:
			draw_line(aim * radius, aim * (85.0 if kind == Kind.CHARGER else 57.0), danger, 2.0, true)
	for side: float in [-1.0, 1.0]:
		var foot := Vector2(side * radius * 0.55, radius * 0.77 + sin(_animation * 17.0 + side) * 1.5)
		draw_circle(foot, radius * 0.38, INK, true, -1.0, true)
	if kind in [Kind.TANK, Kind.CHARGER, Kind.ELITE, Kind.BOSS]:
		for side: float in [-1.0, 1.0]:
			var horn := Vector2(radius * 0.72 * side, -radius * 0.57)
			draw_line(horn, horn + Vector2(side * 7.0, -10.0), INK, radius * 0.36, true)
	draw_circle(Vector2.ZERO, radius + 2, INK, true, -1.0, true)
	draw_circle(Vector2.ZERO, radius, tint, true, -1.0, true)
	draw_arc(Vector2(0, 1), radius * 0.75, 3.65, 5.25, 10, tint.lightened(0.34), 1.8, true)
	for side: float in [-1.0, 1.0]:
		var eye := Vector2(radius * 0.36 * side, -radius * 0.14) + aim * 2.0
		draw_circle(eye, radius * 0.19 + 0.8, Color("#ffe7ce"), true, -1.0, true)
		draw_circle(eye + aim * 1.2, radius * 0.115 + 0.4, INK)
	draw_line(Vector2(-radius * 0.23, radius * 0.38), Vector2(radius * 0.23, radius * 0.34),
			INK, 2.0, true)
	if kind == Kind.SHOOTER:
		draw_circle(aim * (radius * 0.83), 4.2, Color("#f28d9d"))
	if hp < max_hp or kind in [Kind.ELITE, Kind.BOSS]:
		_draw_health()


func _draw_health() -> void:
	draw_rect(Rect2(-radius, -radius - 11, radius * 2, 5), INK)
	draw_rect(Rect2(-radius + 1, -radius - 10, (radius * 2 - 2) * hp / maxi(1, max_hp), 3),
			Color("#ff998b"))


func _draw_tree() -> void:
	draw_line(Vector2(0, 17), Vector2(1, -8), Color("#573c37"), 10.0, true)
	for point: Vector2 in [Vector2(-9, -6), Vector2(9, -7), Vector2(0, -15)]:
		draw_circle(point, 13.0, INK, true, -1.0, true)
		var tint := Color("#c7da91") if hit_flash > 0.0 else TINTS[Kind.TREE]
		draw_circle(point, 10.6, tint, true, -1.0, true)
	draw_circle(Vector2(-9, -9), 2.7, Color("#f2b96e"))
	draw_circle(Vector2(8, -11), 2.7, Color("#f2b96e"))
