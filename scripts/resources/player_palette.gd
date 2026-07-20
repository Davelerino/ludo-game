@tool
class_name PlayerPalette
extends Resource
## ============================================================================
## PlayerPalette — Source unique de vérité pour les noms et couleurs des 4
## joueurs (Bleu=0, Vert=1, Rouge=2, Jaune=3, cf. PawnController.pawn_scenes).
##
## Remplace les copies dupliquées (et parfois incohérentes) qui existaient
## dans ui/hud/hud.gd, ui/scenario/scenario_setup.gd et ui/menu/main_menu.gd.
##
## main_colors reprend les couleurs RÉELLES des matériaux de pions
## (resources/{Blue,Green,Red,Yellow}_mat.tres) pour que les chips du HUD
## correspondent exactement aux pions affichés en jeu. dark_colors/
## light_colors sont les nuances du handoff design (utilisées pour les
## anneaux actifs, ombres, textes colorés, dégradés d'avatar).
## ============================================================================

@export var player_names: Array[String] = ["Bleu", "Vert", "Rouge", "Jaune"]

@export var main_colors: Array[Color] = [
	Color(0, 0.5294118, 0.90588236),    # Bleu
	Color(0, 0.6509804, 0.023529412),   # Vert
	Color(0.90588236, 0.015686275, 0),  # Rouge
	Color(0.90588236, 0.76862746, 0),   # Jaune
]

@export var dark_colors: Array[Color] = [
	Color("#254F9E"),  # Bleu
	Color("#256B2E"),  # Vert
	Color("#AF2E24"),  # Rouge
	Color("#B9791A"),  # Jaune
]

@export var light_colors: Array[Color] = [
	Color("#9CC0FF"),  # Bleu
	Color("#8DE39A"),  # Vert
	Color("#FF8A80"),  # Rouge
	Color("#FFDE9C"),  # Jaune
]


func player_name(player_id: int) -> String:
	return player_names[player_id]


func main(player_id: int) -> Color:
	return main_colors[player_id]


func dark(player_id: int) -> Color:
	return dark_colors[player_id]


func light(player_id: int) -> Color:
	return light_colors[player_id]


## Initiales pour l'avatar du chip (2 lettres max, ex. "Rouge" -> "RO").
func initials(player_id: int) -> String:
	var n: String = player_name(player_id)
	return n.substr(0, 2).to_upper()
