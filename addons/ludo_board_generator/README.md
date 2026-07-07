# Ludo Board Generator (Godot 4 addon)

Generates the **playable logical + visual structure** of a Ludo board on a
`GridMap`: a 52-cell closed ring lane, 4 start tiles, and 4 home lanes. It
produces a reusable `LudoBoardData` resource that gameplay systems (pawns,
rule engine, AI, netcode) can consume **without any dependency on the
GridMap itself**.

This plugin deliberately does **not** implement pawns, dice, capture,
barrier, or win-condition logic — see the companion Game Design Document for
those systems (`RuleEngine`, `TurnManager`, `DiceSystem`, `PawnController`).

## File structure

```
addons/ludo_board_generator/
├── plugin.cfg                     # Plugin manifest
├── plugin.gd                      # EditorPlugin: adds the dock UI
├── board_generator.gd             # @tool node: LudoBoardGenerator (the generator itself)
├── resources/
│   ├── board_data.gd              # LudoBoardData   - source of truth (Resource)
│   ├── cell_data.gd                # LudoCell         - one logical cell (Resource)
│   ├── player_path.gd              # LudoPlayerPath   - one player's path (Resource)
│   ├── mesh_mapping.gd             # LudoMeshMapping  - cell type -> MeshLibrary id (Resource)
│   └── start_tile_config.gd        # LudoStartTileConfig - manual start config entry (Resource)
├── scripts/
│   ├── ludo_board_enums.gd         # LudoBoardEnums   - PlayerColor / CellType
│   ├── ring_path_generator.gd      # LudoRingPathGenerator - pure geometry
│   └── board_validator.gd          # LudoBoardValidator - post-generation checks
├── example/
│   └── rule_engine_example.gd      # How to consume BoardData with zero GridMap coupling
└── generated/
    └── board_data.tres             # Output of the last generation (created on demand)
```

## Data model

```
LudoBoardData
├── ring_lane_length: int                 (default 52)
├── home_lane_length: int                 (default 6)
├── cells: Array[LudoCell]                (every generated cell, indexed by id)
├── ring_lane: Array[int]                 (ordered cell ids, index 0..N-1)
├── index_map: Dictionary                 (Vector3i -> cell id)
├── player_paths: Dictionary              (PlayerColor -> LudoPlayerPath)
└── center_position: Vector3i
```

`LudoCell` carries `position`, `type` (RING / START / HOME / CENTER / SAFE),
`color`, `mesh_id`, `neighbors` (axis-aligned only, never diagonal), plus
`ring_index` / `home_lane_index` where applicable.

`LudoPlayerPath` links a color to its start tile, its ring entry/home entry
indices, and the ordered chain of home lane cell ids ending in the CENTER
cell — mirroring the GDD's `progress` model (§4.1) exactly. `LudoBoardData`
exposes `resolve_position(color, progress)` so a RuleEngine can turn a
pawn's `progress` counter directly into a world position.

## Workflow in the editor

1. Create a `GridMap` node and assign it a `MeshLibrary` with your tile meshes.
2. Add a `LudoBoardGenerator` node anywhere in the scene (it appears in the
   "Create Node" dialog automatically).
3. Point `grid_map_path` at your `GridMap`.
4. Create a `LudoMeshMapping` resource (`New Resource > LudoMeshMapping`),
   fill in the MeshLibrary item ids for each cell type, and assign it to
   `mesh_mapping`.
5. (Optional) Add up to 4 `LudoStartTileConfig` entries under `start_tiles`
   to control color-to-arm ordering, or use the dock's
   **"Auto-Detect Start Tiles From GridMap"** button if you've already
   hand-placed start meshes and mapped their ids in `mesh_mapping`.
6. Select the `LudoBoardGenerator` node — the **"Ludo Board Generator"**
   dock (bottom-right by default) becomes active.
7. Click **Generate Board**. This:
   - builds the 52-cell ring + 4 home lanes procedurally,
   - validates the result (closed loop, axis-aligned, no diagonals, disjoint
     home lanes, all 4 colors present) — generation is aborted with a clear
     error if validation fails,
   - paints the `GridMap` using your `LudoMeshMapping`,
   - saves `LudoBoardData` to `board_data_save_path` (default
     `res://addons/ludo_board_generator/generated/board_data.tres`).
8. Toggle **Debug Mode** to spawn `Label3D` indices/colors above every cell
   and print a full connectivity report to the Output panel.
9. Click **Clear Board** to wipe the `GridMap` and discard the in-memory
   `LudoBoardData` (the saved `.tres` is untouched until the next Generate).

## Consuming BoardData from gameplay code

See `example/rule_engine_example.gd`. In short:

```gdscript
var data: LudoBoardData = load("res://addons/ludo_board_generator/generated/board_data.tres")
var red_path := data.get_player_path(LudoBoardEnums.PlayerColor.RED)
var world_pos := data.resolve_position(LudoBoardEnums.PlayerColor.RED, progress)
```

No `GridMap` reference is required — this is exactly the logic/visual
separation the spec calls for, and it's what lets a headless RuleEngine unit
test run without any 3D scene at all.

## Extension points already in place

- `to_dict()` / `save_json()` on `LudoBoardData` for JSON export (multiplayer
  sync, save files, external tooling).
- `LudoCell.type` includes an unused `SAFE` value reserved for future
  "safe tile" variants.
- `detect_start_tiles_from_gridmap()` as an alternative to manual
  `start_tiles` configuration.
- `board_seed` field is wired through end-to-end but currently cosmetic-only
  (topology is deterministic) — a future visual-variants pass can consume it
  to pick between multiple `MeshLibrary` skins without touching this logic.

## Known simplification

For 52 ring cells split across 4 arms of 13, a perfectly symmetric square
frame has its true geometric center at a half-integer coordinate (see
comments in `ring_path_generator.gd`). Each player's home lane therefore
ends at its own `CENTER`-type cell near, rather than exactly on, a single
shared tile. This has no gameplay impact (each `LudoPlayerPath.center_cell_id`
is authoritative for that color) and can be refined later with custom
per-project geometry if a single physically-shared center mesh is required.
