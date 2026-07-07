## Editor entry point for the Ludo Board Generator plugin.
##
## `LudoBoardGenerator` is a plain @tool script with `class_name`, so Godot 4
## already lists it in the "Create Node" dialog automatically - no
## add_custom_type() registration needed. This plugin adds:
##   - a dock with Generate / Clear / Live Preview / Debug / Reset-Overrides
##     controls that act on whichever LudoBoardGenerator node is selected;
##   - a Node3D gizmo (board_gizmo_plugin.gd) that lets you drag ring/home
##     cells directly in the 3D viewport.
@tool
extends EditorPlugin

const LudoBoardGizmoPluginScript = preload("res://addons/ludo_board_generator/editor/board_gizmo_plugin.gd")

var dock: VBoxContainer
var status_label: Label
var generate_button: Button
var clear_button: Button
var reset_overrides_button: Button
var debug_checkbox: CheckBox
var live_preview_checkbox: CheckBox

var gizmo_plugin: EditorNode3DGizmoPlugin

var _current_target: LudoBoardGenerator = null


func _enter_tree() -> void:
	_build_dock()

	gizmo_plugin = LudoBoardGizmoPluginScript.new()
	gizmo_plugin.undo_redo = get_undo_redo()
	add_node_3d_gizmo_plugin(gizmo_plugin)

	get_editor_interface().get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()


func _exit_tree() -> void:
	if get_editor_interface().get_selection().selection_changed.is_connected(_on_selection_changed):
		get_editor_interface().get_selection().selection_changed.disconnect(_on_selection_changed)
	if gizmo_plugin:
		remove_node_3d_gizmo_plugin(gizmo_plugin)
		gizmo_plugin = null
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

	generate_button = Button.new()
	generate_button.text = "Generate Board"
	generate_button.disabled = true
	generate_button.pressed.connect(_on_generate_pressed)
	dock.add_child(generate_button)

	clear_button = Button.new()
	clear_button.text = "Clear Board"
	clear_button.disabled = true
	clear_button.pressed.connect(_on_clear_pressed)
	dock.add_child(clear_button)

	dock.add_child(HSeparator.new())

	live_preview_checkbox = CheckBox.new()
	live_preview_checkbox.text = "Live Preview (auto-update on edit/drag)"
	live_preview_checkbox.disabled = true
	live_preview_checkbox.toggled.connect(_on_live_preview_toggled)
	dock.add_child(live_preview_checkbox)

	reset_overrides_button = Button.new()
	reset_overrides_button.text = "Reset All Manual Overrides"
	reset_overrides_button.disabled = true
	reset_overrides_button.pressed.connect(_on_reset_overrides_pressed)
	dock.add_child(reset_overrides_button)

	dock.add_child(HSeparator.new())

	debug_checkbox = CheckBox.new()
	debug_checkbox.text = "Debug Mode (indices, colors, connections)"
	debug_checkbox.disabled = true
	debug_checkbox.toggled.connect(_on_debug_toggled)
	dock.add_child(debug_checkbox)

	var hint := Label.new()
	hint.text = "Tip: with Live Preview on, drag the white/yellow handles directly in the 3D viewport to nudge cells - changes apply instantly and support Ctrl+Z."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", 11)
	dock.add_child(hint)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _on_selection_changed() -> void:
	_current_target = null
	for node in get_editor_interface().get_selection().get_selected_nodes():
		if node is LudoBoardGenerator:
			_current_target = node
			break

	var valid := _current_target != null
	generate_button.disabled = not valid
	clear_button.disabled = not valid
	debug_checkbox.disabled = not valid
	live_preview_checkbox.disabled = not valid
	reset_overrides_button.disabled = not valid

	if valid:
		status_label.text = "Target: %s" % _current_target.name
		debug_checkbox.set_pressed_no_signal(_current_target.debug_mode)
		live_preview_checkbox.set_pressed_no_signal(_current_target.live_preview)
	else:
		status_label.text = "Select a LudoBoardGenerator node."


func _on_generate_pressed() -> void:
	if _current_target:
		_current_target.generate_board()
		status_label.text = "Board generated for %s." % _current_target.name


func _on_clear_pressed() -> void:
	if _current_target:
		_current_target.clear_board()
		status_label.text = "Board cleared for %s." % _current_target.name


func _on_live_preview_toggled(enabled: bool) -> void:
	if _current_target:
		_current_target.live_preview = enabled


func _on_reset_overrides_pressed() -> void:
	if _current_target:
		_current_target.clear_all_overrides()
		status_label.text = "Manual overrides cleared for %s." % _current_target.name


func _on_debug_toggled(enabled: bool) -> void:
	if _current_target:
		_current_target.debug_mode = enabled
