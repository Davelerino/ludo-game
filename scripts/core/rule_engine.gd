class_name RuleEngine
extends RefCounted
## ============================================================================
## RuleEngine — Validation des mouvements, barrières, captures, home lane.
## Référence : GDD_Ludo3D.md §6, §7, §8, §10 (cas limites L1-L13)
##
## PRINCIPE DE CONCEPTION (§11.7) :
##   Ce moteur est un ensemble de fonctions PURES : il ne connaît ni GridMap,
##   ni Vector3i, ni noeud de scène. Il opère uniquement sur des index entiers
##   (`progress`, index de ring, index de home lane) et sur des tableaux de
##   Dictionary représentant les pions. Il est donc testable intégralement
##   en dehors de toute scène 3D (cf. test_rule_engine.gd).
##
## FORME D'UN PION (Dictionary) — voir board_config.gd :
##   {
##     "id": int,
##     "player": int,               # 0..PLAYER_COUNT-1
##     "state": BoardConfig.PawnState,
##     "progress": int,             # -1 (yard/capturé) ou 0..FINISH_PROGRESS
##     "captor_id": int,            # -1, ou id du joueur dont la zone de
##                                  # capture retient ce pion (state==CAPTURED)
##   }
##
## Aucune fonction de cette classe ne mute directement l'état sauf apply_move(),
## qui est le seul point d'entrée effectuant un changement d'état persistant.
## ============================================================================

const PawnState := BoardConfig.PawnState


# ----------------------------------------------------------------------------
# 1. CONVERSIONS DE POSITION
# ----------------------------------------------------------------------------

## Index sur la ring lane (0..51) d'un pion actuellement en état RING.
## Retourne -1 si le pion n'est pas sur la ring lane.
static func get_ring_index(pawn: Dictionary) -> int:
	if pawn.state != PawnState.RING:
		return -1
	var offset: int = BoardConfig.get_player_offset(pawn.player)
	return (offset + pawn.progress) % BoardConfig.RING_SIZE

## Index local dans la home lane (0..HOME_LANE_LENGTH-1) d'un pion HOME_LANE ou FINI.
## Retourne -1 si le pion n'est pas dans sa home lane.
static func get_home_lane_index(pawn: Dictionary) -> int:
	if pawn.state != PawnState.HOME_LANE and pawn.state != PawnState.FINI:
		return -1
	return pawn.progress - BoardConfig.HOME_ENTRY_PROGRESS

## Index (sur la ring lane) de la start tile d'un joueur = son offset (§3.2).
static func get_start_tile_index(player_id: int) -> int:
	return BoardConfig.get_player_offset(player_id)

## Index d'entrée en home lane d'un joueur : la case juste avant sa start tile (§7.2).
static func get_home_entry_ring_index(player_id: int) -> int:
	var offset: int = BoardConfig.get_player_offset(player_id)
	return (offset + BoardConfig.RING_SIZE - 1) % BoardConfig.RING_SIZE

static func is_finished(pawn: Dictionary) -> bool:
	return pawn.state == PawnState.FINI


# ----------------------------------------------------------------------------
# 2. DÉTECTION DE BARRIÈRE (§6)
# ----------------------------------------------------------------------------

## Tous les pions présents sur une case donnée de la ring lane.
static func get_pawns_on_ring_index(ring_index: int, all_pawns: Array) -> Array:
	var result: Array = []
	for pawn in all_pawns:
		if pawn.state == PawnState.RING and get_ring_index(pawn) == ring_index:
			result.append(pawn)
	return result

## Retourne l'id du joueur propriétaire d'une barrière sur `ring_index`,
## ou -1 si aucune barrière n'existe sur cette case (B1, B4).
static func get_barrier_owner_at(ring_index: int, all_pawns: Array) -> int:
	var counts := {}
	for pawn in get_pawns_on_ring_index(ring_index, all_pawns):
		counts[pawn.player] = counts.get(pawn.player, 0) + 1
	for player_id in counts.keys():
		if counts[player_id] >= BoardConfig.BARRIER_MIN_PAWNS:
			return player_id
	return -1

