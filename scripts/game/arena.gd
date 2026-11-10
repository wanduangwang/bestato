extends Node2D

const Catalog = preload("res://scripts/game/catalog.gd")
const Build = preload("res://scripts/game/build.gd")
const Player = preload("res://scripts/game/player.gd")
const Enemy = preload("res://scripts/game/enemy.gd")
const Waves = preload("res://scripts/game/waves.gd")
const WorldView = preload("res://scripts/game/world_view.gd")
const Sounds = preload("res://scripts/game/sounds.gd")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_SCENE = preload("res://scenes/enemy.tscn")

const Stat = Catalog.Stat
const Phase = Waves.Phase
const Mark = WorldView.Mark
const FIELD := Rect2(26, 83, 1068, 577)
const MOVE_BOUNDS := Rect2(51, 104, 1018, 524)
const FOE_BOUNDS := Rect2(45, 103, 1030, 537)
const MAX_FOES := 124
const MAX_PROJECTILES := 210
const MATERIAL_LIMIT := 50
const INPUT_INTERVAL := 1.0 / 30.0
const FRAME_INTERVAL := 1.0 / 15.0
const INPUT_TIMEOUT_MS := 450
const PLAYER_STRIDE := 8 + Catalog.SLOT_COUNT * 3
const ENEMY_STRIDE := 8
const CELL_SIZE := 100.0

class Projectile extends RefCounted:
	var point := Vector2.ZERO
	var velocity := Vector2.ZERO
	var distance := 0.0
	var damage := 0
	var owner_id := 0
	var critical := false
	var pierce := 0
	var bounce := 0
	var burn := 0
	var blast := 0.0
	var hit_ids: Dictionary = {}

var waves := Waves.new()
var players: Dictionary = {}
var enemies: Dictionary = {}
var local_profile: Dictionary = {}
var solo := false
var sounds: Sounds

var _view: WorldView
var _inputs: Dictionary = {}
var _foe_grid: Dictionary = {}
var _markers: Array[Dictionary] = []
var _drops: Array[Dictionary] = []
var _blasts: Array[Dictionary] = []
var _projectiles: Array[Projectile] = []
var _profile_queue: Dictionary = {}
var _revision := 0
var _enemy_id := 0
var _material_cursor := 0
var _input_timer := 0.0
var _frame_timer := 0.0


func _ready() -> void:
	sounds = Sounds.new()
	add_child(sounds)
	_view = WorldView.new()
	_view.z_index = 3
	add_child(_view)
	Network.hosted.connect(_prepare_host)
	Network.session_ended.connect(_reset_world)
	Network.input_received.connect(_record_input)
	Network.snapshot_received.connect(_receive_snapshot)
	Network.choice_received.connect(_apply_action)
	Network.profile_received.connect(_receive_profile)
	multiplayer.peer_connected.connect(_peer_joined)
	multiplayer.peer_disconnected.connect(_peer_left)


func open_solo() -> void:
	_reset_world()
	solo = true
	_add_player(1)
	_flush_profiles()


func _prepare_host() -> void:
	_reset_world()
	_add_player(1)
	_flush_profiles()


func back_to_menu() -> void:
	Network.leave_room()
	_reset_world()


func can_launch() -> bool:
	if waves.phase != Phase.LOBBY:
		return false
	return solo or (Network.state == Network.State.HOST and players.size() >= 2
		and waves.ready_count == players.size() - 1)


func launch() -> void:
	if can_launch():
		_begin_wave()
		_flush_profiles()


func cycle_danger() -> void:
	if _is_authority() and waves.phase == Phase.LOBBY:
		waves.danger = (waves.danger + 1) % Waves.DANGER_POWER.size()


func restart() -> void:
	if not _is_authority() or waves.phase not in [Phase.DEFEAT, Phase.VICTORY]:
		return
	var peers := players.keys()
	var was_solo := solo
	var danger := waves.danger
	_reset_world()
	solo = was_solo
	waves.danger = danger
	for peer_id: int in peers:
		_add_player(peer_id)
	_flush_profiles()


func act(action: int, slot := -1) -> void:
	if local_profile.is_empty():
		return
	var revision := int(local_profile["revision"])
	if _is_authority():
		_apply_action(1, action, slot, revision)
		_flush_profiles()
	elif Network.state == Network.State.CLIENT:
		Network.send_choice(action, slot, revision)


