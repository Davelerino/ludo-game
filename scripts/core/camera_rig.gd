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

var _yaw: float = 0.0
var _pitch: float = 0.9
var _distance: float = 14.0
var _camera: Camera3D
var _is_orbiting: bool = false


func _ready() -> void:
	_distance = default_distance
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_update_transform()


func _input(event: InputEvent) -> void:
	# --- Desktop : drag clic droit pour orbiter ---
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = event.pressed
			if _is_orbiting:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return

		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - zoom_step, min_distance, max_distance)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + zoom_step, min_distance, max_distance)
			_update_transform()

	if event is InputEventMouseMotion:
		if _is_orbiting:
			_yaw -= event.relative.x * sensitivity
			_pitch = clampf(_pitch + event.relative.y * sensitivity,
					-PI / 2 + 0.1, PI / 2 - 0.1)
			_update_transform()

	# --- Mobile : drag tactile pour orbiter ---
	elif event is InputEventScreenDrag:
		_yaw -= event.relative.x * sensitivity
		_pitch = clampf(_pitch + event.relative.y * sensitivity,
				-PI / 2 + 0.1, PI / 2 - 0.1)
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
