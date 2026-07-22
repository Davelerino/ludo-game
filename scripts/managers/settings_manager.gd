extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `SettingsManager`) déclaré dans project.godot. Godot enregistre lui-même la
## classe globale ; un `class_name` identique causerait une collision.
## ============================================================================
## SettingsManager — Préférences utilisateur persistantes (menu Paramètres,
## voir ui/settings/settings_menu.gd).
##
## Persistance via ConfigFile (outil natif Godot pour ce cas — clé/valeur
## simple), dans user://settings.cfg. Contrairement aux positions de scénario
## (ui/scenario/scenario_setup.gd, JSON) qui sont une collection structurée,
## ce sont de simples préférences plates : ConfigFile est plus direct qu'un
## JSON fait main pour ce besoin.
## ============================================================================

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "gameplay"

## Recentrage automatique de la caméra au changement de tour (voir
## scripts/core/camera_rig.gd:_on_turn_ended()). Activé par défaut (comportement
## historique avant l'ajout de ce réglage).
signal camera_auto_focus_changed(enabled: bool)

var camera_auto_focus_enabled: bool = true:
	set(value):
		camera_auto_focus_enabled = value
		camera_auto_focus_changed.emit(value)
		_save()


func _ready() -> void:
	_load()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		camera_auto_focus_enabled = cfg.get_value(SECTION, "camera_auto_focus", true)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # préserve d'éventuelles autres clés déjà écrites
	cfg.set_value(SECTION, "camera_auto_focus", camera_auto_focus_enabled)
	cfg.save(SETTINGS_PATH)
