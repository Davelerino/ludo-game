class_name CameraRig
extends Node3D
## ============================================================================
## CameraRig — Caméra orbitale du plateau (GDD §11.5 : noeud CameraRig).
##
## Contrôles :
##   Desktop : maintenir clic droit + déplacer la souris = orbite (yaw/pitch).
##             molette = zoom.
##   Mobile  : drag tactile = orbite ; pinch-to-zoom (futur).
##
## Les bornes de pitch évitent le retournement caméra. Aucune logique de jeu :
## pure présentation.
## ============================================================================

@export var target: Node3D   ## Noeud visé (le BoardRoot, ou sa position)
@export var sensitivity: float = 0.005  ## Vitesse de rotation (rad/pixel)
@export var zoom_step: float = 0.8      ## Pas de zoom par cran de molette
@export var min_distance: float = 6.0
@export var max_distance: float = 20.0
@export var default_distance: float = 14.0

## Conteneur "Yards" de board_root.tscn (Yards/Player0..3/Slot0..3, Marker3D)
## — sert uniquement à dériver _player_yaw au démarrage (voir _ready()) ;
## aucune dépendance de gameplay, main.gd n'a pas besoin de connaître CameraRig.
@export var yards_root: Node3D
## Vitesse du recentrage doux vers le joueur actif (voir _on_turn_ended()).
@export var focus_lerp_speed: float = 2.5

var _yaw: float = 0.0
var _pitch: float = 0.9
var _distance: float = 14.0
var _camera: Camera3D
var _is_orbiting: bool = false

## Yaw "vers" chaque joueur (index = player_id), dérivé de la géométrie réelle
## des yards plutôt que codé en dur — voir _compute_player_yaw().
var _player_yaw: Array[float] = []
var _target_yaw: float = 0.0
var _focusing: bool = false


func _ready() -> void:
	_distance = default_distance
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_update_transform()
	_player_yaw = _compute_player_yaw()
	GameEvents.turn_ended.connect(_on_turn_ended)


## Calcule, pour chaque joueur, l'angle (autour de `target`) de son yard —
## moyenne des 4 Marker3D "SlotN" sous Yards/Player<n>, projetée sur le plan
## XZ. Dérivé de la scène plutôt que codé en dur : reste correct si le
## plateau est retouché plus tard. Retourne [] si yards_root n'est pas assigné.
func _compute_player_yaw() -> Array[float]:
	var yaws: Array[float] = []
	if not is_instance_valid(yards_root) or not is_instance_valid(target):
		return yaws
	for player_id in range(BoardConfig.PLAYER_COUNT):
		var player_node: Node3D = yards_root.get_node_or_null("Player%d" % player_id)
		if player_node == null:
			yaws.append(0.0)
			continue
		var sum := Vector3.ZERO
		var count := 0
		for child in player_node.get_children():
			if child is Marker3D:
				sum += child.position
				count += 1
		var center: Vector3 = (sum / count) if count > 0 else Vector3.ZERO
		var offset: Vector3 = center - target.position
		yaws.append(atan2(offset.x, offset.z))
	return yaws


## Amorce un recentrage doux (voir _process()) vers le yard du nouveau joueur
## actif — jamais pendant un déplacement de pion (seul le changement de TOUR
## déclenche ceci), pour éviter une caméra qui suivrait chaque pas d'un pion.
## Désactivable dans le menu Paramètres (voir ui/settings/settings_menu.gd).
func _on_turn_ended(_previous_player: int, next_player: int) -> void:
	if not SettingsManager.camera_auto_focus_enabled:
		return
	if next_player < 0 or next_player >= _player_yaw.size():
		return
	_target_yaw = _player_yaw[next_player]
	_focusing = true


func _process(delta: float) -> void:
	if not _focusing:
		return
	_yaw = lerp_angle(_yaw, _target_yaw, delta * focus_lerp_speed)
	_update_transform()
	if abs(wrapf(_yaw - _target_yaw, -PI, PI)) < 0.01:
		_focusing = false


func _unhandled_input(event: InputEvent) -> void:
	# --- Desktop : drag clic droit pour orbiter ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = event.pressed
			if _is_orbiting:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_focusing = false  # le contrôle manuel a toujours priorité sur le recentrage auto
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# _unhandled_input() suffit en théorie (les Control consomment déjà
			# la molette avant qu'elle n'arrive ici), mais un ScrollContainer
			# sans contenu à faire défiler ne la consomme pas toujours — on
			# vérifie donc aussi explicitement qu'aucun élément d'UI n'est
			# survolé, pour ne pas zoomer "à travers" le HUD.
			if get_viewport().gui_get_hovered_control() != null:
				return
			_focusing = false  # idem : un zoom manuel interrompt aussi le recentrage auto
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - zoom_step, min_distance, max_distance)
			else:
				_distance = clampf(_distance + zoom_step, min_distance, max_distance)
			_update_transform()

	if event is InputEventMouseMotion:
		if _is_orbiting:
			_yaw -= event.relative.x * sensitivity
			_pitch = clampf(_pitch + event.relative.y * sensitivity,
					0.0, PI / 2 - 0.1)
			_update_transform()

	# --- Mobile : drag tactile pour orbiter ---
	elif event is InputEventScreenDrag:
		_focusing = false  # idem : un drag tactile interrompt aussi le recentrage auto
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch + event.relative.y * sensitivity,
				0.0, PI / 2 - 0.1)
		_update_transform()


func _update_transform() -> void:
	var center: Vector3 = target.position if is_instance_valid(target) else Vector3.ZERO
	var offset := Vector3(
		sin(_yaw) * cos(_pitch) * _distance,
		sin(_pitch) * _distance,
		cos(_yaw) * cos(_pitch) * _distance
	)
	_camera.position = center + offset
	_camera.look_at(center, Vector3.UP)
