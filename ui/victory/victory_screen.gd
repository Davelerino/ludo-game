class_name VictoryScreen
extends Control
## ============================================================================
## VictoryScreen — Écran de fin de partie (§victoire/classement).
##
## PAS une scène atteinte par change_scene_to_file() (ça détruirait tout
## l'état de partie en cours) : c'est un overlay plein-écran, instancié comme
## enfant de ui_manager.tscn et simplement montré/caché via `visible` — même
## principe que SettingsMenu (voir ui/settings/settings_menu.gd). Construit
## entièrement en code, comme le reste de ui/.
##
## Écoute GameEvents.game_over(ranking) : `ranking` de taille 1 (mode
## GameSetup.WinMode.FIRST_WINNER, seul le gagnant est déterminé) affiche un
## grand avatar "X gagne !" ; `ranking` complet (mode FULL_RANKING) affiche le
## classement ligne par ligne, médaille pour le podium.
## ============================================================================

const PALETTE: PlayerPalette = preload("res://resources/PlayerPalette.tres")
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _content: VBoxContainer
var _avatar_base_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	GameEvents.game_over.connect(_on_game_over)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.09, 0.85)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "🏁 Partie terminée"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 12)
	vbox.add_child(_content)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 12)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	var replay_button := Button.new()
	replay_button.text = "Rejouer"
	replay_button.custom_minimum_size = Vector2(160, 48)
	replay_button.theme_type_variation = &"RollButton"
	replay_button.pressed.connect(_on_replay_pressed)
	button_row.add_child(replay_button)

	var menu_button := Button.new()
	menu_button.text = "Menu principal"
	menu_button.custom_minimum_size = Vector2(160, 48)
	menu_button.pressed.connect(_on_menu_pressed)
	button_row.add_child(menu_button)


func _on_game_over(ranking: Array[int]) -> void:
	for child in _content.get_children():
		child.queue_free()

	if ranking.size() == 1:
		_build_single_winner_view(ranking[0])
	else:
		_build_ranking_view(ranking)

	visible = true


func _build_single_winner_view(winner_id: int) -> void:
	var avatar_center := CenterContainer.new()
	_content.add_child(avatar_center)
	avatar_center.add_child(_make_avatar(winner_id, 96, 34))

	var name_label := Label.new()
	name_label.text = "%s gagne !" % PALETTE.player_name(winner_id)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", PALETTE.dark(winner_id))
	_content.add_child(name_label)


func _build_ranking_view(ranking: Array[int]) -> void:
	for i in range(ranking.size()):
		var player_id: int = ranking[i]
		var place: int = i + 1

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_content.add_child(row)

		var place_label := Label.new()
		place_label.text = _place_badge(place)
		place_label.custom_minimum_size = Vector2(48, 0)
		place_label.add_theme_font_size_override("font_size", 20)
		row.add_child(place_label)

		row.add_child(_make_avatar(player_id, 40, 14))

		var name_label := Label.new()
		name_label.text = PALETTE.player_name(player_id)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 18)
		name_label.add_theme_color_override("font_color", PALETTE.dark(player_id))
		row.add_child(name_label)


## Panel + Label imitant PlayerChip._avatar/_avatar_label (voir
## ui/hud/player_chip.gd), mais dimensionné à la volée : la variation de
## thème "PlayerAvatar" a un corner_radius fixe (15, calibré pour les chips
## 30x30 du HUD) — on duplique donc le style et on recalcule le rayon en
## fonction de la taille demandée pour garder un cercle parfait.
func _make_avatar(player_id: int, size: int, font_size: int) -> Panel:
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(size, size)
	avatar.theme_type_variation = &"PlayerAvatar"

	if not _avatar_base_style:
		_avatar_base_style = avatar.get_theme_stylebox("panel")
	var style: StyleBoxFlat = _avatar_base_style.duplicate()
	style.bg_color = PALETTE.main(player_id)
	var radius: int = size / 2
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	avatar.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = PALETTE.initials(player_id)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	avatar.add_child(label)

	return avatar


func _place_badge(place: int) -> String:
	match place:
		1: return "🥇"
		2: return "🥈"
		3: return "🥉"
		_: return "%dème" % place


func _on_replay_pressed() -> void:
	get_tree().reload_current_scene()


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