func _apply_action(peer_id: int, action: int, slot: int, revision: int) -> void:
	var player: Player = players.get(peer_id)
	if player == null or player.build == null or player.build.revision != revision:
		return
	var build := player.build
	var changed := false
	if waves.phase == Phase.LOBBY:
		match action:
			Build.Action.ORIGIN:
				if slot >= 0 and slot < Catalog.ORIGINS.size() and slot != build.origin:
					build.configure(slot, Catalog.ORIGINS[slot]["starter"])
					changed = true
			Build.Action.STARTER:
				if slot in Catalog.STARTERS and Catalog.allows_weapon(build.origin, slot) and slot != build.starter:
					build.configure(build.origin, slot)
					changed = true
			Build.Action.LOBBY_READY:
				if peer_id != 1:
					build.ready = not build.ready
					changed = true
		if changed:
			player.sync_build(true)
	elif waves.phase == Phase.SHOP:
		changed = build.apply_shop_action(action, slot)
		if changed:
			player.sync_build()
	if changed:
		_mark_profile(peer_id)
		_recount_ready()


func _mark_profile(peer_id: int) -> void:
	_revision += 1
	players[peer_id].build.revision = _revision
	_profile_queue[peer_id] = true


func _flush_profiles() -> void:
	for peer_id: int in _profile_queue.keys():
		var player: Player = players.get(peer_id)
		if player == null:
			_profile_queue.erase(peer_id)
			continue
		var data := player.build.profile(waves.phase == Phase.WAVE)
		data["phase"] = waves.phase
		data["wave"] = waves.number
		if peer_id == 1:
			_receive_profile(data)
			_profile_queue.erase(peer_id)
		elif Network.send_profile(peer_id, data):
			_profile_queue.erase(peer_id)


func _receive_profile(data: Dictionary) -> void:
	if int(data.get("revision", -1)) > int(local_profile.get("revision", -1)):
		if not local_profile.is_empty() and data["wave"] == local_profile["wave"]:
			if data["phase"] == Phase.WAVE and data["materials"] > local_profile["materials"]:
				sounds.play(Sounds.Cue.LOOT)
			elif data["phase"] == Phase.SHOP and local_profile["phase"] == Phase.SHOP:
				if data["materials"] < local_profile["materials"] or data["pending"] < local_profile["pending"]:
					sounds.play(Sounds.Cue.PURCHASE)
		local_profile = data


func _recount_ready() -> void:
	waves.ready_count = 0
	if waves.phase in [Phase.LOBBY, Phase.SHOP]:
		for player: Player in players.values():
			if player.build.ready:
				waves.ready_count += 1
		if waves.phase == Phase.SHOP and waves.ready_count == players.size():
			_begin_wave()


func _peer_joined(peer_id: int) -> void:
	if Network.state == Network.State.HOST:
		var player := _add_player(peer_id)
		if waves.phase == Phase.WAVE or waves.phase == Phase.SHOP:
			player.build.catch_up(waves.number)
			if waves.phase == Phase.SHOP:
				player.build.finish_wave(waves.number)
			player.sync_build(true)
			_mark_profile(peer_id)


func _peer_left(peer_id: int) -> void:
	if Network.state == Network.State.HOST and players.has(peer_id):
		players[peer_id].queue_free()
		players.erase(peer_id)
		_inputs.erase(peer_id)
		_profile_queue.erase(peer_id)
		_recount_ready()


func _reset_world() -> void:
	for player: Player in players.values():
		player.hide()
		player.queue_free()
	players.clear()
	_clear_combat()
	_profile_queue.clear()
	local_profile = {}
	solo = false
	waves = Waves.new()
	_material_cursor = 0
	_input_timer = 0.0
	_frame_timer = 0.0


func _clear_combat() -> void:
	for enemy: Enemy in enemies.values():
		enemy.hide()
		enemy.queue_free()
	enemies.clear()
	_inputs.clear()
	_foe_grid.clear()
	_markers.clear()
	_drops.clear()
	_projectiles.clear()
	_blasts.clear()
	_view.update_frame(PackedFloat32Array())
	_view.clear_notices()


func _add_player(peer_id: int) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.peer_id = peer_id
	player.is_local = solo or peer_id == multiplayer.get_unique_id()
	player.is_replica = not _is_authority()
	player.z_index = 2
	player.position = _player_spawn(peer_id)
	players[peer_id] = player
	add_child(player)
	if not player.is_replica:
		player.build = Build.new()
		player.build.configure(0, 0)
		player.sync_build(true)
		_mark_profile(peer_id)
	return player


func _player_spawn(peer_id: int) -> Vector2:
	var offset := Vector2.from_angle((peer_id - 1) * TAU / 4.0) * (62.0 if not solo else 0.0)
	return FIELD.get_center() + offset


func _begin_wave() -> void:
	_clear_combat()
	waves.begin()
	sounds.play(Sounds.Cue.DEPLOY)
	for player: Player in players.values():
		player.position = _player_spawn(player.peer_id)
		player.build.ready = false
		player.sync_build(true)
		_mark_profile(player.peer_id)


func _is_authority() -> bool:
	return solo or Network.state == Network.State.HOST


func _movement() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


func _record_input(peer_id: int, direction: Vector2) -> void:
	if waves.phase == Phase.WAVE and players.has(peer_id):
		_inputs[peer_id] = [direction, Time.get_ticks_msec()]


