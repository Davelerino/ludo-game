class_name SettingsMenu
extends Control
## ============================================================================
## SettingsMenu — Panneau de préférences (menu Paramètres), accessible depuis
## le bouton ⚙ du HUD de jeu (voir ui/hud/player_hud.gd).
##
## PAS une scène atteinte par change_scene_to_file() (ça détruirait tout
## l'état de partie en cours — plateau, pions, TurnManager désynchronisé) :
## c'est un overlay plein-écran, instancié comme enfant de player_hud.tscn et
## simplement montré/caché via `visible` (même principe que HistoryPanel dans
## la même scène). Construit entièrement en code, comme le reste de ui/
## (MainMenu, ScenarioSetup).
## ============================================================================

var _camera_focus_check: CheckButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func _build() -> void:
	# Fond semi-opaque qui bloque les clics vers le plateau 3D tant que le
	# menu est ouvert (mouse_filter = STOP, contrairement aux fonds "ignore"
	# des autres écrans plein-écran de ce projet qui n'ont rien en dessous).
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paramètres"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	var camera_row := HBoxContainer.new()
	camera_row.add_theme_constant_override("separation", 12)
	vbox.add_child(camera_row)

	var camera_label := Label.new()
	camera_label.text = "Recentrer la caméra automatiquement"
	camera_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	camera_row.add_child(camera_label)

	_camera_focus_check = CheckButton.new()
	_camera_focus_check.button_pressed = SettingsManager.camera_auto_focus_enabled
	_camera_focus_check.toggled.connect(_on_camera_focus_toggled)
	camera_row.add_child(_camera_focus_check)

	var close_button := Button.new()
	close_button.text = "Fermer"
	close_button.custom_minimum_size = Vector2(0, 44)
	close_button.pressed.connect(_on_close_pressed)
	vbox.add_child(close_button)


func _on_camera_focus_toggled(pressed: bool) -> void:
	SettingsManager.camera_auto_focus_enabled = pressed


func _on_close_pressed() -> void:
	visible = false
