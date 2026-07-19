extends Node
## Tests de PawnController.compute_segment_duration() — la répartition de la
## durée totale d'un déplacement sur les segments individuels, dans les deux
## modes coexistant pendant le bêta-test (BoardTuning.MoveDurationMode).
## Fonction pure : pas de Tween/scène 3D nécessaire ici, mais PawnController
## référence l'autoload GameEvents en interne, donc ce test doit tourner
## comme une SCÈNE (pas `--script` bare SceneTree, qui n'initialise pas les
## autoloads) :
##
## Exécution :
##   godot --headless --quit-after 60 res://tests/test_pawn_move_duration.tscn

const FIXED_TOTAL := BoardTuning.MoveDurationMode.FIXED_TOTAL
const PROPORTIONAL := BoardTuning.MoveDurationMode.PROPORTIONAL

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("=== Tests PawnController.compute_segment_duration() ===\n")

	test_single_segment_gets_full_budget()
	test_floor_kicks_in_on_long_move()
	test_monotonic_never_slower_than_single_segment()
	test_total_time_grows_little_beyond_floor()
	test_proportional_mode_is_constant_per_cell()

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
# Mode FIXED_TOTAL (durée quasi-fixe, budget réparti + plancher)
# ----------------------------------------------------------------------------
func test_single_segment_gets_full_budget() -> void:
	print("-- test_single_segment_gets_full_budget (FIXED_TOTAL) --")
	var d: float = PawnController.compute_segment_duration(FIXED_TOTAL, 0.5, 0.12, 0.35, 1)
	_assert(is_equal_approx(d, 0.5), "un segment unique reçoit tout le budget (0.5)")


func test_floor_kicks_in_on_long_move() -> void:
	print("-- test_floor_kicks_in_on_long_move (FIXED_TOTAL, dé de 6, budget/6 < plancher) --")
	var d: float = PawnController.compute_segment_duration(FIXED_TOTAL, 0.5, 0.12, 0.35, 6)
	_assert(is_equal_approx(d, 0.12), "le plancher (0.12) s'active quand 0.5/6≈0.083 lui est inférieur")


func test_monotonic_never_slower_than_single_segment() -> void:
	print("-- test_monotonic_never_slower_than_single_segment (FIXED_TOTAL) --")
	var single: float = PawnController.compute_segment_duration(FIXED_TOTAL, 0.5, 0.12, 0.35, 1)
	var all_ok: bool = true
	for n in range(1, 7):
		var d: float = PawnController.compute_segment_duration(FIXED_TOTAL, 0.5, 0.12, 0.35, n)
		if d > single + 0.0001:
			all_ok = false
	_assert(all_ok, "un trajet plus long n'a jamais un segment individuel plus lent qu'un trajet d'une case")


func test_total_time_grows_little_beyond_floor() -> void:
	print("-- test_total_time_grows_little_beyond_floor (FIXED_TOTAL) --")
	var total_for_6: float = PawnController.compute_segment_duration(FIXED_TOTAL, 0.5, 0.12, 0.35, 6) * 6
	_assert(is_equal_approx(total_for_6, 0.72), "durée totale pour 6 cases ≈ 0.72s (plancher × 6)")
	_assert(total_for_6 < 6 * 0.35, "reste très inférieur à l'ancien comportement proportionnel (6×0.35=2.1s)")


# ----------------------------------------------------------------------------
# Mode PROPORTIONAL (durée d'origine : chaque case ajoute une durée fixe)
# ----------------------------------------------------------------------------
func test_proportional_mode_is_constant_per_cell() -> void:
	print("-- test_proportional_mode_is_constant_per_cell (PROPORTIONAL) --")
	var d1: float = PawnController.compute_segment_duration(PROPORTIONAL, 0.5, 0.12, 0.35, 1)
	var d6: float = PawnController.compute_segment_duration(PROPORTIONAL, 0.5, 0.12, 0.35, 6)
	_assert(is_equal_approx(d1, 0.35) and is_equal_approx(d6, 0.35),
		"la durée par segment est toujours duration_per_cell (0.35), quel que soit le nombre de cases")
	_assert(is_equal_approx(d6 * 6, 2.1),
		"durée totale pour 6 cases = 6 × 0.35 = 2.1s (proportionnel, contrairement à FIXED_TOTAL)")
