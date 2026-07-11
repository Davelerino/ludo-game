## Décrit une portion rectiligne d'un chemin sur grille logique (Vector2i).
##
## Convention IMPORTANTE : `length` est INCLUSIF, c'est-à-dire qu'un segment
## de longueur 5 produit exactement 5 cellules (la cellule de départ +
## 4 pas dans `direction`).
##
## `offset` décale le point de départ de CE segment par rapport au point
## de FIN du segment précédent :
##   start_position(segment_n) = end_position(segment_n-1) + offset(segment_n)
##
## Si offset == Vector2i.ZERO, le segment démarre exactement sur la dernière
## cellule du segment précédent : la cellule de jonction est donc PARTAGÉE
## (comptée dans les deux segments). C'est un choix volontaire pour pouvoir
## représenter une case physiquement partagée entre deux segments (ex: un
## embranchement) — voir LudoPathDescriptor.rebuild_cache(). Pour un simple
## virage d'anneau SANS duplication (le cas standard), utiliser un offset
## d'un pas dans la nouvelle direction.
class_name LudoPathSegment
extends Resource

@export var direction: Vector2i = Vector2i.ZERO
@export var length: int = 1
@export var offset: Vector2i = Vector2i.ZERO


func _init(p_direction: Vector2i = Vector2i.ZERO, p_length: int = 1, p_offset: Vector2i = Vector2i.ZERO) -> void:
	direction = p_direction
	length = p_length
	offset = p_offset


## Un segment est valide si sa direction est un pas unitaire orthogonal
## (pas de diagonale, pas de vecteur nul) et si sa longueur est positive.
## Contrainte volontairement stricte pour garantir la compatibilité GridMap.
func is_valid() -> bool:
	if length <= 0:
		return false
	if direction == Vector2i.ZERO:
		return false
	if abs(direction.x) > 1 or abs(direction.y) > 1:
		return false
	if direction.x != 0 and direction.y != 0:
		return false # pas de diagonale
	return true


func _to_string() -> String:
	return "LudoPathSegment(dir=%s, len=%d, offset=%s)" % [direction, length, offset]