func _physics_process(delta: float) -> void:
	if _is_authority():
		if waves.phase == Phase.WAVE:
			_simulate_wave(delta)
		var frame := _world_frame()
		_view.update_frame(frame)
		_frame_timer -= delta
		if _frame_timer <= 0.0:
			_frame_timer = FRAME_INTERVAL
			_flush_profiles()
			if Network.state == Network.State.HOST and players.size() > 1:
				_send_snapshot(frame)
	elif Network.state == Network.State.CLIENT and waves.phase == Phase.WAVE:
		_input_timer -= delta
		if _input_timer <= 0.0:
			_input_timer = INPUT_INTERVAL
			Network.send_input(_movement())


func _simulate_wave(delta: float) -> void:
	var batch := waves.advance(delta, players.size())
	if waves.remaining <= 0.0:
		_finish_wave()
		return
	_schedule_spawns(batch)
	_tick_markers(delta)
	_tick_players(delta)
	_tick_foes(delta)
	_index_foes()
	_tick_projectiles(delta)
	_tick_drops(delta)
	for i in range(_blasts.size() - 1, -1, -1):
		_blasts[i]["life"] -= delta
		if _blasts[i]["life"] <= 0.0:
			_blasts.remove_at(i)
	for player: Player in players.values():
		if player.hp > 0:
			return
	_clear_combat()
	waves.phase = Phase.DEFEAT
	for peer_id: int in players:
		_mark_profile(peer_id)


func _finish_wave() -> void:
	for drop in _drops:
		if drop["kind"] == Mark.MATERIAL:
			waves.bag += int(drop["value"])
		elif drop["kind"] == Mark.CRATE:
			var recipient := _nearest_player(drop["point"])
			if recipient != null:
				recipient.build.crates.append(drop["value"])
	_clear_combat()
	waves.phase = Phase.VICTORY if waves.number == Waves.LAST_WAVE else Phase.SHOP
	sounds.play(Sounds.Cue.CLEAR)
	waves.ready_count = 0
	for player: Player in players.values():
		if waves.phase == Phase.SHOP:
			player.build.finish_wave(waves.number)
			player.level = player.build.level
		_mark_profile(player.peer_id)


