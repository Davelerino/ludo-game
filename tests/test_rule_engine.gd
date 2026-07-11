extends SceneTree
## ============================================================================
## Tests unitaires du RuleEngine — SANS rendu 3D (GDD §11.7).
##
## Copie conforme du harnais de test original, placée dans res://tests/.
## Le RuleEngine est un ensemble de fonctions pures : ces tests ne dépendent
## d'aucune scène 3D, GridMap ou asset.
##
## Exécution :
##   godot --headless --script res://tests/test_rule_engine.gd
## ============================================================================

const PawnState := BoardConfig.PawnState

var _pass_count: int = 0
var _fail_count: int = 0


func _init() -> void:
	print("=== Tests RuleEngine (Ludo 3D) ===\n")

	test_entry_requires_six()
	test_entry_blocked_by_enemy_barrier()
	test_entry_captures_lone_enemy()
	test_transit_blocked_by_enemy_barrier()
	test_transit_blocked_by_ally_barrier()
	test_landing_on_enemy_barrier_illegal()
	test_landing_on_ally_barrier_legal()
	test_capture_on_ring()
	test_no_capture_on_ally_stack_forms_barrier()
	test_captured_pawn_needs_six_to_escape()
	test_captured_pawn_escapes_on_six()
	test_home_lane_entry()
	test_home_lane_overshoot_illegal()
	test_home_lane_exact_finish()
	test_no_barrier_effect_in_home_lane()
	test_victory_detection()

	print("\n=== Résultat : %d PASS / %d FAIL ===" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % label)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % label)

func _pawn_ring(id: int, player: int, progress: int) -> Dictionary:
	return {"id": id, "player": player, "state": PawnState.RING, "progress": progress, "captor_id": -1}

func _pawn_yard(id: int, player: int) -> Dictionary:
	return BoardConfig.create_pawn(id, player)

func _pawn_captured(id: int, player: int, captor_id: int) -> Dictionary:
	return {"id": id, "player": player, "state": PawnState.CAPTURED, "progress": -1, "captor_id": captor_id}


# ----------------------------------------------------------------------------
func test_entry_requires_six() -> void:
	print("-- test_entry_requires_six (§4.2, L4) --")
	var pawn: Dictionary = _pawn_yard(0, 0)
	var all_pawns: Array = [pawn]
	_assert(not RuleEngine.try_move(pawn, 5, all_pawns).legal, "un 5 ne permet pas de sortir du yard")
	_assert(RuleEngine.try_move(pawn, 6, all_pawns).legal, "un 6 permet de sortir du yard")
	_assert(RuleEngine.try_move(pawn, 6, all_pawns).new_progress == 0, "sortie du yard -> progress=0")


func test_entry_blocked_by_enemy_barrier() -> void:
	print("-- test_entry_blocked_by_enemy_barrier (B1/B2) --")
	var entering: Dictionary = _pawn_yard(0, 0)
	var enemy_a: Dictionary = _pawn_ring(10, 1, 39)
	var enemy_b: Dictionary = _pawn_ring(11, 1, 39)
	_assert(not RuleEngine.try_move(entering, 6, [entering, enemy_a, enemy_b]).legal,
		"l'entrée est bloquée par la barrière ennemie sur la start tile")


func test_entry_captures_lone_enemy() -> void:
	print("-- test_entry_captures_lone_enemy (§8.2) --")
	var entering: Dictionary = _pawn_yard(0, 0)
	var lone_enemy: Dictionary = _pawn_ring(10, 1, 39)
	var r: Dictionary = RuleEngine.apply_move(entering, 6, [entering, lone_enemy])
	_assert(r.legal and r.capture, "l'entrée capture le pion adverse isolé")
	_assert(lone_enemy.state == PawnState.CAPTURED and lone_enemy.captor_id == entering.player,
		"le pion capturé va dans la zone de capture du capteur")


