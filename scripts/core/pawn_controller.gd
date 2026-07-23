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

## Pulsation des pions jouables (retour visuel de sélection, voir
## request_selection()) : multiplicateur d'échelle au pic, et durée d'une
## MOITIÉ de cycle (aller OU retour — cycle complet ≈ 2x cette valeur).
## Volontairement plus lent/doux que l'animation de lancer de dé
## (die_button.gd, qui doit lire comme "énergique") : ceci doit rester une
## invite discrète pendant que le joueur réfléchit à son choix.
@export var pulse_scale_factor: float = 1.12
@export var pulse_half_duration: float = 0.5

# --- Noeuds 3D des pions, indexés par pawn.id ---
# Chaque entrée est un StaticBody3D (mesh coloré + CollisionShape3D pour le
# raycast de sélection) — voir _make_pawn_node().
var _pawn_nodes: Dictionary = {}  # pawn.id -> StaticBody3D

## Enfant "mesh" (l'instance de pawn_scenes[...]) de chaque pion, indexé par
## pawn.id — cible EXCLUSIVE de la mise à l'échelle d'empilement (voir
## _apply_stack_layout()). On ne touche JAMAIS l'échelle du StaticBody3D
## lui-même (_pawn_nodes) car cela réduirait aussi son CollisionShape3D et
## dégraderait la précision du raycast de sélection.
var _pawn_mesh_nodes: Dictionary = {}  # pawn.id -> Node3D

# --- Sélection courante ---
var selected_pawn_id: int = -1

## Ids des pions actuellement cliquables (posé par request_selection(),
## consommé par _unhandled_input() via raycast).
var _legal_ids: Array = []

## Tween de pulsation en cours par pion offert (voir _start_pulse()) — vide
## hors offre de sélection.
var _pulse_tweens: Dictionary = {}  # pawn.id -> Tween

## Échelle du mesh au moment où sa pulsation a démarré, capturée pour
## restaurer l'échelle exacte à l'arrêt — JAMAIS Vector3.ONE en dur : un pion
## empilé (_apply_stack_layout()) peut déjà avoir une échelle réduite
## (voir BoardTuning.stack_scale_for()), que la pulsation ne doit pas écraser.
var _pulse_base_scales: Dictionary = {}  # pawn.id -> Vector3

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
	refresh_all_stacks()


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
		var mesh_root: Node3D = pawn_scenes[pawn.player].instantiate()
		body.add_child(mesh_root)
		# _pawn_mesh_nodes cible le vrai MeshInstance3D (ex. "Vert_013", voir
		# sm_ludo_pawn_blue.tscn), pas le noeud racine du .glb importé (un
		# Node3D nu) — utilisé par _apply_stack_layout() pour l'échelle
		# d'empilement des barrières (voir refresh_all_stacks()).
		var mesh_instance: MeshInstance3D = _find_mesh_instance(mesh_root)
		_pawn_mesh_nodes[pawn.id] = mesh_instance if mesh_instance != null else mesh_root

	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = pawn_collision_radius
	cylinder.height = pawn_collision_height
	shape.shape = cylinder
	shape.position = Vector3(0, pawn_collision_height * 0.5, 0)
	body.add_child(shape)

	return body


## Recherche en profondeur le premier MeshInstance3D sous `node` — c'est le
## seul noeud du .glb importé qui soit un GeometryInstance3D et accepte donc
## set_instance_shader_parameter() (voir _make_pawn_node()). Retourne null si
## aucun n'est trouvé (défensif ; ne devrait pas arriver avec les scènes de
## pion actuelles).
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found: MeshInstance3D = _find_mesh_instance(child)
		if found != null:
			return found
	return null


