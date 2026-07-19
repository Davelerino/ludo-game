## Tests du mode "Configuration manuelle de scénario" (ui/scenario/scenario_setup.gd) :
## validation des entrées (RuleEngine) et application au plateau (BoardManager).
##
## Exécution :
##   godot --headless --path . --script res://tests/test_scenario_setup.gd
extends SceneTree

const PawnState := BoardConfig.PawnState

var _pass_count: int = 0
var _fail_count: int = 0


func _initialize() -> void:
	print("=== Tests Configuration manuelle de scénario ===\n")

	test_is_progress_valid_for_state()
	test_validate_scenario_pawn()
	test_apply_scenario_mutates_board()
	test_apply_scenario_unknown_id_warns_without_crash()
	test_validate_scenario_cross_pawn_warning()

	print("\n=== Résultat : %d PASS / %d FAIL ===" % [_pass_count, _fail_count])
	quit(0 if _fail_count == 0 else 1)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % label)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % label)


# ----------------------------------------------------------------------------
func test_is_progress_valid_for_state() -> void:
	print("-- test_is_progress_valid_for_state (bornes RING/HOME_LANE/FINI) --")
	_assert(RuleEngine.is_progress_valid_for_state(PawnState.MAISON, -1), "MAISON valide à progress=-1")
	_assert(not RuleEngine.is_progress_valid_for_state(PawnState.MAISON, 0), "MAISON invalide à progress=0")
	_assert(RuleEngine.is_progress_valid_for_state(PawnState.CAPTURED, -1), "CAPTURED valide à progress=-1")

	_assert(RuleEngine.is_progress_valid_for_state(PawnState.RING, 0), "RING valide à la borne basse (0)")
	_assert(RuleEngine.is_progress_valid_for_state(PawnState.RING, BoardConfig.HOME_ENTRY_PROGRESS - 1),
		"RING valide à la borne haute (HOME_ENTRY_PROGRESS-1)")
	_assert(not RuleEngine.is_progress_valid_for_state(PawnState.RING, BoardConfig.HOME_ENTRY_PROGRESS),
		"RING invalide à HOME_ENTRY_PROGRESS (bascule en HOME_LANE)")

	_assert(RuleEngine.is_progress_valid_for_state(PawnState.HOME_LANE, BoardConfig.HOME_ENTRY_PROGRESS),
		"HOME_LANE valide à la borne basse (HOME_ENTRY_PROGRESS)")
	_assert(RuleEngine.is_progress_valid_for_state(PawnState.HOME_LANE, BoardConfig.FINISH_PROGRESS - 1),
		"HOME_LANE valide à la borne haute (FINISH_PROGRESS-1)")
	_assert(not RuleEngine.is_progress_valid_for_state(PawnState.HOME_LANE, BoardConfig.FINISH_PROGRESS),
		"HOME_LANE invalide à FINISH_PROGRESS (bascule en FINI)")

	_assert(RuleEngine.is_progress_valid_for_state(PawnState.FINI, BoardConfig.FINISH_PROGRESS),
		"FINI valide uniquement à FINISH_PROGRESS")
	_assert(not RuleEngine.is_progress_valid_for_state(PawnState.FINI, BoardConfig.FINISH_PROGRESS - 1),
		"FINI invalide à FINISH_PROGRESS-1")


func test_validate_scenario_pawn() -> void:
	print("-- test_validate_scenario_pawn --")
	var valid_ring := {"id": 0, "state": PawnState.RING, "progress": 10, "captor_id": -1}
	_assert(RuleEngine.validate_scenario_pawn(valid_ring) == "", "entrée RING cohérente -> pas d'avertissement")

	var bad_progress := {"id": 0, "state": PawnState.MAISON, "progress": 5, "captor_id": -1}
	_assert(RuleEngine.validate_scenario_pawn(bad_progress) != "", "MAISON avec progress=5 -> avertissement")

	var bad_captor := {"id": 0, "state": PawnState.CAPTURED, "progress": -1, "captor_id": -1}
	_assert(RuleEngine.validate_scenario_pawn(bad_captor) != "", "CAPTURED avec captor_id=-1 -> avertissement")

	var good_captor := {"id": 0, "state": PawnState.CAPTURED, "progress": -1, "captor_id": 2}
	_assert(RuleEngine.validate_scenario_pawn(good_captor) == "", "CAPTURED avec captor_id valide -> pas d'avertissement")


