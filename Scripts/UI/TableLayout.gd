extends Reference
# TableLayout
# -----------
# Single source of truth for where everything sits on screen. The HUD, the card
# fans and the controller all read their geometry from here, so the composition
# can be reasoned about - and unit tested - in one place.
#
# The original code scattered hand-tuned margins across the codebase, which is
# why widgets collided or drifted off-screen at anything other than 1280x720.
#
# The screen is divided into a stack of horizontal bands, measured top-down:
#
#   +--------------------------------------------------+
#   | top HUD    status pill / deck counts / scores     |  <- BAND_TOP_HUD
#   | opponent fan(s)                                   |  <- opponent cards
#   | opponent name plates                              |
#   | deck + discard row, colour chip, direction        |  <- play row
#   | player fan                                        |  <- your hand
#   +--------------------------------------------------+
#                                    action buttons run
#                                    down the right edge
#
# Band heights are derived from the real rendered card size (including the
# rotation of the outermost fan cards, which is what used to clip off-screen),
# and the leftover space is shared out as even gaps. Tests/TestLayout.gd asserts
# that no two bands overlap and that nothing escapes the viewport.

const CARD_TEXTURE_W = 388.0
const CARD_TEXTURE_H = 562.0

const REFERENCE = Vector2(1280, 720)
const MAX_SCALE = 1.32

# Card scale at the reference resolution.
const PLAYER_CARD_SCALE = 0.31
# Opponent cards are smaller - they are information, not playfield.
const OPPONENT_SCALE_RATIO = 0.70

const BUTTON_COLUMN_WIDTH = 176.0
const EDGE_MARGIN = 20.0

const MAX_SPACING_RATIO = 0.62   # of card width
const MIN_SPACING_RATIO = 0.17
const MAX_FAN_ANGLE = 4.6        # degrees between neighbouring cards
const MAX_TOTAL_ANGLE = 22.0     # total sweep across the whole fan
const ARC_DEPTH = 0.14           # bow height as a fraction of fan width
const ARC_CAP_RATIO = 0.18       # ... never more than this much of card height

# The player's fan is deliberately narrower than the play area: a hand stretched
# edge to edge reads badly and leaves nowhere for the seat plate.
const PLAYER_FAN_WIDTH_RATIO = 0.62
const PLATE_HEIGHT = 32.0
const BOTTOM_MARGIN = 18.0
const MIN_GAP = 6.0
const MAX_GAP = 26.0


# Uniform shrink factor applied below the reference resolution so the whole
# composition keeps its proportions instead of clipping.
# Below the reference size everything shrinks together; above it the
# composition is allowed to grow a little so large displays do not end up with
# a small island of cards floating in a sea of felt.
static func scale_factor(viewport: Vector2) -> float:
	return clamp(min(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y), 0.58, MAX_SCALE)


static func player_card_scale(viewport: Vector2) -> float:
	return PLAYER_CARD_SCALE * scale_factor(viewport)


static func opponent_card_scale(viewport: Vector2) -> float:
	return player_card_scale(viewport) * OPPONENT_SCALE_RATIO


static func card_size(scale: float) -> Vector2:
	return Vector2(CARD_TEXTURE_W * scale, CARD_TEXTURE_H * scale)


# Half-height of a card rotated by the widest angle a fan can reach. This is the
# measurement that matters for clipping - an upright card fits, but the tilted
# outer cards of a fan need noticeably more room.
static func rotated_half_height(scale: float) -> float:
	var size = card_size(scale)
	var angle = deg2rad(MAX_TOTAL_ANGLE * 0.5)
	return (size.x * abs(sin(angle)) + size.y * abs(cos(angle))) * 0.5


static func rotated_half_width(scale: float) -> float:
	var size = card_size(scale)
	var angle = deg2rad(MAX_TOTAL_ANGLE * 0.5)
	return (size.x * abs(cos(angle)) + size.y * abs(sin(angle))) * 0.5


static func arc_height(fan_width: float, scale: float) -> float:
	return min(max(fan_width, 0.0) * ARC_DEPTH, card_size(scale).y * ARC_CAP_RATIO)


# Width reserved on the right for the vertical action-button column.
static func button_column_width(viewport: Vector2) -> float:
	return BUTTON_COLUMN_WIDTH * scale_factor(viewport)


