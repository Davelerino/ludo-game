## Construit le LudoBoardLayout du plateau Ludo classique (croix 15x15,
## anneau de 52 cases, 4 couloirs finaux de 6 cases dérivés directement de
## l'anneau). Les yards ne font PAS partie de ce layout — voir board_root.tscn.
##
## GEOMETRIC NOTE (reprise de l'ancien ring_path_generator.gd) : un anneau
## Ludo à 4 bras égaux de 13 cases ne peut PAS s'obtenir en tournant un seul
## bras de 90 degrés autour de la case centrale (7,7) — toute isométrie qui
## fixe une cellule à coordonnées entières préserve la couleur d'échiquier de
## chaque case, or parcourir 13 pas (un nombre IMPAIR) inverse toujours cette
## couleur. En revanche, les bras opposés SONT reliés par une rotation de 180
## degrés (26 pas, PAIR). D'où : bras RED et GREEN écrits explicitement comme
## des marches directionnelles, YELLOW/BLUE dérivés par rotation 180.
##
## Chaque bras est ensuite compressé en LudoPathSegment (voir
## _build_descriptor_from_cells) : c'est le pont entre "coordonnées bien
## comprises case par case" et "représentation compacte par segments".
@tool
class_name LudoClassicLayoutBuilder
extends RefCounted

## Centre logique du plateau 15x15 (col=row=7 par symétrie).
const CENTER := Vector2i(7, 7)


static func build() -> LudoBoardLayout:
	var layout := LudoBoardLayout.new()
	layout.elevation = 0
	var arms := _build_arms()
	layout.shared_ring = _build_descriptor_from_cells(arms.cells)
	layout.player_paths = _build_player_paths(layout.shared_ring, arms.home_directions)
	return layout


# ============================================================================
# Anneau partagé (52 cases)
# ============================================================================

## Ordre des bras : BLUE (bas-gauche, index 0) -> GREEN (haut-gauche, 13)
## -> RED (haut-droite, 26) -> YELLOW (bas-droite, 39), pour correspondre
## exactement à la numérotation S0/S13/S26/S39 du plateau de référence
## (image du GDD) plutôt qu'à un ordre horaire arbitraire à partir du coin
## haut-gauche.
##
## Capture au passage la direction du premier pas de CHAQUE bras : c'est
## aussi la direction du couloir final de ce joueur (voir
## _derive_home_descriptor), ce qui évite de maintenir une donnée séparée
## et déconnectée de la construction de l'anneau.
static func _build_arms() -> Dictionary:
	var top_left_arm := _walk(Vector2i(1, 6), [
		[Vector2i(1, 0), 5],
		[Vector2i(0, -1), 6],
		[Vector2i(1, 0), 1],
	])
	var top_right_arm := _walk(Vector2i(8, 0), [
		[Vector2i(0, 1), 5],
		[Vector2i(1, 0), 5],
		[Vector2i(0, 1), 2],
	])
	var bottom_right_arm: Array[Vector2i] = []
	for p in top_left_arm:
		bottom_right_arm.append(_rotate180(p))
	var bottom_left_arm: Array[Vector2i] = []
	for p in top_right_arm:
		bottom_left_arm.append(_rotate180(p))

	var all_cells: Array[Vector2i] = []
	all_cells.append_array(bottom_left_arm)  # index 0..12  : BLUE  (S0)
	all_cells.append_array(top_left_arm)     # index 13..25 : GREEN (S13)
	all_cells.append_array(top_right_arm)    # index 26..38 : RED   (S26)
	all_cells.append_array(bottom_right_arm) # index 39..51 : YELLOW (S39)

	var home_directions: Array[Vector2i] = [
		_first_direction(bottom_left_arm),   # player 0 (BLUE)
		_first_direction(top_left_arm),      # player 1 (GREEN)
		_first_direction(top_right_arm),     # player 2 (RED)
		_first_direction(bottom_right_arm),  # player 3 (YELLOW)
	]

	return {"cells": all_cells, "home_directions": home_directions}