static func is_barrier_at(ring_index: int, all_pawns: Array) -> bool:
	return get_barrier_owner_at(ring_index, all_pawns) != -1

## Nombre de pions du joueur `player_id` présents sur la case `home_progress`
## de SA PROPRE home lane. Fonction interne partagée par
## is_home_lane_barrier_at() (transit) et try_move() (atterrissage, où il faut
## compter les occupants AVANT l'arrivée du pion qui atterrit).
static func _count_home_lane_occupants(player_id: int, home_progress: int, all_pawns: Array) -> int:
	var count: int = 0
	for p in all_pawns:
		if p.player == player_id and p.state == PawnState.HOME_LANE and p.progress == home_progress:
			count += 1
	return count

## Vrai si le joueur `player_id` a une barrière (>= BARRIER_MIN_PAWNS pions)
## sur la case `home_progress` de SA PROPRE home lane. Contrairement à
## get_barrier_owner_at() (ring, partagé entre joueurs, peut être "ennemie"),
## la home lane est privée par joueur (§7) : une barrière n'y est jamais
## qu'alliée, pas besoin de retourner un owner.
static func is_home_lane_barrier_at(player_id: int, home_progress: int, all_pawns: Array) -> bool:
	return _count_home_lane_occupants(player_id, home_progress, all_pawns) >= BoardConfig.BARRIER_MIN_PAWNS

## Tous les pions du MÊME joueur présents sur la même case de home lane que
## `pawn` (case privée par joueur — pas de partage inter-joueurs contrairement
## à la ring lane, donc pawn.player + pawn.progress suffisent comme clé).
## Retourne [] si `pawn` n'est pas en HOME_LANE. Un empilement ici peut
## désormais constituer une barrière (>= BARRIER_MIN_PAWNS, voir
## is_home_lane_barrier_at()) qui bloque le TRANSIT des autres pions du même
## joueur — l'atterrissage lui-même reste toujours autorisé (H3 : pas de
## capture possible, case privée). Cette fonction-ci reste utilisée pour
## l'empilement VISUEL (get_stack_at(), PawnController).
static func get_pawns_on_home_lane_cell(pawn: Dictionary, all_pawns: Array) -> Array:
	var result: Array = []
	if pawn.state != PawnState.HOME_LANE:
		return result
	for p in all_pawns:
		if p.player == pawn.player and p.state == PawnState.HOME_LANE and p.progress == pawn.progress:
			result.append(p)
	return result

## Tous les pions (y compris `pawn` lui-même) partageant la case ACTUELLE de
## `pawn`, que ce soit sur l'anneau ou en couloir final — utilisé par
## PawnController pour l'empilement visuel des barrières (§6), PAS pour la
## validation de règles (qui reste dans try_move()/get_barrier_owner_at()
## pour l'anneau, is_home_lane_barrier_at() pour le couloir final).
## Retourne [] pour MAISON/CAPTURED/FINI (pas d'empilement visuel géré pour
## ces états, voir BoardManager._yard_world_position()/_capture_zone_world_position()).
## `all_pawns` est construit une fois par BoardManager par id croissant et
## jamais réordonné, donc le groupe retourné est toujours trié par pawn.id.
static func get_stack_at(pawn: Dictionary, all_pawns: Array) -> Array:
	match pawn.state:
		PawnState.RING:
			return get_pawns_on_ring_index(get_ring_index(pawn), all_pawns)
		PawnState.HOME_LANE:
			return get_pawns_on_home_lane_cell(pawn, all_pawns)
	return []


# ----------------------------------------------------------------------------
# 3. VALIDATION D'UN MOUVEMENT (coeur du RuleEngine)
# ----------------------------------------------------------------------------
#
# Résultat standard renvoyé par try_move() :
# {
#   "legal": bool,
#   "reason": String,            # code d'erreur si illégal, "" sinon
#   "capture": bool,
#   "captured_pawn": Dictionary or null,
#   "forms_barrier": bool,
#   "enters_home": bool,
#   "finishes": bool,
#   "new_progress": int,
#   "new_state": PawnState,
# }

