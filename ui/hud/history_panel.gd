class_name HistoryPanel
extends PanelContainer
## ============================================================================
## HistoryPanel — Historique des tours joués, toujours visible dans le HUD
## (voir handoff design + demande UX : le jeu peut avancer vite, le joueur
## doit pouvoir vérifier après coup ce qu'il vient de jouer).
##
## Une entrée = un tour complet (lancer(s) + coups joués avec). Accumulée
## localement en écoutant GameEvents directement (même pattern que
## hud.gd/dice_pool_view.gd) — pas de nouvel état partagé côté TurnManager.
## ============================================================================

const PALETTE: PlayerPalette = preload("res://resources/PlayerPalette.tres")
const HistoryEntryScene: PackedScene = preload("res://ui/hud/history_entry.tscn")

## Nombre d'entrées archivées conservées (les plus anciennes sont retirées
## au-delà) — réglable dans l'Inspector.
@export var max_entries: int = 20

var turn_manager: TurnManager  # injecté par player_hud.gd

@onready var _list: VBoxContainer = %HistoryList

## {} quand aucun tour en cours d'accumulation ; sinon
## {player_id:int, dice:Array[Array], moves:Array[String], busted:bool}.
var _pending: Dictionary = {}
## Entrées archivées, plus récente en premier (index 0).
var _entries: Array[Dictionary] = []


func _ready() -> void:
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	GameEvents.pawn_moved.connect(_on_pawn_moved)
	GameEvents.pawn_captured.connect(_on_pawn_captured)
	GameEvents.turn_busted.connect(_on_turn_busted)
	GameEvents.turn_ended.connect(_on_turn_ended)
	GameEvents.victory.connect(_on_victory)


func _on_dice_rolled(a: int, b: int, _is_double: bool) -> void:
	if not turn_manager:
		return
	var player_id: int = turn_manager.active_player
	if _pending.is_empty() or _pending.player_id != player_id:
		# Nouveau tour, ou 1er lancer du tour — un double-six enchaîné
		# rappelle dice_rolled plusieurs fois pour le MÊME joueur avant que
		# le tour ne se termine : on alimente alors l'entrée déjà ouverte au
		# lieu d'en recréer une, pour tout regrouper en une seule ligne.
		_pending = {"player_id": player_id, "dice": [], "moves": [], "busted": false}
	_pending.dice.append([a, b])


func _on_pawn_moved(pawn: Dictionary, dice_value: int) -> void:
	if _pending.is_empty():
		return
	_pending.moves.append("Pion #%d avance de %d" % [pawn.id, dice_value])


func _on_pawn_captured(captured_pawn: Dictionary, capturing_pawn: Dictionary) -> void:
	if _pending.is_empty():
		return
	_pending.moves.append("Pion #%d capture le pion #%d" % [capturing_pawn.id, captured_pawn.id])


func _on_turn_busted(player_id: int) -> void:
	if _pending.is_empty() or _pending.player_id != player_id:
		return
	_pending.busted = true


func _on_turn_ended(previous: int, _next: int) -> void:
	if _pending.is_empty() or _pending.player_id != previous:
		return
	_commit_pending()


## Après une victoire, TurnManager._end_turn() n'est jamais appelé — turn_ended
## ne viendra donc pas clôturer le dernier tour gagnant. On l'archive ici pour
## que la ligne finale n'ait pas simplement disparu.
func _on_victory(_winner_id: int) -> void:
	if not _pending.is_empty():
		_commit_pending()


func _commit_pending() -> void:
	_entries.push_front(_pending)
	_pending = {}
	while _entries.size() > max_entries:
		_entries.pop_back()
	_rebuild_list()


func _rebuild_list() -> void:
	for child in _list.get_children():
		child.queue_free()
	for entry in _entries:
		var row: HistoryEntry = HistoryEntryScene.instantiate()
		_list.add_child(row)
		row.set_entry(_format_header(entry), PALETTE.dark(entry.player_id), _format_detail(entry))


func _format_header(entry: Dictionary) -> String:
	var dice_parts: PackedStringArray = []
	for pair in entry.dice:
		dice_parts.append("%d et %d" % [pair[0], pair[1]])
	return "%s — %s" % [PALETTE.player_name(entry.player_id), ", ".join(dice_parts)]


func _format_detail(entry: Dictionary) -> String:
	if entry.busted:
		return "💥 Bust (trois doubles-six)"
	if entry.moves.is_empty():
		return "Aucun coup possible"
	return "\n".join(entry.moves)
