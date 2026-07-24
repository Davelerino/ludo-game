extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `SaveManager`) déclaré dans project.godot, même principe que ScenarioState/
## SettingsManager.
## ============================================================================
## SaveManager — Sauvegardes nommées d'une partie en cours (§ sauvegarde/
## chargement).
##
## Deux rôles combinés :
##   1. Lire/écrire les fichiers de sauvegarde (JSON, user://saves/, même
##      pattern que ui/scenario/scenario_setup.gd:POSITIONS_DIR — une
##      collection structurée, pas de simples préférences plates comme
##      SettingsManager/ConfigFile).
##   2. Servir de boîte aux lettres vers scenes/main.tscn (comme ScenarioState) :
##      queue_load() lit un fichier et le garde en mémoire, main.gd le
##      consomme une seule fois au démarrage via has_pending_load()/
##      consume_pending_load().
##
## La sauvegarde n'a lieu qu'en tout début de tour (TurnManager.TurnState.
## WAITING_FOR_ROLL, voir ui/hud/player_hud.gd) : à cet instant dice_pool et
## locked_pawn_ids sont toujours vides, donc le snapshot n'a besoin de porter
## que active_player + le classement en cours (remaining_players/finish_order,
## utiles en mode Classement complet) + l'état des pions — pas la machine à
## tours en plein vol.
##
## Suivi "non sauvegardé" (is_dirty()) : utilisé par QuitConfirmDialog (voir
## ui/hud/player_hud.gd) pour ne proposer "Sauvegarder et quitter" que quand
## il y a réellement quelque chose à sauvegarder. `turn_ended` (GameEvents)
## est la même granularité "frontière de tour" que la sauvegarde elle-même —
## il couvre aussi bien un coup joué qu'un tour perdu sans coup légal, pas
## besoin d'écouter pawn_moved séparément.
## ============================================================================

const SAVES_DIR := "user://saves/"

var _pending_snapshot: Dictionary = {}
var _has_pending: bool = false
var _is_dirty: bool = false


func _ready() -> void:
	GameEvents.turn_ended.connect(_on_turn_ended)


func _on_turn_ended(_previous_player: int, _next_player: int) -> void:
	_is_dirty = true


func is_dirty() -> bool:
	return _is_dirty


## À appeler une fois qu'une partie (neuve, chargée, ou de scénario) est en
## place et correspond exactement à ce qui est affiché — voir main.gd, fin de
## _ready().
func mark_clean() -> void:
	_is_dirty = false


func has_pending_load() -> bool:
	return _has_pending


## À n'appeler qu'une fois, au démarrage de main.tscn (même contrat que
## ScenarioState.consume()).
func consume_pending_load() -> Dictionary:
	var result: Dictionary = _pending_snapshot
	_pending_snapshot = {}
	_has_pending = false
	return result


## Écrit une nouvelle sauvegarde (ou écrase une sauvegarde existante de même
## nom assaini). `pawns` doit être au format BoardManager.all_pawns (Array de
## Dictionary {"id","player","state","progress","captor_id"}) — on ne garde
## que les 4 champs consommés par BoardManager.apply_scenario().
func save_game(
	save_name: String,
	active_player: int,
	remaining_players: Array[int],
	finish_order: Array[int],
	pawns: Array
) -> bool:
	var raw_name: String = save_name.strip_edges()
	if raw_name.is_empty():
		raw_name = "partie_%s" % Time.get_datetime_string_from_system().replace(":", "-").replace(" ", "_")

	var pawn_entries: Array = []
	for p in pawns:
		pawn_entries.append({
			"id": p.id,
			"state": p.state,
			"progress": p.progress,
			"captor_id": p.captor_id,
		})

	var data := {
		"version": 1,
		"name": raw_name,
		"timestamp": Time.get_datetime_string_from_system(),
		"player_count": GameSetup.player_count,
		"win_mode": GameSetup.win_mode,
		"active_player": active_player,
		"remaining_players": remaining_players,
		"finish_order": finish_order,
		"pawns": pawn_entries,
	}

	DirAccess.make_dir_recursive_absolute(SAVES_DIR)
	var filename: String = _sanitize_filename(raw_name)
	var path: String = SAVES_DIR + filename + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveManager: échec de sauvegarde de '%s' (err=%s)." % [raw_name, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	_is_dirty = false
	GameEvents.game_saved.emit(raw_name)
	return true


