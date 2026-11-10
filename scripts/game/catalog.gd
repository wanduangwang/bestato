extends RefCounted

enum Stat { HP, REGEN, STEAL, DAMAGE, MELEE, RANGED, ATTACK, CRIT, ARMOR, DODGE,
	SPEED, REACH, LUCK, HARVEST, MAGNET, ELEMENTAL, PRICE }
enum Pattern { RANGED, MELEE }
enum Offer { WEAPON, ITEM }

const STAT_NAMES := ["Max HP", "HP Regeneration", "Life Steal", "Damage", "Melee Damage",
	"Ranged Damage", "Attack Speed", "Critical Chance", "Armor", "Dodge", "Speed", "Range",
	"Luck", "Harvesting", "Pickup Range", "Elemental Damage", "Shop Prices"]
const PERCENT_STATS := [Stat.STEAL, Stat.DAMAGE, Stat.ATTACK, Stat.CRIT, Stat.DODGE, Stat.SPEED,
	Stat.PRICE]
const UPGRADABLE := [Stat.HP, Stat.REGEN, Stat.STEAL, Stat.DAMAGE, Stat.MELEE, Stat.RANGED,
	Stat.ATTACK, Stat.CRIT, Stat.ARMOR, Stat.DODGE, Stat.SPEED, Stat.REACH, Stat.LUCK,
	Stat.HARVEST, Stat.MAGNET, Stat.ELEMENTAL]
const UPGRADE_BASE := [3, 2, 2, 5, 2, 1, 5, 3, 1, 3, 3, 15, 5, 5, 12, 2]
const TIERS := ["I", "II", "III", "IV"]
const TIER_COLORS := [Color("#e5dbc8"), Color("#7cc4ff"), Color("#d3a1fc"), Color("#ff9882")]
const TIER_DAMAGE := [1.0, 1.35, 1.8, 2.45]
const TIER_COOLDOWN := [1.0, 0.92, 0.83, 0.72]
const SLOT_COUNT := 6
const STARTERS := [0, 1, 2, 4, 6, 7, 8, 9, 11]
const CLASS_BONUSES := {"Gun": [Stat.REACH, 10], "Primitive": [Stat.HP, 2],
	"Blade": [Stat.MELEE, 1], "Precise": [Stat.CRIT, 3], "Unarmed": [Stat.DODGE, 3],
	"Elemental": [Stat.ELEMENTAL, 1], "Explosive": [Stat.DAMAGE, 3]}

const ORIGINS := [
	{"name": "Scrapper", "line": "A little tougher, quicker, and better at gathering.",
		"stats": {Stat.HP: 5, Stat.SPEED: 5, Stat.HARVEST: 5}, "starter": 0},
	{"name": "Lookout", "line": "Ranged weapons only. High range and ranged damage, lower health.",
		"stats": {Stat.HP: -2, Stat.REACH: 75, Stat.RANGED: 3}, "starter": 1,
		"pattern": Pattern.RANGED},
	{"name": "Bruiser", "line": "Melee only. Faster swings, stronger hits and better dodge.",
		"stats": {Stat.MELEE: 3, Stat.ATTACK: 20, Stat.DODGE: 10, Stat.REACH: -30},
		"starter": 7, "pattern": Pattern.MELEE},
	{"name": "Grower", "line": "Harvests extra materials each wave. Slower with weaker hits.",
		"stats": {Stat.HP: 3, Stat.HARVEST: 10, Stat.SPEED: -5, Stat.DAMAGE: -8}, "starter": 4},
]