## Détruit tous les noeuds de pions (nouvelle partie).
func clear() -> void:
	_stop_all_pulses()  # garde défensive : reset en cours de partie
	for node in _pawn_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_pawn_nodes.clear()
	_pawn_mesh_nodes.clear()
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

	# Empilement (§6/H3, RING/HOME_LANE uniquement) : calcule le slot du pion
	# qui bouge dans SA nouvelle case (déjà mutée par apply_move() au moment
	# de cet appel), puis re-slotte immédiatement (snap) tous les AUTRES
	# pions affectés — ceux qu'il laisse derrière dans son ancienne case, et
	# ceux déjà présents dans sa case d'arrivée. Fait au moment où CE Tween
	# démarre (pas à la fin) pour que la case d'arrivée ne reste pas fausse
	# pendant toute la durée de l'animation.
	var mesh_node: Node3D = _pawn_mesh_nodes.get(pawn.id)
	if pawn.state == PawnState.RING or pawn.state == PawnState.HOME_LANE:
		var cell_pawns: Array = RuleEngine.get_stack_at(pawn, board_manager.all_pawns)
		var slot: Dictionary = compute_stack_slot(pawn.id, cell_pawns, board_tuning)
		final_target += slot.offset
		if mesh_node != null and is_instance_valid(mesh_node):
			mesh_node.scale = Vector3.ONE * slot.scale
	elif mesh_node != null and is_instance_valid(mesh_node):
		mesh_node.scale = Vector3.ONE
	refresh_all_stacks(pawn.id)

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

	var duration_mode: BoardTuning.MoveDurationMode = board_tuning.move_duration_mode if board_tuning else BoardTuning.MoveDurationMode.FIXED_TOTAL
	var total_duration: float = board_tuning.move_total_duration if board_tuning else 0.5
	var min_hop: float = board_tuning.move_min_hop_duration if board_tuning else 0.12
	var duration_per_cell: float = board_tuning.move_duration_per_cell if board_tuning else 0.35
	var segment_duration: float = compute_segment_duration(duration_mode, total_duration, min_hop, duration_per_cell, waypoints.size())

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


## Décalage local (XZ) et facteur d'échelle à appliquer à un pion identifié
## par `pawn_id`, au sein du groupe `cell_pawns` (tous les pions RING/HOME_LANE
## partageant sa case actuelle, y compris lui-même — voir RuleEngine.get_stack_at(),
## dont l'ordre est stable, trié par pawn.id croissant). Fonction pure,
## testable sans scène — voir tests/test_pawn_move_duration.gd.
## `tuning` peut être null (fallback : jamais d'offset/scale).
static func compute_stack_slot(pawn_id: int, cell_pawns: Array, tuning: BoardTuning) -> Dictionary:
	var count: int = cell_pawns.size()
	if count <= 1 or tuning == null:
		return {"offset": Vector3.ZERO, "scale": 1.0}
	var slot_index: int = 0
	for i in range(cell_pawns.size()):
		if cell_pawns[i].id == pawn_id:
			slot_index = i
			break
	return {
		"offset": tuning.stack_offset_for(count, slot_index),
		"scale": tuning.stack_scale_for(count),
	}


## Applique (SNAP instantané, sans Tween) le décalage + échelle d'empilement
## de tous les pions de `cell_pawns` — sauf `skip_pawn_id`, dont la position
## est pilotée par le Tween appelant (move_pawn_visual()) ; seule SON échelle
## est quand même snappée ici.
func _apply_stack_layout(cell_pawns: Array, skip_pawn_id: int = -1) -> void:
	for p in cell_pawns:
		var slot: Dictionary = compute_stack_slot(p.id, cell_pawns, board_tuning)
		var mesh_node: Node3D = _pawn_mesh_nodes.get(p.id)
		if mesh_node != null and is_instance_valid(mesh_node):
			mesh_node.scale = Vector3.ONE * slot.scale
		if p.id == skip_pawn_id:
			continue
		var node: Node3D = _pawn_nodes.get(p.id)
		if node != null and is_instance_valid(node):
			node.position = board_manager.cell_world_position(p) + slot.offset


