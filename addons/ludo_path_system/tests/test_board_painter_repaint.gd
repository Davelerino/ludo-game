## Reproduit et vérifie la correction du bug suivant : éditer les segments
## d'un LudoBoardLayout déjà peint une fois (donc déjà en cache), puis
## relancer "Generate Ludo Board", doit repeindre avec les NOUVELLES
## cellules — pas les anciennes (LudoPathDescriptor ne reconstruit jamais
## son cache tout seul, voir path_descriptor.gd). LudoBoardPainter.paint()
## doit forcer ce rebuild à chaque appel.
##
## Exécution :
##   godot --headless --path . --script res://addons/ludo_path_system/tests/test_board_painter_repaint.gd
extends SceneTree


func _initialize() -> void:
	test_repaint_after_segment_edit_reflects_new_cells()

	print("\nTOUS LES TESTS SONT PASSES (test_board_painter_repaint)")
	quit()


func test_repaint_after_segment_edit_reflects_new_cells() -> void:
	print("-> test_repaint_after_segment_edit_reflects_new_cells")

	var layout := LudoClassicLayoutBuilder.build()
	var grid_map := GridMap.new()
	var mesh_lib := LudoMeshLibraryFactory.get_or_create_mesh_library()

	# 1er "Generate" : construit le cache du shared_ring (52 cases, longueur
	# initiale du premier segment = 6).
	LudoBoardPainter.paint(grid_map, mesh_lib, layout)
	assert(layout.shared_ring.get_length() == 52, "Longueur initiale attendue 52.")
	var first_segment: LudoPathSegment = layout.shared_ring.segments[0]
	assert(first_segment.length == 6, "Longueur du 1er segment attendue 6 avant édition.")

	# Simule une édition dans l'Inspector : on raccourcit le 1er segment de
	# 2 cases. Le cache interne (_cache_built) est toujours à true à ce
	# stade puisque get_all_cells()/get_length() ont déjà été appelés par
	# le paint() ci-dessus.
	first_segment.length = 4

	# 2e "Generate" : sans le fix, LudoBoardPainter réutiliserait l'ancien
	# cache (toujours 52 cases) au lieu de refléter la modification.
	LudoBoardPainter.paint(grid_map, mesh_lib, layout)
	assert(layout.shared_ring.get_length() == 50, "Après édition, longueur attendue 50 (52-2), obtenu %d." % layout.shared_ring.get_length())

	grid_map.free()
