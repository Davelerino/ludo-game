class_name BoardGenerator
extends RefCounted
## ============================================================================
## BoardGenerator — Génération procédurale du plateau Ludo (éditeur + runtime).
##
## RESPONSABILITÉS
##   - Créer une MeshLibrary à partir des 4 meshes GLB importés.
##   - Calculer le layout complet du plateau sur une grille 15×15 (croix Ludo).
##   - Peupler une GridMap via set_cell_item() avec ring, home lanes, yards, centre.
##   - Fournir un mapping ring_index → Vector3i utilisé par BoardManager/PawnController.
##
## PRINCIPE : toutes les fonctions sont statiques et pures. Le plugin éditeur et le
## BoardManager (runtime) appellent les mêmes fonctions. Aucune dépendance scène.
## ============================================================================

# --- Indices des items dans la MeshLibrary -------------------------------
const ITEM_RING_PATH: int = 0    # SM_Ludo_SimplePath.glb
const ITEM_HOME_PATH: int = 1    # SM_Ludo_HomePath.glb
const ITEM_HOME: int = 2         # SM_Ludo_Home.glb
const ITEM_CENTER: int = 3       # SM_Ludo_Center.glb

# --- Chemins vers les meshes GLB ----------------------------------------
const _PATH_RING_PATH := "res://assets/meshes/SM_Ludo_SimplePath.glb"
const _PATH_HOME_PATH := "res://assets/meshes/SM_Ludo_HomePath.glb"
const _PATH_HOME       := "res://assets/meshes/SM_Ludo_Home.glb"
const _PATH_CENTER     := "res://assets/meshes/SM_Ludo_Center.glb"
const _PATH_MESHLIB    := "res://resources/LudoMeshLibrary.tres"

# --- Layout : mapping ring_index (0..51) → cellule GridMap (col, row) ----
# Grille 15×15, croix Ludo. Tracé horaire.
# Voir README ou diagramme dans le plan pour la visualisation.
const _RING_LAYOUT: Array = [
	[7, 0],  # 0  — Joueur 0 start
	[7, 1],  # 1
	[7, 2],  # 2
	[7, 3],  # 3
	[7, 4],  # 4
	[7, 5],  # 5
	[8, 6],  # 6
	[9, 6],  # 7
	[10, 6], # 8
	[11, 6], # 9
	[12, 6], # 10
	[13, 6], # 11
	[14, 6], # 12
	[14, 7], # 13 — Joueur 1 start
	[14, 8], # 14
	[13, 8], # 15
	[12, 8], # 16
	[11, 8], # 17
	[10, 8], # 18
	[9, 8],  # 19
	[8, 9],  # 20
	[8, 10], # 21
	[8, 11], # 22
	[8, 12], # 23
	[8, 13], # 24
	[8, 14], # 25 — Joueur 2 start
	[7, 14], # 26
	[6, 14], # 27
	[6, 13], # 28
	[6, 12], # 29
	[6, 11], # 30
	[6, 10], # 31
	[6, 9],  # 32
	[5, 8],  # 33
	[4, 8],  # 34
	[3, 8],  # 35
	[2, 8],  # 36
	[1, 8],  # 37
	[0, 8],  # 38 — Joueur 3 start
	[0, 7],  # 39
	[0, 6],  # 40
	[1, 6],  # 41
	[2, 6],  # 42
	[3, 6],  # 43
	[4, 6],  # 44
	[5, 6],  # 45
	[6, 5],  # 46
	[6, 4],  # 47
	[6, 3],  # 48
	[6, 2],  # 49
	[6, 1],  # 50
	[6, 0],  # 51
]

# --- Layout : home lanes (6 cellules par joueur, vers le centre) ---------
# home_lane_layout[player_id][local_index] = [col, row]
const _HOME_LANE_LAYOUT: Array = [
	[[7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6]],   # Joueur 0 : descend du haut du bras gauche
	[[13, 7], [12, 7], [11, 7], [10, 7], [9, 7], [8, 7]],  # Joueur 1 : va vers la gauche
	[[7, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8]],  # Joueur 2 : monte du bas du bras droit
	[[1, 7], [2, 7], [3, 7], [4, 7], [5, 7], [6, 7]],     # Joueur 3 : va vers la droite
]

# --- Layout : yards (2×2 coins pour les 4 pions de chaque joueur) --------
# yard_layout[player_id] = Array of [col, row] (4 positions)
const _YARD_LAYOUT: Array = [
	[[10, 1], [10, 2], [11, 1], [11, 2]],   # Joueur 0 : coin bas-gauche
	[[10, 12], [10, 13], [11, 12], [11, 13]], # Joueur 1 : coin bas-droite
	[[2, 12], [2, 13], [3, 12], [3, 13]],    # Joueur 2 : coin haut-droite
	[[2, 1], [2, 2], [3, 1], [3, 2]],        # Joueur 3 : coin haut-gauche
]

const _CENTER_CELL: Array = [7, 7]


# ============================================================================
# 1. CRÉATION DE LA MESHLIBRARY
# ============================================================================

