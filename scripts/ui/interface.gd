extends CanvasLayer

const Arena = preload("res://scripts/game/arena.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Build = preload("res://scripts/game/build.gd")
const Player = preload("res://scripts/game/player.gd")
const Enemy = preload("res://scripts/game/enemy.gd")
const Waves = preload("res://scripts/game/waves.gd")
const Phase = Waves.Phase
const Action = Build.Action

const PAPER := Color("#f6ead6")
const MUTED := Color("#cfb9b5")
const LIME := Color("#d2ea9e")
const GOLD := Color("#f4c88d")
const RED := Color("#f39d94")
const LINE := Color("#806470")
const PANEL := Color("#42323e")
const DARK := Color("#2e222d")
const CARD := Color("#382a36")

@onready var arena: Arena = $"../Arena"

var _root: Control
var _menu: Control
var _hud: Control
var _overlay: Panel
var _join_code: LineEdit
var _solo_button: Button
var _host_button: Button
var _join_button: Button
var _leave_button: Button
var _mute: Button
var _menu_status: Label
var _hp: Label
var _xp: Label
var _wallet: Label
var _bag: Label
var _time: Label
var _wave: Label
var _room: Label
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _team: Array[Label] = []
var _overlay_key := ""
var _copied := false
var _inspect := false


func _ready() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_menu()
	_build_hud()
	_mute = _button(_root, "SFX ON", Rect2(926, 20, 73, 40), DARK, MUTED, 12)
	_mute.pressed.connect(_toggle_sound)
	_leave_button = _button(_root, "EXIT", Rect2(1007, 20, 87, 40))
	_leave_button.pressed.connect(_leave)


func _build_menu() -> void:
	_menu = Control.new()
	_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount(_menu, _root, Rect2(0, 0, 1120, 720))
	_label(_menu, "bestato", Rect2(27, 18, 450, 46), 29, PAPER)
	_label(_menu, "ARENA SURVIVAL   /   20 WAVES", Rect2(657, 24, 262, 35), 16, GOLD)
	_label(_menu, "WASD  MOVE   •   WEAPONS FIRE AUTOMATICALLY", Rect2(27, 672, 700, 28), 14, MUTED)
	var card := _panel(_menu, Rect2(53, 106, 498, 527))
	_label(card, "WAVE SURVIVAL   /   SOLO OR CO-OP", Rect2(26, 21, 445, 28), 15, GOLD)
	_label(card, "Outrun\nthe swarm.", Rect2(24, 55, 450, 144), 61, PAPER)
	_label(card, "Wield up to six weapons, gather materials\nand build your loadout between waves.",
		Rect2(28, 214, 436, 58), 18, MUTED)
	_solo_button = _button(card, "DEPLOY SOLO", Rect2(27, 294, 444, 52), LIME, DARK)
	_solo_button.pressed.connect(arena.open_solo)
	_label(card, "ONLINE CO-OP   /   2–4 PLAYERS", Rect2(28, 365, 420, 27), 14, GOLD)
	_host_button = _button(card, "CREATE ROOM", Rect2(27, 404, 163, 46))
	_host_button.pressed.connect(Network.create_room)
	_join_code = LineEdit.new()
	_join_code.placeholder_text = "CODE"
	_join_code.max_length = 6
	_join_code.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_join_code.add_theme_font_size_override("font_size", 19)
	_join_code.add_theme_color_override("font_color", PAPER)
	_join_code.add_theme_color_override("font_placeholder_color", MUTED)
	_join_code.add_theme_stylebox_override("normal", _style(DARK, LINE, 5))
	_join_code.add_theme_stylebox_override("focus", _style(DARK, LIME, 5))
	_mount(_join_code, card, Rect2(203, 404, 135, 46))
	_join_code.text_submitted.connect(func(_text: String) -> void: _join())
	_join_button = _button(card, "JOIN", Rect2(351, 404, 120, 46))
	_join_button.pressed.connect(_join)
	_menu_status = _label(card, "", Rect2(28, 462, 444, 46), 15, MUTED)
	_menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var art := Node2D.new()
	art.position = Vector2(805, 378)
	_menu.add_child(art)
	var mascot: Player = Arena.PLAYER_SCENE.instantiate()
	mascot.is_local = true
	mascot.scale = Vector2(3.35, 3.35)
	mascot.weapon_codes = PackedInt32Array([1, 5, 17, 25, 29, 45])
	for i in range(Catalog.SLOT_COUNT):
		mascot.weapon_angles[i] = mascot.slot_angle(i)
	art.add_child(mascot)
	mascot.z_index = 1
	var positions := [Vector2(-150, -127), Vector2(144, -116), Vector2(160, 116), Vector2(-153, 120)]
	var kinds := [Enemy.Kind.CHASER, Enemy.Kind.RUNNER, Enemy.Kind.SHOOTER, Enemy.Kind.TANK]
	for i in range(positions.size()):
		var foe: Enemy = Arena.ENEMY_SCENE.instantiate()
		foe.configure(kinds[i], 1, 1)
		foe.position = positions[i]
		foe.scale = Vector2(1.58, 1.58)
		foe.aim = -foe.position.normalized()
		art.add_child(foe)
	var tag := _panel(_menu, Rect2(629, 576, 354, 42), DARK)
	_center(_label(tag, "DODGE  •  LOOT  •  REARM", Rect2(9, 4, 336, 34), 17, GOLD))


func _build_hud() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mount(_hud, _root, Rect2(0, 0, 1120, 720))
	_hp = _label(_hud, "", Rect2(26, 5, 269, 27), 18, PAPER)
	_hp_bar = _bar(_hud, Rect2(26, 34, 232, 12), RED)
	_xp_bar = _bar(_hud, Rect2(26, 55, 232, 6), Color("#c6a0f2"))
	_xp = _label(_hud, "", Rect2(270, 43, 164, 24), 13, MUTED)
	_wallet = _label(_hud, "", Rect2(353, 5, 185, 30), 18, LIME)
	_bag = _label(_hud, "", Rect2(354, 36, 170, 25), 13, GOLD)
	_wave = _label(_hud, "", Rect2(492, 4, 220, 24), 14, GOLD)
	_center(_wave)
	_time = _label(_hud, "", Rect2(492, 24, 220, 43), 33, PAPER)
	_center(_time)
	_room = _label(_hud, "", Rect2(751, 12, 172, 46), 15, MUTED)
	for i in range(Network.ROOM_CAPACITY):
		var tag := _panel(_hud, Rect2(26 + i * 270, 674, 258, 30), DARK)
		_team.append(_label(tag, "", Rect2(10, 1, 238, 28), 14, PAPER))


func _process(_delta: float) -> void:
	var state := Network.state
	var pending := state in [Network.State.REQUESTING, Network.State.CONNECTING]
	var in_menu := not arena.solo and (state == Network.State.IDLE or pending)
	_menu.visible = in_menu
	_hud.visible = not in_menu
	_leave_button.visible = pending or not in_menu
	_solo_button.disabled = pending
	_host_button.disabled = pending
	_join_button.disabled = pending
	_join_code.editable = not pending
	_menu_status.text = Network.status if not Network.status.is_empty() else "Invite friends with a room code."
	if not in_menu:
		_update_hud()
	var phase := arena.waves.phase
	if phase != Phase.SHOP:
		_inspect = false
	var show_panel := not in_menu and phase != Phase.WAVE
	var key := "hidden"
	if show_panel:
		key = "%d/%d/%d/%d/%d/%d/%s/%s" % [state, phase, arena.local_profile.get("revision", 0),
			arena.players.size(), arena.waves.ready_count, arena.waves.danger, Network.room_code, _inspect]
	if key != _overlay_key:
		_overlay_key = key
		_replace_overlay(show_panel)


func _update_hud() -> void:
	var profile := arena.local_profile
	var my_id := multiplayer.get_unique_id()
	var player: Player = arena.players.get(my_id)
	if player != null:
		_hp.text = "HP   %d / %d    •    LV %d" % [player.hp, player.max_hp, player.level]
		_hp_bar.max_value = player.max_hp
		_hp_bar.value = player.hp
	else:
		_hp.text = "SYNCING LOADOUT"
		_hp_bar.value = 0
	_xp_bar.max_value = int(profile.get("xp_goal", 1))
	_xp_bar.value = int(profile.get("xp", 0))
	_xp.text = "%d / %d XP" % [profile.get("xp", 0), profile.get("xp_goal", 0)]
	_wallet.text = "%d MATERIALS" % profile.get("materials", 0)
	_bag.text = "BAG  %d" % arena.waves.bag
	if arena.waves.phase == Phase.LOBBY:
		_wave.text = "PREPARE YOUR LOADOUT"
		_time.text = "READY?"
	elif arena.waves.phase == Phase.WAVE:
		var encounter := arena.waves.encounter(arena.waves.number)
		_wave.text = "WAVE %02d / 20" % arena.waves.number if encounter.is_empty() else encounter
		_time.text = "%02d" % ceili(arena.waves.remaining)
		_time.add_theme_color_override("font_color", RED if arena.waves.remaining <= 6.0 else PAPER)
	else:
		_wave.text = "WAVE %02d / 20" % arena.waves.number
		_time.text = "CLEAR" if arena.waves.phase in [Phase.SHOP, Phase.VICTORY] else "DOWN"
		_time.add_theme_color_override("font_color", PAPER)
	var session := "SOLO RUN" if arena.solo else "ROOM  %s" % Network.room_code
	_room.text = "%s\n%d ELIMINATED" % [session, arena.waves.kills]
	var peers := arena.players.keys()
	peers.sort()
	for i in range(_team.size()):
		var label := _team[i]
		label.get_parent().visible = i < peers.size()
		if i < peers.size():
			var member: Player = arena.players[peers[i]]
			var tag := "YOU" if member.is_local else "P%d" % member.peer_id
			var name_text: String = Catalog.ORIGINS[member.origin]["name"]
			var health := "%d/%d HP" % [member.hp, member.max_hp] if member.hp > 0 else "DOWN"
			label.text = "%s   %s   •   %s" % [tag, name_text, health]
			label.add_theme_color_override("font_color", Player.COLORS[(member.peer_id - 1) % Player.COLORS.size()])


func _replace_overlay(show_panel: bool) -> void:
	if is_instance_valid(_overlay):
		_overlay.hide()
		_overlay.queue_free()
		_overlay = null
	if not show_panel:
		return
	var profile := arena.local_profile
	var phase := arena.waves.phase
	if phase in [Phase.VICTORY, Phase.DEFEAT]:
		_result(phase == Phase.VICTORY)
	elif profile.is_empty() or profile.get("phase", -1) != phase or profile.get("wave", -1) != arena.waves.number:
		_overlay = _panel(_root, Rect2(341, 267, 438, 123))
		_center(_label(_overlay, "Syncing your loadout...", Rect2(10, 30, 418, 61), 23, MUTED))
	elif phase == Phase.LOBBY:
		_loadout(profile)
	elif int(profile["pending"]) > 0:
		_upgrade(profile)
	elif int(profile["crate"]) >= 0:
		_crate(profile)
	elif _inspect:
		_build_details(profile)
	else:
		_shop(profile)


func _loadout(profile: Dictionary) -> void:
	_overlay = _panel(_root, Rect2(63, 108, 994, 524))
	var online := not arena.solo
	var own_origin := int(profile["origin"])
	var own_weapon := int(profile["starter"])
	var origin: Dictionary = Catalog.ORIGINS[own_origin]
	_label(_overlay, "CHOOSE YOUR LOADOUT", Rect2(24, 18, 688, 44), 31)
	if online:
		var copy := _button(_overlay, "COPIED" if _copied else "CODE  %s  •  COPY" % Network.room_code,
			Rect2(735, 19, 235, 41))
		copy.pressed.connect(_copy_code)
	_label(_overlay, "01   CHARACTER", Rect2(25, 75, 898, 26), 14, GOLD)
	for i in range(Catalog.ORIGINS.size()):
		var selected := i == own_origin
		var button := _button(_overlay, Catalog.ORIGINS[i]["name"], Rect2(24 + i * 240, 107, 224, 46),
			LIME if selected else DARK, DARK if selected else PAPER, 19)
		button.pressed.connect(arena.act.bind(Action.ORIGIN, i))
	_label(_overlay, origin["line"], Rect2(25, 162, 931, 26), 16, PAPER)
	_label(_overlay, Catalog.effects_text(origin["stats"]).replace("\n", "   •   "),
		Rect2(25, 193, 946, 25), 14, MUTED)
	_label(_overlay, "02   STARTING WEAPON", Rect2(25, 231, 897, 25), 14, GOLD)
	for i in range(Catalog.STARTERS.size()):
		var id: int = Catalog.STARTERS[i]
		var selected := id == own_weapon
		var x := 24 + (i % 5) * 192
		var y := 263 + floori(i / 5.0) * 51
		var button := _button(_overlay, Catalog.WEAPONS[id]["name"], Rect2(x, y, 178, 42),
			LIME if selected else DARK, DARK if selected else PAPER, 16)
		button.disabled = not Catalog.allows_weapon(own_origin, id)
		button.tooltip_text = _weapon_text(id, 1, true)
		button.pressed.connect(arena.act.bind(Action.STARTER, id))
	_label(_overlay, _weapon_text(own_weapon, 1, true).replace("\n", "   •   "),
		Rect2(25, 372, 944, 33), 15, MUTED)
	var is_guest := Network.state == Network.State.CLIENT
	var room_text := "Solo   /   20 waves" if arena.solo else "%d / 4 connected   •   %d guest(s) ready" % [
		arena.players.size(), arena.waves.ready_count]
	_label(_overlay, room_text, Rect2(25, 449, 372, 44), 17, GOLD)
	var danger := _button(_overlay, "DANGER %d" % arena.waves.danger, Rect2(415, 444, 242, 53))
	danger.disabled = is_guest
	danger.tooltip_text = Waves.DANGER_TEXT[arena.waves.danger]
	danger.pressed.connect(arena.cycle_danger)
	var ready_text := "DEPLOY"
	if is_guest:
		ready_text = "UNREADY" if profile["ready"] else "READY UP"
	elif not arena.can_launch():
		ready_text = "WAITING FOR SQUAD"
	var start := _button(_overlay, ready_text, Rect2(678, 444, 292, 53), LIME, DARK, 17)
	start.disabled = not is_guest and not arena.can_launch()
	if is_guest:
		start.pressed.connect(arena.act.bind(Action.LOBBY_READY))
	else:
		start.pressed.connect(arena.launch)


func _upgrade(profile: Dictionary) -> void:
	_overlay = _panel(_root, Rect2(65, 147, 990, 424))
	_label(_overlay, "LEVEL UP", Rect2(24, 18, 660, 55), 38)
	_label(_overlay, "Choose one upgrade   •   %d pending" % profile["pending"],
		Rect2(26, 77, 624, 33), 17, MUTED)
	var options: Array = profile["upgrades"]
	for i in range(options.size()):
		var entry: Dictionary = options[i]
		var card := _panel(_overlay, Rect2(24 + i * 237, 132, 226, 177), CARD, _tier(entry["tier"]))
		_label(card, "TIER  %s" % Catalog.TIERS[entry["tier"] - 1], Rect2(13, 9, 200, 24), 13, _tier(entry["tier"]))
		_label(card, Catalog.stat_text(entry["stat"], entry["amount"]), Rect2(13, 51, 201, 41), 17)
		var pick := _button(card, "SELECT", Rect2(12, 120, 202, 43), LIME, DARK)
		pick.pressed.connect(arena.act.bind(Action.UPGRADE, i))
	var roll := _button(_overlay, "REROLL  %d" % profile["upgrade_roll"], Rect2(734, 344, 230, 47))
	roll.disabled = profile["materials"] < profile["upgrade_roll"]
	roll.pressed.connect(arena.act.bind(Action.UPGRADE_ROLL))
	_label(_overlay, "%d materials available" % profile["materials"], Rect2(24, 343, 470, 47), 17, LIME)


func _crate(profile: Dictionary) -> void:
	var item: Dictionary = Catalog.ITEMS[profile["crate"]]
	_overlay = _panel(_root, Rect2(264, 178, 592, 362))
	_label(_overlay, "LOOT CRATE   /   TIER %s" % Catalog.TIERS[item["tier"] - 1],
		Rect2(25, 20, 542, 28), 15, _tier(item["tier"]))
	_label(_overlay, item["name"], Rect2(24, 53, 542, 63), 36)
	_label(_overlay, Catalog.effects_text(item["stats"]), Rect2(27, 137, 535, 87), 19, MUTED)
	var recycle := _button(_overlay, "RECYCLE FOR MATERIALS", Rect2(26, 266, 258, 54))
	recycle.pressed.connect(arena.act.bind(Action.CRATE_RECYCLE))
	var take := _button(_overlay, "TAKE ITEM", Rect2(301, 266, 265, 54), LIME, DARK)
	take.disabled = not Catalog.item_available(profile["crate"], profile["items"])
	if take.disabled:
		take.text = "ITEM LIMIT REACHED"
	take.pressed.connect(arena.act.bind(Action.CRATE_KEEP))


func _shop(profile: Dictionary) -> void:
	_overlay = _panel(_root, Rect2(35, 96, 1050, 549))
	_label(_overlay, "THE SHOP", Rect2(18, 10, 475, 48), 33)
	var next := arena.waves.encounter(arena.waves.number + 1)
	var subtitle := "WAVE %02d COMPLETE" % arena.waves.number
	if not next.is_empty():
		subtitle += "   •   NEXT  %s" % next
	_label(_overlay, subtitle, Rect2(19, 59, 560, 28), 14, GOLD)
	_label(_overlay, "%d MATERIALS" % profile["materials"], Rect2(641, 23, 189, 36), 19, LIME)
	var roll := _button(_overlay, "REROLL  %d" % profile["roll"], Rect2(834, 20, 194, 43))
	roll.disabled = profile["ready"] or profile["materials"] < profile["roll"]
	roll.pressed.connect(arena.act.bind(Action.SHOP_ROLL))

	var offers: Array = profile["shop"]
	for i in range(offers.size()):
		_offer_card(offers[i], i, profile)
	var weapons: Array = profile["weapons"]
	_label(_overlay, "ARSENAL   %d / 6" % weapons.size(), Rect2(19, 296, 218, 29), 16, GOLD)
	var sets := _label(_overlay, _class_line(profile["classes"]), Rect2(222, 296, 805, 29), 14, MUTED)
	sets.tooltip_text = _class_details(profile["classes"])
	sets.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in range(Catalog.SLOT_COUNT):
		_inventory_card(i, weapons, profile["ready"])
	_label(_overlay, _stat_line(profile["stats"]), Rect2(19, 457, 689, 29), 15, MUTED)
	_label(_overlay, "%d / %d ready   •   HP refills next wave" % [
		arena.waves.ready_count, arena.players.size()], Rect2(19, 490, 687, 27), 15, GOLD)
	var details := _button(_overlay, "BUILD", Rect2(716, 465, 111, 49))
	details.pressed.connect(_toggle_details)
	var next_wave := _button(_overlay, "UNREADY" if profile["ready"] else "READY / NEXT WAVE",
		Rect2(837, 465, 191, 49), LIME, DARK)
	next_wave.pressed.connect(arena.act.bind(Action.SHOP_READY))


func _offer_card(offer: Dictionary, slot: int, profile: Dictionary) -> void:
	var accent := LINE if offer.is_empty() else _tier(offer["tier"])
	var card := _panel(_overlay, Rect2(19 + slot * 255, 96, 244, 185), CARD, accent)
	if offer.is_empty():
		_center(_label(card, "SOLD", Rect2(10, 48, 224, 87), 23, MUTED))
		return
	var weapon: bool = offer["kind"] == Catalog.Offer.WEAPON
	var spec: Dictionary = Catalog.WEAPONS[offer["id"]] if weapon else Catalog.ITEMS[offer["id"]]
	var kind := "WEAPON" if weapon else "PASSIVE"
	_label(card, "%s   /   TIER %s" % [kind, Catalog.TIERS[offer["tier"] - 1]], Rect2(12, 7, 220, 22), 12, accent)
	_label(card, spec["name"], Rect2(11, 30, 220, 34), 20)
	var summary := _weapon_text(offer["id"], offer["tier"], false) if weapon else Catalog.effects_text(spec["stats"])
	_label(card, summary, Rect2(12, 67, 220, 64), 13, MUTED)
	var buy := _button(card, "BUY  %d" % offer["price"], Rect2(11, 137, 122, 37), LIME, DARK)
	var space: bool = not weapon or profile["weapons"].size() < Catalog.SLOT_COUNT or _has_match(profile["weapons"], offer)
	var item_ok := weapon or Catalog.item_available(offer["id"], profile["items"])
	buy.disabled = profile["ready"] or not space or not item_ok or profile["materials"] < offer["price"]
	if not space:
		buy.tooltip_text = "Arsenal full. Combine or recycle a weapon first."
	elif not item_ok:
		buy.tooltip_text = "Item limit reached."
	buy.pressed.connect(arena.act.bind(Action.BUY, slot))
	var lock := _button(card, "UNLOCK" if offer["locked"] else "LOCK", Rect2(142, 137, 91, 37),
		GOLD if offer["locked"] else DARK, DARK if offer["locked"] else PAPER)
	lock.disabled = profile["ready"]
	lock.tooltip_text = "Keep this offer through rerolls and into the next shop."
	lock.pressed.connect(arena.act.bind(Action.LOCK, slot))


func _inventory_card(slot: int, weapons: Array, ready: bool) -> void:
	var card := _panel(_overlay, Rect2(19 + slot * 170, 332, 159, 109), CARD)
	if slot >= weapons.size():
		_center(_label(card, "EMPTY SLOT", Rect2(9, 16, 141, 77), 13, MUTED))
		return
	var weapon: Dictionary = weapons[slot]
	var name_text: String = Catalog.WEAPONS[weapon["id"]]["name"]
	var label := _label(card, "%s %s" % [name_text, Catalog.TIERS[weapon["tier"] - 1]],
		Rect2(8, 5, 143, 38), 15, _tier(weapon["tier"]))
	label.tooltip_text = _weapon_text(weapon["id"], weapon["tier"], true)
	var combine := _button(card, "MERGE", Rect2(7, 55, 70, 38), DARK, PAPER, 12)
	combine.disabled = ready or not _has_match(weapons, weapon, slot)
	combine.tooltip_text = "Merge two identical weapons of this tier to upgrade one."
	combine.pressed.connect(arena.act.bind(Action.COMBINE, slot))
	var sell := _button(card, "SELL", Rect2(82, 55, 70, 38), DARK, PAPER, 12)
	sell.disabled = ready or weapons.size() == 1
	sell.tooltip_text = "Recycle this weapon for materials."
	sell.pressed.connect(arena.act.bind(Action.RECYCLE, slot))


func _has_match(weapons: Array, entry: Dictionary, skip := -1) -> bool:
	if entry["tier"] >= 4:
		return false
	for i in range(weapons.size()):
		if i != skip and weapons[i]["id"] == entry["id"] and weapons[i]["tier"] == entry["tier"]:
			return true
	return false


func _build_details(profile: Dictionary) -> void:
	_overlay = _panel(_root, Rect2(78, 108, 964, 525))
	_label(_overlay, "YOUR BUILD", Rect2(24, 13, 655, 53), 35)
	var back := _button(_overlay, "BACK TO SHOP", Rect2(739, 22, 200, 44))
	back.pressed.connect(_toggle_details)
	var stats: PackedInt32Array = profile["stats"]
	_label(_overlay, "STATS", Rect2(25, 83, 530, 29), 15, GOLD)
	_label(_overlay, "ITEMS", Rect2(593, 83, 330, 29), 15, GOLD)
	for i in range(stats.size()):
		var x := 25 if i < 9 else 304
		var y := 116 + (i % 9) * 36
		var text := "%d Max HP" % stats[i] if i == Catalog.Stat.HP else Catalog.stat_text(i, stats[i])
		_label(_overlay, text, Rect2(x, y, 269, 32), 17, PAPER if stats[i] != 0 else MUTED)
	var items: Dictionary = profile["items"]
	var scroll := ScrollContainer.new()
	_mount(scroll, _overlay, Rect2(588, 115, 346, 346))
	var list := VBoxContainer.new()
	scroll.add_child(list)
	if items.is_empty():
		_label(list, "No passive items collected yet.", Rect2(0, 0, 321, 32), 17, MUTED)
	for id: int in items:
		var item: Dictionary = Catalog.ITEMS[id]
		var label := _label(list, "%s  ×%d" % [item["name"], items[id]], Rect2(0, 0, 321, 32),
			17, _tier(item["tier"]))
		label.tooltip_text = Catalog.effects_text(item["stats"])
	_label(_overlay, _class_line(profile["classes"]), Rect2(25, 466, 900, 29), 15, LIME)


func _result(victory: bool) -> void:
	_overlay = _panel(_root, Rect2(267, 190, 586, 340))
	_label(_overlay, "RUN REPORT", Rect2(25, 22, 531, 29), 14, GOLD)
	_label(_overlay, "Extraction complete" if victory else "Squad down",
		Rect2(23, 55, 540, 75), 43, LIME if victory else RED)
	_label(_overlay, "%d kills   •   Wave %02d of 20   •   Danger %d" % [
		arena.waves.kills, arena.waves.number, arena.waves.danger],
		Rect2(26, 151, 534, 44), 18, MUTED)
	if arena.solo or Network.state == Network.State.HOST:
		var retry := _button(_overlay, "NEW RUN", Rect2(26, 235, 534, 58), LIME, DARK, 19)
		retry.pressed.connect(arena.restart)
	else:
		_label(_overlay, "Waiting for the host to start a new run.", Rect2(26, 235, 533, 53), 18, MUTED)


func _weapon_text(id: int, tier: int, full: bool) -> String:
	var spec: Dictionary = Catalog.WEAPONS[id]
	var family := " / ".join(PackedStringArray(spec["families"]))
	var damage := roundi(spec["damage"] * Catalog.TIER_DAMAGE[tier - 1])
	var rate: float = spec["rate"] * Catalog.TIER_COOLDOWN[tier - 1]
	var pellets := int(spec.get("pellets", 1))
	var text := "%s\n%d dmg   •   %.2fs" % [family, damage, rate]
	if pellets > 1:
		text += "   •   %d pellets" % pellets
	if full:
		text += "\n%d range" % spec["reach"]
	return text


func _class_line(classes: Dictionary) -> String:
	var labels := PackedStringArray()
	for family: String in classes:
		if int(classes[family]) >= 2:
			labels.append("%s ×%d" % [family, classes[family]])
	return "SET BONUSES   /   %s" % ("Match two weapon classes" if labels.is_empty() else "   •   ".join(labels))


func _class_details(classes: Dictionary) -> String:
	var labels := PackedStringArray()
	for family: String in classes:
		var count: int = classes[family]
		if count >= 2:
			var bonus: Array = Catalog.CLASS_BONUSES[family]
			labels.append("%s: %s" % [family, Catalog.stat_text(bonus[0], bonus[1] * count)])
	return "Match two weapons that share a class to earn a set bonus." if labels.is_empty() else "\n".join(labels)


func _stat_line(stats: PackedInt32Array) -> String:
	var stat := Catalog.Stat
	return "%d HP   /   %+d%% DMG   /   %+d%% ATK SPD   /   %d ARMOR   /   %d HARVEST" % [
		stats[stat.HP], stats[stat.DAMAGE], stats[stat.ATTACK], stats[stat.ARMOR], stats[stat.HARVEST]]


func _tier(tier: int) -> Color:
	return Catalog.TIER_COLORS[tier - 1]


func _toggle_details() -> void:
	_inspect = not _inspect


func _toggle_sound() -> void:
	arena.sounds.muted = not arena.sounds.muted
	_mute.text = "SFX OFF" if arena.sounds.muted else "SFX ON"


func _join() -> void:
	_join_code.release_focus()
	Network.join_room(_join_code.text)


func _leave() -> void:
	_copied = false
	_inspect = false
	arena.back_to_menu()


func _copy_code() -> void:
	DisplayServer.clipboard_set(Network.room_code)
	_copied = true
	_overlay_key = ""


func _mount(control: Control, parent: Control, rect: Rect2) -> void:
	parent.add_child(control)
	control.position = rect.position
	control.size = rect.size


func _style(fill: Color, edge: Color, rounding := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(rounding)
	return box


func _panel(parent: Control, rect: Rect2, fill := PANEL, edge := LINE) -> Panel:
	var panel := Panel.new()
	panel.add_theme_stylebox_override("panel", _style(fill, edge))
	_mount(panel, parent, rect)
	return panel


func _label(parent: Control, value: String, rect: Rect2, points: int, color := PAPER) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", points)
	label.add_theme_color_override("font_color", color)
	_mount(label, parent, rect)
	return label


func _center(label: Label) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _bar(parent: Control, rect: Rect2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", _style(DARK, LINE, 4))
	bar.add_theme_stylebox_override("fill", _style(color, color, 4))
	_mount(bar, parent, rect)
	return bar


func _button(parent: Control, value: String, rect: Rect2, fill := DARK, ink := PAPER,
		points := 15) -> Button:
	var button := Button.new()
	button.text = value
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", points)
	button.add_theme_color_override("font_color", ink)
	button.add_theme_color_override("font_hover_color", ink)
	button.add_theme_color_override("font_pressed_color", ink)
	button.add_theme_color_override("font_focus_color", ink)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.31))
	button.add_theme_stylebox_override("normal", _style(fill, LINE, 5))
	button.add_theme_stylebox_override("hover", _style(fill.lightened(0.13), LIME, 5))
	button.add_theme_stylebox_override("pressed", _style(fill.darkened(0.13), LIME, 5))
	button.add_theme_stylebox_override("disabled", _style(DARK, LINE.darkened(0.18), 5))
	_mount(button, parent, rect)
	return button
