class_name DicePoolView
extends Control
## ============================================================================
## DicePoolView — Affiche le pool de dés du tour. Un dé est TOUJOURS actif dès
## qu'un coup est possible (auto-armé, voir _maybe_auto_arm()) : le joueur
## peut cliquer un pion directement, sans devoir d'abord cliquer un dé. Il
## garde la liberté de cliquer un AUTRE dé du pool pour changer lequel est
## actif avant de cliquer le pion (GDD §11.5/§5.1).
##
## Un DieButton (die_button.tscn) par dé VU ce tour dans %DicePoolRow — y
## compris les dés déjà joués, qui restent affichés estompés (used) plutôt
## que retirés, pour matcher le handoff design. Reconstruit à chaque
## dice_pool_changed/turn_state_changed. Armer un dé (auto ou clic) appelle
## TurnManager.select_die(pool_id) — c'est TurnManager qui décide ensuite
## quels pions deviennent cliquables sur le plateau 3D (PawnController), ou
## joue instantanément s'il n'y a qu'un seul pion légal pour ce dé.
## ============================================================================

const DieButtonScene: PackedScene = preload("res://ui/dice/die_button.tscn")

## Émis à chaque changement de sélection locale (armée pour le prochain clic
## pion). pool_id/value = -1 quand rien n'est sélectionné. Signal SCÈNE-LOCAL
## (pas sur GameEvents) : seul player_hud.gd, qui possède ce noeud, écoute.
signal die_selection_changed(pool_id: int, value: int)

var turn_manager: TurnManager  # injecté par player_hud.gd
var board_manager: BoardManager  # injecté par player_hud.gd (pour griser les dés sans coup légal)

@onready var _row: HBoxContainer = %DicePoolRow

var _current_pool_ids: Array = []
## id -> value, accumulé pour CE tour (turn_ended/WAITING_FOR_ROLL le vide) —
## permet d'afficher un dé déjà joué (retiré de dice_pool) avec sa valeur.
var _seen_entries: Dictionary = {}
var _selected_pool_id: int = -1


func _ready() -> void:
	GameEvents.dice_pool_changed.connect(_on_pool_changed)
	GameEvents.turn_state_changed.connect(_on_state_changed)
	GameEvents.turn_ended.connect(_on_turn_ended)


func _on_pool_changed(_player_id: int, pool: Array) -> void:
	_current_pool_ids = pool.map(func(e: Dictionary) -> int: return e.id)
	for entry in pool:
		_seen_entries[entry.id] = entry.value
	if _selected_pool_id != -1 and _selected_pool_id not in _current_pool_ids:
		# Le dé actif vient d'être joué et retiré du pool — on l'oublie.
		# NOTE : TurnManager passe désormais l'état à MOVING AVANT d'émettre
		# dice_pool_changed pour ce cas (voir turn_manager.gd:_play_pawn /
		# _play_combined_move), donc _maybe_auto_arm() ci-dessous ne pourra
		# PAS armer/rejouer un autre dé tant que cette animation n'est pas
		# terminée — seul le tout premier dé après un lancer (état encore
		# CHECKING_MOVES à ce moment-là, cf. turn_manager.gd:188) traverse
		# encore ce chemin en synchrone.
		_selected_pool_id = -1
	_maybe_auto_arm()
	_rebuild_row()


func _on_state_changed(_old: int, new_state: int) -> void:
	if new_state == TurnManager.TurnState.WAITING_FOR_ROLL:
		_reset_turn()
	_maybe_auto_arm()
	_rebuild_row()


func _on_turn_ended(_prev: int, _next: int) -> void:
	_reset_turn()


func _reset_turn() -> void:
	_current_pool_ids = []
	_seen_entries.clear()
	_selected_pool_id = -1
	die_selection_changed.emit(-1, -1)


func _rebuild_row() -> void:
	for child in _row.get_children():
		child.queue_free()
	var interactive: bool = turn_manager and turn_manager.state == TurnManager.TurnState.WAITING_FOR_SELECTION
	for pool_id in _seen_entries:
		var value: int = _seen_entries[pool_id]
		var used: bool = pool_id not in _current_pool_ids
		var dead: bool = (not used) and _is_dead(value)
		var selected: bool = pool_id == _selected_pool_id
		var btn: DieButton = DieButtonScene.instantiate()
		_row.add_child(btn)
		btn.configure(pool_id, value)
		btn.apply_state(interactive, dead, used, selected)
		btn.die_pressed.connect(_on_die_pressed)


