extends Reference
# EventPresenter
# --------------
# Turns the rules engine's semantic Event queue into everything the player sees
# and hears: card animations, HUD updates, particles, sound cues and the
# round/match summary screens.
#
# The split matters. GameRules mutates state and appends events; nothing in this
# file may change game state. That keeps the simulation authoritative and means
# the presentation can lag behind, be sped up, or be skipped entirely without
# the two ever disagreeing.
#
# `_game` is the GameController that owns this presenter; it provides the scene
# nodes, the card views and the systems (audio, effects, hud, menus).

const GameRules = preload("res://Scripts/Core/GameRules.gd")
const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const TableLayout = preload("res://Scripts/UI/TableLayout.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")
const ThemeFactory = preload("res://Scripts/Systems/ThemeFactory.gd")
const Deck = preload("res://Scripts/Core/Deck.gd")
const MenuLayer = preload("res://Scripts/UI/MenuLayer.gd")

# Older discards are culled from the scene tree; only this many stay visible.
const DISCARD_VISIBLE_LIMIT = DrawOrder.PILE_DEPTH

var _game = null


func _init(game) -> void:
	_game = game

# ---------------------------------------------------------------------------
# Event replay
# ---------------------------------------------------------------------------
# Walk the _game.rules event queue and turn each entry into presentation.
func process_events(events: Array) -> void:
	for event in events:
		match event["type"]:
			GameRules.Event.GAME_STARTED:
				_on_event_game_started(event)
			GameRules.Event.CARD_DEALT:
				_on_event_card_dealt(event)
			GameRules.Event.OPENING_CARD:
				_on_event_opening(event)
			GameRules.Event.CARD_PLAYED:
				_on_event_card_played(event)
			GameRules.Event.CARD_DRAWN:
				_on_event_card_drawn(event)
			GameRules.Event.COLOR_CHOSEN:
				_on_event_color_chosen(event)
			GameRules.Event.COLOR_CHOICE_REQUIRED:
				_on_event_color_required(event)
			GameRules.Event.TURN_CHANGED:
				_on_event_turn_changed(event)
			GameRules.Event.DIRECTION_REVERSED:
				_on_event_reversed(event)
			GameRules.Event.PLAYER_SKIPPED:
				_on_event_skipped(event)
			GameRules.Event.PENALTY_DRAW:
				_on_event_penalty(event)
			GameRules.Event.STACK_GROWN:
				_on_event_stack(event)
			GameRules.Event.UNO_CALLED:
				_on_event_uno(event)
			GameRules.Event.UNO_PENALTY:
				_on_event_uno_penalty(event)
			GameRules.Event.HANDS_SWAPPED, GameRules.Event.HANDS_ROTATED:
				_on_event_hands_moved(event)
			GameRules.Event.DECK_RECYCLED:
				_on_event_recycled(event)
			GameRules.Event.DECK_EXHAUSTED:
				_on_event_deck_exhausted(event)
			GameRules.Event.ROUND_ENDED:
				_on_event_round_ended(event)
			GameRules.Event.MATCH_ENDED:
				_on_event_match_ended(event)
			GameRules.Event.INVALID_MOVE:
				_on_event_invalid(event)

	_game._refresh_all()


func _on_event_game_started(event: Dictionary) -> void:
	_game._game_active = true
	_game._play_cue("shuffle")
	_game.hud.announce("ROUND %d" % event["round"], ThemeFactory.ACCENT)


func _on_event_card_dealt(event: Dictionary) -> void:
	var player = event["player"]
	var card = event["card"]
	var view = _game._spawn_view(card, player != 0)
	# Stagger the deal so cards arrive one at a time like a real dealer. Cards
	# fly straight to their fan slot in the flight band (above the deck backs
	# they start on and above every resting card they pass).
	var delay = _game.settings.anim_scale(0.055) * (event["index"] * _game.rules.player_count() + player)
	var slot = _game._fan_slot(player, event["index"])
	view.set_card_scale(slot["scale"])
	view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], delay)
	_schedule_deal_sound(delay)


func _schedule_deal_sound(delay: float) -> void:
	# Gameplay timers pause with the tree so a pause menu freezes the deal.
	var timer = _game.get_tree().create_timer(delay, false)
	timer.connect("timeout", _game, "_play_cue", ["deal"])


