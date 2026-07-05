class_name HUD
extends Control
## ============================================================================
## HUD — Overlay d'information de partie (GDD §11.5 : UIManager > HUD).
##
## Affiche : joueur actif, dés courants, état du tour (TurnManager.TurnState),
## et le journal d'événements. Écoute GameEvents (§11.2) — ne dépend pas
## directement des managers, ce qui garde l'UI découplée.
## ============================================================================

const PLAYER_NAMES := ["Rouge", "Bleu", "Vert", "Jaune"]

var _player_label: Label
var _state_label: Label
var _dice_label: Label
var _log: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.turn_ended.connect(_on_turn_ended)
	GameEvents.turn_state_changed.connect(_on_state_changed)
	GameEvents.pawn_moved.connect(_on_pawn_moved)
	GameEvents.pawn_captured.connect(_on_pawn_captured)
	GameEvents.victory.connect(_on_victory)
	_player_label.text = "Joueur actif : 0 (%s)" % PLAYER_NAMES[0]


func _build() -> void:
	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	_player_label = Label.new()
	vbox.add_child(_player_label)

	_state_label = Label.new()
	vbox.add_child(_state_label)

	_dice_label = Label.new()
	_dice_label.text = "Dés : - / -"
	vbox.add_child(_dice_label)

	_log = RichTextLabel.new()
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.bbcode_enabled = true
	_log.scroll_following = true
	vbox.add_child(_log)


func _on_dice_rolled(a: int, b: int, is_double: bool) -> void:
	_dice_label.text = "Dés : %d / %d%s" % [a, b, ("  (DOUBLE)" if is_double else "")]
	_append_log("🎲 Dés : [b]%d[/b] et [b]%d[/b]." % [a, b])


func _on_turn_ended(prev: int, next_p: int, extra: bool) -> void:
	if extra:
		_append_log("[color=orange]✦ Extra tour pour le joueur %d (%s)[/color]" % [next_p, PLAYER_NAMES[next_p]])
	else:
		_player_label.text = "Joueur actif : %d (%s)" % [next_p, PLAYER_NAMES[next_p]]
		_append_log("--- Tour du joueur %d (%s) ---" % [next_p, PLAYER_NAMES[next_p]])


func _on_state_changed(_old: int, new_state: int) -> void:
	_state_label.text = "État du tour : %s" % TurnManager.TurnState.find_key(new_state)


func _on_pawn_moved(pawn: Dictionary, _dv: int) -> void:
	_append_log("Pion %d (joueur %d) déplacé -> progress %d." % [pawn.id, pawn.player, pawn.progress])


func _on_pawn_captured(victim: Dictionary, attacker: Dictionary) -> void:
	_append_log("[color=purple]💥 Pion %d capture le pion %d (renvoyé au yard).[/color]" % [attacker.id, victim.id])


func _on_victory(winner: int) -> void:
	_append_log("[b][color=gold]🏆 Victoire du joueur %d (%s) ![/color][/b]" % [winner, PLAYER_NAMES[winner]])


func _append_log(text: String) -> void:
	_log.append_text(text + "\n")
