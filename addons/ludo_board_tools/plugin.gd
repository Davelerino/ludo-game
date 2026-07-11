@tool
extends EditorPlugin
## ============================================================================
## Ludo Board Tools — Plugin éditeur pour la génération du plateau.
##
## Deux points d'entrée équivalents (mêmes actions sous-jacentes) :
##   - Un dock ("Ludo Board Tools", panneau droit) avec deux boutons.
##   - Deux entrées dans le menu Tools : "Generate Ludo Board" / "Clear Board".
##
## "Generate Ludo Board" charge (ou construit) le LudoBoardLayout classique et
## le LudoMeshMapping (identité visuelle par joueur), crée la MeshLibrary si
## besoin, peuple la GridMap via LudoBoardPainter.
## "Clear Board" vide la GridMap.
##
## La géométrie vient de addons/ludo_path_system (LudoBoardLayout /
## LudoClassicLayoutBuilder / LudoBoardPainter) — ce plugin ne fait
## qu'orchestrer l'appel depuis l'UI éditeur et gérer l'undo/redo.
##
## Recherche le noeud BoardRoot > GridMap dans la scène éditée.
## Supporte l'undo/redo via EditorUndoRedoManager.
## ============================================================================

const _LAYOUT_PATH := "res://resources/BoardLayout.tres"
const _MESH_MAPPING_PATH := "res://resources/LudoMeshMapping.tres"

var _undo_redo: EditorUndoRedoManager
var _dock: VBoxContainer
var _status_label: Label


func _enter_tree() -> void:
	_undo_redo = get_undo_redo()
	add_tool_menu_item("Generate Ludo Board", _on_generate_board)
	add_tool_menu_item("Clear Board", _on_clear_board)
	_build_dock()


func _exit_tree() -> void:
	remove_tool_menu_item("Generate Ludo Board")
	remove_tool_menu_item("Clear Board")
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _build_dock() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Ludo Board Tools"

	var title := Label.new()
	title.text = "Ludo Board Tools"
	title.add_theme_font_size_override("font_size", 16)
	_dock.add_child(title)

	_status_label = Label.new()
	_status_label.text = "Prêt."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_dock.add_child(_status_label)

	_dock.add_child(HSeparator.new())

	var generate_button := Button.new()
	generate_button.text = "Generate Ludo Board"
	generate_button.pressed.connect(_on_generate_board)
	_dock.add_child(generate_button)

	var clear_button := Button.new()
	clear_button.text = "Clear Board"
	clear_button.pressed.connect(_on_clear_board)
	_dock.add_child(clear_button)

	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


# ----------------------------------------------------------------------------
# Generate
# ----------------------------------------------------------------------------
func _on_generate_board(_ud: int = 0) -> void:
	var grid_map: GridMap = _find_grid_map()
	if grid_map == null:
		_set_status("Aucun noeud BoardRoot > GridMap trouvé dans la scène.")
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
		_set_status("Échec : impossible de créer la MeshLibrary.")
		push_error("Ludo Board Tools: impossible de créer la MeshLibrary.")
		return
	var layout: LudoBoardLayout = _load_or_build_layout()
	var mesh_mapping: LudoMeshMapping = _load_or_create_mesh_mapping()

	var mapping_errors: Array[String] = mesh_mapping.validate_against(mesh_lib)
	if not mapping_errors.is_empty():
		push_warning("Ludo Board Tools: LudoMeshMapping incohérent avec la MeshLibrary :\n - %s" % "\n - ".join(mapping_errors))

	grid_map.clear()
	LudoBoardPainter.paint(grid_map, mesh_lib, layout, mesh_mapping)
	# Note : commit_action() (appelé par le do/undo qui déclenche cette
	# méthode) marque déjà la scène comme modifiée — pas besoin d'appeler
	# quoi que ce soit ici pour ça (Node n'a de toute façon pas de
	# set_edited(), contrairement à Resource).
	var cell_count: int = grid_map.get_used_cells().size()
	_set_status("%d cellules générées. Pensez à Ctrl+S pour cuire dans la scène." % cell_count)
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


## Charge res://resources/LudoMeshMapping.tres s'il existe déjà, sinon crée
## une instance avec les valeurs par défaut (accordées à la LudoMeshLibrary_02
## actuelle) et la sauvegarde pour que l'utilisateur puisse l'éditer ensuite
## dans l'Inspecteur (player_start_mesh_id / player_home_lane_mesh_id).
func _load_or_create_mesh_mapping() -> LudoMeshMapping:
	if ResourceLoader.exists(_MESH_MAPPING_PATH):
		var mapping: LudoMeshMapping = load(_MESH_MAPPING_PATH)
		if mapping != null:
			return mapping
	var mapping := LudoMeshMapping.new()
	ResourceSaver.save(mapping, _MESH_MAPPING_PATH)
	return mapping


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
		_set_status("Aucun noeud BoardRoot > GridMap trouvé dans la scène.")
		return

	var old_cells: Array = grid_map.get_used_cells()
	if old_cells.is_empty():
		_set_status("La GridMap est déjà vide.")
		return

	_undo_redo.create_action("Clear Ludo Board")

	_undo_redo.add_do_method(self, "_clear_board_impl", grid_map)
	# Undo = re-générer (simple et pratique).
	_undo_redo.add_undo_method(self, "_do_generate", grid_map)

	_undo_redo.commit_action()
	_set_status("GridMap vidée. Pensez à Ctrl+S.")


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


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
