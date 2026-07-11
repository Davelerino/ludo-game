## Tests manuels (assert-based) pour le système de chemin par segments.
##
## Exécution en ligne de commande, depuis la racine du projet Godot :
##   godot4 --headless --script res://addons/ludo_path_system/tests/test_path_descriptor.gd
##
## Le script s'arrête au premier assert qui échoue. S'il affiche
## "TOUS LES TESTS SONT PASSÉS", tout est vert.
extends SceneTree


func _initialize() -> void:
	test_segment_validity()
	test_path_descriptor_example_from_spec()
	test_index_lookup()
	test_junction_cell_is_shared()
	test_player_path_ring_and_home()
	test_player_path_wraps_around_ring()
	test_validate_reports_invalid_segment()

	print("\nTOUS LES TESTS SONT PASSES (test_path_descriptor)")
	quit()


func test_segment_validity() -> void:
	print("-> test_segment_validity")

	var valid_seg := LudoPathSegment.new(Vector2i(1, 0), 6, Vector2i.ZERO)
	assert(valid_seg.is_valid(), "Segment horizontal valide devrait passer.")

	var zero_length := LudoPathSegment.new(Vector2i(1, 0), 0, Vector2i.ZERO)
	assert(not zero_length.is_valid(), "Longueur 0 doit être invalide.")

	var zero_dir := LudoPathSegment.new(Vector2i.ZERO, 5, Vector2i.ZERO)
	assert(not zero_dir.is_valid(), "Direction nulle doit être invalide.")

	var diagonal := LudoPathSegment.new(Vector2i(1, 1), 5, Vector2i.ZERO)
	assert(not diagonal.is_valid(), "Direction diagonale doit être invalide (contrainte GridMap).")


func test_path_descriptor_example_from_spec() -> void:
	print("-> test_path_descriptor_example_from_spec")

	var descriptor := LudoPathDescriptor.new()
	descriptor.start_position = Vector2i(6, 0)
	descriptor.segments = [
		LudoPathSegment.new(Vector2i(0, 1), 5, Vector2i.ZERO),
		LudoPathSegment.new(Vector2i(1, 0), 6, Vector2i.ZERO),
		LudoPathSegment.new(Vector2i(0, -1), 4, Vector2i(2, 0)),
	]

	var cells := descriptor.get_all_cells()

	var expected: Array[Vector2i] = [
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4),
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(11, 4),
		Vector2i(13, 4), Vector2i(13, 3), Vector2i(13, 2), Vector2i(13, 1),
	]

	assert(cells.size() == expected.size(), "Taille attendue %d, obtenue %d" % [expected.size(), cells.size()])
	for i in range(expected.size()):
		assert(cells[i] == expected[i], "Cellule %d attendue %s, obtenue %s" % [i, expected[i], cells[i]])

	assert(descriptor.get_length() == 15, "get_length() devrait retourner 15.")
	assert(descriptor.get_cell(0) == Vector2i(6, 0), "get_cell(0) incorrect.")
	assert(descriptor.get_cell(14) == Vector2i(13, 1), "get_cell(14) (dernière cellule) incorrect.")


func test_index_lookup() -> void:
	print("-> test_index_lookup")

	var descriptor := LudoPathDescriptor.new()
	descriptor.start_position = Vector2i(0, 0)
	descriptor.segments = [
		LudoPathSegment.new(Vector2i(1, 0), 4, Vector2i.ZERO),
	]

	assert(descriptor.get_index_at(Vector2i(2, 0)) == 2, "get_index_at devrait retourner 2 pour (2,0).")
	assert(descriptor.get_index_at(Vector2i(99, 99)) == -1, "Cellule hors chemin doit retourner -1.")


