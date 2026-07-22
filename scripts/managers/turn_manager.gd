extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `TurnManager`) déclaré dans project.godot. Godot enregistre lui-même la
## classe globale ; un `class_name` identique causerait une collision.
## ============================================================================
## TurnManager — Machine à états de tour du Ludo 3D (GDD §9).
##
## RESPONSABILITÉS (§11.1)
##   - Piloter la séquence complète d'un tour : démarrage, enchaînement de
##     lancers de dés (§5.1), constitution du pool de dés, sélection/applique
##     du mouvement (choisi librement par le joueur, dé PUIS pion), fin de
##     tour, et transition vers le joueur suivant.
##   - Appliquer les règles de lancer : un double six déclenche un DROIT à une
##     relance, dont les valeurs rejoignent le même pool — mais c'est le
##     joueur qui la déclenche lui-même (bouton "Relancer", état
##     WAITING_FOR_REROLL) plutôt qu'une relance automatique, avant tout coup
##     joué ; un 3e double six consécutif annule le tour entier (§5.1/§5.3
##     révisés — voir request_roll()/_roll_once()). Verrouillage post-capture
##     d'un pion pour le reste du tour (§8.3 / L10).
##   - Déléguer TOUTE la validation au RuleEngine : le TurnManager ne décide
##     jamais si un coup est légal, il orchestre.
##
## DÉPENDANCES
##   - RuleEngine (try_move / apply_move / get_legal_target_pawns /
##     has_any_legal_move / find_wasted_die_id / check_victory) : réutilisé
##     TEL QUEL, non réécrit.
##   - BoardConfig (PLAYER_COUNT, MAX_CONSECUTIVE_ROLLS, ENTRY_DICE_VALUE) —
##     MAX_CONSECUTIVE_ROLLS sert désormais aussi de seuil de bust (3e double
##     six consécutif).
##   - DiceSystem (roll_pair() : simple source aléatoire, ne connaît rien du
##     pool — voir dice_system.gd).
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
	ROLLING,                # 2. lancer physique en cours
	WAITING_FOR_REROLL,     # 2b. double six obtenu : on attend que le joueur relance lui-même
	CHECKING_MOVES,         # 3. pool constitué : on vérifie les coups légaux
	WAITING_FOR_SELECTION,  # 4. au moins un coup légal : le joueur choisit un dé PUIS un pion
	MOVING,                 # 5. coup appliqué : animation de déplacement en cours
	TURN_ENDING,            # 6. résolution post-coup (pool vide ? victoire ?)
	GAME_OVER,              # 7. un joueur a gagné (§2.3, L12), la boucle s'arrête
}

var state: TurnState = TurnState.WAITING_FOR_ROLL
var active_player: int = 0

# --- Dépendances (à brancher depuis la scène GameRoot, cf. main.gd) ----------
var dice_system: DiceSystem
var board_manager: BoardManager
var pawn_controller: PawnController

# --- État interne du tour (§5.1, §8.3/L10) -----------------------------------
## Ids des pions verrouillés pour le reste du tour après une capture (§8.3).
## Ces ids sont passés à RuleEngine.get_legal_target_pawns(..., locked_pawn_ids)
## pour exclure le pion capturé de tout nouveau coup ce tour (L10).
var locked_pawn_ids: Array = []

## Pool de dés en attente ce tour : Array de {"id": int, "value": int}.
## Construit lancer physique par lancer physique par _roll_once() — un double
## six ajoute ses 2 valeurs au pool et attend un clic joueur (état
## WAITING_FOR_REROLL) avant le lancer suivant, AVANT tout choix de coup
## (§5.1 : le pool complet est toujours constitué avant que le joueur ne
## commence à jouer un dé) ; ne rétrécit QUE lorsqu'un dé est effectivement
## joué (voir _remove_from_pool()) — un dé sans coup légal à l'instant T reste
## dans le pool, car jouer un AUTRE dé d'abord peut le rendre jouable ensuite
## (ex. sortir un pion de la Maison avec un 6 rend un 4 jouable). L'UI grise
## juste les dés temporairement injouables (dice_pool_view.gd:_is_dead()),
## elle ne les retire pas.
var dice_pool: Array = []

