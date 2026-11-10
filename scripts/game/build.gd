extends RefCounted

const Catalog = preload("res://scripts/game/catalog.gd")
const Stat = Catalog.Stat

enum Action { ORIGIN, STARTER, LOBBY_READY, BUY, LOCK, SHOP_ROLL, COMBINE, RECYCLE,
	UPGRADE, UPGRADE_ROLL, CRATE_KEEP, CRATE_RECYCLE, SHOP_READY }

var origin := 0
var starter := 0
var ready := false
var revision := 0
var level := 1
var xp := 0
var materials := 0
var pending_levels := 0
var weapons: Array[Dictionary] = []
var shop: Array[Dictionary] = []
var upgrades: Array[Dictionary] = []
var crates: Array[int] = []
var items: Dictionary = {}
var classes: Dictionary = {}
var values := PackedInt32Array()
var stats := PackedInt32Array()
var shop_rolls := 0
var upgrade_rolls := 0
var _shop_wave := 1


func configure(new_origin: int, new_starter: int) -> void:
	origin = new_origin
	starter = new_starter
	ready = false
	weapons.assign([{"id": starter, "tier": 1}])
	values.resize(Catalog.STAT_NAMES.size())
	values.fill(0)
	values[Stat.HP] = 10
	_add_stats(Catalog.ORIGINS[origin]["stats"])
	_recalculate()


func _add_stats(effects: Dictionary) -> void:
	for stat_id: int in effects:
		values[stat_id] += int(effects[stat_id])


func _recalculate() -> void:
	stats = values.duplicate()
	classes.clear()
	for weapon in weapons:
		var families: Array = Catalog.WEAPONS[weapon["id"]]["families"]
		for family: String in families:
			classes[family] = int(classes.get(family, 0)) + 1
	for family: String in classes:
		var count: int = classes[family]
		if count >= 2:
			var bonus: Array = Catalog.CLASS_BONUSES[family]
			stats[bonus[0]] += int(bonus[1]) * count
	stats[Stat.HP] = maxi(1, stats[Stat.HP])
	stats[Stat.DODGE] = clampi(stats[Stat.DODGE], 0, 60)
	stats[Stat.SPEED] = clampi(stats[Stat.SPEED], -65, 90)


func xp_goal() -> int:
	return 5 + 3 * level + floori(level * level * 0.22)


func catch_up(wave: int) -> void:
	materials = (wave - 1) * 11
	level = 1 + floori((wave - 1) * 0.5)
	values[Stat.HP] += floori((wave - 1) * 0.8)
	for i in range(1, mini(Catalog.SLOT_COUNT, 1 + floori(wave * 0.25))):
		weapons.append({"id": starter, "tier": mini(3, 1 + floori(wave / 8.0))})
	_recalculate()


func earn(amount: int) -> void:
	materials = maxi(0, materials + amount)
	xp = maxi(0, xp + amount)
	while xp >= xp_goal():
		xp -= xp_goal()
		level += 1
		pending_levels += 1


func finish_wave(wave: int) -> void:
	earn(stats[Stat.HARVEST])
	if values[Stat.HARVEST] > 0:
		values[Stat.HARVEST] += ceili(values[Stat.HARVEST] * 0.05)
		_recalculate()
	ready = false
	_shop_wave = wave
	shop_rolls = 0
	upgrade_rolls = 0
	_roll_upgrades()
	_roll_shop()


func shop_roll_price() -> int:
	return 3 + floori(_shop_wave * 0.75) + shop_rolls * (2 + floori(_shop_wave * 0.15))


func upgrade_roll_price() -> int:
	return 2 + floori(_shop_wave * 0.65) + 2 * upgrade_rolls


func _price(base: int) -> int:
	var factor := clampf(1.0 + stats[Stat.PRICE] / 100.0, 0.25, 1.8)
	return maxi(1, floori((base + _shop_wave + base * 0.1 * _shop_wave) * factor))


