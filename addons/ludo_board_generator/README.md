# Ludo Board Generator (addon Godot 4)

**Tu dessines le chemin toi-même dans la `GridMap`. Le plugin le lit, le
valide, et te montre exactement ce qu'il a compris — en pointant du doigt
tout ce qui ne va pas.**

Plus de géométrie procédurale à deviner : `LudoBoardDetector` reconstruit la
structure logique du plateau (ring lane fermée + 4 home lanes) **par pur
parcours de graphe d'adjacence**, à partir de ce qui est réellement peint
dans la `GridMap` — aucune forme ni taille de plateau n'est supposée à
l'avance. Le plugin produit une resource `LudoBoardData` réutilisable, que
les systèmes de gameplay (pions, rule engine, IA, netcode) peuvent exploiter
**sans aucune dépendance à la `GridMap` elle-même**.

Ce plugin n'implémente volontairement **pas** la logique des pions, des dés,
des captures, des barrières ni des conditions de victoire — voir le Game
Design Document pour ces systèmes (`RuleEngine`, `TurnManager`,
`DiceSystem`, `PawnController`).

## Structure des fichiers

```
addons/ludo_board_generator/
├── plugin.cfg                     # Manifeste du plugin
├── plugin.gd                      # EditorPlugin : dock (Detect / Debug / Starter Layout)
├── board_generator.gd             # Node @tool : LudoBoardGenerator
├── resources/
│   ├── board_data.gd              # LudoBoardData   - source de vérité (Resource)
│   ├── cell_data.gd                # LudoCell         - une cellule logique (Resource)
│   ├── player_path.gd              # LudoPlayerPath   - le chemin d'un joueur (Resource)
│   └── mesh_mapping.gd             # LudoMeshMapping  - mesh_id <-> type/couleur (aller-retour)
├── scripts/
│   ├── ludo_board_enums.gd         # LudoBoardEnums     - PlayerColor / CellType
│   ├── board_detector.gd           # LudoBoardDetector  - LE cœur du plugin : lit la GridMap
│   ├── ring_path_generator.gd      # LudoRingPathGenerator - geometrie classique (starter layout optionnel)
│   └── board_validator.gd          # LudoBoardValidator - double-check générique (doublons, etc.)
├── example/
│   └── rule_engine_example.gd      # Exemple d'utilisation de BoardData sans aucune GridMap
└── generated/
    └── board_data.tres             # Résultat de la dernière détection réussie
```

## Workflow

1. Crée un node `GridMap` et assigne-lui une `MeshLibrary`.
2. Crée une resource `LudoMeshMapping` (`New Resource > LudoMeshMapping`) et
   renseigne quel item de la `MeshLibrary` correspond à quel type de case :
   `ring_mesh_id`, `start_red_mesh_id` / `start_blue_mesh_id` / ...,
   `home_red_mesh_id` / `home_blue_mesh_id` / ...
3. Ajoute un node `LudoBoardGenerator`, pointe `grid_map_path` vers ta
   `GridMap`, assigne le `mesh_mapping`.
4. **Peins ton chemin à la main** dans la `GridMap` avec l'outil de
   peinture natif de Godot :
   - une case `ring_mesh_id` pour chaque case du parcours partagé,
   - une case `start_*_mesh_id` pour chaque start tile (une par couleur),
   - une chaîne de cases `home_*_mesh_id` pour chaque home lane, **en
     partant bien de la case ring juste avant la start tile de cette
     couleur** (la vraie règle du Ludo — voir plus bas pourquoi c'est
     important), jusqu'à sa dernière case (le centre/finish).
   - (Tu peux aussi cliquer sur **"Generate Starter Layout"** pour peindre
     automatiquement la croix classique 15x15 comme point de départ, puis
     la retoucher à la main.)
5. Sélectionne le node `LudoBoardGenerator`, clique sur **"Detect Board
   From GridMap"**.
6. Si tout est valide : `BoardData` est sauvegardée, un résumé s'affiche
   dans l'Output (et un rendu ASCII si `print_ascii_on_detect` est actif).
   Si des problèmes sont trouvés : rien n'est sauvegardé, et avec **Debug
   Mode** actif, chaque case problématique est marquée d'un repère **rouge**
   directement dans la vue 3D, avec le message d'erreur exact.