static func _empty_result(reason: String) -> Dictionary:
	return {
		"legal": false,
		"reason": reason,
		"capture": false,
		"captured_pawn": null,
		"forms_barrier": false,
		"enters_home": false,
		"finishes": false,
		"new_progress": -1,
		"new_state": PawnState.MAISON,
		# Index (ring) de la case dont la barrière a causé un rejet, ou -1 si le
		# rejet n'est pas lié à une barrière — voir board_flag_manager.gd, qui
		# s'en sert pour faire clignoter le bouclier de la case concernée.
		"blocking_ring_index": -1,
	}

## Valide (sans muter l'état) le déplacement de `pawn` avec la valeur `dice_value`.
## Couvre : sortie du yard (§4.2), transit/atterrissage sur barrière — anneau
## (§6.3) et home lane, capture (§8.1-8.2), dépassement en home lane (H4/H5, L9),
## entrée en home lane (L5), évasion de zone de capture.
static func try_move(pawn: Dictionary, dice_value: int, all_pawns: Array) -> Dictionary:
	if pawn.state == PawnState.FINI:
		return _empty_result("pawn_already_finished")

	# --- Cas 0 : pion retenu dans une zone de capture — nécessite un 6 pour
	# s'évader, mais retourne dans SON PROPRE yard (MAISON), pas directement
	# sur l'anneau. Aucune vérification de barrière/occupation : un yard
	# privé n'est jamais contesté (contrairement à la sortie de yard normale
	# ci-dessous, qui elle atterrit sur l'anneau partagé).
	if pawn.state == PawnState.CAPTURED:
		if dice_value != BoardConfig.ENTRY_DICE_VALUE:
			return _empty_result("needs_six_to_escape_capture")
		var result: Dictionary = _empty_result("")
		result.legal = true
		# _empty_result() donne déjà new_state=MAISON, new_progress=-1.
		return result

	# --- Cas 1 : pion au yard (MAISON) — nécessite un 6 pour entrer (§4.2) ---
	if pawn.state == PawnState.MAISON:
		if dice_value != BoardConfig.ENTRY_DICE_VALUE:
			return _empty_result("needs_six_to_enter")

		var start_index: int = get_start_tile_index(pawn.player)
		var barrier_owner: int = get_barrier_owner_at(start_index, all_pawns)

		# B1/B2 : une barrière ennemie sur la start tile bloque l'entrée.
		if barrier_owner != -1 and barrier_owner != pawn.player:
			var blocked: Dictionary = _empty_result("start_tile_blocked_by_enemy_barrier")
			blocked.blocking_ring_index = start_index
			return blocked

		var occupants: Array = get_pawns_on_ring_index(start_index, all_pawns)
		var result: Dictionary = _empty_result("")
		result.legal = true
		result.new_progress = 0
		result.new_state = PawnState.RING

		# §8.2 : capture possible si un unique pion adverse occupe la start tile.
		var enemy_occupants: Array = occupants.filter(func(p): return p.player != pawn.player)
		if enemy_occupants.size() == 1 and barrier_owner == -1:
			result.capture = true
			result.captured_pawn = enemy_occupants[0]

		# B4 : la case comptera >=2 pions alliés après l'entrée -> barrière.
		var ally_occupants: Array = occupants.filter(func(p): return p.player == pawn.player)
		if ally_occupants.size() + 1 >= BoardConfig.BARRIER_MIN_PAWNS:
			result.forms_barrier = true

		return result

	# --- Cas 2 : pion en jeu (RING ou HOME_LANE) ---
	var start_progress: int = pawn.progress
	var target_progress: int = start_progress + dice_value

	# H4 / L9 : dépassement du centre — mouvement refusé, dé inutilisable.
	if target_progress > BoardConfig.FINISH_PROGRESS:
		return _empty_result("overshoot_home_center")

	# --- Vérification des cases intermédiaires (transit), anneau OU home lane ---
	# Les intermédiaires vont de start_progress+1 à target_progress-1 (le dernier
	# pas, target_progress, est traité séparément comme "atterrissage"). Une
	# barrière en home lane bloque aussi le transit — comme sur l'anneau
	# (B1/B2/B6) — mais elle n'y est jamais qu'alliée (case privée par joueur, §7).
	for intermediate_progress in range(start_progress + 1, target_progress):
		if intermediate_progress <= BoardConfig.HOME_ENTRY_PROGRESS - 1:
			var offset: int = BoardConfig.get_player_offset(pawn.player)
			var inter_ring_index: int = (offset + intermediate_progress) % BoardConfig.RING_SIZE
			if is_barrier_at(inter_ring_index, all_pawns):
				# B1/B2/B6 : aucune barrière (alliée ou ennemie) n'est traversable.
				var blocked: Dictionary = _empty_result("path_blocked_by_barrier")
				blocked.blocking_ring_index = inter_ring_index
				return blocked
		elif is_home_lane_barrier_at(pawn.player, intermediate_progress, all_pawns):
			# Barrière (toujours alliée) sur une case de home lane traversée :
			# bloque le transit exactement comme sur l'anneau. Pas de ring_index
			# pertinent ici (case de home lane, privée, hors de l'anneau public).
			return _empty_result("path_blocked_by_barrier")

	var result: Dictionary = _empty_result("")
	result.legal = true

	# --- Atterrissage en home lane (target_progress >= HOME_ENTRY_PROGRESS) ---
	if target_progress >= BoardConfig.HOME_ENTRY_PROGRESS:
		result.enters_home = (start_progress < BoardConfig.HOME_ENTRY_PROGRESS)
		result.new_progress = target_progress
		if target_progress == BoardConfig.FINISH_PROGRESS:
			result.finishes = true
			result.new_state = PawnState.FINI
			# La case FINI (56) n'est pas une case de home lane (PawnState.FINI,
			# pas HOME_LANE) : elle ne peut jamais accumuler de "barrière".
		else:
			result.new_state = PawnState.HOME_LANE
			# Atterrissage TOUJOURS autorisé (case privée, jamais de barrière
			# ennemie possible ici) ; s'il porte le compte à
			# >= BARRIER_MIN_PAWNS, il forme/renforce une barrière alliée,
			# comme B6 sur l'anneau.
			var home_occupants: int = _count_home_lane_occupants(pawn.player, target_progress, all_pawns)
			if home_occupants + 1 >= BoardConfig.BARRIER_MIN_PAWNS:
				result.forms_barrier = true
		# H3 : pas de capture en home lane (case privée, pas d'adversaire
		# possible) ; une barrière peut désormais s'y former mais elle ne
		# bloque jamais l'atterrissage, seulement le transit d'autres pions.
		return result

	# --- Atterrissage sur la ring lane ---
	var offset: int = BoardConfig.get_player_offset(pawn.player)
	var landing_index: int = (offset + target_progress) % BoardConfig.RING_SIZE
	var barrier_owner: int = get_barrier_owner_at(landing_index, all_pawns)

	if barrier_owner != -1 and barrier_owner != pawn.player:
		# B2 : atterrissage interdit sur une barrière ennemie.
		var blocked: Dictionary = _empty_result("landing_blocked_enemy_barrier")
		blocked.blocking_ring_index = landing_index
		return blocked

	result.new_progress = target_progress
	result.new_state = PawnState.RING

	if barrier_owner == pawn.player:
		# B6 : atterrissage autorisé sur sa propre barrière (elle grandit simplement).
		result.forms_barrier = true
		return result

	# Pas de barrière sur la case cible : vérifier capture (§8.1) ou formation (B4).
	var occupants: Array = get_pawns_on_ring_index(landing_index, all_pawns)
	var enemy_occupants: Array = occupants.filter(func(p): return p.player != pawn.player)
	var ally_occupants: Array = occupants.filter(func(p): return p.player == pawn.player)

	if enemy_occupants.size() == 1:
		result.capture = true
		result.captured_pawn = enemy_occupants[0]
	elif enemy_occupants.size() >= 2:
		# Ne devrait pas arriver (aurait été détecté comme barrière ennemie ci-dessus),
		# gardé par sécurité défensive.
		return _empty_result("landing_blocked_enemy_barrier")

	if ally_occupants.size() + 1 >= BoardConfig.BARRIER_MIN_PAWNS:
		result.forms_barrier = true

	return result


