## Peint une GridMap à partir d'un LudoBoardLayout (anneau + couloirs finaux
## + yards). Remplace l'ancien BoardGenerator.populate() codé en dur et le
## pipeline peindre-puis-détecter de l'addon ludo_board_generator : la
## géométrie vient maintenant entièrement des LudoPathDescriptor du layout.
##
## Fonction pure : ne modifie que la GridMap passée en paramètre.
class_name LudoBoardPainter
extends RefCounted


static func paint(grid_map: GridMap, mesh_lib: MeshLibrary, layout: LudoBoardLayout) -> void:
	if grid_map == null:
		push_error("LudoBoardPainter.paint: GridMap null.")
		return
	if mesh_lib == null:
		push_error("LudoBoardPainter.paint: MeshLibrary null.")
		return
	if layout == null:
		push_error("LudoBoardPainter.paint: LudoBoardLayout null.")
		return

	grid_map.mesh_library = mesh_lib

	for cell in layout.shared_ring.get_all_cells():
		grid_map.set_cell_item(LudoPathMath.to_cell3i(cell, layout.elevation), LudoMeshLibraryFactory.ITEM_RING_PATH)

	for player_id in range(layout.player_paths.size()):
		var path: LudoPlayerPath = layout.player_paths[player_id]
		var home_cells: Array[Vector2i] = path.home_path.get_all_cells()
		for i in range(home_cells.size()):
			var is_finish: bool = (i == home_cells.size() - 1)
			var item: int = LudoMeshLibraryFactory.ITEM_CENTER if is_finish else LudoMeshLibraryFactory.ITEM_HOME_PATH
			grid_map.set_cell_item(LudoPathMath.to_cell3i(home_cells[i], layout.elevation), item)

	for player_id in range(layout.yard_positions.size()):
		for slot in layout.yard_positions[player_id]:
			grid_map.set_cell_item(LudoPathMath.to_cell3i(slot, layout.elevation), LudoMeshLibraryFactory.ITEM_HOME)

	print("LudoBoardPainter: plateau peint (%d cellules ring, %d joueurs)." % [
		layout.shared_ring.get_length(), layout.player_paths.size()
	])


static func clear(grid_map: GridMap) -> void:
	if grid_map != null:
		grid_map.clear()
