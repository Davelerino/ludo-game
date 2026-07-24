class_name SaveGameDialog
extends Control
## ============================================================================
## SaveGameDialog — Sauvegarde nommée de la partie en cours, déclenchée par
## %SaveButton (voir ui/hud/player_hud.gd).
##
## Même principe que QuitConfirmDialog/SettingsMenu : overlay plein-écran
## instancié comme enfant de player_hud.tscn, montré/caché via `visible`,
## construit entièrement en code. Contrairement à QuitConfirmDialog (qui ne
## fait QUE émettre confirmed/cancelled, la navigation restant décidée par
## PlayerHUD), ce dialogue écrit lui-même la sauvegarde via SaveManager — il
## n'y a pas de décision de navigation à déléguer ici.
##
## PlayerHUD n'ouvre ce dialogue que lorsque TurnManager.state ==
## WAITING_FOR_ROLL (voir _on_turn_state_changed()) : à cet instant
## dice_pool/locked_pawn_ids sont toujours vides (§SaveManager), donc ce
## dialogue n'a besoin de connaître que active_player + le classement en
## cours + la liste des pions pour construire une sauvegarde complète.
##
## `saved`/`cancelled` : émis après coup (le dialogue s'est déjà fermé), pour
## que l'appelant puisse enchaîner une navigation sans dupliquer la logique de
## sauvegarde — voir PlayerHUD._on_quit_save_requested() (flux "Sauvegarder et
## quitter" depuis QuitConfirmDialog).
## ============================================================================

signal saved
signal cancelled

var _name_edit: LineEdit
var _saves_option: OptionButton

var _active_player: int = 0
var _remaining_players: Array[int] = []
var _finish_order: Array[int] = []
var _pawns: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


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
	panel.custom_minimum_size = Vector2(380, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Sauvegarder la partie"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "nom de la sauvegarde"
	vbox.add_child(_name_edit)

	var saves_label := Label.new()
	saves_label.text = "Sauvegardes existantes (cliquer pour écraser) :"
	vbox.add_child(saves_label)

	_saves_option = OptionButton.new()
	_saves_option.item_selected.connect(_on_existing_save_selected)
	vbox.add_child(_saves_option)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	var cancel_button := Button.new()
	cancel_button.text = "Annuler"
	cancel_button.custom_minimum_size = Vector2(140, 44)
	cancel_button.pressed.connect(_on_cancel_pressed)
	button_row.add_child(cancel_button)

	var save_button := Button.new()
	save_button.text = "Sauvegarder"
	save_button.custom_minimum_size = Vector2(140, 44)
	save_button.pressed.connect(_on_save_pressed)
	button_row.add_child(save_button)


## Point d'entrée public (appelé par PlayerHUD) : ouvre le dialogue avec
## l'état de partie à sauvegarder (active_player + classement en cours,
## voir TurnManager.get_ranking_snapshot() + BoardManager.all_pawns).
func open(active_player: int, remaining_players: Array[int], finish_order: Array[int], pawns: Array) -> void:
	_active_player = active_player
	_remaining_players = remaining_players
	_finish_order = finish_order
	_pawns = pawns
	_refresh_saves_list()
	_name_edit.text = _default_name()
	visible = true


func _default_name() -> String:
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	return "Partie du %02d/%02d %02d:%02d" % [dt.day, dt.month, dt.hour, dt.minute]


func _refresh_saves_list() -> void:
	_saves_option.clear()
	for entry in SaveManager.list_saves():
		_saves_option.add_item(entry.name)


func _on_existing_save_selected(index: int) -> void:
	_name_edit.text = _saves_option.get_item_text(index)


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()


func _on_save_pressed() -> void:
	SaveManager.save_game(_name_edit.text, _active_player, _remaining_players, _finish_order, _pawns)
	visible = false
	saved.emit()
