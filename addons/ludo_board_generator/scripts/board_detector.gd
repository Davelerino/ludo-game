## Reconstructs a LudoBoardData purely from adjacency, by reading whatever
## has been hand-painted into a GridMap - no assumed geometry, no fixed
## board size. This is the counterpart to the (optional) procedural
## generator: you design the path yourself with the GridMap's native paint
## tool, then call LudoBoardDetector.detect() to turn it into logical
## BoardData, with precise, positioned error/warning reporting so you can
## fix mistakes directly in the viewport.
##
## KEY INSIGHT that shaped this algorithm: on a real board, home-lane cells
## are geometrically flanked by ring cells on BOTH sides along their entire
## length (e.g. the home lane's row sits directly between two ring rows) -
## so "this cell touches exactly one ring cell" is NOT a reliable way to
## find a home lane's entry point. Instead, the detector uses the actual
## Ludo rule: a colour's home lane must begin at the ring cell immediately
## BEFORE that colour's own start tile. This doubles as validation: a home
## lane painted from the wrong ring cell is reported as an explicit,
## positioned error instead of silently mis-detected.
##
## Detection never repaints or otherwise mutates the GridMap - it is
## strictly read-only.
class_name LudoBoardDetector
extends RefCounted

const _DIRS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]


## Returns:
## {
##   "board_data": LudoBoardData (never null; may be partially populated if
##                 errors were found),
##   "errors":   Array[Dictionary]  -> {"message": String, "position": Variant (Vector3i or null)}
##   "warnings": Array[String],
## }
static func detect(grid_map: GridMap, mesh_mapping: LudoMeshMapping) -> Dictionary:
	var errors: Array[Dictionary] = []
	var warnings: Array[String] = []
	var board_data := LudoBoardData.new()

	if grid_map == null:
		errors.append({"message": "Aucune GridMap assignée (grid_map_path).", "position": null})
		return _result(board_data, errors, warnings)
	if mesh_mapping == null:
		errors.append({"message": "Aucun LudoMeshMapping assigné.", "position": null})
		return _result(board_data, errors, warnings)

	# --- 1. Classify every painted cell -------------------------------------
	var ring_family: Dictionary = {}  # Vector3i -> {"type":int,"color":int}
	var home_family: Dictionary = {}  # Vector3i -> {"type":int,"color":int}

	for pos in grid_map.get_used_cells():
		var info := mesh_mapping.classify(grid_map.get_cell_item(pos))
		if info.is_empty():
			continue  # decorative / unrecognized mesh - ignored, not an error
		match info.type:
			LudoBoardEnums.CellType.RING, LudoBoardEnums.CellType.START:
				ring_family[pos] = info
			LudoBoardEnums.CellType.HOME:
				home_family[pos] = info

	if ring_family.is_empty():
		errors.append({
			"message": "Aucune case de ring/start détectée. Vérifie que le bon LudoMeshMapping est assigné et que des cases ont été peintes avec ring_mesh_id / start_*_mesh_id.",
			"position": null,
		})
		return _result(board_data, errors, warnings)

	# --- 2. Ring degree check (every ring/start cell must have exactly 2
	#        ring/start neighbours for a simple closed loop) ----------------
	for pos in ring_family.keys():
		var nbs := _neighbors(pos, ring_family)
		if nbs.size() != 2:
			errors.append({
				"message": "Case ring en %s a %d voisin(s) ring (attendu : 2)." % [pos, nbs.size()],
				"position": pos,
			})
	if not errors.is_empty():
		return _result(board_data, errors, warnings)

	# --- 3. Walk the ring loop ----------------------------------------------
	var start_pos: Vector3i = ring_family.keys()[0]
	var found_red_start := false
	for pos in ring_family.keys():
		var info: Dictionary = ring_family[pos]
		if info.type == LudoBoardEnums.CellType.START and info.color == LudoBoardEnums.PlayerColor.RED:
			start_pos = pos
			found_red_start = true
			break
	if not found_red_start:
		warnings.append("Aucune start tile ROUGE trouvée - indexation du ring depuis une case arbitraire.")

	var order: Array[Vector3i] = [start_pos]
	var prev_pos: Variant = null
	var cur_pos := start_pos
	var safety := 0
	while true:
		safety += 1
		if safety > ring_family.size() + 5:
			errors.append({"message": "La boucle du ring ne se referme pas (trop de pas parcourus depuis %s)." % start_pos, "position": cur_pos})
			break
		var nbs := _neighbors(cur_pos, ring_family)
		var next_pos: Vector3i = nbs[0] if nbs[1] == prev_pos else nbs[1]
		if next_pos == start_pos:
			break
		if order.has(next_pos):
			errors.append({"message": "La boucle repasse par %s avant de revenir à la case de départ." % next_pos, "position": next_pos})
			break
		order.append(next_pos)
		prev_pos = cur_pos
		cur_pos = next_pos
	if not errors.is_empty():
		return _result(board_data, errors, warnings)

	if order.size() != ring_family.size():
		errors.append({
			"message": "%d case(s) atteinte(s) en suivant la boucle, mais %d case(s) ring peinte(s) au total - composantes séparées (cases orphelines) ?" % [order.size(), ring_family.size()],
			"position": null,
		})
		return _result(board_data, errors, warnings)

	var ring_len := order.size()

	# --- 4. Build LudoCell entries for the ring -----------------------------
	var cells: Array[LudoCell] = []
	var ring_ids: Array[int] = []
	var index_map: Dictionary = {}

	for i in range(order.size()):
		var pos: Vector3i = order[i]
		var info: Dictionary = ring_family[pos]
		var cell := LudoCell.new()
		cell.id = cells.size()
		cell.position = pos
		cell.ring_index = i
		cell.type = info.type
		cell.color = info.get("color", LudoBoardEnums.PlayerColor.NONE)
		cell.mesh_id = grid_map.get_cell_item(pos)
		cells.append(cell)
		ring_ids.append(cell.id)
		index_map[pos] = cell.id

	for i in range(ring_ids.size()):
		var c: LudoCell = cells[ring_ids[i]]
		var nxt: LudoCell = cells[ring_ids[(i + 1) % ring_ids.size()]]
		var prv: LudoCell = cells[ring_ids[(i - 1 + ring_ids.size()) % ring_ids.size()]]
		c.neighbors = [prv.id, nxt.id]

	# --- 5. Start tiles -> per-colour ring_entry_index / home_entry_index --
	var player_paths: Dictionary = {}
	var seen_colors: Dictionary = {}
	for i in range(order.size()):
		var info: Dictionary = ring_family[order[i]]
		if info.type != LudoBoardEnums.CellType.START:
			continue
		if seen_colors.has(info.color):
			errors.append({"message": "Deux start tiles trouvées pour la couleur %s." % LudoBoardEnums.color_name(info.color), "position": order[i]})
			continue
		seen_colors[info.color] = true

		var start_cell: LudoCell = cells[ring_ids[i]]
		var path := LudoPlayerPath.new()
		path.color = info.color
		path.start_tile_id = start_cell.id
		path.start_tile_position = start_cell.position
		path.ring_entry_index = i
		path.home_entry_index = (i - 1 + ring_len) % ring_len
		player_paths[info.color] = path

	for color in LudoBoardEnums.all_colors():
		if not player_paths.has(color):
			warnings.append("Aucune start tile détectée pour la couleur %s." % LudoBoardEnums.color_name(color))
	if not errors.is_empty():
		return _result(board_data, errors, warnings)

	# --- 6. Home lane chains, per colour ------------------------------------
	for color in LudoBoardEnums.all_colors():
		var color_cells: Dictionary = {}
		for pos in home_family.keys():
			if home_family[pos].color == color:
				color_cells[pos] = home_family[pos]

		if color_cells.is_empty():
			if player_paths.has(color):
				warnings.append("Aucune case de home lane peinte pour la couleur %s." % LudoBoardEnums.color_name(color))
			continue
		if not player_paths.has(color):
			errors.append({"message": "Home lane %s peinte, mais aucune start tile trouvée pour cette couleur." % LudoBoardEnums.color_name(color), "position": null})
			continue

		var path: LudoPlayerPath = player_paths[color]
		var local_adj: Dictionary = {}
		var endpoints: Array[Vector3i] = []
		var bad := false

		for pos in color_cells.keys():
			var nbs := _neighbors(pos, color_cells)
			local_adj[pos] = nbs
			if nbs.size() == 1:
				endpoints.append(pos)
			elif nbs.size() != 2:
				errors.append({
					"message": "Home lane %s, case %s : %d voisin(s) dans sa propre home lane (attendu 1 pour une extrémité, 2 pour une case intérieure) - bifurcation ou case isolée ?" % [LudoBoardEnums.color_name(color), pos, nbs.size()],
					"position": pos,
				})
				bad = true
		if bad:
			continue
		if endpoints.size() != 2:
			errors.append({
				"message": "Home lane %s : %d extrémité(s) détectée(s) (attendu exactement 2 : entrée + centre) - la chaîne n'est peut-être pas un chemin simple." % [LudoBoardEnums.color_name(color), endpoints.size()],
				"position": null,
			})
			continue

		var expected_entry_pos: Vector3i = order[path.home_entry_index]
		var entry_cell: Variant = null
		for p in endpoints:
			if _is_axis_neighbor(p, expected_entry_pos):
				entry_cell = p
				break
		if entry_cell == null:
			errors.append({
				"message": "Home lane %s : ni %s ni %s ne touche la case ring attendue %s (index %d, juste avant la start tile) - la home lane part du mauvais endroit." % [
					LudoBoardEnums.color_name(color), endpoints[0], endpoints[1], expected_entry_pos, path.home_entry_index
				],
				"position": endpoints[0],
			})
			continue
		var end_cell: Vector3i = endpoints[1] if entry_cell == endpoints[0] else endpoints[0]

		var chain: Array[Vector3i] = [entry_cell]
		var prv: Variant = null
		var cur: Vector3i = entry_cell
		var safety2 := 0
		while cur != end_cell:
			safety2 += 1
			if safety2 > color_cells.size() + 5:
				errors.append({"message": "Home lane %s : la chaîne ne rejoint pas le centre." % LudoBoardEnums.color_name(color), "position": cur})
				break
			var nbs2: Array[Vector3i] = local_adj[cur]
			var nxt: Variant = null
			for n in nbs2:
				if n != prv:
					nxt = n
					break
			if nxt == null:
				break
			chain.append(nxt)
			prv = cur
			cur = nxt

		if chain.size() != color_cells.size() or chain[chain.size() - 1] != end_cell:
			errors.append({
				"message": "Home lane %s : la chaîne reconstruite (%d case(s)) ne couvre pas toutes les cases peintes (%d)." % [LudoBoardEnums.color_name(color), chain.size(), color_cells.size()],
				"position": null,
			})
			continue

		var home_entry_cell: LudoCell = cells[ring_ids[path.home_entry_index]]
		var home_cell_ids: Array[int] = []
		for step in range(chain.size()):
			var pos2: Vector3i = chain[step]
			var hcell := LudoCell.new()
			hcell.id = cells.size()
			hcell.position = pos2
			hcell.color = color
			hcell.home_lane_index = step
			hcell.mesh_id = grid_map.get_cell_item(pos2)
			hcell.type = LudoBoardEnums.CellType.CENTER if step == chain.size() - 1 else LudoBoardEnums.CellType.HOME
			if hcell.type == LudoBoardEnums.CellType.CENTER:
				path.center_cell_id = hcell.id
			cells.append(hcell)
			home_cell_ids.append(hcell.id)
			index_map[pos2] = hcell.id

		for step in range(home_cell_ids.size()):
			var hc: LudoCell = cells[home_cell_ids[step]]
			var nb: Array[int] = []
			nb.append(home_entry_cell.id if step == 0 else home_cell_ids[step - 1])
			if step < home_cell_ids.size() - 1:
				nb.append(home_cell_ids[step + 1])
			hc.neighbors = nb
		home_entry_cell.neighbors.append(home_cell_ids[0])

		path.home_lane_cell_ids = home_cell_ids

	# --- 7. Finalize BoardData ----------------------------------------------
	board_data.ring_lane_length = ring_len
	board_data.home_lane_length = _representative_home_length(player_paths)
	board_data.cells = cells
	board_data.ring_lane = ring_ids
	board_data.index_map = index_map
	board_data.player_paths = player_paths
	board_data.center_position = _bounding_center(cells)
	board_data.generated_at_unix = Time.get_unix_time_from_system()

	return _result(board_data, errors, warnings)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

