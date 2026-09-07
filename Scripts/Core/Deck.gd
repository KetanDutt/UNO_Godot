extends Reference
# Deck
# ----
# Owns the draw pile and the discard pile as pure data. Contains the standard
# 108-card UNO distribution plus deterministic shuffling (seedable, so tests and
# "replay this deal" features are possible).
#
# Reshuffle semantics follow the official rules: when the stock runs out, every
# discard except the visible top card is returned, wild cards lose their declared
# colour, and the pile is shuffled.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const CardData = preload("res://Scripts/Core/CardData.gd")

var draw_pile: Array = []
var discard_pile: Array = []

var _rng: RandomNumberGenerator = null
var _next_uid: int = 1

# Incremented every time the discard pile is recycled; the HUD surfaces this.
var reshuffle_count: int = 0


func _init(seed_value: int = -1) -> void:
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func get_rng() -> RandomNumberGenerator:
	return _rng


# Build the canonical 108-card deck:
#   per colour: one 0, two each of 1-9, two Skip, two Reverse, two Draw Two
#   plus four Wild and four Wild Draw Four.
func build() -> void:
	draw_pile.clear()
	discard_pile.clear()
	reshuffle_count = 0
	_next_uid = 1

	for color in CardTypes.PLAYABLE_COLORS:
		_append_card(color, CardTypes.CardValue.N0)
		for _copy in range(2):
			for number in range(1, 10):
				_append_card(color, number)
			_append_card(color, CardTypes.CardValue.SKIP)
			_append_card(color, CardTypes.CardValue.REVERSE)
			_append_card(color, CardTypes.CardValue.DRAW_TWO)

	for _copy in range(4):
		_append_card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD)
		_append_card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD_DRAW_FOUR)


func _append_card(color: int, value: int) -> void:
	draw_pile.append(CardData.new(color, value, _next_uid))
	_next_uid += 1


# Fisher-Yates using our own RNG so a seeded deck is fully reproducible
# (Array.shuffle() uses the global RNG and cannot be seeded independently).
func shuffle() -> void:
	_shuffle_array(draw_pile)


func _shuffle_array(array: Array) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j = _rng.randi_range(0, i)
		if i != j:
			var tmp = array[i]
			array[i] = array[j]
			array[j] = tmp


func draw_count() -> int:
	return draw_pile.size()


func discard_count() -> int:
	return discard_pile.size()


func is_empty() -> bool:
	return draw_pile.empty() and discard_pile.size() <= 1


# Pop one card, recycling the discard pile if needed. Returns null only when the
# game has genuinely run out of cards (every card is in a hand).
func draw():
	if draw_pile.empty():
		recycle_discards()
	if draw_pile.empty():
		return null
	return draw_pile.pop_back()


# Draw up to `count` cards; may return fewer if the shoe is exhausted.
func draw_many(count: int) -> Array:
	var result = []
	for _i in range(count):
		var card = draw()
		if card == null:
			break
		result.append(card)
	return result


func top_discard():
	if discard_pile.empty():
		return null
	return discard_pile[discard_pile.size() - 1]


func discard(card) -> void:
	if card == null:
		return
	discard_pile.append(card)


# Return every discard except the visible top card to the draw pile.
func recycle_discards() -> bool:
	if discard_pile.size() <= 1:
		return false
	var top = discard_pile.pop_back()
	for card in discard_pile:
		# A recycled wild is blank again and must be re-declared when replayed.
		if card.is_wild():
			card.chosen_color = -1
		draw_pile.append(card)
	discard_pile = [top]
	_shuffle_array(draw_pile)
	reshuffle_count += 1
	return true


# Pull the opening card. Official rules: if the first flip is a Wild Draw Four
# it must be buried and another card drawn. We also avoid opening on any wild or
# action card so the first turn is always a clean number.
func draw_opening_card():
	for _attempt in range(200):
		var card = draw()
		if card == null:
			return null
		if card.is_number():
			return card
		# Bury it and keep looking.
		draw_pile.insert(0, card)
		if _attempt % 20 == 19:
			_shuffle_array(draw_pile)
	return draw()
