class_name BoardConfig
extends Resource
## ============================================================================
## BoardConfig — Configuration centrale du plateau et des règles.
## Référence : GDD_Ludo3D.md §11.4
##
## Ce script peut être assigné en tant que script d'une Resource `.tres`
## si l'on souhaite exposer des valeurs éditables depuis l'éditeur Godot.
## Toutes les constantes sont statiques : aucun état, uniquement des règles.
## ============================================================================

# --- Dimensions du plateau (§3.1, §3.2) ---
const RING_SIZE: int = 52
const HOME_LANE_LENGTH: int = 6
const PLAYER_COUNT: int = 4
const PAWNS_PER_PLAYER: int = 4

# --- Règles de jeu (§5, §6) ---
const MAX_CONSECUTIVE_ROLLS: int = 3   # Anti-boucle infinie (§5.3)
const BARRIER_MIN_PAWNS: int = 2       # Seuil de formation de barrière (§6.1)
const ENTRY_DICE_VALUE: int = 6        # Valeur requise pour sortir du yard (§4.2)

# --- Progression logique le long du chemin (§4.1) ---
# progress ∈ [0, HOME_ENTRY_PROGRESS-1]      (0..50)  -> Ring lane
# progress ∈ [HOME_ENTRY_PROGRESS, FINISH_PROGRESS] (51..56) -> Home lane
#            (index local dans la home lane = progress - HOME_ENTRY_PROGRESS)
# progress == FINISH_PROGRESS (56)                    -> pion FINI
const HOME_ENTRY_PROGRESS: int = RING_SIZE - 1                              # 51
const FINISH_PROGRESS: int = HOME_ENTRY_PROGRESS + HOME_LANE_LENGTH - 1     # 56

# --- États d'un pion (§11.3) ---
enum PawnState { MAISON, RING, HOME_LANE, FINI }

# --- Mode de fin de partie (§2.3) ---
enum GameEndMode { FIRST_TO_FINISH, FULL_RANKING }

## Retourne les offsets de départ pour chaque joueur (§3.2).
## Joueur 0 -> 0, Joueur 1 -> 13, Joueur 2 -> 26, Joueur 3 -> 39 (pour RING_SIZE=52, PLAYER_COUNT=4)
static func get_player_offsets() -> Array[int]:
	var segment_length: int = RING_SIZE / PLAYER_COUNT
	var offsets: Array[int] = []
	for i in range(PLAYER_COUNT):
		offsets.append(i * segment_length)
	return offsets

static func get_player_offset(player_id: int) -> int:
	return player_id * (RING_SIZE / PLAYER_COUNT)

## Fabrique un pion neuf, à l'état MAISON (yard), non encore en jeu.
static func create_pawn(pawn_id: int, player_id: int) -> Dictionary:
	return {
		"id": pawn_id,
		"player": player_id,
		"state": PawnState.MAISON,
		"progress": -1,   # -1 = pas de progression tant que le pion est au yard
	}

## Fabrique les PAWNS_PER_PLAYER pions initiaux pour un joueur donné.
static func create_player_pawns(player_id: int, id_offset: int) -> Array[Dictionary]:
	var pawns: Array[Dictionary] = []
	for i in range(PAWNS_PER_PLAYER):
		pawns.append(create_pawn(id_offset + i, player_id))
	return pawns
