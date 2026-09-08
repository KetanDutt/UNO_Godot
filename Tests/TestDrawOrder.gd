extends SceneTree
# Draw-order regression tests.
#
#   godot --no-window -s Tests/TestDrawOrder.gd
#
# Guards the composition's DEPTH (TableLayout guards its geometry): the canvas
# strata, the DrawOrder z bands, and the ordering rules that are easy to break
# and hard to notice - a discard pile that paints in deal order, hand cards
# that draw above the pile, dealt cards that slide out from under the deck.
#
# The paint order is computed exactly the way VisualServerCanvas does it:
# effective z accumulates down the tree (z_index adds to the parent's unless
# z_as_relative is off), items sort by effective z, and tree order breaks ties.
# Controls do not expose z_index, so they render at the inherited z.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")

var _passed := 0
var _failed := 0
var _game = null
var _visit := 0


func _init() -> void:
	print("\n=== UNO draw-order test suite ===\n")
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

	yield(self, "idle_frame")
	yield(self, "idle_frame")

	_game.settings.opponent_count = 1
	_game.settings.animation_speed = 6.0
	_game.settings.show_hints = true
	_game.settings.save_settings()

	_run_suite()


func _run_suite() -> void:
	yield(_test_canvas_strata(), "completed")
	yield(_test_deal_bands(), "completed")
	yield(_test_pile_play_order(), "completed")
	yield(_test_flight_band(), "completed")
	yield(_test_played_card_above_hand(), "completed")
	yield(_test_hover_drag_bands(), "completed")
	yield(_test_big_hand_isolated(), "completed")
	yield(_test_ghost_healing(), "completed")
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


# Wait in *real* time, not frame counts. A headless main loop can tick at
# hundreds of iterations per second with sub-millisecond deltas, so a
# frame-counted wait may advance no tween, timer or AI turn at all before the
# assertions run. Everything this suite waits for is driven by real time
# (tweens, SceneTreeTimers), so real time is the correct clock.
func _advance(seconds: float) -> void:
	var deadline = OS.get_ticks_msec() + int(seconds * 1000.0)
	yield(self, "idle_frame")
	while OS.get_ticks_msec() < deadline:
		yield(self, "idle_frame")


