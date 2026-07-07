# Ludo Board Generator (addon Godot 4)

Génère la **structure logique et visuelle jouable** du plateau de Ludo
**classique en croix, sur grille 15x15** : une ring lane fermée de 52 cases
et 4 home lanes de 5 cases, sur une `GridMap`. Le plugin produit une
resource `LudoBoardData` réutilisable, que les systèmes de gameplay (pions,
rule engine, IA, netcode) peuvent exploiter **sans aucune dépendance à la
`GridMap` elle-même**.

Ce plugin n'implémente volontairement **pas** la logique des pions, des dés,
des captures, des barrières ni des conditions de victoire — voir le Game
Design Document pour ces systèmes (`RuleEngine`, `TurnManager`,
`DiceSystem`, `PawnController`).

## Structure des fichiers

```
addons/ludo_board_generator/
├── plugin.cfg                     # Manifeste du plugin
├── plugin.gd                      # EditorPlugin : dock + enregistrement du gizmo
├── board_generator.gd             # Node @tool : LudoBoardGenerator (le générateur lui-même)
├── resources/
│   ├── board_data.gd              # LudoBoardData     - source de vérité (Resource)
│   ├── cell_data.gd                # LudoCell           - une cellule logique (Resource)
│   ├── player_path.gd              # LudoPlayerPath     - le chemin d'un joueur (Resource)
│   ├── mesh_mapping.gd             # LudoMeshMapping    - type de cellule -> item MeshLibrary
│   └── board_overrides.gd          # LudoBoardOverrides - positions forcées, par clé stable
├── scripts/
│   ├── ludo_board_enums.gd         # LudoBoardEnums   - PlayerColor / CellType
│   ├── ring_path_generator.gd      # LudoRingPathGenerator - géométrie en croix (15x15, 52 cases)
│   └── board_validator.gd          # LudoBoardValidator - vérifications post-génération
├── editor/
│   └── board_gizmo_plugin.gd       # Gizmo 3D : glisser les cases dans la vue 3D
├── example/
│   └── rule_engine_example.gd      # Exemple d'utilisation de BoardData sans aucune GridMap
└── generated/
    └── board_data.tres             # Résultat de la dernière génération (créé automatiquement)
```

## La géométrie : plateau classique en croix, 15x15

