extends SceneTree
# Headless rules test suite.
#
# Run with:
#   godot --no-window -s Tests/TestRules.gd
#
# Exits with code 0 when every assertion passes, 1 otherwise, so it can be wired
# straight into CI. It exercises the pure rules layer only - no scenes, no
# rendering, no timing.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const CardData = preload("res://Scripts/Core/CardData.gd")
const Deck = preload("res://Scripts/Core/Deck.gd")
const GameRules = preload("res://Scripts/Core/GameRules.gd")
const AIPlayer = preload("res://Scripts/Core/AIPlayer.gd")

var _passed := 0
var _failed := 0
var _current := ""


func _init() -> void:
	print("\n=== UNO rules test suite ===\n")

	_run("Deck composition", "test_deck_composition")
	_run("Deck seeded shuffle is deterministic", "test_seeded_shuffle")
	_run("Deck recycles discards", "test_recycle")
	_run("Opening card is a number", "test_opening_card")
	_run("Card scoring values", "test_scoring")
	_run("Deal gives correct hand sizes", "test_deal")
	_run("Colour matching", "test_color_match")
	_run("Value matching", "test_value_match")
	_run("Wild is always playable", "test_wild_playable")
	_run("Illegal play is rejected", "test_illegal_play")
	_run("Play out of turn is rejected", "test_out_of_turn")
	_run("Skip skips the next player", "test_skip")
	_run("Reverse acts as skip heads-up", "test_reverse_two_player")
	_run("Reverse flips direction with 3+", "test_reverse_multi")
	_run("Draw Two penalises and skips", "test_draw_two")
	_run("Wild Draw Four penalises and skips", "test_wild_draw_four")
	_run("Wild requires a colour choice", "test_wild_color_choice")
	_run("Stacking accumulates draws", "test_stacking")
	_run("Stacking off resolves immediately", "test_no_stacking")
	_run("Draw limited to once per turn", "test_draw_once")
	_run("Draw until playable", "test_draw_until_playable")
	_run("Pass only after drawing", "test_pass_rules")
	_run("UNO call and catch penalty", "test_uno_catch")
	_run("UNO called safely avoids penalty", "test_uno_safe")
	_run("Round scoring uses opponent hands", "test_round_score")
	_run("Match ends at target score", "test_match_end")
	_run("Seven-zero swap", "test_seven_zero")
	_run("Force play blocks drawing", "test_force_play")
	_run("Jump-in legality", "test_jump_in_legality")
	_run("Jump-in steals the turn", "test_jump_in_turn_flow")
	_run("Jump-in needs the rule enabled", "test_jump_in_disabled")
	_run("Deck never returns duplicate uids", "test_unique_uids")
	_run("AI always picks a legal card", "test_ai_legal")
	_run("Full AI match completes", "test_full_game_simulation")
	_run("Exhausted deck cannot softlock", "test_deck_exhaustion_no_softlock")
	_run("Stalemate awards the lowest hand", "test_stalemate_awards_lowest_hand")
	_run("100 seeded games stay consistent", "test_soak")

	print("\n=== %d passed, %d failed ===\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
func _run(label: String, method: String) -> void:
	_current = label
	var before_failed = _failed
	call(method)
	if _failed == before_failed:
		print("  PASS  %s" % label)


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("  FAIL  %s -> %s" % [_current, message])


func _eq(actual, expected, message: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


# Build a rules object with a fixed seed and deterministic hands.
func _fresh(players: int = 2, ruleset = null, seed_value: int = 1234) -> GameRules:
	var rules = GameRules.new(players, ruleset, seed_value)
	rules.start_match(players)
	return rules


# Replace a hand with explicit cards and force a known top discard.
func _stage(rules, player: int, cards: Array, top_color: int, top_value: int) -> void:
	rules.hands[player] = cards
	var top = CardData.new(top_color, top_value, 9000)
	rules.deck.discard_pile.append(top)
	rules.active_color = top_color
	rules.current_player = player
	rules.has_drawn_this_turn = false
	rules.consume_events()


func _card(color: int, value: int, uid: int = 0) -> CardData:
	return CardData.new(color, value, uid)


func _has_event(events: Array, type: int) -> bool:
	for e in events:
		if e["type"] == type:
			return true
	return false


func _find_event(events: Array, type: int):
	for e in events:
		if e["type"] == type:
			return e
	return null


# ---------------------------------------------------------------------------
# Deck
# ---------------------------------------------------------------------------
func test_deck_composition() -> void:
	var deck = Deck.new(1)
	deck.build()
	_eq(deck.draw_count(), 108, "deck size")

	var zeros = 0
	var wilds = 0
	var draw_fours = 0
	var skips = 0
	var reverses = 0
	var draw_twos = 0
	var numbers = 0
	for card in deck.draw_pile:
		match card.value:
			CardTypes.CardValue.N0:
				zeros += 1
			CardTypes.CardValue.WILD:
				wilds += 1
			CardTypes.CardValue.WILD_DRAW_FOUR:
				draw_fours += 1
			CardTypes.CardValue.SKIP:
				skips += 1
			CardTypes.CardValue.REVERSE:
				reverses += 1
			CardTypes.CardValue.DRAW_TWO:
				draw_twos += 1
		if card.is_number():
			numbers += 1

	_eq(zeros, 4, "one zero per colour")
	_eq(wilds, 4, "four wilds")
	_eq(draw_fours, 4, "four wild draw four")
	_eq(skips, 8, "eight skips")
	_eq(reverses, 8, "eight reverses")
	_eq(draw_twos, 8, "eight draw twos")
	_eq(numbers, 76, "76 number cards")


func test_seeded_shuffle() -> void:
	var a = Deck.new(777)
	a.build()
	a.shuffle()
	var b = Deck.new(777)
	b.build()
	b.shuffle()
	var same = true
	for i in range(a.draw_pile.size()):
		if a.draw_pile[i].color != b.draw_pile[i].color or a.draw_pile[i].value != b.draw_pile[i].value:
			same = false
			break
	_check(same, "same seed produces same order")

	var c = Deck.new(778)
	c.build()
	c.shuffle()
	var different = false
	for i in range(a.draw_pile.size()):
		if a.draw_pile[i].value != c.draw_pile[i].value:
			different = true
			break
	_check(different, "different seed produces different order")


func test_recycle() -> void:
	var deck = Deck.new(5)
	deck.build()
	# Move everything except two cards into the discard pile.
	while deck.draw_count() > 0:
		deck.discard(deck.draw_pile.pop_back())
	_eq(deck.draw_count(), 0, "draw pile emptied")
	var top_before = deck.top_discard()
	var card = deck.draw()
	_check(card != null, "draw triggers recycle")
	_eq(deck.top_discard(), top_before, "top discard preserved")
	_eq(deck.reshuffle_count, 1, "recycle counted")

	# A recycled wild must forget its declared colour.
	var deck2 = Deck.new(6)
	deck2.build()
	var wild = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD, 1)
	wild.chosen_color = CardTypes.CardColor.RED
	deck2.draw_pile.clear()
	deck2.discard(wild)
	deck2.discard(_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N5, 2))
	deck2.recycle_discards()
	_eq(deck2.draw_pile[0].chosen_color, -1, "recycled wild resets colour")


