extends Reference
# GameRules
# ---------
# Pure, engine-free UNO rules engine. It owns the authoritative game state and
# emits a queue of semantic *events* describing what happened. The presentation
# layer replays that queue to drive animations, audio and HUD updates.
#
# Why this split?
#   * The rules can be unit tested headlessly (see Tests/TestRules.gd).
#   * Animation timing can never desync the simulation - the state is already
#     final by the time the first tween starts.
#   * Adding players (3-4 handed UNO) only touched this file.
#
# Supported rules: numbers, Skip, Reverse, Draw Two, Wild, Wild Draw Four,
# optional Draw-Two/Draw-Four stacking, "draw until playable", 7-0 house rule,
# jump-in, forced play, UNO calls with catch penalties, and full match scoring.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const CardData = preload("res://Scripts/Core/CardData.gd")
const Deck = preload("res://Scripts/Core/Deck.gd")

# ---------------------------------------------------------------------------
# Events emitted to the presentation layer
# ---------------------------------------------------------------------------
enum Event {
	GAME_STARTED,
	CARD_DEALT,
	OPENING_CARD,
	CARD_PLAYED,
	CARD_DRAWN,
	COLOR_CHOSEN,
	COLOR_CHOICE_REQUIRED,
	TURN_CHANGED,
	DIRECTION_REVERSED,
	PLAYER_SKIPPED,
	PENALTY_DRAW,
	STACK_GROWN,
	UNO_CALLED,
	UNO_PENALTY,
	HANDS_SWAPPED,
	HANDS_ROTATED,
	DECK_RECYCLED,
	DECK_EXHAUSTED,
	ROUND_ENDED,
	MATCH_ENDED,
	INVALID_MOVE
}

# House-rule switches. Defaults mirror the classic Mattel rules.
class Ruleset:
	extends Reference
	var stacking: bool = false          # +2/+4 can be stacked onto the victim
	var draw_until_playable: bool = false  # keep drawing until a legal card appears
	var seven_zero: bool = false        # 7 = swap hands, 0 = rotate hands
	var jump_in: bool = false           # identical card can be played out of turn
	var force_play: bool = false        # must play if a legal card is held
	var target_score: int = 500         # match ends when someone reaches this
	var starting_hand: int = 7

	func duplicate_rules():
		var copy = get_script().new()
		copy.stacking = stacking
		copy.draw_until_playable = draw_until_playable
		copy.seven_zero = seven_zero
		copy.jump_in = jump_in
		copy.force_play = force_play
		copy.target_score = target_score
		copy.starting_hand = starting_hand
		return copy


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var rules = null
var deck = null

# hands[i] is an Array of CardData for player i. Index 0 is always the human.
var hands: Array = []
var player_names: Array = []
var scores: Array = []

var current_player: int = 0
var direction: int = 1          # +1 clockwise, -1 counter-clockwise
var active_color: int = CardTypes.CardColor.RED
var pending_draw: int = 0       # accumulated +2/+4 waiting to resolve
var pending_draw_is_four: bool = false

var round_active: bool = false
var match_active: bool = false
var round_number: int = 0
var turn_number: int = 0

# Set while a wild has been played but its colour has not been declared yet.
var awaiting_color_choice: bool = false
var awaiting_color_player: int = -1

# Per-player: did they already draw this turn (limits to one draw per turn).
var has_drawn_this_turn: bool = false
# Card the player just drew and may still legally play this turn.
var drawn_playable_card = null

# UNO bookkeeping: whether player i has declared UNO at their current count.
var uno_called: Array = []
# Players who dropped to one card without calling: catchable until their next play.
var uno_vulnerable: Array = []

var events: Array = []

# Stats surfaced on the round summary screen.
var stats_cards_played: Array = []
var stats_cards_drawn: Array = []


func _init(player_count: int = 2, ruleset = null, seed_value: int = -1) -> void:
	rules = ruleset if ruleset != null else Ruleset.new()
	deck = Deck.new(seed_value)
	_resize_for(player_count)


func _resize_for(player_count: int) -> void:
	player_count = int(max(2, min(4, player_count)))
	hands = []
	scores = []
	uno_called = []
	uno_vulnerable = []
	stats_cards_played = []
	stats_cards_drawn = []
	player_names = []
	for i in range(player_count):
		hands.append([])
		scores.append(0)
		uno_called.append(false)
		uno_vulnerable.append(false)
		stats_cards_played.append(0)
		stats_cards_drawn.append(0)
		player_names.append("You" if i == 0 else "CPU %d" % i)