# ----------------------------------------------------------------------------
# 4. APPLICATION D'UN MOUVEMENT (mutation d'état)
# ----------------------------------------------------------------------------

## Applique le mouvement si légal : mute `pawn` et, le cas échéant, le pion capturé.
## Retourne le même Dictionary que try_move() (avec "legal" indiquant le succès).
## Ne mute RIEN si le mouvement est illégal.
static func apply_move(pawn: Dictionary, dice_value: int, all_pawns: Array) -> Dictionary:
	var result: Dictionary = try_move(pawn, dice_value, all_pawns)
	if not result.legal:
		return result

	pawn.state = result.new_state
	pawn.progress = result.new_progress

	# Évasion de zone de capture (cf. try_move Cas 0) : le pion redevient un
	# pion de yard normal, il ne retient plus son ancien capteur.
	if pawn.state == PawnState.MAISON:
		pawn.captor_id = -1

	if result.capture:
		var victim: Dictionary = result.captured_pawn
		victim.state = PawnState.CAPTURED
		victim.progress = -1
		victim.captor_id = pawn.player
		# NOTE (§8.3, R4) : le verrouillage du pion capturant pour le reste du tour
		# n'est PAS géré ici (le RuleEngine reste sans état de "tour"). C'est au
		# TurnManager d'ajouter pawn.id à sa liste `locked_pawn_ids` en lisant
		# result.capture == true, puis de la transmettre aux appels suivants de
		# get_legal_target_pawns() / has_any_legal_move() (voir §9, L10).

	return result