func test_opening_card() -> void:
	for seed_value in range(20):
		var deck = Deck.new(seed_value)
		deck.build()
		deck.shuffle()
		var card = deck.draw_opening_card()
		_check(card != null and card.is_number(), "opening card is a plain number")


func test_scoring() -> void:
	_eq(CardTypes.score_for(CardTypes.CardValue.N0), 0, "zero scores 0")
	_eq(CardTypes.score_for(CardTypes.CardValue.N7), 7, "seven scores 7")
	_eq(CardTypes.score_for(CardTypes.CardValue.N9), 9, "nine scores 9")
	_eq(CardTypes.score_for(CardTypes.CardValue.SKIP), 20, "skip scores 20")
	_eq(CardTypes.score_for(CardTypes.CardValue.REVERSE), 20, "reverse scores 20")
	_eq(CardTypes.score_for(CardTypes.CardValue.DRAW_TWO), 20, "draw two scores 20")
	_eq(CardTypes.score_for(CardTypes.CardValue.WILD), 50, "wild scores 50")
	_eq(CardTypes.score_for(CardTypes.CardValue.WILD_DRAW_FOUR), 50, "wild draw four scores 50")


# ---------------------------------------------------------------------------
# Dealing and legality
# ---------------------------------------------------------------------------
func test_deal() -> void:
	var rules = _fresh(2)
	_eq(rules.hand_size(0), 7, "player hand size")
	_eq(rules.hand_size(1), 7, "ai hand size")
	# 108 - 14 dealt - 1 opening discard.
	_eq(rules.deck.draw_count(), 108 - 14 - 1, "draw pile after deal")
	_eq(rules.deck.discard_count(), 1, "one opening discard")
	_check(rules.round_active, "round is active")

	var four = _fresh(4)
	_eq(four.player_count(), 4, "four players")
	for i in range(4):
		_eq(four.hand_size(i), 7, "player %d hand" % i)


