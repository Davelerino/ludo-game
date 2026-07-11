## Chemin complet d'un joueur dans un Ludo : anneau partagé (commun à tous
## les joueurs) + couloir final (home path, propre à ce joueur).
##
## Cette classe NE remplace PAS PathDescriptor : elle le compose. C'est la
## couche qui gère l'embranchement (fork) entre "je suis encore sur
## l'anneau partagé" et "je suis entré dans mon couloir final".
##
## Le RuleEngine ne manipule qu'un entier `progress` par pion ; PlayerPath
## est la seule classe qui sait traduire ce progress en Vector2i.
class_name PlayerPath
extends Resource

## Index (dans shared_ring) de la cellule d'entrée de CE joueur sur l'anneau.
@export var ring_entry_index: int = 0

## Nombre de pas effectués sur l'anneau partagé avant de bifurquer
## dans le couloir final (typiquement 51 pour un Ludo classique : le pion
## fait quasi le tour complet moins un pas avant d'entrer chez lui).
@export var ring_steps: int = 51

## Couloir final propre à ce joueur (6 cases typiquement).
@export var home_path: PathDescriptor

## Anneau partagé, injecté depuis le BoardManager (pas dupliqué par joueur).
var shared_ring: PathDescriptor


func setup(p_shared_ring: PathDescriptor, p_ring_entry_index: int, p_ring_steps: int, p_home_path: PathDescriptor) -> void:
	shared_ring = p_shared_ring
	ring_entry_index = p_ring_entry_index
	ring_steps = p_ring_steps
	home_path = p_home_path


## Traduit une progression (0-based) en position de grille.
func get_position(progress: int) -> Vector2i:
	assert(shared_ring != null, "PlayerPath: shared_ring non assigné.")
	assert(home_path != null, "PlayerPath: home_path non assigné.")
	assert(progress >= 0 and progress < get_total_length(), "PlayerPath: progress %d hors limites (0..%d)" % [progress, get_total_length() - 1])

	if progress < ring_steps:
		var ring_length: int = shared_ring.get_length()
		var ring_index: int = (ring_entry_index + progress) % ring_length
		return shared_ring.get_cell(ring_index)
	else:
		return home_path.get_cell(progress - ring_steps)


## True si, à ce niveau de progression, le pion est déjà dans son couloir final.
func is_in_home_path(progress: int) -> bool:
	return progress >= ring_steps


func get_total_length() -> int:
	assert(home_path != null, "PlayerPath: home_path non assigné.")
	return ring_steps + home_path.get_length()
