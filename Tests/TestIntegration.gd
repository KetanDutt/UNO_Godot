extends SceneTree
# Headless integration test.
#
#   godot --no-window -s Tests/TestIntegration.gd
#
# Boots the real main scene and drives it the way a player would: start a match,
# play/draw/pass through several rounds, open every menu, toggle every setting
# and resize the window. Any GDScript runtime error, null dereference or bad
# property write surfaces here rather than in front of a player.
#
# This complements Tests/TestRules.gd, which covers the pure rules layer.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const CardData = preload("res://Scripts/Core/CardData.gd")
const PlayerIdentity = preload("res://Scripts/Core/PlayerIdentity.gd")
const MenuLayer = preload("res://Scripts/UI/MenuLayer.gd")
const HudLayer = preload("res://Scripts/UI/HudLayer.gd")

var _passed := 0
var _failed := 0
var _game = null
var _steps := 0

const MAX_STEPS = 4000


func _init() -> void:
	print("\n=== UNO integration test ===\n")
	# Settings persist to user:// - start from a known state.
	var dir = Directory.new()
	dir.remove("user://settings.cfg")
	call_deferred("_boot")


func _boot() -> void:
	var scene = load("res://Scenes/Gameplay.tscn")
	_check(scene != null, "main scene loads")
	if scene == null:
		_finish()
		return

	var instance = scene.instance()
	get_root().add_child(instance)
	_game = instance
	_check(_game != null, "controller instanced")

	# Let _ready() complete before poking at anything.
	yield(self, "idle_frame")
	yield(self, "idle_frame")

	_run_suite()


func _run_suite() -> void:
	yield(_test_boot_state(), "completed")
	yield(_test_menu_navigation(), "completed")
	yield(_test_settings_toggles(), "completed")
	yield(_test_match_flow(), "completed")
	yield(_test_resize(), "completed")
	yield(_test_multiplayer_seats(), "completed")
	yield(_test_house_rules(), "completed")
	yield(_test_jump_in_and_catch(), "completed")
	yield(_test_opponents_and_remote(), "completed")
	yield(_test_dpad_remote(), "completed")
	_finish()


# ---------------------------------------------------------------------------
# Harness
# ---------------------------------------------------------------------------
func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % message)
	else:
		_failed += 1
		printerr("  FAIL  %s" % message)


func _wait(frames: int = 2) -> void:
	for _i in range(frames):
		yield(self, "idle_frame")


# Advance the scene tree by roughly `seconds` of simulated time.
func _advance(seconds: float) -> void:
	var elapsed = 0.0
	while elapsed < seconds:
		yield(self, "idle_frame")
		elapsed += 0.016


func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
func _test_boot_state() -> void:
	print("\n-- boot --")
	_check(_game.settings != null, "settings system present")
	_check(_game.audio != null, "audio system present")
	_check(_game.effects != null, "effects system present")
	_check(_game.hud != null, "hud present")
	_check(_game.menus != null, "menus present")
	_check(_game.color_picker != null, "colour picker present")
	_check(_game.menus.current_screen == MenuLayer.SCREEN_MAIN, "boots into the main menu")
	yield(_wait(), "completed")


func _test_menu_navigation() -> void:
	print("\n-- menus --")
	for screen in [MenuLayer.SCREEN_SETTINGS, MenuLayer.SCREEN_HELP, MenuLayer.SCREEN_STATS]:
		_game.menus.show_screen(screen)
		yield(_wait(3), "completed")
		_check(_game.menus.current_screen == screen, "opened %s" % screen)

	_game.menus.show_screen(MenuLayer.SCREEN_MAIN)
	yield(_wait(3), "completed")
	_check(_game.menus.current_screen == MenuLayer.SCREEN_MAIN, "returned to main menu")


