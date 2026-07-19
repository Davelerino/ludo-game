class_name DiceSystem
extends Node
## ============================================================================
## DiceSystem — Génération aléatoire des deux dés du Ludo (GDD §5).
##
## RESPONSABILITÉS (§11.1)
##   - Produire deux valeurs de dé ∈ [1,6] à la demande.
##   - Détecter le double six (-> extra tour, §5.1) et tout double (-> les
##     deux dés sont jouables séparément, mais un double 6 accorde un tour
##     supplémentaire après la fin du tour courant).
##   - Suivre quels dés ont déjà été consommés ce tour-ci (dice_a_used /
##     dice_b_used), car un coup utilise exactement UN dé.
##   - Émettre dice_rolled sur le bus global GameEvents (§11.2).
##
## DÉPENDANCES
##   - BoardConfig (constantes : ENTRY_DICE_VALUE...).
##   - GameEvents (autoload) pour publier dice_rolled.
##   - Aucune dépendance vers RuleEngine : la validité d'un dé se teste côté
##     RuleEngine (is_dice_value_unusable), pas ici. Le DiceSystem ne fait que
##     produire et marquer "utilisé".
##
## NOTE : la RNG est seedable (seed) pour les tests déterministes (§11.7).
## ============================================================================

# --- État d'un lancer ---
var dice_a: int = 0
var dice_b: int = 0
var dice_a_used: bool = false
var dice_b_used:bool = false

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seed publique : setter pour pouvoir rejouer un scénario (tests/CI).
var seed_value: int:
	set(value):
		seed_value = value
		_rng.seed = value


func _ready() -> void:
	# Graine aléatoire par défaut ; overridable avant roll() pour la reproductibilité.
	_rng.randomize()


## Lance les deux dés, réinitialise les flags "utilisé" et publie le signal.
func roll() -> void:
	dice_a = _rng.randi_range(1, 6)
	dice_b = _rng.randi_range(1, 6)
	dice_a_used = false
	dice_b_used = false
	# IMPORTANT : on capture dice_a/dice_b dans des variables LOCALES avant
	# d'émettre. Si on passait les champs directement, un premier listener
	# (TurnManager, connecté avant les vues) peut, DANS SON traitement
	# synchrone de ce même signal, appeler reset() (ex. aucun coup légal,
	# tour perdu) et remettre dice_a/dice_b à 0 AVANT que les listeners
	# suivants (HUD, DiceView) ne reçoivent l'appel — ceux-ci recevraient
	# alors (0, 0) au lieu du lancer réel, Godot semblant référencer le
	# champ plutôt que d'en copier la valeur à l'émission dans ce cas.
	var rolled_a: int = dice_a
	var rolled_b: int = dice_b
	GameEvents.dice_rolled.emit(rolled_a, rolled_b, rolled_a == rolled_b)


## Marque un dé comme consommé après qu'un pion ait été joué avec.
## `die` vaut "A" ou "B". Ignore silencieusement si le dé est déjà utilisé.
func mark_used(die: String) -> void:
	if die == "A":
		dice_a_used = true
	elif die == "B":
		dice_b_used = true


## Un dé précis est-il encore jouable ce tour-ci ?
func is_die_available(die: String) -> bool:
	if die == "A":
		return dice_a > 0 and not dice_a_used
	if die == "B":
		return dice_b > 0 and not dice_b_used
	return false


## True si les deux dés sont consommés (ou qu'aucun n'a été lancé).
func all_dice_consumed() -> bool:
	if dice_a == 0 and dice_b == 0:
		return true
	return dice_a_used and dice_b_used


## Double six -> extra tour garanti (§5.1).
func is_double_six() -> bool:
	return dice_a == 6 and dice_b == 6


## N'importe quel double (les deux dés ont la même valeur).
func is_double() -> bool:
	return dice_a == dice_b


## Réinitialise l'état du lancer (appelé par TurnManager au début/fin de tour).
func reset() -> void:
	dice_a = 0
	dice_b = 0
	dice_a_used = false
	dice_b_used = false