func _tick_players(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for player: Player in players.values():
		var direction := Vector2.ZERO
		if player.peer_id == 1:
			direction = _movement()
		elif _inputs.has(player.peer_id):
			var recorded: Array = _inputs[player.peer_id]
			if now - int(recorded[1]) <= INPUT_TIMEOUT_MS:
				direction = recorded[0]
		player.simulate(delta, direction, MOVE_BOUNDS)
		if player.hp <= 0:
			continue
		for slot in range(player.build.weapons.size()):
			player.cooldowns[slot] -= delta
			if player.cooldowns[slot] <= 0.0:
				_fire_weapon(player, slot)


func _schedule_spawns(batch: int) -> void:
	if batch > 0:
		var center := _spawn_point()
		for i in range(batch):
			if enemies.size() + _markers.size() >= MAX_FOES:
				break
			var point := center + Vector2.from_angle(randf() * TAU) * randf_range(6.0, 60.0)
			_mark_spawn(_pick_enemy(), point.clamp(FOE_BOUNDS.position, FOE_BOUNDS.end), 0.63)
	if waves.tree_in <= 0.0 and waves.remaining > 3.0:
		waves.tree_in = randf_range(14.0, 20.0)
		_mark_spawn(Enemy.Kind.TREE, _spawn_point(), 0.73)
	if not waves.special_spawned and waves.elapsed >= 1.5:
		waves.special_spawned = true
		if waves.number == Waves.LAST_WAVE:
			var point := _spawn_point()
			_mark_spawn(Enemy.Kind.BOSS, point, 1.18)
			if waves.danger == 5:
				_mark_spawn(Enemy.Kind.BOSS, FIELD.get_center() * 2.0 - point, 1.18)
		elif waves.encounter(waves.number) == "ELITE":
			_mark_spawn(Enemy.Kind.ELITE, _spawn_point(), 1.18)


func _spawn_point() -> Vector2:
	var best := FIELD.get_center()
	var best_distance := 0.0
	for i in range(10):
		var point := Vector2(randf_range(FOE_BOUNDS.position.x, FOE_BOUNDS.end.x),
			randf_range(FOE_BOUNDS.position.y, FOE_BOUNDS.end.y))
		var nearest := _nearest_player(point)
		var distance := INF if nearest == null else point.distance_squared_to(nearest.position)
		if distance >= 169.0 * 169.0:
			return point
		if distance > best_distance:
			best_distance = distance
			best = point
	return best


func _mark_spawn(kind: int, point: Vector2, delay: float) -> void:
	_markers.append({"kind": kind, "point": point, "time": delay})


func _tick_markers(delta: float) -> void:
	for i in range(_markers.size() - 1, -1, -1):
		var marker := _markers[i]
		marker["time"] -= delta
		if marker["time"] <= 0.0:
			_spawn_enemy(marker["kind"], marker["point"])
			_markers.remove_at(i)


func _pick_enemy() -> int:
	var roll := randf()
	if roll < 0.22:
		return Enemy.Kind.RUNNER if waves.number >= 2 else Enemy.Kind.CHASER
	if roll < 0.36:
		return Enemy.Kind.SHOOTER if waves.number >= 4 else Enemy.Kind.CHASER
	if roll < 0.49:
		return Enemy.Kind.TANK if waves.number >= 5 else Enemy.Kind.CHASER
	if roll < 0.63:
		return Enemy.Kind.CHARGER if waves.number >= 7 else Enemy.Kind.CHASER
	if roll < 0.71:
		return Enemy.Kind.NEST if waves.number >= 9 and waves.danger >= 1 else Enemy.Kind.CHASER
	return Enemy.Kind.CHASER


func _spawn_enemy(kind: int, point: Vector2) -> Enemy:
	if enemies.size() >= MAX_FOES:
		return null
	_enemy_id += 1
	return _add_enemy(_enemy_id, kind, point)


func _add_enemy(id: int, kind: int, point: Vector2) -> Enemy:
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.is_replica = not _is_authority()
	enemy.configure(kind, maxi(1, waves.number), maxi(1, players.size()), Waves.DANGER_POWER[waves.danger])
	if kind == Enemy.Kind.BOSS and waves.danger == 5:
		enemy.hp = roundi(enemy.hp * 0.75)
		enemy.max_hp = enemy.hp
	enemy.position = point
	enemy.z_index = 1
	enemies[id] = enemy
	add_child(enemy)
	return enemy


func _nearest_player(point: Vector2) -> Player:
	var nearest: Player
	var best := INF
	for player: Player in players.values():
		if player.hp > 0:
			var distance := player.position.distance_squared_to(point)
			if distance < best:
				best = distance
				nearest = player
	return nearest


func _tick_foes(delta: float) -> void:
	for id: int in enemies.keys():
		var enemy: Enemy = enemies[id]
		if enemy.burn_ticks > 0:
			enemy.burn_clock -= delta
			if enemy.burn_clock <= 0.0:
				enemy.burn_ticks -= 1
				enemy.burn_clock += 0.36
				if _hit_enemy(id, enemy.burn_amount, enemy.burn_owner):
					continue
		if enemy.kind == Enemy.Kind.TREE:
			continue
		var target := _nearest_player(enemy.position)
		if target == null:
			return
		match enemy.simulate(target.position, delta, FOE_BOUNDS):
			Enemy.Attack.AIMED:
				_hostile_bolt(enemy, enemy.aim, 275.0)
			Enemy.Attack.RING:
				var petals := 13 if enemy.kind == Enemy.Kind.BOSS else 8
				for i in range(petals):
					_hostile_bolt(enemy, enemy.aim.rotated(float(i) * TAU / petals), 203.0)
			Enemy.Attack.HATCH:
				if enemies.size() + _markers.size() < MAX_FOES:
					_mark_spawn(Enemy.Kind.CHASER, enemy.position, 0.47)
		if enemy.position.distance_squared_to(target.position) < pow(enemy.radius + Player.BODY_RADIUS, 2.0):
			if _hurt_player(target, enemy.contact_damage) > 0:
				enemy.position += target.position.direction_to(enemy.position) * 19.0


func _hurt_player(player: Player, amount: int) -> int:
	var result := player.hurt(amount)
	if result < 0:
		_view.notice(player.position, "DODGE", Color("#e9eadc"))
	elif result > 0:
		_view.notice(player.position, "-%d" % result, Color("#ff9c92"), true)
		if player.is_local:
			sounds.play(Sounds.Cue.HURT)
	return result


func _nearest_foe(point: Vector2, reach: float, skip: Dictionary = {}) -> int:
	var closest := -1
	var distance := reach * reach
	for id: int in enemies:
		if skip.has(id):
			continue
		var enemy: Enemy = enemies[id]
		var candidate := enemy.position.distance_squared_to(point)
		if candidate < distance:
			closest = id
			distance = candidate
	return closest


func _fire_weapon(player: Player, slot: int) -> void:
	var weapon := player.build.weapons[slot]
	var spec: Dictionary = Catalog.WEAPONS[weapon["id"]]
	var tier := int(weapon["tier"]) - 1
	var stats := player.build.stats
	var melee := spec.has("arc")
	var reach := maxf(38.0, spec["reach"] + stats[Stat.REACH] * (0.50 if melee else 1.0))
	var point := player.position + player.mount_offset(slot)
	var target_id := _nearest_foe(point, reach)
	if target_id < 0:
		return
	var target: Enemy = enemies[target_id]
	var aim := point.direction_to(target.position)
	if aim == Vector2.ZERO:
		aim = Vector2.from_angle(player.weapon_angles[slot])
	var interval := float(spec["rate"]) * float(Catalog.TIER_COOLDOWN[tier])
	interval /= maxf(0.20, 1.0 + stats[Stat.ATTACK] / 100.0)
	player.attack(slot, aim.angle(), maxf(0.06, interval))
	if player.is_local:
		sounds.play(Sounds.Cue.SWING if melee else Sounds.Cue.SHOT)
	if melee:
		_swing(player, spec, tier, point, aim, reach, target_id)
		return
	var pellets := int(spec.get("pellets", 1))
	for i in range(pellets):
		if _projectiles.size() >= MAX_PROJECTILES:
			break
		var bolt := Projectile.new()
		var spread := (i - (pellets - 1) / 2.0) * float(spec.get("spread", 0.0))
		bolt.point = point + aim * 10.0
		bolt.velocity = aim.rotated(spread) * float(spec["speed"])
		bolt.distance = reach + 16.0
		bolt.owner_id = player.peer_id
		bolt.critical = _roll_crit(stats, spec)
		bolt.damage = _weapon_damage(stats, spec, tier, bolt.critical)
		bolt.pierce = int(spec.get("pierce", 0))
		bolt.bounce = int(spec.get("bounce", 0))
		if spec.has("burn"):
			bolt.burn = maxi(1, roundi(spec["burn"] * Catalog.TIER_DAMAGE[tier] + stats[Stat.ELEMENTAL]))
		bolt.blast = float(spec.get("blast", 0.0))
		_projectiles.append(bolt)


func _swing(player: Player, spec: Dictionary, tier: int, point: Vector2, aim: Vector2,
		reach: float, target_id: int) -> void:
	var arc_cutoff := cos(float(spec["arc"]))
	var stats := player.build.stats
	for id: int in enemies.keys():
		var enemy: Enemy = enemies[id]
		var difference := enemy.position - point
		if id != target_id and (difference.length_squared() > pow(reach + enemy.radius * 0.55, 2.0)
			or difference.normalized().dot(aim) < arc_cutoff):
			continue
		var critical := _roll_crit(stats, spec)
		_hit_enemy(id, _weapon_damage(stats, spec, tier, critical), player.peer_id, critical)


func _roll_crit(stats: PackedInt32Array, spec: Dictionary) -> bool:
	return randf() * 100.0 < clampf(3.0 + stats[Stat.CRIT] + float(spec.get("crit", 0)), 0.0, 100.0)


func _weapon_damage(stats: PackedInt32Array, spec: Dictionary, tier: int, crit: bool) -> int:
	var stat_id: int = Stat.MELEE if spec.has("arc") else (Stat.ELEMENTAL if spec.has("burn") else Stat.RANGED)
	var base := float(spec["damage"]) * float(Catalog.TIER_DAMAGE[tier])
	var amount := (base + stats[stat_id] * float(spec.get("scale", 1.0))) * (1.0 + stats[Stat.DAMAGE] / 100.0)
	return maxi(1, roundi(amount * (2.0 if crit else 1.0)))


func _hostile_bolt(enemy: Enemy, direction: Vector2, speed: float) -> void:
	if _projectiles.size() >= MAX_PROJECTILES:
		return
	var bolt := Projectile.new()
	bolt.point = enemy.position + direction * (enemy.radius + 4.0)
	bolt.velocity = direction * speed
	bolt.distance = 680.0
	bolt.damage = enemy.contact_damage
	_projectiles.append(bolt)


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))


