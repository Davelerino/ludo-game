extends Node
## Example: how a gameplay system (RuleEngine, PawnController, AI...) consumes
## the BoardData produced by the Ludo Board Generator plugin.
##
## Note this script never touches a GridMap - it only loads the generated
## LudoBoardData resource, exactly the separation the spec requires.
##
## Usage: attach to any Node in a test scene, run the scene, read the Output
## panel. Generate a board with the plugin dock first so the .tres exists.

@export_file("*.tres") var board_data_path: String = "res://addons/ludo_board_generator/generated/board_data.tres"


func _ready() -> void:
	if not ResourceLoader.exists(board_data_path):
		push_error("No BoardData found at %s. Generate a board first using the plugin dock." % board_data_path)
		return

	var data: LudoBoardData = load(board_data_path)

	print("Ring lane length: %d | Home lane length: %d" % [data.ring_lane_length, data.home_lane_length])

	for color in data.player_paths.keys():
		var path: LudoPlayerPath = data.get_player_path(color)
		print("%s: start ring index %d (%s) | home entry index %d | centre cell id %d" % [
			LudoBoardEnums.color_name(color),
			path.ring_entry_index,
			path.start_tile_position,
			path.home_entry_index,
			path.center_cell_id,
		])

	# Example straight from GDD §4.1: resolve a pawn's world position from
	# its color and its `progress` counter, with zero GridMap involved.
	var example_color := LudoBoardEnums.PlayerColor.RED
	for progress in [0, 5, 50, 51, 55, 56]:
		var pos := data.resolve_position(example_color, progress)
		print("RED pawn at progress=%d -> position %s" % [progress, pos])

	# Example: naive "is this ring cell a barrier-eligible landing spot"
	# check a RuleEngine might build on top of BoardData (barrier/capture
	# logic itself is NOT part of this plugin - only the read-only board
	# query primitives are).
	var ring_cell := data.get_ring_cell(13)
	print("Ring cell #13 is a %s tile owned by %s." % [
		LudoBoardEnums.cell_type_name(ring_cell.type),
		LudoBoardEnums.color_name(ring_cell.color),
	])
