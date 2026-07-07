## The single source of truth for the board's LOGICAL structure.
##
## This resource is completely independent from the GridMap: any other
## system (PawnController, RuleEngine, AI, netcode) can load/reference a
## LudoBoardData .tres and query it without ever touching a GridMap node.
## The GridMap is only ever a visual projection of this data.
@tool
class_name LudoBoardData
extends Resource

@export var ring_lane_length: int = 52
@export var home_lane_length: int = 6

## All generated cells (ring + start + home + center), indexed by LudoCell.id.
@export var cells: Array[LudoCell] = []

## Ordered ring lane cell ids, size == ring_lane_length, index 0..N-1.
@export var ring_lane: Array[int] = []

## Vector3i -> int (cell id). Lets any system resolve "what logical cell is
## at this GridMap coordinate" in O(1), e.g. for click-to-select or capture
## detection.
@export var index_map: Dictionary = {}

## LudoBoardEnums.PlayerColor (int) -> LudoPlayerPath.
@export var player_paths: Dictionary = {}

## Reference logical centre point (approximate - see LudoMeshMapping.center_mesh_id
## docstring). Mostly useful for camera framing / debug drawing.
@export var center_position: Vector3i = Vector3i.ZERO

## Cosmetic-only seed used for this generation (does not affect topology,
## only future visual variants - see GDD §3.5).
@export var board_seed: int = 0

@export var generated_at_unix: int = 0


func get_cell(cell_id: int) -> LudoCell:
	if cell_id < 0 or cell_id >= cells.size():
		return null
	return cells[cell_id]


func get_cell_at(grid_position: Vector3i) -> LudoCell:
	if not index_map.has(grid_position):
		return null
	return get_cell(index_map[grid_position])


## Returns the ring cell at a given ring index, wrapping around (so that e.g.
## get_ring_cell(-1) == get_ring_cell(ring_lane_length - 1)). This is the
## primitive a RuleEngine needs to advance a pawn along the ring.
func get_ring_cell(ring_index: int) -> LudoCell:
	if ring_lane.is_empty():
		return null
	var wrapped := ((ring_index % ring_lane_length) + ring_lane_length) % ring_lane_length
	return get_cell(ring_lane[wrapped])


func get_player_path(color: int) -> LudoPlayerPath:
	return player_paths.get(color, null)


## Resolves the world position for a pawn given its color and its GDD-style
## `progress` counter (0..50 = ring, 51..51+home_len-2 = home lane,
## 51+home_len-1 = FINI). Mirrors GDD §4.1 exactly.
func resolve_position(color: int, progress: int) -> Vector3i:
	var path := get_player_path(color)
	if path == null:
		return Vector3i.ZERO
	if progress <= ring_lane_length - 2:
		var ring_index := (path.ring_entry_index + progress) % ring_lane_length
		return get_ring_cell(ring_index).position
	var home_index: int = progress - (ring_lane_length - 1)
	home_index = clampi(home_index, 0, path.home_lane_cell_ids.size() - 1)
	return get_cell(path.home_lane_cell_ids[home_index]).position


func is_valid() -> bool:
	return ring_lane.size() == ring_lane_length and player_paths.size() == 4


## JSON-friendly export (Vector3i -> [x,y,z] arrays) for tooling, save files,
## or future multiplayer/network sync (see GDD "Extension future").
func to_dict() -> Dictionary:
	var out := {
		"ring_lane_length": ring_lane_length,
		"home_lane_length": home_lane_length,
		"center_position": _v3i_to_arr(center_position),
		"board_seed": board_seed,
		"generated_at_unix": generated_at_unix,
		"ring_lane": ring_lane.duplicate(),
		"cells": [],
		"player_paths": {},
	}
	for cell in cells:
		out["cells"].append({
			"id": cell.id,
			"position": _v3i_to_arr(cell.position),
			"type": cell.type,
			"color": cell.color,
			"mesh_id": cell.mesh_id,
			"neighbors": cell.neighbors.duplicate(),
			"ring_index": cell.ring_index,
			"home_lane_index": cell.home_lane_index,
		})
	for color in player_paths.keys():
		var path: LudoPlayerPath = player_paths[color]
		out["player_paths"][str(color)] = {
			"color": path.color,
			"start_tile_id": path.start_tile_id,
			"start_tile_position": _v3i_to_arr(path.start_tile_position),
			"ring_entry_index": path.ring_entry_index,
			"home_entry_index": path.home_entry_index,
			"home_lane_cell_ids": path.home_lane_cell_ids.duplicate(),
			"center_cell_id": path.center_cell_id,
		}
	return out


func save_json(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	return OK


static func _v3i_to_arr(v: Vector3i) -> Array:
	return [v.x, v.y, v.z]
