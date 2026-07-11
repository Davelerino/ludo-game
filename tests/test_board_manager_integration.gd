## Vérifie l'intégration réelle BoardManager <-> LudoBoardLayout <-> GridMap,
## en utilisant la vraie scène board_root.tscn et la vraie MeshLibrary,
## exactement comme le fait scenes/main.gd au runtime.
##
## Exécution :
##   godot --headless --path . --script res://tests/test_board_manager_integration.gd
extends SceneTree


func _initialize() -> void:
	var board_root: Node3D = (load("res://scenes/board/board_root.tscn") as PackedScene).instantiate()
	var grid_map: GridMap = board_root.get_node("GridMap")
	var yards_root: Node3D = board_root.get_node("Yards")

	var mesh_lib: MeshLibrary = LudoMeshLibraryFactory.get_or_create_mesh_library()
	assert(mesh_lib != null, "MeshLibrary ne devrait pas être null.")

	var layout: LudoBoardLayout = load("res://resources/BoardLayout.tres")
	assert(layout != null, "BoardLayout.tres devrait se charger.")
	assert(layout.validate().is_empty(), "BoardLayout chargé devrait être valide.")

	var mesh_mapping := LudoMeshMapping.new()
	LudoBoardPainter.paint(grid_map, mesh_lib, layout, mesh_mapping)
	assert(grid_map.get_used_cells().size() > 0, "La GridMap devrait être peuplée après paint().")
	print("Cellules peintes: ", grid_map.get_used_cells().size())

	var board_manager: BoardManager = BoardManager.new()
	var cfg: BoardConfig = load("res://resources/BoardConfig.tres")
	board_manager.setup(cfg, grid_map, layout, yards_root)
	assert(board_manager.validate_board(), "validate_board() devrait réussir avec un plateau peint et un layout valide.")

	# Un pion au yard : doit résoudre la position monde du Marker3D correspondant.
	var yard_pawn: Dictionary = board_manager.get_pawn_by_id(0)
	var yard_world_pos: Vector3 = board_manager.cell_world_position(yard_pawn)
	var expected_marker: Node3D = yards_root.get_node("Player0/Slot0")
	assert(yard_world_pos == expected_marker.position,
		"cell_world_position() d'un pion au yard incohérent avec le Marker3D Player0/Slot0.")

	# Simule une entrée en jeu (progress 0) : doit correspondre à la start tile du joueur.
	yard_pawn.state = BoardConfig.PawnState.RING
	yard_pawn.progress = 0
	var ring_cell: Vector3i = board_manager.cell_of(yard_pawn)
	var expected_ring: Vector3i = LudoPathMath.to_cell3i(layout.shared_ring.get_cell(BoardConfig.get_player_offset(0)), layout.elevation)
	assert(ring_cell == expected_ring, "cell_of() progress=0 incohérent avec la start tile de l'anneau.")

	# Simule un pion FINI : doit correspondre à la case de centre partagée.
	yard_pawn.state = BoardConfig.PawnState.FINI
	yard_pawn.progress = BoardConfig.FINISH_PROGRESS
	var finish_cell: Vector3i = board_manager.cell_of(yard_pawn)
	assert(finish_cell == LudoPathMath.to_cell3i(Vector2i(7, 7), layout.elevation), "cell_of() d'un pion FINI devrait être la case de centre (7,7).")

	# cell_world_position ne doit pas planter (passe par grid_map.map_to_local()).
	var world_pos: Vector3 = board_manager.cell_world_position(yard_pawn)
	print("world_pos pion FINI: ", world_pos)

	board_root.queue_free()
	print("\nTOUS LES TESTS SONT PASSES (test_board_manager_integration)")
	quit()