func _on_event_opening(event: Dictionary) -> void:
	var card = event["card"]
	var view = _game._spawn_view(card, true)
	# The opening card's view belongs to the pile, not to any hand: drop it
	# from the view registry (exactly like a played card) so a later recycle
	# + redraw of the same card cannot "find" a stale pile view and skip
	# spawning a fresh one, leaving the drawn card with no view of its own.
	_game._views.erase(card.uid)
	# The opening card waits face-down ON TOP of the deck (its discard-band
	# depth sits above the deck backs) until the dealer flips it out.
	view.position = _game._deck_position()
	_game._discard_views.append(view)
	_stamp_discard_order()
	var deal_time = _game.settings.anim_scale(0.055) \
		* _game.rules.player_count() * _game.rules.rules.starting_hand
	var delay = deal_time + 0.1
	var timer = _game.get_tree().create_timer(delay, false)
	timer.connect("timeout", self, "_reveal_opening", [view])


func _reveal_opening(view) -> void:
	# The round can end (or restart) before this timer fires.
	if not is_instance_valid(view):
		return
	view.set_card_scale(TableLayout.player_card_scale(_game._viewport_size()))
	view.discard_offset = Vector2(rand_range(-11, 11), rand_range(-8, 8))
	view.play_to(_game._discard_position() + view.discard_offset, rand_range(-13, 13), view.rest_z)
	view.flip_to(true)
	_game._play_cue("card_flip")
	_game._play_cue("card_place")
	_game.effects.burst(_game._discard_position(), CardTypes.color_value(_game.rules.active_color), 18)
	_game._refresh_all()
	_game._begin_turn()


func _on_event_card_played(event: Dictionary) -> void:
	var card = event["card"]
	var player = event["player"]
	var view = _game._views.get(card.uid)
	if view == null:
		view = _game._spawn_view(card, false)
		view.position = _game._anchor_for(player)

	_game._views.erase(card.uid)
	_game._discard_views.append(view)

	for ai in _game.ai_players:
		ai.note_play(player, card)

	# Cull the pile, then re-stamp its depth order before the flight: the new
	# top card must land above every card already resting there.
	_cull_discards()
	_stamp_discard_order()

	# The pile is one place with one scale: an opponent's card must not land
	# smaller than yours just because opponent hands render smaller. Re-base
	# the view's scale to the discard scale before the throw.
	view.set_card_scale(TableLayout.player_card_scale(_game._viewport_size()))
	# Rotate and nudge each discard so the pile looks hand-stacked.
	var rotation = rand_range(-13, 13)
	var offset = Vector2(rand_range(-11, 11), rand_range(-8, 8))
	view.discard_offset = offset
	view.set_playable(false)
	view.set_focused(false)
	if view.face_down:
		# An opponent's card reveals as it is thrown.
		view.flip_to(true)
		_game._play_cue("card_flip", rand_range(0.92, 1.08))
	view.play_to(_game._discard_position() + offset, rotation, view.rest_z)

	_game._play_cue("card_place", rand_range(0.94, 1.07))
	var tint = CardTypes.color_value(card.effective_color())
	_game.effects.burst(_game._discard_position(), tint, 20)

	# Jump-ins steal the beat: slam the announcement in before anything else.
	if event.get("jump_in", false):
		_game._play_cue("jump_in")
		_game.hud.announce("JUMP IN!", ThemeFactory.ACCENT)
		_game.effects.impact_ring(_game._discard_position(), tint)
		_game.effects.shake(7.0)

	# Action cards get their own flourish.
	match card.value:
		CardTypes.CardValue.SKIP:
			_game._play_cue("skip")
			_game.effects.impact_ring(_game._discard_position(), tint)
			_game.effects.shake(5.0)
		CardTypes.CardValue.REVERSE:
			_game._play_cue("reverse")
			_game.effects.impact_ring(_game._discard_position(), tint)
		CardTypes.CardValue.DRAW_TWO:
			_game._play_cue("draw_penalty", 1.35)
			_game.effects.shake(6.0)
		CardTypes.CardValue.WILD, CardTypes.CardValue.WILD_DRAW_FOUR:
			_game._play_cue("wild")
			_game.effects.sparkle(_game._discard_position(), Color(1, 1, 1), 24)


# The pile paints bottom-to-top in PLAY order. Godot breaks z ties in tree
# (spawn) order, so equal depths - which is what every discard past the sixth
# used to get - made a freshly played card slide under the card it should have
# covered. Re-stamping the whole stack on every play keeps the order strict.
func _stamp_discard_order() -> void:
	for i in range(_game._discard_views.size()):
		var view = _game._discard_views[i]
		if is_instance_valid(view):
			view.set_rest_z(DrawOrder.discard(i + 1))


# Keep only the top few discard views alive; the rest are pure history.
func _cull_discards() -> void:
	while _game._discard_views.size() > DISCARD_VISIBLE_LIMIT:
		var oldest = _game._discard_views.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()


func _on_event_card_drawn(event: Dictionary) -> void:
	var player = event["player"]
	for ai in _game.ai_players:
		ai.note_draw(player, _game.rules.active_color)
	_spawn_drawn(player, event["cards"], "card_draw")


