extends RefCounted

const Balance = preload("res://scripts/game/balance.gd")

enum Phase { LOBBY, WAVE, SHOP, DEFEAT, VICTORY }

const LAST_WAVE := 20
const DURATIONS := [20, 25, 30, 35, 40, 45, 50, 55, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 60, 90]
const DANGER_POWER := [1.0, 1.0, 1.0, 1.12, 1.26, 1.40]
const DANGER_TEXT := ["Standard run with one final boss.", "Adds nest enemies in later waves.",
	"Adds an elite on wave 11.", "Enemies gain 12% health and damage.",
	"Enemies gain 26% health and damage. Adds wave 15 horde and wave 18 elite.",
	"Enemies gain 40% health and damage. Two bosses in the final wave."]

var phase: int = Phase.LOBBY
var danger := 0
var number := 0
var remaining := 0.0
var elapsed := 0.0
var kills := 0
var bag := 0
var ready_count := 0
var tree_in := 0.0
var special_spawned := false
var team_size := 1
var _beat_in := 0.0
var _spawn_credit := 0.0
var _material_credit := 0.0


func begin(players := 1) -> void:
	number += 1
	team_size = clampi(players, 1, Balance.TEAM_LIMIT)
	remaining = DURATIONS[number - 1]
	elapsed = 0.0
	_beat_in = 0.30
	_spawn_credit = 0.0
	tree_in = 10.0
	special_spawned = false
	ready_count = 0
	phase = Phase.WAVE


func advance(delta: float) -> int:
	elapsed += delta
	remaining = maxf(0.0, remaining - delta)
	tree_in -= delta
	_beat_in -= delta
	if _beat_in > 0.0 or remaining <= 0.0:
		return 0
	_beat_in += maxf(0.61, 1.27 - (number - 1) * 0.039)
	var crowd := 1.0 + (number - 1) * 0.115
	if encounter(number) == "HORDE":
		crowd *= 1.40
	_spawn_credit += crowd * Balance.enemy_count_scale(team_size)
	var count := floori(_spawn_credit)
	_spawn_credit -= count
	return count


func encounter(wave: int) -> String:
	if wave == LAST_WAVE:
		return "TWIN BOSSES" if danger == 5 else "FINAL BOSS"
	if (danger >= 2 and wave == 11) or (danger >= 4 and wave == 18):
		return "ELITE"
	if danger >= 4 and wave == 15:
		return "HORDE"
	return ""


func material_drop_chance() -> float:
	var base := 1.0 if number < 5 else 1.0 - number * 0.015
	return base * 0.65 if encounter(number) == "HORDE" else base


func material_value(base: int) -> int:
	# Carry fractional value between drops so single-material enemies scale correctly.
	_material_credit += base * Balance.material_scale(team_size)
	var value := floori(_material_credit + 0.000001)
	_material_credit = maxf(0.0, _material_credit - value)
	return value
