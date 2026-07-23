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
	test_home_lane_transit_blocked_by_own_barrier()
	test_home_lane_landing_forms_barrier()
	test_home_lane_pawn_can_leave_own_barrier()
	test_home_lane_finish_never_forms_barrier()
	test_victory_detection()
	test_has_any_legal_move_over_pool()
	test_find_wasted_die_id_single_casualty()
	test_find_wasted_die_id_no_conflict()
	test_find_wasted_die_id_ambiguous_multi_casualty()
	test_combined_move_avoids_capture_on_ring()
	test_combined_move_blocked_falls_back()
	test_combined_yard_exit_avoids_capture()
	test_combined_yard_exit_blocked_by_barrier_falls_back()
	test_combined_move_overshoot_illegal()
	test_combined_yard_exit_blocked_by_ally_barrier_on_start_tile()
	test_get_stack_at_groups_ring_allies_sorted_by_id()
	test_get_stack_at_home_lane_groups_only_same_player()
	test_get_stack_at_single_pawn_and_non_ring_home_lane_states()

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


func test_home_lane_transit_blocked_by_own_barrier() -> void:
	print("-- test_home_lane_transit_blocked_by_own_barrier (barrière en home lane, transit) --")
	var mover: Dictionary = _pawn_ring(0, 0, 51)
	mover.state = PawnState.HOME_LANE
	var blocker_a: Dictionary = _pawn_ring(1, 0, 53)
	blocker_a.state = PawnState.HOME_LANE
	var blocker_b: Dictionary = _pawn_ring(2, 0, 53)
	blocker_b.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.try_move(mover, 3, [mover, blocker_a, blocker_b])
	_assert(not r.legal and r.reason == "path_blocked_by_barrier",
		"une barrière alliée (2 pions) sur une case intermédiaire de home lane bloque le transit")


func test_home_lane_landing_forms_barrier() -> void:
	print("-- test_home_lane_landing_forms_barrier (atterrissage forme une barrière) --")
	var mover: Dictionary = _pawn_ring(0, 0, 51)
	mover.state = PawnState.HOME_LANE
	var ally: Dictionary = _pawn_ring(1, 0, 53)
	ally.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.try_move(mover, 2, [mover, ally])
	_assert(r.legal and not r.capture and r.forms_barrier,
		"atterrir sur la case d'un allié en home lane est autorisé et forme une barrière")


func test_home_lane_pawn_can_leave_own_barrier() -> void:
	print("-- test_home_lane_pawn_can_leave_own_barrier --")
	var stacked_a: Dictionary = _pawn_ring(0, 0, 53)
	stacked_a.state = PawnState.HOME_LANE
	var stacked_b: Dictionary = _pawn_ring(1, 0, 53)
	stacked_b.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.try_move(stacked_a, 1, [stacked_a, stacked_b])
	_assert(r.legal, "un pion peut toujours avancer depuis sa propre case, même s'il y forme une barrière")


func test_home_lane_finish_never_forms_barrier() -> void:
	print("-- test_home_lane_finish_never_forms_barrier --")
	var finished_a: Dictionary = _pawn_ring(1, 0, BoardConfig.FINISH_PROGRESS)
	finished_a.state = PawnState.FINI
	var finished_b: Dictionary = _pawn_ring(2, 0, BoardConfig.FINISH_PROGRESS)
	finished_b.state = PawnState.FINI
	var mover: Dictionary = _pawn_ring(0, 0, 55)
	mover.state = PawnState.HOME_LANE
	var r: Dictionary = RuleEngine.try_move(mover, 1, [mover, finished_a, finished_b])
	_assert(r.legal and r.finishes and not r.forms_barrier,
		"la case FINI (progress 56) n'est jamais comptée comme une barrière de home lane")


func test_victory_detection() -> void:
	print("-- test_victory_detection (§2.3, L12) --")
	var all_pawns: Array = []
	for i in range(4):
		var p: Dictionary = _pawn_ring(i, 0, 56)
		p.state = PawnState.FINI
		all_pawns.append(p)
	_assert(RuleEngine.has_player_won(0, all_pawns), "le joueur 0 a 4 pions FINI")
	_assert(RuleEngine.check_victory(all_pawns, [0, 1, 2, 3]) == 0, "check_victory retourne le joueur 0")


# ----------------------------------------------------------------------------
# Pool de dés généralisé à N dés (has_any_legal_move) + filet anti-gâchis
# manuel (find_wasted_die_id, §8 de rule_engine.gd)
# ----------------------------------------------------------------------------

