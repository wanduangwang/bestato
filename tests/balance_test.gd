extends SceneTree

const Balance = preload("res://scripts/game/balance.gd")
const Build = preload("res://scripts/game/build.gd")
const Catalog = preload("res://scripts/game/catalog.gd")
const Waves = preload("res://scripts/game/waves.gd")
const Stat = Catalog.Stat

var _failures := 0


func _initialize() -> void:
	seed(132)
	_test_coop()
	_test_progression()
	_test_shop()
	if _failures == 0:
		print("PASS: co-op budgets, XP thresholds, stock guarantees, price locks and refreshes.")
	quit(0 if _failures == 0 else 1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _test_coop() -> void:
	var first_wave_counts := [16, 20, 25, 30]
	for team in range(1, 5):
		var waves := Waves.new()
		waves.begin(team)
		var spawned := 0
		for tick in range(20 * 60):
			spawned += waves.advance(1.0 / 60.0)
		_expect(spawned == first_wave_counts[team - 1], "Unexpected first-wave spawn budget.")
		var drop_total := 0
		for i in range(1000):
			drop_total += waves.material_value(1)
		_expect(absf(drop_total - Balance.material_scale(team) * 1000) <= 1.0,
				"Repeated rounding distorted materials from single-value enemies.")
		var relative_income := Balance.enemy_count_scale(team) * Balance.material_scale(team) / team
		_expect(is_equal_approx(relative_income, [1.0, 0.93, 0.9066666667, 0.895][team - 1]),
				"Co-op per-player income ratio changed.")
	_expect(is_equal_approx(Balance.enemy_hp_scale(4), 1.9), "Four-player health multiplier changed.")
	_expect(is_equal_approx(Balance.enemy_damage_scale(4), 1.24), "Four-player damage multiplier changed.")


func _test_progression() -> void:
	var build := Build.new()
	build.configure(0, 0)
	var start_hp := build.stats[Stat.HP]
	_expect(build.level == 0 and build.xp_goal() == 16, "Incorrect starting XP threshold.")
	_expect(build.earn(15) == 0 and build.earn(1) == 1, "Level-up fired at the wrong threshold.")
	_expect(build.stats[Stat.HP] == start_hp + 1 and build.xp_goal() == 25, "Level-up missed its HP gain.")
	_expect(build.earn(26) == 1 and build.xp == 1 and build.pending_levels == 2, "XP did not carry over.")
	_expect(Balance.upgrade_tier(5, 500, 0.0) == 2 and Balance.upgrade_tier(20, 500, 0.0) == 3
			and Balance.upgrade_tier(25, 0, 0.99) == 4, "A milestone upgrade used the wrong tier.")
	_expect(Balance.roll_tier(1, 500, 0.0) == 1 and Balance.roll_tier(4, 0, 0.0) == 3
			and Balance.roll_tier(8, 0, 0.0) == 4, "Shop rarity opened at the wrong wave.")
	_expect(Catalog.class_bonus("Primitive", 6)[Stat.HP] == 15
			and Catalog.class_bonus("Blade", 2)[Stat.STEAL] == 1, "Set bonuses changed.")


func _test_shop() -> void:
	var build := Build.new()
	build.configure(2, 7)
	build.finish_wave(1)
	var weapon_count := 0
	for offer in build.shop:
		if offer["kind"] == Catalog.Offer.WEAPON:
			weapon_count += 1
			_expect(Catalog.allows_weapon(build.origin, offer["id"]), "A restricted weapon was offered.")
	_expect(weapon_count == 2, "The first shop needs two weapons and two items.")
	_expect(build.shop_roll_price() == 1 and Balance.reroll_cost(5, 1) == 7, "Wrong reroll price.")
	build.materials = 250
	build.apply_shop_action(Build.Action.LOCK, 0)
	var locked := build.shop[0].duplicate()
	_expect(build.apply_shop_action(Build.Action.SHOP_ROLL, -1), "Reroll was not accepted.")
	_expect(build.shop[0] == locked, "Reroll changed locked stock.")
	build.finish_wave(2)
	_expect(build.shop[0] == locked, "Inflation changed a locked price.")
	var keys: Dictionary = {}
	for offer in build.shop:
		var key := Catalog.offer_key(offer["kind"], offer["id"], offer["tier"])
		_expect(not keys.has(key), "A shop contains duplicate stock.")
		keys[key] = true
	for slot in range(1, 4):
		build.apply_shop_action(Build.Action.LOCK, slot)
	var materials := build.materials
	_expect(not build.apply_shop_action(Build.Action.SHOP_ROLL, -1) and build.materials == materials,
			"A fully locked shop charged for a reroll.")
	for slot in range(4):
		_expect(build.apply_shop_action(Build.Action.BUY, slot), "Could not buy available stock.")
	_expect(build.shop.all(func(offer: Dictionary) -> bool: return not offer.is_empty())
			and build.shop_rolls == 0, "Buying out the shop did not restock for free.")