func _roll_tier() -> int:
	var luck: float = clampf(stats[Stat.LUCK] * 0.0025, -0.10, 0.25)
	var roll := randf()
	if _shop_wave >= 9 and roll < (_shop_wave - 8) * 0.008 + luck * 0.35:
		return 4
	if _shop_wave >= 5 and roll < (_shop_wave - 4) * 0.017 + luck * 0.60:
		return 3
	if _shop_wave >= 2 and roll < _shop_wave * 0.024 + luck:
		return 2
	return 1


func _weapon_offer() -> Dictionary:
	var all: Array[int] = []
	var same_weapon: Array[int] = []
	var same_class: Array[int] = []
	for id in range(Catalog.WEAPONS.size()):
		var spec: Dictionary = Catalog.WEAPONS[id]
		if not Catalog.allows_weapon(origin, id) or _shop_wave < int(spec.get("min_wave", 1)):
			continue
		all.append(id)
		for held in weapons:
			if held["id"] == id:
				same_weapon.append(id)
				break
		for family: String in spec["families"]:
			if classes.has(family):
				same_class.append(id)
				break
	var pool := all
	var roll := randf()
	if roll < 0.20 and not same_weapon.is_empty():
		pool = same_weapon
	elif roll < 0.35 + maxf(0.0, (6 - _shop_wave) * 0.03) and not same_class.is_empty():
		pool = same_class
	var id: int = pool.pick_random()
	return _priced_weapon(id, _roll_tier())


func _priced_weapon(id: int, tier: int) -> Dictionary:
	var base: int = Catalog.WEAPONS[id]["price"]
	return {"kind": Catalog.Offer.WEAPON, "id": id, "tier": tier,
		"price": _price(roundi(base * Catalog.TIER_DAMAGE[tier - 1])), "locked": false}


func _item_offer() -> Dictionary:
	var id := Catalog.pick_item(_roll_tier(), items)
	var item: Dictionary = Catalog.ITEMS[id]
	return {"kind": Catalog.Offer.ITEM, "id": id, "tier": item["tier"],
		"price": _price(item["price"]), "locked": false}


func _roll_shop() -> void:
	var first_stock := shop.is_empty()
	shop.resize(4)
	var guarantee := 2 if _shop_wave <= 2 else (1 if _shop_wave <= 5 else 0)
	for offer in shop:
		if offer and offer["locked"] and offer["kind"] == Catalog.Offer.WEAPON:
			guarantee -= 1
	for i in range(4):
		if shop[i] and shop[i]["locked"]:
			var offer := shop[i]
			if offer["kind"] == Catalog.Offer.WEAPON:
				offer["price"] = _priced_weapon(offer["id"], offer["tier"])["price"]
			else:
				offer["price"] = _price(Catalog.ITEMS[offer["id"]]["price"])
			continue
		if i == 0 and first_stock and _shop_wave == 1:
			shop[i] = _priced_weapon(starter, 1)
			guarantee -= 1
		elif guarantee > 0 or randf() < 0.35:
			shop[i] = _weapon_offer()
			guarantee -= 1
		else:
			shop[i] = _item_offer()


func _roll_upgrades() -> void:
	upgrades.clear()
	if pending_levels == 0:
		return
	var stats_pool := Catalog.UPGRADABLE.duplicate()
	stats_pool.shuffle()
	var reward_level := level - pending_levels + 1
	for i in range(4):
		var stat_id: int = stats_pool[i]
		var tier := _roll_tier()
		if reward_level % 5 == 0:
			tier = maxi(tier, mini(4, reward_level / 5 + 1))
		upgrades.append({"stat": stat_id, "amount": Catalog.UPGRADE_BASE[stat_id] * tier, "tier": tier})


