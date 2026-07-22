class_name ScenarioSetup
extends Control
## ============================================================================
## ScenarioSetup — Configuration manuelle d'un scénario de test.
##
## Écran (accessible depuis le menu principal) qui permet de placer les 16
## pions dans l'état/progression de son choix (Maison / Anneau / Couloir
## final / Fini / Capturé) puis de lancer la partie depuis cette
## configuration, pour tester des règles précises sans rejouer une partie
## entière (captures, barrières, fin de partie, cas limites...).
##
## Construit entièrement en code, comme le reste de ui/ (MainMenu, HUD).
## Au clic sur "Lancer le scénario", empaquette la config dans l'autoload
## ScenarioState puis change de scène vers scenes/main.tscn, qui applique
## la config via BoardManager.apply_scenario() (voir main.gd étape 5).
## ============================================================================

const PawnState := BoardConfig.PawnState
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## Dossier des positions sauvegardées (mode test) — JSON, un fichier par
## position : {"name", "active_player", "pawns": [mêmes entrées que
## apply_scenario()]}. user:// car res:// n'est pas inscriptible à l'exécution.
const POSITIONS_DIR := "user://positions/"

const PALETTE: PlayerPalette = preload("res://resources/PlayerPalette.tres")

const STATE_ITEMS := [
	{"label": "Maison", "value": PawnState.MAISON},
	{"label": "Anneau", "value": PawnState.RING},
	{"label": "Couloir final", "value": PawnState.HOME_LANE},
	{"label": "Fini", "value": PawnState.FINI},
	{"label": "Capturé", "value": PawnState.CAPTURED},
]

## Une entrée par pion (id 0..15) : {state_option, progress_spin, captor_option, captor_row}.
var _rows: Array = []
var _active_player_option: OptionButton
var _warnings_label: RichTextLabel

var _position_name_edit: LineEdit
var _saved_positions_option: OptionButton
var _load_position_button: Button
var _delete_position_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_refresh_saved_positions_list()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	var title := Label.new()
	title.text = "Configuration manuelle de scénario"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	root_vbox.add_child(title)

	root_vbox.add_child(_build_top_bar())
	root_vbox.add_child(_build_positions_bar())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(rows_vbox)

	for player_id in range(BoardConfig.PLAYER_COUNT):
		rows_vbox.add_child(_build_player_header(player_id))
		for slot in range(BoardConfig.PAWNS_PER_PLAYER):
			var pawn_id: int = player_id * BoardConfig.PAWNS_PER_PLAYER + slot
			rows_vbox.add_child(_build_pawn_row(pawn_id, player_id, slot))

	_warnings_label = RichTextLabel.new()
	_warnings_label.bbcode_enabled = true
	_warnings_label.custom_minimum_size = Vector2(0, 60)
	_warnings_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(_warnings_label)

	root_vbox.add_child(_build_bottom_bar())


func _build_top_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "Joueur actif au lancement :"
	row.add_child(label)

	_active_player_option = OptionButton.new()
	for player_id in range(BoardConfig.PLAYER_COUNT):
		_active_player_option.add_item(PALETTE.player_name(player_id), player_id)
	row.add_child(_active_player_option)

	var reset_button := Button.new()
	reset_button.text = "Réinitialiser au yard"
	reset_button.pressed.connect(_on_reset_pressed)
	row.add_child(reset_button)

	return row


