extends SceneTree
# Layout regression tests.
#
#   godot --no-window -s Tests/TestLayout.gd
#
# Asserts the on-screen composition holds up across resolutions and hand sizes:
# nothing escapes the viewport, and the HUD regions, the deck row, the hands and
# the button column never overlap each other.
#
# This is the guard against the class of bug the original project shipped with -
# widgets hand-positioned for 1280x720 that collided at any other size.

const TableLayout = preload("res://Scripts/UI/TableLayout.gd")

var _passed := 0
var _failed := 0

const RESOLUTIONS = [
	Vector2(1280, 720),
	Vector2(1920, 1080),
	Vector2(1600, 900),
	Vector2(1366, 768),
	Vector2(1024, 600),
	Vector2(960, 540),
	Vector2(800, 480)
]

const HAND_SIZES = [1, 2, 5, 7, 12, 20, 30]


func _init() -> void:
	print("\n=== UNO layout test suite ===\n")

	test_no_overlap()
	test_hands_on_screen()
	test_fan_ordering()
	test_fan_fits_budget()
	test_seat_plates_visible()
	test_deck_and_discard_separated()
	test_scaling_monotonic()
	test_fonts_have_glyphs()
	test_hud_text_fits()

	print("\n=== %d passed, %d failed ===\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# Regression: HUD strings must fit the rectangles TableLayout gives them.
# At 800x480 the scoreboard header used to render wider than its panel and ran
# off the right-hand edge of the screen.
func test_hud_text_fits() -> void:
	print("-- HUD text fits its panels --")
	var ThemeFactory = load("res://Scripts/Systems/ThemeFactory.gd")
	var font_small = ThemeFactory.make_font(15, "medium", 3)
	var font_body = ThemeFactory.make_font(18, "medium")

	for viewport in RESOLUTIONS:
		# Worst-case scoreboard: four seats, three-digit scores.
		var score = _rect(TableLayout.score_rect(viewport))
		var short_header = "R%d  /  %d" % [9, 500]
		_check(font_small.get_string_size(short_header).x <= score.size.x + 1.0,
			"%dx%d: the abbreviated score header fits (%f > %f)" % [
				viewport.x, viewport.y,
				font_small.get_string_size(short_header).x, score.size.x])

		for name in ["CPU 3", "You"]:
			var row = "%s   %d" % [name, 500]
			_check(font_small.get_string_size(row).x <= score.size.x + 1.0,
				"%dx%d: score row '%s' fits" % [viewport.x, viewport.y, row])

		# The status pill wraps, but a short line must never overflow.
		var status = _rect(TableLayout.status_rect(viewport))
		var message = "Your turn - 3 playable cards."
		_check(font_body.get_string_size(message).x <= status.size.x + 1.0,
			"%dx%d: status '%s' fits (%f > %f)" % [
				viewport.x, viewport.y, message,
				font_body.get_string_size(message).x, status.size.x])

		# Deck counters.
		var counts = _rect(TableLayout.deck_counts_rect(viewport))
		_check(font_small.get_string_size("DECK  108").x <= counts.size.x + 1.0,
			"%dx%d: deck counter fits" % [viewport.x, viewport.y])

		# Action button captions.
		var column = TableLayout.button_column_rect(viewport, 5)
		var caption_font = ThemeFactory.make_font(16, "bold")
		for caption in ["DRAW", "PASS", "UNO!", "CATCH!", "SORT", "MENU"]:
			_check(caption_font.get_string_size(caption).x <= column["size"].x - 8.0,
				"%dx%d: button '%s' fits the column" % [viewport.x, viewport.y, caption])


# Regression: the bundled Roboto faces contain no arrow or geometric-shape
# glyphs, so decorative characters like U+25B2 or U+21BB used to render as
# empty tofu boxes in the HUD and the colour picker.
#
# Godot 3 has no "does this font have glyph X" query - a missing character is
# silently drawn as a notdef box whose advance width is identical for every
# unsupported codepoint. We detect that by measuring a character the font
# certainly does NOT contain (a CJK ideograph) and treating that exact advance
# as the tofu signature.
func test_fonts_have_glyphs() -> void:
	print("-- fonts can render every UI glyph --")
	var ThemeFactory = load("res://Scripts/Systems/ThemeFactory.gd")
	var CardTypes = load("res://Scripts/Core/CardTypes.gd")

	var samples = []
	for color in range(CardTypes.COLOR_GLYPHS.size()):
		samples.append(CardTypes.color_glyph(color))
	samples.append("\u00BB")   # clockwise turn order
	samples.append("\u00AB")   # anticlockwise turn order

	for weight in ["bold", "black", "medium", "regular"]:
		var font = ThemeFactory.make_font(20, weight)
		# Roboto covers no CJK, so this is guaranteed to be the notdef box.
		var tofu_width = font.get_char_size(ord("\u4E2D")).x

		for glyph in samples:
			if glyph == "":
				continue
			var width = font.get_char_size(ord(glyph)).x
			_check(width > 0.0,
				"%s renders U+%04X" % [weight, ord(glyph)])
			_check(abs(width - tofu_width) > 0.5,
				"%s has a real glyph for '%s' (U+%04X) - got the %.0fpx tofu box" % [
					weight, glyph, ord(glyph), width])


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL  %s" % message)


func _rect(entry: Dictionary) -> Rect2:
	return Rect2(entry["position"], entry["size"])


# Shrink slightly so touching edges are not reported as overlaps.
func _overlaps(a: Rect2, b: Rect2, tolerance: float = 2.0) -> bool:
	var shrunk_a = a.grow(-tolerance)
	var shrunk_b = b.grow(-tolerance)
	if shrunk_a.size.x <= 0 or shrunk_a.size.y <= 0:
		return false
	if shrunk_b.size.x <= 0 or shrunk_b.size.y <= 0:
		return false
	return shrunk_a.intersects(shrunk_b)


# ---------------------------------------------------------------------------
func test_no_overlap() -> void:
	print("-- HUD regions do not collide --")
	for viewport in RESOLUTIONS:
		var regions = {
			"status": _rect(TableLayout.status_rect(viewport)),
			"deck_counts": _rect(TableLayout.deck_counts_rect(viewport)),
			"score": _rect(TableLayout.score_rect(viewport)),
			"color_chip": _rect(TableLayout.color_chip_rect(viewport)),
			"direction": _rect(TableLayout.direction_rect(viewport)),
			"buttons": _rect(TableLayout.button_column_rect(viewport, 5)),
			"stack_badge": _rect(TableLayout.stack_rect(viewport))
		}

		var keys = regions.keys()
		for i in range(keys.size()):
			for j in range(i + 1, keys.size()):
				var a = regions[keys[i]]
				var b = regions[keys[j]]
				_check(not _overlaps(a, b),
					"%dx%d: %s overlaps %s" % [viewport.x, viewport.y, keys[i], keys[j]])

		# Seat plates only ever coexist within a single seat count, so each
		# configuration is checked against itself and the shared HUD regions.
		for opponents in [1, 2, 3]:
			var plates = {}
			for seat in range(opponents + 1):
				var center = TableLayout.seat_plate_position(viewport, seat, opponents)
				plates["plate_%d" % seat] = Rect2(center - Vector2(70, 16), Vector2(140, 32))

			var plate_keys = plates.keys()
			for i in range(plate_keys.size()):
				for j in range(i + 1, plate_keys.size()):
					_check(not _overlaps(plates[plate_keys[i]], plates[plate_keys[j]]),
						"%dx%d (%d opp): %s overlaps %s" % [
							viewport.x, viewport.y, opponents, plate_keys[i], plate_keys[j]])
				for key in keys:
					_check(not _overlaps(plates[plate_keys[i]], regions[key]),
						"%dx%d (%d opp): %s overlaps %s" % [
							viewport.x, viewport.y, opponents, plate_keys[i], key])

		# Every region must sit inside the viewport.
		var screen = Rect2(Vector2.ZERO, viewport)
		for key in keys:
			var region = regions[key]
			_check(screen.encloses(region),
				"%dx%d: %s escapes the viewport (%s)" % [viewport.x, viewport.y, key, str(region)])
	print("   checked %d resolutions" % RESOLUTIONS.size())


func test_hands_on_screen() -> void:
	print("-- hands stay on screen --")
	for viewport in RESOLUTIONS:
		var screen = Rect2(Vector2.ZERO, viewport)
		var player_scale = TableLayout.player_card_scale(viewport)
		var opponent_scale = TableLayout.opponent_card_scale(viewport)

		for count in HAND_SIZES:
			var bounds = TableLayout.fan_bounds(
				TableLayout.player_anchor(viewport), count,
				TableLayout.player_fan_width(viewport), true, player_scale)
			var rect = _rect(bounds)
			_check(screen.grow(4).encloses(rect),
				"%dx%d: player fan of %d escapes (%s)" % [viewport.x, viewport.y, count, str(rect)])

			# The player's fan must not run under the button column.
			var buttons = _rect(TableLayout.button_column_rect(viewport, 5))
			_check(rect.position.x + rect.size.x <= buttons.position.x + 4,
				"%dx%d: player fan of %d reaches the button column" % [viewport.x, viewport.y, count])

			for opponents in [1, 2, 3]:
				for seat in range(opponents):
					var anchor = TableLayout.opponent_anchor(viewport, seat, opponents)
					var opponent_bounds = _rect(TableLayout.fan_bounds(
						anchor, count,
						TableLayout.opponent_fan_width(viewport, opponents), false, opponent_scale))
					_check(screen.grow(6).encloses(opponent_bounds),
						"%dx%d: opponent %d/%d fan of %d escapes (%s)" % [
							viewport.x, viewport.y, seat, opponents, count, str(opponent_bounds)])
	print("   checked %d resolutions x %d hand sizes" % [RESOLUTIONS.size(), HAND_SIZES.size()])


func test_fan_ordering() -> void:
	print("-- fan ordering and symmetry --")
	for viewport in RESOLUTIONS:
		var scale = TableLayout.player_card_scale(viewport)
		for count in HAND_SIZES:
			if count < 2:
				continue
			var slots = TableLayout.fan(
				TableLayout.player_anchor(viewport), count,
				TableLayout.player_fan_width(viewport), true, scale)
			_check(slots.size() == count, "fan returns %d slots" % count)

			# Cards must read left to right with a strictly increasing z.
			for i in range(1, count):
				_check(slots[i]["position"].x > slots[i - 1]["position"].x,
					"%dx%d: fan of %d is not left-to-right at %d" % [viewport.x, viewport.y, count, i])
				_check(slots[i]["z"] > slots[i - 1]["z"],
					"%dx%d: fan z-order not increasing at %d" % [viewport.x, viewport.y, i])

			# The fan is centred on the anchor.
			var center_x = TableLayout.player_anchor(viewport).x
			var mid = (slots[0]["position"].x + slots[count - 1]["position"].x) * 0.5
			_check(abs(mid - center_x) < 1.0,
				"%dx%d: fan of %d is not centred (%f vs %f)" % [viewport.x, viewport.y, count, mid, center_x])

			# Rotation sweeps symmetrically from negative to positive.
			_check(slots[0]["rotation"] <= 0.0 and slots[count - 1]["rotation"] >= 0.0,
				"%dx%d: fan of %d rotation is not symmetric" % [viewport.x, viewport.y, count])


func test_fan_fits_budget() -> void:
	print("-- fan respects its width budget --")
	for viewport in RESOLUTIONS:
		var scale = TableLayout.player_card_scale(viewport)
		var budget = TableLayout.player_fan_width(viewport)
		for count in HAND_SIZES:
			var bounds = _rect(TableLayout.fan_bounds(
				TableLayout.player_anchor(viewport), count, budget, true, scale))
			# Large hands compress to the minimum spacing, which is the floor we
			# accept; anything wider than the budget is a layout bug.
			var min_spacing = TableLayout.card_size(scale).x * TableLayout.MIN_SPACING_RATIO
			# Rotated cards legitimately stick out past the centre-line budget,
			# so allow for the diagonal of an outermost tilted card.
			var overhang = (TableLayout.rotated_half_width(scale)
				- TableLayout.card_size(scale).x * 0.5) * 2.0
			var floor_width = min_spacing * max(count - 1, 0) + TableLayout.card_size(scale).x
			var allowed = max(budget, floor_width) + overhang + 4.0
			_check(bounds.size.x <= allowed,
				"%dx%d: fan of %d is %f wide, budget %f" % [
					viewport.x, viewport.y, count, bounds.size.x, allowed])


func test_seat_plates_visible() -> void:
	print("-- seat plates stay on screen --")
	for viewport in RESOLUTIONS:
		for opponents in [1, 2, 3]:
			for seat in range(opponents + 1):
				var position = TableLayout.seat_plate_position(viewport, seat, opponents)
				var plate = Rect2(position - Vector2(70, 16), Vector2(140, 32))
				_check(Rect2(Vector2.ZERO, viewport).encloses(plate),
					"%dx%d: seat %d/%d plate escapes the viewport (%s)" % [
						viewport.x, viewport.y, seat, opponents, str(plate)])

				# Opponent plates must not sit on top of their own cards, the
				# discard row, or the button column.
				var buttons = _rect(TableLayout.button_column_rect(viewport, 5))
				_check(not _overlaps(plate, buttons),
					"%dx%d: seat %d/%d plate overlaps the buttons" % [
						viewport.x, viewport.y, seat, opponents])

				var card_scale = TableLayout.player_card_scale(viewport)
				var card = TableLayout.card_size(card_scale)
				var discard = Rect2(TableLayout.discard_position(viewport) - card * 0.5, card)
				_check(not _overlaps(plate, discard),
					"%dx%d: seat %d/%d plate overlaps the discard pile" % [
						viewport.x, viewport.y, seat, opponents])

				if seat == 0:
					var fan_rect = _rect(TableLayout.fan_bounds(
						TableLayout.player_anchor(viewport), 7,
						TableLayout.player_fan_width(viewport), true, card_scale))
					_check(not _overlaps(plate, fan_rect),
						"%dx%d: your plate overlaps your hand" % [viewport.x, viewport.y])


func test_deck_and_discard_separated() -> void:
	print("-- deck and discard do not collide --")
	for viewport in RESOLUTIONS:
		var scale = TableLayout.player_card_scale(viewport)
		var size = TableLayout.card_size(scale)
		var deck = Rect2(TableLayout.deck_position(viewport) - size * 0.5, size)
		var discard = Rect2(TableLayout.discard_position(viewport) - size * 0.5, size)
		_check(not _overlaps(deck, discard),
			"%dx%d: deck overlaps the discard pile" % [viewport.x, viewport.y])

		var screen = Rect2(Vector2.ZERO, viewport)
		_check(screen.encloses(deck), "%dx%d: deck escapes the viewport" % [viewport.x, viewport.y])
		_check(screen.encloses(discard), "%dx%d: discard escapes the viewport" % [viewport.x, viewport.y])

		# The discard row must clear both fans.
		var player_bounds = _rect(TableLayout.fan_bounds(
			TableLayout.player_anchor(viewport), 7,
			TableLayout.player_fan_width(viewport), true, scale))
		_check(not _overlaps(discard, player_bounds, 4.0),
			"%dx%d: discard pile overlaps the player's hand" % [viewport.x, viewport.y])

		var opponent_bounds = _rect(TableLayout.fan_bounds(
			TableLayout.opponent_anchor(viewport, 0, 1), 7,
			TableLayout.opponent_fan_width(viewport, 1), false,
			TableLayout.opponent_card_scale(viewport)))
		_check(not _overlaps(discard, opponent_bounds, 4.0),
			"%dx%d: discard pile overlaps the opponent's hand" % [viewport.x, viewport.y])
		_check(not _overlaps(player_bounds, opponent_bounds),
			"%dx%d: the two hands overlap" % [viewport.x, viewport.y])


func test_scaling_monotonic() -> void:
	print("-- scaling behaves sensibly --")
	var small = TableLayout.player_card_scale(Vector2(800, 480))
	var reference = TableLayout.player_card_scale(Vector2(1280, 720))
	var large = TableLayout.player_card_scale(Vector2(1920, 1080))
	var huge = TableLayout.player_card_scale(Vector2(3840, 2160))
	_check(small < reference, "cards shrink below the reference resolution")
	_check(large > reference, "cards grow on large displays")
	_check(large <= reference * TableLayout.MAX_SCALE + 0.001, "growth is capped")
	_check(abs(huge - large) < 0.001, "growth saturates at the cap")
	_check(TableLayout.opponent_card_scale(Vector2(1280, 720)) < reference,
		"opponent cards render smaller than the player's")