# ----------------------------------------------------------------------------
# 5. REQUÊTES POUR LA MACHINE À ÉTATS (VÉRIFIER_ACTIONS, cas limites L1-L8, L13)
# ----------------------------------------------------------------------------

## Tous les pions d'un joueur pouvant légalement jouer `dice_value`,
## en excluant les pions verrouillés par une capture ce tour-ci (§8.3, L10).
## Retourne un Array de Dictionary : { "pawn": Dictionary, "preview": Dictionary (résultat try_move) }
static func get_legal_target_pawns(
	player_id: int,
	all_pawns: Array,
	dice_value: int,
	locked_pawn_ids: Array = []
) -> Array:
	var legal: Array = []
	for pawn in all_pawns:
		if pawn.player != player_id:
			continue
		if pawn.id in locked_pawn_ids:
			continue
		if pawn.state == PawnState.FINI:
			continue
		var preview: Dictionary = try_move(pawn, dice_value, all_pawns)
		if preview.legal:
			legal.append({"pawn": pawn, "preview": preview})
	return legal

## L2/L3/L4/L7/L8 : vrai si le joueur a au moins un coup légal, tous les dés
## du pool confondus (dédupliqué par valeur — inutile de tester deux fois la
## même valeur si plusieurs dés du pool la partagent).
static func has_any_legal_move(
	player_id: int,
	all_pawns: Array,
	dice_values: Array,
	locked_pawn_ids: Array = []
) -> bool:
	var seen := {}
	for value in dice_values:
		if value in seen:
			continue
		seen[value] = true
		if not get_legal_target_pawns(player_id, all_pawns, value, locked_pawn_ids).is_empty():
			return true
	return false

## Un dé précis est-il injouable pour CE joueur, quel que soit le pion choisi ? (L1, L7, L8)
static func is_dice_value_unusable(
	player_id: int,
	all_pawns: Array,
	dice_value: int,
	locked_pawn_ids: Array = []
) -> bool:
	return get_legal_target_pawns(player_id, all_pawns, dice_value, locked_pawn_ids).is_empty()


# ----------------------------------------------------------------------------
# 6. VICTOIRE (§2.3, §7.6, L12)
# ----------------------------------------------------------------------------

static func count_finished_pawns(player_id: int, all_pawns: Array) -> int:
	var count: int = 0
	for pawn in all_pawns:
		if pawn.player == player_id and pawn.state == PawnState.FINI:
			count += 1
	return count