func player_count() -> int:
	return hands.size()


# ---------------------------------------------------------------------------
# Event helpers
# ---------------------------------------------------------------------------
func _emit(type: int, data: Dictionary = {}) -> void:
	data["type"] = type
	events.append(data)


# Drain the queue. The presentation layer calls this once per state change.
func consume_events() -> Array:
	var drained = events
	events = []
	return drained


# ---------------------------------------------------------------------------
# Match / round lifecycle
# ---------------------------------------------------------------------------
func start_match(player_count: int = -1) -> void:
	if player_count > 0 and player_count != hands.size():
		_resize_for(player_count)
	for i in range(scores.size()):
		scores[i] = 0
	round_number = 0
	match_active = true
	start_round(0)


func start_round(first_player: int = 0) -> void:
	deck.build()
	deck.shuffle()

	for i in range(hands.size()):
		hands[i] = []
		uno_called[i] = false
		uno_vulnerable[i] = false
		stats_cards_played[i] = 0
		stats_cards_drawn[i] = 0

	direction = 1
	pending_draw = 0
	pending_draw_is_four = false
	awaiting_color_choice = false
	awaiting_color_player = -1
	has_drawn_this_turn = false
	drawn_playable_card = null
	turn_number = 1
	round_number += 1
	round_active = true

	_emit(Event.GAME_STARTED, {"round": round_number, "players": hands.size()})

	# Deal one card at a time, round-robin, like a real dealer.
	for _c in range(rules.starting_hand):
		for i in range(hands.size()):
			var card = deck.draw()
			if card == null:
				continue
			hands[i].append(card)
			_emit(Event.CARD_DEALT, {"player": i, "card": card, "index": hands[i].size() - 1})

	var opening = deck.draw_opening_card()
	if opening == null:
		# Pathological: deck exhausted. Fail safe rather than crash.
		round_active = false
		return
	deck.discard(opening)
	active_color = opening.color
	_emit(Event.OPENING_CARD, {"card": opening, "color": active_color})

	current_player = int(clamp(first_player, 0, hands.size() - 1))
	_emit(Event.TURN_CHANGED, {"player": current_player, "turn": turn_number})


# ---------------------------------------------------------------------------
# Legality
# ---------------------------------------------------------------------------
func top_card():
	return deck.top_discard()


# Can `card` legally be played right now by the current player?
func is_playable(card) -> bool:
	if card == null:
		return false
	var top = top_card()
	if top == null:
		return false

	# While a +2/+4 stack is live only another stackable card may be played.
	if pending_draw > 0:
		if not rules.stacking:
			return false
		if pending_draw_is_four:
			# A +4 stack may only be answered with another +4.
			return card.value == CardTypes.CardValue.WILD_DRAW_FOUR
		# A +2 stack may be answered with +2, or escalated with a +4.
		return card.value == CardTypes.CardValue.DRAW_TWO \
			or card.value == CardTypes.CardValue.WILD_DRAW_FOUR

	if card.is_wild():
		return true
	if card.color == active_color:
		return true
	if card.value == top.value:
		return true
	return false


func playable_cards(player: int) -> Array:
	var result = []
	if player < 0 or player >= hands.size():
		return result
	for card in hands[player]:
		if is_playable(card):
			result.append(card)
	return result


func has_playable(player: int) -> bool:
	return playable_cards(player).size() > 0


# May the given player draw right now? Blocked once per turn, and blocked
# entirely under the "force play" house rule when a legal card is held.
func can_draw(player: int) -> bool:
	if not round_active or awaiting_color_choice:
		return false
	if player != current_player:
		return false
	if pending_draw > 0:
		return true
	if has_drawn_this_turn:
		return false
	if rules.force_play and has_playable(player):
		return false
	# An exhausted shoe that cannot be recycled has nothing to give.
	return not deck_exhausted()


# ---------------------------------------------------------------------------
# Jump-in (house rule)
# ---------------------------------------------------------------------------
# A player holding a card *identical* to the top of the discard (same colour
# AND same value) may play it immediately, out of turn. Play then resumes from
# the jumper. Wilds can never be jumped in with - their colour only exists once
# declared - and a live draw stack or a pending colour choice blocks it so the
# stack and the declaration stay unambiguous.
func can_jump_in(player: int, card) -> bool:
	if not rules.jump_in or not round_active or awaiting_color_choice:
		return false
	if pending_draw > 0:
		return false
	if player == current_player:
		return false
	if player < 0 or player >= hands.size():
		return false
	if not hands[player].has(card):
		return false
	# Nobody may jump in on the untouched opening card - there is nothing to
	# react to until the first player has actually played.
	if deck.discard_count() <= 1:
		return false
	var top = top_card()
	if top == null or card == null or card.is_wild():
		return false
	return card.color == top.color and card.value == top.value


