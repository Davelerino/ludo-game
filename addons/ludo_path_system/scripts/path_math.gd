## Seul point de conversion entre l'espace logique 2D (Vector2i, col/row) du
## système de chemin et l'espace GridMap 3D (Vector3i, col/elevation/row).
## Évite de dupliquer cette conversion dans BoardManager, LudoBoardPainter, etc.
@tool
class_name LudoPathMath
extends RefCounted

static func to_cell3i(v: Vector2i, elevation: int) -> Vector3i:
	return Vector3i(v.x, elevation, v.y)


static func to_cell2i(v: Vector3i) -> Vector2i:
	return Vector2i(v.x, v.z)