# Reach is measured in arena units. Ranged patterns have projectile speed; melee patterns have an arc.
const WEAPONS := [
	{"name": "Sidearm", "families": ["Gun"], "price": 10, "damage": 9, "rate": 0.62,
		"reach": 305, "speed": 860, "pierce": 1, "ink": Color("#9eb7c4")},
	{"name": "SMG", "families": ["Gun"], "price": 11, "damage": 3, "rate": 0.19,
		"reach": 270, "speed": 900, "scale": 0.6, "ink": Color("#89aeb1")},
	{"name": "Scattergun", "families": ["Gun"], "price": 13, "damage": 4, "rate": 0.98,
		"reach": 245, "speed": 780, "pellets": 5, "spread": 0.12, "scale": 0.55,
		"ink": Color("#b19784")},
	{"name": "Carbine", "families": ["Gun", "Precise"], "price": 18, "damage": 18, "rate": 0.86,
		"reach": 400, "speed": 1070, "pierce": 2, "min_wave": 3, "ink": Color("#a5a3b7")},
	{"name": "Slingshot", "families": ["Primitive"], "price": 10, "damage": 8, "rate": 0.82,
		"reach": 285, "speed": 720, "bounce": 1, "ink": Color("#d8b77c")},
	{"name": "Shuriken", "families": ["Precise"], "price": 12, "damage": 6, "rate": 0.64,
		"reach": 280, "speed": 690, "bounce": 2, "crit": 12, "ink": Color("#c2baff")},
	{"name": "Knife", "families": ["Blade", "Precise"], "price": 10, "damage": 7, "rate": 0.40,
		"reach": 105, "arc": 0.63, "crit": 12, "ink": Color("#c9d7df")},
	{"name": "Spear", "families": ["Primitive", "Blade"], "price": 12, "damage": 14, "rate": 0.79,
		"reach": 150, "arc": 0.41, "ink": Color("#c8cbe2")},
	{"name": "Cudgel", "families": ["Primitive"], "price": 9, "damage": 12, "rate": 0.83,
		"reach": 112, "arc": 1.00, "ink": Color("#c38c5b")},
	{"name": "Gloves", "families": ["Unarmed"], "price": 9, "damage": 6, "rate": 0.37,
		"reach": 93, "arc": 0.72, "ink": Color("#ff9b78")},
	{"name": "Cleaver", "families": ["Blade"], "price": 16, "damage": 20, "rate": 0.91,
		"reach": 126, "arc": 1.03, "min_wave": 3, "ink": Color("#a9cfdd")},
	{"name": "Spark Wand", "families": ["Elemental"], "price": 13, "damage": 3, "rate": 0.71,
		"reach": 282, "speed": 690, "burn": 3, "pierce": 1, "ink": Color("#ffa65c")},
	{"name": "Rocket Tube", "families": ["Gun", "Explosive"], "price": 28, "damage": 25, "rate": 1.49,
		"reach": 365, "speed": 560, "blast": 83, "min_wave": 6, "ink": Color("#b7c291")},
]

