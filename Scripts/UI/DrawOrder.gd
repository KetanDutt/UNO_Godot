extends Reference
# DrawOrder
# ---------
# Single source of truth for DEPTH - which part of the composition draws on
# top of which. TableLayout owns where everything sits on screen; this owns
# where everything sits in the stack.
#
# Two independent axes are at work:
#
#   * CanvasLayers separate the big strata. The world (table, deck, cards,
#     effects) renders in the default layer; the HUD, the colour flash, the
#     colour picker and the menus each own a CanvasLayer and render above the
#     world in `layer` order.
#   * Inside the world layer, every canvas item is sorted by effective z (a
#     child's z_index adds to its parent's), and Godot breaks ties in TREE
#     order - i.e. by spawn order, which is not the order things happened in.
#
# The original scheme ignored both facts: hand cards and the discard pile
# shared the z range 0..29, every discard past the sixth landed on the same
# z (ties then painted in deal order, so a freshly played card could slide
# UNDER the pile), and cards dealt from the deck flew beneath the deck backs.
#
# Each visual group now owns a band wide enough that groups can never collide,
# so the paint order is decided by these constants alone:
#
#   z    0      table felt
#   z   10-14   deck stack (the five face-down backs)
#   z   20-26   discard pile (bottom .. top, re-stamped on every play)
#   z   60-199  resting hand cards (index within the hand, any seat)
#   z  220      any card in transit - dealt, drawn, played or leaving
#   z  240      the hovered card, lifted out of its fan
#   z  280      the dragged card, held by the player
#   z  320+     particle bursts and floating text
#
# The clamps in the helpers below make the impossibility of collisions
# explicit: a hand can never hold more cards than the deck contains (108), so
# the hand band cannot reach the flight band.

# --- CanvasLayers, bottom to top ---------------------------------------------
# The world renders in the default layer 0; nothing else may use it.
const LAYER_HUD := 5
const LAYER_FLASH := 8
const LAYER_PICKER := 15
const LAYER_MENUS := 20

# --- World z bands, bottom to top ----------------------------------------------
const TABLE := 0
const DECK := 10
const DECK_DEPTH := 5
const DISCARD := 20
const PILE_DEPTH := 6
const HANDS := 60
const HAND_SPAN := 140
const FLYING := 220
const HOVER := 240
const DRAG := 280
const EFFECTS := 320

# Relative to EFFECTS, used by EffectsDirector's pooled children.
const FX_PARTICLES := 5
const FX_TEXT := 20


# The i-th face-down back of the draw pile.
static func deck_back(index: int) -> int:
	return DECK + int(clamp(index, 0, DECK_DEPTH - 1))


# Depth within the discard pile; 1 is the bottom card, PILE_DEPTH the top.
static func discard(depth: int) -> int:
	return DISCARD + int(clamp(depth, 1, PILE_DEPTH))


# Depth of a card resting at `index` within any hand's fan.
static func hand(index: int) -> int:
	return HANDS + int(clamp(index, 0, HAND_SPAN - 1))
