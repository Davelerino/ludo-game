class_name DiceSystem
extends Node
## ============================================================================
## DiceSystem — Génération aléatoire d'une paire de dés du Ludo (GDD §5).
##
## RESPONSABILITÉS (§11.1)
##   - Produire une paire de valeurs de dé ∈ [1,6] à la demande, via
##     roll_pair(). Purement une source aléatoire : ne connaît RIEN du pool de
##     dés en cours (ids, valeurs consommées, chaînage de double six...), qui
##     est désormais entièrement possédé et orchestré par TurnManager
##     (voir turn_manager.gd:_run_roll_chain()).
##   - Émettre dice_rolled sur le bus global GameEvents (§11.2) à chaque appel
##     — un signal par lancer PHYSIQUE, TurnManager pouvant appeler roll_pair()
##     plusieurs fois d'affilée pendant un enchaînement de double six.
##
## DÉPENDANCES
##   - GameEvents (autoload) pour publier dice_rolled.
##   - Aucune dépendance vers RuleEngine ni vers TurnManager.
##
## NOTE : la RNG est seedable (seed) pour les tests déterministes (§11.7).
## ============================================================================

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Seed publique : setter pour pouvoir rejouer un scénario (tests/CI).
var seed_value: int:
	set(value):
		seed_value = value
		_rng.seed = value


func _ready() -> void:
	# Graine aléatoire par défaut ; overridable avant roll_pair() pour la reproductibilité.
	_rng.randomize()


## Lance une paire de dés et publie le signal. Retourne [a, b] directement
## (pas de champ partagé à lire ensuite : élimine le risque de course qui
## existait quand dice_a/dice_b étaient des champs mutables lus après coup).
func roll_pair() -> Array[int]:
	var a: int = _rng.randi_range(1, 6)
	var b: int = _rng.randi_range(1, 6)
	GameEvents.dice_rolled.emit(a, b, a == b)
	return [a, b]
