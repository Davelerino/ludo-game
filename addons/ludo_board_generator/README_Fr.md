# Ludo Board Generator (addon Godot 4)

Génère la **structure logique et visuelle jouable** d'un plateau de Ludo sur
une `GridMap` : une ring lane fermée de 52 cases, 4 start tiles et 4 home
lanes. Le plugin produit une resource `LudoBoardData` réutilisable, que les
systèmes de gameplay (pions, rule engine, IA, netcode) peuvent exploiter
**sans aucune dépendance à la `GridMap` elle-même**.

Ce plugin n'implémente volontairement **pas** la logique des pions, des dés,
des captures, des barrières ni des conditions de victoire — voir le Game
Design Document pour ces systèmes (`RuleEngine`, `TurnManager`,
`DiceSystem`, `PawnController`).

## Structure des fichiers

```
addons/ludo_board_generator/
├── plugin.cfg                     # Manifeste du plugin
├── plugin.gd                      # EditorPlugin : ajoute le dock (panneau) dans l'éditeur
├── board_generator.gd             # Node @tool : LudoBoardGenerator (le générateur lui-même)
├── resources/
│   ├── board_data.gd              # LudoBoardData   - source de vérité (Resource)
│   ├── cell_data.gd                # LudoCell         - une cellule logique (Resource)
│   ├── player_path.gd              # LudoPlayerPath   - le chemin d'un joueur (Resource)
│   ├── mesh_mapping.gd             # LudoMeshMapping  - type de cellule -> item MeshLibrary
│   └── start_tile_config.gd        # LudoStartTileConfig - entrée de config manuelle d'une start tile
├── scripts/
│   ├── ludo_board_enums.gd         # LudoBoardEnums   - PlayerColor / CellType
│   ├── ring_path_generator.gd      # LudoRingPathGenerator - géométrie pure
│   └── board_validator.gd          # LudoBoardValidator - vérifications post-génération
├── example/
│   └── rule_engine_example.gd      # Exemple d'utilisation de BoardData sans aucune GridMap
└── generated/
	└── board_data.tres             # Résultat de la dernière génération (créé automatiquement)
```

## Modèle de données

```
LudoBoardData
├── ring_lane_length: int                 (défaut 52)
├── home_lane_length: int                 (défaut 6)
├── cells: Array[LudoCell]                (toutes les cellules générées, indexées par id)
├── ring_lane: Array[int]                 (ids de cellules ordonnés, index 0..N-1)
├── index_map: Dictionary                 (Vector3i -> id de cellule)
├── player_paths: Dictionary              (PlayerColor -> LudoPlayerPath)
└── center_position: Vector3i
```

`LudoCell` porte `position`, `type` (RING / START / HOME / CENTER / SAFE),
`color`, `mesh_id`, `neighbors` (uniquement axis-aligned, jamais en
diagonale), ainsi que `ring_index` / `home_lane_index` selon les cas.

`LudoPlayerPath` relie une couleur à sa start tile, à ses index d'entrée sur
le ring et d'entrée en home lane, et à la chaîne ordonnée des ids de
cellules de la home lane jusqu'à la case CENTER — ce qui reproduit
fidèlement le modèle de `progress` du GDD (§4.1). `LudoBoardData` expose
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
5. (Optionnel) Ajoute jusqu'à 4 entrées `LudoStartTileConfig` dans
   `start_tiles` pour contrôler l'ordre couleur-par-bras, ou utilise le
   bouton **"Auto-Detect Start Tiles From GridMap"** du dock si tu as déjà
   placé des meshes de start à la main et mappé leurs ids dans
   `mesh_mapping`.
6. Sélectionne le node `LudoBoardGenerator` — le dock **"Ludo Board
   Generator"** (en bas à droite par défaut) devient actif.
7. Clique sur **Generate Board**. Cela va :
   - construire procéduralement le ring de 52 cases + les 4 home lanes,
   - valider le résultat (boucle fermée, axis-aligned, aucune diagonale,
	 home lanes disjointes, les 4 couleurs présentes) — la génération est
	 annulée avec un message d'erreur clair en cas d'échec de validation,
   - peindre la `GridMap` en utilisant ton `LudoMeshMapping`,
   - sauvegarder `LudoBoardData` vers `board_data_save_path` (par défaut
	 `res://addons/ludo_board_generator/generated/board_data.tres`).
8. Active **Debug Mode** pour faire apparaître des `Label3D` (index,
   couleurs) au-dessus de chaque case et imprimer un rapport de
   connectivité complet dans le panneau Output.
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

## Points d'extension déjà en place

- `to_dict()` / `save_json()` sur `LudoBoardData` pour un export JSON
  (synchronisation multijoueur, fichiers de sauvegarde, outils externes).
- `LudoCell.type` inclut une valeur `SAFE` non utilisée, réservée à de
  futurs variants de type "case sûre".
- `detect_start_tiles_from_gridmap()` comme alternative à la configuration
  manuelle de `start_tiles`.
- Le champ `board_seed` est câblé de bout en bout mais reste pour l'instant
  purement cosmétique (la topologie est déterministe) — un futur système de
  variantes visuelles pourra s'en servir pour choisir entre plusieurs skins
  de `MeshLibrary` sans toucher à cette logique.

## Simplification connue

Pour 52 cases de ring réparties sur 4 bras de 13, un cadre carré parfaitement
symétrique a son centre géométrique réel sur une coordonnée à demi-entier
(voir les commentaires dans `ring_path_generator.gd`). La home lane de
chaque joueur se termine donc sur sa propre case de type `CENTER`, proche du
centre plutôt que rigoureusement confondue avec une case unique partagée.
Cela n'a aucun impact sur le gameplay (chaque
`LudoPlayerPath.center_cell_id` fait autorité pour sa couleur) et peut être
affiné plus tard avec une géométrie sur mesure si un unique mesh central
physiquement partagé est requis.
