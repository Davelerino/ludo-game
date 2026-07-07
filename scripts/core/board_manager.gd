class_name BoardManager
extends Node
## ============================================================================
## BoardManager — Couche logique du plateau (GDD §3, §11.1).
##
## RESPONSABILITÉS (§11.1) — PURE LOGIQUE, NE GÉNÈRE RIEN
##   - Porter l'état des pions (all_pawns, source de vérité du RuleEngine).
##   - Bridge pion logique (Dictionary) ↔ cellule 3D (Vector3i) ↔ monde (Vector3).
##   - NE PAS construire le plateau : la géométrie est CUIT dans board_root.tscn
##     par le plugin "Ludo Board Tools" (Tools > Generate Ludo Board), puis Ctrl+S.
##     Au runtime, la GridMap a déjà ses cellules — BoardManager ne fait que lire.
##
## WORKFLOW (philosophie A : plugin cuit)
##   1. Éditeur : ouvrir board_root.tscn
##   2. Tools > Generate Ludo Board  (plugin peuple la GridMap)
##   3. Ctrl+S                        (cuit les cellules dans la scène)
##   4. Runtime : main.tscn instancie board_root.tscn → GridMap déjà pleine
##
## DÉPENDANCES
##   - BoardConfig (constantes + fabriques de pions).
##   - BoardGenerator (UNIQUEMENT pour les lookup ring_index→cell, home_lane→cell,
##     yard→cell : table d'adressage partagée avec le plugin. PAS de populate()).
##   - RuleEngine (conversions get_ring_index / get_home_lane_index).
##   - Une GridMap déjà peuplée (assignée dans board_root.tscn).
## ============================================================================

const PawnState := BoardConfig.PawnState

@export var config: BoardConfig
## GridMap peuplée par le plugin éditeur (pas par ce script au runtime).
var grid_map: GridMap

## Source de vérité d'état (les mêmes Dictionaries que ceux du RuleEngine).
var all_pawns: Array = []


## Initialise les pions (4 par joueur, état MAISON) et assigne les dépendances.
## NE génère PAS le plateau — voir validate_board() pour le contrôle.
func setup(p_config: BoardConfig, p_grid_map: GridMap) -> void:
	config = p_config
	grid_map = p_grid_map
	_init_pawns()


func _init_pawns() -> void:
	all_pawns.clear()
	for player_id in range(BoardConfig.PLAYER_COUNT):
		all_pawns.append_array(
			BoardConfig.create_player_pawns(player_id, player_id * BoardConfig.PAWNS_PER_PLAYER)
		)


## Vérifie que la GridMap a bien été cuite par le plugin éditeur.
## Log un warning clair si ce n'est pas le cas (aide au debug — rappelle le
## workflow Tools > Generate Ludo Board puis Ctrl+S).
## Retourne true si le plateau est présent, false sinon.
func validate_board() -> bool:
	if grid_map == null:
		push_warning("BoardManager: aucune GridMap assignée.")
		return false
	if grid_map.get_used_cells().is_empty():
		push_warning(String(" ").join([
			"BoardManager: la GridMap est VIDE au runtime.",
			"Le plateau n'a pas été cuit par le plugin éditeur.",
			"Workflow : ouvrir board_root.tscn → Tools > Generate Ludo Board → Ctrl+S."
		]))
		return false
	return true


# ----------------------------------------------------------------------------
# Géométrie : pion -> cellule / position monde (lecture seule, pas de génération)
# ----------------------------------------------------------------------------

## Coordonnée de cellule GridMap (Vector3i) d'un pion selon son état logique.
## Utilise la lookup table de BoardGenerator (mêmes cellules que celles cuites
## par le plugin) — pure adresse, aucune écriture sur la GridMap.
func cell_of(pawn: Dictionary) -> Vector3i:
	match pawn.state:
		PawnState.MAISON:
			return _yard_cell(pawn)
		PawnState.RING:
			return BoardGenerator.ring_index_to_cell(RuleEngine.get_ring_index(pawn))
		PawnState.HOME_LANE:
			return BoardGenerator.home_lane_cell(pawn.player, RuleEngine.get_home_lane_index(pawn))
		PawnState.FINI:
			return BoardGenerator.center_cell()
	return Vector3i.ZERO


## Position monde (Vector3) d'un pion — utilisée par le PawnController.
func cell_world_position(pawn: Dictionary) -> Vector3:
	if grid_map != null:
		return grid_map.map_to_local(cell_of(pawn))
	# Fallback si la GridMap n'existe pas (dev only).
	var c: Vector3i = cell_of(pawn)
	return Vector3(c.x, 0, c.z)


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
# Internes
# ----------------------------------------------------------------------------

## Cellule de yard pour un pion. Chaque joueur a 4 positions 2×2 ; on assigne
## le slot par l'index local du pion dans son équipe (0..3).
func _yard_cell(pawn: Dictionary) -> Vector3i:
	var slot: int = pawn.id % BoardConfig.PAWNS_PER_PLAYER
	return BoardGenerator.yard_cell(pawn.player, slot)
