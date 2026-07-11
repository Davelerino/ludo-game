## Tests manuels (assert-based) pour le système de chemin par segments.
##
## Exécution en ligne de commande, depuis la racine du projet Godot :
##   godot4 --headless --script res://test_path_descriptor.gd
##
## (adaptez "godot4" au nom de votre exécutable si besoin : "godot",
## "Godot_v4.x_win64.exe", etc.)
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

	print("\n✅ TOUS LES TESTS SONT PASSÉS")
	quit()


func test_segment_validity() -> void:
	print("→ test_segment_validity")

	var valid_seg := PathSegment.new(Vector2i(1, 0), 6, Vector2i.ZERO)
	assert(valid_seg.is_valid(), "Segment horizontal valide devrait passer.")

	var zero_length := PathSegment.new(Vector2i(1, 0), 0, Vector2i.ZERO)
	assert(not zero_length.is_valid(), "Longueur 0 doit être invalide.")

	var zero_dir := PathSegment.new(Vector2i.ZERO, 5, Vector2i.ZERO)
	assert(not zero_dir.is_valid(), "Direction nulle doit être invalide.")

	var diagonal := PathSegment.new(Vector2i(1, 1), 5, Vector2i.ZERO)
	assert(not diagonal.is_valid(), "Direction diagonale doit être invalide (contrainte GridMap).")


func test_path_descriptor_example_from_spec() -> void:
	print("→ test_path_descriptor_example_from_spec")

	# Reproduit exactement l'exemple conceptuel de la conversation :
	# Segment 0: start (6,0), dir (0,1), len 5
	# Segment 1: dir (1,0), len 6, offset (0,0)
	# Segment 2: dir (0,-1), len 4, offset (2,0)
	var descriptor := PathDescriptor.new()
	descriptor.start_position = Vector2i(6, 0)
	descriptor.segments = [
		PathSegment.new(Vector2i(0, 1), 5, Vector2i.ZERO),
		PathSegment.new(Vector2i(1, 0), 6, Vector2i.ZERO),
		PathSegment.new(Vector2i(0, -1), 4, Vector2i(2, 0)),
	]

	var cells := descriptor.get_all_cells()

	var expected: Array[Vector2i] = [
		Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), # segment 0
		Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4), Vector2i(9, 4), Vector2i(10, 4), Vector2i(11, 4), # segment 1 (jonction (6,4) partagée)
		Vector2i(13, 4), Vector2i(13, 3), Vector2i(13, 2), Vector2i(13, 1), # segment 2 (offset (2,0) depuis (11,4) -> (13,4))
	]

	assert(cells.size() == expected.size(), "Taille attendue %d, obtenue %d" % [expected.size(), cells.size()])
	for i in range(expected.size()):
		assert(cells[i] == expected[i], "Cellule %d attendue %s, obtenue %s" % [i, expected[i], cells[i]])

	assert(descriptor.get_length() == 15, "get_length() devrait retourner 15.")
	assert(descriptor.get_cell(0) == Vector2i(6, 0), "get_cell(0) incorrect.")
	assert(descriptor.get_cell(14) == Vector2i(13, 1), "get_cell(14) (dernière cellule) incorrect.")


func test_index_lookup() -> void:
	print("→ test_index_lookup")

	var descriptor := PathDescriptor.new()
	descriptor.start_position = Vector2i(0, 0)
	descriptor.segments = [
		PathSegment.new(Vector2i(1, 0), 4, Vector2i.ZERO), # (0,0)(1,0)(2,0)(3,0)
	]

	assert(descriptor.get_index_at(Vector2i(2, 0)) == 2, "get_index_at devrait retourner 2 pour (2,0).")
	assert(descriptor.get_index_at(Vector2i(99, 99)) == -1, "Cellule hors chemin doit retourner -1.")


func test_junction_cell_is_shared() -> void:
	print("→ test_junction_cell_is_shared")

	# Vérifie explicitement le comportement documenté : quand offset == ZERO,
	# la cellule de jonction apparaît deux fois dans le cache, et
	# get_index_at() retourne le DERNIER index (le plus avancé en progression).
	var descriptor := PathDescriptor.new()
	descriptor.start_position = Vector2i(0, 0)
	descriptor.segments = [
		PathSegment.new(Vector2i(1, 0), 3, Vector2i.ZERO), # (0,0)(1,0)(2,0)
		PathSegment.new(Vector2i(0, 1), 3, Vector2i.ZERO), # (2,0)(2,1)(2,2)
	]

	var cells := descriptor.get_all_cells()
	assert(cells.size() == 6, "Taille attendue 6 (avec doublon de jonction).")
	assert(cells[2] == Vector2i(2, 0) and cells[3] == Vector2i(2, 0), "La jonction (2,0) doit apparaître aux index 2 et 3.")
	assert(descriptor.get_index_at(Vector2i(2, 0)) == 3, "get_index_at doit retourner le dernier index (3), pas le premier (2).")


