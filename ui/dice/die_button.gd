class_name DieButton
extends Button
## ============================================================================
## DieButton — Un dé cliquable du pool (voir handoff design : bottom bar,
## cluster de droite). Composant purement visuel + un signal `die_pressed` ;
## DicePoolView (parent logique) décide de l'état à appliquer à chaque
## reconstruction du pool via apply_state().
## ============================================================================

signal die_pressed(pool_id: int)

var pool_id: int = -1

@onready var _face: DieFace = %DieFace

var _rolling_tween: Tween


func _ready() -> void:
	pressed.connect(func() -> void: die_pressed.emit(pool_id))


## Associe ce bouton à une entrée du pool (TurnManager.dice_pool: {id, value})
## et affiche sa valeur.
func configure(p_pool_id: int, value: int) -> void:
	pool_id = p_pool_id
	_face.set_value(value)


## interactive : le tour permet de choisir un dé (WAITING_FOR_SELECTION).
## dead : aucun pion ne peut jouer cette valeur en ce moment (grisé, pas retiré).
## used : ce dé a déjà été joué ce tour (estompé, non cliquable, reste affiché).
## selected : ce dé est actuellement armé pour le prochain clic sur un pion.
func apply_state(interactive: bool, dead: bool, used: bool, selected: bool) -> void:
	disabled = used or dead or not interactive
	modulate.a = 0.45 if used else 1.0
	theme_type_variation = &"DieButtonSelected" if selected else &""


## Animation de lancer (rotation + léger zoom en boucle) — jouée pendant la
## fenêtre TurnState.ROLLING par le HUD parent. stop_roll_animation() remet
## le dé à son orientation/échelle normale une fois la valeur finale connue.
func play_roll_animation() -> void:
	stop_roll_animation()
	_rolling_tween = create_tween().set_loops()
	_rolling_tween.tween_property(_face, "rotation", TAU, 0.6).from(0.0)
	_rolling_tween.parallel().tween_property(_face, "scale", Vector2(1.15, 1.15), 0.15).from(Vector2.ONE)
	_rolling_tween.chain().tween_property(_face, "scale", Vector2.ONE, 0.45)


func stop_roll_animation() -> void:
	if _rolling_tween and _rolling_tween.is_valid():
		_rolling_tween.kill()
	_rolling_tween = null
	_face.rotation = 0.0
	_face.scale = Vector2.ONE