`LudoRingPathGenerator` génère un anneau de 52 cases en forme de croix
(exactement la forme d'un vrai plateau de Ludo), pas un simple cadre carré.

**Point technique important, à lire avant de modifier la géométrie** : les
4 bras (RED / GREEN / YELLOW / BLUE) ne sont **pas** obtenus en faisant
tourner un seul bras de 13 cases par pas de 90° autour du centre. C'est
mathématiquement impossible : toute rotation ou réflexion qui fixe une
case entière de la grille préserve la couleur "noir/blanc" de cette case sur
le damier, alors que chaque déplacement orthogonal change cette couleur.
Comme 13 (le nombre de cases par bras) est impair, une start tile et
"la start tile 13 pas plus loin" ne peuvent jamais être l'image l'une de
l'autre par une rotation à 90° — ça produit toujours un saut en diagonale à
la jonction entre deux bras.

En revanche, les bras **opposés** (RED/YELLOW et GREEN/BLUE) sont bien liés
par une rotation à **180°** (26 pas, un nombre pair — aucun problème de
parité). Le générateur écrit donc explicitement le bras RED et le bras
GREEN comme des suites de segments directionnels (RIGHT xN / UP xN / DOWN
xN), puis obtient YELLOW et BLUE par rotation à 180°.

Rendu ASCII du plateau généré par défaut (produit automatiquement par
`_print_ascii_board()`, voir plus bas) :

```
      ..G      
      .g.      
      .g.      
      .g.      
      .g.      
      .C...... 
 R.....      . 
 .rrrrC Cyyyy. 
 .      .....Y 
 ......C.      
      .b.      
      .b.      
      .b.      
      .b.      
      B..      
```
(`.` = case de ring partagée, `R/G/Y/B` = start tile, `r/g/y/b` = home lane,
`C` = case finale/centre de chaque couleur, espace = case non utilisée.)

Cette géométrie est **fixe** (elle correspond au vrai plateau, pas à une
forme paramétrable arbitrairement) : `ring_lane_length` reste verrouillé à
52 et `player_count` à 4. Seul `home_lane_length` reste ajustable (défaut 5),
et `color_order` permet de réassigner quelle couleur va sur quel bras
géométrique (l'ordre par défaut est RED / GREEN / YELLOW / BLUE, dans le
sens de parcours de l'anneau).

## Modèle de données

```
LudoBoardData
├── ring_lane_length: int                 (fixe : 52)
├── home_lane_length: int                 (défaut 5)
├── cells: Array[LudoCell]                (toutes les cellules générées, indexées par id)
├── ring_lane: Array[int]                 (ids de cellules ordonnés, index 0..51)
├── index_map: Dictionary                 (Vector3i -> id de cellule)
├── player_paths: Dictionary              (PlayerColor -> LudoPlayerPath)
└── center_position: Vector3i             (case (7,7) du plateau, partagée)
```

`LudoCell` porte `position`, `type` (RING / START / HOME / CENTER / SAFE),
`color`, `mesh_id`, `neighbors` (uniquement axis-aligned, jamais en
diagonale), ainsi que `ring_index` / `home_lane_index` selon les cas.

`LudoPlayerPath` relie une couleur à sa start tile, à son index d'entrée sur
le ring, à son `home_entry_index` (la case de ring juste avant sa propre
start tile — c'est là que ses pions bifurquent vers la home lane après un
tour complet), et à la chaîne ordonnée des ids de cellules de la home lane
jusqu'à la case CENTER. `LudoBoardData` expose
`resolve_position(color, progress)` pour qu'un RuleEngine convertisse
directement le compteur `progress` d'un pion en position monde.

## Workflow dans l'éditeur

1. Crée un node `GridMap` et assigne-lui une `MeshLibrary` contenant tes
   meshes de tuiles.
2. Ajoute un node `LudoBoardGenerator` n'importe où dans la scène (il
   apparaît automatiquement dans la boîte de dialogue "Create Node").
3. Renseigne `grid_map_path` en pointant vers ta `GridMap`.
4. Crée une resource `LudoMeshMapping` (`New Resource > LudoMeshMapping`),
   remplis les ids d'items MeshLibrary pour chaque type de cellule, puis
   assigne-la à `mesh_mapping`.
5. (Optionnel) Modifie `color_order` si tu veux qu'une autre couleur occupe
   un bras donné du plateau.
6. Sélectionne le node `LudoBoardGenerator` — le dock **"Ludo Board
   Generator"** (en bas à droite par défaut) devient actif.
7. Clique sur **Generate Board**. Cela va :
   - construire procéduralement l'anneau en croix (52 cases) + les 4 home
     lanes (5 cases chacune),
   - valider le résultat (boucle fermée, axis-aligned, aucune diagonale,
     aucun doublon de position, home lanes disjointes, les 4 couleurs
     présentes) — la génération est annulée avec un message d'erreur clair
     en cas d'échec de validation,
   - peindre la `GridMap` en utilisant ton `LudoMeshMapping`,
   - sauvegarder `LudoBoardData` vers `board_data_save_path` (par défaut
     `res://addons/ludo_board_generator/generated/board_data.tres`),
   - imprimer le rendu ASCII du plateau dans le panneau Output (désactivable
     via `print_ascii_on_generate`).
8. Active **Debug Mode** pour en plus faire apparaître des `Label3D` (index,
   couleurs) au-dessus de chaque case dans la scène 3D.
9. Clique sur **Clear Board** pour vider la `GridMap` et abandonner le
   `LudoBoardData` en mémoire (le `.tres` sauvegardé n'est pas touché tant
   qu'une nouvelle génération n'est pas lancée).

## Utiliser BoardData depuis le code de gameplay

Voir `example/rule_engine_example.gd`. En résumé :

```gdscript
var data: LudoBoardData = load("res://addons/ludo_board_generator/generated/board_data.tres")
var red_path := data.get_player_path(LudoBoardEnums.PlayerColor.RED)
var world_pos := data.resolve_position(LudoBoardEnums.PlayerColor.RED, progress)
```

Aucune référence à une `GridMap` n'est nécessaire — c'est exactement la
séparation logique/visuel demandée dans le cahier des charges, et c'est ce
qui permet à un RuleEngine de tourner dans des tests unitaires "headless",
sans aucune scène 3D.

## Validation automatique

`LudoBoardValidator` vérifie, à chaque génération :
- **aucun doublon de position** sur l'ensemble des cellules (ring + home
  lanes confondues) ;