func test_color_match() -> void:
	var rules = _fresh(2)
	var red_five = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1)
	_stage(rules, 0, [red_five], CardTypes.CardColor.RED, CardTypes.CardValue.N9)
	_check(rules.is_playable(red_five), "red on red")

	var blue_two = _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N2, 2)
	rules.hands[0] = [blue_two]
	_check(not rules.is_playable(blue_two), "blue on red with no value match")


func test_value_match() -> void:
	var rules = _fresh(2)
	var blue_nine = _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N9, 1)
	_stage(rules, 0, [blue_nine], CardTypes.CardColor.RED, CardTypes.CardValue.N9)
	_check(rules.is_playable(blue_nine), "matching value across colours")

	var green_skip = _card(CardTypes.CardColor.GREEN, CardTypes.CardValue.SKIP, 2)
	rules.hands[0] = [green_skip]
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.SKIP, 3))
	rules.active_color = CardTypes.CardColor.RED
	_check(rules.is_playable(green_skip), "skip on skip")


func test_wild_playable() -> void:
	var rules = _fresh(2)
	var wild = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD, 1)
	var wd4 = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD_DRAW_FOUR, 2)
	_stage(rules, 0, [wild, wd4], CardTypes.CardColor.GREEN, CardTypes.CardValue.N3)
	_check(rules.is_playable(wild), "wild always playable")
	_check(rules.is_playable(wd4), "wild draw four always playable")


func test_illegal_play() -> void:
	var rules = _fresh(2)
	var blue_two = _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N2, 1)
	_stage(rules, 0, [blue_two], CardTypes.CardColor.RED, CardTypes.CardValue.N9)
	var ok = rules.play_card(0, blue_two)
	_check(not ok, "illegal play returns false")
	_eq(rules.hand_size(0), 1, "card stays in hand")
	_check(_has_event(rules.consume_events(), GameRules.Event.INVALID_MOVE), "invalid move event")


func test_out_of_turn() -> void:
	var rules = _fresh(2)
	rules.current_player = 0
	var card = rules.hands[1][0]
	var ok = rules.play_card(1, card)
	_check(not ok, "cannot play out of turn")