func _on_event_penalty(event: Dictionary) -> void:
	var player = event["player"]
	_spawn_drawn(player, event["cards"], "draw_penalty")
	_game.effects.shake(9.0)
	_game.effects.impact_ring(_game._anchor_for(player), Color(0.95, 0.35, 0.3))
	_game.effects.float_text("+%d" % event["count"], _game._anchor_for(player) + Vector2(0, -70),
		Color(1.0, 0.42, 0.36), 40)
	if player == 0:
		_game.effects.flash(Color(0.9, 0.2, 0.2), 0.22, 0.4)


func _spawn_drawn(player: int, cards: Array, cue: String) -> void:
	for i in range(cards.size()):
		var card = cards[i]
		if _game._views.has(card.uid):
			continue
		var view = _game._spawn_view(card, player != 0)
		var delay = _game.settings.anim_scale(0.09) * i
		# Drawn cards fly from the deck straight into their fan slot, above
		# every resting card, exactly like the opening deal.
		var index = _game.rules.hands[player].find(card)
		if index < 0:
			index = 0
		var slot = _game._fan_slot(player, index)
		view.set_card_scale(slot["scale"])
		view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], delay)
		# A rising pitch across a multi-card draw sells the "and another one".
		var timer = _game.get_tree().create_timer(delay, false)
		timer.connect("timeout", _game, "_play_cue", [cue, 1.0 + i * 0.06])


func _on_event_color_chosen(event: Dictionary) -> void:
	var color = event["color"]
	_game.hud.set_active_color(color)
	_game.effects.burst(_game._discard_position(), CardTypes.color_value(color), 34, 260.0)
	_game.effects.flash(CardTypes.color_value(color), 0.16, 0.4)
	if event["player"] != 0:
		_game.hud.announce(CardTypes.color_name(color).to_upper(), CardTypes.color_value(color))


func _on_event_color_required(event: Dictionary) -> void:
	if event["player"] == 0:
		_game._pending_wild_card = event["card"]
		# Wait for the card to land before covering the screen.
		var timer = _game.get_tree().create_timer(_game.settings.anim_scale(0.34), false)
		timer.connect("timeout", self, "_open_color_picker")
	# AI colour choices are resolved inline by _run_ai_turn.


func _open_color_picker() -> void:
	if _game.rules == null or not _game.rules.awaiting_color_choice:
		return
	var counts = _game.rules.color_counts(0)
	var suggested = 0
	for color in CardTypes.PLAYABLE_COLORS:
		if counts[color] > counts[suggested]:
			suggested = color
	_game.color_picker.open(suggested)


func on_color_selected(color: int) -> void:
	if _game.rules == null or not _game.rules.awaiting_color_choice:
		return
	_game.color_picker.close()
	_game._play_cue("button")
	_game.rules.choose_color(0, color)
	process_events(_game.rules.consume_events())
	_game._begin_turn()


func _on_event_turn_changed(_event: Dictionary) -> void:
	_game._selected_index = 0
	_game.hud.set_direction(_game.rules.direction)
	_game.pulse_turn_ring()


func _on_event_reversed(event: Dictionary) -> void:
	_game.hud.set_direction(_game.rules.direction)
	if not event["acts_as_skip"]:
		_game.hud.announce("REVERSE", Color(0.5, 0.85, 1.0))
	_game.effects.shake(4.0)


func _on_event_skipped(event: Dictionary) -> void:
	var player = event["player"]
	_game.effects.float_text("SKIPPED", _game._anchor_for(player) + Vector2(0, -70), Color(1.0, 0.75, 0.3), 34)


func _on_event_stack(event: Dictionary) -> void:
	_game.hud.set_pending_stack(event["amount"])
	if event["amount"] > 2:
		_game.effects.shake(7.0)
		_game.hud.announce("+%d STACKED" % event["amount"], Color(1.0, 0.5, 0.35))


func _on_event_uno(event: Dictionary) -> void:
	var player = event["player"]
	_game._play_cue("uno")
	_game.hud.announce("UNO!", ThemeFactory.ACCENT)
	_game.effects.sparkle(_game._anchor_for(player), ThemeFactory.ACCENT, 30)
	_game.effects.flash(ThemeFactory.ACCENT, 0.14, 0.5)
	if player == 0:
		_game.settings.stat_uno_calls += 1


func _on_event_uno_penalty(event: Dictionary) -> void:
	var player = event["player"]
	_spawn_drawn(player, event["cards"], "draw_penalty")
	var who = "CAUGHT!" if player == 0 else "GOTCHA!"
	_game.hud.announce(who, ThemeFactory.DANGER)
	_game.effects.shake(11.0)
	_game.effects.flash(Color(0.9, 0.2, 0.2), 0.25, 0.45)