func test_player_path_ring_and_home() -> void:
	print("→ test_player_path_ring_and_home")

	# Anneau partagé miniature : un carré de 8 cases (juste pour le test).
	var ring := PathDescriptor.new()
	ring.start_position = Vector2i(0, 0)
	ring.segments = [
		PathSegment.new(Vector2i(1, 0), 3, Vector2i.ZERO),  # (0,0)(1,0)(2,0)
		PathSegment.new(Vector2i(0, 1), 3, Vector2i(1, 0)), # offset pour éviter le doublon -> (3,1)(3,2)(3,3)
		PathSegment.new(Vector2i(-1, 0), 2, Vector2i(-1, 0)),
	]
	# Longueur totale de l'anneau : 3 + 3 + 2 = 8 cases

	var home := PathDescriptor.new()
	home.start_position = Vector2i(2, 5) # couloir final, indépendant de l'anneau
	home.segments = [
		PathSegment.new(Vector2i(0, 1), 3, Vector2i.ZERO),
	]

	var player := PlayerPath.new()
	player.setup(ring, 2, 5, home) # entre à l'index 2 de l'anneau, 5 pas avant le couloir final

	assert(player.get_total_length() == 5 + 3, "Longueur totale attendue 8.")

	# progress 0 -> ring_index (2+0)%8 = 2
	assert(player.get_position(0) == ring.get_cell(2), "progress 0 doit correspondre à ring[2].")
	assert(not player.is_in_home_path(0), "progress 0 ne doit pas être dans le couloir final.")

	# progress 4 (dernier pas sur l'anneau) -> ring_index (2+4)%8 = 6
	assert(player.get_position(4) == ring.get_cell(6), "progress 4 doit correspondre à ring[6].")
	assert(not player.is_in_home_path(4), "progress 4 est encore sur l'anneau.")

	# progress 5 -> premier pas du couloir final (home[0])
	assert(player.get_position(5) == home.get_cell(0), "progress 5 doit correspondre à home[0].")
	assert(player.is_in_home_path(5), "progress 5 doit être dans le couloir final.")

	# progress 7 (dernier pas) -> home[2]
	assert(player.get_position(7) == home.get_cell(2), "progress 7 doit correspondre à home[2].")


func test_player_path_wraps_around_ring() -> void:
	print("→ test_player_path_wraps_around_ring")

	var ring := PathDescriptor.new()
	ring.start_position = Vector2i(0, 0)
	ring.segments = [
		PathSegment.new(Vector2i(1, 0), 4, Vector2i.ZERO), # 4 cases : index 0..3
	]

	var home := PathDescriptor.new()
	home.start_position = Vector2i(10, 10)
	home.segments = [PathSegment.new(Vector2i(1, 0), 2, Vector2i.ZERO)]

	var player := PlayerPath.new()
	# Entrée à l'index 3 (dernière case de l'anneau) : le pas suivant doit
	# boucler correctement sur l'index 0 grâce au modulo.
	player.setup(ring, 3, 3, home)

	assert(player.get_position(0) == ring.get_cell(3), "progress 0 -> ring[3].")
	assert(player.get_position(1) == ring.get_cell(0), "progress 1 doit boucler sur ring[0].")
	assert(player.get_position(2) == ring.get_cell(1), "progress 2 doit boucler sur ring[1].")


func test_validate_reports_invalid_segment() -> void:
	print("→ test_validate_reports_invalid_segment")

	var descriptor := PathDescriptor.new()
	descriptor.start_position = Vector2i.ZERO
	descriptor.segments = [
		PathSegment.new(Vector2i(1, 1), 3, Vector2i.ZERO), # diagonale -> invalide
	]

	var errors := descriptor.validate()
	assert(errors.size() == 1, "validate() devrait remonter exactement 1 erreur.")

	var empty_descriptor := PathDescriptor.new()
	var empty_errors := empty_descriptor.validate()
	assert(empty_errors.size() == 1, "Un descripteur sans segment devrait remonter 1 erreur.")
