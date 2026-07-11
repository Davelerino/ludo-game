## Crée/charge la MeshLibrary utilisée pour peindre un plateau Ludo à partir
## des 4 meshes GLB. Aucune dépendance sur la géométrie du chemin (ring/home) :
## uniquement responsable des assets visuels. Repris tel quel de l'ancien
## scripts/core/board_generator.gd (logique inchangée), séparé de la
## géométrie qui est maintenant portée par LudoBoardLayout/LudoBoardPainter.
class_name LudoMeshLibraryFactory
extends RefCounted

# --- Indices des items dans la MeshLibrary (partagés par tous les joueurs) ---
const ITEM_RING_PATH: int = 0    # SM_Ludo_SimplePath.glb
const ITEM_HOME_PATH: int = 1    # SM_Ludo_HomePath.glb
const ITEM_HOME: int = 2         # SM_Ludo_Home.glb (yard)
const ITEM_CENTER: int = 3       # SM_Ludo_Center.glb

const _PATH_RING_PATH := "res://assets/meshes/SM_Ludo_SimplePath.glb"
const _PATH_HOME_PATH := "res://assets/meshes/SM_Ludo_HomePath.glb"
const _PATH_HOME       := "res://assets/meshes/SM_Ludo_Home.glb"
const _PATH_CENTER     := "res://assets/meshes/SM_Ludo_Center.glb"
const _PATH_MESHLIB    := "res://resources/LudoMeshLibrary_02.tres"


## Crée une MeshLibrary à partir des 4 GLB et la sauve en .tres.
## Retourne la MeshLibrary (ou null si échec).
static func create_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var paths := [_PATH_RING_PATH, _PATH_HOME_PATH, _PATH_HOME, _PATH_CENTER]

	for i in range(paths.size()):
		var packed: PackedScene = load(paths[i]) as PackedScene
		if packed == null:
			push_error("LudoMeshLibraryFactory: impossible de charger %s" % paths[i])
			return null
		var instance: Node3D = packed.instantiate() as Node3D
		if instance == null:
			push_error("LudoMeshLibraryFactory: l'instance de %s n'est pas un Node3D" % paths[i])
			return null
		var mesh_inst: MeshInstance3D = _find_mesh_instance(instance)
		if mesh_inst == null or mesh_inst.mesh == null:
			push_error("LudoMeshLibraryFactory: pas de MeshInstance3D dans %s" % paths[i])
			return null

		lib.create_item(i)
		lib.set_item_mesh(i, mesh_inst.mesh)
		lib.set_item_name(i, paths[i].get_file().replace(".glb", ""))

	ResourceSaver.save(lib, _PATH_MESHLIB)
	print("LudoMeshLibraryFactory: MeshLibrary sauvegardée -> %s (%d items)" % [_PATH_MESHLIB, lib.get_item_list().size()])
	return lib


## Charge la MeshLibrary existante (ou la crée si absente).
static func get_or_create_mesh_library() -> MeshLibrary:
	if ResourceLoader.exists(_PATH_MESHLIB):
		var lib: MeshLibrary = load(_PATH_MESHLIB) as MeshLibrary
		if lib != null and lib.get_item_list().size() > 0:
			return lib
	return create_mesh_library()


static func _find_mesh_instance(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root as MeshInstance3D
	for child in root.get_children():
		var result := _find_mesh_instance(child)
		if result != null:
			return result
	return null
