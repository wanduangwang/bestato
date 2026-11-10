extends RefCounted

const Catalog = preload("res://scripts/game/catalog.gd")
const Balance = preload("res://scripts/game/balance.gd")
const Stat = Catalog.Stat

enum Action { ORIGIN, STARTER, LOBBY_READY, BUY, LOCK, SHOP_ROLL, COMBINE, RECYCLE,
	UPGRADE, UPGRADE_ROLL, CRATE_KEEP, CRATE_RECYCLE, SHOP_READY }

var origin := 0
var starter := 0
var ready := false
var revision := 0
var level := 0
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
			var bonus := Catalog.class_bonus(family, count)
			for stat_id: int in bonus:
				stats[stat_id] += int(bonus[stat_id])
	stats[Stat.HP] = maxi(1, stats[Stat.HP])
	stats[Stat.DODGE] = clampi(stats[Stat.DODGE], 0, 60)
	stats[Stat.SPEED] = clampi(stats[Stat.SPEED], -65, 90)


func xp_goal() -> int:
	return Balance.xp_to_next(level)


func earn(amount: int) -> int:
	materials = maxi(0, materials + amount)
	xp = maxi(0, xp + amount)
	var before := level
	while xp >= xp_goal():
		xp -= xp_goal()
		level += 1
		pending_levels += 1
	var gained := level - before
	if gained > 0:
		values[Stat.HP] += gained
		_recalculate()
	return gained


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
	return Balance.reroll_cost(_shop_wave, shop_rolls)


func upgrade_roll_price() -> int:
	return Balance.reroll_cost(_shop_wave, upgrade_rolls)


func _price(base: int) -> int:
	var factor := clampf(1.0 + stats[Stat.PRICE] / 100.0, 0.25, 1.8)
	return maxi(1, floori((base + _shop_wave + base * 0.1 * _shop_wave) * factor))


func _weapon_offer(tier: int, used: Dictionary, previous: Dictionary) -> Dictionary:
	var all: Array[int] = []
	var fresh: Array[int] = []
	var same_weapon: Array[int] = []
	var same_class: Array[int] = []
	for id in range(Catalog.WEAPONS.size()):
		var spec: Dictionary = Catalog.WEAPONS[id]
		if not Catalog.allows_weapon(origin, id) or _shop_wave < int(spec.get("min_wave", 1)):
			continue
		var key := Catalog.offer_key(Catalog.Offer.WEAPON, id, tier)
		if used.has(key):
			continue
		all.append(id)
		if not previous.has(key):
			fresh.append(id)
	var candidates := all if fresh.is_empty() else fresh
	if candidates.is_empty():
		return {}
	for id in candidates:
		for held in weapons:
			if held["id"] == id:
				same_weapon.append(id)
				break
		for family: String in Catalog.WEAPONS[id]["families"]:
			if classes.has(family):
				same_class.append(id)
				break
	var pool := candidates
	var roll := randf()
	if roll < 0.20 and not same_weapon.is_empty():
		pool = same_weapon
	elif roll < 0.35 + maxf(0.0, (6 - _shop_wave) * 0.03) and not same_class.is_empty():
		pool = same_class
	var id: int = pool.pick_random()
	return _priced_weapon(id, tier)


func _priced_weapon(id: int, tier: int) -> Dictionary:
	var base: int = Catalog.WEAPONS[id]["price"]
	return {"kind": Catalog.Offer.WEAPON, "id": id, "tier": tier,
		"price": _price(roundi(base * Catalog.TIER_DAMAGE[tier - 1])), "locked": false}


func _item_offer(tier: int, used: Dictionary, previous: Dictionary) -> Dictionary:
	var excluded := used.duplicate()
	excluded.merge(previous)
	var id := Catalog.pick_item(tier, items, excluded)
	if id < 0:
		id = Catalog.pick_item(tier, items, used)
	if id < 0:
		return {}
	var item: Dictionary = Catalog.ITEMS[id]
	return {"kind": Catalog.Offer.ITEM, "id": id, "tier": item["tier"],
		"price": _price(item["price"]), "locked": false}


func _roll_shop() -> void:
	shop.resize(4)
	var previous: Dictionary = {}
	var used: Dictionary = {}
	var guarantee := 2 if _shop_wave <= 2 else (1 if _shop_wave <= 5 else 0)
	for offer in shop:
		if offer.is_empty():
			continue
		var key := Catalog.offer_key(offer["kind"], offer["id"], offer["tier"])
		previous[key] = true
		if offer["locked"]:
			used[key] = true
			if offer["kind"] == Catalog.Offer.WEAPON:
				guarantee -= 1
	for i in range(4):
		if shop[i] and shop[i]["locked"]:
			continue
		var tier := Balance.roll_tier(_shop_wave, stats[Stat.LUCK], randf())
		var is_weapon := guarantee > 0 or (_shop_wave > 2 and randf() < 0.35)
		var offer := _weapon_offer(tier, used, previous) if is_weapon else _item_offer(tier, used, previous)
		if offer.is_empty():
			offer = _item_offer(tier, used, previous) if is_weapon else _weapon_offer(tier, used, previous)
		shop[i] = offer
		if not offer.is_empty():
			used[Catalog.offer_key(offer["kind"], offer["id"], offer["tier"])] = true
			if offer["kind"] == Catalog.Offer.WEAPON:
				guarantee -= 1


func _shop_has_unlocked_slot() -> bool:
	for offer in shop:
		if offer.is_empty() or not offer["locked"]:
			return true
	return false


func _roll_upgrades() -> void:
	upgrades.clear()
	if pending_levels == 0:
		return
	var stats_pool := Catalog.UPGRADABLE.duplicate()
	stats_pool.shuffle()
	var reward_level := level - pending_levels + 1
	for i in range(4):
		var stat_id: int = stats_pool[i]
		var tier := Balance.upgrade_tier(reward_level, stats[Stat.LUCK], randf())
		upgrades.append({"stat": stat_id, "amount": Catalog.UPGRADE_VALUES[stat_id][tier - 1], "tier": tier})


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
			if materials >= shop_roll_price() and _shop_has_unlocked_slot():
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
	if shop.all(func(entry: Dictionary) -> bool: return entry.is_empty()):
		_roll_shop()
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
			"can_roll_shop": _shop_has_unlocked_slot(),
			"upgrade_roll": upgrade_roll_price(),
		})
	return data
