class_name MainMenu
extends Control
## ============================================================================
## MainMenu — Écran-titre, point d'entrée du jeu (avant scenes/main.tscn).
##
## Construit comme une scène concrète (scenes/ui/main_menu.tscn), sur le
## modèle de player_hud.tscn : nœuds réels + thème appliqué au nœud racine,
## ce script se contente de câbler les signaux — voir GameSetup pour le
## nombre de joueurs choisi, transporté vers main.tscn.
##
## Trois actions : choisir le nombre de joueurs, lancer une partie (change de
## scène vers le plateau), configurer un scénario de test, ou quitter.
## ============================================================================

const GAME_SCENE := "res://scenes/main.tscn"
const SCENARIO_SCENE := "res://scenes/scenario/scenario_setup.tscn"
const LOAD_GAME_SCENE := "res://scenes/ui/load/load_game_screen.tscn"

@onready var _count2_button: Button = %Count2Button
@onready var _count3_button: Button = %Count3Button
@onready var _count4_button: Button = %Count4Button
@onready var _swatches: Array[PlayerChip] = [%Swatch0, %Swatch1, %Swatch2, %Swatch3]
@onready var _first_winner_button: Button = %FirstWinnerButton
@onready var _full_ranking_button: Button = %FullRankingButton
@onready var _play_button: Button = %PlayButton
@onready var _load_game_button: Button = %LoadGameButton
@onready var _scenario_button: Button = %ScenarioButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_count2_button.pressed.connect(_on_count_selected.bind(2))
	_count3_button.pressed.connect(_on_count_selected.bind(3))
	_count4_button.pressed.connect(_on_count_selected.bind(4))
	_first_winner_button.pressed.connect(_on_win_mode_selected.bind(GameSetup.WinMode.FIRST_WINNER))
	_full_ranking_button.pressed.connect(_on_win_mode_selected.bind(GameSetup.WinMode.FULL_RANKING))
	_play_button.pressed.connect(_on_play_pressed)
	_load_game_button.pressed.connect(_on_load_game_pressed)
	_scenario_button.pressed.connect(_on_scenario_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_on_count_selected(GameSetup.player_count)
	_on_win_mode_selected(GameSetup.win_mode)
	_load_game_button.disabled = SaveManager.list_saves().is_empty()


func _on_count_selected(count: int) -> void:
	GameSetup.player_count = count
	_refresh_swatches(GameSetup.get_active_players())


func _on_win_mode_selected(mode: GameSetup.WinMode) -> void:
	GameSetup.win_mode = mode


func _refresh_swatches(active_players: Array[int]) -> void:
	for i in range(_swatches.size()):
		_swatches[i].visible = i in active_players


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_load_game_pressed() -> void:
	get_tree().change_scene_to_file(LOAD_GAME_SCENE)


func _on_scenario_pressed() -> void:
	get_tree().change_scene_to_file(SCENARIO_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
