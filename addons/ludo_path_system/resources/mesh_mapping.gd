## Table de correspondance player_id -> item id de MeshLibrary, pour peindre
## chaque joueur avec une identité visuelle distincte (start tile sur
## l'anneau + couloir final). Concern PUREMENT visuel/asset : ne référence
## jamais LudoBoardLayout (géométrie logique) — les deux restent découplés,
## comme LudoBoardLayout est déjà découplé de la GridMap.
##
## Les valeurs par défaut correspondent au fichier actuel
## res://resources/LudoMeshLibrary_02.tres (5 items : 0=SM_Ludo_SimplePath
## "anneau uniforme", 1=RedTile, 2=GreenTile, 3=BlueTile, 4=YellowTile) —
## à ré-assigner à la main dans l'Inspecteur si la MeshLibrary change.
@tool
class_name LudoMeshMapping
extends Resource

## Item "anneau" par défaut, utilisé pour toutes les cases de l'anneau qui ne
## sont la start tile d'aucun joueur.
@export var ring_mesh_id: int = 0

## Item de la case de centre partagée (dernière case de chaque home_path).
## -1 = non assigné -> fallback sur ring_mesh_id (la LudoMeshLibrary_02
## actuelle n'a pas encore de mesh "Center" dédié).
@export var center_mesh_id: int = -1

## Item de la start tile de l'anneau de chaque joueur, indexé par player_id
## (0=BLUE, 1=GREEN, 2=RED, 3=YELLOW selon BoardConfig/LudoClassicLayoutBuilder).
## Défaut : Blue=3, Green=2, Red=1, Yellow=4 (ordre des items dans le
## fichier .tres actuel, PAS player_id+1 — l'ordre des couleurs dans le
## fichier ne correspond pas à l'ordre des bras BLUE/GREEN/RED/YELLOW).
@export var player_start_mesh_id: Array[int] = [3, 2, 1, 4]

## Item du couloir final de chaque joueur (hors case de centre). Tableau
## séparé de player_start_mesh_id : réutilise les mêmes ids aujourd'hui
## (aucune variante colorée de SM_Ludo_HomePath.glb n'existe encore), mais
## permet de diverger dès qu'un mesh de couloir dédié est ajouté.
@export var player_home_lane_mesh_id: Array[int] = [3, 2, 1, 4]


func get_ring_mesh_id() -> int:
	return ring_mesh_id


func get_center_mesh_id() -> int:
	return center_mesh_id if center_mesh_id >= 0 else ring_mesh_id


func get_start_mesh_id(player_id: int) -> int:
	return _safe_get(player_start_mesh_id, player_id)


func get_home_lane_mesh_id(player_id: int) -> int:
	return _safe_get(player_home_lane_mesh_id, player_id)


func _safe_get(ids: Array[int], player_id: int) -> int:
	if player_id < 0 or player_id >= ids.size() or ids[player_id] < 0:
		push_warning("LudoMeshMapping: pas d'item assigné pour player_id=%d, fallback ring_mesh_id." % player_id)
		return ring_mesh_id
	return ids[player_id]


## Cohérence structurelle (tailles de tableaux). Voir validate_against() pour
## vérifier que les ids existent réellement dans une MeshLibrary donnée.
func validate() -> Array[String]:
	var errors: Array[String] = []
	if player_start_mesh_id.size() != BoardConfig.PLAYER_COUNT:
		errors.append("LudoMeshMapping: player_start_mesh_id doit contenir %d entrées (trouvé %d)." % [BoardConfig.PLAYER_COUNT, player_start_mesh_id.size()])
	if player_home_lane_mesh_id.size() != BoardConfig.PLAYER_COUNT:
		errors.append("LudoMeshMapping: player_home_lane_mesh_id doit contenir %d entrées (trouvé %d)." % [BoardConfig.PLAYER_COUNT, player_home_lane_mesh_id.size()])
	return errors


## Vérifie que tous les ids référencés existent réellement dans mesh_lib.
## À appeler depuis le plugin éditeur (pas depuis LudoBoardPainter.paint(),
## qui doit rester une fonction pure) pour avertir clairement si la
## MeshLibrary a divergé du mapping.
func validate_against(mesh_lib: MeshLibrary) -> Array[String]:
	var errors: Array[String] = []
	if mesh_lib == null:
		errors.append("LudoMeshMapping: MeshLibrary null.")
		return errors

	var known_ids: Array = mesh_lib.get_item_list()
	var to_check: Array[int] = [ring_mesh_id]
	if center_mesh_id >= 0:
		to_check.append(center_mesh_id)
	to_check.append_array(player_start_mesh_id)
	to_check.append_array(player_home_lane_mesh_id)

	for id in to_check:
		if id not in known_ids:
			errors.append("LudoMeshMapping: item id %d absent de la MeshLibrary." % id)
	return errors
