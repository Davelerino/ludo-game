class_name DiceView
extends Control
## ============================================================================
## DiceView — Affichage 3D/2D des deux dés + bouton "Lancer" (GDD §11.5).
##
## SQUELETTE : un bouton qui appelle TurnManager.request_roll() via le bus
## GameEvents n'étant pas une commande, on passe une référence directe au
## TurnManager (injectée par main.gd). Affiche aussi les valeurs obtenues.
## ============================================================================

var turn_manager: TurnManager  # injecté

var _roll_button: Button
var _label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(220, 80)
	_build()
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.turn_state_changed.connect(_on_state_changed)


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vbox)

	_roll_button = Button.new()
	_roll_button.text = "🎲 Lancer les dés"
	_roll_button.pressed.connect(_on_roll_pressed)
	vbox.add_child(_roll_button)

	_label = Label.new()
	_label.text = "Dés : - / -"
	vbox.add_child(_label)


func _on_roll_pressed() -> void:
	if turn_manager:
		turn_manager.request_roll()


## Raccourci clavier (action "roll_dice", touche D) : même effet que le clic
## sur le bouton, soumis à la même garde (désactivé hors WAITING_FOR_ROLL).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("roll_dice") and not _roll_button.disabled:
		_on_roll_pressed()


func _on_dice_rolled(a: int, b: int, _is_double: bool) -> void:
	_label.text = "Dés : %d / %d" % [a, b]


func _on_state_changed(_old: int, new_state: int) -> void:
	# Le bouton n'est cliquable que pendant WAITING_FOR_ROLL.
	_roll_button.disabled = new_state != TurnManager.TurnState.WAITING_FOR_ROLL
