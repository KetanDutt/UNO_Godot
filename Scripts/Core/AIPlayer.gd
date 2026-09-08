extends Reference
# AIPlayer
# --------
# Opponent brain. Three difficulty tiers share one scoring pipeline so their
# behaviour stays coherent - harder tiers simply weigh more signals and add less
# noise.
#
#   EASY   - plays a mostly random legal card, rarely saves wilds, often forgets
#            to call UNO. Fun to beat.
#   NORMAL - keeps colour flexibility, spends action cards when the opponent is
#            low, always calls UNO.
#   HARD   - counts cards, tracks colours the human is void in, hoards +4 for the
#            kill, dumps high pips when it expects to lose the round, and catches
#            missed UNO calls.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")

enum Difficulty { EASY = 0, NORMAL = 1, HARD = 2 }

const DIFFICULTY_NAMES = ["Easy", "Normal", "Hard"]

var difficulty: int = Difficulty.NORMAL
var seat: int = 1

var _rng: RandomNumberGenerator = null

# Colours we have seen this seat's opponents fail to follow - a decent proxy for
# "they are void in this colour". Reset each round.
var _opponent_void_colors: Array = []


func _init(p_seat: int = 1, p_difficulty: int = Difficulty.NORMAL, seed_value: int = -1) -> void:
	seat = p_seat
	difficulty = p_difficulty
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	reset_memory(4)


func reset_memory(player_count: int) -> void:
	_opponent_void_colors = []
	for _i in range(player_count):
		_opponent_void_colors.append({})


# Called by the controller whenever a player draws - strong evidence that they
# hold nothing matching the active colour.
func note_draw(player: int, active_color: int) -> void:
	if difficulty < Difficulty.HARD:
		return
	if player < 0 or player >= _opponent_void_colors.size():
		return
	_opponent_void_colors[player][active_color] = true


func note_play(player: int, card) -> void:
	if difficulty < Difficulty.HARD:
		return
	if player < 0 or player >= _opponent_void_colors.size():
		return
	# Playing a colour proves they are not void in it.
	if not card.is_wild():
		_opponent_void_colors[player].erase(card.color)


func difficulty_name() -> String:
	return DIFFICULTY_NAMES[int(clamp(difficulty, 0, 2))]


# How long the AI "thinks" before acting, in seconds. Slightly randomised so it
# never feels metronomic.
func think_time() -> float:
	var base = [0.85, 0.7, 0.55][int(clamp(difficulty, 0, 2))]
	return base + _rng.randf_range(-0.12, 0.22)


# ---------------------------------------------------------------------------
# Decisions
# ---------------------------------------------------------------------------
# Returns the CardData to play, or null to draw.
func choose_card(rules, legal: Array):
	if legal.empty():
		return null

	if difficulty == Difficulty.EASY:
		# Mostly random, with a mild nudge toward getting rid of something.
		if _rng.randf() < 0.75:
			return legal[_rng.randi_range(0, legal.size() - 1)]

	var best = legal[0]
	var best_score = -99999.0
	for card in legal:
		var score = _score_card(rules, card)
		if score > best_score:
			best_score = score
			best = card
	return best


