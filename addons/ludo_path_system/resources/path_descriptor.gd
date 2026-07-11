## Représentation compacte d'un chemin sur grille logique à base de segments.
##
## Les données SOURCES (celles qu'on édite/sauvegarde) sont `start_position`
## et `segments` : compactes, lisibles, faciles à modifier dans l'Inspector
## ou dans un fichier .tres.
##
## Un cache interne (`_cache`, `_index_lookup`) est construit à la demande
## pour offrir un accès O(1) en jeu (get_cell / get_index_at), sans jamais
## polluer les données sources. Le cache n'est PAS auto-invalidé : si vous
## modifiez `segments` à l'exécution, appelez rebuild_cache() explicitement.
@tool
class_name LudoPathDescriptor
extends Resource

@export var start_position: Vector2i = Vector2i.ZERO
@export var segments: Array[LudoPathSegment] = []

var _cache: Array[Vector2i] = []
var _index_lookup: Dictionary = {} # Vector2i -> int
var _cache_built: bool = false


## (Re)construit le cache de cellules à partir des segments.
## À appeler explicitement après toute modification de `segments`
## ou `start_position` en cours de partie.
func rebuild_cache() -> void:
	_cache.clear()
	_index_lookup.clear()

	var cursor: Vector2i = start_position
	var first_segment: bool = true

	for seg in segments:
		if seg == null or not seg.is_valid():
			push_error("LudoPathDescriptor: segment invalide ignoré -> %s" % [seg])
			continue

		var seg_start: Vector2i = start_position if first_segment else cursor + seg.offset
		first_segment = false

		for i in range(seg.length):
			var cell: Vector2i = seg_start + seg.direction * i
			_cache.append(cell)
			# En cas de cellule partagée (jonction d'angle), on garde le
			# DERNIER index rencontré : c'est celui qui représente la
			# progression la plus avancée du pion sur cette cellule.
			_index_lookup[cell] = _cache.size() - 1

		cursor = seg_start + seg.direction * (seg.length - 1)

	_cache_built = true


func _ensure_cache() -> void:
	if not _cache_built:
		rebuild_cache()


## Retourne la position de grille pour un index de progression donné.
func get_cell(index: int) -> Vector2i:
	_ensure_cache()
	assert(index >= 0 and index < _cache.size(), "LudoPathDescriptor: index %d hors limites (taille=%d)" % [index, _cache.size()])
	return _cache[index]


## Nombre total de cellules du chemin (avec doublons de jonction inclus).
func get_length() -> int:
	_ensure_cache()
	return _cache.size()


## Retourne l'index de progression correspondant à une cellule, ou -1
## si la cellule n'appartient pas au chemin.
func get_index_at(cell: Vector2i) -> int:
	_ensure_cache()
	return _index_lookup.get(cell, -1)


## Retourne la liste complète des cellules, dans l'ordre de progression.
## Utile pour du debug visuel ou pour peupler une GridMap.
func get_all_cells() -> Array[Vector2i]:
	_ensure_cache()
	return _cache.duplicate()


## True si au moins une jonction inter-segments a dupliqué une cellule
## (offset == ZERO quelque part). Un anneau "classique" fermé sur un nombre
## de cases fixe (ex: BoardConfig.RING_SIZE) ne doit normalement PAS en
## avoir : à vérifier via LudoBoardLayout.validate(), pas ici — un
## descripteur isolé n'a pas à connaître la contrainte du plateau complet.
func has_duplicated_junctions() -> bool:
	_ensure_cache()
	return _index_lookup.size() != _cache.size()


## Valide la cohérence du descripteur sans construire le cache "pour de bon".
## Retourne un tableau de messages d'erreur (vide si tout est valide).
func validate() -> Array[String]:
	var errors: Array[String] = []

	if segments.is_empty():
		errors.append("LudoPathDescriptor: aucun segment défini.")
		return errors

	for i in range(segments.size()):
		var seg := segments[i]
		if seg == null:
			errors.append("Segment %d: null." % i)
			continue
		if not seg.is_valid():
			errors.append("Segment %d invalide: %s" % [i, seg])

	return errors
