class_name BoardManager
extends Node
## ============================================================================
## BoardManager — Génère et expose la géométrie du plateau (GDD §3, §11.1).
##
## RESPONSABILITÉS (§11.1)
##   - Construire le plateau procéduralement dans une GridMap (ring de 52 cases,
##     4 home lanes de 6 cases, 4 yards) à partir d'un BoardConfig.
##   - Traduire un pion logique (Dictionary) en coordonnées de cellule GridMap
##     (Vector3i) puis en position monde (Vector3) pour le PawnController.
##   - Maintenir la liste `all_pawns` (source de vérité d'état) et fournir des
##     accesseurs (get_pawn_by_id, pawns_of, ...) utilisés par les vues.
##   - NE PAS valider de règles : tout passe par RuleEngine. BoardManager ne
##     fait que porter l'état + la géométrie.
##
## DÉPENDANCES
##   - BoardConfig (constantes + fabriques de pions).
##   - RuleEngine (uniquement pour les conversions get_ring_index /
##     get_home_lane_index : ce sont des fonctions pures de positionnement).
##   - Une GridMap enfant (assignée dans board_root.tscn).
##
## NOTE : c'est un SQUELETTE. La géométrie réelle (MeshLibrary, offsets par
## joueur, élévations) sera branchée quand les assets seront prêts. Les
## signatures publiques (setup, cell_of, cell_world_position, get_pawn_by_id)
## sont définitives pour ne pas casser TurnManager/PawnController.
## ============================================================================

const PawnState := BoardConfig.PawnState

@export var config: BoardConfig
## La GridMap peuplée par build_board(). Rattachée dans board_root.tscn.
var grid_map: GridMap

## Source de vérité d'état (les mêmes Dictionaries que ceux du RuleEngine).
var all_pawns: Array = []

# --- offsets 3D par joueur (placeholder : disposition en croix centrée) ------
# En attendant les vrais assets, on calcule des positions déduites de l'index
# de ring / home lane pour que le PawnController ait des coordonnées cohérentes.
const CELL_SIZE: float = 1.0
const RING_RADIUS: float = 8.0  # rayon du cercle du ring (placeholder)


## Initialise les pions (4 par joueur, état MAISON) et construit le plateau.
func setup(p_config: BoardConfig, p_grid_map: GridMap) -> void:
	config = p_config
	grid_map = p_grid_map
	_init_pawns()
	build_board()


func _init_pawns() -> void:
	all_pawns.clear()
	for player_id in range(BoardConfig.PLAYER_COUNT):
		all_pawns.append_array(
			BoardConfig.create_player_pawns(player_id, player_id * BoardConfig.PAWNS_PER_PLAYER)
		)


## Construit la GridMap (ring + home lanes + yards). SQUELETTE : à compléter
## avec une MeshLibrary et la logique de placement par joueur (§3.1/§3.2).
func build_board() -> void:
	if grid_map == null:
		push_warning("BoardManager: aucune GridMap assignée, plateau non construit.")
		return
	# TODO §3 : peupler grid_map avec les cellules du ring, des home lanes et
	# des yards en utilisant config.RING_SIZE / HOME_LANE_LENGTH / PLAYER_COUNT
	# et RuleEngine.get_start_tile_index() / get_home_entry_ring_index().
	pass


# ----------------------------------------------------------------------------
# Géométrie : pion -> cellule / position monde
# ----------------------------------------------------------------------------

## Coordonnée de cellule GridMap (Vector3i) d'un pion selon son état logique.
func cell_of(pawn: Dictionary) -> Vector3i:
	match pawn.state:
		PawnState.MAISON:
			return _yard_cell(pawn)
		PawnState.RING:
			return _ring_cell(RuleEngine.get_ring_index(pawn))
		PawnState.HOME_LANE, PawnState.FINI:
			return _home_lane_cell(pawn.player, RuleEngine.get_home_lane_index(pawn))
	return Vector3i.ZERO


## Position monde (Vector3) d'un pion — utilisée par le PawnController.
func cell_world_position(pawn: Dictionary) -> Vector3:
	if grid_map != null:
		return grid_map.map_to_local(cell_of(pawn))
	# Fallback placeholder si la GridMap n'existe pas encore.
	return _placeholder_world_position(pawn)


# ----------------------------------------------------------------------------
# Accès à l'état
# ----------------------------------------------------------------------------

func get_pawn_by_id(pawn_id: int) -> Dictionary:
	for p in all_pawns:
		if p.id == pawn_id:
			return p
	return {}


func pawns_of(player_id: int) -> Array:
	return all_pawns.filter(func(p): return p.player == player_id)


func reset_all_to_yard() -> void:
	for pawn in all_pawns:
		pawn.state = PawnState.MAISON
		pawn.progress = -1


# ----------------------------------------------------------------------------
# Internes de géométrie (placeholders cohérents avec un plateau carré)
# ----------------------------------------------------------------------------

func _ring_cell(ring_index: int) -> Vector3i:
	# Placeholder : l'index de ring est mappé sur un cercle d'élévation z=0.
	# La vraie forme (croix Ludo) viendra avec la MeshLibrary.
	var angle: float = (float(ring_index) / float(BoardConfig.RING_SIZE)) * TAU
	return Vector3i(round(cos(angle) * RING_RADIUS), 0, round(sin(angle) * RING_RADIUS))


func _home_lane_cell(player_id: int, local_index: int) -> Vector3i:
	# Placeholder : home lane = segment radial vers le centre.
	var angle: float = (float(player_id) / float(BoardConfig.PLAYER_COUNT)) * TAU
	var r: float = RING_RADIUS - float(local_index + 1) * CELL_SIZE
	return Vector3i(round(cos(angle) * r), 0, round(sin(angle) * r))


func _yard_cell(pawn: Dictionary) -> Vector3i:
	# Placeholder : yards dans les coins, offset par pion du joueur.
	var base_angle: float = (float(pawn.player) / float(BoardConfig.PLAYER_COUNT)) * TAU
	var r: float = RING_RADIUS + 2.0 * CELL_SIZE
	return Vector3i(
		round(cos(base_angle) * r) + (pawn.id % 2),
		0,
		round(sin(base_angle) * r) + (pawn.id / 2)
	)


func _placeholder_world_position(pawn: Dictionary) -> Vector3:
	var c: Vector3i = cell_of(pawn)
	return Vector3(c) * CELL_SIZE
