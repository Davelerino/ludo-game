## Manual position overrides layered on top of the procedural ring/home lane
## generation. Keyed by a STABLE string (not by cell id, which can shift
## between regenerations) so overrides survive regeneration:
##   - ring cells:  "ring:<ring_index>"           e.g. "ring:13"
##   - home cells:  "home:<PlayerColor int>:<home_lane_index>"  e.g. "home:0:2"
##
## This resource holds ONLY positions - it never changes topology (which
## cell is adjacent to which). That's deliberate: LudoBoardValidator still
## checks real axis-aligned adjacency after overrides are applied, so an
## illegal manual nudge is caught immediately instead of silently producing
## a broken board.
@tool
class_name LudoBoardOverrides
extends Resource

## String key -> Vector3i forced position.
@export var position_overrides: Dictionary = {}


func has_override(key: String) -> bool:
	return position_overrides.has(key)


func get_override(key: String, fallback: Vector3i) -> Vector3i:
	return position_overrides.get(key, fallback)


func set_override(key: String, pos: Vector3i) -> void:
	position_overrides[key] = pos
	emit_changed()


func clear_override(key: String) -> void:
	if position_overrides.has(key):
		position_overrides.erase(key)
		emit_changed()


func clear_all() -> void:
	if not position_overrides.is_empty():
		position_overrides.clear()
		emit_changed()
