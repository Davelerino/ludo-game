@tool
class_name BoardFlagTuning
extends Resource
## ============================================================================
## BoardFlagTuning — Valeurs de réglage ÉDITABLES de l'apparence des flags
## (icônes flottantes ancrées en 3D, voir board_flag.gd / board_flag_manager.gd).
## Même esprit que BoardTuning (resources/board_tuning.gd) : un seul .tres
## partagé, réglable dans l'inspecteur sans toucher au code.
## ============================================================================

@export_group("Texte")
@export var font_size: int = 72
@export var outline_size: int = 10
@export var outline_color: Color = Color.BLACK
## Opacité de repos du flag (avant pulsation/clignotement) — 1.0 = opaque.
@export_range(0.0, 1.0) var opacity: float = 1.0

@export_group("Position")
## Décalage vertical au-dessus de la case/du yard ancré.
@export var height_offset: float = 0.3

@export_group("Orientation")
## Si vrai (défaut), le flag pivote autour de l'axe Y pour toujours faire
## face à la caméra horizontalement (Label3D.BILLBOARD_FIXED_Y — reste
## "debout", ne suit pas l'inclinaison de la caméra). Si faux, son
## orientation reste fixe. Dans les deux cas, la lévitation idle
## (levitate_amplitude/levitate_half_duration ci-dessous) reste active.
@export var billboard_enabled: bool = true

@export_group("Animation")
## Opacité minimale atteinte en pulsation continue ou en clignotement.
@export var low_alpha: float = 0.35
## Durée d'une MOITIÉ de cycle de la pulsation continue (mode BoardFlag.Mode.PULSE).
@export var pulse_half_duration: float = 0.6
## Durée d'une MOITIÉ de cycle du burst de clignotement (BoardFlag.play_blink_burst()).
@export var blink_half_duration: float = 0.12
## Amplitude verticale (mètres) de la lévitation idle — toujours active,
## billboard activé ou non (voir BoardFlag._start_levitate()).
@export var levitate_amplitude: float = 0.05
## Durée d'une MOITIÉ de cycle de la lévitation (montée OU descente).
@export var levitate_half_duration: float = 1.0
