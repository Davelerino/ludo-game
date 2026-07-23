class_name BoardFlag
extends Node3D
## ============================================================================
## BoardFlag — Icône flottante ancrée en 3D au-dessus du plateau (bouclier de
## barrière, badge de podium, ...). Widget générique et sans état de jeu : le
## texte et le mode d'affichage sont pilotés par BoardFlagManager, qui
## possède le cycle de vie (création/positionnement/destruction) de chaque
## instance — voir board_flag_manager.gd.
##
## Anime modulate:a du Label3D (plutôt que scale, comme la pulsation des
## pions jouables dans PawnController) : un texte reste plus lisible sous une
## variation d'opacité que sous une variation d'échelle.
## ============================================================================

enum Mode { STATIC, PULSE }

## Opacité minimale atteinte en pulsation continue ou en clignotement.
@export var low_alpha: float = 0.35
## Durée d'une MOITIÉ de cycle de la pulsation continue (mode PULSE).
@export var pulse_half_duration: float = 0.6
## Durée d'une MOITIÉ de cycle du burst de clignotement (play_blink_burst()).
@export var blink_half_duration: float = 0.12
## Amplitude verticale (mètres) de la lévitation idle (billboard désactivé).
@export var levitate_amplitude: float = 0.05
## Durée d'une MOITIÉ de cycle de la lévitation (montée OU descente).
@export var levitate_half_duration: float = 1.0

@onready var _label: Label3D = $Label3D

var _idle_tween: Tween
var _blink_tween: Tween
var _levitate_tween: Tween
## Opacité de repos du label, capturée une fois — jamais 1.0 en dur, au cas
## où un futur appelant configurerait une opacité de base différente.
var _base_alpha: float = 1.0
## Position locale de repos du label (pivot de la lévitation), capturée une
## fois — jamais Vector3.ZERO en dur, au cas où le label serait décalé dans
## la scène.
var _label_base_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_base_alpha = _label.modulate.a
	_label_base_position = _label.position


## Applique un BoardFlagTuning (police, contour, orientation, animation) —
## voir resources/board_flag_tuning.gd. Appelé par BoardFlagManager juste
## après l'instanciation (donc APRÈS _ready(), _label est déjà résolu).
## `t == null` est un no-op défensif : les valeurs par défaut du script/de la
## scène restent alors actives.
func apply_tuning(t: BoardFlagTuning) -> void:
	if t == null:
		return
	_label.font_size = t.font_size
	_label.outline_size = t.outline_size
	_label.outline_modulate = t.outline_color
	# FIXED_Y (pas ENABLED) : le flag ne pivote qu'autour de l'axe vertical
	# pour faire face à la caméra, sans suivre son inclinaison — reste
	# toujours "debout", lisible, même quand la caméra regarde de haut/bas.
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y if t.billboard_enabled else BaseMaterial3D.BILLBOARD_DISABLED
	# Opacité de repos : appliquée directement (pas seulement capturée), et
	# _base_alpha mis à jour en conséquence — sinon play_blink_burst()/
	# _stop_idle() reviendraient à l'opacité par défaut de la scène (1.0) au
	# lieu de celle configurée ici.
	_label.modulate.a = t.opacity
	_base_alpha = t.opacity
	low_alpha = t.low_alpha
	pulse_half_duration = t.pulse_half_duration
	blink_half_duration = t.blink_half_duration
	levitate_amplitude = t.levitate_amplitude
	levitate_half_duration = t.levitate_half_duration
	# La lévitation idle est toujours active, billboard activé ou non.
	_start_levitate()


func set_text(text: String) -> void:
	_label.text = text


func set_mode(mode: Mode) -> void:
	_stop_idle()
	if mode == Mode.PULSE:
		_start_idle_pulse()


## Quelques cycles rapides d'opacité pour attirer l'attention sur un flag déjà
## affiché (ex. clic bloqué par une barrière), puis retour à l'opacité de repos.
func play_blink_burst(cycles: int = 3) -> void:
	if _blink_tween != null and _blink_tween.is_valid():
		_blink_tween.kill()
	_label.modulate.a = _base_alpha
	_blink_tween = create_tween()
	for i in range(cycles):
		_blink_tween.tween_property(_label, "modulate:a", low_alpha, blink_half_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_blink_tween.tween_property(_label, "modulate:a", _base_alpha, blink_half_duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _start_idle_pulse() -> void:
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(_label, "modulate:a", low_alpha, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_idle_tween.tween_property(_label, "modulate:a", _base_alpha, pulse_half_duration)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _stop_idle() -> void:
	if _idle_tween != null and _idle_tween.is_valid():
		_idle_tween.kill()
	_idle_tween = null
	_label.modulate.a = _base_alpha


## Fait légèrement flotter le label de haut en bas (position LOCALE, donc
## sans conflit avec BoardFlagManager.show_flag() qui pilote uniquement la
## position du nœud racine — voir _label_base_position). Actif dans tous les
## cas (billboard activé ou non) — voir BoardFlagTuning.levitate_amplitude.
func _start_levitate() -> void:
	if _levitate_tween != null and _levitate_tween.is_valid():
		return  # déjà en cours, pas de redémarrage superflu.
	_levitate_tween = create_tween().set_loops()
	_levitate_tween.tween_property(
		_label, "position:y", _label_base_position.y + levitate_amplitude, levitate_half_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_levitate_tween.tween_property(
		_label, "position:y", _label_base_position.y, levitate_half_duration
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
