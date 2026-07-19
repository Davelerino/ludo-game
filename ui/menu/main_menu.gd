class_name MainMenu
extends Control
## ============================================================================
## MainMenu — Écran-titre, point d'entrée du jeu (avant scenes/main.tscn).
##
## Deux actions : lancer une partie (change de scène vers le plateau) ou
## quitter. Construit entièrement en code, comme le reste de ui/ (HUD,
## DiceView, FeedbackLayer), pour rester cohérent avec le style existant.
## ============================================================================

const GAME_SCENE := "res://scenes/main.tscn"
const SCENARIO_SCENE := "res://scenes/scenario/scenario_setup.tscn"
const PLAYER_COLORS: Array[Color] = [Color.CRIMSON, Color.ROYAL_BLUE, Color.FOREST_GREEN, Color.GOLDENROD]

var _play_button: Button
var _scenario_button: Button
var _quit_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "LUDO 3D"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)

	var swatches := HBoxContainer.new()
	swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	swatches.add_theme_constant_override("separation", 8)
	vbox.add_child(swatches)
	for color in PLAYER_COLORS:
		var chip := ColorRect.new()
		chip.color = color
		chip.custom_minimum_size = Vector2(28, 28)
		swatches.add_child(chip)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	_play_button = Button.new()
	_play_button.text = "Jouer"
	_play_button.custom_minimum_size = Vector2(220, 48)
	_play_button.pressed.connect(_on_play_pressed)
	vbox.add_child(_play_button)

	_scenario_button = Button.new()
	_scenario_button.text = "Configurer un scénario"
	_scenario_button.custom_minimum_size = Vector2(220, 48)
	_scenario_button.pressed.connect(_on_scenario_pressed)
	vbox.add_child(_scenario_button)

	_quit_button = Button.new()
	_quit_button.text = "Quitter"
	_quit_button.custom_minimum_size = Vector2(220, 48)
	_quit_button.pressed.connect(_on_quit_pressed)
	vbox.add_child(_quit_button)


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_scenario_pressed() -> void:
	get_tree().change_scene_to_file(SCENARIO_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