func test_junction_cell_is_shared() -> void:
	print("-> test_junction_cell_is_shared")

	var descriptor := LudoPathDescriptor.new()
	descriptor.start_position = Vector2i(0, 0)
	descriptor.segments = [
		LudoPathSegment.new(Vector2i(1, 0), 3, Vector2i.ZERO),
		LudoPathSegment.new(Vector2i(0, 1), 3, Vector2i.ZERO),
	]

	var cells := descriptor.get_all_cells()
	assert(cells.size() == 6, "Taille attendue 6 (avec doublon de jonction).")
	assert(cells[2] == Vector2i(2, 0) and cells[3] == Vector2i(2, 0), "La jonction (2,0) doit apparaître aux index 2 et 3.")
	assert(descriptor.get_index_at(Vector2i(2, 0)) == 3, "get_index_at doit retourner le dernier index (3), pas le premier (2).")
	assert(descriptor.has_duplicated_junctions(), "has_duplicated_junctions() doit détecter le doublon.")


func test_player_path_ring_and_home() -> void:
	print("-> test_player_path_ring_and_home")

	var ring := LudoPathDescriptor.new()
	ring.start_position = Vector2i(0, 0)
	ring.segments = [
		LudoPathSegment.new(Vector2i(1, 0), 3, Vector2i.ZERO),
		LudoPathSegment.new(Vector2i(0, 1), 3, Vector2i(1, 0)),
		LudoPathSegment.new(Vector2i(-1, 0), 2, Vector2i(-1, 0)),
	]
	assert(not ring.has_duplicated_junctions(), "Cet anneau ne doit pas avoir de jonction dupliquée.")

	var home := LudoPathDescriptor.new()
	home.start_position = Vector2i(2, 5)
	home.segments = [
		LudoPathSegment.new(Vector2i(0, 1), 3, Vector2i.ZERO),
	]

	var player := LudoPlayerPath.new()
	player.setup(ring, 2, 5, home)

	assert(player.get_total_length() == 5 + 3, "Longueur totale attendue 8.")

	assert(player.get_position(0) == ring.get_cell(2), "progress 0 doit correspondre à ring[2].")
	assert(not player.is_in_home_path(0), "progress 0 ne doit pas être dans le couloir final.")

	assert(player.get_position(4) == ring.get_cell(6), "progress 4 doit correspondre à ring[6].")
	assert(not player.is_in_home_path(4), "progress 4 est encore sur l'anneau.")

	assert(player.get_position(5) == home.get_cell(0), "progress 5 doit correspondre à home[0].")
	assert(player.is_in_home_path(5), "progress 5 doit être dans le couloir final.")

	assert(player.get_position(7) == home.get_cell(2), "progress 7 doit correspondre à home[2].")
	assert(player.get_finish_cell() == home.get_cell(2), "get_finish_cell() doit retourner la dernière cellule du home_path.")


func test_player_path_wraps_around_ring() -> void:
	print("-> test_player_path_wraps_around_ring")

	var ring := LudoPathDescriptor.new()
	ring.start_position = Vector2i(0, 0)
	ring.segments = [
		LudoPathSegment.new(Vector2i(1, 0), 4, Vector2i.ZERO),
	]

	var home := LudoPathDescriptor.new()
	home.start_position = Vector2i(10, 10)
	home.segments = [LudoPathSegment.new(Vector2i(1, 0), 2, Vector2i.ZERO)]

	var player := LudoPlayerPath.new()
	player.setup(ring, 3, 3, home)

	assert(player.get_position(0) == ring.get_cell(3), "progress 0 -> ring[3].")
	assert(player.get_position(1) == ring.get_cell(0), "progress 1 doit boucler sur ring[0].")
	assert(player.get_position(2) == ring.get_cell(1), "progress 2 doit boucler sur ring[1].")


func test_validate_reports_invalid_segment() -> void:
	print("-> test_validate_reports_invalid_segment")

	var descriptor := LudoPathDescriptor.new()
	descriptor.start_position = Vector2i.ZERO
	descriptor.segments = [
		LudoPathSegment.new(Vector2i(1, 1), 3, Vector2i.ZERO),
	]

	var errors := descriptor.validate()
	assert(errors.size() == 1, "validate() devrait remonter exactement 1 erreur.")

	var empty_descriptor := LudoPathDescriptor.new()
	var empty_errors := empty_descriptor.validate()
	assert(empty_errors.size() == 1, "Un descripteur sans segment devrait remonter 1 erreur.")
