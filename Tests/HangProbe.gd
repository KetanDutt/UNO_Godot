extends SceneTree

# Hang reproducer (development aid).
#
#   timeout 900 godot --no-window -s Tests/HangProbe.gd -- --opponents=1 --anim=1.0 --rules=all
#
# Boots the real game and plays like a user through the REAL input path:
# hover (mouse_entered), press + release events routed through the card's own
# input handlers (which emit card_pressed -> _on_card_pressed -> _try_play),
# occasional drags dropped on the pile, UNO calls, draws and passes.
#
# Three hang signatures are watched for:
#
#   A) _can_act() false for a long stretch with no picker/menu/round-end
#      anywhere in sight - the game state itself is wedged.
#   B) _can_act() true but every card view is left non-interactive, so real
#      mouse clicks would hit nothing.
#   C) The hand is visually stranded: a card sits far from its fan slot, is
#      invisible/transparent, or is stuck "in flight" for seconds - the user
#      sees a dead table even though the state machine is fine. The resume
#      path's _layout_hands() would repair exactly this.
#
# On detecting any, dumps the game state and then performs the user's reported
# workaround (menu button, then resume) to confirm it recovers.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")

var _game = null

var _player_plays := 0
var _rounds := 0
var _hangs := 0
var _clicks := 0
var _drags := 0

var _stuck_a := 0.0
var _stuck_b := 0.0
var _stuck_c := 0.0
var _stuck_c_reason := ""
var _progress := ""

var _opponents := 1
var _anim := 1.0
var _use_drags := true
var _fps := 60
var _dwell := false
var _misclicks_since_play := 0


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var scene = load("res://Scenes/Gameplay.tscn")
	var instance = scene.instance()
	get_root().add_child(instance)
	_game = instance

	yield(self, "idle_frame")
	yield(self, "idle_frame")

	_opponents = int(_cli("opponents", "1"))
	_anim = float(_cli("anim", "1.0"))
	_use_drags = bool(int(_cli("drags", "1")))
	_fps = int(_cli("fps", "60"))
	_dwell = bool(int(_cli("dwell", "1")))

	_game.settings.opponent_count = _opponents
	_game.settings.animation_speed = _anim
	_game.settings.show_hints = true

	var rules = _cli("rules", "none")
	_game.settings.rule_stacking = rules == "all" or rules == "stacking"
	_game.settings.rule_draw_until_playable = rules == "all" or rules == "drawtill"
	_game.settings.rule_seven_zero = rules == "all" or rules == "seveno"
	_game.settings.rule_force_play = rules == "all" or rules == "force"

	if _fps > 0:
		Engine.target_fps = _fps

	_game._on_start_game()
	yield(_advance(2.0), "completed")

	for _match in range(8):
		var result = yield(_play_until_hang(150.0), "completed")
		if result == "HANG":
			break
		if result == "ROUND_OVER":
			_game._on_restart_game()
			yield(_advance(2.0), "completed")
			_rounds += 1

	var ruleset = _cli("rules", "none")
	print("\nRESULT: hangs=%d player_plays=%d clicks=%d drags=%d rounds=%d"
		% [_hangs, _player_plays, _clicks, _drags, _rounds])
	print("cfg: %d opponents, %.1f anim, %s rules, %d fps"
		% [_opponents, _anim, ruleset, _fps])
	quit()


# ---------------------------------------------------------------------------


