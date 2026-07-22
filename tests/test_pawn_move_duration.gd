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
	test_stack_slot_identity_when_no_stacking_or_no_tuning()
	test_stack_slot_two_pawns_get_distinct_slots()
	test_stack_slot_three_and_four_pawns_match_tuning_tables()

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


# ----------------------------------------------------------------------------
# PawnController.compute_stack_slot() — décalage/échelle d'empilement (§6/H3)
# ----------------------------------------------------------------------------
func test_stack_slot_identity_when_no_stacking_or_no_tuning() -> void:
	print("-- test_stack_slot_identity_when_no_stacking_or_no_tuning --")
	var tuning := BoardTuning.new()

	var single: Dictionary = PawnController.compute_stack_slot(0, [{"id": 0}], tuning)
	_assert(single.offset == Vector3.ZERO and is_equal_approx(single.scale, 1.0),
		"un seul pion sur la case -> pas d'offset, échelle 1.0 (aucune régression du cas courant)")

	var empty_group: Dictionary = PawnController.compute_stack_slot(0, [], tuning)
	_assert(empty_group.offset == Vector3.ZERO and is_equal_approx(empty_group.scale, 1.0),
		"groupe vide -> identité (défensif)")

	var no_tuning: Dictionary = PawnController.compute_stack_slot(0, [{"id": 0}, {"id": 1}], null)
	_assert(no_tuning.offset == Vector3.ZERO and is_equal_approx(no_tuning.scale, 1.0),
		"tuning == null -> toujours l'identité, même avec 2 pions (fallback défensif)")


func test_stack_slot_two_pawns_get_distinct_slots() -> void:
	print("-- test_stack_slot_two_pawns_get_distinct_slots --")
	var tuning := BoardTuning.new()
	var cell_pawns: Array = [{"id": 2}, {"id": 5}]  # déjà trié par id, comme le garantit RuleEngine.get_stack_at()

	var slot_low: Dictionary = PawnController.compute_stack_slot(2, cell_pawns, tuning)
	var slot_high: Dictionary = PawnController.compute_stack_slot(5, cell_pawns, tuning)

	_assert(slot_low.offset == tuning.stack_offsets_2[0], "le pion au 1er rang du groupe reçoit le 1er offset de la table")
	_assert(slot_high.offset == tuning.stack_offsets_2[1], "le pion au 2e rang du groupe reçoit le 2e offset de la table")
	_assert(slot_low.offset != slot_high.offset, "les deux pions reçoivent des offsets distincts (pas de superposition)")
	_assert(is_equal_approx(slot_low.scale, tuning.stack_scale_2) and is_equal_approx(slot_high.scale, tuning.stack_scale_2),
		"les deux pions du groupe partagent la même échelle réduite (stack_scale_2)")


func test_stack_slot_three_and_four_pawns_match_tuning_tables() -> void:
	print("-- test_stack_slot_three_and_four_pawns_match_tuning_tables --")
	var tuning := BoardTuning.new()

	var group3: Array = [{"id": 0}, {"id": 1}, {"id": 2}]
	for i in range(group3.size()):
		var slot: Dictionary = PawnController.compute_stack_slot(group3[i].id, group3, tuning)
		_assert(slot.offset == tuning.stack_offsets_3[i], "groupe de 3 : le pion au rang %d reçoit stack_offsets_3[%d]" % [i, i])
		_assert(is_equal_approx(slot.scale, tuning.stack_scale_3), "groupe de 3 : échelle = stack_scale_3")

	var group4: Array = [{"id": 0}, {"id": 1}, {"id": 2}, {"id": 3}]
	for i in range(group4.size()):
		var slot: Dictionary = PawnController.compute_stack_slot(group4[i].id, group4, tuning)
		_assert(slot.offset == tuning.stack_offsets_4[i], "groupe de 4 : le pion au rang %d reçoit stack_offsets_4[%d]" % [i, i])
		_assert(is_equal_approx(slot.scale, tuning.stack_scale_4), "groupe de 4 : échelle = stack_scale_4")
