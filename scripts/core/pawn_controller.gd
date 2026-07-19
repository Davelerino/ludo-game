class_name PawnController
extends Node
## ============================================================================
## PawnController — Pont entre l'état logique d'un pion et sa représentation 3D.
##
## RESPONSABILITÉS (§11.1)
##   - Convertir un pion logique (Dictionary du RuleEngine) en position 3D sur
##     le plateau (GridMap), en interrogeant BoardManager pour la géométrie.
##   - Animer le déplacement visuel d'un pion (tween) sans toucher à la logique.
##   - Gérer la sélection du pion par le joueur (clic souris / input map,
##     GDD §11.6/15) et lever un signal de sélection vers le TurnManager.
##   - Publier pawn_moved / pawn_captured sur GameEvents (§11.2).
##
## DÉPENDANCES
##   - BoardManager (pour grid_map + cell_of(pawn) -> Vector3i).
##   - GameEvents (autoload).
##   - RuleEngine indirectement : il ne valide RIEN, il consomme l'état dicté
##     par le TurnManager/RuleEngine. Le PawnController ne mut jamais
##     pawn.state / pawn.progress (c'est le rôle de RuleEngine.apply_move()).
##
## ============================================================================

const PawnState := BoardConfig.PawnState

## Bit de collision dédié aux corps de pions (raycast de sélection souris,
## voir _raycast_pawn_id()). Ne partage sa couche avec rien d'autre pour que
## le raycast n'accroche jamais la GridMap ou le décor.
const PAWN_COLLISION_LAYER: int = 1 << 1
const RAY_LENGTH: float = 100.0

# --- Références à rattacher dans l'inspecteur / au _ready() ---
@export var board_manager: BoardManager
@export var board_tuning: BoardTuning

## Scènes de mesh par joueur (indexées par pawn.player), calquées sur la
## couleur déjà assignée à chaque yard dans board_root.tscn (Player0=Bleu,
## Player1=Vert, Player2=Rouge, Player3=Jaune).
@export var pawn_scenes: Array[PackedScene] = [
	preload("res://scenes/pawns/sm_ludo_pawn_blue.tscn"),
	preload("res://scenes/pawns/sm_ludo_pawn_green.tscn"),
	preload("res://scenes/pawns/sm_ludo_pawn_red.tscn"),
	preload("res://scenes/pawns/sm_ludo_pawn_yellow.tscn"),
]

## Dimensions du collider de sélection (cylindre invisible autour du mesh).
@export var pawn_collision_radius: float = 0.08
@export var pawn_collision_height: float = 0.23

# --- Noeuds 3D des pions, indexés par pawn.id ---
# Chaque entrée est un StaticBody3D (mesh coloré + CollisionShape3D pour le
# raycast de sélection) — voir _make_pawn_node().
var _pawn_nodes: Dictionary = {}  # pawn.id -> StaticBody3D

# --- Sélection courante ---
var selected_pawn_id: int = -1

## Ids des pions actuellement cliquables (posé par request_selection(),
## consommé par _unhandled_input() via raycast).
var _legal_ids: Array = []

## Émis quand le joueur sélectionne un de ses pions cliquable. Le TurnManager
## écoute ce signal pour déclencher apply_move() via le RuleEngine.
signal pawn_selected(pawn: Dictionary)


## Instancie un noeud 3D (mesh coloré + collider de sélection) par pion et le
## place sur son yard.
func setup(all_pawns: Array) -> void:
	clear()
	for pawn in all_pawns:
		var node := _make_pawn_node(pawn)
		node.position = board_manager.cell_world_position(pawn)
		_pawn_nodes[pawn.id] = node
		add_child(node)