func test_has_any_legal_move_over_pool() -> void:
	print("-- test_has_any_legal_move_over_pool (généralisé à un Array de valeurs) --")
	var mover: Dictionary = _pawn_ring(0, 0, 5)
	var all_pawns: Array = [mover, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]
	_assert(RuleEngine.has_any_legal_move(0, all_pawns, [6, 6, 4, 2], []),
		"au moins un dé du pool (4 valeurs, avec doublons) offre un coup légal")
	_assert(RuleEngine.has_any_legal_move(0, all_pawns, [4, 4, 4, 4], []),
		"un pool où toutes les valeurs sont identiques (double réel) est géré sans erreur")

	var stuck: Dictionary = _pawn_ring(0, 0, 55)
	stuck.state = PawnState.HOME_LANE
	var stuck_pawns: Array = [stuck, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]
	_assert(not RuleEngine.has_any_legal_move(0, stuck_pawns, [5, 4, 3], []),
		"aucun dé du pool n'offre de coup légal (overshoot en home lane, yard bloqué sans 6)")


func test_find_wasted_die_id_single_casualty() -> void:
	print("-- test_find_wasted_die_id_single_casualty (un seul dé gâché -> id retourné) --")
	# mover (joueur 0) progress=10. Jouer chosen_value=4 capture l'ennemi seul
	# en ring 14 -> mover verrouillé (§8.3/L10) -> plus aucun pion pour la
	# valeur 3 (les autres pions du joueur 0 sont au yard, besoin d'un 6).
	var mover: Dictionary = _pawn_ring(0, 0, 10)
	var enemy: Dictionary = _pawn_ring(10, 1, 1)  # ring_index (13+1)%52 = 14
	var all_pawns: Array = [mover, enemy, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]

	var wasted_id: int = RuleEngine.find_wasted_die_id(0, all_pawns, mover.id, 4, [{"id": 1, "value": 3}], [])
	_assert(wasted_id == 1, "jouer le dé 4 sur mover gâcherait le dé id=1 (valeur 3) -> son id est retourné")


func test_find_wasted_die_id_no_conflict() -> void:
	print("-- test_find_wasted_die_id_no_conflict (pas de capture, pas de conflit) --")
	# Aucune capture possible ici : jouer 4 sur mover ne le verrouille pas, il
	# reste candidat pour jouer 3 ensuite -> rien n'est gâché.
	var mover: Dictionary = _pawn_ring(0, 0, 5)
	var all_pawns: Array = [mover, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]

	var wasted_id: int = RuleEngine.find_wasted_die_id(0, all_pawns, mover.id, 4, [{"id": 1, "value": 3}], [])
	_assert(wasted_id == -1, "aucun dé n'est gâché : le mouvement combiné n'est pas nécessaire")


func test_find_wasted_die_id_ambiguous_multi_casualty() -> void:
	print("-- test_find_wasted_die_id_ambiguous_multi_casualty (2 dés gâchés à la fois -> -1) --")
	# Même mise en place que test_find_wasted_die_id_single_casualty, mais
	# avec un pool élargi à 3 dés (4, 3, 5) : jouer 4 verrouille mover et
	# gâche À LA FOIS le dé 3 ET le dé 5 (aucun autre pion ne les joue).
	# Cas ambigu : on ne devine pas lequel sauver via un mouvement combiné à
	# 2 dés seulement -> -1, comportement normal (la perte est acceptée).
	var mover: Dictionary = _pawn_ring(0, 0, 10)
	var enemy: Dictionary = _pawn_ring(10, 1, 1)  # ring_index (13+1)%52 = 14
	var all_pawns: Array = [mover, enemy, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]

	var other_dice: Array = [{"id": 1, "value": 3}, {"id": 2, "value": 5}]
	var wasted_id: int = RuleEngine.find_wasted_die_id(0, all_pawns, mover.id, 4, other_dice, [])
	_assert(wasted_id == -1, "deux dés seraient gâchés simultanément -> cas ambigu, pas d'auto-combine")


# ----------------------------------------------------------------------------
# Mouvement combiné (RuleEngine.try_combined_move / apply_combined_move)
# ----------------------------------------------------------------------------

func test_combined_move_avoids_capture_on_ring() -> void:
	print("-- test_combined_move_avoids_capture_on_ring (filet anti-gâchis : mouvement combiné) --")
	# Jouer les dés 4 et 3 séparément mènerait chacun à une capture qui
	# verrouillerait le seul mover — MAIS fusionner les deux dés en un seul
	# mouvement (10 -> 17) évite les deux captures : les ennemis en 14 et 13
	# ne sont que traversés, pas atterris dessus.
	var mover: Dictionary = _pawn_ring(0, 0, 10)
	var enemy_a: Dictionary = _pawn_ring(10, 1, 1)   # ring_index (13+1)%52 = 14 (atteint par le dé 4 seul)
	var enemy_b: Dictionary = _pawn_ring(11, 2, 39)  # ring_index (26+39)%52 = 13 (atteint par le dé 3 seul)
	var all_pawns: Array = [mover, enemy_a, enemy_b, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]

	var preview: Dictionary = RuleEngine.try_combined_move(mover, 4, 3, all_pawns)
	_assert(preview.legal and preview.new_progress == 17 and not preview.capture,
		"le mouvement combiné atterrit en progress 17 sans capturer aucun des deux ennemis traversés")

	var result: Dictionary = RuleEngine.apply_combined_move(mover, 4, 3, all_pawns)
	_assert(result.legal and mover.progress == 17, "apply_combined_move déplace bien mover jusqu'à progress 17")
	_assert(enemy_a.state == PawnState.RING and enemy_b.state == PawnState.RING,
		"les deux ennemis traversés restent RING (non capturés)")


