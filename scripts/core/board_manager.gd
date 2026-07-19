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
##     segments (anneau + couloirs finaux). Remplace l'ancien BoardGenerator
##     à tableaux codés en dur.
##   - RuleEngine : aucune dépendance géométrique, seulement pawn.progress
##     (entier), traduit en Vector2i par LudoPlayerPath.get_position().
##   - Une GridMap déjà peuplée (assignée dans board_root.tscn).
##   - yards_root (Node3D) : conteneur "Yards" de board_root.tscn, avec des
##     Marker3D Player<id>/Slot<n> — pur décor pour l'état MAISON, PAS une
##     géométrie de chemin (voir _yard_world_position()).
##   - capture_zones_root (Node3D) : conteneur "CaptureZones" de board_root.tscn,
##     même principe pour l'état CAPTURED (voir _capture_zone_world_position()).
## ============================================================================

const PawnState := BoardConfig.PawnState

@export var config: BoardConfig
## Géométrie du plateau (anneau + couloirs finaux), voir LudoBoardLayout.
@export var layout: LudoBoardLayout
## GridMap peuplée par le plugin éditeur (pas par ce script au runtime).
var grid_map: GridMap
## Conteneur des Marker3D de yard ("Yards" dans board_root.tscn).
var yards_root: Node3D
## Conteneur des Marker3D de zone de capture ("CaptureZones" dans board_root.tscn).
var capture_zones_root: Node3D

## Source de vérité d'état (les mêmes Dictionaries que ceux du RuleEngine).
var all_pawns: Array = []


## Initialise les pions (4 par joueur, état MAISON) et assigne les dépendances.
## NE génère PAS le plateau — voir validate_board() pour le contrôle.
func setup(p_config: BoardConfig, p_grid_map: GridMap, p_layout: LudoBoardLayout, p_yards_root: Node3D, p_capture_zones_root: Node3D) -> void:
	config = p_config
	grid_map = p_grid_map
	layout = p_layout
	yards_root = p_yards_root
	capture_zones_root = p_capture_zones_root
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

## Coordonnée de cellule GridMap (Vector3i) d'un pion EN JEU (RING/HOME_LANE/
## FINI) — pas pour MAISON, qui n'est plus une case du chemin logique (voir
## cell_world_position()). RING/HOME_LANE passent par
## LudoPlayerPath.get_position(pawn.progress), qui gère lui-même le bouclage
## sur l'anneau et l'embranchement vers le couloir final — BoardManager ne
## fait ici que convertir Vector2i -> Vector3i.
func cell_of(pawn: Dictionary) -> Vector3i:
	match pawn.state:
		PawnState.RING, PawnState.HOME_LANE:
			var cell: Vector2i = layout.player_paths[pawn.player].get_position(pawn.progress)
			return LudoPathMath.to_cell3i(cell, layout.elevation)
		PawnState.FINI:
			var finish: Vector2i = layout.player_paths[pawn.player].get_finish_cell()
			return LudoPathMath.to_cell3i(finish, layout.elevation)
	push_error("BoardManager.cell_of: état %s non géré (MAISON n'est pas une case de chemin, voir cell_world_position())." % pawn.state)
	return Vector3i.ZERO


## Position monde (Vector3) d'un pion — utilisée par le PawnController.
## MAISON/CAPTURED sont du pur décor de scène (Marker3D sous yards_root /
## capture_zones_root), pas des cases de GridMap : traités à part, avant tout
## appel à cell_of().
func cell_world_position(pawn: Dictionary) -> Vector3:
	if pawn.state == PawnState.MAISON:
		return _yard_world_position(pawn)
	if pawn.state == PawnState.CAPTURED:
		return _capture_zone_world_position(pawn)
	if grid_map != null:
		return grid_map.map_to_local(cell_of(pawn))
	# Fallback si la GridMap n'existe pas (dev only).
	var c: Vector3i = cell_of(pawn)
	return Vector3(c.x, 0, c.z)