func _test_settings_toggles() -> void:
	print("\n-- settings --")
	var settings = _game.settings

	# Every cycle control should wrap without error.
	for _i in range(4):
		_game.menus._on_cycle_difficulty()
		_game.menus._on_cycle_opponents()
		_game.menus._on_cycle_target()
		_game.menus._on_cycle_table()
		_game.menus._on_cycle_speed()
	yield(_wait(), "completed")
	_check(settings.difficulty >= 0 and settings.difficulty <= 2, "difficulty stays in range")
	_check(settings.opponent_count >= 1 and settings.opponent_count <= 3, "opponent count in range")
	_check(settings.table_variant >= 0 and settings.table_variant <= 4, "table variant in range")

	for key in ["stacking", "draw_until", "seven_zero", "force_play", "jump_in"]:
		_game.menus._on_toggle_rule(key)
	for key in ["hints", "glyphs", "shake", "particles", "contrast"]:
		_game.menus._on_toggle_display(key)
	yield(_wait(), "completed")
	_check(true, "all toggles fire without error")

	_game.menus._on_volume_changed(0.5, "master")
	_game.menus._on_volume_changed(0.0, "music")
	_game.menus._on_volume_changed(0.9, "sfx")
	yield(_wait(), "completed")
	_check(abs(settings.master_volume - 0.5) < 0.01, "master volume applied")

	# Settings must survive a save/load round-trip.
	settings.save_settings()
	var before = settings.difficulty
	settings.difficulty = 99
	settings.load_settings()
	_check(settings.difficulty == before, "settings reload from disk")

	_game.menus._on_reset_defaults()
	yield(_wait(), "completed")
	_check(settings.difficulty == 1, "reset to defaults works")


func _test_match_flow() -> void:
	print("\n-- match --")
	_game.settings.opponent_count = 1
	_game.settings.animation_speed = 2.0   # keep the test quick
	_game.settings.save_settings()

	_game._on_start_game()
	yield(_advance(2.0), "completed")

	_check(_game.rules != null, "rules created")
	_check(_game.rules.round_active, "round is active")
	_check(_game.rules.hand_size(0) == 7, "player dealt seven cards")
	_check(_game.rules.hand_size(1) == 7, "opponent dealt seven cards")
	_check(_game._views.size() >= 14, "card views spawned")
	_check(_game.rules.top_card() != null, "opening discard exists")

	# Drive the match to completion through the public action handlers.
	var guard = 0
	while _game.rules != null and _game.rules.round_active and guard < 400:
		guard += 1
		yield(_step_player_turn(), "completed")

	if guard >= 400:
		var r = _game.rules
		printerr("    STALL: current=%d round_active=%s awaiting_color=%s(%d) pending=%d drawn=%s" % [
			r.current_player, str(r.round_active), str(r.awaiting_color_choice),
			r.awaiting_color_player, r.pending_draw, str(r.has_drawn_this_turn)])
		printerr("    STALL: draw=%d discard=%d hands=%s playable0=%d can_draw0=%s can_pass0=%s" % [
			r.deck.draw_count(), r.deck.discard_count(),
			str([r.hand_size(0), r.hand_size(1)]), r.playable_cards(0).size(),
			str(r.can_draw(0)), str(r.can_pass(0))])
		printerr("    STALL: busy=%s ai_token=%d active_color=%d" % [
			str(_game._busy), _game._ai_turn_token, r.active_color])
		printerr("    STALL: can_draw1=%s can_pass1=%s playable1=%d" % [
			str(r.can_draw(1)), str(r.can_pass(1)), r.playable_cards(1).size()])
	_check(guard < 400, "round finished in %d steps" % guard)
	_check(not _game.rules.round_active, "round closed cleanly")
	_check(_game.settings.stat_rounds_played >= 1, "rounds-played stat tracked")

	# Card conservation across the whole presentation layer.
	var total = _game.rules.deck.draw_count() + _game.rules.deck.discard_count()
	for hand in _game.rules.hands:
		total += hand.size()
	_check(total == 108, "108 cards still accounted for (found %d)" % total)

	yield(_advance(2.5), "completed")
	var screen = _game.menus.current_screen
	_check(screen == MenuLayer.SCREEN_ROUND or screen == MenuLayer.SCREEN_MATCH,
		"summary screen shown (%s)" % screen)

	# Continue to the next round if the match is still live.
	if screen == MenuLayer.SCREEN_ROUND:
		_game._on_next_round()
		yield(_advance(2.0), "completed")
		_check(_game.rules.round_active, "next round starts")
		_check(_game.rules.round_number == 2, "round counter advanced")