# ---------------------------------------------------------------------------
# Action cards
# ---------------------------------------------------------------------------
func test_skip() -> void:
	# Heads-up: playing Skip returns the turn to the same player.
	var rules = _fresh(2)
	var skip = _card(CardTypes.CardColor.RED, CardTypes.CardValue.SKIP, 1)
	_stage(rules, 0, [skip, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, skip)
	_eq(rules.current_player, 0, "skip returns turn to player heads-up")
	_check(_has_event(rules.consume_events(), GameRules.Event.PLAYER_SKIPPED), "skip event")

	# Three players: seat 0 skips seat 1, so seat 2 plays.
	var three = _fresh(3)
	var skip3 = _card(CardTypes.CardColor.RED, CardTypes.CardValue.SKIP, 3)
	_stage(three, 0, [skip3, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 4)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	three.play_card(0, skip3)
	_eq(three.current_player, 2, "skip jumps the next seat")


func test_reverse_two_player() -> void:
	var rules = _fresh(2)
	var rev = _card(CardTypes.CardColor.RED, CardTypes.CardValue.REVERSE, 1)
	_stage(rules, 0, [rev, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, rev)
	_eq(rules.current_player, 0, "reverse acts as skip heads-up")
	_eq(rules.direction, 1, "direction unchanged heads-up")
	var event = _find_event(rules.consume_events(), GameRules.Event.DIRECTION_REVERSED)
	_check(event != null and event["acts_as_skip"], "reverse flagged as skip")


func test_reverse_multi() -> void:
	var rules = _fresh(3)
	var rev = _card(CardTypes.CardColor.RED, CardTypes.CardValue.REVERSE, 1)
	_stage(rules, 0, [rev, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, rev)
	_eq(rules.direction, -1, "direction flipped")
	_eq(rules.current_player, 2, "play moves counter-clockwise")


func test_draw_two() -> void:
	var rules = _fresh(2)
	var d2 = _card(CardTypes.CardColor.RED, CardTypes.CardValue.DRAW_TWO, 1)
	_stage(rules, 0, [d2, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	var before = rules.hand_size(1)
	rules.play_card(0, d2)
	_eq(rules.hand_size(1), before + 2, "opponent draws two")
	_eq(rules.current_player, 0, "victim loses their turn")
	_eq(rules.pending_draw, 0, "stack cleared")
	_check(_has_event(rules.consume_events(), GameRules.Event.PENALTY_DRAW), "penalty event")


func test_wild_draw_four() -> void:
	var rules = _fresh(2)
	var wd4 = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD_DRAW_FOUR, 1)
	_stage(rules, 0, [wd4, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	var before = rules.hand_size(1)
	rules.play_card(0, wd4, CardTypes.CardColor.GREEN)
	_eq(rules.hand_size(1), before + 4, "opponent draws four")
	_eq(rules.active_color, CardTypes.CardColor.GREEN, "colour applied")
	_eq(rules.current_player, 0, "victim loses their turn")


func test_wild_color_choice() -> void:
	var rules = _fresh(2)
	var wild = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD, 1)
	_stage(rules, 0, [wild, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 2)],
		CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, wild)
	_check(rules.awaiting_color_choice, "waiting for colour")
	_check(_has_event(rules.consume_events(), GameRules.Event.COLOR_CHOICE_REQUIRED), "choice event")

	_check(not rules.choose_color(1, CardTypes.CardColor.BLUE), "wrong player cannot choose")
	_check(rules.choose_color(0, CardTypes.CardColor.BLUE), "correct player chooses")
	_eq(rules.active_color, CardTypes.CardColor.BLUE, "colour applied")
	_check(not rules.awaiting_color_choice, "no longer waiting")
	_eq(rules.current_player, 1, "turn advances after choice")


# ---------------------------------------------------------------------------
# House rules
# ---------------------------------------------------------------------------
func test_stacking() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.stacking = true
	var rules = _fresh(2, ruleset)

	var d2_a = _card(CardTypes.CardColor.RED, CardTypes.CardValue.DRAW_TWO, 1)
	var d2_b = _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.DRAW_TWO, 2)
	rules.hands[0] = [d2_a, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 5)]
	rules.hands[1] = [d2_b, _card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N4, 6)]
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 7))
	rules.active_color = CardTypes.CardColor.RED
	rules.current_player = 0
	rules.consume_events()

	rules.play_card(0, d2_a)
	_eq(rules.pending_draw, 2, "stack at two")
	_eq(rules.current_player, 1, "victim may respond")

	rules.play_card(1, d2_b)
	_eq(rules.pending_draw, 0, "stack resolved after player 0 cannot answer")
	_eq(rules.hand_size(0), 1 + 4, "player 0 eats four")

	# A +2 stack may be escalated by a +4.
	var ruleset2 = GameRules.Ruleset.new()
	ruleset2.stacking = true
	var r2 = _fresh(2, ruleset2)
	var d2 = _card(CardTypes.CardColor.RED, CardTypes.CardValue.DRAW_TWO, 1)
	var wd4 = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD_DRAW_FOUR, 2)
	r2.hands[0] = [d2, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 5)]
	r2.hands[1] = [wd4, _card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N4, 6)]
	r2.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 7))
	r2.active_color = CardTypes.CardColor.RED
	r2.current_player = 0
	r2.consume_events()
	r2.play_card(0, d2)
	_check(r2.is_playable(wd4), "+4 can answer a +2 stack")
	r2.play_card(1, wd4, CardTypes.CardColor.BLUE)
	_eq(r2.hand_size(0), 1 + 6, "player 0 eats six")