# Horizontal centre of the play area (everything left of the button column).
static func play_center_x(viewport: Vector2) -> float:
	return (viewport.x - button_column_width(viewport)) * 0.5


static func play_width(viewport: Vector2) -> float:
	return viewport.x - button_column_width(viewport)


# ---------------------------------------------------------------------------
# Vertical band solver
# ---------------------------------------------------------------------------
# Returns every horizontal guide line the rest of the layout is built from.
static func metrics(viewport: Vector2, opponent_count: int = 1) -> Dictionary:
	var s = scale_factor(viewport)
	var player_scale = player_card_scale(viewport)
	var opponent_scale = opponent_card_scale(viewport)

	var player_card = card_size(player_scale)

	var player_half = rotated_half_height(player_scale)
	var opponent_half = rotated_half_height(opponent_scale)

	var player_arc = arc_height(player_fan_width(viewport), player_scale)
	var opponent_arc = arc_height(opponent_fan_width(viewport, opponent_count), opponent_scale)

	var top_hud_h = 66.0 * s
	var plate_h = PLATE_HEIGHT * s
	var opponent_fan_h = opponent_half * 2.0 + opponent_arc
	var deck_row_h = player_card.y
	var player_fan_h = player_half * 2.0 + player_arc
	var bottom = BOTTOM_MARGIN * s

	# Four gaps separate the five bands. Share the slack evenly.
	var content = top_hud_h + opponent_fan_h + plate_h + deck_row_h + player_fan_h
	var slack = viewport.y - content - bottom - 14.0 * s
	var gap = clamp(slack / 4.0, MIN_GAP * s, MAX_GAP * s)

	var top_hud_top = 14.0 * s
	var opponent_fan_top = top_hud_top + top_hud_h + gap
	# The fan bows downward, so its flat outer edges define the top.
	var opponent_center_y = opponent_fan_top + opponent_half
	var opponent_fan_bottom = opponent_center_y + opponent_arc + opponent_half

	var plate_center_y = opponent_fan_bottom + gap + plate_h * 0.5

	# The player's fan hangs off the bottom edge.
	var player_center_y = viewport.y - bottom - player_half
	var player_top = player_center_y - player_arc - player_half

	# The play row (deck + discard) then takes the centre of whatever space is
	# left between the opponent plates and the player's hand. On a tall window
	# this keeps the table visually balanced instead of top-heavy.
	var free_top = plate_center_y + plate_h * 0.5
	var deck_center_y = (free_top + player_top) * 0.5
	deck_center_y = max(deck_center_y, free_top + gap + deck_row_h * 0.5)

	# If the window is too short for that, push the fan down instead.
	var earliest = deck_center_y + deck_row_h * 0.5 + gap + player_arc + player_half
	player_center_y = max(player_center_y, earliest)

	return {
		"scale": s,
		"gap": gap,
		"player_scale": player_scale,
		"opponent_scale": opponent_scale,
		"top_hud_top": top_hud_top,
		"top_hud_height": top_hud_h,
		"opponent_center_y": opponent_center_y,
		"opponent_plate_y": plate_center_y,
		"deck_center_y": deck_center_y,
		"player_center_y": player_center_y,
		"player_half": player_half,
		"opponent_half": opponent_half,
		"player_arc": player_arc,
		"opponent_arc": opponent_arc
	}


# --- table furniture -------------------------------------------------------
static func deck_row_y(viewport: Vector2) -> float:
	return metrics(viewport)["deck_center_y"]


# The draw pile sits immediately left of the discard so the two read as one
# "play row" rather than two unrelated islands.
static func deck_position(viewport: Vector2) -> Vector2:
	var card = card_size(player_card_scale(viewport))
	var offset = card.x * 1.35
	var x = max(play_center_x(viewport) - offset, EDGE_MARGIN + card.x * 0.5)
	return Vector2(x, deck_row_y(viewport))


static func discard_position(viewport: Vector2) -> Vector2:
	return Vector2(play_center_x(viewport), deck_row_y(viewport))


# --- hands -----------------------------------------------------------------
static func player_anchor(viewport: Vector2) -> Vector2:
	return Vector2(play_center_x(viewport), metrics(viewport)["player_center_y"])


# Horizontal extent the player's fan may occupy.
static func player_fan_width(viewport: Vector2) -> float:
	var center = play_center_x(viewport)
	var right_bound = viewport.x - button_column_width(viewport) - EDGE_MARGIN
	var reach = min(center - EDGE_MARGIN, right_bound - center) * 2.0
	return min(play_width(viewport) * PLAYER_FAN_WIDTH_RATIO, reach)