## Id (dans dice_pool) du dé actuellement armé par select_die(), en attente
## d'un clic sur un pion (via pawn_controller.pawn_selected). -1 = aucun dé
## armé (le joueur doit d'abord cliquer un dé, PUIS un pion — plus d'ordre
## imposé automatiquement par le moteur).
var _selected_die_id: int = -1

var _last_result: Dictionary = {}

## Compteur de lancers PHYSIQUES consécutifs pour LE TOUR COURANT (§5.3) —
## incrémenté à chaque _roll_once(), remis à 0 au début de CHAQUE tour (par
## _start_turn_loop() pour le tout premier tour de la partie, par _end_turn()
## pour tous les tours suivants — sans ce dernier reset, le compteur cumulerait
## les lancers de TOUS les joueurs sur toute la partie au lieu d'être propre à
## chaque tour). Sert de seuil de bust : un 3e double six consécutif annule le
## tour (voir BoardConfig.MAX_CONSECUTIVE_ROLLS).
var _roll_chain_count: int = 0

## Prochain id à distribuer dans dice_pool — continu sur toute la chaîne de
## lancers d'un même tour (potentiellement plusieurs appels séparés de
## _roll_once() si le joueur enchaîne des doubles six), remis à 0 par
## _start_turn_loop().
var _next_dice_id: int = 0


## Rattachement explicite des dépendances (appelé par main.gd / GameRoot).
## Le PawnController signale la sélection du joueur : connecté ici plutôt
## qu'en _ready() car pawn_controller peut être assigné tardivement.
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
	_start_turn_loop(board_manager.active_players[0])


## Démarre la boucle de tours à partir d'un plateau DÉJÀ configuré (mode
## "Configuration manuelle de scénario", voir ScenarioState +
## BoardManager.apply_scenario()) : ne touche PAS board_manager.all_pawns,
## seulement la mécanique de tour.
func start_from_scenario(active_player_id: int = 0) -> void:
	_start_turn_loop(active_player_id)


func _start_turn_loop(starting_player: int) -> void:
	active_player = starting_player
	locked_pawn_ids.clear()
	dice_pool.clear()
	_selected_die_id = -1
	_last_result = {}
	_roll_chain_count = 0
	_next_dice_id = 0
	_change_state(TurnState.WAITING_FOR_ROLL)


# ----------------------------------------------------------------------------
# État 1/2b -> 2 : le joueur demande à lancer (ou relancer après un double six)
# ----------------------------------------------------------------------------
## Appelé par le bouton "Lancer"/"Relancer" (voir dice_view.gd) : valide pour
## le tout premier lancer du tour (WAITING_FOR_ROLL) ET pour chaque relance
## après un double six (WAITING_FOR_REROLL) — c'est désormais TOUJOURS le
## joueur qui déclenche explicitement chaque lancer physique, y compris ceux
## gagnés par un double six (plus de relance automatique enchaînée).
func request_roll() -> void:
	if state != TurnState.WAITING_FOR_ROLL and state != TurnState.WAITING_FOR_REROLL:
		return
	_change_state(TurnState.ROLLING)
	_roll_once()


# ----------------------------------------------------------------------------
# État 2 -> 2b/3 : un lancer physique (§5.1 fix + §5.3 révisé)
# ----------------------------------------------------------------------------
## Exécute UN lancer physique et l'ajoute à dice_pool (qui peut déjà contenir
## des dés de lancers précédents du même tour, si le joueur a enchaîné des
## doubles six). Un double six donne droit à une relance, mais ne la
## déclenche plus automatiquement : on repasse la main au joueur
## (WAITING_FOR_REROLL) qui doit recliquer "Relancer" — plus gratifiant que
## l'ancien enchaînement instantané, et cohérent avec le principe "AVANT tout
## coup joué" (le pool n'est proposé au choix du joueur qu'une fois la chaîne
## de lancers terminée). On a droit à 2 doubles six d'affilée (2 relances) ;
## un 3e double six consécutif annule le tour entier (bust total : pool vidé,
## aucun pion ne bouge). Réutilise BoardConfig.MAX_CONSECUTIVE_ROLLS (3)
## comme seuil de bust plutôt que d'introduire une nouvelle constante.
func _roll_once() -> void:
	_roll_chain_count += 1
	var pair: Array[int] = dice_system.roll_pair()
	var is_double_six: bool = pair[0] == 6 and pair[1] == 6
	if is_double_six and _roll_chain_count >= BoardConfig.MAX_CONSECUTIVE_ROLLS:
		dice_pool.clear()
		GameEvents.turn_busted.emit(active_player)
		_end_turn("triple_double_six_bust")
		return

	dice_pool.append({"id": _next_dice_id, "value": pair[0]})
	_next_dice_id += 1
	dice_pool.append({"id": _next_dice_id, "value": pair[1]})
	_next_dice_id += 1

	if is_double_six:
		# Montre les dés déjà engrangés pendant que le joueur décide de
		# relancer — _resolve_checked_moves() (cas non-double, ci-dessous)
		# émettra son propre dice_pool_changed une fois le pool final connu,
		# inutile de le dupliquer ici.
		GameEvents.dice_pool_changed.emit(active_player, dice_pool)
		_change_state(TurnState.WAITING_FOR_REROLL)
		return

	_change_state(TurnState.CHECKING_MOVES)
	_resolve_checked_moves()