func test_no_stacking() -> void:
	var rules = _fresh(2)  # stacking off by default
	var d2_a = _card(CardTypes.CardColor.RED, CardTypes.CardValue.DRAW_TWO, 1)
	var d2_b = _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.DRAW_TWO, 2)
	rules.hands[0] = [d2_a, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N1, 5)]
	rules.hands[1] = [d2_b, _card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N4, 6)]
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 7))
	rules.active_color = CardTypes.CardColor.RED
	rules.current_player = 0
	rules.consume_events()

	rules.play_card(0, d2_a)
	_eq(rules.hand_size(1), 2 + 2, "victim draws immediately")
	_eq(rules.current_player, 0, "victim is skipped")
	_eq(rules.pending_draw, 0, "no lingering stack")


func test_draw_once() -> void:
	var rules = _fresh(2)
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()
	_check(rules.can_draw(0), "can draw at turn start")
	rules.draw_for_turn(0)
	_check(not rules.can_draw(0), "cannot draw twice")
	_eq(rules.draw_for_turn(0).size(), 0, "second draw yields nothing")


func test_draw_until_playable() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.draw_until_playable = true
	var rules = _fresh(2, ruleset)
	# Stack the deck: two dead cards then a match.
	rules.hands[0] = []
	rules.deck.discard_pile = [_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 100)]
	rules.active_color = CardTypes.CardColor.RED
	rules.deck.draw_pile = [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N8, 103),
		_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N5, 102),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N9, 101)
	]
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()

	var drawn = rules.draw_for_turn(0)
	_eq(drawn.size(), 3, "draws until a playable card appears")
	_check(rules.is_playable(drawn[drawn.size() - 1]), "last drawn card is playable")


func test_pass_rules() -> void:
	var rules = _fresh(2)
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()
	_check(not rules.can_pass(0), "cannot pass before drawing")
	rules.draw_for_turn(0)
	_check(rules.can_pass(0), "can pass after drawing")
	rules.pass_turn(0)
	_eq(rules.current_player, 1, "turn advances on pass")


func test_seven_zero() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.seven_zero = true
	var rules = _fresh(2, ruleset)

	var seven = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N7, 1)
	rules.hands[0] = [seven, _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N2, 2)]
	rules.hands[1] = [
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N4, 3),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N5, 4),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N6, 5)
	]
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 6))
	rules.active_color = CardTypes.CardColor.RED
	rules.current_player = 0
	rules.consume_events()

	rules.play_card(0, seven)
	_eq(rules.hand_size(0), 3, "player receives opponent hand")
	_eq(rules.hand_size(1), 1, "opponent receives player hand")
	_check(_has_event(rules.consume_events(), GameRules.Event.HANDS_SWAPPED), "swap event")


func test_force_play() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.force_play = true
	var rules = _fresh(2, ruleset)
	var red = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1)
	_stage(rules, 0, [red], CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	_check(not rules.can_draw(0), "cannot draw while holding a legal card")

	rules.hands[0] = [_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N2, 2)]
	_check(rules.can_draw(0), "may draw with no legal card")


# ---------------------------------------------------------------------------
# Jump-in
# ---------------------------------------------------------------------------
func test_jump_in_legality() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.jump_in = true
	var rules = _fresh(3, ruleset)

	# Three players; seat 0 is on turn and plays a Red 5 onto a Red 3.
	_stage(rules, 0, [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N2, 2)
	], CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, rules.hands[0][0])
	_eq(rules.current_player, 1, "turn passed to seat 1")
	rules.consume_events()

	# Seat 2 holds an exact twin, a near miss, and a wild.
	var twin = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 10)
	var near = _card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N5, 11)
	var wild = _card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD, 12)
	rules.hands[2] = [twin, near, wild]

	_check(rules.can_jump_in(2, twin), "exact twin may jump in")
	_check(not rules.can_jump_in(2, near), "same value, wrong colour may not")
	_check(not rules.can_jump_in(2, wild), "wilds may never jump in")
	_check(not rules.can_jump_in(1, twin), "a card not in the seat's hand is not a jump-in")
	_check(not rules.can_jump_in(2, _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 99)),
		"an unknown card object is not a jump-in")

	# A live draw stack blocks jump-ins entirely.
	rules.pending_draw = 2
	_check(not rules.can_jump_in(2, twin), "no jump-in into a draw stack")
	rules.pending_draw = 0

	# The untouched opening card cannot be jumped in on, even by an exact twin.
	rules.deck.discard_pile = [_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 50)]
	rules.active_color = CardTypes.CardColor.RED
	_check(not rules.can_jump_in(2, twin), "no jump-in on the untouched opening card")

	# Once a real play covers the opening card, the same twin becomes legal.
	rules.deck.discard_pile = [
		_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N1, 51),
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 52)]
	rules.active_color = CardTypes.CardColor.RED
	_check(rules.can_jump_in(2, twin), "twin of a genuinely played top card is legal")


