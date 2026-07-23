class_name BoardFlagManager
extends Node
## ============================================================================
## BoardFlagManager — Propriétaire du cycle de vie de tous les BoardFlag
## actifs (icônes flottantes ancrées en 3D, voir board_flag.gd). Deux
## familles aujourd'hui, namespacées par préfixe de clé :
##   - "barrier_<ring_index>" : bouclier au-dessus d'une case en barrière.
##   - "podium_<player_id>"   : badge de classement au-dessus d'un yard.
## Toute nouvelle famille future n'a qu'à choisir son propre préfixe et
## appeler show_flag()/hide_flag() — aucune nouvelle plomberie nécessaire.
## ============================================================================

const BoardFlagScene: PackedScene = preload("res://scenes/board/board_flag.tscn")

## Raisons de rejet de RuleEngine.try_move() dues à une barrière — voir
## rule_engine.gd (_empty_result().blocking_ring_index). Les autres raisons
## (ex. "needs_six_to_enter") n'ont pas de case à faire clignoter.
const _BARRIER_REASONS := [
	"start_tile_blocked_by_enemy_barrier",
	"path_blocked_by_barrier",
	"landing_blocked_enemy_barrier",
]

const _MEDAL_BY_PLACE := {1: "🥇", 2: "🥈", 3: "🥉"}

## Apparence des flags (police, contour, hauteur, animation) — voir
## resources/board_flag_tuning.gd. Assigné par main.gd, comme
## PawnController.board_tuning. Peut rester null (fallbacks internes).
@export var tuning: BoardFlagTuning

var board_manager: BoardManager
var flags_root: Node3D

var _active_flags: Dictionary = {}   # key: String -> BoardFlag
## Snapshot du dernier _resync (ring_index -> Vector3), pour diffing.
var _barrier_cells: Dictionary = {}


func setup(p_board_manager: BoardManager, p_flags_root: Node3D) -> void:
	board_manager = p_board_manager
	flags_root = p_flags_root
	GameEvents.barrier_formed.connect(_on_barrier_formed)
	GameEvents.pawn_moved.connect(_on_pawn_moved)
	GameEvents.move_blocked.connect(_on_move_blocked)
	GameEvents.player_finished_ranked.connect(_on_player_finished_ranked)
	refresh_barrier_flags()


# ----------------------------------------------------------------------------
# API générique
# ----------------------------------------------------------------------------

## Affiche (ou repositionne/retextualise si déjà affiché) le flag `key` à
## `world_pos` (le décalage de flottaison est appliqué ici, pas par
## l'appelant). Retourne l'instance pour les cas qui veulent agir dessus
## juste après (ex. play_blink_burst()).
func show_flag(key: String, world_pos: Vector3, text: String, mode: BoardFlag.Mode = BoardFlag.Mode.STATIC) -> BoardFlag:
	var flag: BoardFlag = _active_flags.get(key)
	if flag == null or not is_instance_valid(flag):
		flag = BoardFlagScene.instantiate()
		flags_root.add_child(flag)
		flag.apply_tuning(tuning)
		_active_flags[key] = flag
	var height_offset: float = tuning.height_offset if tuning != null else 0.3
	flag.position = world_pos + Vector3(0, height_offset, 0)
	flag.set_text(text)
	flag.set_mode(mode)
	return flag


func hide_flag(key: String) -> void:
	var flag: BoardFlag = _active_flags.get(key)
	if flag != null and is_instance_valid(flag):
		flag.queue_free()
	_active_flags.erase(key)


# ----------------------------------------------------------------------------
# Bouclier de barrière
# ----------------------------------------------------------------------------

func _on_barrier_formed(pawn: Dictionary, ring_index: int) -> void:
	var pos: Vector3 = board_manager.cell_world_position(pawn)
	show_flag("barrier_%d" % ring_index, pos, "🛡")
	_barrier_cells[ring_index] = pos


func _on_pawn_moved(_pawn: Dictionary, _dice_value: int) -> void:
	refresh_barrier_flags()


## Recalcule l'ensemble des cases d'anneau actuellement en barrière (dérivé
## de l'état des pions, PAS stocké — voir RuleEngine.is_barrier_at()) et
## synchronise les flags affichés (apparition + disparition). Coût négligeable
## (≤16 pions), même philosophie que PawnController.refresh_all_stacks().
## Public : appelée aussi par main.gd après le chargement d'un scénario, qui
## ne déclenche aucun signal GameEvents.
func refresh_barrier_flags() -> void:
	if board_manager == null:
		return
	var current: Dictionary = {}   # ring_index -> Vector3
	for pawn in board_manager.all_pawns:
		if pawn.state != BoardConfig.PawnState.RING:
			continue
		var ring_index: int = RuleEngine.get_ring_index(pawn)
		if current.has(ring_index):
			continue
		if RuleEngine.is_barrier_at(ring_index, board_manager.all_pawns):
			current[ring_index] = board_manager.cell_world_position(pawn)

	for ring_index in current.keys():
		if not _barrier_cells.has(ring_index):
			show_flag("barrier_%d" % ring_index, current[ring_index], "🛡")
	for ring_index in _barrier_cells.keys():
		if not current.has(ring_index):
			hide_flag("barrier_%d" % ring_index)
	_barrier_cells = current


## Tentative de coup rejetée à cause d'une barrière (voir
## PawnController.pawn_click_rejected -> TurnManager -> GameEvents.move_blocked) :
## fait clignoter le bouclier déjà affiché sur la case en cause. Si aucun
## bouclier n'y est encore affiché (ex. barrière issue d'un scénario chargé
## juste avant refresh_barrier_flags()), no-op — cas limite acceptable.
func _on_move_blocked(_pawn: Dictionary, reason: String, ring_index: int) -> void:
	if ring_index == -1 or reason not in _BARRIER_REASONS:
		return
	var flag: BoardFlag = _active_flags.get("barrier_%d" % ring_index)
	if flag != null and is_instance_valid(flag):
		flag.play_blink_burst()


# ----------------------------------------------------------------------------
# Badge de podium
# ----------------------------------------------------------------------------

## Affiché dans les DEUX modes de fin de partie (GameSetup.WinMode) : le
## joueur a bien fini ses 4 pions dans les deux cas, que la partie continue
## (FULL_RANKING) ou s'arrête aussitôt (FIRST_WINNER) — voir
## GameEvents.player_finished_ranked. Jamais masqué : un reset complet passe
## par reload_current_scene() (VictoryScreen._on_replay_pressed()), qui
## détruit tout l'arbre de scène y compris ce manager.
func _on_player_finished_ranked(player_id: int, place: int) -> void:
	var anchor: Vector3 = _yard_anchor(player_id)
	show_flag("podium_%d" % player_id, anchor, _medal_text(place))


func _medal_text(place: int) -> String:
	return _MEDAL_BY_PLACE.get(place, "%dème" % place)


## Moyenne des 4 Marker3D Slot0..Slot3 du yard du joueur — le nœud
## "Player<id>" lui-même a une transform identité (voir board_root.tscn),
## donc utiliser sa seule position placerait le badge à l'origine du plateau.
func _yard_anchor(player_id: int) -> Vector3:
	var player_node: Node3D = board_manager.yards_root.get_node_or_null("Player%d" % player_id)
	if player_node == null:
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var count := 0
	for slot in player_node.get_children():
		if slot is Node3D:
			sum += slot.position
			count += 1
	if count == 0:
		return Vector3.ZERO
	return sum / count