## Un dé est temporairement "mort" (grisé, mais PAS retiré du pool) si aucun
## pion du joueur actif ne peut le jouer À CET INSTANT — par exemple parce que
## tous les pions sont encore à la Maison (besoin d'un 6 d'abord) ou que le
## seul pion capable a été verrouillé par une capture ce tour-ci (§8.3/L10).
## Jouer un AUTRE dé du pool peut le rendre jouable ensuite : ce grisage est
## donc réévalué à chaque reconstruction des boutons, pas figé.
func _is_dead(value: int) -> bool:
	if not turn_manager or not board_manager:
		return false
	return RuleEngine.is_dice_value_unusable(
		turn_manager.active_player, board_manager.all_pawns, value, turn_manager.locked_pawn_ids
	)


## Il y a toujours un dé actif dès qu'un coup est possible (UX : cliquer un
## pion directement sans devoir d'abord cliquer un dé) — appelée avant chaque
## reconstruction de la rangée, depuis _on_pool_changed() (utile pour le tout
## premier dé après un lancer : dice_pool_changed est alors émis pendant que
## l'état est encore CHECKING_MOVES, voir turn_manager.gd:188, donc le garde-
## fou state != WAITING_FOR_SELECTION bloque l'armement à ce stade) ET
## _on_state_changed() (qui arme réellement ce premier dé, ET chaque dé
## suivant une fois l'animation du précédent terminée et l'état repassé à
## WAITING_FOR_SELECTION par _after_move_resolved()). Un 6 encore jouable est
## toujours choisi en priorité sur les autres dés du pool (voir corps de la
## fonction) : sortir un pion de la Maison change souvent les pions légaux
## disponibles pour les autres dés, le joueur doit garder la main sur cet
## ordre plutôt que de se faire devancer par l'avance auto d'un autre dé.
func _maybe_auto_arm() -> void:
	if not turn_manager or turn_manager.state != TurnManager.TurnState.WAITING_FOR_SELECTION:
		return
	if _selected_pool_id != -1:
		return
	# Priorise un 6 encore jouable : sortir un pion de la Maison (§4.2) change
	# souvent les pions légaux des autres dés, donc le joueur doit pouvoir le
	# jouer en premier plutôt que de se faire devancer par l'avance auto d'un
	# autre dé. Fallback sur le premier dé jouable du pool si aucun 6 dispo.
	var six_id: int = -1
	var fallback_id: int = -1
	for pool_id in _current_pool_ids:
		var value: int = _seen_entries[pool_id]
		if _is_dead(value):
			continue
		if value == BoardConfig.ENTRY_DICE_VALUE:
			six_id = pool_id
			break
		if fallback_id == -1:
			fallback_id = pool_id
	var chosen_id: int = six_id if six_id != -1 else fallback_id
	if chosen_id != -1:
		_arm_die(chosen_id)


func _on_die_pressed(pool_id: int) -> void:
	if not turn_manager or _selected_pool_id == pool_id:
		# Retap sur le dé déjà actif : plus de désélection, il y a toujours
		# un dé actif dès qu'un coup est possible (voir _maybe_auto_arm()).
		return
	_arm_die(pool_id)
	_rebuild_row()


## Arme `pool_id` côté TurnManager (rend ses pions cliquables en 3D, ou joue
## instantanément s'il n'y a qu'un seul pion légal) et met à jour l'état local
## de sélection en conséquence.
func _arm_die(pool_id: int) -> void:
	turn_manager.select_die(pool_id)
	# select_die() peut résoudre immédiatement (un seul pion légal) et faire
	# quitter WAITING_FOR_SELECTION avant même de revenir ici — dans ce cas
	# il n'y a rien à mettre en surbrillance.
	if turn_manager.state == TurnManager.TurnState.WAITING_FOR_SELECTION:
		_selected_pool_id = pool_id
	else:
		_selected_pool_id = -1
	var value: int = _seen_entries.get(_selected_pool_id, -1)
	die_selection_changed.emit(_selected_pool_id, value)
