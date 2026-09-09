extends Reference
# ReactionDirector
# ----------------
# Delayed opponent reactions, on real timers, so the table feels alive:
#
#   * A missed UNO call is punished after a fair window (Easy ~2.2s, Hard
#     ~1.0s, scaled by the animation-speed setting) rather than instantly.
#     That window is exactly when a player can still press UNO! to self-call.
#   * Under the jump-in house rule, an opponent holding an exact twin of the
#     top card can slap it down out of turn, after a human-scale reaction
#     delay - which the human can always beat by simply clicking first.
#
# Both reactions are *armed* when the rules state makes them possible and
# *validated again* when they fire, because the state may have changed in
# between (the target self-called, another card covered the pile, the round
# ended, the table was cleared). Tokens invalidate anything armed by an older
# match or round.
#
# The pattern mirrors EventPresenter: a Reference with a back-reference to the
# GameController that owns it. It may read rules state and call the
# controller's dispatchers; the rules engine stays authoritative.

var _game = null

var _catch_armed: Dictionary = {}
var _catch_token: int = 0
var _jump_in_armed: Dictionary = {}
var _jump_token: int = 0


func _init(game) -> void:
	_game = game


# Drop every armed reaction. Called whenever the table is cleared (new match,
# next round, exit to menu); a firing timer then retires on its token check.
func invalidate() -> void:
	_catch_token += 1
	_jump_token += 1
	_catch_armed.clear()
	_jump_in_armed.clear()


# Called after every event batch: arm whatever the current rules state makes
# possible. Cheap (a few array scans) and idempotent per seat.
func evaluate() -> void:
	_evaluate_catch_windows()
	_evaluate_jump_in_windows()


# ---------------------------------------------------------------------------
# UNO catch windows
# ---------------------------------------------------------------------------
# Arm a catch for every currently-vulnerable seat that has none scheduled yet.
func _evaluate_catch_windows() -> void:
	var rules = _game.rules
	if rules == null or not rules.round_active:
		return
	for seat in range(rules.player_count()):
		if rules.uno_vulnerable[seat] and not _catch_armed.has(seat):
			_schedule_ai_catch(seat)


# The AI seat that would catch `target`: the next opponent in turn order after
# them. Returns -1 when only the human could do the catching.
func _catcher_for(target: int) -> int:
	var rules = _game.rules
	var count = rules.player_count()
	for step in range(1, count):
		var seat = int(posmod(target + rules.direction * step, count))
		if seat != 0 and seat != target:
			return seat
	return -1


func _schedule_ai_catch(target: int) -> void:
	var catcher = _catcher_for(target)
	if catcher < 0:
		# Only the human can punish this one; the CATCH button appears on its
		# own through the HUD refresh.
		return
	var ai = _game._ai_for(catcher)
	if not ai.should_catch_uno():
		# This opponent was not paying attention. The seat stays catchable by
		# the human, and may be re-armed later by another play.
		return
	_catch_armed[target] = true
	var token = _catch_token
	var delay = _game.settings.anim_scale(ai.catch_delay())
	# Gameplay timers pause with the tree, so a pause menu freezes the table.
	var timer = _game.get_tree().create_timer(delay, false)
	timer.connect("timeout", self, "_ai_catch_fire", [target, catcher, token])


func _ai_catch_fire(target: int, catcher: int, token: int) -> void:
	_catch_armed.erase(target)
	if token != _catch_token or _game.rules == null or not _game.rules.round_active:
		return
	# The window may have been used well: the target self-called, drew cards,
	# or the round already ended.
	if not _game.rules.uno_vulnerable[target] or catcher == target:
		return
	_game.rules.catch_uno(catcher, target)
	_game._process_events(_game.rules.consume_events())


# ---------------------------------------------------------------------------
# AI jump-ins
# ---------------------------------------------------------------------------
# Arm an AI jump-in whenever the top card has an exact twin in an opponent's
# hand. While the human is the one deciding, the opening is left to them -
# opponents react to plays, never to hesitation.
func _evaluate_jump_in_windows() -> void:
	var rules = _game.rules
	if rules == null or not rules.round_active or not rules.rules.jump_in:
		return
	if rules.awaiting_color_choice or rules.pending_draw > 0:
		return
	if rules.current_player == 0 and not _game._busy:
		return
	for seat in range(1, rules.player_count()):
		if _jump_in_armed.has(seat) or rules.current_player == seat:
			continue
		var ai = _game._ai_for(seat)
		if rules.jump_in_cards(seat).empty() or not ai.should_jump_in():
			continue
		_jump_in_armed[seat] = true
		var token = _jump_token
		var delay = _game.settings.anim_scale(ai.jump_in_delay())
		var timer = _game.get_tree().create_timer(delay, false)
		timer.connect("timeout", self, "_ai_jump_in_fire", [seat, token])


func _ai_jump_in_fire(seat: int, token: int) -> void:
	_jump_in_armed.erase(seat)
	var rules = _game.rules
	if token != _jump_token or rules == null or not rules.round_active:
		return
	if rules.awaiting_color_choice or rules.pending_draw > 0:
		return
	var cards = rules.jump_in_cards(seat)
	if cards.empty():
		return
	var ai = _game._ai_for(seat)
	var card = cards[0]
	# Declare UNO before dropping to a single card.
	if rules.hands[seat].size() == 2 and ai.should_call_uno():
		rules.call_uno(seat)
	rules.play_card(seat, card)
	_game._process_events(rules.consume_events())
	_game._busy = false
	_game._begin_turn()