func apply_shop_action(action: int, slot: int) -> bool:
	if ready and action != Action.SHOP_READY:
		return false
	if pending_levels > 0:
		if action == Action.UPGRADE and slot >= 0 and slot < upgrades.size():
			var upgrade := upgrades[slot]
			values[upgrade["stat"]] += upgrade["amount"]
			pending_levels -= 1
			_recalculate()
			_roll_upgrades()
			return true
		if action == Action.UPGRADE_ROLL and materials >= upgrade_roll_price():
			materials -= upgrade_roll_price()
			upgrade_rolls += 1
			_roll_upgrades()
			return true
		return false
	if not crates.is_empty():
		if action == Action.CRATE_KEEP and Catalog.item_available(crates[0], items):
			_add_item(crates.pop_front())
			return true
		if action == Action.CRATE_RECYCLE:
			var item_id: int = crates.pop_front()
			materials += _recycle_value(Catalog.ITEMS[item_id]["price"])
			return true
		return false
	match action:
		Action.BUY:
			return _buy(slot)
		Action.LOCK:
			if slot >= 0 and slot < shop.size() and not shop[slot].is_empty():
				shop[slot]["locked"] = not shop[slot]["locked"]
				return true
		Action.SHOP_ROLL:
			if materials >= shop_roll_price():
				materials -= shop_roll_price()
				shop_rolls += 1
				_roll_shop()
				return true
		Action.COMBINE:
			return _combine(slot)
		Action.RECYCLE:
			if slot >= 0 and slot < weapons.size() and weapons.size() > 1:
				var weapon := weapons[slot]
				var base: int = Catalog.WEAPONS[weapon["id"]]["price"]
				materials += _recycle_value(roundi(base * Catalog.TIER_DAMAGE[weapon["tier"] - 1]))
				weapons.remove_at(slot)
				_recalculate()
				return true
		Action.SHOP_READY:
			ready = not ready
			return true
	return false


func _buy(slot: int) -> bool:
	if slot < 0 or slot >= shop.size() or shop[slot].is_empty():
		return false
	var offer := shop[slot]
	if materials < int(offer["price"]):
		return false
	if offer["kind"] == Catalog.Offer.ITEM:
		if not Catalog.item_available(offer["id"], items):
			return false
		_add_item(offer["id"])
	elif weapons.size() < Catalog.SLOT_COUNT:
		weapons.append({"id": offer["id"], "tier": offer["tier"]})
		_recalculate()
	else:
		var match_index := _matching_weapon(offer, -1)
		if match_index < 0:
			return false
		weapons[match_index]["tier"] += 1
		_recalculate()
	materials -= int(offer["price"])
	shop[slot] = {}
	return true


func _combine(slot: int) -> bool:
	if slot < 0 or slot >= weapons.size():
		return false
	var other := _matching_weapon(weapons[slot], slot)
	if other < 0:
		return false
	weapons[slot]["tier"] += 1
	weapons.remove_at(other)
	_recalculate()
	return true


func _matching_weapon(weapon: Dictionary, skip: int) -> int:
	if weapon["tier"] >= 4:
		return -1
	for i in range(weapons.size()):
		if i != skip and weapons[i]["id"] == weapon["id"] and weapons[i]["tier"] == weapon["tier"]:
			return i
	return -1


func _add_item(id: int) -> void:
	items[id] = int(items.get(id, 0)) + 1
	_add_stats(Catalog.ITEMS[id]["stats"])
	_recalculate()


func _recycle_value(base: int) -> int:
	return maxi(1, floori(_price(base) * 0.25))


func profile(compact: bool) -> Dictionary:
	var data := {"revision": revision, "level": level, "xp": xp, "xp_goal": xp_goal(),
		"materials": materials, "pending": pending_levels}
	if not compact:
		data.merge({
			"origin": origin, "starter": starter, "ready": ready, "stats": stats,
			"weapons": weapons.duplicate(true), "shop": shop.duplicate(true),
			"upgrades": upgrades.duplicate(true), "crate": -1 if crates.is_empty() else crates[0],
			"items": items.duplicate(), "classes": classes.duplicate(), "roll": shop_roll_price(),
			"upgrade_roll": upgrade_roll_price(),
		})
	return data