func test_jump_in_turn_flow() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.jump_in = true
	var rules = _fresh(3, ruleset)

	_stage(rules, 0, [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N2, 2)
	], CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, rules.hands[0][0])
	rules.consume_events()
	_eq(rules.current_player, 1, "seat 1 is on turn")

	var twin = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 10)
	rules.hands[2] = [twin, _card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N8, 11)]
	var played_before = rules.stats_cards_played[2]

	_check(rules.play_card(2, twin), "out-of-turn twin is accepted")
	var events = rules.consume_events()
	var played = _find_event(events, GameRules.Event.CARD_PLAYED)
	_check(played != null and played.get("jump_in", false), "CARD_PLAYED is flagged as a jump-in")
	_eq(rules.current_player, 0, "play resumes from the seat after the jumper")
	_eq(rules.stats_cards_played[2], played_before + 1, "jump-in counts as a play")
	_eq(rules.hand_size(2), 1, "jump-in card left the hand")

	# A jump-in down to one card still exposes the player to a catch.
	_check(rules.uno_vulnerable[2], "silent jump-in to one card is catchable")


func test_jump_in_disabled() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.jump_in = false
	var rules = _fresh(3, ruleset)

	_stage(rules, 0, [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N2, 2)
	], CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, rules.hands[0][0])
	rules.consume_events()

	var twin = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 10)
	rules.hands[2] = [twin]
	_check(not rules.can_jump_in(2, twin), "jump-in is illegal with the rule off")
	_check(not rules.play_card(2, twin), "out-of-turn play is rejected with the rule off")
	var events = rules.consume_events()
	var invalid = _find_event(events, GameRules.Event.INVALID_MOVE)
	_check(invalid != null and invalid.get("reason", "") == "not_your_turn",
		"rejection reports not_your_turn")


# ---------------------------------------------------------------------------
# UNO
# ---------------------------------------------------------------------------
func test_uno_catch() -> void:
	var rules = _fresh(2)
	var last_two = [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N6, 2)
	]
	_stage(rules, 0, last_two, CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	rules.play_card(0, last_two[0])   # down to one, no call
	_check(rules.uno_vulnerable[0], "player is catchable")

	var before = rules.hand_size(0)
	_check(rules.catch_uno(1, 0), "catch succeeds")
	_eq(rules.hand_size(0), before + 2, "catch costs two cards")
	_check(not rules.uno_vulnerable[0], "no longer catchable")
	_check(not rules.catch_uno(1, 0), "cannot catch twice")


func test_uno_safe() -> void:
	var rules = _fresh(2)
	var last_two = [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N6, 2)
	]
	_stage(rules, 0, last_two, CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	_check(rules.call_uno(0), "can declare at two cards")
	rules.play_card(0, last_two[0])
	_check(not rules.uno_vulnerable[0], "declared player is safe")
	_check(not rules.catch_uno(1, 0), "catch fails against a declared player")

	# Late self-call also rescues you.
	var r2 = _fresh(2)
	var pair = [
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1),
		_card(CardTypes.CardColor.RED, CardTypes.CardValue.N6, 2)
	]
	_stage(r2, 0, pair, CardTypes.CardColor.RED, CardTypes.CardValue.N3)
	r2.play_card(0, pair[0])
	_check(r2.call_uno(0), "late self-call allowed")
	_check(not r2.catch_uno(1, 0), "late call blocks the catch")


