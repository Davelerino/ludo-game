extends Node3D
## ============================================================================
## Main — Racine de la scène principale (GDD §11.5).
##
## Arbre (§11.5) :
##   Main (Node3D, ce script)
##   ├─ BoardRoot (board_root.tscn : GridMap, RingDecor, PawnContainer)
##   ├─ CameraRig
##   ├─ AudioManager
##   ├─ UIManager (CanvasLayer : HUD, DiceView, DicePoolView, FeedbackLayer)
##   └─ GameRoot (TurnManager + DiceSystem + BoardManager + PawnController)
##
## Ce script INSTANCIE et BRANCHE les managers entre eux. TurnManager est
## déclaré en autoload (singleton) pour sa persistance ; mais on garde aussi
## une référence locale pour le câblage.
## ============================================================================

@onready var board_root: Node3D = $BoardRoot
@onready var ui_manager: CanvasLayer = $UIManager

# Les managers sont des enfants de GameRoot dans main.tscn.
@onready var board_manager: BoardManager = $GameRoot/BoardManager
@onready var pawn_controller: PawnController = $GameRoot/PawnController
@onready var dice_system: DiceSystem = $GameRoot/DiceSystem


func _ready() -> void:
	# 1. Initialise le BoardManager (état des pions + dépendances).
	#    NOTE : le plateau n'est PAS généré ici — il est cuit dans board_root.tscn
	#    par le plugin "Ludo Board Tools" (Tools > Generate Ludo Board → Ctrl+S).
	var cfg: BoardConfig = load("res://resources/BoardConfig.tres")
	var layout: LudoBoardLayout = load("res://resources/BoardLayout.tres")
	board_manager.setup(
		cfg, board_root.get_node("GridMap"), layout,
		board_root.get_node("Yards"), board_root.get_node("CaptureZones")
	)

	# 2. Vérifie que le plateau a bien été cuit (warning si vide, pas fatal).
	board_manager.validate_board()

	# 3. Instancie les pions visuels.
	pawn_controller.board_manager = board_manager
	pawn_controller.board_tuning = load("res://resources/BoardTuning.tres")
	pawn_controller.setup(board_manager.all_pawns)

	# 4. Branche le TurnManager (autoload singleton) avec ses dépendances.
	TurnManager.setup(dice_system, board_manager, pawn_controller)

	# 5. Démarre la partie : depuis zéro, ou depuis un scénario configuré
	#    manuellement via ui/scenario/scenario_setup.gd (mode test).
	if ScenarioState.has_pending():
		var scenario: Dictionary = ScenarioState.consume()
		var warnings: Array[String] = board_manager.apply_scenario(scenario.pawn_entries)
		warnings.append_array(RuleEngine.validate_scenario(board_manager.all_pawns))
		for w in warnings:
			push_warning("ScenarioSetup: %s" % w)
		pawn_controller.setup(board_manager.all_pawns)  # ré-aligne les visuels (pas d'animation).
		TurnManager.start_from_scenario(scenario.active_player)
	else:
		TurnManager.start_new_game()

	# 6. Injecte le TurnManager dans la DiceView (pour le bouton "Lancer").
	var dice_view: DiceView = ui_manager.get_node_or_null("DiceView")
	if dice_view:
		dice_view.turn_manager = TurnManager

	# 6b. Injecte les dépendances de la DicePoolView (choix du dé à jouer).
	var dice_pool_view: DicePoolView = ui_manager.get_node_or_null("DicePoolView")
	if dice_pool_view:
		dice_pool_view.turn_manager = TurnManager
		dice_pool_view.board_manager = board_manager

	# 7. Injecte les dépendances du HUD (BoardManager n'est pas un autoload,
	#    contrairement à TurnManager).
	var hud: HUD = ui_manager.get_node_or_null("HUD")
	if hud:
		hud.board_manager = board_manager
		hud.refresh()