## Recalcule l'empilement visuel de TOUTES les cases RING/HOME_LANE actuelles
## (barrières et empilements de couloir final, §6/H3). Un seul passage O(n²)
## dans le pire cas (16 pions, négligeable) — volontairement pas de tracking
## "case sale" précise : plus simple et robuste face aux mouvements combinés/
## captures qui touchent 2-3 cases à la fois.
## Réinitialise aussi l'échelle à 1.0 pour tout pion qui n'est PLUS RING/
## HOME_LANE (MAISON/CAPTURED/FINI), pour éviter une échelle rétrécie
## persistante depuis un ancien empilement.
func refresh_all_stacks(skip_pawn_id: int = -1) -> void:
	var visited_ids := {}
	for pawn in board_manager.all_pawns:
		if pawn.id in visited_ids:
			continue
		if pawn.state != PawnState.RING and pawn.state != PawnState.HOME_LANE:
			var mesh_node: Node3D = _pawn_mesh_nodes.get(pawn.id)
			if mesh_node != null and is_instance_valid(mesh_node):
				mesh_node.scale = Vector3.ONE
			continue
		var cell_pawns: Array = RuleEngine.get_stack_at(pawn, board_manager.all_pawns)
		for p in cell_pawns:
			visited_ids[p.id] = true
		_apply_stack_layout(cell_pawns, skip_pawn_id)


## Durée d'un segment individuel, selon le mode configuré dans BoardTuning —
## voir tests/test_pawn_move_duration.gd. Fonction pure, testable sans scène.
## - FIXED_TOTAL : le budget total (`total_duration`) est réparti sur toutes
##   les cases du trajet (`waypoint_count`), avec un plancher
##   (`min_hop_duration`) pour rester lisible sur les longs coups.
## - PROPORTIONAL : chaque case dure `duration_per_cell`, quel que soit le
##   nombre de cases (comportement d'origine du projet).
static func compute_segment_duration(
	mode: BoardTuning.MoveDurationMode,
	total_duration: float,
	min_hop_duration: float,
	duration_per_cell: float,
	waypoint_count: int
) -> float:
	if mode == BoardTuning.MoveDurationMode.PROPORTIONAL:
		return duration_per_cell
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


## Démarre la pulsation (échelle en aller-retour, en boucle) du pion
## `pawn_id` — retour visuel indiquant qu'il est cliquable. Anime TOUJOURS
## relativement à l'échelle actuelle du mesh (jamais Vector3.ONE en dur), qui
## peut déjà être réduite par l'empilement (_apply_stack_layout()).
func _start_pulse(pawn_id: int) -> void:
	var mesh_node: Node3D = _pawn_mesh_nodes.get(pawn_id)
	if mesh_node == null or not is_instance_valid(mesh_node):
		return
	var base_scale: Vector3 = mesh_node.scale
	_pulse_base_scales[pawn_id] = base_scale
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(mesh_node, "scale", base_scale * pulse_scale_factor, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(mesh_node, "scale", base_scale, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tweens[pawn_id] = tween


## Arrête la pulsation de `pawn_id` et restaure son échelle de repos exacte
## (celle capturée au démarrage, pas Vector3.ONE — voir _start_pulse()).
func _stop_pulse(pawn_id: int) -> void:
	var tween: Tween = _pulse_tweens.get(pawn_id)
	if tween != null and tween.is_valid():
		tween.kill()
	_pulse_tweens.erase(pawn_id)
	var mesh_node: Node3D = _pawn_mesh_nodes.get(pawn_id)
	if mesh_node != null and is_instance_valid(mesh_node):
		mesh_node.scale = _pulse_base_scales.get(pawn_id, Vector3.ONE)
	_pulse_base_scales.erase(pawn_id)


## Arrête toute pulsation en cours — appelé avant une nouvelle offre (le
## joueur peut ré-armer un autre dé sans avoir cliqué de pion, voir
## TurnManager.select_die()), à la sélection d'un pion, et au reset de partie.
func _stop_all_pulses() -> void:
	for pawn_id in _pulse_tweens.keys().duplicate():
		_stop_pulse(pawn_id)


## Rend un ensemble de pions cliquables par le joueur actif (sélection souris,
## §11.6). `legal_ids` est la liste des ids autorisés par
## RuleEngine.get_legal_target_pawns() ; un clic sur tout autre pion est ignoré.
func request_selection(player_id: int, legal_ids: Array) -> void:
	_stop_all_pulses()
	_legal_ids = legal_ids
	for pawn_id in legal_ids:
		_start_pulse(pawn_id)


## Marque un pion comme sélectionné et notifie le TurnManager.
func select_pawn(pawn_id: int) -> void:
	selected_pawn_id = pawn_id
	_legal_ids.clear()
	_stop_all_pulses()
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
