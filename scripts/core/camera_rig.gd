class_name CameraRig
extends Node3D
## ============================================================================
## CameraRig — Caméra orbitale du plateau (GDD §11.5 : noeud CameraRig).
##
## SQUELETTE : caméra 3D orientée vers le centre, avec un léger zoom à la
## molette et rotation au clic droit. Les bornes évitent de sortir du plateau.
## Aucune logique de jeu : pure présentation.
## ============================================================================

@export var target: Node3D   # noeud visé (le BoardRoot, ou sa position)
@export var orbit_speed: float = 0.005
@export var min_distance: float = 6.0
@export var max_distance: float = 20.0
@export var default_distance: float = 14.0

var _yaw: float = 0.0
var _pitch: float = 0.9
var _distance: float = 14.0
var _camera: Camera3D


func _ready() -> void:
	_distance = default_distance
	_camera = Camera3D.new()
	_camera.current = true
	add_child(_camera)
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 0.6, min_distance, max_distance)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 0.6, min_distance, max_distance)
			_update_transform()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_yaw += orbit_speed * 60.0
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