func test_combined_move_blocked_falls_back() -> void:
	print("-- test_combined_move_blocked_falls_back --")
	# Même mise en place que ci-dessus, MAIS une barrière ennemie occupe
	# exactement la case d'arrivée du mouvement combiné (ring 17, joueur 3) :
	# le mouvement combiné échoue -> repli sur un coup normal (perte d'un dé
	# acceptée, voir find_wasted_die_id_ambiguous / no auto-combine possible).
	var mover: Dictionary = _pawn_ring(0, 0, 10)
	var enemy_a: Dictionary = _pawn_ring(10, 1, 1)   # ring 14
	var enemy_b: Dictionary = _pawn_ring(11, 2, 39)  # ring 13
	var barrier_a: Dictionary = _pawn_ring(12, 3, 30)  # ring_index (39+30)%52 = 17
	var barrier_b: Dictionary = _pawn_ring(13, 3, 30)  # idem -> barrière à 2 pions en 17
	var all_pawns: Array = [mover, enemy_a, enemy_b, barrier_a, barrier_b, _pawn_yard(1, 0), _pawn_yard(2, 0), _pawn_yard(3, 0)]

	var preview: Dictionary = RuleEngine.try_combined_move(mover, 4, 3, all_pawns)
	_assert(not preview.legal, "le mouvement combiné est bloqué par la barrière ennemie sur la case d'arrivée (ring 17)")


func test_combined_yard_exit_avoids_capture() -> void:
	print("-- test_combined_yard_exit_avoids_capture (sortie de Maison combinée) --")
	# mover sort avec le 6 puis continue de 3 cases (au lieu de s'arrêter et
	# capturer sur sa propre start tile) : atterrit en progress 3, l'ennemi
	# sur la start tile n'est que traversé.
	var mover: Dictionary = _pawn_yard(0, 0)
	var enemy: Dictionary = _pawn_ring(10, 1, 39)  # ring_index (13+39)%52 = 0 = start tile du joueur 0
	var all_pawns: Array = [mover, enemy]

	var preview: Dictionary = RuleEngine.try_combined_move(mover, 3, 6, all_pawns)
	_assert(preview.legal and preview.new_progress == 3 and not preview.capture,
		"mover atterrit en progress 3 (continuation), sans capturer l'ennemi de la start tile")

	var result: Dictionary = RuleEngine.apply_combined_move(mover, 3, 6, all_pawns)
	_assert(result.legal and mover.state == PawnState.RING and mover.progress == 3,
		"apply_combined_move place mover en RING, progress 3")
	_assert(enemy.state == PawnState.RING, "l'ennemi de la start tile n'est pas capturé (juste traversé)")


func test_combined_yard_exit_blocked_by_barrier_falls_back() -> void:
	print("-- test_combined_yard_exit_blocked_by_barrier_falls_back --")
	# Une barrière ennemie sur le chemin de continuation (ring 1) bloque le
	# mouvement combiné : repli sur le comportement normal (perte du second dé).
	var mover: Dictionary = _pawn_yard(0, 0)
	var barrier_a: Dictionary = _pawn_ring(20, 2, 27)  # ring_index (26+27)%52 = 1
	var barrier_b: Dictionary = _pawn_ring(21, 2, 27)  # idem -> barrière à 2 pions en 1
	var all_pawns: Array = [mover, barrier_a, barrier_b]

	var preview: Dictionary = RuleEngine.try_combined_move(mover, 6, 3, all_pawns)
	_assert(not preview.legal and preview.reason == "path_blocked_by_barrier",
		"try_combined_move confirme le blocage par la barrière (barrière en ring 1, sur le chemin de continuation)")


func test_combined_move_overshoot_illegal() -> void:
	print("-- test_combined_move_overshoot_illegal (branche non-MAISON générique) --")
	var pawn: Dictionary = _pawn_ring(0, 0, 52)
	pawn.state = PawnState.HOME_LANE
	var result: Dictionary = RuleEngine.try_combined_move(pawn, 5, 4, [pawn])
	_assert(not result.legal and result.reason == "overshoot_home_center",
		"la somme des deux dés (9) dépasserait le centre (52+9=61>56) -> illégal")


