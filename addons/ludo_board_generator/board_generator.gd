## LudoBoardGenerator
## -------------------
## Attach this node anywhere in your scene (typically as a sibling of a
## GridMap). Point `grid_map_path` at your GridMap, assign a LudoMeshMapping,
## then use the "Ludo Board Generator" editor dock (bottom-right by default)
## to Generate / Clear the board.
##
## Generates the CLASSIC 15x15 cross-shaped Ludo ring lane (52 cells, 4 start
## tiles at the fixed real-board offsets 0/13/26/39) plus 4 home lanes - see
## scripts/ring_path_generator.gd for the geometry itself.
##
## MANUAL ADJUSTMENT ARCHITECTURE (3 layers):
##   1. Procedural base  - LudoRingPathGenerator (fixed classic geometry).
##   2. Override layer   - `overrides` (LudoBoardOverrides resource): forced
##      positions keyed by a STABLE string ("ring:13", "home:0:2"), applied
##      on top of the procedural base every regeneration. Topology (which
##      cell is adjacent to which) never changes - only positions do - so
##      LudoBoardValidator still catches illegal manual nudges immediately.
##   3. Live layer       - when `live_preview` is on, any relevant edit
##      (inspector OR the in-viewport gizmo, see editor/board_gizmo_plugin.gd)
##      triggers an immediate lightweight rebuild + repaint + revalidation,
##      without waiting for "Generate Board". The gizmo uses a cheap
##      in-memory `preview_override()` while dragging (no disk save, no
##      console spam) and only calls the authoritative, saved
##      `commit_override()` on mouse release, wrapped in EditorUndoRedoManager
##      for Ctrl+Z support.
##
## Responsibilities (and ONLY these - see GDD companion spec): generate the
## board data + visuals. Explicitly NOT this node's job: pawns, dice,
## capture rules, win conditions, turn order.
@tool
class_name LudoBoardGenerator
extends Node3D

# ---------------------------------------------------------------------------
# Inspector: Board Settings
# ---------------------------------------------------------------------------
@export_group("Board Settings")
## Fixed by the classic 15x15 cross geometry - see ring_path_generator.gd.
@export var ring_lane_length: int = LudoRingPathGenerator.RING_LENGTH:
	set(value):
		ring_lane_length = LudoRingPathGenerator.RING_LENGTH
## Number of cells per home lane (5 = classic board).
@export var home_lane_length: int = 5:
	set(value):
		home_lane_length = maxi(value, 1)
		_on_setting_changed()
## Fixed at 4 - the classic cross geometry only has 4 arms.
@export var player_count: int = 4:
	set(value):
		player_count = 4
## Y coordinate (GridMap cell elevation) the whole board is generated on.
@export var elevation: int = 0:
	set(value):
		elevation = value
		_on_setting_changed()
## Cosmetic-only seed (does not change topology - see GDD §3.5).
@export var board_seed: int = 0

# ---------------------------------------------------------------------------
# Inspector: Mesh Mapping
# ---------------------------------------------------------------------------
@export_group("Mesh Mapping")
@export var mesh_mapping: LudoMeshMapping:
	set(value):
		mesh_mapping = value
		_on_setting_changed()

# ---------------------------------------------------------------------------
# Inspector: Start Configuration
# ---------------------------------------------------------------------------
@export_group("Start Configuration")
## Which colour goes to which of the 4 fixed geometric arms, in traversal
## order. Defaults to RED / GREEN / YELLOW / BLUE.
@export var color_order: Array[int] = [
	LudoBoardEnums.PlayerColor.RED,
	LudoBoardEnums.PlayerColor.GREEN,
	LudoBoardEnums.PlayerColor.YELLOW,
	LudoBoardEnums.PlayerColor.BLUE,
]:
	set(value):
		color_order = value
		_on_setting_changed()

# ---------------------------------------------------------------------------
# Inspector: Manual Adjustments
# ---------------------------------------------------------------------------
@export_group("Manual Adjustments")
## Manual position overrides layered on top of the procedural generation -
## see LudoBoardOverrides and the class doc comment above. Editable directly
## in the inspector (as a Dictionary of "ring:13" -> Vector3i), or via the
## in-viewport gizmo, or via preview_override()/commit_override() from code.
@export var overrides: LudoBoardOverrides:
	set(value):
		if overrides and overrides.changed.is_connected(_on_overrides_changed):
			overrides.changed.disconnect(_on_overrides_changed)
		overrides = value
		if overrides:
			overrides.changed.connect(_on_overrides_changed)
		_on_setting_changed()
## When true, ANY relevant change (inspector fields above, or gizmo drag)
## immediately rebuilds + repaints + revalidates the board, instead of
## requiring a manual "Generate Board" click. Disk save + full console
## report still only happen on an explicit Generate or gizmo commit, keeping
## continuous edits (e.g. dragging a handle) cheap and quiet.
@export var live_preview: bool = true

