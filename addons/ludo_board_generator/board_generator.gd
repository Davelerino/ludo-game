## LudoBoardGenerator
## -------------------
## Workflow: paint your own ring/home path directly in the assigned GridMap
## using its native paint tool and a LudoMeshMapping (ring_mesh_id,
## start_*_mesh_id, home_*_mesh_id). Then click **Detect Board From
## GridMap** - LudoBoardDetector reads back whatever you painted, purely
## from real adjacency (no assumed shape, no fixed size), and reconstructs
## logical BoardData. Enable **Debug Mode** to see exactly what was found:
## every valid cell gets an index/colour label, every PROBLEM cell (branch,
## dead end, wrong attachment point...) gets a red warning marker at its
## exact position, so you can fix it directly in the viewport and detect
## again.
##
## A procedural "Generate Starter Layout" button is also provided as an
## optional convenience: it paints the classic 15x15 cross shape (see
## scripts/ring_path_generator.gd) as a starting scaffold you can then hand-
## edit, but it is NOT required - you can paint entirely from scratch.
##
## Responsibilities (and ONLY these - see GDD companion spec): read/generate
## board visuals and produce BoardData. Explicitly NOT this node's job:
## pawns, dice, capture rules, win conditions, turn order.
@tool
class_name LudoBoardGenerator
extends Node3D

# ---------------------------------------------------------------------------
# Inspector: Mesh Mapping
# ---------------------------------------------------------------------------
@export_group("Mesh Mapping")
## Which MeshLibrary item id means what. Also used in reverse by the
## detector (LudoMeshMapping.classify) to read back a hand-painted GridMap.
@export var mesh_mapping: LudoMeshMapping

# ---------------------------------------------------------------------------
# Inspector: Target
# ---------------------------------------------------------------------------
@export_group("Target")
@export_node_path("GridMap") var grid_map_path: NodePath
@export_file("*.tres") var board_data_save_path: String = "res://addons/ludo_board_generator/generated/board_data.tres"

# ---------------------------------------------------------------------------
# Inspector: Optional Starter Layout
# ---------------------------------------------------------------------------
@export_group("Optional Starter Layout")
## Only used by "Generate Starter Layout" - the classic geometry is fixed
## (52 ring cells, 4 arms) so this only affects the Y layer it's painted on.
@export var elevation: int = 0
@export var board_seed: int = 0

# ---------------------------------------------------------------------------
# Inspector: Debug
# ---------------------------------------------------------------------------
@export_group("Debug")
@export var debug_mode: bool = true:
	set(value):
		debug_mode = value
		if is_inside_tree():
			_update_debug_visuals()
@export var print_ascii_on_detect: bool = true

## The last successfully-detected (or generated) BoardData.
var board_data: LudoBoardData
## Structured problems from the most recent detection:
## Array[{"message": String, "position": Variant}]
var last_detection_errors: Array[Dictionary] = []
var last_detection_warnings: Array[String] = []


# ===========================================================================
# Public API (also called by the editor dock buttons)
# ===========================================================================

## THE primary action: reads whatever is currently painted in the assigned
## GridMap and reconstructs logical BoardData from real adjacency. Never
## modifies the GridMap. Always updates debug visuals (if debug_mode is on)
## and last_detection_errors/warnings, even on failure, so you can see
## exactly what's wrong. Only saves BoardData to disk if detection found
## zero errors.
func detect_board() -> bool:
	var gm := _get_grid_map()
	var result := LudoBoardDetector.detect(gm, mesh_mapping)
	board_data = result.board_data
	last_detection_errors = result.errors
	last_detection_warnings = result.warnings

	if debug_mode:
		_update_debug_visuals()

	if not last_detection_errors.is_empty():
		push_error("LudoBoardGenerator: %d problème(s) détecté(s) :\n - %s" % [
			last_detection_errors.size(),
			"\n - ".join(last_detection_errors.map(func(e): return _format_error(e)))
		])
		return false

	for w in last_detection_warnings:
		push_warning("LudoBoardGenerator: %s" % w)

	_save_board_data(board_data)
	if print_ascii_on_detect:
		_print_ascii_board(board_data)
	print("LudoBoardGenerator: plateau détecté avec succès (%d cases, %d cases ring, %d couleurs)." % [
		board_data.cells.size(), board_data.ring_lane.size(), board_data.player_paths.size()
	])
	return true