## Position monde pour un player_id + progress ARBITRAIRE (RING/HOME_LANE/FINI),
## sans passer par un Dictionary de pion réel. Utilisée par PawnController pour
## calculer les cases intermédiaires d'une animation multi-hop, sans avoir
## besoin de muter (ou dupliquer) un pion réel. Fonction pure.
func world_position_for_progress(player_id: int, progress: int) -> Vector3:
	var cell2i: Vector2i = layout.player_paths[player_id].get_position(progress)
	var cell3i: Vector3i = LudoPathMath.to_cell3i(cell2i, layout.elevation)
	if grid_map != null:
		return grid_map.map_to_local(cell3i)
	return Vector3(cell3i.x, 0, cell3i.z)


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
		pawn.captor_id = -1


## Applique un scénario manuel (mode test, voir ui/scenario/scenario_setup.gd) :
## mute directement state/progress/captor_id des pions EXISTANTS (trouvés par
## id), SANS passer par RuleEngine.apply_move() — positionnement brut, pas un
## coup validé. Les pions non mentionnés dans `entries` restent inchangés.
## Retourne les avertissements non bloquants de RuleEngine.validate_scenario_pawn().
func apply_scenario(entries: Array) -> Array[String]:
	var warnings: Array[String] = []
	for entry in entries:
		var pawn: Dictionary = get_pawn_by_id(entry.id)
		if pawn.is_empty():
			warnings.append("apply_scenario: pion id=%s introuvable, ignoré." % entry.id)
			continue
		var reason: String = RuleEngine.validate_scenario_pawn(entry)
		if reason != "":
			warnings.append("apply_scenario: pion id=%d — %s (appliqué quand même)." % [entry.id, reason])
		pawn.state = entry.state
		pawn.progress = entry.progress
		pawn.captor_id = entry.captor_id
	return warnings


# ----------------------------------------------------------------------------
# Internes
# ----------------------------------------------------------------------------

## Position monde d'un pion au yard : lue directement sur le Marker3D
## "Player<id>/Slot<n>" sous yards_root (pur décor de scène, librement
## déplaçable dans l'éditeur — pas une géométrie de chemin). Le slot est
## l'index local du pion dans son équipe (0..3).
func _yard_world_position(pawn: Dictionary) -> Vector3:
	var slot: int = pawn.id % BoardConfig.PAWNS_PER_PLAYER
	if yards_root == null:
		push_warning("BoardManager: yards_root non assigné, position de yard = ZERO.")
		return Vector3.ZERO
	var marker: Node3D = yards_root.get_node_or_null("Player%d/Slot%d" % [pawn.player, slot])
	if marker == null:
		push_warning("BoardManager: Marker3D de yard introuvable pour player=%d slot=%d." % [pawn.player, slot])
		return Vector3.ZERO
	return marker.position


## Position monde d'un pion CAPTURED : lue sur le Marker3D "Player<captor_id>/
## Slot<n>" sous capture_zones_root — la zone du joueur qui l'a capturé, PAS
## la sienne. Contrairement au yard, le slot n'est pas déductible de pawn.id
## (les victimes qui atterrissent dans une zone donnée varient selon la
## partie) : on compte les pions déjà CAPTURED par le même capteur.
func _capture_zone_world_position(pawn: Dictionary) -> Vector3:
	if capture_zones_root == null:
		push_warning("BoardManager: capture_zones_root non assigné, position de capture = ZERO.")
		return Vector3.ZERO
	var slot: int = _resolve_capture_zone_slot(pawn)
	var marker: Node3D = capture_zones_root.get_node_or_null("Player%d/Slot%d" % [pawn.captor_id, slot])
	if marker == null:
		push_warning("BoardManager: Marker3D de capture zone introuvable pour captor=%d slot=%d." % [pawn.captor_id, slot])
		return Vector3.ZERO
	return marker.position


## Compte les pions déjà CAPTURED avec le même captor_id (hors `pawn` lui-même)
## pour déterminer le prochain slot libre. 12 slots/zone garantissent qu'il ne
## déborde jamais (pire cas : les 12 pions adverses).
func _resolve_capture_zone_slot(pawn: Dictionary) -> int:
	var count: int = 0
	for p in all_pawns:
		if p.id == pawn.id:
			continue
		if p.state == PawnState.CAPTURED and p.captor_id == pawn.captor_id:
			count += 1
	return count