# ---------------------------------------------------------------------------
# Inspector: Target
# ---------------------------------------------------------------------------
@export_group("Target")
@export_node_path("GridMap") var grid_map_path: NodePath:
	set(value):
		grid_map_path = value
		_on_setting_changed()
@export_file("*.tres") var board_data_save_path: String = "res://addons/ludo_board_generator/generated/board_data.tres"

# ---------------------------------------------------------------------------
# Inspector: Debug
# ---------------------------------------------------------------------------
@export_group("Debug")
@export var debug_mode: bool = false:
	set(value):
		debug_mode = value
		if is_inside_tree():
			_update_debug_visuals()
@export var print_ascii_on_generate: bool = true

## The last generated BoardData. Also what gets saved to board_data_save_path.
var board_data: LudoBoardData
## Errors from the most recent (possibly silent, preview-mode) validation.
## Read by the dock/gizmo to surface problems without spamming the console.
var last_validation_errors: Array[String] = []


func _ready() -> void:
	if overrides and not overrides.changed.is_connected(_on_overrides_changed):
		overrides.changed.connect(_on_overrides_changed)


# ===========================================================================
# Public API (also called by the editor dock buttons and the gizmo plugin)
# ===========================================================================

## Full, authoritative generation: rebuild, validate (loud), paint, save to
## disk, refresh debug visuals/ASCII. Use this for the dock's "Generate
## Board" button and after a gizmo commit.
func generate_board() -> void:
	if not _regenerate(true, true):
		return
	print("LudoBoardGenerator: board generated successfully (%d cells, %d ring, %d colors)." % [
		board_data.cells.size(), board_data.ring_lane.size(), board_data.player_paths.size()
	])


func clear_board() -> void:
	var gm := _get_grid_map()
	if gm:
		gm.clear()
	board_data = null
	last_validation_errors.clear()
	_clear_debug_visuals()


## Wipes every manual override and regenerates from the pure procedural
## base. Bound to the dock's "Reset All Manual Overrides" button.
func clear_all_overrides() -> void:
	if overrides:
		overrides.clear_all()
	elif live_preview:
		_regenerate(true, true)


func get_board_data() -> LudoBoardData:
	if board_data != null:
		return board_data
	if ResourceLoader.exists(board_data_save_path):
		return load(board_data_save_path)
	return null


# ===========================================================================
# Manual adjustment API (used by the in-viewport gizmo, and usable from code)
# ===========================================================================

## Returns every editable "slot" (ring cell or home lane cell) as
## {"key": String, "position": Vector3i}, in a stable order used as gizmo
## handle ids by editor/board_gizmo_plugin.gd.
func get_editable_slots() -> Array[Dictionary]:
	if board_data == null:
		return []
	var slots: Array[Dictionary] = []
	for i in range(board_data.ring_lane.size()):
		var cell := board_data.get_cell(board_data.ring_lane[i])
		slots.append({"key": _ring_key(i), "position": cell.position})
	for color in board_data.player_paths.keys():
		var path: LudoPlayerPath = board_data.player_paths[color]
		for step in range(path.home_lane_cell_ids.size()):
			var cell := board_data.get_cell(path.home_lane_cell_ids[step])
			slots.append({"key": _home_key(color, step), "position": cell.position})
	return slots


## Cheap, in-memory-only nudge: rebuilds + repaints + validates silently
## (errors go to last_validation_errors, not push_error/console), does NOT
## save to disk. Meant to be called every frame while dragging a gizmo
## handle.
func preview_override(key: String, grid_pos: Vector3i) -> void:
	_ensure_overrides()
	overrides.position_overrides[key] = grid_pos # avoid emit_changed() feedback loop mid-drag
	_regenerate(false, false)
	if Engine.is_editor_hint():
		update_gizmos()


## Authoritative nudge: writes the override (via the resource, so it emits
## `changed` and participates in undo/redo when set through
## EditorUndoRedoManager), then does a full loud regeneration + save.
func commit_override(key: String, grid_pos: Vector3i) -> void:
	_ensure_overrides()
	overrides.set_override(key, grid_pos)
	generate_board()
	if Engine.is_editor_hint():
		update_gizmos()


func clear_override(key: String) -> void:
	if overrides:
		overrides.clear_override(key)


## Converts a GridMap cell coordinate to this node's local 3D space, going
## through the actual assigned GridMap's cell_size/transform so gizmo
## handles line up correctly regardless of cell size or relative transform.
## Falls back to a 1-unit-per-cell assumption if no GridMap is assigned.
func grid_to_local(grid_pos: Vector3i) -> Vector3:
	var gm := _get_grid_map()
	if gm == null:
		return Vector3(grid_pos)
	var global_pos := gm.to_global(gm.map_to_local(grid_pos))
	return to_local(global_pos)


