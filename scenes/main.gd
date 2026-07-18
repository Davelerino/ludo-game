extends Node3D
## ============================================================================
## Main — Racine de la scène principale (GDD §11.5).
##
## Arbre (§11.5) :
##   Main (Node3D, ce script)
##   ├─ BoardRoot (board_root.tscn : GridMap, RingDecor, PawnContainer)
##   ├─ CameraRig
##   ├─ AudioManager
##   ├─ UIManager (CanvasLayer : HUD, DiceView, FeedbackLayer)
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

	# 5. Démarre la première partie.
	TurnManager.start_new_game()

	# 6. Injecte le TurnManager dans la DiceView (pour le bouton "Lancer").
	var dice_view: DiceView = ui_manager.get_node_or_null("DiceView")
	if dice_view:
		dice_view.turn_manager = TurnManager

	# 7. Injecte les dépendances du HUD (DiceSystem/BoardManager ne sont pas
	#    des autoloads, contrairement à TurnManager).
	var hud: HUD = ui_manager.get_node_or_null("HUD")
	if hud:
		hud.dice_system = dice_system
		hud.board_manager = board_manager
		hud.refresh()
