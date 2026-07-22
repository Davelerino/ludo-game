@tool
class_name BoardTuning
extends Resource
## ============================================================================
## BoardTuning — Valeurs de réglage ÉDITABLES du plateau (complément de
## BoardConfig, GDD §11.4).
##
## BoardConfig (board_config.gd) reste un ensemble de CONSTANTIUMES pures
## (réutilisé tel quel, non modifié). BoardTuning, lui, regroupe les paramètres
## de mise en scène / feeling qu'on veut pouvoir ajuster dans l'inspecteur
## SANS toucher aux règles : tailles de cellule, rayons, hauteurs, durées
## d'animation, couleurs des joueurs... On instancie un .tres par défaut.
## ============================================================================

@export_group("Géométrie")
@export var cell_size: float = 1.0
@export var ring_radius: float = 8.0
@export var yard_elevation: float = 0.2
@export var pawn_lift_height: float = 0.5

## Mode de répartition de la durée d'un déplacement sur ses cases (réglable
## dans l'inspecteur — les deux modes coexistent le temps du bêta-test, un
## seul sera retenu ensuite) :
## - FIXED_TOTAL : budget total quasi-fixe (`move_total_duration`), réparti
##   sur les cases avec un plancher (`move_min_hop_duration`), quel que soit
##   le nombre de cases franchies (un dé de 6 ne dure pas 6x plus qu'un dé de 1).
## - PROPORTIONAL : chaque case ajoute une durée fixe (`move_duration_per_cell`)
##   au total — comportement d'origine du projet.
enum MoveDurationMode { FIXED_TOTAL, PROPORTIONAL }

@export_group("Animation")
@export var move_duration_mode: MoveDurationMode = MoveDurationMode.FIXED_TOTAL
## Budget de durée pour TOUT le déplacement d'un pion — mode FIXED_TOTAL
## uniquement. Voir PawnController.compute_segment_duration().
@export var move_total_duration: float = 0.5
## Plancher de durée par segment, pour que chaque case franchie reste lisible
## même sur un long trajet (dé de 6) où le budget total serait sinon réparti
## trop finement — mode FIXED_TOTAL uniquement.
@export var move_min_hop_duration: float = 0.12
## Durée fixe par case franchie — mode PROPORTIONAL uniquement.
@export var move_duration_per_cell: float = 0.35
## Courbe d'interpolation du glissement (case par case) — modifiable dans
## l'inspecteur pour essayer différents ressentis : BACK = petit "punch" à
## l'arrivée, EXPO/CUBIC = démarrage vif, ELASTIC = rebond élastique,
## BOUNCE = rebonds successifs...
@export var move_transition: Tween.TransitionType = Tween.TRANS_BACK
@export var move_ease: Tween.EaseType = Tween.EASE_OUT
@export var capture_duration: float = 0.5

@export_group("Joueurs")
## Couleurs représentatives des 4 joueurs (Rouge, Bleu, Vert, Jaune).
@export var player_colors: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW
]
@export var player_names: Array[String] = [
	"Rouge", "Bleu", "Vert", "Jaune"
]

@export_group("Empilement (barrières RING/HOME_LANE)")
## Décalages locaux (plan XZ, Y toujours 0) appliqués aux pions quand une case
## RING/HOME_LANE en contient exactement N (N=1 n'a pas d'entrée : toujours
## Vector3.ZERO, voir PawnController.compute_stack_slot()). Index = position
## dans le groupe trié par pawn.id croissant (RuleEngine.get_stack_at()).
@export var stack_offsets_2: Array[Vector3] = [Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0)]
@export var stack_scale_2: float = 0.55

@export var stack_offsets_3: Array[Vector3] = [Vector3(0, 0, 0.055), Vector3(-0.0476, 0, -0.0275), Vector3(0.0476, 0, -0.0275)]
@export var stack_scale_3: float = 0.5

@export var stack_offsets_4: Array[Vector3] = [
	Vector3(-0.055, 0, -0.055), Vector3(0.055, 0, -0.055),
	Vector3(-0.055, 0, 0.055), Vector3(0.055, 0, 0.055),
]
@export var stack_scale_4: float = 0.45

## Lookup utilitaire — voir PawnController.compute_stack_slot(). `count` est
## la taille du groupe (2..PAWNS_PER_PLAYER), `slot_index` la position dans
## le groupe trié. Retourne Vector3.ZERO hors plage (défensif).
func stack_offset_for(count: int, slot_index: int) -> Vector3:
	var table: Array[Vector3] = []
	match count:
		2: table = stack_offsets_2
		3: table = stack_offsets_3
		4: table = stack_offsets_4
		_: return Vector3.ZERO
	return table[slot_index] if slot_index >= 0 and slot_index < table.size() else Vector3.ZERO

## Lookup utilitaire de l'échelle — voir stack_offset_for().
func stack_scale_for(count: int) -> float:
	match count:
		2: return stack_scale_2
		3: return stack_scale_3
		4: return stack_scale_4
		_: return 1.0