func _play_until_hang(budget: float) -> String:
	var elapsed := 0.0
	var last_round_active := true

	while elapsed < budget:
		yield(_advance(0.1), "completed")
		elapsed += 0.1

		if _game.rules == null:
			return "ROUND_OVER"

		if not _game.rules.round_active:
			if last_round_active:
				print("t=%.1f  round ended (player plays so far: %d)" % [elapsed, _player_plays])
			last_round_active = false
			yield(_advance(3.0), "completed")
			return "ROUND_OVER"
		last_round_active = true

		# Signature A: the game makes NO progress at all - same current player,
		# same pile, same hand sizes - for a long stretch with nothing
		# legitimately blocking (no picker, no menus, round alive). Long AI
		# turn chains are fine as long as the state keeps moving.
		var progress = _progress_fingerprint()
		if progress != _progress:
			_progress = progress
			_stuck_a = 0.0
		elif not _game.menus.is_open() and not _game.color_picker.is_open():
			_stuck_a += 0.1
		else:
			_stuck_a = 0.0

		# Signature B: the state says the player may act, but the views were
		# never switched back to interactive, so clicks hit nothing.
		if _can_act_probe() and _interactive_view_count() == 0 \
				and _game.rules.hands[0].size() > 0:
			_stuck_b += 0.1
		else:
			_stuck_b = 0.0

		# Signature C: hand cards visually stranded off their fan slots.
		var strand = _strand_check()
		if strand != "":
			if strand != _stuck_c_reason:
				_stuck_c_reason = strand
				_stuck_c = 0.0
			_stuck_c += 0.1
		else:
			_stuck_c = 0.0
			_stuck_c_reason = ""

		if _stuck_a > 0.55 and fmod(_stuck_a, 0.5) < 0.051:
			_state_line(elapsed)
		if _stuck_c > 0.05 and fmod(_stuck_c, 0.5) < 0.051:
			_state_line(elapsed)
			print("    strand: %s" % _stuck_c_reason)

		if _stuck_a >= 8.0 or _stuck_b >= 1.5 or _stuck_c >= 2.0:
			_hangs += 1
			_dump_state(elapsed)
			var recovered = yield(_try_menu_resume_workaround(), "completed")
			print("workaround (menu -> resume) recovered: %s" % recovered)
			if _stuck_a >= 8.0 and not recovered:
				return "HANG"
			_stuck_a = 0.0
			_stuck_b = 0.0
			_stuck_c = 0.0
			_stuck_c_reason = ""
			continue

		# Drive the game like a player.
		if _game.color_picker.is_open():
			var counts = _game.rules.color_counts(0)
			var best = 0
			for color in CardTypes.PLAYABLE_COLORS:
				if counts[color] > counts[best]:
					best = color
			_game._on_color_selected(best)
			continue

		if _can_act_probe():
			# Users misclick - and the classic misclick is on the card they
			# just drew, while it is still flying in (shake_invalid kills that
			# flight). Try an unplayable card every few actions, preferring
			# one that is still in transit.
			_misclicks_since_play += 1
			if _misclicks_since_play >= 3:
				_misclicks_since_play = 0
				var victim = _pick_misclick_victim()
				if victim != null:
					yield(_click_card(victim), "completed")
					continue

			var legal = _game.rules.playable_cards(0)
			var chosen = null
			for card in legal:
				if not card.is_wild():
					chosen = card
					break
			if chosen == null and legal.size() > 0:
				chosen = legal[0]
			if chosen != null and _game._views.has(chosen.uid) \
					and is_instance_valid(_game._views[chosen.uid]):
				if _use_drags and _player_plays % 3 == 2:
					yield(_drag_card_to_pile(_game._views[chosen.uid]), "completed")
				else:
					yield(_click_card(_game._views[chosen.uid]), "completed")
				_player_plays += 1
				_misclicks_since_play = 0
				# Humans dwell between moves; races love a slow hand.
				if _dwell and _player_plays % 4 == 3:
					yield(_advance(2.0), "completed")
			elif _game.rules.can_draw(0):
				_game._on_draw_pressed()
			elif _game.rules.can_pass(0):
				_game._on_pass_pressed()
			continue

		# Not the player's turn: the AI dispatcher owns the flow.

	return "BUDGET"


# ---------------------------------------------------------------------------


# Returns a reason string if any hand card is far from its fan slot, hidden,
# transparent, or perpetually in flight; "" when everything sits where the
# user could see and click it.
func _strand_check() -> String:
	for seat in range(_game.rules.player_count()):
		var hand = _game.rules.hands[seat]
		for i in range(hand.size()):
			var card = hand[i]
			if not _game._views.has(card.uid):
				return "seat %d card %d has no view" % [seat, i]
			var view = _game._views[card.uid]
			if not is_instance_valid(view):
				return "seat %d card %d view is dead" % [seat, i]
			if not view.visible:
				return "seat %d card %d invisible" % [seat, i]
			if view.modulate.a < 0.35:
				return "seat %d card %d alpha %.2f" % [seat, i, view.modulate.a]
			var slot = _game._fan_slot(seat, i)
			var drift = view.position.distance_to(slot["position"])
			if drift > 90.0:
				return "seat %d card %d off-slot by %.0f px (in_flight=%s)" \
					% [seat, i, drift, view.is_in_flight()]
			# A hand card parked in the flight band floats above the whole fan
			# and swallows clicks meant for the cards beneath it.
			if view.is_in_flight() and drift <= 90.0:
				return "seat %d card %d stuck in flight at its slot (z=%d)" \
					% [seat, i, view.z_index]
	return ""


# Hover, press, release - exactly what a mouse click does, through the card's
# own handlers so the full card_pressed -> _on_card_pressed -> _try_play path runs.
func _click_card(view) -> void:
	if view.interactive:
		view._on_mouse_entered()
		yield(_advance(0.09), "completed")
	var press = InputEventMouseButton.new()
	press.button_index = BUTTON_LEFT
	press.pressed = true
	view._on_area_input(null, press, 0)
	yield(_advance(0.05), "completed")
	var release = InputEventMouseButton.new()
	release.button_index = BUTTON_LEFT
	release.pressed = false
	view._input(release)
	_clicks += 1
	if is_instance_valid(view):
		view._on_mouse_exited()