## Liste les sauvegardes existantes, triées par nom de fichier : chaque entrée
## {"filename", "name", "timestamp", "player_count"} — lit l'en-tête de chaque
## fichier (peu de sauvegardes attendues, coût négligeable) pour afficher un
## nom/date lisibles dans l'écran de chargement.
func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return result

	var filenames: PackedStringArray = DirAccess.get_files_at(SAVES_DIR)
	var basenames: Array = []
	for f in filenames:
		if f.ends_with(".json"):
			basenames.append(f.get_basename())
	basenames.sort()

	for filename in basenames:
		var parsed: Dictionary = _read_save_file(filename)
		if parsed.is_empty():
			continue
		result.append({
			"filename": filename,
			"name": str(parsed.get("name", filename)),
			"timestamp": str(parsed.get("timestamp", "")),
			"player_count": int(parsed.get("player_count", 4)),
		})
	return result


func delete_save(filename: String) -> void:
	DirAccess.remove_absolute(SAVES_DIR + filename + ".json")


## Lit `filename` et le garde en mémoire pour que main.gd le consomme au
## prochain chargement de scenes/main.tscn. Retourne false si le fichier est
## absent/invalide (aucun état de chargement en attente n'est alors posé).
func queue_load(filename: String) -> bool:
	var parsed: Dictionary = _read_save_file(filename)
	if parsed.is_empty():
		return false
	_pending_snapshot = parsed
	_has_pending = true
	return true


func _read_save_file(filename: String) -> Dictionary:
	var path: String = SAVES_DIR + filename + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("SaveManager: échec de lecture de la sauvegarde '%s'." % filename)
		return {}
	var text: String = file.get_as_text()
	file.close()

	var raw: Variant = JSON.parse_string(text)
	if typeof(raw) != TYPE_DICTIONARY or not raw.has("pawns"):
		push_warning("SaveManager: fichier de sauvegarde invalide : %s" % filename)
		return {}
	return _normalize_snapshot(raw)


## JSON.parse_string() renvoie des float pour tous les nombres (y compris les
## states d'enum PawnState et les ids) — un `match` (voir BoardManager.cell_of())
## comme les comparaisons `==` avec un enum int attendent un vrai int, pas un
## float numériquement égal. ScenarioSetup ne rencontre jamais ce problème car
## une position chargée repasse toujours par les widgets typés de l'écran
## avant d'être relancée (voir scenario_setup.gd:_apply_loaded_entries()) ;
## une sauvegarde est appliquée directement via BoardManager.apply_scenario(),
## donc on caste ici, une fois, à la lecture du fichier.
func _normalize_snapshot(raw: Dictionary) -> Dictionary:
	var pawn_entries: Array = []
	for raw_entry in raw.get("pawns", []):
		var entry: Dictionary = raw_entry
		pawn_entries.append({
			"id": int(entry.get("id", -1)),
			"state": int(entry.get("state", 0)),
			"progress": int(entry.get("progress", -1)),
			"captor_id": int(entry.get("captor_id", -1)),
		})

	var remaining_players: Array[int] = []
	for v in raw.get("remaining_players", []):
		remaining_players.append(int(v))
	var finish_order: Array[int] = []
	for v in raw.get("finish_order", []):
		finish_order.append(int(v))

	return {
		"version": int(raw.get("version", 1)),
		"name": str(raw.get("name", "")),
		"timestamp": str(raw.get("timestamp", "")),
		"player_count": int(raw.get("player_count", 4)),
		"win_mode": int(raw.get("win_mode", 0)),
		"active_player": int(raw.get("active_player", 0)),
		"remaining_players": remaining_players,
		"finish_order": finish_order,
		"pawns": pawn_entries,
	}


## Même règle que ScenarioSetup._sanitize_filename() : tout caractère hors
## [A-Za-z0-9_-] remplacé par "_", pour un nom de fichier sûr sur tous les OS.
func _sanitize_filename(name: String) -> String:
	var regex := RegEx.new()
	regex.compile("[^A-Za-z0-9_\\-]+")
	var cleaned: String = regex.sub(name, "_", true).strip_edges()
	return cleaned if not cleaned.is_empty() else "partie"
