# Tests — RuleEngine (GDD §11.7)

Le `RuleEngine` est un ensemble de **fonctions pures** : il ne dépend d'aucune
scène 3D, GridMap ou asset. Les tests le valident donc intégralement **en
headless**, sans ouvrir l'éditeur.

## Exécution

```bash
godot --headless --script res://tests/test_rule_engine.gd
```

Résultat attendu :

```
14 PASS / 0 FAIL
```

## Couverture (cas limites du GDD)

| Test | Référence GDD |
|---|---|
| `test_entry_requires_six` | §4.2, L4 |
| `test_entry_blocked_by_enemy_barrier` | B1/B2 |
| `test_entry_captures_lone_enemy` | §8.2 |
| `test_transit_blocked_by_enemy_barrier` | B1/B2 |
| `test_transit_blocked_by_ally_barrier` | B6 (transit) |
| `test_landing_on_enemy_barrier_illegal` | B2 |
| `test_landing_on_ally_barrier_legal` | B6 |
| `test_capture_on_ring` | §8.1 |
| `test_no_capture_on_ally_stack_forms_barrier` | B4 |
| `test_home_lane_entry` | §7.2, L5 |
| `test_home_lane_overshoot_illegal` | H4, L9 |
| `test_home_lane_exact_finish` | H1, H5 |
| `test_no_barrier_effect_in_home_lane` | §7.5 |
| `test_victory_detection` | §2.3, L12 |

## Pourquoi ce n'est pas un test du TurnManager

Ces tests ne couvrent que le **moteur de règles** (sans état de tour), par
conception (GDD §11.7). La machine à états de tour (§9), le compteur de
lancers consécutifs (§5.3) et le verrouillage post-capture (§8.3/L10) sont
portés par `TurnManager` et se testent via une partie jouable — c'est
l'objet de la scène `main.tscn`.
