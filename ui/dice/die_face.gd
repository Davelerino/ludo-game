class_name DieFace
extends GridContainer
## ============================================================================
## DieFace — Grille 3x3 de pips (points) affichant la valeur d'un dé (1-6),
## sans image : 9 Panel (%Pip0..%Pip8) dont la visibilité est basculée selon
## la disposition standard d'un dé à six faces (voir handoff design).
## ============================================================================

const PIP_LAYOUTS := {
	1: [4],
	2: [2, 6],
	3: [0, 4, 8],
	4: [0, 2, 6, 8],
	5: [0, 2, 4, 6, 8],
	6: [0, 2, 3, 5, 6, 8],
}

@onready var _pip0: Panel = %Pip0
@onready var _pip1: Panel = %Pip1
@onready var _pip2: Panel = %Pip2
@onready var _pip3: Panel = %Pip3
@onready var _pip4: Panel = %Pip4
@onready var _pip5: Panel = %Pip5
@onready var _pip6: Panel = %Pip6
@onready var _pip7: Panel = %Pip7
@onready var _pip8: Panel = %Pip8

var _pips: Array[Panel] = []


func _ready() -> void:
	_pips = [_pip0, _pip1, _pip2, _pip3, _pip4, _pip5, _pip6, _pip7, _pip8]
	set_value(1)


## value : 1..6. Toute autre valeur (ex. 0 pendant l'animation de lancer)
## masque tous les pips.
func set_value(value: int) -> void:
	var active: Array = PIP_LAYOUTS.get(value, [])
	for i in range(_pips.size()):
		_pips[i].visible = i in active