func test_apply_scenario_mutates_board() -> void:
	print("-- test_apply_scenario_mutates_board (BoardManager.apply_scenario) --")
	var board_manager: BoardManager = _make_board_manager()

	var entries: Array[Dictionary] = [
		{"id": 0, "state": PawnState.RING, "progress": 12, "captor_id": -1},
		{"id": 1, "state": PawnState.HOME_LANE, "progress": 53, "captor_id": -1},
		{"id": 4, "state": PawnState.CAPTURED, "progress": -1, "captor_id": 2},
		{"id": 8, "state": PawnState.FINI, "progress": BoardConfig.FINISH_PROGRESS, "captor_id": -1},
	]
	var warnings: Array[String] = board_manager.apply_scenario(entries)
	_assert(warnings.is_empty(), "aucune entrée invalide -> aucun avertissement")

	var pawn0: Dictionary = board_manager.get_pawn_by_id(0)
	_assert(pawn0.state == PawnState.RING and pawn0.progress == 12, "pion 0 -> RING progress=12")

	var pawn1: Dictionary = board_manager.get_pawn_by_id(1)
	_assert(pawn1.state == PawnState.HOME_LANE and pawn1.progress == 53, "pion 1 -> HOME_LANE progress=53")

	var pawn4: Dictionary = board_manager.get_pawn_by_id(4)
	_assert(pawn4.state == PawnState.CAPTURED and pawn4.captor_id == 2, "pion 4 -> CAPTURED par joueur 2")

	var pawn8: Dictionary = board_manager.get_pawn_by_id(8)
	_assert(pawn8.state == PawnState.FINI, "pion 8 -> FINI")

	var pawn2: Dictionary = board_manager.get_pawn_by_id(2)
	_assert(pawn2.state == PawnState.MAISON, "pion 2 (non mentionné) reste MAISON")

	board_manager.get_parent().queue_free()


func test_apply_scenario_unknown_id_warns_without_crash() -> void:
	print("-- test_apply_scenario_unknown_id_warns_without_crash --")
	var board_manager: BoardManager = _make_board_manager()

	var entries: Array[Dictionary] = [
		{"id": 999, "state": PawnState.RING, "progress": 0, "captor_id": -1},
	]
	var warnings: Array[String] = board_manager.apply_scenario(entries)
	_assert(warnings.size() == 1, "id inconnu -> exactement un avertissement, pas de crash")

	board_manager.get_parent().queue_free()


func test_validate_scenario_cross_pawn_warning() -> void:
	print("-- test_validate_scenario_cross_pawn_warning (empilement de 3 joueurs) --")
	var all_pawns: Array = [
		{"id": 0, "player": 0, "state": PawnState.RING, "progress": 0, "captor_id": -1},
		{"id": 10, "player": 1, "state": PawnState.RING, "progress": (0 - BoardConfig.get_player_offset(1) + BoardConfig.RING_SIZE) % BoardConfig.RING_SIZE, "captor_id": -1},
		{"id": 20, "player": 2, "state": PawnState.RING, "progress": (0 - BoardConfig.get_player_offset(2) + BoardConfig.RING_SIZE) % BoardConfig.RING_SIZE, "captor_id": -1},
	]
	var warnings: Array[String] = RuleEngine.validate_scenario(all_pawns)
	_assert(not warnings.is_empty(), "3 joueurs empilés sur la même case d'anneau -> avertissement")


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

## Instancie board_root.tscn + un BoardManager pleinement configuré, exactement
## comme scenes/main.gd. Le noeud racine renvoyé par board_manager.get_parent()
## doit être libéré (queue_free()) par l'appelant une fois le test terminé.
func _make_board_manager() -> BoardManager:
	var board_root: Node3D = (load("res://scenes/board/board_root.tscn") as PackedScene).instantiate()
	var grid_map: GridMap = board_root.get_node("GridMap")
	var yards_root: Node3D = board_root.get_node("Yards")
	var capture_zones_root: Node3D = board_root.get_node("CaptureZones")

	var mesh_lib: MeshLibrary = LudoMeshLibraryFactory.get_or_create_mesh_library()
	var layout: LudoBoardLayout = load("res://resources/BoardLayout.tres")
	var mesh_mapping := LudoMeshMapping.new()
	LudoBoardPainter.paint(grid_map, mesh_lib, layout, mesh_mapping)

	var board_manager: BoardManager = BoardManager.new()
	board_root.add_child(board_manager)
	var cfg: BoardConfig = load("res://resources/BoardConfig.tres")
	board_manager.setup(cfg, grid_map, layout, yards_root, capture_zones_root)
	return board_manager