func test_combined_yard_exit_blocked_by_ally_barrier_on_start_tile() -> void:
	print("-- test_combined_yard_exit_blocked_by_ally_barrier_on_start_tile (correctif du bug détecté) --")
	# Une barrière ALLIÉE (2 pions du MÊME joueur) sur la start tile du joueur
	# doit AUSSI bloquer le mouvement combiné : la start tile est une case de
	# TRANSIT ici, et aucune barrière (alliée ou ennemie) n'est traversable —
	# contrairement à la règle d'ATTERRISSAGE qui ne bloque que les barrières
	# ennemies. Avant le correctif, ce cas serait passé à tort.
	var mover: Dictionary = _pawn_yard(0, 0)
	var ally_a: Dictionary = _pawn_ring(1, 0, 0)  # ring_index (0+0)%52 = 0 = start tile du joueur 0
	var ally_b: Dictionary = _pawn_ring(2, 0, 0)  # idem -> barrière alliée à 2 pions en 0
	var all_pawns: Array = [mover, ally_a, ally_b]

	var result: Dictionary = RuleEngine.try_combined_move(mover, 6, 3, all_pawns)
	_assert(not result.legal and result.reason == "path_blocked_by_barrier",
		"la barrière alliée sur la start tile bloque aussi le passage (pas seulement les barrières ennemies)")


# ----------------------------------------------------------------------------
# get_stack_at() / get_pawns_on_home_lane_cell() — empilement visuel (§6/H3)
# ----------------------------------------------------------------------------

func test_get_stack_at_groups_ring_allies_sorted_by_id() -> void:
	print("-- test_get_stack_at_groups_ring_allies_sorted_by_id --")
	var low_id: Dictionary = _pawn_ring(2, 0, 10)
	var high_id: Dictionary = _pawn_ring(5, 0, 10)
	var distractor: Dictionary = _pawn_ring(3, 1, 20)
	# all_pawns doit être fourni trié par id croissant : c'est l'ordre garanti
	# par BoardManager.all_pawns (jamais réordonné) dont dépend le tri du
	# groupe retourné — get_pawns_on_ring_index() ne trie pas lui-même, il
	# préserve l'ordre d'entrée (voir docstring de get_stack_at()).
	var all_pawns: Array = [low_id, high_id, distractor]

	var stack: Array = RuleEngine.get_stack_at(high_id, all_pawns)
	_assert(stack.size() == 2, "2 pions alliés sur la même case d'anneau -> groupe de taille 2")
	_assert(stack[0].id == 2 and stack[1].id == 5, "groupe dans l'ordre de all_pawns (par id croissant, garanti par BoardManager)")


func test_get_stack_at_home_lane_groups_only_same_player() -> void:
	print("-- test_get_stack_at_home_lane_groups_only_same_player --")
	var ally_a: Dictionary = _pawn_ring(0, 0, 52)
	ally_a.state = PawnState.HOME_LANE
	var ally_b: Dictionary = _pawn_ring(1, 0, 52)
	ally_b.state = PawnState.HOME_LANE
	# Même progress NUMÉRIQUE mais un AUTRE joueur : case de home lane privée,
	# ne doit jamais être regroupée avec celle du joueur 0.
	var other_player: Dictionary = _pawn_ring(2, 1, 52)
	other_player.state = PawnState.HOME_LANE
	var all_pawns: Array = [ally_a, ally_b, other_player]

	var stack: Array = RuleEngine.get_stack_at(ally_a, all_pawns)
	_assert(stack.size() == 2, "2 pions alliés au même progress en home lane -> groupe de taille 2")
	_assert(stack[0].id == 0 and stack[1].id == 1, "le pion d'un autre joueur au même progress numérique est exclu")


func test_get_stack_at_single_pawn_and_non_ring_home_lane_states() -> void:
	print("-- test_get_stack_at_single_pawn_and_non_ring_home_lane_states --")
	var lone_ring: Dictionary = _pawn_ring(0, 0, 10)
	_assert(RuleEngine.get_stack_at(lone_ring, [lone_ring]).size() == 1,
		"un pion seul sur sa case d'anneau -> groupe de taille 1")

	var yard: Dictionary = _pawn_yard(1, 0)
	_assert(RuleEngine.get_stack_at(yard, [yard]).is_empty(), "pion MAISON -> groupe vide (pas d'empilement visuel géré)")

	var captured: Dictionary = _pawn_captured(2, 0, 1)
	_assert(RuleEngine.get_stack_at(captured, [captured]).is_empty(), "pion CAPTURED -> groupe vide")

	var finished: Dictionary = _pawn_ring(3, 0, BoardConfig.FINISH_PROGRESS)
	finished.state = PawnState.FINI
	_assert(RuleEngine.get_stack_at(finished, [finished]).is_empty(), "pion FINI -> groupe vide (hors scope)")
