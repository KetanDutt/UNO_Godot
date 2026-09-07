extends Reference
# CardTypes
# ---------
# Central vocabulary for the whole project: colour / value enums, display names,
# official UNO scoring values and the asset key used to resolve card artwork.
#
# Everything here is `static` or `const` so the script can be preloaded and used
# without instancing, and so the pure rules layer stays free of engine state.

enum CardColor { RED = 0, YELLOW = 1, GREEN = 2, BLUE = 3, WILD = 4 }

enum CardValue {
	N0 = 0,
	N1 = 1,
	N2 = 2,
	N3 = 3,
	N4 = 4,
	N5 = 5,
	N6 = 6,
	N7 = 7,
	N8 = 8,
	N9 = 9,
	SKIP = 10,
	REVERSE = 11,
	DRAW_TWO = 12,
	WILD = 13,
	WILD_DRAW_FOUR = 14
}

# Colours that can actually be "active" on the table (wild is a placeholder).
const PLAYABLE_COLORS = [CardColor.RED, CardColor.YELLOW, CardColor.GREEN, CardColor.BLUE]

const COLOR_NAMES = ["Red", "Yellow", "Green", "Blue", "Wild"]

# Asset filename fragment for each colour, e.g. "Red_Skip.png".
const COLOR_ASSET_KEYS = ["Red", "Yellow", "Green", "Blue", "Wild"]

const VALUE_NAMES = [
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"Skip", "Reverse", "Draw Two", "Wild", "Wild Draw Four"
]

# Suffix used by the shipped artwork. Numbers use their digit, actions use words.
const VALUE_ASSET_KEYS = [
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"Skip", "Reverse", "Draw", "Wild", "Wild_Draw"
]

# Tint used for HUD chips, particles and glows. Kept slightly desaturated from
# pure RGB so it reads well against the felt table art.
const COLOR_VALUES = [
	Color(0.90, 0.16, 0.16, 1.0),
	Color(1.00, 0.78, 0.10, 1.0),
	Color(0.13, 0.70, 0.28, 1.0),
	Color(0.13, 0.42, 0.92, 1.0),
	Color(0.16, 0.16, 0.20, 1.0)
]

# Accessible markers shown next to the active colour for colour-blind players.
#
# These are deliberately plain letters: the bundled Roboto faces contain no
# geometric-shape or arrow glyphs (U+25A0, U+2605, U+21BB and friends are all
# absent), so the obvious triangle/circle/square set rendered as empty tofu
# boxes. Letters are unambiguous, always available, and readable at small sizes.
const COLOR_GLYPHS = ["R", "B", "G", "Y", "W"]

const SCORE_ACTION = 20
const SCORE_WILD = 50


static func is_wild(value: int) -> bool:
	return value == CardValue.WILD or value == CardValue.WILD_DRAW_FOUR


static func is_number(value: int) -> bool:
	return value >= CardValue.N0 and value <= CardValue.N9


static func is_action(value: int) -> bool:
	return value == CardValue.SKIP or value == CardValue.REVERSE or value == CardValue.DRAW_TWO


static func color_name(color: int) -> String:
	if color < 0 or color >= COLOR_NAMES.size():
		return "Unknown"
	return COLOR_NAMES[color]


static func color_glyph(color: int) -> String:
	if color < 0 or color >= COLOR_GLYPHS.size():
		return ""
	return COLOR_GLYPHS[color]


static func value_name(value: int) -> String:
	if value < 0 or value >= VALUE_NAMES.size():
		return "Unknown"
	return VALUE_NAMES[value]


static func color_value(color: int) -> Color:
	if color < 0 or color >= COLOR_VALUES.size():
		return COLOR_VALUES[CardColor.WILD]
	return COLOR_VALUES[color]


# Asset key such as "Red_Skip", "Blue_7", "Wild" or "Wild_Draw".
static func asset_key(color: int, value: int) -> String:
	if is_wild(value):
		return VALUE_ASSET_KEYS[value]
	return COLOR_ASSET_KEYS[color] + "_" + VALUE_ASSET_KEYS[value]


# Official UNO scoring: numbers are face value, actions 20, wilds 50.
static func score_for(value: int) -> int:
	if is_number(value):
		return value
	if is_wild(value):
		return SCORE_WILD
	return SCORE_ACTION