# ----------------------------------------------------------------------------
# État 3 : vérifier les coups légaux sur le pool entier (cas L1-L8, L13)
# ----------------------------------------------------------------------------
func _resolve_checked_moves() -> void:
	var pool_values: Array = dice_pool.map(func(e): return e.value)

	# Cas L2/L3/L4 : aucun coup possible avec AUCUN dé du pool -> tour perdu.
	# NOTE : on ne retire PAS ici les dés individuellement injouables À CET
	# INSTANT (ex. un 4 alors que les 4 pions sont encore à la Maison) — jouer
	# un AUTRE dé du pool en premier (ex. le 6 qui fait sortir un pion) peut
	# rendre ce dé jouable ensuite. Un dé ne quitte le pool que lorsqu'il est
	# effectivement joué (_remove_from_pool()), jamais par élagage préventif.
	if not RuleEngine.has_any_legal_move(active_player, board_manager.all_pawns, pool_values, locked_pawn_ids):
		_end_turn("no_legal_move")
		return

	GameEvents.dice_pool_changed.emit(active_player, dice_pool)
	_change_state(TurnState.WAITING_FOR_SELECTION)


# ----------------------------------------------------------------------------
# État 4 : le joueur choisit un dé du pool (UI : DicePoolView)
# ----------------------------------------------------------------------------
## Appelé par l'UI quand le joueur clique un dé encore jouable du pool.
func select_die(pool_id: int) -> void:
	if state != TurnState.WAITING_FOR_SELECTION:
		return
	var entry: Dictionary = _pool_entry_by_id(pool_id)
	if entry.is_empty():
		return
	var legal: Array = RuleEngine.get_legal_target_pawns(
		active_player, board_manager.all_pawns, entry.value, locked_pawn_ids
	)
	if legal.is_empty():
		# Garde défensive : l'UI grise déjà les dés morts (dice_pool_view.gd),
		# ne devrait pas arriver hors race de clic.
		return

	var legal_ids: Array = legal.map(func(e): return e.pawn.id)
	GameEvents.pawns_offered.emit(active_player, legal_ids, entry.value)

	if legal.size() == 1:
		# Un seul pion peut jouer ce dé : pas un vrai choix, on le joue
		# automatiquement au lieu d'attendre un clic (QoL).
		_resolve_die_pawn_choice(pool_id, legal[0].pawn)
		return

	_selected_die_id = pool_id
	pawn_controller.request_selection(active_player, legal_ids)


# ----------------------------------------------------------------------------
# État 4 -> 5 : le joueur a sélectionné un pion pour le dé armé
# ----------------------------------------------------------------------------
func _on_pawn_selected(pawn: Dictionary) -> void:
	if state != TurnState.WAITING_FOR_SELECTION or _selected_die_id == -1:
		return
	var die_id: int = _selected_die_id
	_selected_die_id = -1
	_resolve_die_pawn_choice(die_id, pawn)


