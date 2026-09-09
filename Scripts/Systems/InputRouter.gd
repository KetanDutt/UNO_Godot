extends Reference
# InputRouter
# -----------
# Turns raw input events into game actions, and owns the two-zone selection
# model that makes the whole game playable with nothing but a TV remote
# (Android TV / Fire TV: D-pad, Select, Back - no touch, no mouse, no hotkeys).
#
# Zones:
#   * HAND    - left/right moves the card selection, Enter plays it.
#   * BUTTONS - up/down (and left/right) cycle the action buttons, Enter
#               activates the focused one; up from the top button returns to
#               the hand.
#   Up or down from the hand switches to the buttons. Every gameplay action
#   (draw, pass, UNO, catch, sort, menu) is therefore reachable from the
#   D-pad alone, and the mouse and keyboard shortcuts keep working unchanged.
#
# Keyboard letters (D/P/U/C/S) and gamepad face buttons remain as shortcuts.
# Menus and the colour picker are not routed through here at all: they use the
# engine's own Control focus system (D-pad moves focus, Enter activates,
# Back goes back), which the remote maps to natively.
#
# The pattern mirrors EventPresenter / ReactionDirector: a Reference with a
# back-reference to the GameController that owns it.


enum UiZone { ZONE_HAND, ZONE_BUTTONS }

var _game = null

var _ui_zone: int = UiZone.ZONE_HAND
var _button_index: int = 0

# Analogue stick re-press locks: one event per deflection, not one per frame.
var _joy_axis_lock: int = 0
var _joy_axis_lock_y: int = 0


func _init(game) -> void:
	_game = game


func zone() -> int:
	return _ui_zone


func button_index() -> int:
	return _button_index


# Entry point for GameController._unhandled_input. Returns true when the event
# was consumed and should not reach anyone else.
func handle(event) -> bool:
	# Release the analogue stick locks when they return to centre.
	if event is InputEventJoypadMotion:
		if abs(event.axis_value) < 0.35:
			if event.axis == 0:
				_joy_axis_lock = 0
			elif event.axis == 1:
				_joy_axis_lock_y = 0
		return false

	if _is_cancel(event):
		_game._handle_cancel()
		return true

	if _game.menus.is_open() or _game.color_picker.is_open():
		return false
	if not _game._can_interact():
		return false

	if _is_left(event):
		if _ui_zone == UiZone.ZONE_HAND:
			_game._move_selection(-1)
		else:
			_cycle_buttons(-1)
	elif _is_right(event):
		if _ui_zone == UiZone.ZONE_HAND:
			_game._move_selection(1)
		else:
			_cycle_buttons(1)
	elif _is_up(event):
		if _ui_zone == UiZone.ZONE_HAND:
			enter_button_zone()
		else:
			_cycle_buttons(-1)
	elif _is_down(event):
		if _ui_zone == UiZone.ZONE_HAND:
			enter_button_zone()
		else:
			_cycle_buttons(1)
	elif _is_accept(event):
		if _ui_zone == UiZone.ZONE_HAND:
			_game._play_selected()
		else:
			_activate_focused_button()
	elif _is_key(event, KEY_D) or _is_pad(event, JOY_XBOX_X):
		_game._on_draw_pressed()
	elif _is_key(event, KEY_P) or _is_pad(event, JOY_XBOX_Y):
		_game._on_pass_pressed()
	elif _is_key(event, KEY_U) or _is_pad(event, JOY_R):
		_game._on_uno_pressed()
	elif _is_key(event, KEY_C):
		_game._on_catch_pressed()
	elif _is_key(event, KEY_S) or _is_pad(event, JOY_L):
		_game._on_sort_pressed()
	else:
		return false
	return true


# ---------------------------------------------------------------------------
# Zone model
# ---------------------------------------------------------------------------

func reset_to_hand() -> void:
	_ui_zone = UiZone.ZONE_HAND
	apply_button_selection()


func enter_button_zone() -> void:
	var count = _game.hud.get_buttons().size()
	for i in range(count):
		if _game.hud.is_button_selectable(i):
			_ui_zone = UiZone.ZONE_BUTTONS
			_button_index = i
			_game._play_cue("select", 1.0 + i * 0.02)
			_game.hud.set_button_selection(i)
			return