const ITEMS := [
	{"name": "Heavy Vest", "price": 13, "tier": 1, "stats": {Stat.ARMOR: 3, Stat.SPEED: -2}},
	{"name": "Coffee", "price": 11, "tier": 1, "stats": {Stat.ATTACK: 10, Stat.DAMAGE: -2}},
	{"name": "Gym Badge", "price": 11, "tier": 1, "stats": {Stat.HP: 4, Stat.REACH: -8}},
	{"name": "Seed Pouch", "price": 12, "tier": 1, "limit": 4, "stats": {Stat.HARVEST: 7, Stat.MELEE: -1}},
	{"name": "Bandage Roll", "price": 10, "tier": 1, "stats": {Stat.REGEN: 3}},
	{"name": "Running Shoes", "price": 11, "tier": 1, "stats": {Stat.SPEED: 7, Stat.ARMOR: -1}},
	{"name": "Field Lens", "price": 12, "tier": 1, "stats": {Stat.REACH: 35, Stat.ATTACK: -3}},
	{"name": "Lucky Bean", "price": 11, "tier": 1, "limit": 5, "stats": {Stat.LUCK: 8, Stat.CRIT: -2}},
	{"name": "Rubber Soles", "price": 12, "tier": 1, "stats": {Stat.DODGE: 6, Stat.HP: -1}},
	{"name": "Magnet Ring", "price": 11, "tier": 1, "stats": {Stat.MAGNET: 22}},
	{"name": "Training Weight", "price": 12, "tier": 1, "stats": {Stat.MELEE: 3, Stat.SPEED: -2}},
	{"name": "Powder Flask", "price": 13, "tier": 1, "stats": {Stat.RANGED: 2, Stat.DODGE: -3}},
	{"name": "Copper Coil", "price": 12, "tier": 1, "stats": {Stat.ELEMENTAL: 3, Stat.ARMOR: -1}},
	{"name": "Shop Coupon", "price": 13, "tier": 1, "limit": 4, "stats": {Stat.PRICE: -5}},
	{"name": "Serrated Teeth", "price": 19, "tier": 2, "stats": {Stat.STEAL: 6, Stat.REGEN: -1}},
	{"name": "Cracked Scope", "price": 20, "tier": 2, "stats": {Stat.CRIT: 10, Stat.REACH: 20, Stat.SPEED: -3}},
	{"name": "Reactor Cell", "price": 21, "tier": 2, "limit": 3, "stats": {Stat.ATTACK: 16, Stat.HP: -3}},
	{"name": "Packed Lunch", "price": 18, "tier": 2, "limit": 4, "stats": {Stat.HP: 7, Stat.REGEN: 2}},
	{"name": "Lucky Spore", "price": 19, "tier": 2, "limit": 3, "stats": {Stat.LUCK: 15, Stat.HARVEST: 4, Stat.ARMOR: -1}},
	{"name": "Steel Knuckles", "price": 26, "tier": 3, "stats": {Stat.MELEE: 7, Stat.ARMOR: 2, Stat.REACH: -15}},
	{"name": "Glass Core", "price": 27, "tier": 3, "limit": 3, "stats": {Stat.DAMAGE: 28, Stat.HP: -5, Stat.ARMOR: -2}},
	{"name": "Sprout Serum", "price": 29, "tier": 3, "limit": 2, "stats": {Stat.HARVEST: 18, Stat.REGEN: 5}},
	{"name": "Meteor Seed", "price": 38, "tier": 4, "limit": 1, "stats": {Stat.DAMAGE: 32, Stat.ELEMENTAL: 10, Stat.SPEED: -6}},
	{"name": "Titan Shell", "price": 40, "tier": 4, "limit": 1, "stats": {Stat.HP: 15, Stat.ARMOR: 8, Stat.DODGE: -8}},
]


static func pattern(weapon_id: int) -> int:
	return Pattern.MELEE if WEAPONS[weapon_id].has("arc") else Pattern.RANGED


static func allows_weapon(origin: int, weapon_id: int) -> bool:
	if origin < 0 or origin >= ORIGINS.size() or weapon_id < 0 or weapon_id >= WEAPONS.size():
		return false
	return int(ORIGINS[origin].get("pattern", pattern(weapon_id))) == pattern(weapon_id)


static func stat_text(stat_id: int, amount: int) -> String:
	var sign_text := "+" if amount >= 0 else ""
	var suffix := "%" if stat_id in PERCENT_STATS else ""
	return "%s%d%s %s" % [sign_text, amount, suffix, STAT_NAMES[stat_id]]


static func effects_text(effects: Dictionary) -> String:
	var lines := PackedStringArray()
	for stat_id: int in effects:
		lines.append(stat_text(stat_id, effects[stat_id]))
	return "\n".join(lines)


static func item_available(id: int, held: Dictionary) -> bool:
	return int(held.get(id, 0)) < int(ITEMS[id].get("limit", 999))


static func pick_item(tier: int, held: Dictionary = {}) -> int:
	for rarity in range(tier, 0, -1):
		var pool: Array[int] = []
		for id in range(ITEMS.size()):
			if ITEMS[id]["tier"] == rarity and item_available(id, held):
				pool.append(id)
		if not pool.is_empty():
			return pool.pick_random()
	return 0
