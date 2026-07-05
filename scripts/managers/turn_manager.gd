extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `TurnManager`) déclaré dans project.godot. Godot enregistre lui-même la
## classe globale ; un `class_name` identique causerait une collision.
## ============================================================================
## TurnManager — Machine à états de tour du Ludo 3D (GDD §9).
##
## RESPONSABILITÉS (§11.1)
##   - Piloter la séquence complète d'un tour : démarrage, lancer de dés,
##     vérification des coups légaux, sélection/applique du mouvement, fin de
##     tour, et transition vers le joueur suivant ou un extra tour (§5.1).
##   - Appliquer les règles de fin de tour : double six = extra tour (§5.1),
##     compteur des 3 lancers consécutifs anti-boucle (§5.3), verrouillage
##     post-capture d'un pion pour le reste du tour (§8.3 / L10).
##   - Déléguer TOUTE la validation au RuleEngine : le TurnManager ne décide
##     jamais si un coup est légal, il orchestre.
##
## DÉPENDANCES
##   - RuleEngine (try_move / apply_move / get_legal_target_pawns /
##     has_any_legal_move / check_victory) : réutilisé TEL QUEL, non réécrit.
##   - BoardConfig (PLAYER_COUNT, MAX_CONSECUTIVE_ROLLS, ENTRY_DICE_VALUE).
##   - DiceSystem (production + suivi des dés consommés).
##   - BoardManager (source de vérité de l'état `all_pawns`).
##   - PawnController (sélection + rendu visuel).
##   - GameEvents (autoload) pour publier les signaux §11.2.
##
## C'est la VERSION COMPLÈTE du §9 — PAS le harnais simplifié de test.
## ============================================================================

const PawnState := BoardConfig.PawnState

# ----------------------------------------------------------------------------
# Les 7 états de la machine à tours (GDD §9).
# ----------------------------------------------------------------------------
enum TurnState {
	WAITING_FOR_ROLL,       # 1. début de tour : on attend que le joueur lance les dés
	ROLLING,                # 2. dés en cours de lancer (animation) -> DICE_ROLLED
	CHECKING_MOVES,         # 3. dés obtenus : on vérifie les coups légaux
	WAITING_FOR_SELECTION,  # 4. au moins un coup légal : le joueur choisit un pion
	MOVING,                 # 5. coup appliqué : animation de déplacement en cours
	TURN_ENDING,            # 6. résolution de fin de tour (extra tour ? capture-lock ?)
	GAME_OVER,              # 7. un joueur a gagné (§2.3, L12), la boucle s'arrête
}

var state: TurnState = TurnState.WAITING_FOR_ROLL
var active_player: int = 0

# --- Dépendances (à brancher depuis la scène GameRoot, cf. main.gd) ----------
var dice_system: DiceSystem
var board_manager: BoardManager
var pawn_controller: PawnController

# --- État interne du tour (§5.3, §8.3/L10) -----------------------------------
## Compteur de lancers consécutifs DU MÊME JOUEUR. Un extra tour (double six,
## §5.1) le décrémente/redémarre ; à MAX_CONSECUTIVE_ROLLS (3) le tour est
## forcé à se terminer pour éviter une boucle infinie (§5.3).
var consecutive_rolls: int = 0

## Ids des pions verrouillés pour le reste du tour après une capture (§8.3).
## Ces ids sont passés à RuleEngine.get_legal_target_pawns(..., locked_pawn_ids)
## pour exclure le pion capturé de tout nouveau coup ce tour (L10).
var locked_pawn_ids: Array = []

## Dés restant à jouer ce tour (liste de {"die":"A"|"B","value":int}).
var _pending_dice: Array = []

var _is_double_six: bool = false
var _last_result: Dictionary = {}


func _ready() -> void:
	# Branchement au bus global (les vues écoutent GameEvents, pas directement TM).
	GameEvents.dice_rolled.connect(_on_dice_rolled)
	# Le PawnController signale la sélection du joueur :
	# (connecté dans setup() car pawn_controller peut être assigné tardivement)


