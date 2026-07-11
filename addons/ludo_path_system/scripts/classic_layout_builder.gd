## Construit le LudoBoardLayout du plateau Ludo classique (croix 15x15,
## anneau de 52 cases, 4 couloirs finaux de 6 cases, 4 yards de 4 cases).
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
class_name LudoClassicLayoutBuilder
extends RefCounted

## Centre logique du plateau 15x15 (col=row=7 par symétrie).
const CENTER := Vector2i(7, 7)


static func build() -> LudoBoardLayout:
	var layout := LudoBoardLayout.new()
	layout.elevation = 0
	layout.shared_ring = _build_shared_ring()
	layout.player_paths = _build_player_paths(layout.shared_ring)
	layout.yard_positions = _build_yard_positions()
	return layout


# ============================================================================
# Anneau partagé (52 cases)
# ============================================================================

static func _build_shared_ring() -> LudoPathDescriptor:
	var red_arm := _walk(Vector2i(1, 6), [
		[Vector2i(1, 0), 5],
		[Vector2i(0, -1), 6],
		[Vector2i(1, 0), 1],
	])
	var green_arm := _walk(Vector2i(8, 0), [
		[Vector2i(0, 1), 5],
		[Vector2i(1, 0), 5],
		[Vector2i(0, 1), 2],
	])
	var yellow_arm: Array[Vector2i] = []
	for p in red_arm:
		yellow_arm.append(_rotate180(p))
	var blue_arm: Array[Vector2i] = []
	for p in green_arm:
		blue_arm.append(_rotate180(p))

	var all_cells: Array[Vector2i] = []
	all_cells.append_array(red_arm)
	all_cells.append_array(green_arm)
	all_cells.append_array(yellow_arm)
	all_cells.append_array(blue_arm)

	return _build_descriptor_from_cells(all_cells)


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
# Chaque couloir longe la ligne médiane (row7 pour RED/YELLOW, col7 pour
# GREEN/BLUE) en partant 2 cases après la case de transition d'anneau de
# la couleur PRÉCÉDENTE (pour ne jamais chevaucher l'anneau) et en
# remontant jusqu'au centre (7,7), partagé intentionnellement par les 4
# couloirs comme case d'arrivée commune.

static func _build_player_paths(shared_ring: LudoPathDescriptor) -> Array[LudoPlayerPath]:
	var home_specs := [
		[Vector2i(2, 7), Vector2i(1, 0)],   # player 0 (RED)   : row7,  col croissant
		[Vector2i(7, 2), Vector2i(0, 1)],   # player 1 (GREEN) : col7,  row croissant
		[Vector2i(12, 7), Vector2i(-1, 0)], # player 2 (YELLOW): row7,  col décroissant
		[Vector2i(7, 12), Vector2i(0, -1)], # player 3 (BLUE)  : col7,  row décroissant
	]

	var paths: Array[LudoPlayerPath] = []
	for player_id in range(BoardConfig.PLAYER_COUNT):
		var home := LudoPathDescriptor.new()
		home.start_position = home_specs[player_id][0]
		home.segments = [LudoPathSegment.new(home_specs[player_id][1], BoardConfig.HOME_LANE_LENGTH, Vector2i.ZERO)]

		var path := LudoPlayerPath.new()
		path.setup(shared_ring, BoardConfig.get_player_offset(player_id), BoardConfig.HOME_ENTRY_PROGRESS, home)
		paths.append(path)

	return paths


# ============================================================================
# Yards (2x2 par joueur, dans le coin adjacent à son propre bras)
# ============================================================================

static func _build_yard_positions() -> Array[Array]:
	return [
		[Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)],       # player 0 (RED)   : coin haut-gauche
		[Vector2i(12, 1), Vector2i(13, 1), Vector2i(12, 2), Vector2i(13, 2)],   # player 1 (GREEN) : coin haut-droit
		[Vector2i(12, 12), Vector2i(13, 12), Vector2i(12, 13), Vector2i(13, 13)], # player 2 (YELLOW): coin bas-droit
		[Vector2i(1, 12), Vector2i(2, 12), Vector2i(1, 13), Vector2i(2, 13)],   # player 3 (BLUE)  : coin bas-gauche
	]
