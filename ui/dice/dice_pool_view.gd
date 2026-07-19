class_name DicePoolView
extends Control
## ============================================================================
## DicePoolView — Affiche le pool de dés du tour et laisse le joueur choisir
## LIBREMENT quel dé jouer, AVANT de choisir le pion (GDD §11.5/§5.1).
##
## Un simple row de boutons (un par dé encore dans TurnManager.dice_pool),
## reconstruit à chaque dice_pool_changed. Cliquer un dé jouable appelle
## TurnManager.select_die(pool_id) — c'est TurnManager qui décide ensuite
## quels pions deviennent cliquables sur le plateau 3D (PawnController).
## ============================================================================

var turn_manager: TurnManager  # injecté (autoload, mais passé pour cohérence avec DiceView)
var board_manager: BoardManager  # injecté (pour griser les dés sans coup légal)

var _hbox: HBoxContainer
var _current_pool: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(320, 60)
	_build()
	GameEvents.dice_pool_changed.connect(_on_pool_changed)
	GameEvents.turn_state_changed.connect(_on_state_changed)


func _build() -> void:
	_hbox = HBoxContainer.new()
	_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hbox.add_theme_constant_override("separation", 6)
	add_child(_hbox)


func _on_pool_changed(_player_id: int, pool: Array) -> void:
	_current_pool = pool
	_rebuild_buttons()


func _on_state_changed(_old: int, new_state: int) -> void:
	if new_state == TurnManager.TurnState.WAITING_FOR_ROLL:
		_current_pool = []
	_rebuild_buttons()


func _rebuild_buttons() -> void:
	for child in _hbox.get_children():
		child.queue_free()
	var interactive: bool = turn_manager and turn_manager.state == TurnManager.TurnState.WAITING_FOR_SELECTION
	for entry in _current_pool:
		var btn := Button.new()
		btn.text = "🎲 %d" % entry.value
		btn.custom_minimum_size = Vector2(48, 48)
		btn.disabled = not interactive or _is_dead(entry.value)
		btn.pressed.connect(_on_die_pressed.bind(entry.id))
		_hbox.add_child(btn)


## Un dé est temporairement "mort" (grisé, mais PAS retiré du pool) si aucun
## pion du joueur actif ne peut le jouer À CET INSTANT — par exemple parce que
## tous les pions sont encore à la Maison (besoin d'un 6 d'abord) ou que le
## seul pion capable a été verrouillé par une capture ce tour-ci (§8.3/L10).
## Jouer un AUTRE dé du pool peut le rendre jouable ensuite (voir
## TurnManager.dice_pool) : ce grisage est donc réévalué à chaque
## reconstruction des boutons, pas figé.
func _is_dead(value: int) -> bool:
	if not turn_manager or not board_manager:
		return false
	return RuleEngine.is_dice_value_unusable(
		turn_manager.active_player, board_manager.all_pawns, value, turn_manager.locked_pawn_ids
	)


func _on_die_pressed(pool_id: int) -> void:
	if turn_manager:
		turn_manager.select_die(pool_id)