# Perform one legal action for whoever is on turn, waiting for the AI.
func _step_player_turn() -> void:
	var rules = _game.rules
	if rules == null or not rules.round_active:
		yield(_wait(1), "completed")
		return

	if rules.awaiting_color_choice:
		if rules.awaiting_color_player == 0:
			_game._on_color_selected(CardTypes.CardColor.RED)
		yield(_advance(0.3), "completed")
		return

	if rules.current_player != 0:
		# Let the AI take its scheduled turn.
		yield(_advance(0.35), "completed")
		return

	var legal = rules.playable_cards(0)
	if legal.size() > 0:
		var card = legal[0]
		if _game._views.has(card.uid):
			_game._try_play(_game._views[card.uid])
		else:
			rules.play_card(0, card, CardTypes.CardColor.RED)
			_game._process_events(rules.consume_events())
			_game._begin_turn()
	elif rules.can_draw(0):
		_game._on_draw_pressed()
	elif rules.can_pass(0):
		_game._on_pass_pressed()
	else:
		yield(_advance(0.2), "completed")
		return

	yield(_advance(0.3), "completed")


func _test_resize() -> void:
	print("\n-- responsive layout --")
	for size in [Vector2(1920, 1080), Vector2(1024, 600), Vector2(800, 480), Vector2(1280, 720)]:
		get_root().set_size_override(true, size)
		get_root().set_size_override_stretch(true)
		_game._on_viewport_resized()
		yield(_wait(2), "completed")
		_check(true, "laid out at %dx%d" % [size.x, size.y])

	# Cards must stay on screen at the smallest supported size.
	get_root().set_size_override(true, Vector2(800, 480))
	_game._on_viewport_resized()
	yield(_wait(2), "completed")
	var off_screen = 0
	if _game.rules != null:
		for card in _game.rules.hands[0]:
			if _game._views.has(card.uid):
				var view = _game._views[card.uid]
				if view.rest_position.x < -60 or view.rest_position.x > 860:
					off_screen += 1
	_check(off_screen == 0, "no cards escape an 800x480 viewport (%d strays)" % off_screen)

	get_root().set_size_override(true, Vector2(1280, 720))
	_game._on_viewport_resized()
	yield(_wait(2), "completed")


func _test_multiplayer_seats() -> void:
	print("\n-- three and four handed --")
	for opponents in [2, 3]:
		_game.settings.opponent_count = opponents
		_game.settings.save_settings()
		_game._on_restart_game()
		yield(_advance(2.2), "completed")

		_check(_game.rules.player_count() == opponents + 1,
			"%d seats dealt" % (opponents + 1))
		for seat in range(opponents + 1):
			_check(_game.rules.hand_size(seat) == 7, "seat %d holds seven" % seat)

		# Play a handful of turns to exercise multi-seat turn rotation.
		for _i in range(24):
			if not _game.rules.round_active:
				break
			yield(_step_player_turn(), "completed")

		var total = _game.rules.deck.draw_count() + _game.rules.deck.discard_count()
		for hand in _game.rules.hands:
			total += hand.size()
		_check(total == 108, "%d-player card count intact" % (opponents + 1))