# ---------------------------------------------------------------------------
# Scoring and match flow
# ---------------------------------------------------------------------------
func test_round_score() -> void:
	var rules = _fresh(2)
	var winner_card = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1)
	rules.hands[0] = [winner_card]
	rules.hands[1] = [
		_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N9, 2),          # 9
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.SKIP, 3),       # 20
		_card(CardTypes.CardColor.WILD, CardTypes.CardValue.WILD_DRAW_FOUR, 4)  # 50
	]
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 5))
	rules.active_color = CardTypes.CardColor.RED
	rules.current_player = 0
	rules.consume_events()

	rules.play_card(0, winner_card)
	var event = _find_event(rules.consume_events(), GameRules.Event.ROUND_ENDED)
	_check(event != null, "round ended event")
	_eq(event["winner"], 0, "player wins")
	_eq(event["points"], 79, "9 + 20 + 50 = 79")
	_eq(rules.scores[0], 79, "score recorded")
	_check(not rules.round_active, "round closed")


func test_match_end() -> void:
	var ruleset = GameRules.Ruleset.new()
	ruleset.target_score = 50
	var rules = _fresh(2, ruleset)
	rules.scores[0] = 40
	var winner_card = _card(CardTypes.CardColor.RED, CardTypes.CardValue.N5, 1)
	rules.hands[0] = [winner_card]
	rules.hands[1] = [_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.SKIP, 2)]  # 20
	rules.deck.discard_pile.append(_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 3))
	rules.active_color = CardTypes.CardColor.RED
	rules.current_player = 0
	rules.consume_events()

	rules.play_card(0, winner_card)
	var events = rules.consume_events()
	_check(_has_event(events, GameRules.Event.MATCH_ENDED), "match ended")
	_check(not rules.match_active, "match closed")
	_eq(rules.scores[0], 60, "40 + 20")


func test_unique_uids() -> void:
	var deck = Deck.new(11)
	deck.build()
	var seen = {}
	for card in deck.draw_pile:
		_check(not seen.has(card.uid), "uid %d is unique" % card.uid)
		seen[card.uid] = true


# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------
func test_ai_legal() -> void:
	for difficulty in range(3):
		var rules = _fresh(2, null, 40 + difficulty)
		var ai = AIPlayer.new(1, difficulty, 99)
		ai.reset_memory(2)
		for _turn in range(40):
			if not rules.round_active:
				break
			var seat = rules.current_player
			var legal = rules.playable_cards(seat)
			if legal.empty():
				if rules.can_draw(seat):
					rules.draw_for_turn(seat)
					if rules.can_pass(seat):
						rules.pass_turn(seat)
				else:
					rules.pass_turn(seat)
				continue
			var choice = ai.choose_card(rules, legal)
			_check(choice != null, "AI returned a card")
			_check(legal.has(choice), "AI choice is legal")
			var color = ai.choose_color(rules) if choice.is_wild() else -1
			rules.play_card(seat, choice, color)
			rules.consume_events()


func test_full_game_simulation() -> void:
	var rules = _fresh(2, null, 2024)
	var ai = AIPlayer.new(1, AIPlayer.Difficulty.HARD, 7)
	ai.reset_memory(2)
	var guard = 0
	while rules.round_active and guard < 3000:
		guard += 1
		_drive_turn(rules, ai)
	_check(not rules.round_active, "round completed within the turn budget")
	_check(guard < 3000, "no infinite loop (used %d steps)" % guard)


func _drive_turn(rules, ai) -> void:
	var seat = rules.current_player
	if rules.awaiting_color_choice:
		rules.choose_color(rules.awaiting_color_player, CardTypes.CardColor.RED)
		rules.consume_events()
		return
	var legal = rules.playable_cards(seat)
	if legal.size() > 0:
		var choice = ai.choose_card(rules, legal)
		var color = ai.choose_color(rules) if choice.is_wild() else -1
		rules.play_card(seat, choice, color)
	elif rules.can_draw(seat):
		rules.draw_for_turn(seat)
		var after = rules.playable_cards(seat)
		if rules.drawn_playable_card != null and after.has(rules.drawn_playable_card):
			var card = rules.drawn_playable_card
			var color2 = ai.choose_color(rules) if card.is_wild() else -1
			rules.play_card(seat, card, color2)
		elif rules.can_pass(seat):
			rules.pass_turn(seat)
	elif rules.can_pass(seat):
		rules.pass_turn(seat)
	else:
		# Nothing legal and nothing to draw - force the turn along.
		rules._advance_turn(false)
	rules.consume_events()


