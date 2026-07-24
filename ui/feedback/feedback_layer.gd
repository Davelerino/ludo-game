class_name FeedbackLayer
extends Control
## ============================================================================
## FeedbackLayer — Retours visuels ponctuels (capture, barrière, victoire).
## GDD §11.5 : UIManager > feedback. Écoute GameEvents.
##
## SQUELETTE : empile des labels flottants qui s'estompent. À remplacer par
## des particules / flashs d'écran quand les assets seront prêts.
## ============================================================================

var _anchor: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_anchor = VBoxContainer.new()
	_anchor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_anchor.alignment = BoxContainer.ALIGNMENT_END
	add_child(_anchor)

	GameEvents.pawn_captured.connect(_on_capture)
	GameEvents.barrier_formed.connect(_on_barrier)
	GameEvents.victory.connect(_on_victory)
	GameEvents.player_finished_ranked.connect(_on_player_finished_ranked)
	GameEvents.game_saved.connect(_on_game_saved)


func _show(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	_anchor.add_child(lbl)
	var tween := create_tween()
	tween.tween_property(lbl, "modulate:a", 0.0, 1.5).set_delay(1.0)
	tween.tween_callback(lbl.queue_free)


func _on_capture(v: Dictionary, a: Dictionary) -> void:
	_show("💥 Capture ! Pion %d" % a.id, Color.PURPLE)

func _on_barrier(_p: Dictionary, _idx: int) -> void:
	_show("🛡 Barrière formée", Color.TEAL)

func _on_victory(w: int) -> void:
	_show("🏆 Joueur %d gagne !" % w, Color.GOLD)

## La 1ère place est déjà annoncée par _on_victory() ci-dessus (même instant,
## voir TurnManager._after_move_resolved()) — ne montrer ce toast que pour les
## places suivantes (mode FULL_RANKING, GameSetup.WinMode).
func _on_player_finished_ranked(player_id: int, place: int) -> void:
	if place == 1:
		return
	_show("🎉 Joueur %d termine %s !" % [player_id, _ordinal(place)], Color.SILVER)


func _ordinal(place: int) -> String:
	return "%dème" % place

func _on_game_saved(save_name: String) -> void:
	_show("💾 Partie sauvegardée : %s" % save_name, Color.SKY_BLUE)
