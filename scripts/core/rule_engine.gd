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
##     "progress": int,             # -1 (yard) ou 0..FINISH_PROGRESS
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
	}

## Valide (sans muter l'état) le déplacement de `pawn` avec la valeur `dice_value`.
## Couvre : sortie du yard (§4.2), transit/atterrissage sur barrière (§6.3),
## capture (§8.1-8.2), dépassement en home lane (H4/H5, L9), entrée en home lane (L5).
static func try_move(pawn: Dictionary, dice_value: int, all_pawns: Array) -> Dictionary:
	if pawn.state == PawnState.FINI:
		return _empty_result("pawn_already_finished")

	# --- Cas 1 : pion au yard (MAISON) — nécessite un 6 pour entrer (§4.2) ---
	if pawn.state == PawnState.MAISON:
		if dice_value != BoardConfig.ENTRY_DICE_VALUE:
			return _empty_result("needs_six_to_enter")

		var start_index: int = get_start_tile_index(pawn.player)
		var barrier_owner: int = get_barrier_owner_at(start_index, all_pawns)

		# B1/B2 : une barrière ennemie sur la start tile bloque l'entrée.
		if barrier_owner != -1 and barrier_owner != pawn.player:
			return _empty_result("start_tile_blocked_by_enemy_barrier")

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

	# --- Vérification des cases intermédiaires (transit), hors home lane (§7.5) ---
	# Les intermédiaires vont de start_progress+1 à target_progress-1 (le dernier
	# pas, target_progress, est traité séparément comme "atterrissage").
	for intermediate_progress in range(start_progress + 1, target_progress):
		if intermediate_progress <= BoardConfig.HOME_ENTRY_PROGRESS - 1:
			var offset: int = BoardConfig.get_player_offset(pawn.player)
			var inter_ring_index: int = (offset + intermediate_progress) % BoardConfig.RING_SIZE
			if is_barrier_at(inter_ring_index, all_pawns):
				# B1/B2/B6 : aucune barrière (alliée ou ennemie) n'est traversable.
				return _empty_result("path_blocked_by_barrier")
		# Sinon : case intermédiaire en home lane -> pas de barrière possible (§7.5), on ignore.

	var result: Dictionary = _empty_result("")
	result.legal = true

	# --- Atterrissage en home lane (target_progress >= HOME_ENTRY_PROGRESS) ---
	if target_progress >= BoardConfig.HOME_ENTRY_PROGRESS:
		result.enters_home = (start_progress < BoardConfig.HOME_ENTRY_PROGRESS)
		result.new_progress = target_progress
		if target_progress == BoardConfig.FINISH_PROGRESS:
			result.finishes = true
			result.new_state = PawnState.FINI
		else:
			result.new_state = PawnState.HOME_LANE
		# H3 : pas de capture, pas de barrière possible en home lane.
		return result

	# --- Atterrissage sur la ring lane ---
	var offset: int = BoardConfig.get_player_offset(pawn.player)
	var landing_index: int = (offset + target_progress) % BoardConfig.RING_SIZE
	var barrier_owner: int = get_barrier_owner_at(landing_index, all_pawns)

	if barrier_owner != -1 and barrier_owner != pawn.player:
		# B2 : atterrissage interdit sur une barrière ennemie.
		return _empty_result("landing_blocked_enemy_barrier")

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

	if result.capture:
		var victim: Dictionary = result.captured_pawn
		victim.state = PawnState.MAISON
		victim.progress = -1
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

## L2/L3/L4/L7/L8 : vrai si le joueur a au moins un coup légal, tous dés confondus.
static func has_any_legal_move(
	player_id: int,
	all_pawns: Array,
	dice_a: int,
	dice_b: int,
	locked_pawn_ids: Array = []
) -> bool:
	if not get_legal_target_pawns(player_id, all_pawns, dice_a, locked_pawn_ids).is_empty():
		return true
	if dice_a != dice_b:
		if not get_legal_target_pawns(player_id, all_pawns, dice_b, locked_pawn_ids).is_empty():
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
static func check_victory(all_pawns: Array) -> int:
	for player_id in range(BoardConfig.PLAYER_COUNT):
		if has_player_won(player_id, all_pawns):
			return player_id
	return -1