## Inverse of grid_to_local: snaps a local-space position back to the
## nearest GridMap cell coordinate.
func local_to_grid(local_pos: Vector3) -> Vector3i:
	var gm := _get_grid_map()
	if gm == null:
		return Vector3i(roundi(local_pos.x), roundi(local_pos.y), roundi(local_pos.z))
	var gm_local := gm.to_local(to_global(local_pos))
	return gm.local_to_map(gm_local)


# ===========================================================================
# Generation pipeline (internal)
# ===========================================================================

func _ring_key(ring_index: int) -> String:
	return "ring:%d" % ring_index


func _home_key(color: int, home_index: int) -> String:
	return "home:%d:%d" % [color, home_index]


func _ensure_overrides() -> void:
	if overrides == null:
		overrides = LudoBoardOverrides.new()


func _on_setting_changed() -> void:
	if live_preview and is_inside_tree():
		_regenerate(false, false)


func _on_overrides_changed() -> void:
	if live_preview and is_inside_tree():
		_regenerate(false, false)


## Core regeneration routine.
##   save_to_disk: persist BoardData to board_data_save_path and paint the
##                 GridMap. Skipped during pure in-memory gizmo previews only
##                 if you pass false explicitly - normally true.
##   verbose:      push_error on failure / print success & ASCII board.
##                 False during live-preview edits, so dragging a handle or
##                 tweaking a field doesn't spam the Output panel with
##                 transient "invalid" states while you're mid-edit.
## Returns true if the resulting board is valid.
func _regenerate(save_to_disk: bool, verbose: bool) -> bool:
	if mesh_mapping == null:
		if verbose:
			push_error("LudoBoardGenerator: no LudoMeshMapping assigned - aborting generation.")
		return false
	if color_order.size() != player_count:
		if verbose:
			push_error("LudoBoardGenerator: color_order must have exactly %d entries (found %d)." % [player_count, color_order.size()])
		return false

	var new_board := _build_board_data()
	var validation := LudoBoardValidator.validate_all(new_board)
	last_validation_errors = validation.errors

	if not validation.valid:
		if verbose:
			push_error("LudoBoardGenerator: generated board failed validation:\n - " + "\n - ".join(validation.errors))
		return false

	board_data = new_board

	if save_to_disk:
		_paint_gridmap(board_data)
		_save_board_data(board_data)
	else:
		# Still repaint the GridMap for live visual feedback, just skip the
		# disk write (cheap - GridMap.set_cell_item is not I/O).
		_paint_gridmap(board_data)

	if debug_mode:
		_update_debug_visuals()
		if verbose:
			_print_debug_info(board_data)
	if verbose and print_ascii_on_generate:
		_print_ascii_board(board_data)

	return true