# Every card the seat could legally jump in with right now.
func jump_in_cards(player: int) -> Array:
	var result = []
	if player < 0 or player >= hands.size():
		return result
	for card in hands[player]:
		if can_jump_in(player, card):
			result.append(card)
	return result


func can_pass(player: int) -> bool:
	if not round_active or awaiting_color_choice:
		return false
	if player != current_player:
		return false
	if pending_draw > 0:
		return false
	if has_drawn_this_turn:
		return true
	# Without a drawable card and without a legal play the turn would otherwise
	# deadlock, so passing becomes legal. This is the standard "shoe exhausted"
	# resolution and it guarantees the round always terminates.
	return deck_exhausted() and not has_playable(player)


# True when the draw pile is empty and the discard pile cannot refill it
# (only the face-up top card remains, which must stay on the table).
func deck_exhausted() -> bool:
	return deck.draw_count() == 0 and deck.discard_count() <= 1


# ---------------------------------------------------------------------------
# Playing a card
# ---------------------------------------------------------------------------
# `chosen_color` is required for wilds; when omitted a COLOR_CHOICE_REQUIRED
# event is emitted and the state machine waits for `choose_color()`.
func play_card(player: int, card, chosen_color: int = -1) -> bool:
	if not round_active or awaiting_color_choice:
		return false
	var jumped_in := false
	if player != current_player:
		# Out of turn is only legal as a jump-in with an identical card.
		if not can_jump_in(player, card):
			_emit(Event.INVALID_MOVE, {"player": player, "reason": "not_your_turn"})
			return false
		jumped_in = true
		# Play resumes from the jumper's seat.
		current_player = player
	if not hands[player].has(card):
		_emit(Event.INVALID_MOVE, {"player": player, "reason": "not_in_hand"})
		return false
	if not is_playable(card):
		_emit(Event.INVALID_MOVE, {"player": player, "card": card, "reason": "illegal"})
		return false

	hands[player].erase(card)
	stats_cards_played[player] += 1
	deck.discard(card)
	drawn_playable_card = null

	# Playing anything clears your "caught without calling UNO" exposure.
	uno_vulnerable[player] = false

	_emit(Event.CARD_PLAYED, {
		"player": player,
		"card": card,
		"remaining": hands[player].size(),
		"jump_in": jumped_in
	})

	if card.is_wild():
		if chosen_color < 0:
			awaiting_color_choice = true
			awaiting_color_player = player
			_emit(Event.COLOR_CHOICE_REQUIRED, {"player": player, "card": card})
			return true
		_apply_color_choice(player, card, chosen_color)
	else:
		active_color = card.color

	_resolve_after_play(player, card)
	return true


# Complete a pending wild colour declaration.
func choose_color(player: int, color: int) -> bool:
	if not awaiting_color_choice or player != awaiting_color_player:
		return false
	if not CardTypes.PLAYABLE_COLORS.has(color):
		return false
	var card = top_card()
	awaiting_color_choice = false
	awaiting_color_player = -1
	_apply_color_choice(player, card, color)
	_resolve_after_play(player, card)
	return true


func _apply_color_choice(player: int, card, color: int) -> void:
	active_color = color
	if card != null:
		card.chosen_color = color
	_emit(Event.COLOR_CHOSEN, {"player": player, "color": color})


# Apply the card's effect, check for a win, then advance the turn.
func _resolve_after_play(player: int, card) -> void:
	_check_uno_state(player)

	if hands[player].empty():
		_end_round(player)
		return

	var skip_next = false

	match card.value:
		CardTypes.CardValue.SKIP:
			skip_next = true
		CardTypes.CardValue.REVERSE:
			if hands.size() == 2:
				# Heads-up: Reverse acts as a Skip (official rule).
				skip_next = true
				_emit(Event.DIRECTION_REVERSED, {"direction": direction, "acts_as_skip": true})
			else:
				direction = -direction
				_emit(Event.DIRECTION_REVERSED, {"direction": direction, "acts_as_skip": false})
		CardTypes.CardValue.DRAW_TWO:
			pending_draw += 2
			pending_draw_is_four = false
			_emit(Event.STACK_GROWN, {"amount": pending_draw, "player": player})
		CardTypes.CardValue.WILD_DRAW_FOUR:
			pending_draw += 4
			pending_draw_is_four = true
			_emit(Event.STACK_GROWN, {"amount": pending_draw, "player": player})
		CardTypes.CardValue.N7:
			if rules.seven_zero:
				_seven_swap(player)
		CardTypes.CardValue.N0:
			if rules.seven_zero and hands.size() > 2:
				_zero_rotate(player)

	_advance_turn(skip_next)