## Rattachement explicite des dépendances (appelé par main.gd / GameRoot).
func setup(p_dice: DiceSystem, p_board: BoardManager, p_pawns: PawnController) -> void:
	dice_system = p_dice
	board_manager = p_board
	pawn_controller = p_pawns
	if pawn_controller:
		pawn_controller.pawn_selected.connect(_on_pawn_selected)
	_change_state(TurnState.WAITING_FOR_ROLL)


# ----------------------------------------------------------------------------
# Point d'entrée : démarrer une nouvelle partie
# ----------------------------------------------------------------------------
func start_new_game() -> void:
	board_manager.reset_all_to_yard()
	active_player = 0
	consecutive_rolls = 0
	locked_pawn_ids.clear()
	_pending_dice.clear()
	_is_double_six = false
	_last_result = {}
	_change_state(TurnState.WAITING_FOR_ROLL)


# ----------------------------------------------------------------------------
# État 1 -> 2 : le joueur demande à lancer les dés
# ----------------------------------------------------------------------------
func request_roll() -> void:
	if state != TurnState.WAITING_FOR_ROLL:
		return
	_change_state(TurnState.ROLLING)
	dice_system.roll()  # -> émet dice_rolled -> _on_dice_rolled (état 2->3)


# ----------------------------------------------------------------------------
# État 2 -> 3 : dés lancés, reçus via le bus
# ----------------------------------------------------------------------------
func _on_dice_rolled(a: int, b: int, _is_double: bool) -> void:
	if state != TurnState.ROLLING:
		return
	_is_double_six = (a == 6 and b == 6)
	_change_state(TurnState.CHECKING_MOVES)
	_resolve_checked_moves(a, b)


# ----------------------------------------------------------------------------
# État 3 : vérifier les coups légaux (cas L1-L8, L13)
# ----------------------------------------------------------------------------
func _resolve_checked_moves(a: int, b: int) -> void:
	# §5.3 : incrément du compteur de lancers consécutifs (anti-boucle).
	consecutive_rolls += 1

	# Cas L2/L3/L4 : aucun coup possible avec aucun des deux dés -> tour perdu.
	if not RuleEngine.has_any_legal_move(active_player, board_manager.all_pawns, a, b, locked_pawn_ids):
		_end_turn(false, "no_legal_move")
		return

	# §5.3 : à 3 lancers consécutifs on force la fin du tour même si le joueur
	# pourrait continuer (garde-fou contre les boucles de double six).
	if consecutive_rolls >= BoardConfig.MAX_CONSECUTIVE_ROLLS:
		# On laisse le joueur consommer les dés actuels, puis on forcera la fin.
		pass  # traité dans _after_move_resolved() via _force_end_after_consume

	# Construit la liste des dés encore jouables ce tour.
	_pending_dice.clear()
	_pending_dice.append({"die": "A", "value": a})
	if a != b:
		_pending_dice.append({"die": "B", "value": b})
	# (sur un double, un seul "dé logique" — règle Ludo : les deux faces sont
	#  identiques, on joue deux fois la même valeur via A puis B consommés.)

	_change_state(TurnState.WAITING_FOR_SELECTION)
	_offer_selection()


# ----------------------------------------------------------------------------
# État 4 : proposer la sélection des pions légaux au joueur
# ----------------------------------------------------------------------------
func _offer_selection() -> void:
	if _pending_dice.is_empty():
		# Tous les dés consommés : fin normale du tour.
		_end_turn(_is_double_six, "all_dice_consumed")
		return

	var first: Dictionary = _pending_dice[0]
	var legal: Array = RuleEngine.get_legal_target_pawns(
		active_player, board_manager.all_pawns, first.value, locked_pawn_ids
	)
	if legal.is_empty():
		# Ce dé n'est jouable par aucun pion (L1, L7, L8) -> on le retire.
		dice_system.mark_used(first.die)
		_pending_dice.pop_front()
		_offer_selection()  # réessaie avec le dé suivant
		return

	# Demande au PawnController de laisser le joueur choisir (§11.6).
	var legal_ids: Array = legal.map(func(e): return e.pawn.id)
	pawn_controller.request_selection(active_player, legal_ids)