## Barre de sauvegarde/chargement de positions (mode test, §voir POSITIONS_DIR) :
## un nom + Sauvegarder à gauche, une liste des positions existantes +
## Charger/Supprimer à droite.
func _build_positions_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var name_label := Label.new()
	name_label.text = "Position :"
	row.add_child(name_label)

	_position_name_edit = LineEdit.new()
	_position_name_edit.placeholder_text = "nom de la position"
	_position_name_edit.custom_minimum_size = Vector2(180, 0)
	row.add_child(_position_name_edit)

	var save_button := Button.new()
	save_button.text = "Sauvegarder"
	save_button.pressed.connect(_on_save_position_pressed)
	row.add_child(save_button)

	var separator := VSeparator.new()
	row.add_child(separator)

	_saved_positions_option = OptionButton.new()
	_saved_positions_option.custom_minimum_size = Vector2(180, 0)
	_saved_positions_option.item_selected.connect(_on_saved_position_selected)
	row.add_child(_saved_positions_option)

	_load_position_button = Button.new()
	_load_position_button.text = "Charger"
	_load_position_button.pressed.connect(_on_load_position_pressed)
	row.add_child(_load_position_button)

	_delete_position_button = Button.new()
	_delete_position_button.text = "Supprimer"
	_delete_position_button.pressed.connect(_on_delete_position_pressed)
	row.add_child(_delete_position_button)

	return row


func _build_player_header(player_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var swatch := ColorRect.new()
	swatch.color = PALETTE.main(player_id)
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var label := Label.new()
	label.text = "Joueur %d — %s" % [player_id, PALETTE.player_name(player_id)]
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)

	return row


func _build_pawn_row(pawn_id: int, player_id: int, slot: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = "  Pion %d" % slot
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)

	var state_option := OptionButton.new()
	for item in STATE_ITEMS:
		state_option.add_item(item.label, item.value)
	row.add_child(state_option)

	var progress_spin := SpinBox.new()
	progress_spin.custom_minimum_size = Vector2(90, 0)
	row.add_child(progress_spin)

	var captor_row := HBoxContainer.new()
	var captor_label := Label.new()
	captor_label.text = "capturé par :"
	captor_row.add_child(captor_label)
	var captor_option := OptionButton.new()
	for other_id in range(BoardConfig.PLAYER_COUNT):
		captor_option.add_item(PALETTE.player_name(other_id), other_id)
	captor_row.add_child(captor_option)
	row.add_child(captor_row)

	var entry := {
		"pawn_id": pawn_id,
		"player_id": player_id,
		"state_option": state_option,
		"progress_spin": progress_spin,
		"captor_option": captor_option,
		"captor_row": captor_row,
	}
	_rows.append(entry)

	state_option.item_selected.connect(func(_index: int): _on_state_selected(entry))
	# État initial (MAISON, cohérent avec BoardConfig.create_pawn()).
	state_option.select(state_option.get_item_index(PawnState.MAISON))
	_apply_state_constraints(entry, PawnState.MAISON)

	return row


func _build_bottom_bar() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)

	var back_button := Button.new()
	back_button.text = "Retour au menu"
	back_button.custom_minimum_size = Vector2(180, 44)
	back_button.pressed.connect(_on_back_pressed)
	row.add_child(back_button)

	var launch_button := Button.new()
	launch_button.text = "Lancer le scénario"
	launch_button.custom_minimum_size = Vector2(220, 44)
	launch_button.pressed.connect(_on_launch_pressed)
	row.add_child(launch_button)

	return row


## Ajuste la plage du SpinBox de progression et la visibilité du sélecteur de
## capteur selon l'état choisi pour cette ligne — voir RuleEngine.is_progress_valid_for_state().
func _apply_state_constraints(entry: Dictionary, state: int) -> void:
	var spin: SpinBox = entry.progress_spin
	match state:
		PawnState.MAISON, PawnState.CAPTURED:
			spin.min_value = -1
			spin.max_value = -1
			spin.value = -1
			spin.editable = false
		PawnState.RING:
			spin.min_value = 0
			spin.max_value = BoardConfig.HOME_ENTRY_PROGRESS - 1
			spin.value = 0
			spin.editable = true
		PawnState.HOME_LANE:
			spin.min_value = BoardConfig.HOME_ENTRY_PROGRESS
			spin.max_value = BoardConfig.FINISH_PROGRESS - 1
			spin.value = BoardConfig.HOME_ENTRY_PROGRESS
			spin.editable = true
		PawnState.FINI:
			spin.min_value = BoardConfig.FINISH_PROGRESS
			spin.max_value = BoardConfig.FINISH_PROGRESS
			spin.value = BoardConfig.FINISH_PROGRESS
			spin.editable = false

	entry.captor_row.visible = (state == PawnState.CAPTURED)
	if state == PawnState.CAPTURED:
		var captor_option: OptionButton = entry.captor_option
		# Par défaut, capturé par le premier adversaire (jamais par lui-même).
		var default_captor: int = 0 if entry.player_id != 0 else 1
		captor_option.select(captor_option.get_item_index(default_captor))


