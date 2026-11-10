extends Node2D

const Catalog = preload("res://scripts/game/catalog.gd")
const Build = preload("res://scripts/game/build.gd")
const Stat = Catalog.Stat
const SLOT_COUNT := Catalog.SLOT_COUNT
const SPEED := 218.0
const BODY_RADIUS := 15.0
const COLORS := [Color("#f6d08b"), Color("#9de0ad"), Color("#98c9fb"), Color("#eab5ef")]
const INK := Color("#30252e")
const SKIN := [Color("#e9b871"), Color("#f5c981"), Color("#d3a16b"), Color("#e7c18d")]

static var _body := PackedVector2Array([Vector2(-15, 5), Vector2(-15, -4), Vector2(-12, -12),
	Vector2(-5, -17), Vector2(5, -18), Vector2(12, -13), Vector2(16, -5), Vector2(16, 5),
	Vector2(12, 12), Vector2(4, 15), Vector2(-6, 15), Vector2(-12, 11), Vector2(-15, 5)])

var build: Build
var peer_id := 1
var hp := 15
var max_hp := 15
var origin := 0
var level := 0
var facing := 1.0
var is_local := false
var is_replica := false
var goal_position := Vector2.ZERO
var hurt_flash := 0.0
var invulnerable := 0.0
var weapon_codes := PackedInt32Array()
var weapon_angles := PackedFloat32Array()
var shot_numbers := PackedInt32Array()
var cooldowns := PackedFloat32Array()
var flashes := PackedFloat32Array()
var _regen := 0.0
var _steal_delay := 0.0
var _last_position := Vector2.ZERO
var _gait := 0.0
var _moving := false


func _init() -> void:
	weapon_codes.resize(SLOT_COUNT)
	weapon_angles.resize(SLOT_COUNT)
	shot_numbers.resize(SLOT_COUNT)
	cooldowns.resize(SLOT_COUNT)
	flashes.resize(SLOT_COUNT)


func sync_build(refill := false) -> void:
	max_hp = build.stats[Stat.HP]
	hp = max_hp if refill else mini(hp, max_hp)
	level = build.level
	origin = build.origin
	for i in range(SLOT_COUNT):
		weapon_codes[i] = 0
		if i < build.weapons.size():
			var weapon := build.weapons[i]
			weapon_codes[i] = int(weapon["id"]) * 4 + int(weapon["tier"])
			if refill:
				weapon_angles[i] = slot_angle(i)
	if refill:
		cooldowns.fill(0.0)
		invulnerable = 0.65
		_regen = 0.0


func slot_angle(slot: int) -> float:
	return float(slot) * TAU / SLOT_COUNT - PI / 6.0


func mount_offset(slot: int) -> Vector2:
	var radial := Vector2.from_angle(slot_angle(slot))
	return Vector2(radial.x * 25.0, radial.y * 22.0)


func simulate(delta: float, direction: Vector2, bounds: Rect2) -> void:
	invulnerable = maxf(0.0, invulnerable - delta)
	_steal_delay = maxf(0.0, _steal_delay - delta)
	if hp == 0:
		return
	var speed_factor := 1.0 + build.stats[Stat.SPEED] / 100.0
	position = (position + direction * SPEED * speed_factor * delta).clamp(bounds.position, bounds.end)
	if absf(direction.x) > 0.02:
		facing = signf(direction.x)
	if hp < max_hp:
		_regen += maxf(0.0, build.stats[Stat.REGEN] * 0.20) * delta
		if _regen >= 1.0:
			var recovered := floori(_regen)
			heal(recovered)
			_regen -= recovered


func hurt(raw_damage: int) -> int:
	if invulnerable > 0.0 or hp <= 0:
		return 0
	if randf() * 100.0 < build.stats[Stat.DODGE]:
		invulnerable = 0.18
		return -1
	var armor: int = build.stats[Stat.ARMOR]
	var armor_factor := 1.0 - armor / (15.0 + absf(armor))
	var amount := maxi(1, roundi(raw_damage * armor_factor))
	hp = maxi(0, hp - amount)
	invulnerable = 0.43
	hurt_flash = 0.23
	return amount


func heal(amount: int) -> int:
	if hp <= 0:
		return 0
	var healed := mini(amount, max_hp - hp)
	hp += healed
	return healed