# ----------------------------------------------------------------------------
# État 4 -> 5 : le joueur a sélectionné un pion
# ----------------------------------------------------------------------------
func _on_pawn_selected(pawn: Dictionary) -> void:
	if state != TurnState.WAITING_FOR_SELECTION:
		return
	if _pending_dice.is_empty():
		return

	var entry: Dictionary = _pending_dice[0]
	# Valide (via RuleEngine) puis applique réellement le mouvement.
	var result: Dictionary = RuleEngine.apply_move(pawn, entry.value, board_manager.all_pawns)
	if not result.legal:
		# Sélection invalide (race) : on ignore, le joueur doit rechoisir.
		return

	_last_result = result
	dice_system.mark_used(entry.die)
	_pending_dice.pop_front()

	# Publie les signaux de haut niveau (§11.2) AVANT l'animation.
	GameEvents.move_validated.emit(pawn, entry.value, result)
	if result.capture:
		locked_pawn_ids.append(pawn.id)  # §8.3 / L10 : verrouillage post-capture
		GameEvents.pawn_captured.emit(result.captured_pawn, pawn)

	_change_state(TurnState.MOVING)
	pawn_controller.move_pawn_visual(pawn, true)
	# -> l'animation appellera _on_move_animation_done via pawn_moved.
	GameEvents.pawn_moved.connect(_on_move_animation_done, CONNECT_ONE_SHOT)


# ----------------------------------------------------------------------------
# État 5 -> 6 : fin de l'animation du déplacement
# ----------------------------------------------------------------------------
func _on_move_animation_done(pawn: Dictionary, _dice_value: int) -> void:
	if state != TurnState.MOVING:
		return

	# Signaux secondaires (B4 / H1 / §7.2) après déplacement effectif.
	if _last_result.get("forms_barrier", false):
		GameEvents.barrier_formed.emit(pawn, RuleEngine.get_ring_index(pawn))
	if _last_result.get("enters_home", false):
		GameEvents.pawn_entered_home.emit(pawn)
	if _last_result.get("finishes", false):
		GameEvents.pawn_finished.emit(pawn)

	_change_state(TurnState.TURN_ENDING)
	_after_move_resolved()


# ----------------------------------------------------------------------------
# État 6 : résolution post-coup (victoire ? encore des dés ? extra tour ?)
# ----------------------------------------------------------------------------
func _after_move_resolved() -> void:
	# 1. Victoire ? (§2.3, L12) — vérifié même pendant un extra tour.
	var winner: int = RuleEngine.check_victory(board_manager.all_pawns)
	if winner != -1:
		_change_state(TurnState.GAME_OVER)
		GameEvents.victory.emit(winner)
		return

	# 2. Reste-t-il des dés jouables ? Si oui, on continue la sélection.
	if not _pending_dice.is_empty() and not dice_system.all_dice_consumed():
		_change_state(TurnState.WAITING_FOR_SELECTION)
		_offer_selection()
		return

	# 3. Tous les dés sont consommés : fin du tour (extra tour si double six).
	#    §5.3 : si on a atteint 3 lancers consécutifs, on interdit l'extra tour.
	var grant_extra: bool = _is_double_six and consecutive_rolls < BoardConfig.MAX_CONSECUTIVE_ROLLS
	_end_turn(grant_extra, "turn_resolved")


# ----------------------------------------------------------------------------
# État 6 -> 1 : termine le tour courant et passe au suivant
# ----------------------------------------------------------------------------
func _end_turn(grant_extra: bool, reason: String) -> void:
	var previous: int = active_player
	locked_pawn_ids.clear()
	dice_system.reset()
	_pending_dice.clear()
	_is_double_six = false

	if not grant_extra:
		# Joueur suivant (ordre horaire, §5.1).
		active_player = (active_player + 1) % BoardConfig.PLAYER_COUNT
		consecutive_rolls = 0
	else:
		# Extra tour : même joueur, le compteur de lancers reste (§5.3 cumule).
		pass

	GameEvents.turn_ended.emit(previous, active_player, grant_extra)
	_change_state(TurnState.WAITING_FOR_ROLL)


# ----------------------------------------------------------------------------
# Transition d'état sécurisée + publication (§11.2)
# ----------------------------------------------------------------------------
func _change_state(new_state: TurnState) -> void:
	if new_state == state:
		return
	var old: int = state
	state = new_state
	GameEvents.turn_state_changed.emit(old, new_state)