static func opponent_fan_width(viewport: Vector2, opponent_count: int) -> float:
	var width = play_width(viewport)
	if opponent_count <= 1:
		return width * 0.30
	if opponent_count == 2:
		return width * 0.25
	return width * 0.21


static func opponent_anchor(viewport: Vector2, seat_index: int, opponent_count: int) -> Vector2:
	var y = metrics(viewport, opponent_count)["opponent_center_y"]
	var center = play_center_x(viewport)

	if opponent_count <= 1:
		return Vector2(center, y)

	# Two or three opponents share the top row. Clamp each anchor so even a
	# fully compressed fan stays inside the play area.
	var fan_half = _fan_extent(viewport, opponent_count) * 0.5
	var left_bound = EDGE_MARGIN + fan_half
	var right_bound = viewport.x - button_column_width(viewport) - EDGE_MARGIN - fan_half
	if right_bound < left_bound:
		return Vector2(center, y)

	var span = play_width(viewport) * 0.62
	var x = center
	if opponent_count == 2:
		x = center + (span * 0.5 if seat_index == 1 else -span * 0.5)
	else:
		x = center + (seat_index - 1) * span * 0.5

	return Vector2(clamp(x, left_bound, right_bound), y)


# Worst-case rendered width of an opponent fan (minimum spacing, many cards).
static func _fan_extent(viewport: Vector2, opponent_count: int) -> float:
	var scale = opponent_card_scale(viewport)
	var size = card_size(scale)
	var budget = opponent_fan_width(viewport, opponent_count)
	var min_spacing = size.x * MIN_SPACING_RATIO
	var floor_width = min_spacing * 29.0 + rotated_half_width(scale) * 2.0
	return max(budget, min(floor_width, play_width(viewport) * 0.44))


# Where a seat's name plate sits (centre point).
static func seat_plate_position(viewport: Vector2, seat: int, opponent_count: int) -> Vector2:
	var s = scale_factor(viewport)
	if seat == 0:
		# Bottom-left, in the gap the narrowed player fan leaves free.
		var half_plate = 70.0
		return Vector2(
			max(EDGE_MARGIN + 76.0 * s, half_plate + 4.0),
			viewport.y - max(PLATE_HEIGHT * s, 18.0))
	var anchor = opponent_anchor(viewport, seat - 1, opponent_count)
	return Vector2(anchor.x, metrics(viewport, opponent_count)["opponent_plate_y"])


# --- HUD rectangles --------------------------------------------------------
# Returned as {position, size} so both the HUD and the layout test agree.
static func status_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	var width = min(520.0 * s, play_width(viewport) - 300.0 * s)
	width = max(width, 240.0 * s)
	return {
		"position": Vector2(play_center_x(viewport) - width * 0.5, 14.0 * s),
		"size": Vector2(width, 44.0 * s)
	}


static func deck_counts_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	return {
		"position": Vector2(EDGE_MARGIN, 14.0 * s),
		"size": Vector2(200.0 * s, 50.0 * s)
	}


static func score_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	# Right-aligned against the same edge as the button column, and never wider
	# than the space between the status pill and that edge.
	var right = viewport.x - EDGE_MARGIN * 0.8
	var status = status_rect(viewport)
	var available = right - (status["position"].x + status["size"].x) - 12.0 * s
	var width = clamp(250.0 * s, 132.0, max(available, 132.0))
	return {
		"position": Vector2(right - width, 14.0 * s),
		"size": Vector2(width, 92.0 * s)
	}


static func color_chip_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	var size = Vector2(140.0 * s, 40.0 * s)
	var half = card_size(player_card_scale(viewport)) * 0.5
	var center = Vector2(
		play_center_x(viewport) + half.x + 26.0 * s + size.x * 0.5,
		deck_row_y(viewport) - 24.0 * s)
	return {"position": center - size * 0.5, "size": size}


static func direction_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	var size = Vector2(52.0 * s, 40.0 * s)
	var chip = color_chip_rect(viewport)
	var center = Vector2(
		chip["position"].x + size.x * 0.5,
		chip["position"].y + chip["size"].y + 12.0 * s + size.y * 0.5)
	return {"position": center - size * 0.5, "size": size}