# 7 house rule: swap hands with the opponent holding the fewest cards
# (heads-up this is simply the other player).
func _seven_swap(player: int) -> void:
	var target = -1
	var best = 9999
	for i in range(hands.size()):
		if i == player:
			continue
		if hands[i].size() < best:
			best = hands[i].size()
			target = i
	if target < 0:
		return
	var tmp = hands[player]
	hands[player] = hands[target]
	hands[target] = tmp
	uno_called[player] = false
	uno_called[target] = false
	_emit(Event.HANDS_SWAPPED, {"a": player, "b": target})


# 0 house rule: everyone passes their hand in the direction of play.
func _zero_rotate(player: int) -> void:
	var count = hands.size()
	var rotated = []
	for i in range(count):
		var source = int(posmod(i - direction, count))
		rotated.append(hands[source])
	hands = rotated
	for i in range(count):
		uno_called[i] = false
	_emit(Event.HANDS_ROTATED, {"direction": direction, "by": player})


func _next_player(from: int, steps: int = 1) -> int:
	return int(posmod(from + direction * steps, hands.size()))


# Move to the next player, applying a skip and resolving any +2/+4 stack that
# the incoming player cannot answer.
func _advance_turn(skip_next: bool) -> void:
	has_drawn_this_turn = false
	drawn_playable_card = null

	var next = _next_player(current_player)

	if skip_next:
		_emit(Event.PLAYER_SKIPPED, {"player": next})
		next = _next_player(next)

	current_player = next
	turn_number += 1

	# If a draw stack is live and the incoming player cannot (or may not) stack,
	# they eat the whole pile and forfeit the turn.
	if pending_draw > 0 and not _can_answer_stack(current_player):
		_apply_pending_draw(current_player)
		current_player = _next_player(current_player)
		turn_number += 1

	_emit(Event.TURN_CHANGED, {"player": current_player, "turn": turn_number})

	# A shoe that can no longer be replenished can leave every remaining player
	# without a legal move. Close the round on points instead of spinning.
	if _is_stalemate():
		_end_round_by_stalemate()


# True when no player can play and no card can be drawn: the round is stuck.
func _is_stalemate() -> bool:
	if not round_active or not deck_exhausted():
		return false
	for player in range(hands.size()):
		if has_playable(player):
			return false
	return true


# Award the round to the player holding the fewest points.
func _end_round_by_stalemate() -> void:
	var best = 0
	for player in range(hands.size()):
		if hand_score(player) < hand_score(best):
			best = player
	_emit(Event.DECK_EXHAUSTED, {"winner": best})
	_end_round(best)


func _can_answer_stack(player: int) -> bool:
	if not rules.stacking:
		return false
	for card in hands[player]:
		if is_playable(card):
			return true
	return false


func _apply_pending_draw(player: int) -> void:
	var amount = pending_draw
	pending_draw = 0
	pending_draw_is_four = false
	var drawn = _draw_cards(player, amount)
	_emit(Event.PENALTY_DRAW, {"player": player, "count": drawn.size(), "cards": drawn})
	_emit(Event.PLAYER_SKIPPED, {"player": player})


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
func _draw_cards(player: int, count: int) -> Array:
	var drawn = []
	for _i in range(count):
		var before = deck.reshuffle_count
		var card = deck.draw()
		if deck.reshuffle_count != before:
			_emit(Event.DECK_RECYCLED, {"remaining": deck.draw_count()})
		if card == null:
			break
		hands[player].append(card)
		stats_cards_drawn[player] += 1
		drawn.append(card)
	# Gaining cards clears any UNO declaration and exposure.
	if drawn.size() > 0:
		uno_called[player] = false
		uno_vulnerable[player] = false
	return drawn


