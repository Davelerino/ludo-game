## Pure, stateless geometry generator: turns "N cells per arm" into an
## ordered, closed, axis-aligned square loop of Vector3i positions.
##
## Geometric note (why a square frame):
## A square "picture frame" (only the border cells of an n x n grid) has
## exactly 4 * (n - 1) cells. For ring_lane_length = 52 with 4 players, each
## arm must contribute exactly 13 NEW cells (52 / 4 = 13), which is achieved
## with n = 14 (coordinates 0..13). This falls out of the same 52 = 4 x 13
## symmetry the GDD calls out in §3.2, and conveniently makes each player's
## start tile land exactly on a corner (indices 0, 13, 26, 39 - identical to
## the GDD's fixed offsets), with zero special-casing required.
class_name LudoRingPathGenerator
extends RefCounted


## Generates the ordered ring lane as a closed square loop.
## side_length = number of NEW cells contributed per arm (ring_lane_length / player_count).
## Returns exactly `side_length * 4` positions, index 0 being the corner used
## as Player 1's start tile, going around monotonically once (no diagonals,
## each consecutive pair - including last-to-first - is an axis-aligned
## unit-distance neighbor).
static func generate_ring_square(side_length: int, elevation: int = 0) -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	var directions: Array[Vector3i] = [
		Vector3i(1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, -1),
	]
	var current := Vector3i(0, elevation, 0)
	for side in range(4):
		var dir: Vector3i = directions[side]
		for _step in range(side_length):
			positions.append(current)
			current += dir
	return positions


## Direction each player's home lane travels, starting from that player's
## home-entry ring cell, moving toward the board interior. Indexed by arm
## number (0..3), matching the arm order used in generate_ring_square.
static func get_inward_directions() -> Array[Vector3i]:
	return [
		Vector3i(0, 0, 1),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, -1),
		Vector3i(1, 0, 0),
	]
