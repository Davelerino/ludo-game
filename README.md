# Godo Ludo 3D

Projet Godot 4.x (testé sur 4.6) — plateau de Ludo 3D basé sur GridMap avec
**RuleEngine réutilisé tel quel**, machine à états de tour conforme au §9 du
GDD, et bus de signaux global conforme au §11.2.

> Architecture détaillée : **GDD_Ludo3D.md §11**. Ce projet en est la
> traduction complète en dossiers/scènes/scripts.

---

## 1. Ouvrir le projet

1. Lance **Godot 4.6** (4.3+ fonctionne).
2. **Import** → sélectionne ce dossier (celui qui contient `project.godot`).
3. **Play** (▶ / F5) démarre `scenes/main.tscn`.

> Le RuleEngine se valide **sans rendu** : voir §5 ci-dessous.

## 2. Arborescence (justification vs GDD §11)

```
res://
├── scenes/                 # §11.5 — scènes .tscn
│   ├── main.tscn           #   Arbre racine §11.5 (Main > BoardRoot, CameraRig, AudioManager, UIManager, GameRoot)
│   ├── board/board_root.tscn   #   GridMap + RingDecor + PawnContainer
│   ├── pawns/pawn.tscn     #   Conteneur de pions (PawnController)
│   └── ui/ui_manager.tscn  #   CanvasLayer : HUD, DiceView, FeedbackLayer
├── scripts/
│   ├── core/               # §11.1 — modules cœur
│   │   ├── rule_engine.gd  #   ★ RÉUTILISÉ TEL QUEL (validation, barrières, capture, victoire)
│   │   ├── board_config.gd #   ★ RÉUTILISÉ TEL QUEL (constantes §11.4 + fabriques de pions)
│   │   ├── board_manager.gd#   Géométrie GridMap + état all_pawns (source de vérité)
│   │   ├── pawn_controller.gd  # Pont pion logique <-> noeud 3D + sélection souris (§11.6)
│   │   ├── dice_system.gd  #   RNG des 2 dés + suivi "dé consommé"
│   │   ├── camera_rig.gd   #   Caméra orbitale (présentation pure)
│   │   └── audio_manager.gd#   SFX/musique (écoute GameEvents)
│   └── managers/           # §11.1 — orchestration
│       ├── game_events.gd  #   ★ AUTOLOAD — bus global de signaux §11.2
│       └── turn_manager.gd #   ★ AUTOLOAD — machine à états de tour §9 (7 états)
├── resources/              # §11.4 — ressources éditables dans l'inspecteur
│   ├── BoardConfig.tres    #   Référence board_config.gd (constantes §11.4)
│   ├── BoardTuning.gd      #   Classe des réglages feeling (géométrie/anim/couleurs)
│   └── BoardTuning.tres    #   Instance par défaut
├── assets/
│   ├── meshes/             # Meshes 3D du plateau/pions (à fournir)
│   ├── materials/          # Matériaux (couleurs joueurs, sol...)
│   └── audio/              # Streams sfx/musique (à fournir)
├── ui/                     # §11.5 UIManager — scripts des vues
│   ├── hud/hud.gd          #   Joueur actif, état du tour, journal
│   ├── dice/dice_view.gd   #   Bouton "Lancer" + valeurs des dés
│   └── feedback/feedback_layer.gd # Popups capture/barrière/victoire
├── tests/                  # §11.7 — tests unitaires hors scène
│   ├── test_rule_engine.gd #   14 assertions L1-L13 (headless)
│   └── README.md
├── project.godot           # Nom, scène principale, input map §11.6/15, autoloads
├── icon.svg
└── README.md (ce fichier)
```

## 3. Où brancher le RuleEngine **déjà écrit**

Les fichiers `scripts/core/rule_engine.gd` et `scripts/core/board_config.gd`
sont **des copies conformes** de ton RuleEngine existant (uids préservés :
`uid://blgo7eavuxea`, `uid://c7x0goksmaocw`). **Aucune ligne n'a été modifiée**.

- **Aucune action requise** : le `TurnManager` les importe et les appelle déjà
  (`RuleEngine.try_move`, `apply_move`, `get_legal_target_pawns`,
  `has_any_legal_move`, `check_victory`).
- Pour repartir de TA version la plus à jour : copie simplement tes fichiers
  par-dessus `scripts/core/rule_engine.gd` et `scripts/core/board_config.gd`.

Le RuleEngine reste **sans état de tour** (cf. commentaire §8.3/R4 dans
`apply_move`) : le verrouillage post-capture et le compteur de lancers sont
gérés par le `TurnManager`, conformément au GDD.

## 4. Autoloads (singletons) — §11

Déclarés dans `project.godot` > `[autoload]` :

| Singleton | Rôle | Pourquoi un autoload ? |
|---|---|---|
| **`GameEvents`** | Bus de signaux §11.2 | Découple émetteurs (managers) et récepteurs (vues). Persistance non requise mais pratique : un seul point de câblage global. |
| **`TurnManager`** | Machine à états de tour §9 | Doit survivre à tout changement de scène et être adressable depuis n'importe quel noeud (DiceView, PawnController...). |

Les autres modules (`BoardManager`, `PawnController`, `DiceSystem`,
`CameraRig`, `AudioManager`) sont des **noeuds de scène** : leur durée de vie
est liée à la partie et ils portent des références à des noeuds enfants
(GridMap, noeuds 3D). En faire des singletons n'apporterait rien et compliquerait
le `_ready()`.

## 5. Lancer les tests du RuleEngine (sans 3D)

```bash
godot --headless --script res://tests/test_rule_engine.gd
```

Attendu : `14 PASS / 0 FAIL`. Couvre L1-L13 + B1-B6 + H1-H5 (voir
`tests/README.md`).

## 6. Machine à états de tour (§9) — résumé

`TurnManager.TurnState` : `WAITING_FOR_ROLL → ROLLING → CHECKING_MOVES →
WAITING_FOR_SELECTION → MOVING → TURN_ENDING → (boucle ou GAME_OVER)`.

Points clés implémentés :
- **Double six → extra tour** (§5.1) — même joueur rejoue.
- **Compteur `consecutive_rolls` ≤ 3** (§5.3) — anti-boucle infinie : au 3e
  lancer consécutif, l'extra tour est refusé.
- **Verrouillage post-capture** (§8.3 / L10) — `locked_pawn_ids` est passé à
  `RuleEngine.get_legal_target_pawns(...)` pour exclure le pion capturant du
  reste du tour.
- **Tour perdu si aucun coup légal** (L2/L3/L4) — via `has_any_legal_move`.

## 7. État actuel (squelette)

Le projet **compile et tourne** : la machine à tours est pleinement
fonctionnelle côté logique. Ce qui reste à brancher (assets) :
- `BoardManager.build_board()` : peupler la GridMap avec une MeshLibrary.
- `PawnController` : remplacer les `Marker3D` par de vrais `MeshInstance3D`
  cliquables (raycast dans `_unhandled_input`).
- `AudioManager` : déposer les streams dans `assets/audio/` et les assigner.
