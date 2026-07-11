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
##   - LudoBoardLayout (addons/ludo_path_system) : géométrie du plateau par
##     segments (anneau + couloirs finaux + yards). Remplace l'ancien
##     BoardGenerator à tableaux codés en dur.
##   - RuleEngine : aucune dépendance géométrique, seulement pawn.progress
##     (entier), traduit en Vector2i par LudoPlayerPath.get_position().
##   - Une GridMap déjà peuplée (assignée dans board_root.tscn).
## ============================================================================

const PawnState := BoardConfig.PawnState

@export var config: BoardConfig
## Géométrie du plateau (anneau + couloirs finaux + yards), voir LudoBoardLayout.
@export var layout: LudoBoardLayout
## GridMap peuplée par le plugin éditeur (pas par ce script au runtime).
var grid_map: GridMap

## Source de vérité d'état (les mêmes Dictionaries que ceux du RuleEngine).
var all_pawns: Array = []


## Initialise les pions (4 par joueur, état MAISON) et assigne les dépendances.
## NE génère PAS le plateau — voir validate_board() pour le contrôle.
func setup(p_config: BoardConfig, p_grid_map: GridMap, p_layout: LudoBoardLayout) -> void:
	config = p_config
	grid_map = p_grid_map
	layout = p_layout
	if layout != null:
		layout.rewire()
	_init_pawns()


func _init_pawns() -> void:
	all_pawns.clear()
	for player_id in range(BoardConfig.PLAYER_COUNT):
		all_pawns.append_array(
			BoardConfig.create_player_pawns(player_id, player_id * BoardConfig.PAWNS_PER_PLAYER)
		)


## Vérifie que le layout est cohérent et que la GridMap a bien été cuite par
## le plugin éditeur. Log un warning clair si ce n'est pas le cas (aide au
## debug — rappelle le workflow Tools > Generate Ludo Board puis Ctrl+S).
## Retourne true si le plateau est présent, false sinon.
func validate_board() -> bool:
	if layout == null:
		push_warning("BoardManager: aucun LudoBoardLayout assigné.")
		return false
	var layout_errors: Array[String] = layout.validate()
	if not layout_errors.is_empty():
		push_warning("BoardManager: LudoBoardLayout invalide :\n - %s" % "\n - ".join(layout_errors))
		return false
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
## RING/HOME_LANE passent par LudoPlayerPath.get_position(pawn.progress), qui
## gère lui-même le bouclage sur l'anneau et l'embranchement vers le couloir
## final — BoardManager ne fait ici que convertir Vector2i -> Vector3i.
func cell_of(pawn: Dictionary) -> Vector3i:
	match pawn.state:
		PawnState.MAISON:
			return _yard_cell(pawn)
		PawnState.RING, PawnState.HOME_LANE:
			var cell: Vector2i = layout.player_paths[pawn.player].get_position(pawn.progress)
			return LudoPathMath.to_cell3i(cell, layout.elevation)
		PawnState.FINI:
			var finish: Vector2i = layout.player_paths[pawn.player].get_finish_cell()
			return LudoPathMath.to_cell3i(finish, layout.elevation)
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
	return LudoPathMath.to_cell3i(layout.get_yard_cell(pawn.player, slot), layout.elevation)