func _index_foes() -> void:
	_foe_grid.clear()
	for id: int in enemies:
		var enemy: Enemy = enemies[id]
		var cell := _cell(enemy.position)
		if not _foe_grid.has(cell):
			_foe_grid[cell] = []
		_foe_grid[cell].append(id)
	for group: Array in _foe_grid.values():
		for i in range(1, group.size()):
			var enemy: Enemy = enemies[group[i]]
			if enemy.kind == Enemy.Kind.TREE or enemy.mode == Enemy.Mode.DASH:
				continue
			for j in range(maxi(0, i - 4), i):
				var other: Enemy = enemies[group[j]]
				var gap := enemy.position - other.position
				var clearance := (enemy.radius + other.radius) * 0.76
				if gap.length_squared() < clearance * clearance:
					var axis := gap.normalized() if gap != Vector2.ZERO else Vector2.RIGHT
					enemy.position = (enemy.position + axis * 1.1).clamp(FOE_BOUNDS.position, FOE_BOUNDS.end)


func _projectile_target(bolt: Projectile, start: Vector2, end: Vector2) -> int:
	var pad := Vector2(41, 41)
	var low := _cell(start.min(end) - pad)
	var high := _cell(start.max(end) + pad)
	var closest := -1
	var best := INF
	for x in range(low.x, high.x + 1):
		for y in range(low.y, high.y + 1):
			for id: int in _foe_grid.get(Vector2i(x, y), []):
				var enemy: Enemy = enemies.get(id)
				if enemy == null or bolt.hit_ids.has(id):
					continue
				var point := Geometry2D.get_closest_point_to_segment(enemy.position, start, end)
				var radius := enemy.radius + 3.0
				if enemy.position.distance_squared_to(point) <= radius * radius:
					var distance := start.distance_squared_to(point)
					if distance < best:
						best = distance
						closest = id
	return closest


