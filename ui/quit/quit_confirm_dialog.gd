class_name QuitConfirmDialog
extends Control
## ============================================================================
## QuitConfirmDialog — Confirmation avant d'abandonner la partie en cours,
## déclenchée par %BackButton (voir ui/hud/player_hud.gd) ou par la touche
## Échap (action "ui_cancel").
##
## Même principe que SettingsMenu/VictoryScreen : overlay plein-écran
## instancié comme enfant de player_hud.tscn, montré/caché via `visible`,
## construit entièrement en code. N'effectue PAS la navigation elle-même —
## elle émet `confirmed`/`cancelled`/`save_requested` et laisse PlayerHUD
## décider (c'est lui qui connaît MENU_SCENE et sait ouvrir SaveGameDialog).
##
## `open(can_offer_save)` : quand PlayerHUD détecte une partie non sauvegardée
## (voir SaveManager.is_dirty()) ET qu'il est possible de sauvegarder à cet
## instant (TurnState.WAITING_FOR_ROLL, même condition que %SaveButton), un
## 3e bouton "Sauvegarder et quitter" apparaît. Sinon, comportement inchangé
## (2 boutons "Annuler"/"Quitter").
## ============================================================================

signal confirmed
signal cancelled
signal save_requested

var _quit_button: Button
var _save_and_quit_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## Touche Échap : ferme le dialogue s'il est ouvert (annulation), sans
## rouvrir immédiatement via le handler d'ouverture de PlayerHUD (event
## marqué "handled" par set_input_as_handled).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Quitter la partie ?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var message := Label.new()
	message.text = "La partie en cours sera perdue si tu retournes au menu maintenant."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(message)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	var cancel_button := Button.new()
	cancel_button.text = "Annuler"
	cancel_button.custom_minimum_size = Vector2(140, 44)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_row.add_child(cancel_button)

	_quit_button = Button.new()
	_quit_button.text = "Quitter"
	_quit_button.custom_minimum_size = Vector2(140, 44)
	_quit_button.pressed.connect(_on_quit_pressed)
	button_row.add_child(_quit_button)

	_save_and_quit_button = Button.new()
	_save_and_quit_button.text = "Sauvegarder et quitter"
	_save_and_quit_button.custom_minimum_size = Vector2(180, 44)
	_save_and_quit_button.visible = false
	_save_and_quit_button.pressed.connect(_on_save_and_quit_pressed)
	button_row.add_child(_save_and_quit_button)


## Point d'entrée public : ouvre le dialogue (appelé par PlayerHUD).
## `can_offer_save` : voir doc de classe ci-dessus.
func open(can_offer_save: bool = false) -> void:
	_save_and_quit_button.visible = can_offer_save
	_quit_button.text = "Quitter sans sauvegarder" if can_offer_save else "Quitter"
	visible = true


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_quit_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_save_and_quit_pressed() -> void:
	visible = false
	save_requested.emit()
