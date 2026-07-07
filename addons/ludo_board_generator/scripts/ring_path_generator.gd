## Generates the CLASSIC 15x15 Ludo cross-shaped ring lane (52 cells).
##
## GEOMETRIC NOTE - why this is not "rotate one arm by 90 degrees":
## A real Ludo ring split into 4 equal arms of 13 cells CANNOT be produced by
## rotating a single 13-cell template by 90 degrees around the board's centre
## cell (7,7). Any isometry (rotation or reflection) that fixes an
## integer-coordinate grid cell preserves that cell's checkerboard
## (black/white) colour for every position it maps - but walking 13 steps
## (an ODD number) along the ring always flips checkerboard colour. So a
## start tile and "the start tile 13 steps later" can never be the image of
## one another under a 90-degree rotation: doing so produces a diagonal jump
## at every quarter boundary (which is exactly the bug in the previous
## square-frame generator once adapted naively to a cross).
##
## Opposite arms ARE related by a clean 180-degree rotation (26 steps - an
## EVEN number - no parity problem). So this generator writes RED's and
## GREEN's arms explicitly as directional segments (RIGHT xN / UP xN / DOWN
## xN, per the required generation method), then derives YELLOW (= 180
## degree rotation of RED) and BLUE (= 180 degree rotation of GREEN).
## Every junction and the full loop closure is unit-tested in
## board_validator.gd.
class_name LudoRingPathGenerator
extends RefCounted

const BOARD_SIZE := 15
## Centre cell of the 15x15 board, in (row, col) space.
const CENTER := Vector2i(7, 7)

const RING_LENGTH := 52
const CELLS_PER_ARM := 13


## Returns the 52 ring lane positions in traversal order (index 0..51).
## Quarter boundaries land exactly at 0 (RED), 13 (GREEN), 26 (YELLOW),
## 39 (BLUE) - the classic board's start-tile offsets.
static func generate_classic_cross_ring(elevation: int = 0) -> Array[Vector3i]:
	# RED arm: row 6, cols 1->6 (RIGHT x5), then col 6, rows 5->0 (UP x6),
	# then one more RIGHT step onto row 0 (the corner cell before GREEN's arm).
	var red_arm := _walk(Vector2i(6, 1), [
		[Vector2i(0, 1), 5],
		[Vector2i(-1, 0), 6],
		[Vector2i(0, 1), 1],
	])

	# GREEN arm: col 8, rows 0->5 (DOWN x5), then row 5, cols 8->13 (RIGHT x5),
	# then col 13, rows 5->7 (DOWN x2) - the corner cells before YELLOW's arm.
	var green_arm := _walk(Vector2i(0, 8), [
		[Vector2i(1, 0), 5],
		[Vector2i(0, 1), 5],
		[Vector2i(1, 0), 2],
	])

	var yellow_arm: Array[Vector2i] = []
	for p in red_arm:
		yellow_arm.append(_rotate180(p))

	var blue_arm: Array[Vector2i] = []
	for p in green_arm:
		blue_arm.append(_rotate180(p))

	var ring2i: Array[Vector2i] = []
	ring2i.append_array(red_arm)
	ring2i.append_array(green_arm)
	ring2i.append_array(yellow_arm)
	ring2i.append_array(blue_arm)

	var ring3i: Array[Vector3i] = []
	for p in ring2i:
		ring3i.append(_to_v3i(p, elevation))
	return ring3i


## Direction a given colour's home lane travels, starting from that colour's
## home-entry ring cell (the ring cell immediately before that colour's own
## start tile), moving toward the board interior.
static func get_home_lane_direction(color: int) -> Vector3i:
	match color:
		LudoBoardEnums.PlayerColor.RED:
			return Vector3i(1, 0, 0)    # row 7, +col (eastward, toward centre)
		LudoBoardEnums.PlayerColor.GREEN:
			return Vector3i(0, 0, 1)    # col 7, +row (southward, toward centre)
		LudoBoardEnums.PlayerColor.YELLOW:
			return Vector3i(-1, 0, 0)   # row 7, -col (westward, toward centre)
		LudoBoardEnums.PlayerColor.BLUE:
			return Vector3i(0, 0, -1)   # col 7, -row (northward, toward centre)
		_:
			return Vector3i.ZERO


## Logical board centre (row 7, col 7), converted to GridMap space.
static func board_center(elevation: int = 0) -> Vector3i:
	return _to_v3i(CENTER, elevation)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

## Walks a sequence of [unit_step: Vector2i, count: int] segments starting at
## `start` (in (row, col) space) and returns every visited cell, INCLUDING
## the starting cell. This is the direct GDScript equivalent of the
## "RIGHT xN / UP xN / DOWN xN / LEFT xN" segment method: each entry of
## `segments` is one straight directional run.
static func _walk(start: Vector2i, segments: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [start]
	var cursor := start
	for segment in segments:
		var unit: Vector2i = segment[0]
		var count: int = segment[1]
		for _i in range(count):
			cursor += unit
			cells.append(cursor)
	return cells


static func _rotate180(p: Vector2i) -> Vector2i:
	return Vector2i(2 * CENTER.x - p.x, 2 * CENTER.y - p.y)


## (row, col) -> GridMap Vector3i. row maps to Z, col maps to X, matching the
## X/Z ground-plane convention used by the rest of this plugin.
static func _to_v3i(p: Vector2i, elevation: int) -> Vector3i:
	return Vector3i(p.y, elevation, p.x)