func try_life_steal() -> void:
	if _steal_delay <= 0.0 and hp < max_hp and randf() * 100.0 < build.stats[Stat.STEAL]:
		heal(1)
		_steal_delay = 0.10


func attack(slot: int, angle: float, interval: float) -> void:
	weapon_angles[slot] = angle
	shot_numbers[slot] += 1
	flashes[slot] = 0.13
	cooldowns[slot] = interval
	# Separate simultaneous copies so the first nearby target does not soak every shot.
	var weapon_id := (weapon_codes[slot] - 1) >> 2
	var copies: Array[int] = []
	for i in range(SLOT_COUNT):
		if cooldowns[i] <= 0.0 and weapon_codes[i] > 0 and ((weapon_codes[i] - 1) >> 2) == weapon_id:
			copies.append(i)
	for i in range(copies.size()):
		cooldowns[copies[i]] = minf(0.10, interval / (copies.size() + 1)) * (i + 1)


func replicate(frame: PackedFloat32Array, start: int) -> void:
	var next_hp := int(frame[start + 3])
	if next_hp < hp:
		hurt_flash = 0.23
	hp = next_hp
	max_hp = int(frame[start + 4])
	origin = int(frame[start + 5])
	level = int(frame[start + 6])
	facing = frame[start + 7]
	for i in range(SLOT_COUNT):
		var offset := start + 8 + i * 3
		weapon_codes[i] = int(frame[offset])
		weapon_angles[i] = frame[offset + 1]
		var next_shot := int(frame[offset + 2])
		if next_shot > 0 and next_shot != shot_numbers[i]:
			flashes[i] = 0.13
		shot_numbers[i] = next_shot


func _process(delta: float) -> void:
	if is_replica:
		position = position.lerp(goal_position, 1.0 - exp(-23.0 * delta))
	_moving = position.distance_squared_to(_last_position) > 0.24
	_last_position = position
	_gait += delta * 18.0
	hurt_flash = maxf(0.0, hurt_flash - delta)
	for i in range(SLOT_COUNT):
		flashes[i] = maxf(0.0, flashes[i] - delta)
	queue_redraw()


func _draw() -> void:
	var tint: Color = COLORS[(peer_id - 1) % COLORS.size()]
	if hp <= 0:
		draw_circle(Vector2(0, 6), 14.0, Color("#392c33"))
		draw_line(Vector2(-5, 1), Vector2(5, 11), tint.darkened(0.15), 2.5, true)
		draw_line(Vector2(5, 1), Vector2(-5, 11), tint.darkened(0.15), 2.5, true)
		return
	draw_set_transform(Vector2(2, 13), 0.0, Vector2(1.14, 0.46))
	draw_circle(Vector2.ZERO, 17.0, Color(0.13, 0.08, 0.12, 0.40), true, -1.0, true)
	draw_set_transform(Vector2.ZERO)
	if is_local:
		draw_arc(Vector2(0, 2), 23.0, 0.0, TAU, 30, tint, 1.7, true)

	for i in range(SLOT_COUNT):
		if weapon_codes[i] > 0:
			_draw_weapon(i)
	for side: float in [-1.0, 1.0]:
		var step := sin(_gait) * side * 3.1 if _moving else 0.0
		var foot := Vector2(7.0 * side, 13.5)
		draw_line(foot, foot + Vector2(step, 5.0), INK, 4.6, true)
	draw_colored_polygon(_body, Color("#fff1d7") if hurt_flash > 0.0 else SKIN[origin])
	draw_polyline(_body, INK, 3.2, true)
	draw_circle(Vector2(-9, -8), 2.0, Color("#ffe1aa"), true, -1.0, true)
	draw_circle(Vector2(-10, 6), 1.5, Color("#b87f55"))
	draw_circle(Vector2(10, 6), 1.8, Color("#b87f55"))
	for side in [-1.0, 1.0]:
		var eye := Vector2(side * 4.2 + facing * 1.8, -3.8)
		draw_circle(eye, 2.5, INK, true, -1.0, true)
		draw_circle(eye + Vector2(-0.5, -0.7), 0.75, Color("#fff6e0"))
	draw_arc(Vector2(1.5 * facing, 0), 4.2, 0.34, 2.8, 8, INK, 1.5, true)
	draw_line(Vector2(-12, 8), Vector2(12, 8), INK, 4.6, true)
	draw_line(Vector2(-11, 8), Vector2(11, 8), tint, 2.6, true)
	draw_rect(Rect2(-16, 30, 32, 5), Color("#30242e"))
	draw_rect(Rect2(-15, 31, 30.0 * hp / maxi(1, max_hp), 3), tint)