func _test_house_rules() -> void:
	print("\n-- house rules --")
	_game.settings.opponent_count = 1
	_game.settings.rule_stacking = true
	_game.settings.rule_draw_until_playable = true
	_game.settings.rule_seven_zero = true
	_game.settings.save_settings()

	_game._on_restart_game()
	yield(_advance(2.0), "completed")
	_check(_game.rules.rules.stacking, "stacking rule applied to the match")
	_check(_game.rules.rules.seven_zero, "seven-zero rule applied")

	for _i in range(60):
		if not _game.rules.round_active:
			break
		yield(_step_player_turn(), "completed")

	var total = _game.rules.deck.draw_count() + _game.rules.deck.discard_count()
	for hand in _game.rules.hands:
		total += hand.size()
	_check(total == 108, "card count intact with house rules")

	# Pause / resume must not strand the game in a busy state. Start a fresh
	# round first so we are testing pause during live play, not after a summary.
	if not _game.rules.round_active:
		_game._on_restart_game()
		yield(_advance(2.0), "completed")
	_check(_game.rules.round_active, "match is live before pausing")
	_game._toggle_pause()
	yield(_wait(3), "completed")
	_check(_game.menus.current_screen == MenuLayer.SCREEN_PAUSE, "pause opens")
	_game._on_resume_game()
	yield(_wait(3), "completed")
	_check(not _game.menus.is_open(), "resume closes the menu")
	_check(not get_tree_paused(), "tree unpaused after resume")

	# Returning to the main menu must tear the table down cleanly.
	_game._show_main_menu()
	yield(_wait(3), "completed")
	_check(_game._views.size() == 0, "table cleared on exit to menu")


func _test_jump_in_and_catch() -> void:
	print("\n-- jump-in and the catch window --")
	_game.settings.opponent_count = 2
	_game.settings.difficulty = 2        # Hard: always catches, always jumps in
	_game.settings.rule_jump_in = true
	# Keep the other house rules out of the way: seven-zero would rewrite the
	# staged hands and stacking changes what a staged play resolves into.
	_game.settings.rule_stacking = false
	_game.settings.rule_draw_until_playable = false
	_game.settings.rule_seven_zero = false
	_game.settings.rule_force_play = false
	_game.settings.animation_speed = 2.0
	_game.settings.save_settings()

	_game._on_restart_game()
	yield(_advance(2.5), "completed")
	var rules = _game.rules
	_check(rules.rules.jump_in, "jump-in rule applied to the match")
	_check(rules.player_count() == 3, "three seats at the table")

	# --- The human jumps in out of turn -------------------------------------
	# Seat 1 plays onto the opening card (so the pile has a real play on top
	# and the turn belongs to seat 2), then the human drops an exact twin.
	# Nothing is scheduled between the staged steps, so the flow is
	# deterministic despite the AI timers elsewhere in the suite.
	rules.current_player = 1
	rules.has_drawn_this_turn = false
	rules.consume_events()
	# A number card only: an action card would skip/stack/reverse and rewrite
	# the turn order the test is about to assert on.
	var ai_card = null
	for card in rules.hands[1]:
		if card.is_number():
			rules.active_color = card.color
			ai_card = card
			break
	_check(ai_card != null, "staged a play for seat 1")
	# Strip every *other* copy so nobody can jump in on this play; keep the
	# chosen instance, which is the card about to be played.
	_strip_exact_copies(rules.hands[2], ai_card)
	for i in range(rules.hands[1].size() - 1, -1, -1):
		var other = rules.hands[1][i]
		if other != ai_card and other.color == ai_card.color and other.value == ai_card.value:
			rules.hands[1].remove(i)
	rules.play_card(1, ai_card)
	_game._process_events(rules.consume_events())
	_check(rules.current_player == 2, "turn moved to seat 2")

	var twin = CardData.new(ai_card.color, ai_card.value, 8888)
	rules.hands[0].append(twin)
	var twin_view = _game._spawn_view(twin, false)
	_game._refresh_all()
	_check(is_instance_valid(twin_view) and twin_view.interactive,
		"twin card is interactive out of turn")
	_check(twin_view.playable, "twin card is highlighted as playable")

	_game._try_play(twin_view)
	_check(rules.top_card() != null and rules.top_card().uid == 8888,
		"human jumped in with the twin")
	_check(not rules.hands[0].has(twin), "jump-in card left the human's hand")
	_check(rules.current_player == 1, "play resumed from the seat after the jumper")

	# --- An AI jumps in on the human's play ---------------------------------
	# Retire the think timer the jump-in dispatch just scheduled, then have
	# the human play a card that seat 2 holds an exact twin of.
	_game._ai_turn_token += 1
	var lead = null
	for card in rules.hands[0]:
		if card.is_number():
			rules.active_color = card.color
			lead = card
			break
	if lead != null:
		_strip_exact_copies(rules.hands[1], lead)
		_strip_exact_copies(rules.hands[2], lead)
		var reply = CardData.new(lead.color, lead.value, 7777)
		rules.hands[2].append(reply)
		rules.current_player = 0
		rules.has_drawn_this_turn = false
		rules.consume_events()
		rules.play_card(0, lead)
		_game._process_events(rules.consume_events())
		# Seat 2's jump-in fires on its reaction delay.
		yield(_advance(1.4), "completed")
		_check(rules.top_card() != null and rules.top_card().uid == 7777,
			"AI jumped in with an exact twin of the human's card")

	# --- The UNO button and the AI catch window ------------------------------
	# Stage the human silently on one card; the HUD must offer the late call,
	# and the hard opponent must catch them once the window elapses.
	_game._on_restart_game()
	yield(_advance(2.5), "completed")
	rules = _game.rules
	while rules.hands[0].size() > 1:
		rules.hands[0].pop_back()
	rules.uno_vulnerable[0] = true
	rules.consume_events()
	_game._refresh_all()
	yield(_wait(2), "completed")
	_check(not _game.hud._uno_button.disabled, "UNO button enabled while vulnerable")

	yield(_advance(1.5), "completed")
	_check(not rules.uno_vulnerable[0], "the opponent caught the missed UNO call")
	_check(rules.hands[0].size() == 3, "catch penalty drew two cards")

	# Leave the settings clean for any run that follows.
	_game.settings.rule_jump_in = false
	_game.settings.difficulty = 1
	_game.settings.save_settings()
	_game._on_restart_game()
	yield(_advance(1.5), "completed")