func _on_state_selected(entry: Dictionary) -> void:
	var state_option: OptionButton = entry.state_option
	var state: int = state_option.get_item_id(state_option.selected)
	_apply_state_constraints(entry, state)


func _on_reset_pressed() -> void:
	for entry in _rows:
		var state_option: OptionButton = entry.state_option
		state_option.select(state_option.get_item_index(PawnState.MAISON))
		_apply_state_constraints(entry, PawnState.MAISON)
	_active_player_option.select(0)
	_warnings_label.text = ""


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Construit les entrées pion à partir de l'état courant des lignes (utilisé
## par le lancement ET la sauvegarde) + les avertissements non bloquants de
## RuleEngine.validate_scenario_pawn() pour chaque pion.
func _collect_entries() -> Dictionary:
	var entries: Array[Dictionary] = []
	var pawn_warnings: Array[String] = []

	for row in _rows:
		var state_option: OptionButton = row.state_option
		var state: int = state_option.get_item_id(state_option.selected)
		var progress: int = int(row.progress_spin.value)
		var captor_option: OptionButton = row.captor_option
		var captor_id: int = captor_option.get_item_id(captor_option.selected) if state == PawnState.CAPTURED else -1

		var entry := {
			"id": row.pawn_id,
			"state": state,
			"progress": progress,
			"captor_id": captor_id,
		}
		var reason: String = RuleEngine.validate_scenario_pawn(entry)
		if reason != "":
			pawn_warnings.append("Pion %d : %s" % [row.pawn_id, reason])
		entries.append(entry)

	return {"entries": entries, "warnings": pawn_warnings}


func _show_warnings(pawn_warnings: Array[String]) -> void:
	# Non bloquant (outil de dev) : on affiche les avertissements mais on
	# n'empêche jamais l'action — le testeur peut vouloir un état volontairement atypique.
	if not pawn_warnings.is_empty():
		_warnings_label.text = "[color=orange]%s[/color]" % "\n".join(pawn_warnings)
	else:
		_warnings_label.text = ""


func _on_launch_pressed() -> void:
	var collected: Dictionary = _collect_entries()
	_show_warnings(collected.warnings)

	var active_player: int = _active_player_option.get_item_id(_active_player_option.selected)
	ScenarioState.set_pending(collected.entries, active_player)
	get_tree().change_scene_to_file(GAME_SCENE)


# ----------------------------------------------------------------------------
# Sauvegarde / chargement de positions (mode test, voir POSITIONS_DIR)
# ----------------------------------------------------------------------------