## Optional convenience: paints the classic 15x15 cross shape into the
## GridMap as a starting scaffold (pure visual paint, does not itself build
## BoardData), then immediately runs detect_board() on what it just painted
## - both to give you an instantly-valid board AND as a built-in self-test
## that the detector correctly reads back the classic layout.
func generate_starter_layout() -> void:
	if mesh_mapping == null:
		push_error("LudoBoardGenerator: no LudoMeshMapping assigned - aborting.")
		return
	var gm := _get_grid_map()
	if gm == null:
		push_error("LudoBoardGenerator: no GridMap assigned (grid_map_path) - aborting.")
		return

	gm.clear()
	var ring_positions := LudoRingPathGenerator.generate_classic_cross_ring(elevation)
	var side_length := LudoRingPathGenerator.CELLS_PER_ARM
	var color_order := [
		LudoBoardEnums.PlayerColor.RED, LudoBoardEnums.PlayerColor.GREEN,
		LudoBoardEnums.PlayerColor.YELLOW, LudoBoardEnums.PlayerColor.BLUE,
	]

	for i in range(ring_positions.size()):
		var pos: Vector3i = ring_positions[i]
		var arm := i / side_length
		var is_start := (i % side_length) == 0
		var mesh_id := mesh_mapping.mesh_id_for_start(color_order[arm]) if is_start else mesh_mapping.ring_mesh_id
		gm.set_cell_item(pos, mesh_id)

	for arm in range(4):
		var color: int = color_order[arm]
		var start_ring_index := arm * side_length
		var home_entry_index := (start_ring_index - 1 + LudoRingPathGenerator.RING_LENGTH) % LudoRingPathGenerator.RING_LENGTH
		var cursor: Vector3i = ring_positions[home_entry_index]
		var dir := LudoRingPathGenerator.get_home_lane_direction(color)
		for _step in range(5):
			cursor += dir
			gm.set_cell_item(cursor, mesh_mapping.mesh_id_for_home(color))

	detect_board()


func clear_board() -> void:
	var gm := _get_grid_map()
	if gm:
		gm.clear()
	board_data = null
	last_detection_errors.clear()
	last_detection_warnings.clear()
	_clear_debug_visuals()


func get_board_data() -> LudoBoardData:
	if board_data != null:
		return board_data
	if ResourceLoader.exists(board_data_save_path):
		return load(board_data_save_path)
	return null


# ===========================================================================
# Internal
# ===========================================================================

func _get_grid_map() -> GridMap:
	if grid_map_path.is_empty():
		return null
	var node := get_node_or_null(grid_map_path)
	return node if node is GridMap else null


func _save_board_data(data: LudoBoardData) -> void:
	if board_data_save_path.is_empty() or data == null:
		return
	var dir_path := board_data_save_path.get_base_dir()
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := ResourceSaver.save(data, board_data_save_path)
	if err != OK:
		push_error("LudoBoardGenerator: failed to save BoardData to %s (error %d)." % [board_data_save_path, err])
	else:
		print("LudoBoardGenerator: BoardData saved to %s" % board_data_save_path)


func _format_error(e: Dictionary) -> String:
	if e.get("position") != null:
		return "%s [%s]" % [e.message, e.position]
	return e.message


# ===========================================================================
# Debug: 3D overlay (valid cells labeled, problem cells flagged in red) +
# ASCII rendering (bounding-box sized, no assumption about board dimensions)
# ===========================================================================

const _DEBUG_NODE_NAME := "LudoBoardDebugVisuals"

