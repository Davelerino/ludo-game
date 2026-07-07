## LudoBoardGenerator
## -------------------
## Attach this node anywhere in your scene (typically as a sibling of a
## GridMap). Point `grid_map_path` at your GridMap, assign a LudoMeshMapping,
## then use the "Ludo Board Generator" editor dock (bottom-right by default)
## to Generate / Clear the board.
##
## Responsibilities (and ONLY these - see GDD companion spec):
##   - Read start-tile color/order configuration.
##   - Procedurally generate the ring lane (52 cells) and the 4 home lanes.
##   - Paint the corresponding MeshLibrary items into the GridMap.
##   - Build and persist a LudoBoardData resource (.tres) as the single
##     source of truth other systems (PawnController, RuleEngine, AI,
##     netcode) should depend on.
##
## Explicitly NOT this node's job: pawns, dice, capture rules, win
## conditions, turn order. Those belong to other systems that only ever
## READ the generated LudoBoardData.
@tool
class_name LudoBoardGenerator
extends Node3D

# ---------------------------------------------------------------------------
# Inspector: Board Settings
# ---------------------------------------------------------------------------
@export_group("Board Settings")
## Total ring lane cells. Must be evenly divisible by player_count.
@export var ring_lane_length: int = 52:
	set(value):
		ring_lane_length = maxi(value, 4)
## Number of cells per home lane (including the final CENTER cell).
@export var home_lane_length: int = 6:
	set(value):
		home_lane_length = maxi(value, 2)
## Number of players / arms. Classic Ludo = 4.
@export var player_count: int = 4:
	set(value):
		player_count = clampi(value, 2, 4)
## Y coordinate (GridMap cell elevation) the whole board is generated on.
@export var elevation: int = 0
## Cosmetic-only seed (does not change topology - see GDD §3.5).
@export var board_seed: int = 0

# ---------------------------------------------------------------------------
# Inspector: Mesh Mapping
# ---------------------------------------------------------------------------
@export_group("Mesh Mapping")
## LudoMeshMapping resource describing which MeshLibrary item id to use for
## each logical cell type/color. Never hardcode ids in code - edit this
## resource instead.
@export var mesh_mapping: LudoMeshMapping

# ---------------------------------------------------------------------------
# Inspector: Start Configuration
# ---------------------------------------------------------------------------
@export_group("Start Configuration")
## One entry per color. Only used to determine ANGULAR/PLAY ORDER of the 4
## generated arms - not literal placement (see LudoStartTileConfig).
## If left empty, defaults to RED, BLUE, GREEN, YELLOW in that order.
@export var start_tiles: Array[LudoStartTileConfig] = []
## If true, start_tiles are sorted by angle around their centroid before
## being assigned to arms 0..3, so the order you place them in the array
## doesn't matter as long as positions are roughly correct.
@export var auto_order_by_angle: bool = true

# ---------------------------------------------------------------------------
# Inspector: Target
# ---------------------------------------------------------------------------
@export_group("Target")
## Path to the GridMap that should receive the generated visuals. Optional:
## if empty, generation still produces valid BoardData, it just isn't painted.
@export_node_path("GridMap") var grid_map_path: NodePath
## Where to persist the generated BoardData as a .tres Resource.
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

## The last generated BoardData. Also what gets saved to board_data_save_path.
var board_data: LudoBoardData


# ===========================================================================
# Public API (also called by the editor dock buttons)
# ===========================================================================

func generate_board() -> void:
	if mesh_mapping == null:
		push_error("LudoBoardGenerator: no LudoMeshMapping assigned - aborting generation.")
		return

	var side_length := ring_lane_length / player_count
	if side_length * player_count != ring_lane_length:
		push_error("LudoBoardGenerator: ring_lane_length (%d) must be divisible by player_count (%d)." % [ring_lane_length, player_count])
		return
	if side_length < 2:
		push_error("LudoBoardGenerator: side_length too small (%d) - increase ring_lane_length." % side_length)
		return

	clear_board()

	var ordered_colors := _resolve_player_color_order()
	var new_board := _build_board_data(side_length, ordered_colors)

	var validation := LudoBoardValidator.validate_all(new_board)
	if not validation.valid:
		push_error("LudoBoardGenerator: generated board failed validation:\n - " + "\n - ".join(validation.errors))
		return

	board_data = new_board
	_paint_gridmap(board_data)
	_save_board_data(board_data)

	if debug_mode:
		_update_debug_visuals()
		_print_debug_info(board_data)

	print("LudoBoardGenerator: board generated successfully (%d cells, %d ring, %d colors)." % [
		board_data.cells.size(), board_data.ring_lane.size(), board_data.player_paths.size()
	])


func clear_board() -> void:
	var gm := _get_grid_map()
	if gm:
		gm.clear()
	board_data = null
	_clear_debug_visuals()


## Returns the current BoardData, loading it from disk if this node hasn't
## generated one in memory yet (useful for gameplay scripts that just want
## to consume the data without re-running generation).
func get_board_data() -> LudoBoardData:
	if board_data != null:
		return board_data
	if ResourceLoader.exists(board_data_save_path):
		return load(board_data_save_path)
	return null