func _draw_weapon(slot: int) -> void:
	var code := weapon_codes[slot] - 1
	var weapon_id := code / 4
	var spec: Dictionary = Catalog.WEAPONS[weapon_id]
	var tint: Color = spec["ink"]
	if code % 4 > 0:
		tint = tint.lerp(Catalog.TIER_COLORS[code % 4], 0.57)
	var angle := weapon_angles[slot]
	var flash := flashes[slot] / 0.13
	var direction := Vector2.from_angle(angle)
	var mount := mount_offset(slot)
	var melee := spec.has("arc")
	draw_set_transform(mount + direction * flash * (14.0 if melee else -4.0), angle)
	_draw_gear(weapon_id, tint)
	if not melee and flash > 0.25:
		draw_line(Vector2(13, 0), Vector2(21, 0), Color("#ffe095"), 4.0, true)
	draw_set_transform(Vector2.ZERO)
	if melee and flash > 0.0:
		var slash := Color("#fff2cb")
		slash.a = flash * 0.82
		if spec.has("thrust"):
			draw_line(mount + direction * 22.0, mount + direction * (48.0 + 18.0 * (1.0 - flash)),
					slash, 3.1, true)
		else:
			var arc: float = spec["arc"]
			draw_arc(mount, 30.0 + 15.0 * (1.0 - flash), angle - arc, angle + arc, 12, slash, 3.1, true)


func _draw_gear(id: int, tint: Color) -> void:
	match id:
		4:
			draw_line(Vector2(-7, 0), Vector2(7, 0), INK, 7.0, true)
			draw_line(Vector2(-7, 0), Vector2(7, 0), tint, 3.9, true)
			for y in [-6.0, 6.0]:
				draw_line(Vector2(4, 0), Vector2(12, y), INK, 5.1, true)
				draw_line(Vector2(4, 0), Vector2(12, y), tint, 2.6, true)
			draw_line(Vector2(12, -6), Vector2(12, 6), Color("#fff1cf"), 1.5, true)
		5:
			draw_circle(Vector2(4, 0), 8.0, INK, true, -1.0, true)
			for angle in [0.0, PI / 2, PI, PI * 1.5]:
				var direction := Vector2.from_angle(angle)
				draw_line(Vector2(4, 0), Vector2(4, 0) + direction * 10.0, tint, 3.5, true)
		6, 7, 8, 10, 11:
			var tip := 17.0 if id == 7 else 12.0
			draw_line(Vector2(-7, 0), Vector2(tip, 0), INK, 7.7, true)
			draw_line(Vector2(-7, 0), Vector2(tip, 0), Color("#bd875e"), 4.2, true)
			if id == 11:
				draw_circle(Vector2(tip, 0), 5.2, Color("#f6a451"), true, -1.0, true)
				draw_circle(Vector2(tip, 0), 2.3, Color("#fff2b4"))
			elif id == 8:
				draw_line(Vector2(6, 0), Vector2(tip + 2, 0), tint, 7.6, true)
			else:
				var width := 6.7 if id == 10 else 4.3
				draw_colored_polygon(PackedVector2Array([Vector2(tip - 7, -width),
					Vector2(tip + 6, 0), Vector2(tip - 7, width)]), tint)
		9:
			draw_circle(Vector2(5, 0), 8.8, INK, true, -1.0, true)
			draw_circle(Vector2(5, 0), 6.4, tint, true, -1.0, true)
			draw_line(Vector2(-2, 0), Vector2(-9, 0), INK, 7.0, true)
		_:
			var length := 28.0 if id in [3, 12] else 21.0
			var height := 13.0 if id in [2, 12] else 10.0
			draw_rect(Rect2(-7, -height / 2.0, length, height), INK)
			draw_rect(Rect2(-5, -height / 2.0 + 2.0, length - 4.0, height - 4.0), tint)
			draw_rect(Rect2(-4, height / 2.0 - 1.0, 6, 6), INK)
			if id == 3:
				draw_rect(Rect2(1, -8, 10, 4), tint.darkened(0.29))