func _update_debug_visuals() -> void:
	_clear_debug_visuals()
	if not debug_mode:
		return
	if board_data == null and last_detection_errors.is_empty():
		return

	var container := Node3D.new()
	container.name = _DEBUG_NODE_NAME
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root

	if board_data:
		for cell in board_data.cells:
			var label := Label3D.new()
			label.text = _debug_label_text(cell)
			label.pixel_size = 0.01
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.modulate = _debug_color_for(cell.color)
			label.position = Vector3(cell.position.x, cell.position.y + 0.6, cell.position.z)
			container.add_child(label)
			if Engine.is_editor_hint():
				label.owner = get_tree().edited_scene_root

	# Problem markers: bright red, oversized, ALWAYS on top of valid-cell
	# labels so they're impossible to miss in the viewport.
	for e in last_detection_errors:
		var pos = e.get("position")
		if pos == null:
			continue
		var marker := Label3D.new()
		marker.text = "⚠ %s" % e.message
		marker.pixel_size = 0.014
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.modulate = Color.RED
		marker.outline_modulate = Color.WHITE
		marker.outline_size = 12
		marker.position = Vector3(pos.x, pos.y + 1.1, pos.z)
		container.add_child(marker)
		if Engine.is_editor_hint():
			marker.owner = get_tree().edited_scene_root


func _clear_debug_visuals() -> void:
	var existing := get_node_or_null(NodePath(_DEBUG_NODE_NAME))
	if existing:
		existing.queue_free()


func _debug_label_text(cell: LudoCell) -> String:
	match cell.type:
		LudoBoardEnums.CellType.START:
			return "S%d" % cell.ring_index
		LudoBoardEnums.CellType.HOME:
			return "H%d" % cell.home_lane_index
		LudoBoardEnums.CellType.CENTER:
			return "C"
		_:
			return str(cell.ring_index)


func _debug_color_for(color: int) -> Color:
	match color:
		LudoBoardEnums.PlayerColor.RED:
			return Color.RED
		LudoBoardEnums.PlayerColor.BLUE:
			return Color.DODGER_BLUE
		LudoBoardEnums.PlayerColor.GREEN:
			return Color.LIME_GREEN
		LudoBoardEnums.PlayerColor.YELLOW:
			return Color.GOLD
		_:
			return Color.WHITE


## Ascii rendering sized to the actual bounding box of the detected cells
## (not a hardcoded 15x15) - works for any custom shape/size you painted.
func _print_ascii_board(data: LudoBoardData) -> void:
	if data == null or data.cells.is_empty():
		return
	var min_x := data.cells[0].position.x
	var max_x := data.cells[0].position.x
	var min_z := data.cells[0].position.z
	var max_z := data.cells[0].position.z
	for cell in data.cells:
		min_x = mini(min_x, cell.position.x)
		max_x = maxi(max_x, cell.position.x)
		min_z = mini(min_z, cell.position.z)
		max_z = maxi(max_z, cell.position.z)

	var width := max_x - min_x + 1
	var height := max_z - min_z + 1
	var grid := []
	for _r in range(height):
		var row := []
		row.resize(width)
		row.fill(" ")
		grid.append(row)

	for cell in data.cells:
		grid[cell.position.z - min_z][cell.position.x - min_x] = _ascii_symbol_for(cell)

	print("--- Ludo Board (ASCII, %dx%d) ---" % [width, height])
	for row in grid:
		print("".join(row))
	print("----------------------------------")


func _ascii_symbol_for(cell: LudoCell) -> String:
	var upper := {
		LudoBoardEnums.PlayerColor.RED: "R",
		LudoBoardEnums.PlayerColor.GREEN: "G",
		LudoBoardEnums.PlayerColor.YELLOW: "Y",
		LudoBoardEnums.PlayerColor.BLUE: "B",
	}
	var lower := {
		LudoBoardEnums.PlayerColor.RED: "r",
		LudoBoardEnums.PlayerColor.GREEN: "g",
		LudoBoardEnums.PlayerColor.YELLOW: "y",
		LudoBoardEnums.PlayerColor.BLUE: "b",
	}
	match cell.type:
		LudoBoardEnums.CellType.START:
			return upper.get(cell.color, "S")
		LudoBoardEnums.CellType.HOME:
			return lower.get(cell.color, "h")
		LudoBoardEnums.CellType.CENTER:
			return "C"
		LudoBoardEnums.CellType.RING:
			return "."
		_:
			return "?"