static func has_player_won(player_id: int, all_pawns: Array) -> bool:
	return count_finished_pawns(player_id, all_pawns) == BoardConfig.PAWNS_PER_PLAYER

## Retourne l'id du premier joueur ayant gagné, ou -1 si personne n'a encore gagné.
## Utilisé en mode GameEndMode.FIRST_TO_FINISH, y compris pendant un extra turn (L12).
## `active_players` : sièges participant à la partie en cours (voir BoardManager.active_players).
static func check_victory(all_pawns: Array, active_players: Array[int]) -> int:
	for player_id in active_players:
		if has_player_won(player_id, all_pawns):
			return player_id
	return -1


# ----------------------------------------------------------------------------
# 7. VALIDATION DE SCÉNARIO MANUEL (mode test, voir ui/scenario/scenario_setup.gd)
# ----------------------------------------------------------------------------
#
# Ce mode permet de positionner les pions "à la main" (hors de tout coup joué)
# pour tester un scénario précis. Ces fonctions ne valident QUE la cohérence
# interne d'une entrée (state/progress/captor_id), pas les règles de jeu
# habituelles (barrière, capture...) — c'est un outil de dev, pas un nouveau
# chemin de jeu validé.

## Une entrée de scénario : {"id", "state", "progress", "captor_id"}.
static func is_progress_valid_for_state(state: int, progress: int) -> bool:
	match state:
		PawnState.MAISON, PawnState.CAPTURED:
			return progress == -1
		PawnState.RING:
			return progress >= 0 and progress < BoardConfig.HOME_ENTRY_PROGRESS
		PawnState.HOME_LANE:
			return progress >= BoardConfig.HOME_ENTRY_PROGRESS and progress < BoardConfig.FINISH_PROGRESS
		PawnState.FINI:
			return progress == BoardConfig.FINISH_PROGRESS
	return false

## Retourne une chaîne d'erreur si `entry` est incohérente, "" sinon.
static func validate_scenario_pawn(entry: Dictionary) -> String:
	if not is_progress_valid_for_state(entry.state, entry.progress):
		return "progress=%s incohérent avec state=%s" % [entry.progress, PawnState.find_key(entry.state)]
	if entry.state == PawnState.CAPTURED and (entry.captor_id < 0 or entry.captor_id >= BoardConfig.PLAYER_COUNT):
		return "captor_id=%s invalide pour un pion CAPTURED" % entry.captor_id
	return ""

## Vérifications croisées sur un plateau déjà appliqué (all_pawns complets,
## avec "player") : signale les cas qu'un coup normal ne produirait jamais
## (3 joueurs ou plus empilés sur la même case d'anneau), sans bloquer —
## juste un avertissement affiché au testeur.
static func validate_scenario(all_pawns: Array) -> Array[String]:
	var warnings: Array[String] = []
	for ring_index in range(BoardConfig.RING_SIZE):
		var distinct_players := {}
		for p in get_pawns_on_ring_index(ring_index, all_pawns):
			distinct_players[p.player] = true
		if distinct_players.size() > 2:
			warnings.append("Case anneau %d : %d joueurs différents empilés." % [ring_index, distinct_players.size()])
	return warnings


# ----------------------------------------------------------------------------
# 8. FILET ANTI-GÂCHIS DU POOL DE DÉS (règle maison)
# ----------------------------------------------------------------------------
#
# Règle (révisée) : le joueur choisit LIBREMENT quel dé du pool jouer sur quel
# pion — il n'y a plus d'ordre imposé automatiquement (TurnManager.select_die()
# laisse le joueur cliquer n'importe quel dé encore jouable). La seule
# automatisation restante : si jouer le dé choisi sur le pion choisi
# verrouillerait le pion (capture, §8.3/L10) et rendrait ainsi UN SEUL autre
# dé du pool injouable par tout autre pion, ALORS QU'un mouvement combiné
# (les deux dés en un seul coup sur ce même pion, sans capturer/verrouiller
# sur la case intermédiaire) l'évite, ce mouvement combiné est joué à la
# place — voir find_wasted_die_id() + TurnManager._resolve_die_pawn_choice().
# Si aucun mouvement combiné ne sauve le dé, ou si le choix du joueur ne gâche
# rien, on joue simplement le coup tel quel : la perte d'un dé n'est acceptée
# que quand elle est inévitable ou ambiguë (plusieurs dés gâchés à la fois).

