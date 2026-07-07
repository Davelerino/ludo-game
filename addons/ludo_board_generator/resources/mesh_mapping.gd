## Configurable mapping from logical cell type/color to MeshLibrary item id.
## Nothing in the generator ever hardcodes a mesh id - everything goes
## through an instance of this resource, editable in the Inspector.
##
## Create one as a standalone .tres (Resource > New Resource > LudoMeshMapping)
## so it can be shared/reused across multiple boards, and assign it to the
## `mesh_mapping` field of a LudoBoardGenerator node.
@tool
class_name LudoMeshMapping
extends Resource

@export_group("Ring")
## MeshLibrary item id used for every regular (non-start) ring lane cell.
@export var ring_mesh_id: int = 0

@export_group("Start Tiles")
@export var start_red_mesh_id: int = 1
@export var start_blue_mesh_id: int = 2
@export var start_green_mesh_id: int = 3
@export var start_yellow_mesh_id: int = 4

@export_group("Home Lanes")
@export var home_red_mesh_id: int = 5
@export var home_blue_mesh_id: int = 6
@export var home_green_mesh_id: int = 7
@export var home_yellow_mesh_id: int = 8

@export_group("Center / Finish")
## Mesh used for every player's final home-lane cell. Kept as a single id
## since the centre tile is conceptually shared, even though each player
## currently owns a distinct CENTER cell instance (see board_generator.gd
## docstring for why a single perfectly-shared cell isn't geometrically
## trivial with a 52-cell / 13-per-arm ring).
@export var center_mesh_id: int = 9


func mesh_id_for_start(color: int) -> int:
	match color:
		LudoBoardEnums.PlayerColor.RED:
			return start_red_mesh_id
		LudoBoardEnums.PlayerColor.BLUE:
			return start_blue_mesh_id
		LudoBoardEnums.PlayerColor.GREEN:
			return start_green_mesh_id
		LudoBoardEnums.PlayerColor.YELLOW:
			return start_yellow_mesh_id
		_:
			return ring_mesh_id


func mesh_id_for_home(color: int) -> int:
	match color:
		LudoBoardEnums.PlayerColor.RED:
			return home_red_mesh_id
		LudoBoardEnums.PlayerColor.BLUE:
			return home_blue_mesh_id
		LudoBoardEnums.PlayerColor.GREEN:
			return home_green_mesh_id
		LudoBoardEnums.PlayerColor.YELLOW:
			return home_yellow_mesh_id
		_:
			return ring_mesh_id
