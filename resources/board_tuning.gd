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
@export var move_duration: float = 0.35
@export var capture_duration: float = 0.5

@export_group("Joueurs")
## Couleurs représentatives des 4 joueurs (Rouge, Bleu, Vert, Jaune).
@export var player_colors: Array[Color] = [
	Color.RED, Color.BLUE, Color.GREEN, Color.YELLOW
]
@export var player_names: Array[String] = [
	"Rouge", "Bleu", "Vert", "Jaune"
]
