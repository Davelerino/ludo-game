class_name LoadGameScreen
extends Control
## ============================================================================
## LoadGameScreen — Choix d'une partie sauvegardée à reprendre, accessible
## depuis le menu principal (%LoadGameButton, voir ui/menu/main_menu.gd).
##
## Construit entièrement en code (comme MainMenu/QuitConfirmDialog). Sur le
## modèle de la liste de positions de ui/scenario/scenario_setup.gd : une
## liste déroulante des sauvegardes existantes (SaveManager.list_saves()) +
## Charger/Supprimer, sans réinventer un nouveau pattern de listing.
##
## "Charger" ne fait QUE poser l'état en attente dans SaveManager
## (queue_load()) puis changer de scène vers scenes/main.tscn, qui consomme
## réellement la sauvegarde au démarrage (voir main.gd, étape 0/5) — même
## principe que ScenarioState/scenario_setup.gd.
## ============================================================================

const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

var _saves_option: OptionButton
var _info_label: Label
var _load_button: Button
var _delete_button: Button

## Parallèle à _saves_option (même ordre) : chaque entrée est le Dictionary
## {"filename","name","timestamp","player_count"} retourné par SaveManager.list_saves().
var _save_entries: Array[Dictionary] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_saves_list()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Charger une partie"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_saves_option = OptionButton.new()
	_saves_option.item_selected.connect(_on_save_selected)
	vbox.add_child(_saves_option)

	_info_label = Label.new()
	_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_info_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	var back_button := Button.new()
	back_button.text = "Retour au menu"
	back_button.custom_minimum_size = Vector2(160, 44)
	back_button.pressed.connect(_on_back_pressed)
	button_row.add_child(back_button)

	_delete_button = Button.new()
	_delete_button.text = "Supprimer"
	_delete_button.custom_minimum_size = Vector2(120, 44)
	_delete_button.pressed.connect(_on_delete_pressed)
	button_row.add_child(_delete_button)

	_load_button = Button.new()
	_load_button.text = "Charger"
	_load_button.custom_minimum_size = Vector2(120, 44)
	_load_button.theme_type_variation = &"RollButton"
	_load_button.pressed.connect(_on_load_pressed)
	button_row.add_child(_load_button)


func _refresh_saves_list() -> void:
	_saves_option.clear()
	_save_entries = SaveManager.list_saves()
	for entry in _save_entries:
		_saves_option.add_item(entry.name)

	var has_saves: bool = not _save_entries.is_empty()
	_load_button.disabled = not has_saves
	_delete_button.disabled = not has_saves
	if has_saves:
		_saves_option.select(0)
		_update_info_label(0)
	else:
		_info_label.text = "Aucune sauvegarde."


func _on_save_selected(index: int) -> void:
	_update_info_label(index)


func _update_info_label(index: int) -> void:
	if index < 0 or index >= _save_entries.size():
		_info_label.text = ""
		return
	var entry: Dictionary = _save_entries[index]
	_info_label.text = "%s — %d joueurs" % [entry.timestamp, entry.player_count]


func _on_load_pressed() -> void:
	if _saves_option.selected == -1:
		return
	var entry: Dictionary = _save_entries[_saves_option.selected]
	if SaveManager.queue_load(entry.filename):
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_delete_pressed() -> void:
	if _saves_option.selected == -1:
		return
	var entry: Dictionary = _save_entries[_saves_option.selected]
	SaveManager.delete_save(entry.filename)
	_refresh_saves_list()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