func _on_event_hands_moved(_event: Dictionary) -> void:
	# Hands changed owner: rebuild every view so faces and positions are right.
	_game.hud.announce("HANDS SWAPPED", Color(0.7, 0.6, 1.0))
	_game._play_cue("shuffle")
	_game._rebuild_all_views()


func _on_event_recycled(_event: Dictionary) -> void:
	_game._play_cue("shuffle")
	_game.hud.set_status("The discard pile was reshuffled into the deck.")
	# Drop the old discard views; the pile logically no longer exists.
	while _game._discard_views.size() > 1:
		var oldest = _game._discard_views.pop_front()
		if is_instance_valid(oldest):
			oldest.fly_out(_game._deck_position())
	_stamp_discard_order()
	pulse_deck()


func pulse_deck() -> void:
	var tween = _game.create_tween()
	tween.tween_property(_game._deck_stack, "scale", Vector2(1.12, 1.12), _game.settings.anim_scale(0.14)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_game._deck_stack, "scale", Vector2.ONE, _game.settings.anim_scale(0.22)) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _on_event_invalid(event: Dictionary) -> void:
	if event.get("reason", "") == "illegal" and event.get("player", -1) == 0:
		var card = event.get("card")
		if card != null and _game._views.has(card.uid):
			_game._views[card.uid].shake_invalid()
		_game._play_cue("error")


# The shoe ran dry with nobody able to move; the round is scored as it stands.
func _on_event_deck_exhausted(_event: Dictionary) -> void:
	_game.hud.announce("Deck exhausted - lowest hand wins")
	_game.hud.set_status("No cards left to draw")
	_game.audio.play("shuffle")


func _on_event_round_ended(event: Dictionary) -> void:
	_game._game_active = false
	var won = event["winner"] == 0
	_game.settings.stat_cards_played += _game.rules.stats_cards_played[0]
	_game.settings.stat_rounds_played += 1
	if won:
		_game.settings.stat_rounds_won += 1
		_game.settings.stat_best_score = int(max(_game.settings.stat_best_score, event["points"]))
	_game.settings.save_settings()

	# The winning card takes a bow on top of the pile.
	var winning_view = null
	for i in range(_game._discard_views.size() - 1, -1, -1):
		var candidate = _game._discard_views[i]
		if is_instance_valid(candidate):
			winning_view = candidate
			break
	if winning_view != null:
		winning_view.celebrate()
		_game.effects.sparkle(_game._discard_position(), ThemeFactory.ACCENT, 34)

	if won:
		_game._play_cue("win")
		_game.effects.confetti(_game._viewport_size(), [
			CardTypes.color_value(0), CardTypes.color_value(1),
			CardTypes.color_value(2), CardTypes.color_value(3)
		])
	else:
		_game._play_cue("lose")
	_game.audio.duck_music(1.4)

	# Let the winning animation breathe before the summary panel appears.
	var timer = _game.get_tree().create_timer(_game.settings.anim_scale(1.5), false)
	timer.connect("timeout", self, "_show_round_summary", [event])


func _show_round_summary(event: Dictionary) -> void:
	# The match-over screen supersedes the round summary.
	if not _game.rules.match_active:
		return
	var lines = []
	var breakdown = event.get("breakdown", [])
	for i in range(_game.rules.player_names.size()):
		var gained = breakdown[i] if i < breakdown.size() else 0
		# Points banked this round next to the running match total.
		lines.append("%-9s %+5d   total %d" % [
			_game.rules.player_names[i], gained, event["scores"][i]])
	lines.append("")
	lines.append("First to %d wins the match" % _game.rules.rules.target_score)
	_game.menus.return_screen = MenuLayer.SCREEN_ROUND
	_game.menus.show_round_summary(event["winner"] == 0, event["points"], lines)


func _on_event_match_ended(event: Dictionary) -> void:
	var won = event["winner"] == 0
	if won:
		_game.settings.stat_games_won += 1
	_game.settings.save_settings()

	var lines = []
	lines.append("%s wins the match" % _game.rules.player_names[event["winner"]])
	lines.append("")
	for i in range(_game.rules.player_names.size()):
		lines.append("%s   %d points" % [_game.rules.player_names[i], event["scores"][i]])

	var timer = _game.get_tree().create_timer(_game.settings.anim_scale(1.7), false)
	timer.connect("timeout", self, "_present_match_over", [won, lines])


func _present_match_over(won: bool, lines: Array) -> void:
	_game.menus.return_screen = MenuLayer.SCREEN_MATCH
	_game.menus.show_match_over(won, lines)
