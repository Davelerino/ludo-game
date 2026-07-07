## Shared enums used across the whole plugin.
## Kept in a single small script (instead of duplicating enums in every
## Resource) so gameplay code (RuleEngine, PawnController, AI...) can rely on
## one canonical source of truth: LudoBoardEnums.PlayerColor / CellType.
class_name LudoBoardEnums
extends RefCounted

enum PlayerColor {
	NONE = -1,
	RED = 0,
	BLUE = 1,
	GREEN = 2,
	YELLOW = 3,
}

enum CellType {
	RING,          ## Regular ring lane cell, shared by all players.
	START,         ## A player's entry point on the ring lane.
	HOME,          ## A cell inside a player's private home lane.
	CENTER,        ## Final cell of a home lane (the "finish" tile).
	SAFE,          ## Reserved for future variants (e.g. safe/star tiles).
}

static func color_name(color: int) -> String:
	match color:
		PlayerColor.RED:
			return "RED"
		PlayerColor.BLUE:
			return "BLUE"
		PlayerColor.GREEN:
			return "GREEN"
		PlayerColor.YELLOW:
			return "YELLOW"
		_:
			return "NONE"

static func cell_type_name(type: int) -> String:
	match type:
		CellType.RING:
			return "RING"
		CellType.START:
			return "START"
		CellType.HOME:
			return "HOME"
		CellType.CENTER:
			return "CENTER"
		CellType.SAFE:
			return "SAFE"
		_:
			return "UNKNOWN"

## Canonical iteration order for the 4 colors.
static func all_colors() -> Array[int]:
	return [PlayerColor.RED, PlayerColor.BLUE, PlayerColor.GREEN, PlayerColor.YELLOW]