static func _result(board_data: LudoBoardData, errors: Array[Dictionary], warnings: Array[String]) -> Dictionary:
	return {"board_data": board_data, "errors": errors, "warnings": warnings}


static func _neighbors(pos: Vector3i, in_set: Dictionary) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for d in _DIRS:
		var n := pos + d
		if in_set.has(n):
			result.append(n)
	return result


static func _is_axis_neighbor(a: Vector3i, b: Vector3i) -> bool:
	return _DIRS.has(b - a)


static func _representative_home_length(player_paths: Dictionary) -> int:
	for color in player_paths.keys():
		var path: LudoPlayerPath = player_paths[color]
		if not path.home_lane_cell_ids.is_empty():
			return path.home_lane_cell_ids.size()
	return 0


static func _bounding_center(cells: Array[LudoCell]) -> Vector3i:
	if cells.is_empty():
		return Vector3i.ZERO
	var min_pos := cells[0].position
	var max_pos := cells[0].position
	for cell in cells:
		var p := cell.position
		min_pos = Vector3i(mini(min_pos.x, p.x), mini(min_pos.y, p.y), mini(min_pos.z, p.z))
		max_pos = Vector3i(maxi(max_pos.x, p.x), maxi(max_pos.y, p.y), maxi(max_pos.z, p.z))
	return (min_pos + max_pos) / 2