## Coeur du filet de sécurité anti-gâchis (§8 révisé, voir rule_engine.gd) :
## joue le dé choisi normalement sur `pawn`, SAUF si cela gâcherait un unique
## autre dé du pool ET qu'un mouvement combiné légal existe pour ce même
## pion — auquel cas on fusionne silencieusement les deux dés en un seul coup
## au lieu de perdre un dé. Dans tous les autres cas, le choix du joueur est
## joué tel quel (pas de réordonnancement automatique).
func _resolve_die_pawn_choice(chosen_id: int, pawn: Dictionary) -> void:
	var chosen_entry: Dictionary = _pool_entry_by_id(chosen_id)
	if chosen_entry.is_empty():
		return

	var other_entries: Array = dice_pool.filter(func(e): return e.id != chosen_id)
	var wasted_id: int = RuleEngine.find_wasted_die_id(
		active_player, board_manager.all_pawns, pawn.id,
		chosen_entry.value, other_entries, locked_pawn_ids
	)
	if wasted_id != -1:
		var wasted_entry: Dictionary = _pool_entry_by_id(wasted_id)
		var combo: Dictionary = RuleEngine.try_combined_move(
			pawn, chosen_entry.value, wasted_entry.value, board_manager.all_pawns
		)
		if combo.legal:
			_play_combined_move(pawn, chosen_entry, wasted_entry)
			return

	_play_pawn(pawn, chosen_entry)


## Joue `pawn` avec le dé de pool `entry`, que le choix vienne d'un clic
## joueur ou d'un coup forcé auto-joué (select_die(), quand un seul pion est
## légal pour ce dé).
func _play_pawn(pawn: Dictionary, entry: Dictionary) -> void:
	# Snapshot AVANT toute mutation : apply_move() va muter pawn.state/progress
	# (et ceux de la victime en cas de capture) en place, donc c'est le seul
	# moyen pour PawnController de connaître le point de départ de l'animation.
	var old_state: int = pawn.state
	var old_progress: int = pawn.progress

	var preview: Dictionary = RuleEngine.try_move(pawn, entry.value, board_manager.all_pawns)
	if not preview.legal:
		# Sélection invalide (race) : on ignore, le joueur doit rechoisir.
		return

	var capture_info: Dictionary = {}
	if preview.capture:
		var victim: Dictionary = preview.captured_pawn
		capture_info = {
			"captured_pawn": victim,
			"old_state": victim.state,
			"old_progress": victim.progress,
		}

	# Valide (via RuleEngine) puis applique réellement le mouvement.
	var result: Dictionary = RuleEngine.apply_move(pawn, entry.value, board_manager.all_pawns)
	if not result.legal:
		# Défensif : try_move()/apply_move() doivent converger, ne devrait pas arriver.
		return

	_last_result = result
	_remove_from_pool(entry.id)
	# _change_state(MOVING) AVANT ce emit : DicePoolView._on_pool_changed()
	# écoute dice_pool_changed de façon SYNCHRONE et peut ré-armer/auto-jouer
	# le dé suivant (_maybe_auto_arm -> select_die) dans le même appel — le
	# garde-fou de select_die() (state != WAITING_FOR_SELECTION) doit donc
	# déjà voir MOVING ici, sinon deux _play_pawn()/_play_combined_move()
	# s'enchaînent avant que le Tween du premier n'existe (glitch visuel :
	# saut direct au point final puis retour en arrière case par case).
	_change_state(TurnState.MOVING)
	GameEvents.dice_pool_changed.emit(active_player, dice_pool)

	# Publie les signaux de haut niveau (§11.2) AVANT l'animation.
	GameEvents.move_validated.emit(pawn, entry.value, result)
	if result.capture:
		locked_pawn_ids.append(pawn.id)  # §8.3 / L10 : verrouillage post-capture
		GameEvents.pawn_captured.emit(result.captured_pawn, pawn)

	pawn_controller.move_pawn_visual(pawn, old_state, old_progress, entry.value, capture_info, true)
	# -> l'animation (mouvement + éventuelle étape de capture) appellera
	# _on_move_animation_done via pawn_moved, une fois TOUTE l'animation finie.
	GameEvents.pawn_moved.connect(_on_move_animation_done, CONNECT_ONE_SHOT)