## Direction du tout premier pas d'un bras (entre ses 2 premières cellules).
static func _first_direction(arm_cells: Array[Vector2i]) -> Vector2i:
	assert(arm_cells.size() >= 2, "LudoClassicLayoutBuilder: bras trop court pour en déduire une direction.")
	return arm_cells[1] - arm_cells[0]


## Marche une séquence de [direction: Vector2i, count: int] à partir de
## `start`, incluant la case de départ. Équivalent direct de la méthode
## "RIGHT xN / UP xN / DOWN xN" du GDD.
static func _walk(start: Vector2i, steps: Array) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [start]
	var cursor := start
	for step in steps:
		var dir: Vector2i = step[0]
		var count: int = step[1]
		for _i in range(count):
			cursor += dir
			cells.append(cursor)
	return cells


static func _rotate180(p: Vector2i) -> Vector2i:
	return Vector2i(2 * CENTER.x - p.x, 2 * CENTER.y - p.y)


## Compresse une liste de cellules contiguës (pas orthogonaux uniquement) en
## un LudoPathDescriptor : détecte les changements de direction et émet un
## LudoPathSegment par run rectiligne. Le premier segment démarre à
## start_position ; chaque segment suivant utilise offset = sa propre
## direction (un pas), pour ne JAMAIS dupliquer la cellule de jonction.
static func _build_descriptor_from_cells(cells: Array[Vector2i]) -> LudoPathDescriptor:
	assert(cells.size() >= 2, "LudoClassicLayoutBuilder: au moins 2 cellules requises.")

	var descriptor := LudoPathDescriptor.new()
	descriptor.start_position = cells[0]
	var segments: Array[LudoPathSegment] = []

	var i: int = 1
	var is_first_segment: bool = true
	while i < cells.size():
		var run_dir: Vector2i = cells[i] - cells[i - 1]
		var run_delta_count: int = 1
		var j: int = i + 1
		while j < cells.size() and (cells[j] - cells[j - 1]) == run_dir:
			run_delta_count += 1
			j += 1

		var seg_length: int = (run_delta_count + 1) if is_first_segment else run_delta_count
		var seg_offset: Vector2i = Vector2i.ZERO if is_first_segment else run_dir
		segments.append(LudoPathSegment.new(run_dir, seg_length, seg_offset))

		is_first_segment = false
		i = j

	descriptor.segments = segments
	return descriptor


# ============================================================================
# Couloirs finaux (6 cases par joueur, dernière case = centre partagé (7,7))
# ============================================================================
#
# Chaque couloir est ENTIÈREMENT dérivé de la direction du premier pas du
# bras d'anneau de ce joueur (voir _derive_home_descriptor) : aucune donnée
# séparée à maintenir en plus de l'anneau lui-même.

static func _build_player_paths(shared_ring: LudoPathDescriptor, home_directions: Array[Vector2i]) -> Array[LudoPlayerPath]:
	var paths: Array[LudoPlayerPath] = []
	for player_id in range(BoardConfig.PLAYER_COUNT):
		var home := _derive_home_descriptor(home_directions[player_id])
		var path := LudoPlayerPath.new()
		path.setup(shared_ring, BoardConfig.get_player_offset(player_id), BoardConfig.HOME_ENTRY_PROGRESS, home)
		paths.append(path)

	return paths


## Dérive le couloir final d'un joueur à partir de la SEULE direction de son
## bras d'anneau : le couloir remonte vers CENTER dans cette même direction,
## et sa DERNIÈRE case (index HOME_LANE_LENGTH-1) tombe exactement sur
## CENTER -> start_position = CENTER - (HOME_LANE_LENGTH-1) * direction.
## Fonction pure et testable en isolation (aucune dépendance sur l'anneau).
static func _derive_home_descriptor(direction: Vector2i) -> LudoPathDescriptor:
	var home := LudoPathDescriptor.new()
	home.start_position = CENTER - direction * (BoardConfig.HOME_LANE_LENGTH - 1)
	home.segments = [LudoPathSegment.new(direction, BoardConfig.HOME_LANE_LENGTH, Vector2i.ZERO)]
	return home
