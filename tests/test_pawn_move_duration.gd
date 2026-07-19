extends Node
## Tests de PawnController.compute_segment_duration() — la répartition de la
## durée totale d'un déplacement sur les segments individuels (glissement
## plat, budget quasi-fixe). Fonction pure : pas de Tween/scène 3D nécessaire
## ici, mais PawnController référence l'autoload GameEvents en interne, donc
## ce test doit tourner comme une SCÈNE (pas `--script` bare SceneTree, qui
## n'initialise pas les autoloads) :
##
## Exécution :
##   godot --headless --quit-after 60 res://tests/test_pawn_move_duration.tscn

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("=== Tests PawnController.compute_segment_duration() ===\n")

	test_single_segment_gets_full_budget()
	test_floor_kicks_in_on_long_move()
	test_monotonic_never_slower_than_single_segment()
	test_total_time_grows_little_beyond_floor()

	print("\n=== Résultat : %d PASS / %d FAIL ===" % [_pass_count, _fail_count])
	get_tree().quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % label)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % label)


# ----------------------------------------------------------------------------
func test_single_segment_gets_full_budget() -> void:
	print("-- test_single_segment_gets_full_budget --")
	var d: float = PawnController.compute_segment_duration(0.5, 0.12, 1)
	_assert(is_equal_approx(d, 0.5), "un segment unique reçoit tout le budget (0.5)")


func test_floor_kicks_in_on_long_move() -> void:
	print("-- test_floor_kicks_in_on_long_move (dé de 6, budget/6 < plancher) --")
	var d: float = PawnController.compute_segment_duration(0.5, 0.12, 6)
	_assert(is_equal_approx(d, 0.12), "le plancher (0.12) s'active quand 0.5/6≈0.083 lui est inférieur")


func test_monotonic_never_slower_than_single_segment() -> void:
	print("-- test_monotonic_never_slower_than_single_segment --")
	var single: float = PawnController.compute_segment_duration(0.5, 0.12, 1)
	var all_ok: bool = true
	for n in range(1, 7):
		var d: float = PawnController.compute_segment_duration(0.5, 0.12, n)
		if d > single + 0.0001:
			all_ok = false
	_assert(all_ok, "un trajet plus long n'a jamais un segment individuel plus lent qu'un trajet d'une case")


func test_total_time_grows_little_beyond_floor() -> void:
	print("-- test_total_time_grows_little_beyond_floor --")
	var total_for_6: float = PawnController.compute_segment_duration(0.5, 0.12, 6) * 6
	_assert(is_equal_approx(total_for_6, 0.72), "durée totale pour 6 cases ≈ 0.72s (plancher × 6)")
	_assert(total_for_6 < 6 * 0.35, "reste très inférieur à l'ancien comportement proportionnel (6×0.35=2.1s)")