func test_deck_exhaustion_no_softlock() -> void:
	# Regression: an empty shoe that cannot be recycled used to strand the
	# current player - can_draw() stayed true, draw produced nothing, and
	# can_pass() stayed false, so the round never terminated.
	var rules = GameRules.new(2, null, 5)
	rules.start_match(2)
	rules.deck.draw_pile.clear()
	rules.deck.discard_pile = [_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 900)]
	rules.active_color = CardTypes.CardColor.RED
	rules.hands[0] = [_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.N7, 901)]
	rules.hands[1] = [_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.N8, 902)]
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()

	_check(rules.deck_exhausted(), "deck reports itself exhausted")
	_check(not rules.can_draw(0), "cannot draw from an exhausted shoe")
	_check(rules.can_pass(0), "passing is legal when the shoe is dry and nothing is playable")

	# The turn must be escapable.
	var passed = rules.pass_turn(0)
	_check(passed, "pass_turn succeeds on an exhausted shoe")

	# And the round must end rather than spin forever.
	var guard = 0
	while rules.round_active and guard < 50:
		guard += 1
		var player = rules.current_player
		if not rules.pass_turn(player):
			break
	_check(not rules.round_active, "round terminates instead of softlocking")


func test_stalemate_awards_lowest_hand() -> void:
	# When nobody can move, the player holding the fewest points takes the round.
	var rules = GameRules.new(2, null, 11)
	rules.start_match(2)
	rules.deck.draw_pile.clear()
	rules.deck.discard_pile = [_card(CardTypes.CardColor.RED, CardTypes.CardValue.N3, 910)]
	rules.active_color = CardTypes.CardColor.RED
	# Seat 1 holds far less value than seat 0.
	rules.hands[0] = [
		_card(CardTypes.CardColor.BLUE, CardTypes.CardValue.SKIP, 911),
		_card(CardTypes.CardColor.GREEN, CardTypes.CardValue.SKIP, 912)
	]
	rules.hands[1] = [_card(CardTypes.CardColor.YELLOW, CardTypes.CardValue.N1, 913)]
	rules.current_player = 0
	rules.consume_events()

	rules.pass_turn(0)
	_check(not rules.round_active, "stalemate closes the round")
	_check(rules.scores[1] > 0, "lowest hand scores the round (seat 1 got %d)" % rules.scores[1])
	_check(rules.scores[0] == 0, "the higher hand scores nothing")


func test_soak() -> void:
	# Play 100 seeded games across player counts and rule sets, asserting that
	# invariants hold at every step. This is the regression net for the engine.
	var failures = 0
	for seed_value in range(100):
		var players = 2 + (seed_value % 3)
		var ruleset = GameRules.Ruleset.new()
		ruleset.stacking = seed_value % 2 == 0
		ruleset.draw_until_playable = seed_value % 5 == 0
		ruleset.seven_zero = seed_value % 7 == 0
		ruleset.target_score = 200

		var rules = GameRules.new(players, ruleset, seed_value)
		rules.start_match(players)
		var ai = AIPlayer.new(0, seed_value % 3, seed_value)
		ai.reset_memory(players)

		var guard = 0
		while rules.round_active and guard < 4000:
			guard += 1
			ai.seat = rules.current_player
			_drive_turn(rules, ai)

			# Invariant: total cards in play is conserved.
			var total = rules.deck.draw_count() + rules.deck.discard_count()
			for h in rules.hands:
				total += h.size()
			if total != 108:
				failures += 1
				printerr("    seed %d: card count drifted to %d" % [seed_value, total])
				break

			# Invariant: the turn pointer stays in range.
			if rules.current_player < 0 or rules.current_player >= players:
				failures += 1
				printerr("    seed %d: bad current_player %d" % [seed_value, rules.current_player])
				break

		if guard >= 4000:
			failures += 1
			printerr("    seed %d: game did not terminate" % seed_value)

	_eq(failures, 0, "all 100 soak games are clean")
