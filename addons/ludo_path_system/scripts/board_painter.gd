## Peint une GridMap à partir d'un LudoBoardLayout (anneau + couloirs finaux)
## et d'un LudoMeshMapping (identité visuelle par joueur : start tile sur
## l'anneau + couleur du couloir final). Remplace l'ancien
## BoardGenerator.populate() codé en dur et le pipeline peindre-puis-détecter
## de l'addon ludo_board_generator : la géométrie vient entièrement des
## LudoPathDescriptor du layout, l'identité visuelle entièrement du mapping.
##
## Les yards ne sont PAS peints ici : ce sont des Marker3D placés à la main
## dans la scène (décor pour l'état MAISON), pas une géométrie de chemin.
##
## Fonction pure : ne modifie que la GridMap passée en paramètre.
@tool
class_name LudoBoardPainter
extends RefCounted


static func paint(grid_map: GridMap, mesh_lib: MeshLibrary, layout: LudoBoardLayout, mesh_mapping: LudoMeshMapping) -> void:
	if grid_map == null:
		push_error("LudoBoardPainter.paint: GridMap null.")
		return
	if mesh_lib == null:
		push_error("LudoBoardPainter.paint: MeshLibrary null.")
		return
	if layout == null:
		push_error("LudoBoardPainter.paint: LudoBoardLayout null.")
		return
	if mesh_mapping == null:
		push_error("LudoBoardPainter.paint: LudoMeshMapping null.")
		return

	grid_map.mesh_library = mesh_lib

	# LudoPathDescriptor met son cache de cellules en cache APRÈS le premier
	# accès et ne le reconstruit jamais tout seul (par design, voir son
	# docstring — c'est une optimisation runtime, pas pertinente ici). Sans
	# ce rebuild explicite, éditer des segments dans l'Inspector puis
	# relancer "Generate Ludo Board" repeindrait avec les ANCIENNES cellules
	# si ce LudoBoardLayout avait déjà été peint une fois dans cette session
	# éditeur (l'objet Resource, et donc son cache, reste en mémoire).
	layout.shared_ring.rebuild_cache()
	for path in layout.player_paths:
		if path != null and path.home_path != null:
			path.home_path.rebuild_cache()

	# 1) Anneau uniforme.
	for cell in layout.shared_ring.get_all_cells():
		grid_map.set_cell_item(LudoPathMath.to_cell3i(cell, layout.elevation), mesh_mapping.get_ring_mesh_id())

	# 2) Start tile de chaque joueur (écrase l'item uniforme posé à l'étape 1
	# — logiquement c'est toujours une case d'anneau normale, seul son mesh diffère).
	for player_id in range(layout.player_paths.size()):
		var path: LudoPlayerPath = layout.player_paths[player_id]
		var start_cell: Vector2i = layout.shared_ring.get_cell(path.ring_entry_index)
		grid_map.set_cell_item(LudoPathMath.to_cell3i(start_cell, layout.elevation), mesh_mapping.get_start_mesh_id(player_id))

	# 3) Couloir final de chaque joueur (case de centre partagée en dernier).
	for player_id in range(layout.player_paths.size()):
		var path: LudoPlayerPath = layout.player_paths[player_id]
		var home_cells: Array[Vector2i] = path.home_path.get_all_cells()
		for i in range(home_cells.size()):
			var is_finish: bool = (i == home_cells.size() - 1)
			var item: int = mesh_mapping.get_center_mesh_id() if is_finish else mesh_mapping.get_home_lane_mesh_id(player_id)
			grid_map.set_cell_item(LudoPathMath.to_cell3i(home_cells[i], layout.elevation), item)

	print("LudoBoardPainter: plateau peint (%d cellules ring, %d joueurs)." % [
		layout.shared_ring.get_length(), layout.player_paths.size()
	])


static func clear(grid_map: GridMap) -> void:
	if grid_map != null:
		grid_map.clear()
