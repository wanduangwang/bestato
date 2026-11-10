extends RefCounted

const TEAM_LIMIT := 4


static func enemy_count_scale(team: int) -> float:
	return 1.0 + (clampi(team, 1, TEAM_LIMIT) - 1) * 0.30


static func enemy_hp_scale(team: int) -> float:
	return enemy_count_scale(team)


static func enemy_damage_scale(team: int) -> float:
	return 1.0 + (clampi(team, 1, TEAM_LIMIT) - 1) * 0.08


static func material_scale(team: int) -> float:
	var size := clampi(team, 1, TEAM_LIMIT)
	# Recover 80% of the per-player income gap left by the spawn multiplier.
	return 1.0 + 0.80 * (size / enemy_count_scale(size) - 1.0)


static func xp_to_next(level: int) -> int:
	var target := level + 4
	return target * target


static func reroll_cost(wave: int, rerolls: int) -> int:
	var step := maxi(1, wave * 40 / 100)
	return wave * 75 / 100 + step * (rerolls + 1)


static func roll_tier(step: int, luck: int, roll: float) -> int:
	var factor := maxf(0.0, 1.0 + luck * 0.01)
	if step >= 8 and roll < minf(0.08, (step - 7) * 0.0023 * factor):
		return 4
	if step >= 4 and roll < minf(0.25, (step - 3) * 0.02 * factor):
		return 3
	if step >= 2 and roll < minf(0.60, (step - 1) * 0.06 * factor):
		return 2
	return 1


static func upgrade_tier(level: int, luck: int, roll: float) -> int:
	if level == 5:
		return 2
	if level >= 10 and level % 5 == 0:
		return 3 if level < 25 else 4
	return roll_tier(level, luck, roll)
