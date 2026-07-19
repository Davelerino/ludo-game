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

@export_group("Animation")
## Budget de durée pour TOUT le déplacement d'un pion (pas par case) — voir
## PawnController.compute_hop_duration().
@export var move_total_duration: float = 0.5
## Plancher de durée par saut, pour que les sauts restent lisibles même sur
## un long trajet (dé de 6) où le budget total serait sinon réparti trop finement.
@export var move_min_hop_duration: float = 0.12
## Hauteur (unités monde) de l'arc parabolique de chaque saut.
@export var hop_height: float = 0.18
@export var capture_duration: float = 0.5

@export_group("Joueurs")
## Couleurs représentatives des 4 joueurs (Rouge, Bleu, Vert, Jaune).
@export var player_colors: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW
]
@export var player_names: Array[String] = [
	"Rouge", "Bleu", "Vert", "Jaune"
]