## Fabrique le noeud visuel+cliquable d'un pion : un StaticBody3D portant le
## mesh coloré de son joueur (pawn_scenes) et un CollisionShape3D cylindrique
## utilisé uniquement pour le raycast de sélection (_raycast_pawn_id()).
func _make_pawn_node(pawn: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Pawn_%d" % pawn.id
	body.collision_layer = PAWN_COLLISION_LAYER
	body.collision_mask = 0
	body.set_meta("pawn_id", pawn.id)

	if pawn.player < pawn_scenes.size() and pawn_scenes[pawn.player] != null:
		body.add_child(pawn_scenes[pawn.player].instantiate())

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = pawn_collision_radius
	cylinder.height = pawn_collision_height
	shape.shape = cylinder
	shape.position = Vector3(0, pawn_collision_height * 0.5, 0)
	body.add_child(shape)

	return body


## Détruit tous les noeuds de pions (nouvelle partie).
func clear() -> void:
	for node in _pawn_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_pawn_nodes.clear()
	selected_pawn_id = -1
	_legal_ids.clear()


## Met à jour la position 3D d'un pion après un coup, avec animation optionnelle
## case par case. Ne change QUE la transform visuelle ; l'état logique a déjà
## été muté par RuleEngine.apply_move() au moment de l'appel — `old_state`/
## `old_progress` sont donc un SNAPSHOT pris par l'appelant (TurnManager) avant
## cette mutation, seul moyen de connaître le point de départ de l'animation.
##
## `capture_info`, si non vide, vaut {"captured_pawn": Dictionary, "old_state":
## int, "old_progress": int} — le snapshot PRÉ-mutation de la victime (elle
## aussi déjà mutée en CAPTURED au moment de l'appel). Dans ce cas, une
## deuxième animation (le pion capturé partant vers sa zone de capture)
## s'ajoute APRÈS l'animation principale, sur le MÊME Tween (séquentiel).
func move_pawn_visual(
	pawn: Dictionary,
	old_state: int,
	old_progress: int,
	dice_value: int,
	capture_info: Dictionary = {},
	animate: bool = true
) -> void:
	var node: Node3D = _pawn_nodes.get(pawn.id)
	if node == null or not is_instance_valid(node):
		return
	var final_target: Vector3 = board_manager.cell_world_position(pawn)

	if not animate:
		node.position = final_target
		if not capture_info.is_empty():
			var victim: Dictionary = capture_info.captured_pawn
			var victim_node: Node3D = _pawn_nodes.get(victim.id)
			if victim_node != null and is_instance_valid(victim_node):
				victim_node.position = board_manager.cell_world_position(victim)
		GameEvents.pawn_moved.emit(pawn, dice_value)
		return

	# (b)/(c) sortie de yard ou évasion de zone de capture : un seul saut, pas
	# de cases intermédiaires (aucune n'existe entre une zone décorative et
	# l'anneau/le yard).
	var is_single_hop: bool = (
		(old_state == PawnState.MAISON and pawn.state == PawnState.RING)
		or (old_state == PawnState.CAPTURED and pawn.state == PawnState.MAISON)
	)

	# (a) mouvement normal RING/HOME_LANE : un saut par case intermédiaire ;
	# is_single_hop : aucune case intermédiaire, juste `final_target`.
	var waypoints: Array[Vector3] = []
	if not is_single_hop:
		for step_progress in range(old_progress + 1, pawn.progress):
			waypoints.append(board_manager.world_position_for_progress(pawn.player, step_progress))
	waypoints.append(final_target)

	var total_duration: float = board_tuning.move_total_duration if board_tuning else 0.5
	var min_hop: float = board_tuning.move_min_hop_duration if board_tuning else 0.12
	var segment_duration: float = compute_segment_duration(total_duration, min_hop, waypoints.size())

	var tween: Tween = create_tween()
	for waypoint in waypoints:
		_append_move_segment(tween, node, waypoint, segment_duration)

	if not capture_info.is_empty():
		_append_capture_stage(tween, capture_info)

	# L'émission de pawn_moved se fait après TOUTE l'animation (y compris
	# l'étape de capture éventuelle, puisqu'elle est sur le même Tween).
	tween.finished.connect(func():
		GameEvents.pawn_moved.emit(pawn, dice_value)
	, CONNECT_ONE_SHOT)


## (d) Animation séparée de la capture : ajoutée en étape SÉQUENTIELLE (pas
## .parallel()) sur le tween du pion capturant, donc s'exécute forcément APRÈS
## que celui-ci ait fini de bouger.
func _append_capture_stage(tween: Tween, capture_info: Dictionary) -> void:
	var victim: Dictionary = capture_info.captured_pawn
	var victim_node: Node3D = _pawn_nodes.get(victim.id)
	if victim_node == null or not is_instance_valid(victim_node):
		return
	var cap_duration: float = board_tuning.capture_duration if board_tuning else 0.5
	var trans: Tween.TransitionType = board_tuning.move_transition if board_tuning else Tween.TRANS_SINE
	var ease_type: Tween.EaseType = board_tuning.move_ease if board_tuning else Tween.EASE_IN_OUT
	# victim.state est déjà CAPTURED (apply_move() l'a déjà mutée par
	# référence), donc cell_world_position(victim) résout sa nouvelle case de
	# zone de capture.
	var victim_target: Vector3 = board_manager.cell_world_position(victim)
	# Point de départ explicite (case ring d'avant capture, dérivée du snapshot
	# pré-mutation) plutôt que la transform courante du nœud — plus robuste.
	var victim_from: Vector3 = board_manager.world_position_for_progress(victim.player, capture_info.old_progress)
	tween.tween_property(victim_node, "position", victim_target, cap_duration)\
		.from(victim_from)\
		.set_trans(trans).set_ease(ease_type)


## Durée d'un segment individuel : le budget total (`total_duration`) est
## réparti sur toutes les cases du trajet (`waypoint_count`), avec un plancher
## (`min_hop_duration`) pour rester lisible sur les longs coups — voir
## tests/test_pawn_move_duration.gd. Fonction pure, testable sans scène.
static func compute_segment_duration(total_duration: float, min_hop_duration: float, waypoint_count: int) -> float:
	return max(min_hop_duration, total_duration / max(1, waypoint_count))


## Ajoute un segment de déplacement au tween (glissement plat, poursuit
## depuis la position courante du nœud — comportement standard de
## tween_property() quand les segments sont chaînés sur le même Tween). La
## courbe d'interpolation vient de BoardTuning.move_transition/move_ease
## (réglable dans l'inspecteur, voir board_tuning.gd).
func _append_move_segment(tween: Tween, node: Node3D, to_pos: Vector3, duration: float) -> void:
	var trans: Tween.TransitionType = board_tuning.move_transition if board_tuning else Tween.TRANS_SINE
	var ease_type: Tween.EaseType = board_tuning.move_ease if board_tuning else Tween.EASE_IN_OUT
	tween.tween_property(node, "position", to_pos, duration)\
		.set_trans(trans).set_ease(ease_type)


## Rend un ensemble de pions cliquables par le joueur actif (sélection souris,
## §11.6). `legal_ids` est la liste des ids autorisés par
## RuleEngine.get_legal_target_pawns() ; un clic sur tout autre pion est ignoré.
func request_selection(player_id: int, legal_ids: Array) -> void:
	_legal_ids = legal_ids


## Marque un pion comme sélectionné et notifie le TurnManager.
func select_pawn(pawn_id: int) -> void:
	selected_pawn_id = pawn_id
	_legal_ids.clear()
	var pawn: Dictionary = board_manager.get_pawn_by_id(pawn_id)
	if not pawn.is_empty():
		pawn_selected.emit(pawn)


# --- Entrée souris (sélection de pion, GDD §11.6/15) -------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pawn_select"):
		return
	if _legal_ids.is_empty():
		return
	var pawn_id: int = _raycast_pawn_id()
	if pawn_id == -1 or not (pawn_id in _legal_ids):
		return
	select_pawn(pawn_id)


## Lance un rayon caméra -> souris et renvoie l'id (méta "pawn_id") du premier
## StaticBody3D de pion touché, ou -1 si rien n'est touché (voir
## PAWN_COLLISION_LAYER, seule couche interrogée).
func _raycast_pawn_id() -> int:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return -1
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_pos)
	var to: Vector3 = from + camera.project_ray_normal(mouse_pos) * RAY_LENGTH
	var query := PhysicsRayQueryParameters3D.create(from, to, PAWN_COLLISION_LAYER)
	var hit: Dictionary = get_viewport().find_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1
	return hit.collider.get_meta("pawn_id", -1)