7. Corrige les cases signalées dans la `GridMap`, reclique sur **Detect**.
   Répète jusqu'à 0 erreur.

## Pourquoi le point d'entrée de la home lane est vérifié précisément

Sur un vrai plateau, une case de home lane est **flanquée de cases ring des
deux côtés** sur toute sa longueur (par ex. sa rangée est coincée entre deux
rangées du ring) — donc "cette case touche une seule case ring" ne suffit
**pas** à identifier son point d'entrée. Le détecteur utilise donc la vraie
règle du Ludo : la home lane d'une couleur doit démarrer exactement à la
case ring située juste avant la start tile de cette couleur. Si ta home
lane part d'ailleurs, le détecteur te le signale avec un message précis
plutôt que de deviner silencieusement une structure fausse.

Exemple de message d'erreur réel (testé) :

```
Home lane RED : ni (7, 0, -1) ni (7, 0, -5) ne touche la case ring attendue
(2, 0, 6) (index 51, juste avant la start tile) - la home lane part du
mauvais endroit.
```

## Autres erreurs détectées

- une case ring avec ≠ 2 voisins ring (bifurcation, bout mort, case isolée) ;
- la boucle du ring qui ne se referme pas, ou repasse par une case déjà
  visitée ;
- des composantes séparées (cases orphelines non connectées à la boucle
  principale) ;
- une home lane avec une bifurcation, ou un nombre d'extrémités ≠ 2 ;
- une couleur avec deux start tiles, ou aucune.

Les avertissements (non bloquants) couvrent par exemple une couleur sans
start tile détectée, ou une home lane non peinte pour une couleur donnée -
le plateau reste utilisable en partie pour les autres couleurs.

## Modèle de données

```
LudoBoardData
├── ring_lane_length: int                 (déduit du nombre de cases détectées)
├── home_lane_length: int                 (longueur d'une chaîne détectée, informatif)
├── cells: Array[LudoCell]                (toutes les cellules détectées, indexées par id)
├── ring_lane: Array[int]                 (ids de cellules ordonnés, index 0..N-1)
├── index_map: Dictionary                 (Vector3i -> id de cellule)
├── player_paths: Dictionary              (PlayerColor -> LudoPlayerPath)
└── center_position: Vector3i             (centre de la bounding box détectée)
```

`LudoCell` porte `position`, `type` (RING / START / HOME / CENTER / SAFE),
`color`, `mesh_id`, `neighbors` (toujours axis-aligned), ainsi que
`ring_index` / `home_lane_index` selon les cas.

`LudoPlayerPath` relie une couleur à sa start tile, à son `ring_entry_index`,
à son `home_entry_index` (la case ring juste avant sa start tile), et à la
chaîne ordonnée d'ids de la home lane jusqu'à la case CENTER (détectée par
sa **position** dans la chaîne - l'extrémité opposée au ring - pas par un
mesh dédié : peins toute la home lane, y compris sa dernière case, avec le
mesh `home_*` de cette couleur). `LudoBoardData` expose
`resolve_position(color, progress)` pour qu'un RuleEngine convertisse
directement le compteur `progress` d'un pion en position monde.

## Utiliser BoardData depuis le code de gameplay

Voir `example/rule_engine_example.gd`. En résumé :

```gdscript
var data: LudoBoardData = load("res://addons/ludo_board_generator/generated/board_data.tres")
var red_path := data.get_player_path(LudoBoardEnums.PlayerColor.RED)
var world_pos := data.resolve_position(LudoBoardEnums.PlayerColor.RED, progress)
```

Aucune référence à une `GridMap` n'est nécessaire — c'est exactement la
séparation logique/visuel demandée dans le cahier des charges.

## Points d'extension déjà en place

- `to_dict()` / `save_json()` sur `LudoBoardData` pour un export JSON
  (synchronisation multijoueur, fichiers de sauvegarde, outils externes).
- `LudoBoardValidator` tourne aussi après la détection comme double
  vérification générique (doublons de position, etc.).
- `_print_ascii_board()` : rendu texte instantané, désormais dimensionné
  automatiquement à la bounding box réelle du plateau détecté (fonctionne
  quelle que soit la forme/taille que tu as peinte).
- `generate_starter_layout()` reste disponible comme point de départ
  procédural optionnel (géométrie classique 15x15), mais n'est plus la
  source de vérité : tout repasse par `detect_board()` ensuite.