func _build_board_data() -> LudoBoardData:
	var new_board := LudoBoardData.new()
	new_board.ring_lane_length = ring_lane_length
	new_board.home_lane_length = home_lane_length
	new_board.board_seed = board_seed
	new_board.generated_at_unix = Time.get_unix_time_from_system()

	var ring_positions := LudoRingPathGenerator.generate_classic_cross_ring(elevation)
	var side_length := LudoRingPathGenerator.CELLS_PER_ARM

	var cells: Array[LudoCell] = []
	var ring_ids: Array[int] = []
	var index_map: Dictionary = {}

	# --- Ring + start cells (procedural position, then override layer) -----
	for i in range(ring_positions.size()):
		var pos: Vector3i = ring_positions[i]
		if overrides and overrides.has_override(_ring_key(i)):
			pos = overrides.get_override(_ring_key(i), pos)

		var arm := i / side_length
		var is_start := (i % side_length) == 0

		var cell := LudoCell.new()
		cell.id = cells.size()
		cell.position = pos
		cell.ring_index = i

		if is_start:
			cell.type = LudoBoardEnums.CellType.START
			cell.color = color_order[arm]
			cell.mesh_id = mesh_mapping.mesh_id_for_start(cell.color)
		else:
			cell.type = LudoBoardEnums.CellType.RING
			cell.color = LudoBoardEnums.PlayerColor.NONE
			cell.mesh_id = mesh_mapping.ring_mesh_id

		cells.append(cell)
		ring_ids.append(cell.id)
		index_map[pos] = cell.id

	# Ring neighbors are INDEX-based (topology never changes from overrides),
	# closed loop: last wraps to first.
	for i in range(ring_ids.size()):
		var current_cell: LudoCell = cells[ring_ids[i]]
		var next_cell: LudoCell = cells[ring_ids[(i + 1) % ring_ids.size()]]
		var prev_cell: LudoCell = cells[ring_ids[(i - 1 + ring_ids.size()) % ring_ids.size()]]
		current_cell.neighbors = [prev_cell.id, next_cell.id]

	# --- Player paths + home lanes ------------------------------------------
	var player_paths: Dictionary = {}
	for arm in range(player_count):
		var color: int = color_order[arm]
		var start_ring_index := arm * side_length
		var home_entry_index := (start_ring_index - 1 + ring_lane_length) % ring_lane_length
		var start_cell: LudoCell = cells[ring_ids[start_ring_index]]

		var path := LudoPlayerPath.new()
		path.color = color
		path.start_tile_id = start_cell.id
		path.start_tile_position = start_cell.position
		path.ring_entry_index = start_ring_index
		path.home_entry_index = home_entry_index

		var home_entry_cell: LudoCell = cells[ring_ids[home_entry_index]]
		var dir: Vector3i = LudoRingPathGenerator.get_home_lane_direction(color)
		var cursor := home_entry_cell.position
		var home_cell_ids: Array[int] = []

		for step in range(home_lane_length):
			# Natural (procedural) next position continues from the actual
			# (possibly already-overridden) previous cell, so overriding one
			# cell drags the rest of that chain along with it unless THEY
			# are also individually overridden.
			cursor += dir
			var key := _home_key(color, step)
			if overrides and overrides.has_override(key):
				cursor = overrides.get_override(key, cursor)

			var hcell := LudoCell.new()
			hcell.id = cells.size()
			hcell.position = cursor
			hcell.color = color
			hcell.home_lane_index = step

			if step == home_lane_length - 1:
				hcell.type = LudoBoardEnums.CellType.CENTER
				hcell.mesh_id = mesh_mapping.center_mesh_id
				path.center_cell_id = hcell.id
			else:
				hcell.type = LudoBoardEnums.CellType.HOME
				hcell.mesh_id = mesh_mapping.mesh_id_for_home(color)

			cells.append(hcell)
			home_cell_ids.append(hcell.id)
			index_map[cursor] = hcell.id

		for step in range(home_cell_ids.size()):
			var hc: LudoCell = cells[home_cell_ids[step]]
			var nb: Array[int] = []
			nb.append(home_entry_cell.id if step == 0 else home_cell_ids[step - 1])
			if step < home_cell_ids.size() - 1:
				nb.append(home_cell_ids[step + 1])
			hc.neighbors = nb
		home_entry_cell.neighbors.append(home_cell_ids[0])

		path.home_lane_cell_ids = home_cell_ids
		player_paths[color] = path

	new_board.cells = cells
	new_board.ring_lane = ring_ids
	new_board.index_map = index_map
	new_board.player_paths = player_paths
	new_board.center_position = LudoRingPathGenerator.board_center(elevation)

	return new_board


func _get_grid_map() -> GridMap:
	if grid_map_path.is_empty():
		return null
	var node := get_node_or_null(grid_map_path)
	return node if node is GridMap else null


func _paint_gridmap(data: LudoBoardData) -> void:
	var gm := _get_grid_map()
	if gm == null:
		return
	gm.clear()
	for cell in data.cells:
		if cell.mesh_id >= 0:
			gm.set_cell_item(cell.position, cell.mesh_id)


func _save_board_data(data: LudoBoardData) -> void:
	if board_data_save_path.is_empty():
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


# ===========================================================================
# Debug mode
# ===========================================================================

const _DEBUG_NODE_NAME := "LudoBoardDebugVisuals"

func _print_debug_info(data: LudoBoardData) -> void:
	print("--- Ludo Board Debug ---")
	print("Ring cells: %d | Home lane length: %d" % [data.ring_lane.size(), data.home_lane_length])
	for color in data.player_paths.keys():
		var path: LudoPlayerPath = data.player_paths[color]
		print(" %s: start ring idx=%d @ %s | home entry idx=%d | centre cell id=%d" % [
			LudoBoardEnums.color_name(color), path.ring_entry_index, path.start_tile_position,
			path.home_entry_index, path.center_cell_id
		])
	print("Validation: %s" % ("OK" if last_validation_errors.is_empty() else "FAILED (%d errors)" % last_validation_errors.size()))
	print("-------------------------")


func _print_ascii_board(data: LudoBoardData) -> void:
	var size := LudoRingPathGenerator.BOARD_SIZE
	var grid := []
	for _r in range(size):
		var row := []
		row.resize(size)
		row.fill(" ")
		grid.append(row)

	for cell in data.cells:
		var col := cell.position.x
		var row := cell.position.z
		if row < 0 or row >= size or col < 0 or col >= size:
			continue
		grid[row][col] = _ascii_symbol_for(cell)

	print("--- Ludo Board (ASCII, 15x15) ---")
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


func _update_debug_visuals() -> void:
	_clear_debug_visuals()
	if not debug_mode or board_data == null:
		return

	var container := Node3D.new()
	container.name = _DEBUG_NODE_NAME
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root

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
