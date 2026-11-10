extends RefCounted

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
var _beat_in := 0.0
var _spawn_credit := 0.0


func begin() -> void:
	number += 1
	remaining = DURATIONS[number - 1]
	elapsed = 0.0
	_beat_in = 0.30
	_spawn_credit = 0.0
	tree_in = 4.0
	special_spawned = false
	ready_count = 0
	phase = Phase.WAVE


func advance(delta: float, player_count: int) -> int:
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
	_spawn_credit += crowd * (1.0 + (player_count - 1) * 0.30)
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
