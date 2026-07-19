extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `ScenarioState`) déclaré dans project.godot. Godot enregistre lui-même la
## classe globale ; un `class_name` identique causerait une collision.
## ============================================================================
## ScenarioState — Boîte aux lettres entre scenario_setup.tscn et main.tscn.
##
## Transporte la configuration manuelle d'un scénario de test (voir
## ui/scenario/scenario_setup.gd) d'une scène à l'autre, puisque
## `change_scene_to_file()` détruit tous les noeuds de la scène courante.
## `main.gd` consomme cet état une seule fois au démarrage (voir consume()).
## ============================================================================

var _pending_pawn_entries: Array = []
var _pending_active_player: int = 0
var _has_pending: bool = false


## Chaque entrée : {"id": int, "state": BoardConfig.PawnState, "progress": int,
## "captor_id": int} — voir BoardManager.apply_scenario().
func set_pending(pawn_entries: Array, active_player: int) -> void:
	_pending_pawn_entries = pawn_entries
	_pending_active_player = active_player
	_has_pending = true


func has_pending() -> bool:
	return _has_pending


## Retourne {"pawn_entries": Array, "active_player": int} et vide l'état
## (à n'appeler qu'une fois, au démarrage de main.tscn).
func consume() -> Dictionary:
	var result := {
		"pawn_entries": _pending_pawn_entries,
		"active_player": _pending_active_player,
	}
	_pending_pawn_entries = []
	_pending_active_player = 0
	_has_pending = false
	return result
