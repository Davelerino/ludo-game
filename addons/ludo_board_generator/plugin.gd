## Editor entry point for the Ludo Board Generator plugin.
##
## `LudoBoardGenerator` is a plain @tool script with `class_name`, so Godot 4
## already lists it in the "Create Node" dialog automatically - no
## add_custom_type() registration needed. This plugin's only job is a dock
## with the detection workflow controls, acting on whichever
## LudoBoardGenerator node is currently selected in the scene tree.
@tool
extends EditorPlugin

var dock: VBoxContainer
var status_label: Label
var detect_button: Button
var starter_layout_button: Button
var clear_button: Button
var debug_checkbox: CheckBox

var _current_target: LudoBoardGenerator = null


func _enter_tree() -> void:
	_build_dock()
	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if get_editor_interface().get_selection().selection_changed.is_connected(_on_selection_changed):
		get_editor_interface().get_selection().selection_changed.disconnect(_on_selection_changed)
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _build_dock() -> void:
	dock = VBoxContainer.new()
	dock.name = "Ludo Board Generator"

	var title := Label.new()
	title.text = "Ludo Board Generator"
	title.add_theme_font_size_override("font_size", 16)
	dock.add_child(title)

	status_label = Label.new()
	status_label.text = "Select a LudoBoardGenerator node."
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	dock.add_child(status_label)

	dock.add_child(HSeparator.new())

	var workflow_hint := Label.new()
	workflow_hint.text = "1. Paint your ring/home path in the GridMap with your MeshLibrary.\n2. Click Detect. 3. Fix any red-flagged cell in the viewport. 4. Detect again."
	workflow_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	workflow_hint.add_theme_font_size_override("font_size", 11)
	dock.add_child(workflow_hint)

	detect_button = Button.new()
	detect_button.text = "Detect Board From GridMap"
	detect_button.disabled = true
	detect_button.pressed.connect(_on_detect_pressed)
	dock.add_child(detect_button)

	debug_checkbox = CheckBox.new()
	debug_checkbox.text = "Debug Mode (labels + red problem markers)"
	debug_checkbox.disabled = true
	debug_checkbox.toggled.connect(_on_debug_toggled)
	dock.add_child(debug_checkbox)

	dock.add_child(HSeparator.new())

	var optional_label := Label.new()
	optional_label.text = "Optional:"
	dock.add_child(optional_label)

	starter_layout_button = Button.new()
	starter_layout_button.text = "Generate Starter Layout (classic cross)"
	starter_layout_button.disabled = true
	starter_layout_button.pressed.connect(_on_starter_layout_pressed)
	dock.add_child(starter_layout_button)

	clear_button = Button.new()
	clear_button.text = "Clear GridMap"
	clear_button.disabled = true
	clear_button.pressed.connect(_on_clear_pressed)
	dock.add_child(clear_button)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _on_selection_changed() -> void:
	_current_target = null
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is LudoBoardGenerator:
			_current_target = node
			break

	var valid := _current_target != null
	detect_button.disabled = not valid
	starter_layout_button.disabled = not valid
	clear_button.disabled = not valid
	debug_checkbox.disabled = not valid

	if valid:
		status_label.text = "Target: %s" % _current_target.name
		debug_checkbox.set_pressed_no_signal(_current_target.debug_mode)
	else:
		status_label.text = "Select a LudoBoardGenerator node."


func _on_detect_pressed() -> void:
	if not _current_target:
		return
	var ok := _current_target.detect_board()
	if ok:
		status_label.text = "OK - %d cellules, %d couleurs." % [
			_current_target.board_data.cells.size(), _current_target.board_data.player_paths.size()
		]
	else:
		status_label.text = "%d problème(s) détecté(s) - voir l'Output et les marqueurs rouges dans la vue 3D." % _current_target.last_detection_errors.size()


func _on_starter_layout_pressed() -> void:
	if _current_target:
		_current_target.generate_starter_layout()
		status_label.text = "Starter layout généré pour %s." % _current_target.name


func _on_clear_pressed() -> void:
	if _current_target:
		_current_target.clear_board()
		status_label.text = "GridMap vidée pour %s." % _current_target.name


func _on_debug_toggled(enabled: bool) -> void:
	if _current_target:
		_current_target.debug_mode = enabled
