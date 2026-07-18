class_name HUD
extends Control
## ============================================================================
## HUD — Panneau de debug/état de partie (GDD §11.5 : UIManager > HUD).
##
## Affiche : joueur actif (avec sa vraie couleur), état du tour, les deux dés
## (valeur + consommé ou non), les pions actuellement jouables, un tableau
## compact des 16 pions, et un journal d'événements réduit en dessous.
## Écoute GameEvents (§11.2) pour rester découplée des managers — sauf
## DiceSystem/BoardManager, qui ne sont pas des autoloads (contrairement à
## TurnManager) et doivent être injectés par main.gd.
## ============================================================================

const PawnState := BoardConfig.PawnState

## Player0=Bleu, Player1=Vert, Player2=Rouge, Player3=Jaune — voir
## pawn_controller.gd:pawn_scenes (source de vérité des couleurs réelles).
const PLAYER_NAMES := ["Bleu", "Vert", "Rouge", "Jaune"]
## Reprises des shader_parameter/albedo_color de resources/{Couleur}_mat.tres,
## pour que les pastilles du panneau correspondent aux pions sur le plateau.
const PLAYER_COLORS := [
	Color(0, 0.5294118, 0.90588236),
	Color(0, 0.6509804, 0.023529412),
	Color(0.90588236, 0.015686275, 0),
	Color(0.90588236, 0.76862746, 0),
]

## Injectés par main.gd (DiceSystem/BoardManager sont des noeuds de scène,
## pas des autoloads).
var dice_system: DiceSystem
var board_manager: BoardManager

var _player_swatch: ColorRect
var _player_label: Label
var _state_label: Label
var _dice_label: Label
var _offered_label: Label
var _pawns_table: RichTextLabel
var _log: RichTextLabel

var _offered_pawn_ids: Array = []
var _offered_dice_value: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.turn_ended.connect(_on_turn_ended)
	GameEvents.turn_state_changed.connect(_on_state_changed)
	GameEvents.pawns_offered.connect(_on_pawns_offered)
	GameEvents.pawn_moved.connect(_on_pawn_moved)
	GameEvents.pawn_captured.connect(_on_pawn_captured)
	GameEvents.victory.connect(_on_victory)
	_refresh_player_label(0)
	_refresh_offered_label()
	refresh()


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 6)
	vbox.add_child(player_row)

	_player_swatch = ColorRect.new()
	_player_swatch.custom_minimum_size = Vector2(14, 14)
	_player_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_row.add_child(_player_swatch)

	_player_label = Label.new()
	player_row.add_child(_player_label)

	_state_label = Label.new()
	vbox.add_child(_state_label)

	_dice_label = Label.new()
	_dice_label.text = "Dés : - / -"
	vbox.add_child(_dice_label)

	_offered_label = Label.new()
	vbox.add_child(_offered_label)

	# Tableau compact des 16 pions (bbcode [table], pas de noeuds par ligne à
	# reconstruire à la main à chaque rafraîchissement).
	_pawns_table = RichTextLabel.new()
	_pawns_table.bbcode_enabled = true
	_pawns_table.fit_content = true
	_pawns_table.custom_minimum_size = Vector2(0, 170)
	# RichTextLabel a mouse_filter=STOP par défaut (contrairement à Label) —
	# voir le correctif du journal ci-dessous, même raison.
	_pawns_table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_pawns_table)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.bbcode_enabled = true
	_log.scroll_following = true
	# RichTextLabel a mouse_filter=STOP par défaut (contrairement à Label) pour
	# permettre la sélection de texte / les liens BBCode. Ce journal n'en a pas
	# besoin, et son rect s'étend sur presque tout l'écran (EXPAND_FILL dans un
	# conteneur plein écran) : sans IGNORE explicite, il absorbe tous les clics
	# destinés au plateau 3D en dessous, avant qu'ils n'atteignent PawnController.
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_log)


## Rafraîchit les champs qui dépendent de dice_system/board_manager — à
## appeler une fois ces références injectées par main.gd (elles ne le sont
## pas encore quand _ready() tourne : HUD est un enfant, donc prêt avant le
## script racine Main qui fait l'injection).
func refresh() -> void:
	_refresh_dice_label()
	_refresh_pawns_table()