## Crée une MeshLibrary à partir des 4 GLB et la sauve en .tres.
## Retourne la MeshLibrary (ou null si échec).
static func create_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var paths := [_PATH_RING_PATH, _PATH_HOME_PATH, _PATH_HOME, _PATH_CENTER]

	for i in range(paths.size()):
		var packed: PackedScene = load(paths[i]) as PackedScene
		if packed == null:
			push_error("BoardGenerator: impossible de charger %s" % paths[i])
			return null
		var instance: Node3D = packed.instantiate() as Node3D
		if instance == null:
			push_error("BoardGenerator: l'instance de %s n'est pas un Node3D" % paths[i])
			return null
		# Trouver le premier MeshInstance3D dans l'arbre du GLB.
		var mesh_inst: MeshInstance3D = _find_mesh_instance(instance)
		if mesh_inst == null or mesh_inst.mesh == null:
			push_error("BoardGenerator: pas de MeshInstance3D dans %s" % paths[i])
			return null

		# Créer un item avec l'index i, puis lui assigner le mesh.
		# Godot 4 MeshLibrary API : create_item(id), set_item_mesh(id, mesh),
		# set_item_name(id, name). Pas de set_item_shape en Godot 4.
		lib.create_item(i)
		lib.set_item_mesh(i, mesh_inst.mesh)
		lib.set_item_name(i, paths[i].get_file().replace(".glb", ""))

	# Sauvegarder en .tres pour réutilisation / édition dans l'inspecteur.
	ResourceSaver.save(lib, _PATH_MESHLIB)
	print("BoardGenerator: MeshLibrary sauvegardée → %s (%d items)" % [_PATH_MESHLIB, lib.get_item_list().size()])
	return lib


## Charge la MeshLibrary existante (ou la crée si absente).
static func get_or_create_mesh_library() -> MeshLibrary:
	if ResourceLoader.exists(_PATH_MESHLIB):
		var lib: MeshLibrary = load(_PATH_MESHLIB) as MeshLibrary
		if lib != null and lib.get_item_list().size() > 0:
			return lib
	return create_mesh_library()


# ============================================================================
# 2. PEUPLEMENT DE LA GRIDMAP
# ============================================================================

## Remplit la GridMap avec ring + home lanes + yards + centre.
## Ne vide PAS la GridMap avant (caller responsable).
static func populate(grid_map: GridMap, mesh_lib: MeshLibrary) -> void:
	if grid_map == null:
		push_error("BoardGenerator.populate: GridMap null.")
		return
	if mesh_lib == null:
		push_error("BoardGenerator.populate: MeshLibrary null — créez-la d'abord via create_mesh_library().")
		return
	grid_map.mesh_library = mesh_lib
	grid_map.cell_size = Vector3.ONE

	# Ring (52 cellules)
	for ring_index in range(BoardConfig.RING_SIZE):
		var cell: Vector3i = _array_to_vec3i(_RING_LAYOUT[ring_index])
		grid_map.set_cell_item(cell, ITEM_RING_PATH)

	# Home lanes (4 joueurs × 6 cellules)
	for player_id in range(BoardConfig.PLAYER_COUNT):
		for local_idx in range(BoardConfig.HOME_LANE_LENGTH):
			var cell: Vector3i = _array_to_vec3i(_HOME_LANE_LAYOUT[player_id][local_idx])
			grid_map.set_cell_item(cell, ITEM_HOME_PATH)

	# Yards (4 joueurs × 4 positions)
	for player_id in range(BoardConfig.PLAYER_COUNT):
		for pos in _YARD_LAYOUT[player_id]:
			var cell: Vector3i = _array_to_vec3i(pos)
			grid_map.set_cell_item(cell, ITEM_HOME)

	# Centre
	grid_map.set_cell_item(_array_to_vec3i(_CENTER_CELL), ITEM_CENTER)

	print("BoardGenerator: plateau généré (%d cellules ring, %d home lanes, %d yards, 1 centre)" % [
		BoardConfig.RING_SIZE,
		BoardConfig.PLAYER_COUNT * BoardConfig.HOME_LANE_LENGTH,
		BoardConfig.PLAYER_COUNT * BoardConfig.PAWNS_PER_PLAYER
	])


## Vide entièrement la GridMap.
static func clear(grid_map: GridMap) -> void:
	if grid_map == null:
		return
	grid_map.clear()


# ============================================================================
# 3. MAPPING POSITION → GRILLE (utilisé par BoardManager.cell_of())
# ============================================================================

## Retourne la cellule GridMap (Vector3i) pour un ring_index donné.
static func ring_index_to_cell(ring_index: int) -> Vector3i:
	return _array_to_vec3i(_RING_LAYOUT[ring_index])

## Retourne la cellule GridMap pour la home lane d'un joueur.
static func home_lane_cell(player_id: int, local_index: int) -> Vector3i:
	return _array_to_vec3i(_HOME_LANE_LAYOUT[player_id][local_index])

## Retourne la cellule du yard pour un joueur et un index de pion (0..3).
static func yard_cell(player_id: int, pawn_slot: int) -> Vector3i:
	return _array_to_vec3i(_YARD_LAYOUT[player_id][pawn_slot])

## Retourne la cellule du centre.
static func center_cell() -> Vector3i:
	return _array_to_vec3i(_CENTER_CELL)


# ============================================================================
# 4. UTILITAIRES INTERNES
# ============================================================================

static func _array_to_vec3i(arr: Array) -> Vector3i:
	# Les layouts stockent [col, row]. GridMap utilise (x, y, z) = (col, 0, row).
	return Vector3i(arr[0], 0, arr[1])


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var result := _find_mesh_instance(child)
		if result != null:
			return result
	return null


## Réservé pour un futur ajout de collision par item dans la MeshLibrary.
#static func _create_box_shape(aabb: AABB) -> BoxShape3D:
#	var shape := BoxShape3D.new()
#	shape.size = aabb.size
#	return shape