# Named, avatar'd opponents; a uniform discard pile; the turn ring; and the
# D-pad-only action model that carries the game on a TV remote.
func _test_opponents_and_remote() -> void:
	print("\n-- opponents, the pile and the remote --")
	_game.settings.opponent_count = 2
	_game.settings.rule_jump_in = false
	_game.settings.animation_speed = 2.0
	_game.settings.save_settings()

	_game._on_restart_game()
	yield(_advance(2.5), "completed")
	var rules = _game.rules

	# --- Opponent identities -------------------------------------------------
	_check(rules.player_names[0] == "You", "the human seat is still You")
	var all_named = true
	var unique = true
	var seen = {}
	for i in range(1, rules.player_count()):
		var name = rules.player_names[i]
		if not PlayerIdentity.NAMES.has(name):
			all_named = false
		if seen.has(name):
			unique = false
		seen[name] = true
	_check(all_named, "CPU seats drew names from the roster")
	_check(unique, "no two seats share a name")
	for i in range(rules.player_count()):
		_check(_game.hud.seat_avatar_texture(i) != null,
			"seat %d shows an avatar" % i)

	# --- The discard pile is one size, hand-stacked --------------------------
	# Stage two deterministic plays (the jump-in group's recipe: retire the
	# pending think timer, then play a number card from an AI hand) so the
	# pile holds real played cards from *opponent* hands - the ones that used
	# to land at the wrong scale. An opponent's card renders at 70% in the
	# hand; on the pile it must match the human's cards exactly.
	_game._ai_turn_token += 1
	var staged_seat = 1
	while staged_seat <= 2 and _game._discard_views.size() < 3:
		rules.current_player = staged_seat
		rules.has_drawn_this_turn = false
		rules.consume_events()
		var play = null
		for card in rules.hands[staged_seat]:
			if card.is_number() and card.color == rules.active_color:
				play = card
				break
		if play == null:
			for card in rules.hands[staged_seat]:
				if card.is_number():
					rules.active_color = card.color
					play = card
					break
		if play == null:
			break
		_strip_exact_copies(rules.hands[0], play)
		if staged_seat == 1:
			_strip_exact_copies(rules.hands[2], play)
		rules.play_card(staged_seat, play)
		_game._process_events(rules.consume_events())
		yield(_advance(0.5), "completed")
		staged_seat += 1

	# Let the last throw land before measuring: a card in transit is still
	# scaling and rotating towards its rest pose.
	var views = _game._discard_views
	for _s in range(60):
		var any_flying = false
		for view in views:
			if is_instance_valid(view) and view.is_in_flight():
				any_flying = true
				break
		if not any_flying:
			break
		yield(_advance(0.05), "completed")

	_check(views.size() >= 3, "the pile holds several discards (%d)" % views.size())
	var uniform_scale = true
	var rotations_vary = false
	for i in range(views.size()):
		if not is_instance_valid(views[i]):
			continue
		if abs(views[i].scale.x - views[0].scale.x) > 0.001 \
				or abs(views[i].scale.y - views[0].scale.y) > 0.001:
			uniform_scale = false
		if abs(views[i].rotation_degrees - views[0].rotation_degrees) > 0.5:
			rotations_vary = true
	_check(uniform_scale, "every resting discard renders at the same scale")
	_check(rotations_vary, "pile cards carry varied rotation")

	# --- The turn ring --------------------------------------------------------
	_check(_game._turn_ring != null and _game._turn_ring.visible,
		"the turn ring is on the table")
	_check(_game._turn_ring.direction == rules.direction,
		"the ring spins the way the turn passes")

	# --- Remote model: D-pad only ---------------------------------------------
	var router = _game.input_router
	_check(router != null, "the input router exists")
	# The staged plays above may have snapped focus onto CATCH (that auto-focus
	# is verified in its own suite) - assert the selection MODEL, so reset to
	# the hand first.
	router.reset_to_hand()
	_check(router.zone() == 0, "the selection starts on the hand")
	router.enter_button_zone()
	_check(router.zone() == 1, "up/down reaches the action buttons")
	var first_index = router.button_index()
	router._cycle_buttons(1)
	_check(router.button_index() != first_index, "down cycles the buttons")
	router._cycle_buttons(-1)
	_check(router.button_index() == first_index, "up cycles back")
	router._cycle_buttons(-1)
	_check(router.zone() == 0, "up from the top button returns to the hand")

	# Activating DRAW through the remote path draws a card.
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()
	var hand_before = rules.hands[0].size()
	_game._ai_turn_token += 1
	_game._begin_turn()
	yield(_wait(), "completed")
	router.enter_button_zone()
	_check(router.button_index() == 0, "the selection lands on DRAW when stuck")
	var draw_ok = router.button_index() == 0
	if draw_ok:
		router._activate_focused_button()
		yield(_wait(), "completed")
		_check(rules.hands[0].size() == hand_before + 1,
			"Enter on the focused DRAW button draws a card")

	# Leave the tree clean for anything that follows.
	_game.input_router.reset_to_hand()
	_game.settings.opponent_count = 1
	_game.settings.save_settings()
	_game._on_restart_game()
	yield(_advance(1.5), "completed")