- la ring lane fait exactement 52 cases et forme une boucle fermée où chaque
  paire de cases consécutives est un voisin axis-aligned à distance 1
  (jamais de diagonale, jamais de saut) ;
- les 4 couleurs possèdent bien une start tile ;
- chaque home lane a la bonne longueur, est connectée par un voisinage
  axis-aligned à sa case d'entrée, et ne chevauche aucune autre home lane.

## Ajustement manuel du plateau (overrides + live preview + gizmo 3D)

Trois couches, qui communiquent en temps réel :

1. **Base procédurale** — `LudoRingPathGenerator` (inchangé, voir plus haut).
2. **Couche overrides** — `resources/board_overrides.gd` (`LudoBoardOverrides`) :
   une resource qui stocke des positions forcées, indexées par une **clé
   stable** (`"ring:13"`, `"home:0:2"` où `0`=RED), appliquées par-dessus la
   génération procédurale à chaque régénération. Important : les overrides
   ne changent **que la position** d'une case, jamais la topologie (quelle
   case est voisine de quelle autre, calculée par index) — donc si tu
   déplaces une case à un endroit qui casse l'alignement orthogonal, le
   `LudoBoardValidator` le détecte immédiatement au lieu de laisser un
   plateau cassé silencieusement.
3. **Couche live** — `live_preview` (bool, activé par défaut) sur
   `LudoBoardGenerator` : toute modification pertinente (champs de
   l'inspecteur, overrides, ou drag du gizmo 3D) redéclenche aussitôt une
   reconstruction + repeinture GridMap + revalidation, sans avoir besoin de
   cliquer sur "Generate Board". Pendant un drag, seule une version légère
   `preview_override()` tourne (aucune écriture disque, aucun message
   console) ; le commit définitif (avec sauvegarde + undo/redo) n'a lieu
   qu'au relâchement de la souris.

### Gizmo interactif (`editor/board_gizmo_plugin.gd`)

Un `EditorNode3DGizmoPlugin` affiche chaque case du ring (poignées blanches)
et des home lanes (poignées jaunes) directement dans la vue 3D, reliées par
des lignes qui dessinent le chemin. Tu peux cliquer-glisser n'importe quelle
poignée : elle se réaligne sur la case de `GridMap` la plus proche à chaque
frame (conversion via `grid_to_local()` / `local_to_grid()`, qui passe par
le `cell_size`/transform réel de la `GridMap` assignée), et le déplacement
est intégré à l'undo/redo de l'éditeur (Ctrl+Z fonctionne).

**Note de compatibilité** : la signature exacte des callbacks
`_get_handle_value` / `_set_handle` / `_commit_handle` d'
`EditorNode3DGizmoPlugin` a légèrement évolué entre versions mineures de
Godot 4.x. Le code est écrit contre l'API 4.x telle que documentée à ce
jour ; si ta version rejette une signature, vérifie la référence de classe
`EditorNode3DGizmoPlugin` de ta version exacte et ajuste en conséquence — le
reste du système (overrides + `live_preview`) fonctionne de façon totalement
indépendante du gizmo et n'en a pas besoin pour être utile.

### API utilisable depuis le code (ou un futur outil d'édition custom)

```gdscript
generator.get_editable_slots()               # liste [{key, position}, ...]
generator.preview_override(key, grid_pos)    # nudge léger, pas de sauvegarde
generator.commit_override(key, grid_pos)     # nudge définitif + sauvegarde
generator.clear_override(key)                # retire un override précis
generator.clear_all_overrides()              # retour à la géométrie pure
generator.grid_to_local(grid_pos)            # GridMap -> espace local du node
generator.local_to_grid(local_pos)           # inverse, avec snapping
```

## Points d'extension déjà en place

- `to_dict()` / `save_json()` sur `LudoBoardData` pour un export JSON
  (synchronisation multijoueur, fichiers de sauvegarde, outils externes).
- `LudoCell.type` inclut une valeur `SAFE` non utilisée, réservée à de
  futurs variants de type "case sûre".
- `_print_ascii_board()` sur `LudoBoardGenerator` : rendu texte instantané
  du plateau, pratique pour vérifier toute modification de la géométrie
  sans repasser par l'éditeur 3D.
- Le champ `board_seed` est câblé de bout en bout mais reste pour l'instant
  purement cosmétique (la topologie est déterministe et fixe).
