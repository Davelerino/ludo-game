class_name PlayerChip
extends PanelContainer
## ============================================================================
## PlayerChip — Une pastille du TopBar (voir handoff design : player chip
## row). Composant d'affichage : player_hud.gd pilote l'état actif/inactif et
## le score, ce chip ne lit lui-même que PlayerPalette pour son propre id.
## ============================================================================

const PALETTE: PlayerPalette = preload("res://resources/PlayerPalette.tres")

## Fixé par instance dans l'éditeur (PlayerChip0..3 dans player_hud.tscn).
@export var player_id: int = 0:
	set(value):
		player_id = value
		if is_node_ready():
			_refresh_static()

@onready var _avatar: Panel = %Avatar
@onready var _avatar_label: Label = %AvatarLabel
@onready var _name_label: Label = %NameLabel
@onready var _score_label: Label = %ScoreLabel

var _avatar_style: StyleBoxFlat


func _ready() -> void:
	_avatar_style = _avatar.get_theme_stylebox("panel").duplicate()
	_avatar.add_theme_stylebox_override("panel", _avatar_style)
	_refresh_static()


func _refresh_static() -> void:
	_name_label.text = PALETTE.player_name(player_id)
	_avatar_label.text = PALETTE.initials(player_id)
	_avatar_style.bg_color = PALETTE.main(player_id)


func set_active(active: bool) -> void:
	theme_type_variation = &"PlayerChipActive" if active else &""
	var target_y: float = -2.0 if active else 0.0
	create_tween().tween_property(self, "position:y", target_y, 0.2).set_trans(Tween.TRANS_SINE)


func set_score(finished: int, total: int) -> void:
	_score_label.text = "★ %d/%d" % [finished, total]