func _tick_projectiles(delta: float) -> void:
	var offscreen := FIELD.grow(24.0)
	for i in range(_projectiles.size() - 1, -1, -1):
		var bolt := _projectiles[i]
		var start := bolt.point
		var step := bolt.velocity * delta
		bolt.distance -= step.length()
		bolt.point += step
		var remove := false
		if bolt.owner_id == 0:
			for player: Player in players.values():
				var nearest := Geometry2D.get_closest_point_to_segment(player.position, start, bolt.point)
				if player.hp > 0 and player.position.distance_squared_to(nearest) < 19.0 * 19.0:
					_hurt_player(player, bolt.damage)
					remove = true
					break
		else:
			var hit_id := _projectile_target(bolt, start, bolt.point)
			if hit_id >= 0:
				remove = _impact(bolt, hit_id)
		if remove or bolt.distance <= 0.0 or not offscreen.has_point(bolt.point):
			if not remove and bolt.blast > 0.0 and FIELD.has_point(bolt.point):
				_explode(bolt, bolt.point)
			_projectiles.remove_at(i)


func _impact(bolt: Projectile, id: int) -> bool:
	var enemy: Enemy = enemies[id]
	if bolt.blast > 0.0:
		_explode(bolt, enemy.position)
		return true
	var point := enemy.position
	if not _hit_enemy(id, bolt.damage, bolt.owner_id, bolt.critical) and bolt.burn > 0:
		enemy.ignite(bolt.burn, bolt.owner_id)
	bolt.hit_ids[id] = true
	if bolt.bounce > 0:
		var next_id := _nearest_foe(point, 190.0, bolt.hit_ids)
		if next_id >= 0:
			var target: Enemy = enemies[next_id]
			bolt.point = point
			bolt.velocity = point.direction_to(target.position) * bolt.velocity.length()
			bolt.distance = 206.0
			bolt.bounce -= 1
			bolt.damage = maxi(1, roundi(bolt.damage * 0.84))
			return false
	if bolt.pierce > 0:
		bolt.pierce -= 1
		bolt.damage = maxi(1, roundi(bolt.damage * 0.72))
		return false
	return true


func _explode(bolt: Projectile, point: Vector2) -> void:
	_blasts.append({"point": point, "radius": bolt.blast, "life": 0.33})
	for id: int in enemies.keys():
		var enemy: Enemy = enemies[id]
		var distance := point.distance_to(enemy.position)
		if distance < bolt.blast + enemy.radius:
			var factor := 1.0 - 0.35 * minf(1.0, distance / bolt.blast)
			_hit_enemy(id, maxi(1, roundi(bolt.damage * factor)), bolt.owner_id, bolt.critical)


func _hit_enemy(id: int, amount: int, owner_id: int, critical := false) -> bool:
	var enemy: Enemy = enemies[id]
	enemy.hit(amount)
	var tint := Color("#ffe298") if critical else Color("#fff0da")
	_view.notice(enemy.position, str(amount), tint, critical)
	var owner: Player = players.get(owner_id)
	if owner != null and owner.hp > 0 and enemy.kind != Enemy.Kind.TREE:
		owner.try_life_steal()
	if enemy.hp > 0:
		return false
	_enemy_loot(enemy, owner)
	enemy.queue_free()
	enemies.erase(id)
	return true


func _enemy_loot(enemy: Enemy, owner: Player) -> void:
	var luck := 0 if owner == null else owner.build.stats[Stat.LUCK]
	var point := enemy.position
	var crate_chance := clampf(0.014 + luck * 0.0010, 0.005, 0.19)
	var fruit_chance := clampf(0.043 + luck * 0.0012, 0.012, 0.28)
	if enemy.kind == Enemy.Kind.TREE:
		if randf() < clampf(0.23 + luck * 0.006, 0.09, 0.67):
			_drop_crate(point, false)
		else:
			_drop_pickup(Mark.FRUIT, point, 3)
		return
	waves.kills += 1
	if enemy.kind in [Enemy.Kind.ELITE, Enemy.Kind.BOSS] or randf() < waves.material_drop_chance():
		var base := roundi(enemy.reward * (1.0 + (players.size() - 1) * 0.42))
		var bonus := mini(base, waves.bag)
		waves.bag -= bonus
		_drop_material(point, base + bonus)
	if enemy.kind in [Enemy.Kind.ELITE, Enemy.Kind.BOSS]:
		_drop_crate(point, true)
	elif randf() < crate_chance:
		_drop_crate(point, false)
	elif randf() < fruit_chance:
		_drop_pickup(Mark.FRUIT, point, 3)