## Alternative to manual start_tiles configuration: scans the assigned
## GridMap for cells whose item id matches one of the configured start mesh
## ids in `mesh_mapping`, and rebuilds `start_tiles` from what it finds.
## Provided for the "auto-detection" workflow mentioned in the spec; manual
## configuration remains the default because it is more predictable.
func detect_start_tiles_from_gridmap() -> void:
	var gm := _get_grid_map()
	if gm == null or mesh_mapping == null:
		push_warning("LudoBoardGenerator: need both a GridMap and a MeshMapping to auto-detect start tiles.")
		return

	var mesh_to_color := {
		mesh_mapping.start_red_mesh_id: LudoBoardEnums.PlayerColor.RED,
		mesh_mapping.start_blue_mesh_id: LudoBoardEnums.PlayerColor.BLUE,
		mesh_mapping.start_green_mesh_id: LudoBoardEnums.PlayerColor.GREEN,
		mesh_mapping.start_yellow_mesh_id: LudoBoardEnums.PlayerColor.YELLOW,
	}

	var found: Array[LudoStartTileConfig] = []
	for cell_pos in gm.get_used_cells():
		var item := gm.get_cell_item(cell_pos)
		if mesh_to_color.has(item):
			var cfg := LudoStartTileConfig.new()
			cfg.color = mesh_to_color[item]
			cfg.grid_position = cell_pos
			found.append(cfg)

	if found.size() != player_count:
		push_warning("LudoBoardGenerator: auto-detection found %d start tiles, expected %d." % [found.size(), player_count])

	start_tiles = found
	notify_property_list_changed()


# ===========================================================================
# Generation pipeline (internal)
# ===========================================================================

func _resolve_player_color_order() -> Array[int]:
	var colors: Array[int] = []

	if start_tiles.size() > 0:
		var configs := start_tiles.duplicate()
		if auto_order_by_angle and configs.size() > 1:
			var centroid := Vector2.ZERO
			for cfg in configs:
				centroid += Vector2(cfg.grid_position.x, cfg.grid_position.z)
			centroid /= configs.size()
			configs.sort_custom(func(a: LudoStartTileConfig, b: LudoStartTileConfig) -> bool:
				var angle_a := (Vector2(a.grid_position.x, a.grid_position.z) - centroid).angle()
				var angle_b := (Vector2(b.grid_position.x, b.grid_position.z) - centroid).angle()
				return angle_a < angle_b
			)
		for cfg in configs:
			colors.append(cfg.color)

	# Fill any remaining arms with the canonical RED/BLUE/GREEN/YELLOW order.
	var defaults := LudoBoardEnums.all_colors()
	var i := 0
	while colors.size() < player_count:
		colors.append(defaults[i % defaults.size()])
		i += 1

	return colors


func _build_board_data(side_length: int, ordered_colors: Array[int]) -> LudoBoardData:
	var new_board := LudoBoardData.new()
	new_board.ring_lane_length = ring_lane_length
	new_board.home_lane_length = home_lane_length
	new_board.board_seed = board_seed
	new_board.generated_at_unix = Time.get_unix_time_from_system()

	var ring_positions := LudoRingPathGenerator.generate_ring_square(side_length, elevation)
	var inward_dirs := LudoRingPathGenerator.get_inward_directions()

	var cells: Array[LudoCell] = []
	var ring_ids: Array[int] = []
	var index_map: Dictionary = {}

	# --- Ring + start cells -------------------------------------------------
	for i in range(ring_positions.size()):
		var pos: Vector3i = ring_positions[i]
		var arm := i / side_length
		var is_start := (i % side_length) == 0

		var cell := LudoCell.new()
		cell.id = cells.size()
		cell.position = pos
		cell.ring_index = i

		if is_start:
			cell.type = LudoBoardEnums.CellType.START
			cell.color = ordered_colors[arm]
			cell.mesh_id = mesh_mapping.mesh_id_for_start(cell.color)
		else:
			cell.type = LudoBoardEnums.CellType.RING
			cell.color = LudoBoardEnums.PlayerColor.NONE
			cell.mesh_id = mesh_mapping.ring_mesh_id

		cells.append(cell)
		ring_ids.append(cell.id)
		index_map[pos] = cell.id

	# Ring neighbors (closed loop: last wraps to first).
	for i in range(ring_ids.size()):
		var current_cell: LudoCell = cells[ring_ids[i]]
		var next_cell: LudoCell = cells[ring_ids[(i + 1) % ring_ids.size()]]
		var prev_cell: LudoCell = cells[ring_ids[(i - 1 + ring_ids.size()) % ring_ids.size()]]
		current_cell.neighbors = [prev_cell.id, next_cell.id]

	# --- Player paths + home lanes ------------------------------------------
	var player_paths: Dictionary = {}
	for arm in range(player_count):
		var color: int = ordered_colors[arm]
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
		var dir: Vector3i = inward_dirs[arm]
		var cursor := home_entry_cell.position
		var home_cell_ids: Array[int] = []

		for step in range(home_lane_length):
			cursor += dir
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

		# Chain neighbors within the home lane, plus link back to the ring.
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
	new_board.center_position = Vector3i(side_length / 2, elevation, side_length / 2)

	return new_board


func _get_grid_map() -> GridMap:
	if grid_map_path.is_empty():
		return null
	var node := get_node_or_null(grid_map_path)
	return node if node is GridMap else null


func _paint_gridmap(data: LudoBoardData) -> void:
	var gm := _get_grid_map()
	if gm == null:
		push_warning("LudoBoardGenerator: no GridMap assigned (grid_map_path) - BoardData was generated but not painted.")
		return
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
	var validation := LudoBoardValidator.validate_all(data)
	print("Validation: %s" % ("OK" if validation.valid else "FAILED (%d errors)" % validation.errors.size()))
	print("-------------------------")


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
