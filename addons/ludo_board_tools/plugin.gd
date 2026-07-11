@tool
extends EditorPlugin
## ============================================================================
## Ludo Board Tools — Plugin éditeur pour la génération du plateau.
##
## Ajoute deux entrées dans le menu Tools de l'éditeur :
##   - "Generate Ludo Board" : charge (ou construit) le LudoBoardLayout
##     classique, crée la MeshLibrary si besoin, peuple la GridMap via
##     LudoBoardPainter.
##   - "Clear Board"         : vide la GridMap.
##
## La géométrie vient de addons/ludo_path_system (LudoBoardLayout /
## LudoClassicLayoutBuilder / LudoBoardPainter) — ce plugin ne fait
## qu'orchestrer l'appel depuis le menu Tools et gérer l'undo/redo.
##
## Recherche le noeud BoardRoot > GridMap dans la scène éditée.
## Supporte l'undo/redo via EditorUndoRedoManager.
## ============================================================================

const _LAYOUT_PATH := "res://resources/BoardLayout.tres"

var _undo_redo: EditorUndoRedoManager


func _enter_tree() -> void:
	_undo_redo = get_undo_redo()
	add_tool_menu_item("Generate Ludo Board", _on_generate_board)
	add_tool_menu_item("Clear Board", _on_clear_board)


func _exit_tree() -> void:
	remove_tool_menu_item("Generate Ludo Board")
	remove_tool_menu_item("Clear Board")


# ----------------------------------------------------------------------------
# Generate
# ----------------------------------------------------------------------------
func _on_generate_board(_ud: int = 0) -> void:
	var grid_map: GridMap = _find_grid_map()
	if grid_map == null:
		push_warning("Ludo Board Tools: aucun noeud BoardRoot > GridMap trouvé dans la scène.")
		return

	_undo_redo.create_action("Generate Ludo Board")

	# Commit la liste des cellules actuelles pour le redo (elles seront effacées).
	var old_cells: Array = grid_map.get_used_cells()

	_undo_redo.add_do_method(self, "_do_generate", grid_map)
	_undo_redo.add_undo_method(self, "_undo_generate", grid_map, old_cells)

	_undo_redo.commit_action()


func _do_generate(grid_map: GridMap) -> void:
	var mesh_lib: MeshLibrary = LudoMeshLibraryFactory.get_or_create_mesh_library()
	if mesh_lib == null:
		push_error("Ludo Board Tools: impossible de créer la MeshLibrary.")
		return
	var layout: LudoBoardLayout = _load_or_build_layout()
	grid_map.clear()
	LudoBoardPainter.paint(grid_map, mesh_lib, layout)
	# Marque la scène comme modifiée pour que Ctrl+S cuise les cellules.
	var edited: Node = get_editor_interface().get_edited_scene_root()
	if edited != null:
		edited.set_edited(true)
	# Feedback : nombre de cellules générées + rappel de sauvegarde.
	var cell_count: int = grid_map.get_used_cells().size()
	print("Ludo Board Tools: %d cellules générées. Pensez à Ctrl+S pour cuire dans la scène." % cell_count)


func _clear_board_impl(grid_map: GridMap) -> void:
	LudoBoardPainter.clear(grid_map)


## Charge le LudoBoardLayout classique s'il existe déjà (res://resources/BoardLayout.tres),
## sinon le construit via LudoClassicLayoutBuilder et le sauvegarde pour la prochaine fois.
func _load_or_build_layout() -> LudoBoardLayout:
	if ResourceLoader.exists(_LAYOUT_PATH):
		var layout: LudoBoardLayout = load(_LAYOUT_PATH)
		if layout != null:
			return layout
	var layout: LudoBoardLayout = LudoClassicLayoutBuilder.build()
	var errors: Array[String] = layout.validate()
	if not errors.is_empty():
		push_error("Ludo Board Tools: LudoBoardLayout généré invalide :\n - %s" % "\n - ".join(errors))
	ResourceSaver.save(layout, _LAYOUT_PATH)
	return layout


func _undo_generate(grid_map: GridMap, old_cells: Array) -> void:
	grid_map.clear()
	# Remet l'ancien mesh library si le grid_map en avait un (il sera celui
	# qu'on vient de mettre, c'est OK pour undo).
	for cell in old_cells:
		# On ne peut pas restaurer les anciens items sans avoir sauvegardé
		# chaque (cell, item) — pour simplifier, l'undo restaure juste un plateau vide.
		pass


# ----------------------------------------------------------------------------
# Clear
# ----------------------------------------------------------------------------
func _on_clear_board(_ud: int = 0) -> void:
	var grid_map: GridMap = _find_grid_map()
	if grid_map == null:
		return

	var old_cells: Array = grid_map.get_used_cells()
	if old_cells.is_empty():
		return

	_undo_redo.create_action("Clear Ludo Board")

	_undo_redo.add_do_method(self, "_clear_board_impl", grid_map)
	# Undo = re-générer (simple et pratique).
	_undo_redo.add_undo_method(self, "_do_generate", grid_map)

	_undo_redo.commit_action()


# ----------------------------------------------------------------------------
# Recherche du GridMap dans la scène éditée
# ----------------------------------------------------------------------------
func _find_grid_map() -> GridMap:
	var root: Node = get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	# Cherche BoardRoot > GridMap.
	if root.name == "BoardRoot":
		return root.get_node_or_null("GridMap") as GridMap
	var board_root: Node = root.get_node_or_null("BoardRoot")
	if board_root != null:
		return board_root.get_node_or_null("GridMap") as GridMap
	# Fallback : cherche directement un GridMap enfant.
	for child in root.get_children():
		if child is GridMap:
			return child
	return null