func _finish() -> void:
	print("\n=== %d passed, %d failed ===\n" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# Effective z of one node, accumulated from the world root exactly as the
# renderer does it.
func _effective_z(node, start_z: int = 0) -> int:
	var chain = []
	var cur = node
	while cur != null and cur != _game:
		chain.push_front(cur)
		cur = cur.get_parent()
	var z = start_z
	for item in chain:
		var own = item.get("z_index")
		if own == null:
			continue
		var relative = item.get("z_as_relative")
		if relative != null and not relative:
			z = own
		else:
			z += own
	return z


# Full paint order of the world canvas: [{node, z, visit}] sorted the way the
# renderer draws it.
func _world_order() -> Array:
	var out = []
	_visit = 0
	_walk(_game, 0, out)
	out.sort_custom(self, "_sort_entries")
	return out


func _sort_entries(a, b) -> bool:
	if a["z"] != b["z"]:
		return a["z"] < b["z"]
	return a["visit"] < b["visit"]


func _walk(node, parent_z: int, out: Array) -> void:
	var own = node.get("z_index")
	if own != null:
		var relative = node.get("z_as_relative")
		if relative != null and not relative:
			parent_z = own
		else:
			parent_z += own
	out.append({"node": node, "z": parent_z, "visit": _visit})
	_visit += 1
	for child in node.get_children():
		if child is CanvasLayer:
			continue
		if child is CanvasItem:
			_walk(child, parent_z, out)


func _hand_views(player: int) -> Array:
	var views = []
	for card in _game.rules.hands[player]:
		if _game._views.has(card.uid) and is_instance_valid(_game._views[card.uid]):
			views.append(_game._views[card.uid])
	return views


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

# The big strata: world (implicit layer 0) < HUD < flash < picker < menus.
# A card can never render above the HUD, and no menu can render under the
# colour picker it may be answering.
func _test_canvas_strata() -> void:
	print("-- canvas strata --")
	_check(_game.hud.layer == DrawOrder.LAYER_HUD, "HUD layer is %d" % DrawOrder.LAYER_HUD)
	var flash = _game.get_node_or_null("FlashLayer")
	_check(flash != null, "flash layer is named and reachable")
	if flash != null:
		_check(flash.layer == DrawOrder.LAYER_FLASH, "flash layer is %d" % DrawOrder.LAYER_FLASH)
	_check(_game.color_picker.layer == DrawOrder.LAYER_PICKER,
		"colour picker layer is %d" % DrawOrder.LAYER_PICKER)
	_check(_game.menus.layer == DrawOrder.LAYER_MENUS, "menu layer is %d" % DrawOrder.LAYER_MENUS)
	_check(DrawOrder.LAYER_HUD < DrawOrder.LAYER_FLASH
		and DrawOrder.LAYER_FLASH < DrawOrder.LAYER_PICKER
		and DrawOrder.LAYER_PICKER < DrawOrder.LAYER_MENUS,
		"strata are strictly ordered")
	yield(_wait(), "completed")


# After the deal: every group rests inside its own band, so no group can ever
# paint over another regardless of hand sizes or pile depth.
func _test_deal_bands() -> void:
	print("-- world bands after the deal --")
	_game._on_start_game()
	yield(_advance(2.5), "completed")

	var order = _world_order()
	var by_name = {}
	for entry in order:
		by_name[entry["node"].name] = entry["z"]

	_check(by_name.get("Table", -1) == DrawOrder.TABLE, "table felt is at z %d" % DrawOrder.TABLE)

	var backs = []
	for child in _game._deck_stack.get_children():
		if child is Sprite:
			backs.append(child.z_index)
	backs.sort()
	_check(backs.size() == DrawOrder.DECK_DEPTH, "deck stack has %d backs" % DrawOrder.DECK_DEPTH)
	_check(backs[0] == DrawOrder.DECK and backs.back() == DrawOrder.deck_back(DrawOrder.DECK_DEPTH - 1),
		"deck backs fill their band (%s)" % str(backs))

	for player in range(_game.rules.player_count()):
		var views = _hand_views(player)
		var in_band = true
		for i in range(views.size()):
			if views[i].z_index != DrawOrder.hand(i):
				in_band = false
		_check(in_band and views.size() > 0,
			"seat %d hand rests in its band (z %d..%d)" % [
				player, DrawOrder.hand(0), DrawOrder.hand(views.size() - 1)])

	_check(_game._discard_views.size() >= 1
		and _game._discard_views[0].z_index == DrawOrder.discard(1),
		"opening card rests at the bottom of the pile band")

	_check(_game.effects.z_index == DrawOrder.EFFECTS,
		"effects sit above every card at z %d" % DrawOrder.EFFECTS)
	yield(_wait(), "completed")


# The bug that made the pile paint in spawn order: past the sixth discard every
# card used to land on the same z, and Godot broke the tie in tree order, so a
# freshly played card slid under the pile. The pile must now be strictly
# ordered by play, and its top must be the logical top of the discard.
func _test_pile_play_order() -> void:
	print("-- discard pile paints in play order --")
	# Enough plays to push the pile past its cull limit, where the old code
	# saturated every discard onto the same z. Stop as soon as we have them.
	for _i in range(24):
		if _game.rules.deck.discard_count() >= 9:
			break
		if not _game.rules.round_active:
			_game._on_start_game()
			yield(_advance(1.5), "completed")
		yield(_take_turn(), "completed")

	var pile = _game._discard_views
	# A card thrown at the pile sits in the FLYING band until its tween lands
	# it in the discard band - by design. An opponent can play arbitrarily late
	# inside the 0.5 s turn window, so wait for any in-flight pile card to land
	# before sampling depths (bounded, like every wait in this suite).
	for _s in range(40):
		var any_flying = false
		for view in pile:
			if is_instance_valid(view) and view.is_in_flight():
				any_flying = true
				break
		if not any_flying:
			break
		yield(_advance(0.05), "completed")
	_check(pile.size() > 3, "several discards accumulated (%d views)" % pile.size())
	var strictly_rising = true
	for i in range(pile.size() - 1):
		if not is_instance_valid(pile[i]) or not is_instance_valid(pile[i + 1]):
			continue
		if pile[i].z_index >= pile[i + 1].z_index:
			strictly_rising = false
	_check(strictly_rising, "pile z strictly increases from bottom to top")

	var top = pile.back()
	var logical_top = _game.rules.deck.top_discard()
	_check(is_instance_valid(top) and top.card_data == logical_top,
		"top pile view is the card that was played last")
	_check(top.z_index == DrawOrder.discard(min(pile.size(), DrawOrder.PILE_DEPTH)),
		"top of the pile is the highest depth in the band")
	yield(_wait(), "completed")


# While the staggered deal plays out, cards fly in the flight band - above the
# deck backs they start on and above every resting card they pass. The deal
# flight must also survive the refresh that follows the event batch, which is
# what used to collapse the stagger into one simultaneous clump.
func _test_flight_band() -> void:
	print("-- cards in transit --")
	_game._on_start_game()

	# Synchronous snapshot: the deal events and the trailing refresh have both
	# run, and no frame has elapsed yet. Every card must still be sitting on
	# the deck in the flight band with its staggered tween alive - a refresh
	# that re-targeted them would already have dropped them out of the band.
	var deck = _game._deck_position()
	var flying = 0
	for player in range(_game.rules.player_count()):
		for view in _hand_views(player):
			if view.is_in_flight() \
					and view.z_index == DrawOrder.FLYING \
					and view.position.distance_to(deck) < 2.0:
				flying += 1
			else:
				_check(false, "dealt card left the flight band before moving (z %d)" % view.z_index)
	_check(flying == 14, "all 14 dealt cards wait on the deck in the flight band (%d)" % flying)

	yield(_advance(3.0), "completed")

	var settled = true
	for player in range(_game.rules.player_count()):
		var views = _hand_views(player)
		for i in range(views.size()):
			if views[i].z_index != DrawOrder.hand(i):
				settled = false
	_check(settled, "every dealt card settled into its hand band")
	yield(_wait(), "completed")


# A card thrown at the pile must clear every resting hand card on the way -
# with a big hand it used to fly under the rightmost cards.
func _test_played_card_above_hand() -> void:
	print("-- played card flies above the hand --")
	yield(_wait_for_player_turn(), "completed")
	if not _player_can_act():
		_check(true, "(skipped: the dealer never handed over a turn)")
		yield(_wait(), "completed")
		return

	_force_hand_size(18)
	_game._refresh_all()

	var legal = _game.rules.playable_cards(0)
	if legal.empty():
		_check(true, "(skipped: nothing playable)")
		yield(_wait(), "completed")
		return

	var hand_max = 0
	for view in _hand_views(0):
		hand_max = max(hand_max, view.z_index)
	var view = _game._views[legal[0].uid]
	_game._try_play(view)

	# Synchronous: the card is in the air, on top of everything at rest.
	_check(view.z_index == DrawOrder.FLYING,
		"the thrown card is in the flight band (z %d)" % view.z_index)
	_check(view.z_index > hand_max, "the thrown card clears the whole hand (max %d)" % hand_max)
	_check(view == _game._discard_views.back(), "the thrown card is the pile's newest card")

	yield(_advance(1.2), "completed")
	_check(not view.is_in_flight() and view.z_index >= DrawOrder.discard(1),
		"the thrown card settled onto the pile (z %d)" % view.z_index)
	var at_index = _game._discard_views.find(view)
	_check(at_index > 0 and _game._discard_views[at_index - 1].z_index < view.z_index,
		"the thrown card landed above the cards already on the pile")
	yield(_wait(), "completed")


# Hover and drag own their bands, and a layout refresh must not drop a hovered
# card back under its neighbours.
func _test_hover_drag_bands() -> void:
	print("-- hover and drag bands --")
	yield(_wait_for_player_turn(), "completed")
	if not _player_can_act():
		_check(true, "(skipped: the dealer never handed over a turn)")
		yield(_wait(), "completed")
		return

	var views = _hand_views(0)
	if views.empty():
		_check(true, "(skipped: empty hand)")
		yield(_wait(), "completed")
		return

	# All of the interaction changes are synchronous, so the whole sequence is
	# asserted without yielding a frame.
	var view = views[0]
	view.set_interactive(true)
	view._on_mouse_entered()
	_check(view.z_index == DrawOrder.HOVER, "hovered card lifts to z %d" % DrawOrder.HOVER)

	# The refresh that follows every event batch used to stomp the hover z.
	_game._refresh_all()
	_check(view._is_hovered and view.z_index == DrawOrder.HOVER,
		"a refresh during hover keeps the card above its neighbours")

	view._begin_drag()
	_check(view.z_index == DrawOrder.DRAG, "dragged card lifts to z %d" % DrawOrder.DRAG)
	view.cancel_drag()
	_check(view.z_index == DrawOrder.HOVER,
		"a cancelled drag returns the card to the hover band while still hovered (z %d)" % view.z_index)

	view._on_mouse_exited()
	_check(view.z_index == view.rest_z, "hover exit restores the resting depth")
	_check(view.rest_z >= DrawOrder.HANDS, "the resting depth is the hand band (z %d)" % view.rest_z)
	yield(_wait(), "completed")


# Even a pathological hand stays inside its band and cannot reach the flight,
# hover or drag bands above it.
func _test_big_hand_isolated() -> void:
	print("-- big hands stay in their band --")
	_force_hand_size(30)

	# Depth is applied synchronously by the layout, so no frame needs to pass
	# (and none may: an opponent acting mid-wait would redraw the hand).
	var views = _hand_views(0)
	var max_z = 0
	var in_band = true
	for i in range(views.size()):
		max_z = max(max_z, views[i].z_index)
		if views[i].z_index != DrawOrder.hand(i):
			in_band = false
	_check(in_band and views.size() == 30, "a 30-card hand occupies z %d..%d" % [
		DrawOrder.hand(0), max_z])
	_check(max_z < DrawOrder.FLYING, "the hand band never reaches the flight band")

	for pile_view in _game._discard_views:
		if is_instance_valid(pile_view):
			_check(pile_view.z_index <= DrawOrder.discard(DrawOrder.PILE_DEPTH),
				"pile depth stays capped at z %d" % DrawOrder.discard(DrawOrder.PILE_DEPTH))
			break
	yield(_wait(), "completed")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _player_can_act() -> bool:
	return _game.rules != null and _game.rules.round_active \
		and _game.rules.current_player == 0 \
		and not _game.rules.awaiting_color_choice \
		and not _game._busy


# Advance until the turn is the player's (or give up after a while). The deal
# reveal, AI turns and colour choices all resolve on their own timers.
func _wait_for_player_turn() -> void:
	# Always yields at least one frame so the caller can yield on the result.
	for _i in range(60):
		if _player_can_act():
			yield(self, "idle_frame")
			return
		if _game.rules == null or not _game.rules.round_active:
			_game._on_start_game()
		elif _game.rules.awaiting_color_choice and _game.rules.awaiting_color_player == 0:
			_game._on_color_selected(CardTypes.CardColor.BLUE)
		yield(_advance(0.3), "completed")


func _take_turn() -> void:
	var rules = _game.rules
	if rules.awaiting_color_choice:
		if rules.awaiting_color_player == 0:
			_game._on_color_selected(CardTypes.CardColor.BLUE)
		yield(_advance(0.4), "completed")
		return
	if rules.current_player != 0:
		yield(_advance(0.4), "completed")
		return
	var legal = rules.playable_cards(0)
	if legal.size() > 0:
		var card = legal[0]
		if _game._views.has(card.uid):
			_game._try_play(_game._views[card.uid])
			yield(_advance(0.5), "completed")
			return
	if rules.can_draw(0):
		_game._on_draw_pressed()
	elif rules.can_pass(0):
		_game._on_pass_pressed()
	yield(_advance(0.5), "completed")


# Grow (or shrink) the player's hand with synthetic cards, laid out exactly
# like a real deal, so band collisions can be tested at any size. Uids must
# never repeat: views are keyed by uid, and the game's Deck guarantees this
# for real cards.
var _synthetic_uid := 900000

func _force_hand_size(target: int) -> void:
	var CardData = load("res://Scripts/Core/CardData.gd")
	var rules = _game.rules
	while rules.hands[0].size() < target:
		_synthetic_uid += 1
		var card = CardData.new(CardTypes.CardColor.RED, CardTypes.CardValue.N1, _synthetic_uid)
		rules.hands[0].append(card)
		var view = _game._spawn_view(card, false)
		view.position = _game._anchor_for(0)
	_game._refresh_all()


# The ghost bugs (found by running): a hand card whose deal flight is
# interrupted was left with a frozen fade (alpha 0.0-0.35, i.e. invisible),
# and a rejection shake on a card still flying in stranded it in the flight
# band forever - floating above the fan and swallowing clicks meant for the
# cards beneath. Every interruption path must land the card: full pose,
# opacity and resting depth.
func _test_ghost_healing() -> void:
	print("-- interrupted flights heal --")
	yield(_wait_for_player_turn(), "completed")
	var views = _hand_views(0)
	if views.size() < 4:
		_force_hand_size(4)
		views = _hand_views(0)
	var view = views[0]
	var slot = _game._fan_slot(0, 0)
	var other = _game._fan_slot(0, 3)

	# The opening card's view belongs to the pile, not the hand registry - a
	# stale entry there would make a recycled redraw skip spawning a view.
	_check(_game._discard_views.size() >= 1
		and not _game._views.has(_game._discard_views[0].card_data.uid),
		"opening card is not in the hand view registry")

	# A rejection shake landing on a card mid-flight must land it afterwards:
	# settled, opaque, in its band, at its slot.
	view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], 0.0)
	_check(view.is_in_flight() and view.modulate.a < 0.05,
		"deal flight starts transparent in the flight band")
	view.shake_invalid()
	yield(_advance(1.5), "completed")
	_check(not view.is_in_flight(), "shaken card is no longer in flight")
	_check(abs(view.modulate.a - 1.0) < 0.01, "shaken card is fully opaque")
	_check(view.z_index == DrawOrder.hand(0), "shaken card rests in its band")
	_check(view.position.distance_to(slot["position"]) < 2.0, "shaken card sits at its slot")

	# A re-target mid-fade (the fan re-flows) must finish the interrupted
	# fade instead of landing a permanent ghost at the new slot.
	view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], 0.0)
	view.move_to(other["position"], other["rotation"], other["z"], true)
	_check(view.modulate.a < 0.05, "interrupted fade is still frozen mid-fade")
	yield(_advance(1.5), "completed")
	_check(abs(view.modulate.a - 1.0) < 0.01, "re-targeted card fades back in")
	_check(not view.is_in_flight() and view.z_index == other["z"],
		"re-targeted card settles into the new slot's band")
	_check(view.position.distance_to(other["position"]) < 2.0, "re-targeted card sits at the new slot")

	# A dead flight tween must never count as "en route": deferring to it
	# stranded the card in the flight band forever.
	view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], 0.0)
	if view._move_tween != null and view._move_tween.is_valid():
		view._move_tween.kill()
	_check(view.is_in_flight(), "killed flight still claims to be in flight")
	view.move_to(slot["position"], slot["rotation"], slot["z"], true)
	yield(_advance(1.5), "completed")
	_check(not view.is_in_flight() and abs(view.modulate.a - 1.0) < 0.01,
		"a dead tween does not defer the re-layout")
	_check(view.z_index == slot["z"], "the card re-lands in its resting band")

	# Hover traffic never lifts a flying card out of the flight band.
	view.deal_from(_game._deck_position(), slot["position"], slot["rotation"], slot["z"], 0.0)
	view._on_mouse_entered()
	_check(view.z_index == DrawOrder.FLYING, "hover does not lift a flying card to the hover band")
	view._on_mouse_exited()
	_check(view.z_index == DrawOrder.FLYING, "hover exit keeps a flying card in the flight band")
	yield(_advance(1.5), "completed")
	_check(not view.is_in_flight() and abs(view.modulate.a - 1.0) < 0.01
		and view.z_index == slot["z"],
		"the flight lands cleanly through hover traffic")

	# Restore the fan.
	_game._refresh_all()
	yield(_wait(), "completed")