# Hover, press, drag, drop on the pile - the release-side of the drag path.
func _drag_card_to_pile(view) -> void:
	if view.interactive:
		view._on_mouse_entered()
		yield(_advance(0.09), "completed")
	var press = InputEventMouseButton.new()
	press.button_index = BUTTON_LEFT
	press.pressed = true
	view._on_area_input(null, press, 0)
	yield(_advance(0.05), "completed")
	view._begin_drag()
	yield(_advance(0.07), "completed")
	view._is_dragging = false
	view._drag_ready = false
	view.set_process_input(false)
	view.emit_signal("drag_ended", view, _game._discard_position())
	_drags += 1
	if is_instance_valid(view):
		view._on_mouse_exited()


func _try_menu_resume_workaround():
	print("\n--- performing user workaround: MENU button, then RESUME ---")
	_game._on_menu_pressed()
	yield(_advance(0.5), "completed")
	print("  menu open: %s screen: %s paused: %s"
		% [_game.menus.is_open(), _game.menus.current_screen, paused])
	_game._on_resume_game()
	yield(_advance(1.5), "completed")

	# After resuming, the user's mouse travels back across their cards -
	# hover enter/exit traffic. Mirror it.
	for card in _game.rules.hands[0]:
		if _game._views.has(card.uid) and is_instance_valid(_game._views[card.uid]):
			var view = _game._views[card.uid]
			if view.interactive:
				view._on_mouse_entered()
				yield(_advance(0.05), "completed")
				view._on_mouse_exited()

	for _i in range(20):
		if _game.rules == null or not _game.rules.round_active:
			return false
		if _can_act_probe() and _interactive_view_count() > 0 and _strand_check() == "":
			return true
		if _game.color_picker.is_open():
			return true
		if _game.rules.current_player != 0 and not _game._busy:
			return true
		yield(_advance(0.25), "completed")
	return false


# The classic misclick: the card you just drew, still flying in from the
# deck, that turns out not to be playable. Falls back to any unplayable card.
func _pick_misclick_victim():
	var fallback = null
	var hand = _game.rules.hands[0]
	for i in range(hand.size() - 1, -1, -1):
		var card = hand[i]
		if _game.rules.is_playable(card):
			continue
		if not _game._views.has(card.uid):
			continue
		var view = _game._views[card.uid]
		if not is_instance_valid(view):
			continue
		if view.is_in_flight():
			return view
		if fallback == null:
			fallback = view
	return fallback


func _progress_fingerprint() -> String:
	var hands := 0
	for i in range(_game.rules.player_count()):
		hands = hands * 31 + _game.rules.hands[i].size()
	return "%d/%d/%d" % [_game.rules.current_player,
		_game.rules.deck.discard_count(), hands]


func _can_act_probe() -> bool:
	return _game.rules != null and _game.rules.round_active and not _game._busy \
		and _game.rules.current_player == 0 \
		and not _game.rules.awaiting_color_choice \
		and not _game.menus.is_open() and not _game.color_picker.is_open()


func _interactive_view_count() -> int:
	var count := 0
	for card in _game.rules.hands[0]:
		if _game._views.has(card.uid):
			var view = _game._views[card.uid]
			if is_instance_valid(view) and view.interactive:
				count += 1
	return count


func _in_flight_count() -> int:
	var count := 0
	for uid in _game._views:
		var view = _game._views[uid]
		if is_instance_valid(view) and view.is_in_flight():
			count += 1
	return count


func _state_line(t: float) -> void:
	print("  t=%.1f busy=%s cur=%d await=%s picker=%s menus=%s paused=%s interactive=%d" % [
		t, _game._busy, _game.rules.current_player, _game.rules.awaiting_color_choice,
		_game.color_picker.is_open(), _game.menus.is_open(), paused,
		_interactive_view_count()])


func _dump_state(t: float) -> void:
	print("\n================ HANG ================")
	_state_line(t)
	print("  player plays: %d   rounds: %d   clicks: %d  drags: %d" % [_player_plays, _rounds, _clicks, _drags])
	print("  hand size: %d   pile views: %d   deck: %d" % [
		_game.rules.hands[0].size(), _game._discard_views.size(),
		_game.rules.deck.draw_count()])
	print("  in-flight views: %d   strand: %s" % [_in_flight_count(), _stuck_c_reason])
	print("  pending_draw: %d   selected_index: %d" % [
		_game.rules.pending_draw, _game._selected_index])
	print("  turn watchdog: %.2f" % _game._turn_watchdog)
	print("  menus.current_screen: %s" % _game.menus.current_screen)
	for i in range(_game.rules.player_count()):
		print("  seat %d: %d cards" % [i, _game.rules.hands[i].size()])
	print("====================================================")


func _cli(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--" + key + "="):
			return arg.substr(key.length() + 3)
	return fallback


func _advance(seconds: float) -> void:
	var deadline = OS.get_ticks_msec() + int(seconds * 1000.0)
	yield(self, "idle_frame")
	while OS.get_ticks_msec() < deadline:
		yield(self, "idle_frame")
