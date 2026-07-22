## Tests du seuil de bust (§5.3) du TurnManager : un 3e double six consécutif
## DANS LE MÊME TOUR annule le tour, mais le compteur ne doit pas s'accumuler
## d'un joueur à l'autre (régression corrigée dans _end_turn(), voir
## turn_manager.gd:_roll_chain_count). TurnManager référence les autoloads
## GameEvents/TurnManager lui-même, donc ce test doit tourner comme une SCÈNE
## (pas `--script` bare SceneTree, qui n'initialise pas les autoloads — voir
## tests/test_pawn_move_duration.gd) :
##
## Exécution :
##   godot --headless --quit-after 60 res://tests/test_turn_manager_bust.tscn
extends Node

var _pass_count: int = 0
var _fail_count: int = 0


func _ready() -> void:
	print("=== Tests TurnManager — seuil de bust des doubles six ===\n")

	test_bust_count_resets_between_turns()

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
func test_bust_count_resets_between_turns() -> void:
	print("-- test_bust_count_resets_between_turns --")

	var board_manager: BoardManager = _make_board_manager()
	var pawn_controller := PawnController.new()
	var dice := DiceSystem.new()

	var busted_players: Array = []
	GameEvents.turn_busted.connect(func(player_id: int): busted_players.append(player_id))

	TurnManager.setup(dice, board_manager, pawn_controller)
	TurnManager.start_from_scenario(0)

	# Joueur 0 : un lancer (2,3) sans coup légal (aucun 6, tous les pions à la
	# Maison) -> fin de tour normale (chain=1, jamais remis à 0 avant le
	# correctif car _end_turn() ne le faisait pas).
	dice.set_forced_pair(2, 3)
	TurnManager.request_roll()
	_assert(busted_players.is_empty(), "joueur 0 : pas de bust (aucun double six)")
	_assert(TurnManager.active_player == 1, "le tour est bien passé au joueur 1 après le lancer sans coup légal")

	# Joueur 1 : idem, un 2e lancer (2,3) sans coup légal -> chain=2 au global
	# avant le correctif (jamais remis à 0 entre les tours).
	dice.set_forced_pair(2, 3)
	TurnManager.request_roll()
	_assert(busted_players.is_empty(), "joueur 1 : pas de bust (aucun double six)")
	_assert(TurnManager.active_player == 2, "le tour est bien passé au joueur 2 après le lancer sans coup légal")

	# Régression : le tout premier lancer du joueur 2 est un double six. Avant
	# le correctif, le compteur global valait déjà 2 (deux lancers SANS RAPPORT
	# joués par d'autres joueurs) et ce lancer atteignait le seuil de 3 -> bust
	# à tort, alors qu'aucun double six consécutif n'a jamais eu lieu.
	dice.set_forced_pair(6, 6)
	TurnManager.request_roll()

	_assert(busted_players.is_empty(), "joueur 2 : son 1er double six ne bust PAS (compteur remis à 0 à son tour)")
	_assert(TurnManager.active_player == 2, "le tour du joueur 2 continue (pas de bust)")
	_assert(not TurnManager.dice_pool.is_empty(), "le pool contient bien les dés du 1er double six du joueur 2")

	# Le joueur 2 enchaîne un 2e double six (chain=2) : toujours pas de bust.
	dice.set_forced_pair(6, 6)
	TurnManager.request_roll()
	_assert(busted_players.is_empty(), "joueur 2 : 2e double six consécutif, toujours pas de bust")

	# Le joueur 2 enchaîne un 3e double six CONSÉCUTIF (chain=3) : bust attendu,
	# la règle §5.3 elle-même doit continuer à fonctionner après le correctif.
	dice.set_forced_pair(6, 6)
	TurnManager.request_roll()

	_assert(busted_players == [2], "joueur 2 : 3e double six consécutif -> bust (turn_busted(2))")
	_assert(TurnManager.dice_pool.is_empty(), "le pool est vidé après le bust total")
	_assert(TurnManager.active_player == 3, "le tour est passé au joueur 3 après le bust")

	board_manager.get_parent().queue_free()
	pawn_controller.free()
	dice.free()


# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

## Instancie board_root.tscn + un BoardManager pleinement configuré, exactement
## comme scenes/main.gd / tests/test_scenario_setup.gd. Le noeud racine renvoyé
## par board_manager.get_parent() doit être libéré (queue_free()) par l'appelant.
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