func _drop_material(point: Vector2, value: int) -> void:
	var count := 0
	var nearest: Dictionary = {}
	var distance := INF
	for drop in _drops:
		if drop["kind"] == Mark.MATERIAL:
			count += 1
			var candidate := point.distance_squared_to(drop["point"])
			if candidate < distance:
				distance = candidate
				nearest = drop
	if count >= MATERIAL_LIMIT:
		nearest["value"] += value
	else:
		_drop_pickup(Mark.MATERIAL, point, value)


func _drop_crate(point: Vector2, rare: bool) -> void:
	var tier := 1
	if rare:
		tier = 4
	elif waves.number >= 5 and randf() < 0.33:
		tier = 2
	_drop_pickup(Mark.CRATE, point + Vector2(13, -6), Catalog.pick_item(tier))


func _drop_pickup(kind: int, point: Vector2, value: int) -> void:
	_drops.append({"kind": kind, "point": point.clamp(MOVE_BOUNDS.position, MOVE_BOUNDS.end), "value": value})


func _tick_drops(delta: float) -> void:
	for i in range(_drops.size() - 1, -1, -1):
		var drop := _drops[i]
		var point: Vector2 = drop["point"]
		var closest: Player
		var distance := INF
		for player: Player in players.values():
			if player.hp <= 0 or (drop["kind"] == Mark.FRUIT and player.hp >= player.max_hp):
				continue
			var candidate := point.distance_squared_to(player.position)
			var magnet := maxf(25.0, 72.0 + player.build.stats[Stat.MAGNET])
			if candidate < distance and candidate <= magnet * magnet:
				distance = candidate
				closest = player
		if closest == null:
			continue
		if distance <= 18.0 * 18.0:
			_collect(drop, closest)
			_drops.remove_at(i)
		else:
			drop["point"] = point.move_toward(closest.position, 342.0 * delta)


func _collect(drop: Dictionary, player: Player) -> void:
	var value := int(drop["value"])
	match int(drop["kind"]):
		Mark.MATERIAL:
			_distribute_materials(value)
		Mark.FRUIT:
			var healed := player.heal(value)
			if healed > 0:
				_view.notice(player.position, "+%d" % healed, Color("#ccf69d"))
		Mark.CRATE:
			player.build.crates.append(value)
			_view.notice(player.position, "CRATE", Color("#ffda9d"), true)
			var item: Dictionary = Catalog.ITEMS[value]
			player.heal(player.max_hp if item["tier"] == 4 else 3)


func _distribute_materials(amount: int) -> void:
	var peers := players.keys()
	peers.sort()
	var share := floori(float(amount) / peers.size())
	var extra := amount % peers.size()
	for i in range(peers.size()):
		var distance := posmod(i - _material_cursor, peers.size())
		var payout := share + (1 if distance < extra else 0)
		if payout > 0:
			var player: Player = players[peers[i]]
			player.build.earn(payout)
			player.level = player.build.level
			_mark_profile(player.peer_id)
	_material_cursor = (_material_cursor + extra) % peers.size()


func _world_frame() -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	for drop in _drops:
		var point: Vector2 = drop["point"]
		frame.append_array(PackedFloat32Array([drop["kind"], point.x, point.y, drop["value"], 0, 0]))
	for marker in _markers:
		var point: Vector2 = marker["point"]
		frame.append_array(PackedFloat32Array([Mark.SPAWN, point.x, point.y, marker["time"], 0, 0]))
	for bolt in _projectiles:
		var kind: int = Mark.HOSTILE if bolt.owner_id == 0 else Mark.SHOT
		var style := 2 if bolt.blast > 0.0 else (1 if bolt.burn > 0 else 0)
		frame.append_array(PackedFloat32Array([kind, bolt.point.x, bolt.point.y,
			bolt.velocity.x, bolt.velocity.y, style]))
	for blast in _blasts:
		var point: Vector2 = blast["point"]
		frame.append_array(PackedFloat32Array([Mark.BLAST, point.x, point.y, blast["radius"], blast["life"], 0]))
	return frame


func _send_snapshot(world: PackedFloat32Array) -> void:
	# Fixed rows carry presentation state. Shop actions and private builds use reliable RPCs.
	var roster := PackedFloat32Array()
	for player: Player in players.values():
		roster.append_array(PackedFloat32Array([player.peer_id, player.position.x, player.position.y,
			player.hp, player.max_hp, player.origin, player.level, player.facing]))
		for i in range(Catalog.SLOT_COUNT):
			roster.append_array(PackedFloat32Array([
				player.weapon_codes[i], player.weapon_angles[i], player.shot_numbers[i]]))
	var horde := PackedFloat32Array()
	for id: int in enemies:
		var enemy: Enemy = enemies[id]
		horde.append_array(PackedFloat32Array([id, enemy.position.x, enemy.position.y,
			enemy.hp, enemy.max_hp, enemy.kind, enemy.mode, enemy.aim.angle()]))
	var info := PackedInt32Array([waves.phase, waves.number, waves.bag, waves.kills,
		waves.ready_count, waves.danger])
	Network.send_snapshot(info, waves.remaining, roster, horde, world)


