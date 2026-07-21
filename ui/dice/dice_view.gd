class_name DiceView
extends Control
## ============================================================================
## DiceView — Bouton "Lancer/Relancer" (GDD §11.5). Noeud logique de taille
## nulle dans player_hud.tscn (BottomBar) ; pilote %RollButton via son nom
## unique de scène.
## ============================================================================

var turn_manager: TurnManager  # injecté par player_hud.gd

@onready var _roll_button: Button = %RollButton


func _ready() -> void:
	_roll_button.pressed.connect(_on_roll_pressed)
	GameEvents.turn_state_changed.connect(_on_state_changed)
	# La toute première transition de TurnManager est un no-op silencieux
	# (state vaut déjà WAITING_FOR_ROLL par défaut, _change_state() ignore les
	# transitions vers le même état — voir turn_manager.gd) : aucun signal
	# turn_state_changed n'arrive donc au tout premier tour. On pose l'état
	# initial explicitement ici plutôt que d'attendre ce signal qui ne vient
	# jamais, sous peine de laisser le bouton désactivé en permanence.
	_apply_state(TurnManager.TurnState.WAITING_FOR_ROLL)


func _on_roll_pressed() -> void:
	if turn_manager:
		turn_manager.request_roll()


## Raccourci clavier (action "roll_dice", touche D) : même effet que le clic
## sur le bouton, soumis à la même garde (désactivé hors WAITING_FOR_ROLL /
## WAITING_FOR_REROLL).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("roll_dice") and not _roll_button.disabled:
		_on_roll_pressed()


func _on_state_changed(_old: int, new_state: int) -> void:
	_apply_state(new_state)


func _apply_state(state: int) -> void:
	if state == TurnManager.TurnState.WAITING_FOR_ROLL:
		_roll_button.text = "Lancer"
		_roll_button.disabled = false
	elif state == TurnManager.TurnState.WAITING_FOR_REROLL:
		# Double six : le joueur a gagné une relance mais doit la déclencher
		# lui-même (plus de relance automatique enchaînée, voir turn_manager.gd).
		_roll_button.text = "Relancer !"
		_roll_button.disabled = false
	else:
		_roll_button.text = "…"
		_roll_button.disabled = true
