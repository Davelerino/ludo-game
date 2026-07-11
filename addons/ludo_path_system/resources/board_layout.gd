## Bundle exporté (.tres) qui rassemble toute la géométrie logique d'un
## plateau Ludo : l'anneau partagé, le chemin complet de chaque joueur
## (couloir final inclus) et les positions de yard. C'est l'unique asset que
## BoardManager charge pour convertir un pion logique en position de grille.
##
## Indépendant de la GridMap : LudoBoardPainter s'en sert pour peindre une
## GridMap, mais ce Resource n'a lui-même aucune dépendance sur GridMap/Node.
class_name LudoBoardLayout
extends Resource

@export var shared_ring: LudoPathDescriptor

## Chemin complet de chaque joueur, indexé par player_id (taille == BoardConfig.PLAYER_COUNT).
@export var player_paths: Array[LudoPlayerPath] = []

## yard_positions[player_id] = Array[Vector2i] (BoardConfig.PAWNS_PER_PLAYER slots).
@export var yard_positions: Array[Array] = []

## Élévation (Y) commune utilisée pour convertir toutes les cellules Vector2i
## de ce plateau en Vector3i de GridMap (voir LudoPathMath.to_cell3i).
@export var elevation: int = 0


## Cellule de yard pour un pion donné (par son slot 0..PAWNS_PER_PLAYER-1).
func get_yard_cell(player_id: int, slot: int) -> Vector2i:
	return yard_positions[player_id][slot]


## Ré-attache shared_ring à chaque LudoPlayerPath. Nécessaire après un
## chargement depuis disque : shared_ring n'est PAS @export sur
## LudoPlayerPath (pour éviter de sérialiser l'anneau une fois par joueur
## dans le .tres), donc il doit être réinjecté explicitement avant tout
## get_position()/cell_of(). BoardManager.setup() s'en charge automatiquement.
func rewire() -> void:
	for path in player_paths:
		if path != null:
			path.shared_ring = shared_ring


## Vérifie la cohérence du plateau contre les constantes de BoardConfig.
## Retourne un tableau de messages d'erreur (vide si tout est valide).
func validate() -> Array[String]:
	var errors: Array[String] = []

	if shared_ring == null:
		errors.append("LudoBoardLayout: shared_ring manquant.")
	else:
		errors.append_array(shared_ring.validate())
		if shared_ring.get_length() != BoardConfig.RING_SIZE:
			errors.append(
				"LudoBoardLayout: shared_ring.get_length()=%d != BoardConfig.RING_SIZE=%d (jonction dupliquée par erreur ?)" % [
					shared_ring.get_length(), BoardConfig.RING_SIZE
				]
			)

	if player_paths.size() != BoardConfig.PLAYER_COUNT:
		errors.append("LudoBoardLayout: player_paths doit contenir %d entrées (trouvé %d)." % [BoardConfig.PLAYER_COUNT, player_paths.size()])

	for i in range(player_paths.size()):
		var path: LudoPlayerPath = player_paths[i]
		if path == null or path.home_path == null:
			errors.append("LudoBoardLayout: player_paths[%d] ou son home_path est null." % i)
			continue
		errors.append_array(path.home_path.validate())
		if path.home_path.get_length() != BoardConfig.HOME_LANE_LENGTH:
			errors.append(
				"LudoBoardLayout: player_paths[%d].home_path.get_length()=%d != BoardConfig.HOME_LANE_LENGTH=%d." % [
					i, path.home_path.get_length(), BoardConfig.HOME_LANE_LENGTH
				]
			)

	if yard_positions.size() != BoardConfig.PLAYER_COUNT:
		errors.append("LudoBoardLayout: yard_positions doit contenir %d entrées (trouvé %d)." % [BoardConfig.PLAYER_COUNT, yard_positions.size()])
	else:
		for i in range(yard_positions.size()):
			if yard_positions[i].size() != BoardConfig.PAWNS_PER_PLAYER:
				errors.append(
					"LudoBoardLayout: yard_positions[%d] doit contenir %d cases (trouvé %d)." % [
						i, BoardConfig.PAWNS_PER_PLAYER, yard_positions[i].size()
					]
				)

	errors.append_array(_validate_no_overlap())
	return errors


## Vérifie qu'aucune cellule n'est partagée entre l'anneau, les couloirs
## finaux et les yards — SAUF la case de centre (dernière cellule de chaque
## home_path), volontairement partagée entre les 4 joueurs.
func _validate_no_overlap() -> Array[String]:
	var errors: Array[String] = []
	var owner_of: Dictionary = {} # Vector2i -> String (description du propriétaire)

	if shared_ring != null:
		for cell in shared_ring.get_all_cells():
			owner_of[cell] = "shared_ring"

	for i in range(player_paths.size()):
		var path: LudoPlayerPath = player_paths[i]
		if path == null or path.home_path == null:
			continue
		var cells: Array[Vector2i] = path.home_path.get_all_cells()
		for j in range(cells.size()):
			var cell: Vector2i = cells[j]
			var is_finish: bool = (j == cells.size() - 1)
			if owner_of.has(cell):
				# Le centre partagé (dernière cellule de home_path) est une
				# exception attendue si l'autre propriétaire est aussi un
				# home_path à sa dernière cellule.
				if is_finish and owner_of[cell].begins_with("home_path"):
					continue
				errors.append("LudoBoardLayout: collision de cellule %s entre %s et home_path[%d]." % [cell, owner_of[cell], i])
			owner_of[cell] = "home_path[%d]" % i

	for i in range(yard_positions.size()):
		for slot in yard_positions[i]:
			if owner_of.has(slot):
				errors.append("LudoBoardLayout: collision de cellule %s entre %s et yard[%d]." % [slot, owner_of[slot], i])
			owner_of[slot] = "yard[%d]" % i

	return errors