func _receive_snapshot(info: PackedInt32Array, time_left: float, roster: PackedFloat32Array,
		horde: PackedFloat32Array, world: PackedFloat32Array) -> void:
	if info.size() != 6 or roster.size() % PLAYER_STRIDE != 0 or horde.size() % ENEMY_STRIDE != 0:
		return
	if world.size() % WorldView.STRIDE != 0:
		return
	var new_wave := waves.number != info[1]
	var old_phase := waves.phase
	waves.phase = info[0]
	waves.number = info[1]
	waves.bag = info[2]
	waves.kills = info[3]
	waves.ready_count = info[4]
	waves.danger = info[5]
	waves.remaining = time_left
	if waves.phase == Phase.WAVE and (old_phase != Phase.WAVE or new_wave):
		sounds.play(Sounds.Cue.DEPLOY)
	elif old_phase == Phase.WAVE and waves.phase in [Phase.SHOP, Phase.VICTORY]:
		sounds.play(Sounds.Cue.CLEAR)
	var seen_players: Dictionary = {}
	for i in range(0, roster.size(), PLAYER_STRIDE):
		var peer_id := int(roster[i])
		var player: Player = players.get(peer_id)
		var point := Vector2(roster[i + 1], roster[i + 2])
		if player == null:
			player = _add_player(peer_id)
			player.position = point
		elif new_wave:
			player.position = point
		elif int(roster[i + 3]) < player.hp:
			_view.notice(point, "-%d" % (player.hp - int(roster[i + 3])), Color("#ff9c92"), true)
			if player.is_local:
				sounds.play(Sounds.Cue.HURT)
		if player.is_local and waves.phase == Phase.WAVE and not new_wave:
			_play_replica_shot(player, roster, i)
		player.goal_position = point
		player.replicate(roster, i)
		seen_players[peer_id] = true
	for peer_id: int in players.keys():
		if not seen_players.has(peer_id):
			players[peer_id].queue_free()
			players.erase(peer_id)
	var seen_foes: Dictionary = {}
	for i in range(0, horde.size(), ENEMY_STRIDE):
		var id := int(horde[i])
		var point := Vector2(horde[i + 1], horde[i + 2])
		var enemy: Enemy = enemies.get(id)
		if enemy == null:
			enemy = _add_enemy(id, int(horde[i + 5]), point)
		elif int(horde[i + 3]) < enemy.hp:
			_view.notice(point, str(enemy.hp - int(horde[i + 3])), Color("#fff0da"))
			enemy.hit_flash = 0.10
		enemy.goal_position = point
		enemy.hp = int(horde[i + 3])
		enemy.max_hp = int(horde[i + 4])
		enemy.mode = int(horde[i + 6])
		enemy.aim = Vector2.from_angle(horde[i + 7])
		seen_foes[id] = true
	for id: int in enemies.keys():
		if not seen_foes.has(id):
			enemies[id].queue_free()
			enemies.erase(id)
	_view.update_frame(world, true)


func _play_replica_shot(player: Player, frame: PackedFloat32Array, start: int) -> void:
	for slot in range(Catalog.SLOT_COUNT):
		var offset := start + 8 + slot * 3
		var code := int(frame[offset])
		var shot := int(frame[offset + 2])
		if code > 0 and shot > player.shot_numbers[slot]:
			var id := floori((code - 1) / 4.0)
			var melee := Catalog.pattern(id) == Catalog.Pattern.MELEE
			sounds.play(Sounds.Cue.SWING if melee else Sounds.Cue.SHOT)
			break


func _draw() -> void:
	draw_rect(FIELD.grow(5.0), Color("#251b23"))
	draw_rect(FIELD, Color("#ac826b"))
	draw_rect(FIELD.grow(-7.0), Color("#b58a70"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 177
	for i in range(215):
		var point := Vector2(rng.randf_range(42.0, 1078.0), rng.randf_range(96.0, 645.0))
		var size := rng.randf_range(1.0, 3.0)
		draw_line(point, point + Vector2(size * 2.0, size * -0.53),
			Color(0.44, 0.25, 0.22, rng.randf_range(0.17, 0.43)), size, true)
	for i in range(28):
		var point := Vector2(rng.randf_range(46.0, 1074.0), rng.randf_range(102.0, 641.0))
		draw_circle(point, rng.randf_range(3.0, 8.0), Color(0.50, 0.31, 0.28, 0.17), true, -1.0, true)
	draw_rect(FIELD, Color("#725044"), false, 2.2)