func _on_dice_rolled(a: int, b: int, is_double: bool) -> void:
	_append_log("🎲 Dés : [b]%d[/b] et [b]%d[/b]%s." % [a, b, ("  (DOUBLE)" if is_double else "")])
	_refresh_dice_label()


func _on_turn_ended(_prev: int, next_p: int, extra: bool) -> void:
	if extra:
		_append_log("[color=orange]✦ Extra tour pour le joueur %d (%s)[/color]" % [next_p, PLAYER_NAMES[next_p]])
	else:
		_append_log("--- Tour du joueur %d (%s) ---" % [next_p, PLAYER_NAMES[next_p]])
		_refresh_player_label(next_p)
	_offered_pawn_ids = []
	_refresh_offered_label()


func _on_state_changed(_old: int, new_state: int) -> void:
	_state_label.text = "État du tour : %s" % TurnManager.TurnState.find_key(new_state)
	if new_state == TurnManager.TurnState.CHECKING_MOVES:
		# Nouveau lancer : la liste de pions jouables du tour précédent est
		# obsolète tant que _offer_selection() n'en a pas republié une.
		_offered_pawn_ids = []
		_refresh_offered_label()
	_refresh_dice_label()
	_refresh_pawns_table()


func _on_pawns_offered(_player_id: int, pawn_ids: Array, dice_value: int) -> void:
	_offered_pawn_ids = pawn_ids
	_offered_dice_value = dice_value
	_refresh_offered_label()


func _on_pawn_moved(pawn: Dictionary, _dv: int) -> void:
	_append_log("Pion %d (joueur %d) déplacé -> progress %d." % [pawn.id, pawn.player, pawn.progress])
	_refresh_dice_label()
	_refresh_pawns_table()


func _on_pawn_captured(victim: Dictionary, attacker: Dictionary) -> void:
	_append_log("[color=purple]💥 Pion %d capture le pion %d (renvoyé au yard).[/color]" % [attacker.id, victim.id])


func _on_victory(winner: int) -> void:
	_append_log("[b][color=gold]🏆 Victoire du joueur %d (%s) ![/color][/b]" % [winner, PLAYER_NAMES[winner]])


func _refresh_player_label(player_id: int) -> void:
	_player_label.text = "Joueur actif : %d (%s)" % [player_id, PLAYER_NAMES[player_id]]
	_player_swatch.color = PLAYER_COLORS[player_id]


func _refresh_offered_label() -> void:
	if _offered_pawn_ids.is_empty():
		_offered_label.text = "Pions jouables : -"
		return
	var ids := PackedStringArray()
	for pawn_id in _offered_pawn_ids:
		ids.append(str(pawn_id))
	_offered_label.text = "Pions jouables (dé=%d) : %s" % [_offered_dice_value, ", ".join(ids)]


func _refresh_dice_label() -> void:
	if not dice_system or dice_system.dice_a == 0:
		_dice_label.text = "Dés : - / -"
		return
	var a_state := "utilisé" if dice_system.dice_a_used else "libre"
	var b_state := "utilisé" if dice_system.dice_b_used else "libre"
	var double_tag := "  (DOUBLE)" if dice_system.is_double() else ""
	_dice_label.text = "Dés : A=%d (%s) · B=%d (%s)%s" % [
		dice_system.dice_a, a_state, dice_system.dice_b, b_state, double_tag
	]


func _refresh_pawns_table() -> void:
	if not board_manager:
		return
	var bb := "[table=4]"
	bb += "[cell][b]Id[/b][/cell][cell][b]Joueur[/b][/cell][cell][b]État[/b][/cell][cell][b]Prog.[/b][/cell]"
	for pawn in board_manager.all_pawns:
		var color_hex: String = PLAYER_COLORS[pawn.player].to_html(false)
		bb += "[cell]%d[/cell][cell][color=#%s]%s[/color][/cell][cell]%s[/cell][cell]%d[/cell]" % [
			pawn.id, color_hex, PLAYER_NAMES[pawn.player],
			PawnState.find_key(pawn.state), pawn.progress
		]
	bb += "[/table]"
	_pawns_table.text = bb


func _append_log(text: String) -> void:
	_log.append_text(text + "\n")
