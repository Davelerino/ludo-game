## Pure validation of a generated LudoBoardData. Never mutates anything.
## Mirrors the "Validation obligatoire" checklist from the GDD (§3.5 / §10):
## closed ring of the right length, axis-aligned neighbors everywhere, no
## diagonals, disjoint home lanes, all 4 colors present.
class_name LudoBoardValidator
extends RefCounted


static func validate_all(data: LudoBoardData) -> Dictionary:
	var errors: Array[String] = []
	errors.append_array(validate_no_duplicate_positions(data))
	errors.append_array(validate_ring(data))
	errors.append_array(validate_start_tiles(data))
	errors.append_array(validate_home_lanes(data))
	return {"valid": errors.is_empty(), "errors": errors}


## Explicit, global "no duplicate position" check across EVERY generated
## cell (ring AND home lanes together) - independent from the ring/home
## lane checks below, which only catch overlaps within their own scope.
static func validate_no_duplicate_positions(data: LudoBoardData) -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for cell in data.cells:
		if seen.has(cell.position):
			var other: LudoCell = seen[cell.position]
			errors.append(
				"Duplicate grid position %s used by cell id %d (%s) and cell id %d (%s)." % [
					cell.position, other.id, LudoBoardEnums.cell_type_name(other.type),
					cell.id, LudoBoardEnums.cell_type_name(cell.type)
				]
			)
		else:
			seen[cell.position] = cell
	return errors


static func validate_ring(data: LudoBoardData) -> Array[String]:
	var errors: Array[String] = []
	if data.ring_lane.size() != data.ring_lane_length:
		errors.append("Ring lane has %d cells, expected %d." % [data.ring_lane.size(), data.ring_lane_length])
		return errors
	for i in range(data.ring_lane_length):
		var current: LudoCell = data.get_cell(data.ring_lane[i])
		var next_cell: LudoCell = data.get_cell(data.ring_lane[(i + 1) % data.ring_lane_length])
		if current == null or next_cell == null:
			errors.append("Ring index %d references a missing cell." % i)
			continue
		if not _is_axis_neighbor(current.position, next_cell.position):
			errors.append(
				"Ring cells %d and %d are not axis-aligned unit neighbors (%s -> %s)." % [
					i, (i + 1) % data.ring_lane_length, current.position, next_cell.position
				]
			)
	return errors


static func validate_start_tiles(data: LudoBoardData) -> Array[String]:
	var errors: Array[String] = []
	var found_colors: Dictionary = {}
	for cell_id in data.ring_lane:
		var cell: LudoCell = data.get_cell(cell_id)
		if cell != null and cell.type == LudoBoardEnums.CellType.START:
			found_colors[cell.color] = true
	for color in LudoBoardEnums.all_colors():
		if not found_colors.has(color):
			errors.append("Missing start tile for color %s." % LudoBoardEnums.color_name(color))
	return errors


static func validate_home_lanes(data: LudoBoardData) -> Array[String]:
	var errors: Array[String] = []
	var seen_positions: Dictionary = {}
	for color in data.player_paths.keys():
		var path: LudoPlayerPath = data.player_paths[color]
		if path.home_lane_cell_ids.size() != data.home_lane_length:
			errors.append(
				"Home lane for %s has %d cells, expected %d." % [
					LudoBoardEnums.color_name(color), path.home_lane_cell_ids.size(), data.home_lane_length
				]
			)

		var entry_cell := data.get_ring_cell(path.home_entry_index)
		if entry_cell == null:
			errors.append("Home entry index %d for %s is invalid." % [path.home_entry_index, LudoBoardEnums.color_name(color)])
			continue

		var prev_pos: Vector3i = entry_cell.position
		for cell_id in path.home_lane_cell_ids:
			var cell: LudoCell = data.get_cell(cell_id)
			if cell == null:
				errors.append("Home lane for %s references a missing cell id %d." % [LudoBoardEnums.color_name(color), cell_id])
				continue
			if not _is_axis_neighbor(prev_pos, cell.position):
				errors.append(
					"Home lane cell for %s is not an axis-aligned neighbor of the previous cell (%s -> %s)." % [
						LudoBoardEnums.color_name(color), prev_pos, cell.position
					]
				)
			if seen_positions.has(cell.position):
				errors.append(
					"Home lane overlap: position %s used by both %s and %s." % [
						cell.position, LudoBoardEnums.color_name(seen_positions[cell.position]), LudoBoardEnums.color_name(color)
					]
				)
			seen_positions[cell.position] = color
			prev_pos = cell.position
	return errors


## True if `b` is exactly one axis-aligned unit step away from `a`
## (never a diagonal, never a jump).
static func _is_axis_neighbor(a: Vector3i, b: Vector3i) -> bool:
	var diff := b - a
	var nonzero_axes := 0
	if diff.x != 0:
		nonzero_axes += 1
		if absi(diff.x) != 1:
			return false
	if diff.y != 0:
		nonzero_axes += 1
		if absi(diff.y) != 1:
			return false
	if diff.z != 0:
		nonzero_axes += 1
		if absi(diff.z) != 1:
			return false
	return nonzero_axes == 1
