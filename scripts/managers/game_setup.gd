extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `GameSetup`) déclaré dans project.godot, même principe que ScenarioState.
## ============================================================================
## GameSetup — Boîte aux lettres entre main_menu.tscn et main.tscn.
##
## Transporte le nombre de joueurs choisi au menu principal. Le plateau a
## toujours 4 sièges physiques fixes (BoardConfig.PLAYER_COUNT, cf. §board
## geometry) — get_active_players() choisit lequel de ces 4 sièges participe
## réellement à la partie en cours :
##   2 joueurs -> Bleu + Rouge (diagonale, convention classique du Ludo)
##   3 joueurs -> Bleu + Vert + Rouge (on retire Jaune)
##   4 joueurs -> tous les sièges
## ============================================================================

var player_count: int = 4


func get_active_players() -> Array[int]:
	match player_count:
		2:
			return [0, 2]
		3:
			return [0, 1, 2]
		_:
			return [0, 1, 2, 3]