func test_transit_blocked_by_enemy_barrier() -> void:
	print("-- test_transit_blocked_by_enemy_barrier (B1/B2) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var eb1: Dictionary = _pawn_ring(11, 1, (2 - 13 + 52) % 52)
	var eb2: Dictionary = _pawn_ring(12, 1, (2 - 13 + 52) % 52)
	_assert(not RuleEngine.try_move(mover, 4, [mover, eb1, eb2]).legal,
		"le transit à travers une barrière ennemie est interdit")


func test_transit_blocked_by_ally_barrier() -> void:
	print("-- test_transit_blocked_by_ally_barrier (B6, transit) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var a1: Dictionary = _pawn_ring(1, 0, 2)
	var a2: Dictionary = _pawn_ring(2, 0, 2)
	_assert(not RuleEngine.try_move(mover, 4, [mover, a1, a2]).legal,
		"une barrière alliée bloque aussi le TRANSIT")


func test_landing_on_enemy_barrier_illegal() -> void:
	print("-- test_landing_on_enemy_barrier_illegal (B2) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var e1: Dictionary = _pawn_ring(10, 1, (3 - 13 + 52) % 52)
	var e2: Dictionary = _pawn_ring(11, 1, (3 - 13 + 52) % 52)
	_assert(not RuleEngine.try_move(mover, 3, [mover, e1, e2]).legal,
		"atterrir sur une barrière ennemie est interdit")


func test_landing_on_ally_barrier_legal() -> void:
	print("-- test_landing_on_ally_barrier_legal (B6) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var a1: Dictionary = _pawn_ring(1, 0, 3)
	var a2: Dictionary = _pawn_ring(2, 0, 3)
	var r: Dictionary = RuleEngine.try_move(mover, 3, [mover, a1, a2])
	_assert(r.legal and r.forms_barrier and not r.capture,
		"atterrir sur sa propre barrière est autorisé et renforce la barrière")


func test_capture_on_ring() -> void:
	print("-- test_capture_on_ring (§8.1) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var lone_enemy: Dictionary = _pawn_ring(10, 1, (5 - 13 + 52) % 52)
	var r: Dictionary = RuleEngine.apply_move(mover, 5, [mover, lone_enemy])
	_assert(r.legal and r.capture and lone_enemy.state == PawnState.CAPTURED and lone_enemy.captor_id == mover.player,
		"capture d'un pion adverse seul sur la ring lane -> zone de capture du capteur")


func test_no_capture_on_ally_stack_forms_barrier() -> void:
	print("-- test_no_capture_on_ally_stack_forms_barrier (B4) --")
	var mover: Dictionary = _pawn_ring(0, 0, 0)
	var ally: Dictionary = _pawn_ring(1, 0, 5)
	var r: Dictionary = RuleEngine.apply_move(mover, 5, [mover, ally])
	_assert(r.legal and not r.capture and r.forms_barrier,
		"rejoindre un allié forme une barrière (pas de capture)")


func test_captured_pawn_needs_six_to_escape() -> void:
	print("-- test_captured_pawn_needs_six_to_escape --")
	var pawn: Dictionary = _pawn_captured(0, 0, 1)
	var r: Dictionary = RuleEngine.try_move(pawn, 3, [pawn])
	_assert(not r.legal and r.reason == "needs_six_to_escape_capture",
		"un dé autre que 6 ne libère pas un pion capturé")


func test_captured_pawn_escapes_on_six() -> void:
	print("-- test_captured_pawn_escapes_on_six --")
	var pawn: Dictionary = _pawn_captured(0, 0, 1)
	var r: Dictionary = RuleEngine.apply_move(pawn, 6, [pawn])
	_assert(r.legal, "un 6 libère un pion capturé")
	_assert(pawn.state == PawnState.MAISON and pawn.progress == -1,
		"le pion évadé retourne dans son propre yard (pas directement sur l'anneau)")
	_assert(pawn.captor_id == -1, "captor_id est réinitialisé après évasion")


func test_home_lane_entry() -> void:
	print("-- test_home_lane_entry (§7.2, L5) --")
	var pawn: Dictionary = _pawn_ring(0, 0, 49)
	var r: Dictionary = RuleEngine.apply_move(pawn, 4, [pawn])
	_assert(r.legal and r.enters_home and pawn.state == PawnState.HOME_LANE,
		"le pion diverge dans sa home lane")
	_assert(RuleEngine.get_home_lane_index(pawn) == 2, "index local home lane correct (2)")


func test_home_lane_overshoot_illegal() -> void:
	print("-- test_home_lane_overshoot_illegal (H4, L9) --")
	var pawn: Dictionary = _pawn_ring(0, 0, 54)
	pawn.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.try_move(pawn, 5, [pawn])
	_assert(not r.legal and r.reason == "overshoot_home_center",
		"un dé qui dépasserait le centre est refusé (H4)")


func test_home_lane_exact_finish() -> void:
	print("-- test_home_lane_exact_finish (H1, H5) --")
	var pawn: Dictionary = _pawn_ring(0, 0, 54)
	pawn.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.apply_move(pawn, 2, [pawn])
	_assert(r.legal and r.finishes and pawn.state == PawnState.FINI,
		"atterrissage exact sur le centre = pion FINI")


func test_no_barrier_effect_in_home_lane() -> void:
	print("-- test_no_barrier_effect_in_home_lane (§7.5) --")
	var mover: Dictionary = _pawn_ring(0, 0, 52)
	mover.state = PawnState.HOME_LANE
	var ally_blocker: Dictionary = _pawn_ring(1, 0, 53)
	ally_blocker.state = PawnState.HOME_LANE
	_assert(RuleEngine.try_move(mover, 1, [mover, ally_blocker]).legal,
		"aucune barrière ne s'applique en home lane")


func test_victory_detection() -> void:
	print("-- test_victory_detection (§2.3, L12) --")
	var all_pawns: Array = []
	for i in range(4):
		var p: Dictionary = _pawn_ring(i, 0, 56)
		p.state = PawnState.FINI
		all_pawns.append(p)
	_assert(RuleEngine.has_player_won(0, all_pawns), "le joueur 0 a 4 pions FINI")
	_assert(RuleEngine.check_victory(all_pawns) == 0, "check_victory retourne le joueur 0")