func _on_save_position_pressed() -> void:
	var collected: Dictionary = _collect_entries()
	_show_warnings(collected.warnings)

	var active_player: int = _active_player_option.get_item_id(_active_player_option.selected)
	var raw_name: String = _position_name_edit.text.strip_edges()
	if raw_name.is_empty():
		raw_name = "position_%s" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")
		_position_name_edit.text = raw_name

	var filename: String = _sanitize_filename(raw_name)
	var data := {
		"name": raw_name,
		"active_player": active_player,
		"pawns": collected.entries,
	}

	DirAccess.make_dir_recursive_absolute(POSITIONS_DIR)
	var path: String = POSITIONS_DIR + filename + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("ScenarioSetup: échec de sauvegarde de la position '%s' (err=%s)." % [raw_name, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_refresh_saved_positions_list()
	_select_position_in_list(filename)


func _on_saved_position_selected(_index: int) -> void:
	if _saved_positions_option.selected == -1:
		return
	_position_name_edit.text = _saved_positions_option.get_item_text(_saved_positions_option.selected)


func _on_load_position_pressed() -> void:
	if _saved_positions_option.item_count == 0 or _saved_positions_option.selected == -1:
		return
	var filename: String = _saved_positions_option.get_item_text(_saved_positions_option.selected)
	var path: String = POSITIONS_DIR + filename + ".json"

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("ScenarioSetup: échec de chargement de la position '%s'." % filename)
		return
	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("pawns"):
		push_warning("ScenarioSetup: fichier de position invalide : %s" % filename)
		return

	_apply_loaded_entries(parsed.pawns, int(parsed.get("active_player", 0)))
	_position_name_edit.text = str(parsed.get("name", filename))


func _on_delete_position_pressed() -> void:
	if _saved_positions_option.item_count == 0 or _saved_positions_option.selected == -1:
		return
	var filename: String = _saved_positions_option.get_item_text(_saved_positions_option.selected)
	DirAccess.remove_absolute(POSITIONS_DIR + filename + ".json")
	_refresh_saved_positions_list()


## Peuple les lignes existantes à partir d'entrées chargées — pions absents du
## fichier laissés inchangés (comme apply_scenario() côté BoardManager).
func _apply_loaded_entries(entries: Array, active_player: int) -> void:
	for raw_entry in entries:
		var entry: Dictionary = raw_entry
		var pawn_id: int = int(entry.get("id", -1))
		var row: Dictionary = _row_by_pawn_id(pawn_id)
		if row.is_empty():
			continue

		var state: int = int(entry.get("state", PawnState.MAISON))
		var state_option: OptionButton = row.state_option
		state_option.select(state_option.get_item_index(state))
		_apply_state_constraints(row, state)

		var progress_spin: SpinBox = row.progress_spin
		if progress_spin.editable:
			progress_spin.value = int(entry.get("progress", progress_spin.value))

		if state == PawnState.CAPTURED:
			var captor_id: int = int(entry.get("captor_id", -1))
			if captor_id != -1:
				var captor_option: OptionButton = row.captor_option
				captor_option.select(captor_option.get_item_index(captor_id))

	var clamped_player: int = clampi(active_player, 0, BoardConfig.PLAYER_COUNT - 1)
	_active_player_option.select(_active_player_option.get_item_index(clamped_player))
	_warnings_label.text = ""


func _row_by_pawn_id(pawn_id: int) -> Dictionary:
	for row in _rows:
		if row.pawn_id == pawn_id:
			return row
	return {}


func _refresh_saved_positions_list() -> void:
	_saved_positions_option.clear()
	var names: Array = []
	if DirAccess.dir_exists_absolute(POSITIONS_DIR):
		var files: PackedStringArray = DirAccess.get_files_at(POSITIONS_DIR)
		for f in files:
			if f.ends_with(".json"):
				names.append(f.get_basename())
	names.sort()
	for n in names:
		_saved_positions_option.add_item(n)

	var has_positions: bool = _saved_positions_option.item_count > 0
	_load_position_button.disabled = not has_positions
	_delete_position_button.disabled = not has_positions
	if has_positions:
		_saved_positions_option.select(0)


func _select_position_in_list(filename: String) -> void:
	for i in range(_saved_positions_option.item_count):
		if _saved_positions_option.get_item_text(i) == filename:
			_saved_positions_option.select(i)
			return


## Remplace tout caractère hors [A-Za-z0-9_-] par "_" pour obtenir un nom de
## fichier sûr sur tous les OS, sans dépendre de l'échappement de POSITIONS_DIR.
func _sanitize_filename(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9_\\-]+")
	var cleaned: String = regex.sub(name, "_", true).strip_edges()
	return cleaned if not cleaned.is_empty() else "position"