# Voluntary draw on your turn. Honours "draw until playable" when enabled.
func draw_for_turn(player: int) -> Array:
	if not can_draw(player):
		return []

	# Drawing into a live stack means accepting the penalty.
	if pending_draw > 0:
		var amount = pending_draw
		pending_draw = 0
		pending_draw_is_four = false
		var eaten = _draw_cards(player, amount)
		_emit(Event.PENALTY_DRAW, {"player": player, "count": eaten.size(), "cards": eaten})
		_advance_turn(false)
		return eaten

	var drawn = []
	if rules.draw_until_playable:
		# Hard cap protects against a pathological empty shoe.
		for _i in range(60):
			var batch = _draw_cards(player, 1)
			if batch.empty():
				break
			drawn.append(batch[0])
			if is_playable(batch[0]):
				break
	else:
		drawn = _draw_cards(player, 1)

	if drawn.empty():
		# Nothing left to draw. Rather than stranding the player on a turn they
		# cannot end, mark the turn as spent so passing is legal.
		has_drawn_this_turn = true
		drawn_playable_card = null
		_emit(Event.INVALID_MOVE, {"player": player, "reason": "deck_empty"})
		if not has_playable(player):
			_advance_turn(false)
		return []

	has_drawn_this_turn = true
	var last = drawn[drawn.size() - 1]
	drawn_playable_card = last if is_playable(last) else null

	_emit(Event.CARD_DRAWN, {
		"player": player,
		"cards": drawn,
		"playable": drawn_playable_card != null
	})
	return drawn


# End the turn after drawing.
func pass_turn(player: int) -> bool:
	if not can_pass(player):
		return false
	_advance_turn(false)
	return true


# ---------------------------------------------------------------------------
# UNO calls
# ---------------------------------------------------------------------------
# Declare UNO. Legal while holding two cards (pre-declaring), or immediately
# after dropping to one before an opponent catches you.
func call_uno(player: int) -> bool:
	if not round_active:
		return false
	var count = hands[player].size()
	if count == 1:
		if uno_vulnerable[player]:
			uno_vulnerable[player] = false
			uno_called[player] = true
			_emit(Event.UNO_CALLED, {"player": player, "late": true})
			return true
		return false
	if count == 2 and player == current_player:
		uno_called[player] = true
		_emit(Event.UNO_CALLED, {"player": player, "late": false})
		return true
	return false


# Catch an opponent who reached one card without declaring. Returns true when
# the catch lands (the victim draws two).
func catch_uno(accuser: int, target: int) -> bool:
	if not round_active:
		return false
	if target < 0 or target >= hands.size() or accuser == target:
		return false
	if not uno_vulnerable[target]:
		return false
	uno_vulnerable[target] = false
	var drawn = _draw_cards(target, 2)
	_emit(Event.UNO_PENALTY, {
		"player": target,
		"by": accuser,
		"count": drawn.size(),
		"cards": drawn
	})
	return true


# After a play, mark the player catchable if they hit one card silently.
func _check_uno_state(player: int) -> void:
	if hands[player].size() == 1:
		if uno_called[player]:
			uno_vulnerable[player] = false
			_emit(Event.UNO_CALLED, {"player": player, "late": false, "confirmed": true})
		else:
			uno_vulnerable[player] = true
	else:
		uno_called[player] = false
		uno_vulnerable[player] = false


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------
func hand_score(player: int) -> int:
	var total = 0
	for card in hands[player]:
		total += card.score()
	return total


func _end_round(winner: int) -> void:
	round_active = false
	var gained = 0
	var breakdown = []
	for i in range(hands.size()):
		if i == winner:
			breakdown.append(0)
			continue
		var value = hand_score(i)
		gained += value
		breakdown.append(value)
	scores[winner] += gained

	_emit(Event.ROUND_ENDED, {
		"winner": winner,
		"points": gained,
		"breakdown": breakdown,
		"scores": scores.duplicate(),
		"round": round_number,
		"turns": turn_number
	})

	if scores[winner] >= rules.target_score:
		match_active = false
		_emit(Event.MATCH_ENDED, {"winner": winner, "scores": scores.duplicate()})


# ---------------------------------------------------------------------------
# Introspection helpers used by the AI and the HUD
# ---------------------------------------------------------------------------
func hand_size(player: int) -> int:
	if player < 0 or player >= hands.size():
		return 0
	return hands[player].size()


func color_counts(player: int) -> Array:
	var counts = [0, 0, 0, 0]
	for card in hands[player]:
		if card.color < 4:
			counts[card.color] += 1
	return counts


# Snapshot used by tests and the debug overlay.
func snapshot() -> Dictionary:
	var sizes = []
	for h in hands:
		sizes.append(h.size())
	return {
		"current_player": current_player,
		"direction": direction,
		"active_color": active_color,
		"pending_draw": pending_draw,
		"hand_sizes": sizes,
		"scores": scores.duplicate(),
		"draw_pile": deck.draw_count(),
		"discard_pile": deck.discard_count(),
		"round_active": round_active
	}
