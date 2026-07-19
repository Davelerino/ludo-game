extends Node
## NOTE : pas de `class_name` ici. Ce script est un AUTOLOAD (singleton global
## `GameEvents`) déclaré dans project.godot : Godot enregistre lui-même la classe
## globale du nom de l'autoload. Ajouter un `class_name` identique provoquerait
## une collision ("Class hides an autoload singleton").
## ============================================================================
## GameEvents — Bus global de signaux (GDD §11.2).
##
## Pourquoi un bus global ? Le GDD §11.2 décrit un petit ensemble de signaux
## de haut niveau (dice.rolled, rule_engine.move_validated, pawn.moved,
## rule_engine.captured, turn_manager.turn_ended) qui doivent traverser les
## couches : UI (HUD, dés), scène 3D (pions, plateau) et logique de tour.
## Un autoload central évite le câblage point-à-point fragile entre managers
## et vues, et garde les émetteurs/récepteurs découplés (§11.1).
##
## Rôles :
##   - Les managers (TurnManager, BoardManager...) ÉMETTENT ici.
##   - Les vues (HUD, DiceView, FeedbackLayer, PawnController) ÉCOUTENT ici.
## ============================================================================

# --- Dés (DiceSystem) ---
## Émis à chaque lancer PHYSIQUE d'une paire de dés (dice_a/dice_b ∈ [1,6]).
## is_double vaut true sur un double. Peut être émis plusieurs fois d'affilée
## pendant un enchaînement de double six (§5.1) — voir dice_pool_changed
## ci-dessous pour l'état agrégé du pool qui en résulte.
signal dice_rolled(dice_a: int, dice_b: int, is_double: bool)

## Émis quand le pool de dés du tour est (re)construit après un enchaînement
## de lancers, ou qu'il rétrécit après qu'un coup ait consommé un ou deux dés.
## `pool` est un Array de {"id": int, "value": int} (voir TurnManager.dice_pool).
signal dice_pool_changed(player_id: int, pool: Array)

## Émis quand un 3e double six consécutif annule le tour entier (§5.3
## révisé) : le pool est vidé, aucun pion ne bouge, le tour passe directement
## au joueur suivant (turn_ended suit immédiatement).
signal turn_busted(player_id: int)

# --- RuleEngine (validation) ---
## Émis AVANT d'appliquer un coup, pour signaler qu'il a été validé.
## `result` est le Dictionary retourné par RuleEngine.try_move().
signal move_validated(pawn: Dictionary, dice_value: int, result: Dictionary)

# --- Pion (après application) ---
## Émis APRÈS qu'un pion ait effectivement bougé (état + progress mis à jour).
signal pawn_moved(pawn: Dictionary, dice_value: int)

# --- RuleEngine (capture) ---
## Émis quand un pion adverse est capturé et renvoyé au yard (§8).
## `captured_pawn` est la victime, `capturing_pawn` le pion qui capture.
signal pawn_captured(captured_pawn: Dictionary, capturing_pawn: Dictionary)

# --- Événements secondaires issus d'un coup (B4/H1/§7.2) ---
signal barrier_formed(pawn: Dictionary, ring_index: int)
signal pawn_entered_home(pawn: Dictionary)
signal pawn_finished(pawn: Dictionary)

# --- TurnManager (§9) ---
## Émis à chaque changement d'état de la machine à tours (utile pour le debug
## et pour piloter l'UI). `old_state`/`new_state` ∈ TurnManager.TurnState.
signal turn_state_changed(old_state: int, new_state: int)
## Émis quand le TurnManager propose un dé à jouer : la liste des pions
## légaux pour `dice_value` (peut être vide juste avant qu'un dé injouable
## soit retiré). Utile pour l'UI/debug, qui n'a pas à réévaluer
## RuleEngine.get_legal_target_pawns() elle-même.
signal pawns_offered(player_id: int, pawn_ids: Array, dice_value: int)
## Émis quand un tour se termine et qu'on passe au joueur suivant. Le
## chaînage des double six (§5.1) est désormais entièrement résolu EN AMONT,
## dans TurnManager._run_roll_chain() — il n'y a donc plus de notion d'"extra
## tour accordé ici" : ce signal signifie toujours une avance de joueur.
signal turn_ended(previous_player: int, next_player: int)

# --- Partie (§2.3, L12) ---
## Émis dès qu'un joueur gagne. `winner_id` ∈ [0, PLAYER_COUNT-1].
signal victory(winner_id: int)