static func stack_rect(viewport: Vector2) -> Dictionary:
	var s = scale_factor(viewport)
	var size = Vector2(70.0 * s, 38.0 * s)
	var half = card_size(player_card_scale(viewport)) * 0.5
	# Lower-right shoulder of the discard pile: reads as a badge on the stack,
	# clear of the seat plates above and the player's fan below.
	var center = Vector2(
		play_center_x(viewport) + half.x * 0.80,
		deck_row_y(viewport) + half.y * 0.72)
	return {"position": center - size * 0.5, "size": size}


static func button_column_rect(viewport: Vector2, button_count: int) -> Dictionary:
	var s = scale_factor(viewport)
	var button_height = 46.0 * s
	var separation = 8.0 * s
	var height = button_count * button_height + max(button_count - 1, 0) * separation
	var width = (BUTTON_COLUMN_WIDTH - 32.0) * s
	var x = viewport.x - width - 16.0 * s
	var top_hud = score_rect(viewport)
	var lowest = top_hud["position"].y + top_hud["size"].y + 14.0 * s
	var y = max((viewport.y - height) * 0.5, lowest)
	return {
		"position": Vector2(x, y),
		"size": Vector2(width, height),
		"button_height": button_height,
		"separation": separation
	}


# ---------------------------------------------------------------------------
# Fan geometry
# ---------------------------------------------------------------------------
# Returns an Array of {position, rotation, z} for `count` cards.
#
#   center    - anchor point of the fan
#   max_width - total horizontal extent the fan must fit inside
#   arc_up    - true bows the fan upward (player), false downward (opponents)
#   scale     - card scale, used to derive spacing and arc height
static func fan(center: Vector2, count: int, max_width: float, arc_up: bool, scale: float) -> Array:
	var layout = []
	if count <= 0:
		return layout

	var size = card_size(scale)
	if count == 1:
		layout.append({"position": center, "rotation": 0.0, "z": 0})
		return layout

	var max_spacing = size.x * MAX_SPACING_RATIO
	var min_spacing = size.x * MIN_SPACING_RATIO
	# The fan's full extent is max_width, so the card centres span
	# max_width - card_width.
	var usable = max(max_width - size.x, size.x * 0.5)
	var spacing = clamp(usable / float(count - 1), min_spacing, max_spacing)

	var total_width = spacing * (count - 1)
	var start_x = center.x - total_width * 0.5

	var per_card_angle = min(MAX_FAN_ANGLE, MAX_TOTAL_ANGLE / float(count - 1))
	var start_angle = -per_card_angle * (count - 1) * 0.5

	var bow = arc_height(total_width, scale)

	for i in range(count):
		var t = float(i) / float(count - 1)
		var centered = (t - 0.5) * 2.0
		# Parabolic arc: peaks in the middle, flat at the ends.
		var lift = (1.0 - centered * centered) * bow
		var y = center.y - lift if arc_up else center.y + lift
		var angle = start_angle + per_card_angle * i
		if not arc_up:
			angle = -angle
		layout.append({
			"position": Vector2(start_x + spacing * i, y),
			"rotation": angle,
			"z": i
		})

	return layout


# Bounding box of a fan, accounting for each card's rotation. The naive
# axis-aligned box under-reports by ~25px per card at these angles, which is
# exactly how the player's hand ended up clipped by the bottom of the screen.
static func fan_bounds(center: Vector2, count: int, max_width: float,
		arc_up: bool, scale: float) -> Dictionary:
	var slots = fan(center, count, max_width, arc_up, scale)
	if slots.empty():
		return {"position": center, "size": Vector2.ZERO}

	var size = card_size(scale)
	var min_point = Vector2(INF, INF)
	var max_point = Vector2(-INF, -INF)

	for slot in slots:
		var pos = slot["position"]
		var angle = deg2rad(slot["rotation"])
		var half_w = (size.x * abs(cos(angle)) + size.y * abs(sin(angle))) * 0.5
		var half_h = (size.x * abs(sin(angle)) + size.y * abs(cos(angle))) * 0.5
		min_point.x = min(min_point.x, pos.x - half_w)
		min_point.y = min(min_point.y, pos.y - half_h)
		max_point.x = max(max_point.x, pos.x + half_w)
		max_point.y = max(max_point.y, pos.y + half_h)

	return {"position": min_point, "size": max_point - min_point}
