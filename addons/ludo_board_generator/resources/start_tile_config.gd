## One entry of manual start-tile configuration: which color owns which
## approximate board position. Used only to determine the ANGULAR ORDER in
## which colors are assigned to the 4 generated ring arms (Player 1..4) -
## the generator still procedurally places every cell itself (see §3.3 of
## the GDD: only the *existence* of 4 start tiles is designer-authored,
## the rest of the path is generated).
##
## If you need true auto-detection from existing GridMap mesh items instead
## of manual configuration, see LudoBoardGenerator.detect_start_tiles_from_gridmap().
@tool
class_name LudoStartTileConfig
extends Resource

@export var color: int = LudoBoardEnums.PlayerColor.RED

## Approximate world/GridMap position used only for angle-sorting relative
## to the other configured start tiles (see auto_order_by_angle on the
## generator). Does not need to be pixel-perfect.
@export var grid_position: Vector3i = Vector3i.ZERO