## Clone superficiel d'un tableau de pions (Dictionary de champs primitifs
## uniquement — un `duplicate()` peu profond suffit, pas de structure imbriquée).
static func _clone_pawns(all_pawns: Array) -> Array:
	var cloned: Array = []
	for p in all_pawns:
		cloned.append(p.duplicate())
	return cloned

## true si jouer le pion `pawn_id` avec `value_now` (sur un CLONE, sans muter
## `all_pawns`) laisse au moins un coup légal pour `value_next` ensuite — en
## reproduisant le verrouillage post-capture (§8.3/L10) dans la simulation.
static func _would_still_be_playable(
	player_id: int,
	all_pawns: Array,
	pawn_id: int,
	value_now: int,
	value_next: int,
	locked_pawn_ids: Array
) -> bool:
	var cloned: Array = _clone_pawns(all_pawns)
	var cloned_pawn: Dictionary = {}
	for p in cloned:
		if p.id == pawn_id:
			cloned_pawn = p
			break
	var cloned_locked: Array = locked_pawn_ids.duplicate()
	var result: Dictionary = apply_move(cloned_pawn, value_now, cloned)
	if result.capture:
		cloned_locked.append(cloned_pawn.id)
	return not get_legal_target_pawns(player_id, cloned, value_next, cloned_locked).is_empty()

## Après que le joueur a choisi de jouer `chosen_value` sur `pawn_id`, indique
## si EXACTEMENT UN AUTRE dé du pool restant (`other_dice`, Array de
## {"id":int,"value":int}) serait rendu injouable par tout pion suite à ce
## choix. Retourne l'id de ce dé, ou -1 si aucun dé n'est gâché OU si
## PLUSIEURS dés seraient gâchés simultanément (cas ambigu : on ne devine pas
## lequel sauver via un mouvement combiné à 2 dés, on joue normalement et on
## assume la perte).
static func find_wasted_die_id(
	player_id: int,
	all_pawns: Array,
	pawn_id: int,
	chosen_value: int,
	other_dice: Array,
	locked_pawn_ids: Array
) -> int:
	var wasted_ids: Array = []
	for entry in other_dice:
		if not _would_still_be_playable(player_id, all_pawns, pawn_id, chosen_value, entry.value, locked_pawn_ids):
			wasted_ids.append(entry.id)
	if wasted_ids.size() == 1:
		return wasted_ids[0]
	return -1