## Joue LES DEUX dés `entry_a`/`entry_b` en une seule action pour `pawn`
## (filet anti-gâchis, voir _resolve_die_pawn_choice()) : utilisé quand jouer
## les dés séparément gâcherait `entry_b` (verrouillage post-capture sur
## `entry_a` par exemple) alors qu'un mouvement combiné l'évite. La case qui
## aurait normalement capturé/verrouillé devient une simple case de transit.
func _play_combined_move(pawn: Dictionary, entry_a: Dictionary, entry_b: Dictionary) -> void:
	var value_a: int = entry_a.value
	var value_b: int = entry_b.value
	var old_state: int = pawn.state
	var old_progress: int = pawn.progress

	var preview: Dictionary = RuleEngine.try_combined_move(pawn, value_a, value_b, board_manager.all_pawns)
	if not preview.legal:
		# Sélection invalide (race) : ne devrait pas arriver, déjà vérifié par l'appelant.
		return

	var capture_info: Dictionary = {}
	if preview.capture:
		var victim: Dictionary = preview.captured_pawn
		capture_info = {
			"captured_pawn": victim,
			"old_state": victim.state,
			"old_progress": victim.progress,
		}

	var result: Dictionary = RuleEngine.apply_combined_move(pawn, value_a, value_b, board_manager.all_pawns)
	if not result.legal:
		return

	_last_result = result
	_remove_from_pool(entry_a.id)
	_remove_from_pool(entry_b.id)
	# Voir _play_pawn() : _change_state(MOVING) doit précéder ce emit pour
	# empêcher DicePoolView de ré-armer/auto-jouer un autre dé en cascade
	# avant que le Tween de CE mouvement n'existe.
	_change_state(TurnState.MOVING)
	GameEvents.dice_pool_changed.emit(active_player, dice_pool)

	GameEvents.move_validated.emit(pawn, value_a + value_b, result)
	if result.capture:
		locked_pawn_ids.append(pawn.id)  # sans effet ce tour (dés consommés), mais cohérent
		GameEvents.pawn_captured.emit(result.captured_pawn, pawn)

	pawn_controller.move_pawn_visual(pawn, old_state, old_progress, value_a + value_b, capture_info, true)
	GameEvents.pawn_moved.connect(_on_move_animation_done, CONNECT_ONE_SHOT)


# ----------------------------------------------------------------------------
# Helpers pool
# ----------------------------------------------------------------------------
func _pool_entry_by_id(id: int) -> Dictionary:
	for entry in dice_pool:
		if entry.id == id:
			return entry
	return {}


func _remove_from_pool(id: int) -> void:
	for i in range(dice_pool.size()):
		if dice_pool[i].id == id:
			dice_pool.remove_at(i)
			return


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
# État 6 : résolution post-coup (victoire ? encore des dés dans le pool ?)
# ----------------------------------------------------------------------------
func _after_move_resolved() -> void:
	# 1. Victoire ? (§2.3, L12) — vérifié même avec des dés restants dans le pool.
	var winner: int = RuleEngine.check_victory(board_manager.all_pawns, board_manager.active_players)
	if winner != -1:
		_change_state(TurnState.GAME_OVER)
		GameEvents.victory.emit(winner)
		return

	# 2. Reste-t-il au moins un dé ENCORE JOUABLE dans le pool ? Un dé qui
	#    n'a pas de coup légal À CET INSTANT peut le redevenir après un autre
	#    coup (voir la note dans _resolve_checked_moves()) — on ne le retire
	#    donc pas du pool tant qu'il n'a pas été effectivement joué, on
	#    vérifie juste si LE POOL DANS SON ENSEMBLE offre encore un coup.
	if not dice_pool.is_empty():
		var pool_values: Array = dice_pool.map(func(e): return e.value)
		if RuleEngine.has_any_legal_move(active_player, board_manager.all_pawns, pool_values, locked_pawn_ids):
			_change_state(TurnState.WAITING_FOR_SELECTION)
			return

	# 3. Pool vide, ou plus aucun dé restant n'est jouable : fin du tour. Le
	#    chaînage des double six (§5.1) a déjà été entièrement résolu en amont
	#    dans _run_roll_chain() — il n'y a plus de notion d'"extra tour
	#    accordé ici", le tour avance toujours.
	_end_turn("all_dice_consumed")


# ----------------------------------------------------------------------------
# État 6 -> 1 : termine le tour courant et passe au joueur suivant
# ----------------------------------------------------------------------------
func _end_turn(reason: String) -> void:
	var previous: int = active_player
	locked_pawn_ids.clear()
	dice_pool.clear()
	_selected_die_id = -1
	_roll_chain_count = 0  # le seuil de bust (§5.3) redémarre à 0 pour le joueur suivant

	var active_idx: int = board_manager.active_players.find(active_player)
	active_player = board_manager.active_players[(active_idx + 1) % board_manager.active_players.size()]

	GameEvents.turn_ended.emit(previous, active_player)
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
