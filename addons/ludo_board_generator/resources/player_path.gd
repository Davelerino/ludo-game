## Describes one player's full path across the board: their start tile on the
## ring lane, where they branch off into their home lane, and the ordered
## chain of home-lane cells leading to their centre/finish cell.
##
## A LudoPlayerPath is never built independently: it is always derived from
## its corresponding start tile during generation (see board_generator.gd).
@tool
class_name LudoPlayerPath
extends Resource

## LudoBoardEnums.PlayerColor this path belongs to.
@export var color: int = LudoBoardEnums.PlayerColor.NONE

## Id (into BoardData.cells) of this player's start tile.
@export var start_tile_id: int = -1

## World/GridMap position of the start tile (cached for convenience).
@export var start_tile_position: Vector3i = Vector3i.ZERO

## Index of the start tile on the ring lane. This is also the player's
## "offset" (progress 0 maps to this ring index).
@export var ring_entry_index: int = -1

## Ring index of the cell just before this player's start tile
## ((ring_entry_index - 1 + ring_lane_length) % ring_lane_length).
## This is where the player's pawns branch off the ring into their home lane.
@export var home_entry_index: int = -1

## Ordered ids (into BoardData.cells) of this player's home lane cells,
## from the first home-lane cell up to and including the CENTER cell.
## Length is always BoardData.home_lane_length.
@export var home_lane_cell_ids: Array[int] = []

## Id of this player's CENTER (finish) cell - always the last entry of
## home_lane_cell_ids, kept separately for O(1) access.
@export var center_cell_id: int = -1


func _to_string() -> String:
	return "LudoPlayerPath(color=%s, start_ring_index=%d, home_entry=%d, home_len=%d)" % [
		LudoBoardEnums.color_name(color), ring_entry_index, home_entry_index, home_lane_cell_ids.size()
	]