# End-to-end D-pad-only play: hat-button bindings, the pile tint regression,
# the centre ring reversing, and every action being reachable while an
# opponent is thinking (pause and the time-critical CATCH window).
func _test_dpad_remote() -> void:
	print("\n-- D-pad-only remote play --")

	# A pure D-pad remote presents a hat, not a stick: all four directions and
	# Back must answer its buttons in the input map.
	# Godot 3.5 numbers the D-pad hat JOY_DPAD_UP=12..RIGHT=15 (Godot 4's
	# SDL-style numbering differs, so bind the constants, not raw indices).
	var dpad_hats = {"ui_up": JOY_DPAD_UP, "ui_down": JOY_DPAD_DOWN,
		"ui_left": JOY_DPAD_LEFT, "ui_right": JOY_DPAD_RIGHT}
	for action in dpad_hats.keys():
		var bound = false
		for event in InputMap.get_action_list(action):
			if event is InputEventJoypadButton and event.button_index == dpad_hats[action]:
				bound = true
		_check(bound, "%s answers the D-pad hat button" % action)
	var start_bound = false
	for event in InputMap.get_action_list("ui_cancel"):
		if event is InputEventJoypadButton and event.button_index == JOY_START:
			start_bound = true
	_check(start_bound, "ui_cancel answers the Start button")

	# Hints off dims every card in the hand; pile cards must still be full
	# colour - that was the greyed-pile regression.
	_game.settings.show_hints = false
	_game.settings.difficulty = 2
	_game.settings.opponent_count = 2
	_game.settings.rule_jump_in = false
	_game.settings.animation_speed = 2.0
	_game.settings.save_settings()

	_game._on_restart_game()
	yield(_advance(2.5), "completed")
	var rules = _game.rules
	# Stage the human turn directly: retire any in-flight AI think timer and
	# dispatch the seat-0 turn the same way the engine would.
	rules.current_player = 0
	rules.has_drawn_this_turn = false
	rules.consume_events()
	_game._ai_turn_token += 1
	_game._begin_turn()
	yield(_wait(), "completed")
	_check(rules.round_active and rules.current_player == 0, "reached the human turn")

	if rules.round_active and rules.current_player == 0:
		var legal_cards = rules.playable_cards(0)
		if legal_cards.size() > 0:
			# Hat Right moves the hand selection through the router (with a
			# legal card in hand the turn opens on the hand zone).
			var before = _game._selected_index
			var hat_right = InputEventJoypadButton.new()
			hat_right.button_index = JOY_DPAD_RIGHT
			hat_right.pressed = true
			var consumed = _game.input_router.handle(hat_right)
			var expected = int(posmod(before + 1, rules.hands[0].size()))
			_check(consumed and _game._selected_index == expected,
				"D-pad Right cycles the hand selection")

		# With hints off every interactive fan card is dimmed.
		var dimmed = 0
		for card in rules.hands[0]:
			if _game._views.has(card.uid) and _game._views[card.uid]._sprite.modulate.r < 0.8:
				dimmed += 1
		_check(dimmed == rules.hands[0].size(),
			"hints-off cards in the hand are dimmed (%d/%d)" % [dimmed, rules.hands[0].size()])

		# Play a number card and check the copy on the centre pile is bright.
		var chosen = null
		for card in legal_cards:
			if card.is_number():
				chosen = card
				break
		if chosen == null:
			for card in legal_cards:
				if not card.is_wild():
					chosen = card
					break
		if chosen != null:
			var played_uid = chosen.uid
			_game._try_play(_game._views[played_uid])
			# A wild opens the mandatory colour picker; resolve it the same
			# way the other suites do, otherwise the card never lands.
			if rules.awaiting_color_choice:
				_game._on_color_selected(CardTypes.CardColor.RED)
			yield(_advance(0.6), "completed")
			if rules.awaiting_color_choice:
				_game._on_color_selected(CardTypes.CardColor.RED)
				yield(_wait(4), "completed")
			var pile_view = null
			for view in _game._discard_views:
				if is_instance_valid(view) and view.card_data != null \
						and view.card_data.uid == played_uid:
					pile_view = view
			_check(pile_view != null, "the played card reached the centre pile")
			if pile_view != null:
				var tint = pile_view._sprite.modulate
				_check(tint.r >= 0.99 and tint.g >= 0.99 and tint.b >= 0.99,
					"the played pile card is not greyed out (%.2f %.2f %.2f)" % [
						tint.r, tint.g, tint.b])

	# Every face-up card anywhere on the pile shows full colour.
	var pile_bright = true
	for view in _game._discard_views:
		if is_instance_valid(view) and view.card_data != null and not view.face_down:
			var tint = view._sprite.modulate
			if tint.r < 0.99 or tint.g < 0.99 or tint.b < 0.99:
				pile_bright = false
	_check(pile_bright, "every face on the centre pile is full colour")

	# The centre ring's arrow flips with the rules direction.
	var ring = _game._turn_ring
	ring.set_direction(-1)
	_check(ring.direction == -1, "the centre ring reverses counter-clockwise")
	ring.set_direction(1)
	_check(ring.direction == 1, "the centre ring restores clockwise")

	# Actions must stay reachable while an opponent is thinking.
	rules.current_player = 1
	rules.has_drawn_this_turn = false
	if rules.awaiting_color_choice:
		_game._on_color_selected(CardTypes.CardColor.RED)
	rules.consume_events()
	_game._ai_turn_token += 1
	_game._begin_turn()
	yield(_wait(), "completed")
	_check(_game._busy, "an opponent turn blocks acting")
	var router = _game.input_router
	router.focus_button(HudLayer.BUTTON_MENU)
	_check(router.zone() == 1 and router.button_index() == HudLayer.BUTTON_MENU,
		"MENU is reachable on the D-pad while an opponent thinks")
	router._activate_focused_button()
	yield(_wait(2), "completed")
	_check(_game.menus.current_screen == MenuLayer.SCREEN_PAUSE,
		"activating MENU pauses mid opponent turn")

	# Back while paused must resume - the GameController is frozen, so the
	# menu layer answers it itself.
	var back = InputEventJoypadButton.new()
	back.button_index = JOY_XBOX_B
	back.pressed = true
	_game.menus._unhandled_input(back)
	yield(_wait(3), "completed")
	_check(not _game.menus.is_open() and not get_tree_paused(),
		"Back on the pause screen resumes play")

	# A catchable opponent selects CATCH for the remote player automatically.
	yield(_advance(0.2), "completed")
	router.reset_to_hand()
	for i in range(rules.player_count()):
		rules.uno_vulnerable[i] = false
	_game._refresh_all()
	while rules.hands[1].size() > 1:
		rules.hands[1].pop_back()
	var caught_before = rules.hands[1].size()
	rules.uno_vulnerable[1] = true
	rules.consume_events()
	_game._refresh_all()
	_check(router.zone() == 1 and router.button_index() == HudLayer.BUTTON_CATCH,
		"the selection jumps to CATCH when the window opens")
	router._activate_focused_button()
	yield(_wait(2), "completed")
	_check(not rules.uno_vulnerable[1], "the remote CATCH lands")
	_check(rules.hands[1].size() == caught_before + 2,
		"the caught opponent drew two cards")
	router.reset_to_hand()

	# Leave clean settings for anything that follows.
	_game.settings.show_hints = true
	_game.settings.difficulty = 1
	_game.settings.opponent_count = 1
	_game.settings.rule_jump_in = false
	_game.settings.animation_speed = 2.0
	_game.settings.save_settings()
	_game._on_restart_game()
	yield(_advance(1.5), "completed")


# Remove every card identical to `card` from a hand (test staging aid).
func _strip_exact_copies(hand: Array, card) -> void:
	for i in range(hand.size() - 1, -1, -1):
		if hand[i].color == card.color and hand[i].value == card.value:
			hand.remove(i)


func get_tree_paused() -> bool:
	return paused