## Combine "sortie de yard" + "continuation avec le second dé" en UN SEUL
## mouvement : le pion n'atterrit JAMAIS sur la start tile (progress 0), il la
## traverse comme une case de transit normale (aucune capture ; seule une
## barrière — alliée OU ennemie, comme toute case de transit — y bloquerait
## le passage) et n'atterrit réellement qu'à
## `continuation = (value_a + value_b) - ENTRY_DICE_VALUE` cases plus loin.
## `continuation` ∈ [1,6] toujours (un dé vaut exactement 6, l'autre 1-6),
## donc jamais besoin de gérer l'entrée en couloir final ici.
static func _try_combined_yard_exit(pawn: Dictionary, value_a: int, value_b: int, all_pawns: Array) -> Dictionary:
	if value_a != BoardConfig.ENTRY_DICE_VALUE and value_b != BoardConfig.ENTRY_DICE_VALUE:
		return _empty_result("needs_six_to_enter")
	var continuation: int = (value_a + value_b) - BoardConfig.ENTRY_DICE_VALUE
	if continuation < 1:
		return _empty_result("invalid_combined_distance")

	var offset: int = BoardConfig.get_player_offset(pawn.player)
	var start_index: int = offset  # = get_start_tile_index(pawn.player), progress 0

	# La start tile est ici une case de TRANSIT, pas un atterrissage — TOUTE
	# barrière (alliée ou ennemie) y bloque le passage, comme n'importe quelle
	# case de transit (cf. Cas 2 de try_move(), "aucune barrière, alliée ou
	# ennemie, n'est traversable"). Ne PAS se limiter à "barrière ennemie"
	# (ce serait la règle d'ATTERRISSAGE, pas de transit).
	if is_barrier_at(start_index, all_pawns):
		var blocked_start: Dictionary = _empty_result("path_blocked_by_barrier")
		blocked_start.blocking_ring_index = start_index
		return blocked_start

	# Transit (progress 1..continuation-1).
	for intermediate_progress in range(1, continuation):
		var inter_ring_index: int = (offset + intermediate_progress) % BoardConfig.RING_SIZE
		if is_barrier_at(inter_ring_index, all_pawns):
			var blocked_inter: Dictionary = _empty_result("path_blocked_by_barrier")
			blocked_inter.blocking_ring_index = inter_ring_index
			return blocked_inter

	# Atterrissage final (identique à la logique d'atterrissage normale de Cas 2).
	var landing_index: int = (offset + continuation) % BoardConfig.RING_SIZE
	var barrier_owner: int = get_barrier_owner_at(landing_index, all_pawns)
	if barrier_owner != -1 and barrier_owner != pawn.player:
		var blocked_landing: Dictionary = _empty_result("landing_blocked_enemy_barrier")
		blocked_landing.blocking_ring_index = landing_index
		return blocked_landing

	var result: Dictionary = _empty_result("")
	result.legal = true
	result.new_progress = continuation
	result.new_state = PawnState.RING

	if barrier_owner == pawn.player:
		result.forms_barrier = true
		return result

	var occupants: Array = get_pawns_on_ring_index(landing_index, all_pawns)
	var enemy_occupants: Array = occupants.filter(func(p): return p.player != pawn.player)
	var ally_occupants: Array = occupants.filter(func(p): return p.player == pawn.player)
	if enemy_occupants.size() == 1:
		result.capture = true
		result.captured_pawn = enemy_occupants[0]
	elif enemy_occupants.size() >= 2:
		return _empty_result("landing_blocked_enemy_barrier")
	if ally_occupants.size() + 1 >= BoardConfig.BARRIER_MIN_PAWNS:
		result.forms_barrier = true
	return result


## Prévisualise un mouvement combiné (les deux dés d'un coup, pour un même
## pion) — voir find_wasted_die_id() / TurnManager._resolve_die_pawn_choice().
## Pour un pion déjà en jeu (RING/HOME_LANE), c'est simplement try_move() avec la somme des deux
## dés : le comportement normal d'un grand déplacement (transit = seules les
## barrières bloquent, capture/formation de barrière uniquement à la case
## finale) est déjà exactement ce qu'il faut. Seul le cas MAISON (sortie de
## yard) a besoin d'une logique dédiée (_try_combined_yard_exit), car
## try_move() exige `dice_value == ENTRY_DICE_VALUE` et atterrit toujours en
## progress 0.
static func try_combined_move(pawn: Dictionary, value_a: int, value_b: int, all_pawns: Array) -> Dictionary:
	if pawn.state == PawnState.MAISON:
		return _try_combined_yard_exit(pawn, value_a, value_b, all_pawns)
	return try_move(pawn, value_a + value_b, all_pawns)


## Applique un mouvement combiné validé par try_combined_move() : mute `pawn`
## (et la victime éventuelle). Même contrat que apply_move().
static func apply_combined_move(pawn: Dictionary, value_a: int, value_b: int, all_pawns: Array) -> Dictionary:
	if pawn.state == PawnState.MAISON:
		var result: Dictionary = _try_combined_yard_exit(pawn, value_a, value_b, all_pawns)
		if not result.legal:
			return result
		pawn.state = result.new_state
		pawn.progress = result.new_progress
		if result.capture:
			var victim: Dictionary = result.captured_pawn
			victim.state = PawnState.CAPTURED
			victim.progress = -1
			victim.captor_id = pawn.player
		return result
	return apply_move(pawn, value_a + value_b, all_pawns)
