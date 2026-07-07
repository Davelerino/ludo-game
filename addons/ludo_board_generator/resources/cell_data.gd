## Logical representation of a single board cell.
## This is the atomic unit of BoardData. It is completely independent from
## the GridMap - it only carries a GridMap-compatible Vector3i position so
## that visual painting can use it, but nothing here reads back from the
## GridMap itself.
@tool
class_name LudoCell
extends Resource

## Unique id of this cell within BoardData.cells (its index in that array).
@export var id: int = -1

## GridMap cell coordinate (Vector3i) where this logical cell is painted.
@export var position: Vector3i = Vector3i.ZERO

## RING, START, HOME, CENTER or SAFE. See LudoBoardEnums.CellType.
@export var type: int = LudoBoardEnums.CellType.RING

## Owning player color. LudoBoardEnums.PlayerColor.NONE for shared ring cells.
@export var color: int = LudoBoardEnums.PlayerColor.NONE

## MeshLibrary item id to paint into the GridMap for this cell.
@export var mesh_id: int = -1

## Ids (not positions) of adjacent cells in BoardData.cells, following the
## playable path graph (ring neighbors, or home-lane chain). Diagonals never
## appear here - only axis-aligned neighbors are ever recorded.
@export var neighbors: Array[int] = []

## Index on the ring lane (0..ring_lane_length-1). -1 if this cell is not on
## the ring lane (i.e. it's a HOME or CENTER cell).
@export var ring_index: int = -1

## Index within its owner's home lane (0..home_lane_length-1). -1 if this
## cell is not part of a home lane (i.e. it's a RING or START cell).
@export var home_lane_index: int = -1


func _to_string() -> String:
	return "LudoCell(id=%d, pos=%s, type=%s, color=%s)" % [
		id, position, LudoBoardEnums.cell_type_name(type), LudoBoardEnums.color_name(color)
	]