func _cycle_buttons(direction: int) -> void:
	var count = _game.hud.get_buttons().size()
	if count == 0:
		return
	# Up from the top button hands control back to the hand.
	if direction < 0 and _button_index <= 0:
		reset_to_hand()
		return
	var candidate = _button_index
	for _step in range(count):
		candidate = int(posmod(candidate + direction, count))
		if _game.hud.is_button_selectable(candidate):
			break
	_button_index = candidate
	_game._play_cue("select", 1.0 + _button_index * 0.02)
	_game.hud.set_button_selection(_button_index)


func _activate_focused_button() -> void:
	if not _game.hud.is_button_selectable(_button_index):
		apply_button_selection()
	if _ui_zone != UiZone.ZONE_BUTTONS:
		return
	match _button_index:
		0:
			_game._on_draw_pressed()
		1:
			_game._on_pass_pressed()
		2:
			_game._on_uno_pressed()
		3:
			_game._on_catch_pressed()
		4:
			_game._on_sort_pressed()
		5:
			_game._on_menu_pressed()


# Re-point the button selection after the enabled states change; a selection
# that no longer names a selectable button moves to the next one that does.
func apply_button_selection() -> void:
	if _game.hud == null:
		return
	if _ui_zone == UiZone.ZONE_HAND:
		_game.hud.set_button_selection(-1)
		return
	if _game.hud.is_button_selectable(_button_index):
		_game.hud.set_button_selection(_button_index)
		return
	var count = _game.hud.get_buttons().size()
	for step in range(1, count + 1):
		var candidate = int(posmod(_button_index + step, count))
		if _game.hud.is_button_selectable(candidate):
			_button_index = candidate
			_game.hud.set_button_selection(_button_index)
			return
	_ui_zone = UiZone.ZONE_HAND
	_game.hud.set_button_selection(-1)


# ---------------------------------------------------------------------------
# Event predicates
# ---------------------------------------------------------------------------

func _is_pressed(event) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return false


func _is_key(event, scancode: int) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.scancode == scancode


func _is_pad(event, button: int) -> bool:
	return event is InputEventJoypadButton and event.pressed and event.button_index == button


func _is_left(event) -> bool:
	if event is InputEventJoypadMotion:
		if event.axis == 0 and event.axis_value < -0.7 and _joy_axis_lock != -1:
			_joy_axis_lock = -1
			return true
		return false
	return _is_pressed(event) and event.is_action_pressed("ui_left")


func _is_right(event) -> bool:
	if event is InputEventJoypadMotion:
		if event.axis == 0 and event.axis_value > 0.7 and _joy_axis_lock != 1:
			_joy_axis_lock = 1
			return true
		return false
	return _is_pressed(event) and event.is_action_pressed("ui_right")


func _is_up(event) -> bool:
	if event is InputEventJoypadMotion:
		if event.axis == 1 and event.axis_value < -0.7 and _joy_axis_lock_y != -1:
			_joy_axis_lock_y = -1
			return true
		return false
	return _is_pressed(event) and event.is_action_pressed("ui_up")


func _is_down(event) -> bool:
	if event is InputEventJoypadMotion:
		if event.axis == 1 and event.axis_value > 0.7 and _joy_axis_lock_y != 1:
			_joy_axis_lock_y = 1
			return true
		return false
	return _is_pressed(event) and event.is_action_pressed("ui_down")


func _is_accept(event) -> bool:
	if not _is_pressed(event):
		return false
	if event.is_action_pressed("ui_accept"):
		return true
	if event is InputEventKey and event.scancode == KEY_SPACE:
		return true
	return event is InputEventJoypadButton and event.button_index == JOY_XBOX_A


func _is_cancel(event) -> bool:
	if not _is_pressed(event):
		return false
	if event is InputEventKey and event.scancode == KEY_ESCAPE:
		return true
	if event is InputEventJoypadButton:
		return event.button_index == JOY_XBOX_B or event.button_index == JOY_START
	return false
