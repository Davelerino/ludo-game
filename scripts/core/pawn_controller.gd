class_name PawnController
extends Node
## ============================================================================
## PawnController — Pont entre l'état logique d'un pion et sa représentation 3D.
##
## RESPONSABILITÉS (§11.1)
##   - Convertir un pion logique (Dictionary du RuleEngine) en position 3D sur
##     le plateau (GridMap), en interrogeant BoardManager pour la géométrie.
##   - Animer le déplacement visuel d'un pion (tween) sans toucher à la logique.
##   - Gérer la sélection du pion par le joueur (clic souris / input map,
##     GDD §11.6/15) et lever un signal de sélection vers le TurnManager.
##   - Publier pawn_moved / pawn_captured sur GameEvents (§11.2).
##
## DÉPENDANCES
##   - BoardManager (pour grid_map + cell_of(pawn) -> Vector3i).
##   - GameEvents (autoload).
##   - RuleEngine indirectement : il ne valide RIEN, il consomme l'état dicté
##     par le TurnManager/RuleEngine. Le PawnController ne mut jamais
##     pawn.state / pawn.progress (c'est le rôle de RuleEngine.apply_move()).
##
## NOTE : ici c'est un SQUELETTE. L'instanciation des MeshInstance3D réels et
## le tween visuel seront branchés une fois les assets 3D disponibles. La
## structure des signaux et la signature publique sont définitives.
## ============================================================================

const PawnState := BoardConfig.PawnState

# --- Références à rattacher dans l'inspecteur / au _ready() ---
@export var board_manager: BoardManager

# --- Noeuds 3D des pions, indexés par pawn.id ---
# En attendant les vrais meshes, on stocke des Marker3D invisibles pour que la
# scène compile et que la sélection fonctionne (raycast sur la position).
var _pawn_nodes: Dictionary = {}  # pawn.id -> Node3D

# --- Sélection courante ---
var selected_pawn_id: int = -1

## Émis quand le joueur sélectionne un de ses pions cliquable. Le TurnManager
## écoute ce signal pour déclencher apply_move() via le RuleEngine.
signal pawn_selected(pawn: Dictionary)


## Instancie un noeud 3D (placeholder) par pion et le place sur son yard.
func setup(all_pawns: Array) -> void:
	clear()
	for pawn in all_pawns:
		var node := Marker3D.new()
		node.name = "Pawn_%d" % pawn.id
		node.position = board_manager.cell_world_position(pawn)
		_pawn_nodes[pawn.id] = node
		add_child(node)


## Détruit tous les noeuds de pions (nouvelle partie).
func clear() -> void:
	for node in _pawn_nodes.values():
		if is_instance_valid(node):
			node.queue_free()
	_pawn_nodes.clear()
	selected_pawn_id = -1


## Met à jour la position 3D d'un pion après un coup, avec animation optionnelle.
## Ne change QUE la transform visuelle ; l'état logique a déjà été muté par le
## RuleEngine au moment de l'appel.
func move_pawn_visual(pawn: Dictionary, animate: bool = true) -> void:
	var node: Node3D = _pawn_nodes.get(pawn.id)
	if node == null or not is_instance_valid(node):
		return
	var target: Vector3 = board_manager.cell_world_position(pawn)
	if not animate:
		node.position = target
		return
	# Tween linéaire simple (placeholder) ; à remplacer par une courbe d'arc.
	var tween: Tween = create_tween()
	tween.tween_property(node, "position", target, 0.35)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	# L'émission de pawn_moved se fait après l'animation.
	tween.finished.connect(func():
		GameEvents.pawn_moved.emit(pawn, _last_dice_for(pawn))
	, CONNECT_ONE_SHOT)


## Renvoie un pion cliquable par le joueur actif (sélection souris, §11.6).
## `legal_ids` est la liste des ids autorisés par RuleEngine.get_legal_target_pawns().
func request_selection(player_id: int, legal_ids: Array) -> void:
	# Squelette : dans la version finale on mettra en surbrillance les pions de
	# legal_ids et on attendra un clic. Pour l'instant on prend le 1er légal.
	if legal_ids.is_empty():
		return
	select_pawn(legal_ids[0])


## Marque un pion comme sélectionné et notifie le TurnManager.
func select_pawn(pawn_id: int) -> void:
	selected_pawn_id = pawn_id
	var pawn: Dictionary = board_manager.get_pawn_by_id(pawn_id)
	if not pawn.is_empty():
		pawn_selected.emit(pawn)


# --- Entrée souris (sélection de pion, GDD §11.6/15) -------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pawn_select"):
		# TODO final : raycast depuis la caméra vers _pawn_nodes, puis select_pawn().
		# Le squelette ne fait rien ici tant qu'on n'a pas de meshes cliquables.
		pass


# --- interne -----------------------------------------------------------------
var _last_dice_map: Dictionary = {}  # pawn.id -> dice_value (pour le signal)

func _last_dice_for(pawn: Dictionary) -> int:
	return _last_dice_map.get(pawn.id, 0)
