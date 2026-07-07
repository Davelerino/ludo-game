## In-viewport gizmo for LudoBoardGenerator: draws every ring/home cell as a
## draggable handle, and every ring-to-ring / home-chain link as a line, so
## the board can be nudged by clicking and dragging directly in the 3D view.
##
## Talks to the node exclusively through its public manual-adjustment API
## (get_editable_slots / grid_to_local / local_to_grid / preview_override /
## commit_override) - this file has zero knowledge of ring/home lane
## internals, it's purely an input-to-grid-coordinate adapter.
##
## NOTE ON GODOT VERSION SENSITIVITY: the EditorNode3DGizmoPlugin handle
## callback signatures (_get_handle_value / _set_handle / _commit_handle)
## have shifted slightly across Godot 4.x minor versions. This is written
## against the 4.x API as of this writing; if your exact version rejects a
## signature, check "EditorNode3DGizmoPlugin" in the class reference for
## that version and adjust the parameter list accordingly - the rest of the
## manual-adjustment system (LudoBoardOverrides + live_preview on the node)
## works completely independently of this file and does not need the gizmo
## to function.
@tool
class_name LudoBoardGizmoPlugin
extends EditorNode3DGizmoPlugin

## Set by plugin.gd so commits can go through the editor's undo/redo stack.
var undo_redo: EditorUndoRedoManager

const HANDLE_COLOR_RING := Color(1.0, 1.0, 1.0, 0.9)
const HANDLE_COLOR_HOME := Color(1.0, 0.85, 0.2, 0.9)
const LINE_COLOR := Color(0.3, 0.8, 1.0, 0.6)

# Cached per-gizmo so _set_handle/_commit_handle can recover the ORIGINAL
# (drag-start) position without re-deriving it from board state that may
# already have changed mid-drag.
var _drag_start_positions: Dictionary = {} # handle_id -> Vector3i

var _ring_handle_material: StandardMaterial3D
var _home_handle_material: StandardMaterial3D


func _init() -> void:
	# create_handle_material()'s 3rd argument is a Texture2D (for a custom
	# handle icon), not a Color - building plain StandardMaterial3D ourselves
	# and passing them directly to add_handles() is simpler and version-safe.
	_ring_handle_material = _make_handle_material(HANDLE_COLOR_RING)
	_home_handle_material = _make_handle_material(HANDLE_COLOR_HOME)
	create_material("path_lines", LINE_COLOR)


func _make_handle_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.render_priority = 10
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = false
	mat.use_point_size = true
	mat.point_size = 12.0
	return mat


func _get_gizmo_name() -> String:
	return "LudoBoardGenerator"


func _has_gizmo(node: Node3D) -> bool:
	return node is LudoBoardGenerator


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d() as LudoBoardGenerator
	if node == null or node.board_data == null:
		return

	var slots := node.get_editable_slots()
	if slots.is_empty():
		return

	var ring_points := PackedVector3Array()
	var ring_ids := PackedInt32Array()
	var home_points := PackedVector3Array()
	var home_ids := PackedInt32Array()
	var lines := PackedVector3Array()

	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		var local_pos := node.grid_to_local(slot.position)
		var key: String = slot.key
		if key.begins_with("ring:"):
			ring_points.append(local_pos)
			ring_ids.append(i)
		else:
			home_points.append(local_pos)
			home_ids.append(i)

	if not ring_points.is_empty():
		gizmo.add_handles(ring_points, _ring_handle_material, ring_ids)
	if not home_points.is_empty():
		gizmo.add_handles(home_points, _home_handle_material, home_ids)

	# Draw the ring loop + each home lane chain as connecting lines, purely
	# cosmetic (helps you see the path while dragging).
	var ring_count := node.board_data.ring_lane.size()
	for i in range(ring_count):
		var a := node.grid_to_local(node.board_data.get_cell(node.board_data.ring_lane[i]).position)
		var b := node.grid_to_local(node.board_data.get_cell(node.board_data.ring_lane[(i + 1) % ring_count]).position)
		lines.append(a)
		lines.append(b)
	for color in node.board_data.player_paths.keys():
		var path: LudoPlayerPath = node.board_data.player_paths[color]
		var prev := node.grid_to_local(node.board_data.get_cell(node.board_data.ring_lane[path.home_entry_index]).position)
		for cell_id in path.home_lane_cell_ids:
			var cur := node.grid_to_local(node.board_data.get_cell(cell_id).position)
			lines.append(prev)
			lines.append(cur)
			prev = cur

	if not lines.is_empty():
		gizmo.add_lines(lines, get_material("path_lines", gizmo))


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> String:
	var node := gizmo.get_node_3d() as LudoBoardGenerator
	var slots := node.get_editable_slots()
	if handle_id < 0 or handle_id >= slots.size():
		return "?"
	return slots[handle_id].key


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool) -> Variant:
	var node := gizmo.get_node_3d() as LudoBoardGenerator
	var slots := node.get_editable_slots()
	if handle_id < 0 or handle_id >= slots.size():
		return Vector3i.ZERO
	var pos: Vector3i = slots[handle_id].position
	_drag_start_positions[handle_id] = pos
	return pos


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d() as LudoBoardGenerator
	var slots := node.get_editable_slots()
	if handle_id < 0 or handle_id >= slots.size():
		return
	var key: String = slots[handle_id].key

	var original_grid: Vector3i = _drag_start_positions.get(handle_id, slots[handle_id].position)
	var original_local := node.grid_to_local(original_grid)
	var plane_height := node.to_global(original_local).y

	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, plane_height)
	var hit = plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return

	var new_local := node.to_local(hit)
	var new_grid := node.local_to_grid(new_local)
	node.preview_override(key, new_grid)


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d() as LudoBoardGenerator
	var slots := node.get_editable_slots()
	if handle_id < 0 or handle_id >= slots.size():
		return
	var key: String = slots[handle_id].key
	var original_grid: Vector3i = restore if restore is Vector3i else _drag_start_positions.get(handle_id, slots[handle_id].position)

	if cancel:
		node.preview_override(key, original_grid)
		node.commit_override(key, original_grid)
		_drag_start_positions.erase(handle_id)
		return

	var final_grid: Vector3i = node.overrides.get_override(key, original_grid) if node.overrides else original_grid

	if undo_redo:
		undo_redo.create_action("Adjust Ludo board cell (%s)" % key)
		undo_redo.add_do_method(node, "commit_override", key, final_grid)
		undo_redo.add_undo_method(node, "commit_override", key, original_grid)
		undo_redo.commit_action()
	else:
		node.commit_override(key, final_grid)

	_drag_start_positions.erase(handle_id)