func _score_card(rules, card) -> float:
	var score = 0.0
	var opponents = _opponent_hand_sizes(rules)
	var lowest_opponent = 99
	for size in opponents:
		lowest_opponent = int(min(lowest_opponent, size))
	var my_size = rules.hand_size(seat)
	var counts = rules.color_counts(seat)

	# Base: dump high pip values first so we do not eat points if we lose.
	score += card.score() * 0.35

	match card.value:
		CardTypes.CardValue.WILD_DRAW_FOUR:
			# The strongest card in the game. Save it unless it wins or hurts.
			score += 30.0
			if lowest_opponent <= 2:
				score += 55.0
			elif difficulty >= Difficulty.NORMAL and my_size > 3:
				# Hold it for a better moment.
				score -= 34.0
		CardTypes.CardValue.WILD:
			score += 18.0
			if difficulty >= Difficulty.NORMAL and my_size > 3:
				score -= 20.0
			if _stuck_on_color(rules, counts):
				score += 26.0
		CardTypes.CardValue.DRAW_TWO:
			score += 26.0
			if lowest_opponent <= 2:
				score += 30.0
		CardTypes.CardValue.SKIP, CardTypes.CardValue.REVERSE:
			score += 22.0
			if lowest_opponent <= 2:
				score += 26.0

	# Prefer playing a colour we are rich in - keeps future options open.
	if not card.is_wild():
		score += counts[card.color] * 4.0
		# Changing colour has a small cost unless we are dumping a bad colour.
		if card.color != rules.active_color:
			score -= 3.0
		if difficulty >= Difficulty.HARD:
			# Steering into a colour the leader is void in is very strong.
			for i in range(_opponent_void_colors.size()):
				if i == seat or i >= rules.player_count():
					continue
				if _opponent_void_colors[i].has(card.color) and rules.hand_size(i) <= 3:
					score += 14.0

	# Endgame: with two cards left, play the one that leaves a flexible last card.
	if difficulty >= Difficulty.NORMAL and my_size == 2:
		if card.is_wild():
			score -= 25.0  # keep the wild as the guaranteed final play

	var noise = [9.0, 4.0, 1.5][int(clamp(difficulty, 0, 2))]
	score += _rng.randf_range(-noise, noise)
	return score


func _opponent_hand_sizes(rules) -> Array:
	var sizes = []
	for i in range(rules.player_count()):
		if i != seat:
			sizes.append(rules.hand_size(i))
	return sizes


# True when almost nothing in hand matches the active colour.
func _stuck_on_color(rules, _counts: Array) -> bool:
	var matching = 0
	for card in rules.hands[seat]:
		if not card.is_wild() and card.color == rules.active_color:
			matching += 1
	return matching <= 1


# Pick the colour to declare after a wild.
func choose_color(rules) -> int:
	var counts = rules.color_counts(seat)

	if difficulty == Difficulty.EASY:
		# Usually the most common colour, sometimes a whim.
		if _rng.randf() < 0.3:
			return CardTypes.PLAYABLE_COLORS[_rng.randi_range(0, 3)]

	var best = CardTypes.CardColor.RED
	var best_score = -999.0
	for color in CardTypes.PLAYABLE_COLORS:
		var score = float(counts[color]) * 10.0

		if difficulty >= Difficulty.HARD:
			# Favour colours our closest rival appears void in.
			for i in range(rules.player_count()):
				if i == seat:
					continue
				if _opponent_void_colors.size() > i and _opponent_void_colors[i].has(color):
					var pressure = 8.0 if rules.hand_size(i) <= 3 else 4.0
					score += pressure

		score += _rng.randf_range(0.0, 2.0)
		if score > best_score:
			best_score = score
			best = color
	return best


# Should the AI declare UNO this turn? Easy AI is forgetful on purpose.
func should_call_uno() -> bool:
	match difficulty:
		Difficulty.EASY:
			return _rng.randf() < 0.45
		Difficulty.NORMAL:
			return _rng.randf() < 0.9
		_:
			return true


# Should the AI catch a human who forgot to call UNO?
func should_catch_uno() -> bool:
	match difficulty:
		Difficulty.EASY:
			return _rng.randf() < 0.15
		Difficulty.NORMAL:
			return _rng.randf() < 0.7
		_:
			return true


# Delay before the catch fires, giving the human a fair window to self-call.
func catch_delay() -> float:
	return [2.2, 1.5, 1.0][int(clamp(difficulty, 0, 2))]


# Should the AI jump in with an identical card out of turn? Easier opponents
# are slower to spot the opening.
func should_jump_in() -> bool:
	match difficulty:
		Difficulty.EASY:
			return _rng.randf() < 0.35
		Difficulty.NORMAL:
			return _rng.randf() < 0.8
		_:
			return true


# Reaction time before an AI jump-in lands, so the human can beat them to it.
func jump_in_delay() -> float:
	var base = [0.95, 0.75, 0.55][int(clamp(difficulty, 0, 2))]
	return base + _rng.randf_range(-0.1, 0.25)
