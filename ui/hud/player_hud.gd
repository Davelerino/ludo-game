class_name PlayerHUD
extends Control
## ============================================================================
## PlayerHUD — HUD de jeu stylisé (GDD §11.5, remplace la barre du haut/bas
## historiquement absente). Assemble TopBar (chips joueurs), BottomBar
## (infos de tour + DiceView + DicePoolView) et HistoryPanel (historique des
## tours) définis dans player_hud.tscn.
##
## Point d'entrée unique pour main.gd : setup(turn_manager, board_manager).
## Les noms uniques de scène (%Node) sont la seule façon dont ce script et
## ses enfants (DiceView, DicePoolView, PlayerChip) se retrouvent entre eux —
## voir le plan HUD pour la convention complète.
## ============================================================================

const PALETTE: PlayerPalette = preload("res://resources/PlayerPalette.tres")
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

@onready var _back_button: Button = %BackButton
@onready var _history_toggle_button: Button = %HistoryToggleButton
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_menu: SettingsMenu = %SettingsMenu
@onready var _chip0: PlayerChip = %PlayerChip0
@onready var _chip1: PlayerChip = %PlayerChip1
@onready var _chip2: PlayerChip = %PlayerChip2
@onready var _chip3: PlayerChip = %PlayerChip3
@onready var _turn_label: Label = %TurnLabel
@onready var _turn_helper_label: Label = %TurnHelperLabel
@onready var _dice_view: DiceView = %DiceView
@onready var _dice_pool_view: DicePoolView = %DicePoolView
@onready var _history_panel: HistoryPanel = %HistoryPanel

var turn_manager: TurnManager  # injecté par main.gd via setup()
var board_manager: BoardManager  # injecté par main.gd via setup()

var _chips: Array[PlayerChip] = []

## Bookkeeping LOCAL et indépendant de celui de DicePoolView (même principe
## que hud.gd/dice_pool_view.gd qui écoutent chacun GameEvents séparément) —
## sert uniquement au texte d'aide ("Il reste un dé à jouer" vs "Choisis...").
var _selected_die_value: int = -1
var _any_die_used_this_turn: bool = false
var _max_pool_size_this_turn: int = 0


func _ready() -> void:
	# player_id (0=Bleu..3=Jaune) est déjà fixé par instance dans le .tscn
	# (PlayerChip0..3) — voir player_chip.gd.
	_chips = [_chip0, _chip1, _chip2, _chip3]
	_back_button.pressed.connect(_on_back_pressed)
	_history_toggle_button.pressed.connect(_on_history_toggle_pressed)
	_settings_button.pressed.connect(_on_settings_toggle_pressed)


## Touche H (action "toggle_history_panel") : même effet que le bouton
## %HistoryToggleButton — le panneau reste accessible même caché, puisque ce
## bouton vit dans TopBarRow et non dans HistoryPanel lui-même.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_history_panel"):
		_on_history_toggle_pressed()


func _on_history_toggle_pressed() -> void:
	_history_panel.visible = not _history_panel.visible


func _on_settings_toggle_pressed() -> void:
	_settings_menu.visible = not _settings_menu.visible


func setup(p_turn_manager: TurnManager, p_board_manager: BoardManager) -> void:
	turn_manager = p_turn_manager
	board_manager = p_board_manager
	for i in range(_chips.size()):
		_chips[i].visible = i in board_manager.active_players
	_dice_view.turn_manager = p_turn_manager
	_dice_pool_view.turn_manager = p_turn_manager
	_dice_pool_view.board_manager = p_board_manager
	_history_panel.turn_manager = p_turn_manager
	_dice_pool_view.die_selection_changed.connect(_on_die_selection_changed)
	GameEvents.turn_ended.connect(_on_turn_ended)
	GameEvents.turn_state_changed.connect(_on_turn_state_changed)
	GameEvents.dice_pool_changed.connect(_on_dice_pool_changed)
	GameEvents.pawn_finished.connect(_on_pawn_finished)
	_refresh_active_player(p_turn_manager.active_player)
	_refresh_all_scores()
	_refresh_helper_text()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _refresh_active_player(player_id: int) -> void:
	for i in range(_chips.size()):
		_chips[i].set_active(i == player_id)
	_turn_label.text = "Au tour de %s" % PALETTE.player_name(player_id)
	_turn_label.add_theme_color_override("font_color", PALETTE.dark(player_id))


func _refresh_all_scores() -> void:
	if not board_manager:
		return
	for i in range(_chips.size()):
		_chips[i].set_score(RuleEngine.count_finished_pawns(i, board_manager.all_pawns), BoardConfig.PAWNS_PER_PLAYER)


func _on_turn_ended(_prev: int, next_p: int) -> void:
	_refresh_active_player(next_p)
	_reset_turn_bookkeeping()


func _on_turn_state_changed(_old: int, new_state: int) -> void:
	if new_state == TurnManager.TurnState.WAITING_FOR_ROLL:
		_reset_turn_bookkeeping()
	_refresh_helper_text()


func _reset_turn_bookkeeping() -> void:
	_selected_die_value = -1
	_any_die_used_this_turn = false
	_max_pool_size_this_turn = 0


func _on_dice_pool_changed(_player_id: int, pool: Array) -> void:
	if pool.size() > _max_pool_size_this_turn:
		_max_pool_size_this_turn = pool.size()
	elif pool.size() < _max_pool_size_this_turn:
		_any_die_used_this_turn = true
	_refresh_helper_text()


func _on_die_selection_changed(_pool_id: int, value: int) -> void:
	_selected_die_value = value
	_refresh_helper_text()


func _on_pawn_finished(pawn: Dictionary) -> void:
	if not board_manager:
		return
	_chips[pawn.player].set_score(
		RuleEngine.count_finished_pawns(pawn.player, board_manager.all_pawns), BoardConfig.PAWNS_PER_PLAYER
	)


## Mapping vérifié contre turn_manager.gd : une fois le pool épuisé, _end_turn()
## fait TOUJOURS avancer active_player, donc WAITING_FOR_ROLL correspond sans
## ambiguïté à "nouveau joueur actif, premier lancer à venir". Le cas "même
## joueur, relance" existe désormais (double six) : c'est WAITING_FOR_REROLL,
## distinct, pour ne pas mélanger les deux messages.
func _refresh_helper_text() -> void:
	if not turn_manager:
		return
	match turn_manager.state:
		TurnManager.TurnState.ROLLING:
			_turn_helper_label.text = "Lancer en cours…"
		TurnManager.TurnState.WAITING_FOR_ROLL:
			_turn_helper_label.text = "Relance pour continuer"
		TurnManager.TurnState.WAITING_FOR_REROLL:
			_turn_helper_label.text = "Double six ! Relance encore"
		TurnManager.TurnState.WAITING_FOR_SELECTION:
			if _selected_die_value != -1:
				_turn_helper_label.text = "Clique un pion pour jouer le %d" % _selected_die_value
			elif _any_die_used_this_turn:
				_turn_helper_label.text = "Il reste un dé à jouer"
			else:
				_turn_helper_label.text = "Choisis un dé à jouer"
		_:
			_turn_helper_label.text = ""
