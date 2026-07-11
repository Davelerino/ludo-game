## Vérifie que LudoClassicLayoutBuilder produit un plateau cohérent :
## anneau de 52 cases sans jonction dupliquée, adjacence orthogonale partout
## (y compris la fermeture de boucle), couloirs finaux de la bonne longueur,
## aucune collision de cellule (sauf le centre partagé), et alignement des
## offsets de départ avec BoardConfig.
##
## Exécution :
##   godot4 --headless --script res://addons/ludo_path_system/tests/test_classic_layout.gd
extends SceneTree


func _initialize() -> void:
	var layout := LudoClassicLayoutBuilder.build()

	test_ring_length_and_no_duplication(layout)
	test_ring_is_axis_connected_and_closed(layout)
	test_home_lanes(layout)
	test_no_overlap(layout)
	test_player_offsets_match_board_config(layout)
	test_derive_home_descriptor_in_isolation()

	print("\nTOUS LES TESTS SONT PASSES (test_classic_layout)")
	quit()


func test_ring_length_and_no_duplication(layout: LudoBoardLayout) -> void:
	print("-> test_ring_length_and_no_duplication")
	assert(layout.shared_ring.get_length() == BoardConfig.RING_SIZE,
		"Ring devrait avoir %d cases, obtenu %d." % [BoardConfig.RING_SIZE, layout.shared_ring.get_length()])
	assert(not layout.shared_ring.has_duplicated_junctions(),
		"L'anneau classique ne doit avoir aucune jonction dupliquée.")


func test_ring_is_axis_connected_and_closed(layout: LudoBoardLayout) -> void:
	print("-> test_ring_is_axis_connected_and_closed")
	var cells := layout.shared_ring.get_all_cells()
	var n := cells.size()
	for i in range(n):
		var a: Vector2i = cells[i]
		var b: Vector2i = cells[(i + 1) % n]
		var diff := b - a
		var steps := absi(diff.x) + absi(diff.y)
		assert(steps == 1, "Ring: cellules %d->%d ne sont pas des voisins orthogonaux unitaires (%s -> %s)." % [i, (i + 1) % n, a, b])


func test_home_lanes(layout: LudoBoardLayout) -> void:
	print("-> test_home_lanes")
	for player_id in range(layout.player_paths.size()):
		var home := layout.player_paths[player_id].home_path
		assert(home.get_length() == BoardConfig.HOME_LANE_LENGTH,
			"Home lane joueur %d: longueur %d attendue %d." % [player_id, home.get_length(), BoardConfig.HOME_LANE_LENGTH])
		var cells := home.get_all_cells()
		for i in range(1, cells.size()):
			var diff: Vector2i = cells[i] - cells[i - 1]
			assert(absi(diff.x) + absi(diff.y) == 1, "Home lane joueur %d: cellules non adjacentes à l'index %d." % [player_id, i])
	# Les 4 couloirs doivent converger sur EXACTEMENT la même case de centre.
	var finish0 := layout.player_paths[0].get_finish_cell()
	for player_id in range(1, layout.player_paths.size()):
		assert(layout.player_paths[player_id].get_finish_cell() == finish0,
			"Le joueur %d ne termine pas sur la même case de centre que le joueur 0." % player_id)
	assert(finish0 == LudoClassicLayoutBuilder.CENTER, "La case de centre doit être (7,7).")


func test_no_overlap(layout: LudoBoardLayout) -> void:
	print("-> test_no_overlap")
	var errors := layout.validate()
	assert(errors.is_empty(), "LudoBoardLayout.validate() devrait être vide, obtenu: %s" % [errors])


func test_player_offsets_match_board_config(layout: LudoBoardLayout) -> void:
	print("-> test_player_offsets_match_board_config")
	for player_id in range(BoardConfig.PLAYER_COUNT):
		var path := layout.player_paths[player_id]
		assert(path.ring_entry_index == BoardConfig.get_player_offset(player_id),
			"ring_entry_index joueur %d attendu %d, obtenu %d." % [player_id, BoardConfig.get_player_offset(player_id), path.ring_entry_index])
		assert(path.ring_steps == BoardConfig.HOME_ENTRY_PROGRESS,
			"ring_steps joueur %d attendu %d, obtenu %d." % [player_id, BoardConfig.HOME_ENTRY_PROGRESS, path.ring_steps])
		# progress 0 doit correspondre exactement à la start tile du joueur sur l'anneau.
		assert(path.get_position(0) == layout.shared_ring.get_cell(path.ring_entry_index),
			"progress 0 du joueur %d ne correspond pas à sa start tile sur l'anneau." % player_id)


## Vérifie _derive_home_descriptor() en isolation (sans passer par build()) :
## une direction seule doit reproduire exactement les couloirs finaux
## attendus (start_position + case finale = centre).
func test_derive_home_descriptor_in_isolation() -> void:
	print("-> test_derive_home_descriptor_in_isolation")
	var cases := [
		{"direction": Vector2i(0, -1), "expected_start": Vector2i(7, 12)}, # BLUE
		{"direction": Vector2i(1, 0), "expected_start": Vector2i(2, 7)},   # GREEN
		{"direction": Vector2i(0, 1), "expected_start": Vector2i(7, 2)},   # RED
		{"direction": Vector2i(-1, 0), "expected_start": Vector2i(12, 7)}, # YELLOW
	]
	for c in cases:
		var home: LudoPathDescriptor = LudoClassicLayoutBuilder._derive_home_descriptor(c.direction)
		assert(home.start_position == c.expected_start,
			"_derive_home_descriptor(%s): start_position attendu %s, obtenu %s." % [c.direction, c.expected_start, home.start_position])
		assert(home.get_length() == BoardConfig.HOME_LANE_LENGTH,
			"_derive_home_descriptor(%s): longueur attendue %d." % [c.direction, BoardConfig.HOME_LANE_LENGTH])
		assert(home.get_cell(BoardConfig.HOME_LANE_LENGTH - 1) == LudoClassicLayoutBuilder.CENTER,
			"_derive_home_descriptor(%s): dernière case attendue = centre (7,7)." % c.direction)
