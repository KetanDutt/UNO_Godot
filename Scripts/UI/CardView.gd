extends Node2D
# CardView
# --------
# Visual representation of a single card. Holds no game rules - it renders a
# CardData reference and reports intent (hover / press / drag) upward via signals.
#
# Rewritten from the original `Card.gd`, fixing several real problems:
#   * The old script created a `Tween` node per card and called `stop_all()`
#     from multiple handlers, so a hover during a layout tween could strand a
#     card mid-flight. Tweens are now tracked per-purpose and killed explicitly.
#   * Hover used `home_position` captured at `_ready()`, which was stale after
#     any re-layout, causing cards to drift.
#   * `raise()` on hover permanently reordered siblings and broke the fan's
#     z-order; z_index is now restored on exit.
#   * The face texture was assigned even while face-down, briefly leaking the
#     opponent's hand on the first frame.
#
# Presentation features: pseudo-3D flip (x-scale through zero), spring hover,
# drag-to-play, playable glow, disabled dimming, and a shadow that tracks lift.

signal card_pressed(view)
signal card_hovered(view)
signal card_unhovered(view)
signal drag_started(view)
signal drag_ended(view, global_pos)

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")

# The source art is 388x562. The rendered scale is supplied by TableLayout so
# cards shrink together with the rest of the composition on small windows.
const DEFAULT_SCALE = 0.34
const HOVER_SCALE_RATIO = 1.16
const DRAG_SCALE_RATIO = 1.24
const HOVER_LIFT_RATIO = -0.16   # of card height

const CARD_WIDTH = 388.0
const CARD_HEIGHT = 562.0

# Shadow offsets are in the sprite's local (unscaled) space.
const SHADOW_OFFSET = Vector2(14, 26)
const SHADOW_LIFT_OFFSET = Vector2(9, 30)

# Current rendered scale, set by set_card_scale().
var base_scale: float = DEFAULT_SCALE

var card_data = null
var face_down: bool = true
var interactive: bool = false
var playable: bool = false
var focused: bool = false

# Layout target written by TableLayout; hover and return-to-rest use this.
var rest_position: Vector2 = Vector2.ZERO
var rest_rotation: float = 0.0
var rest_z: int = 0

var _sprite: Sprite = null
var _shadow: Sprite = null
var _glow: Sprite = null
var _area: Area2D = null
var _collision: CollisionShape2D = null

var _hover_tween = null
var _move_tween = null
var _flip_tween = null
var _pulse_tween = null

var _is_hovered: bool = false
var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _drag_ready: bool = false
var _press_position: Vector2 = Vector2.ZERO

var settings = null
var _front_texture: Texture = null
var _back_texture: Texture = null

# Drag must exceed this many pixels before it counts as a drag rather than a tap.
const DRAG_THRESHOLD = 14.0


func _ready() -> void:
	_build_nodes()
	set_process_input(false)


# --- scale helpers ---------------------------------------------------------
func _base() -> Vector2:
	return Vector2(base_scale, base_scale)


func _hover() -> Vector2:
	return _base() * HOVER_SCALE_RATIO


func _drag() -> Vector2:
	return _base() * DRAG_SCALE_RATIO


func _lift() -> Vector2:
	return Vector2(0, CARD_HEIGHT * base_scale * HOVER_LIFT_RATIO)


# Set the rendered card scale. Applied immediately unless the card is mid-hover
# or mid-drag, where the current interaction scale takes precedence.
func set_card_scale(value: float) -> void:
	if abs(base_scale - value) < 0.0001:
		return
	base_scale = value
	if _is_dragging:
		scale = _drag()
	elif _is_hovered:
		scale = _hover()
	else:
		scale = _base()


func _build_nodes() -> void:
	_shadow = Sprite.new()
	_shadow.name = "Shadow"
	_shadow.modulate = Color(0, 0, 0, 0.36)
	_shadow.position = SHADOW_OFFSET
	_shadow.z_index = -1
	add_child(_shadow)

	_glow = Sprite.new()
	_glow.name = "Glow"
	_glow.modulate = Color(1, 1, 1, 0)
	_glow.scale = Vector2(1.09, 1.07)
	_glow.z_index = -1
	add_child(_glow)

	_sprite = Sprite.new()
	_sprite.name = "Face"
	add_child(_sprite)

	_area = Area2D.new()
	_area.name = "Hitbox"
	# Input is only picked up when this card is interactive (see set_interactive).
	_area.input_pickable = false
	add_child(_area)

	_collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.extents = Vector2(CARD_WIDTH * 0.5, CARD_HEIGHT * 0.5)
	_collision.shape = shape
	_area.add_child(_collision)

	_area.connect("input_event", self, "_on_area_input")
	_area.connect("mouse_entered", self, "_on_mouse_entered")
	_area.connect("mouse_exited", self, "_on_mouse_exited")

	scale = _base()


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
func setup(data, front: Texture, back: Texture, is_face_down: bool, settings_ref = null) -> void:
	card_data = data
	_front_texture = front
	_back_texture = back
	face_down = is_face_down
	settings = settings_ref

	# Assign only the currently visible texture so a face-down card can never
	# flash its face for a frame.
	var texture = _back_texture if face_down else _front_texture
	_sprite.texture = texture
	_shadow.texture = texture
	_glow.texture = texture
	_sprite.scale = Vector2.ONE
	scale = _base()
	modulate = Color(1, 1, 1, 1)
	_update_tint()


func _anim(duration: float) -> float:
	if settings != null:
		return settings.anim_scale(duration)
	return duration


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
func set_interactive(value: bool) -> void:
	interactive = value
	# Toggling pickability is far cheaper than leaving every card in the physics
	# broadphase and filtering in the handler.
	_area.input_pickable = value
	if not value and _is_hovered:
		_is_hovered = false
		_return_to_rest()


func set_playable(value: bool) -> void:
	if playable == value:
		return
	playable = value
	_update_tint()
	_update_glow()


func set_focused(value: bool) -> void:
	if focused == value:
		return
	focused = value
	_update_glow()
	if focused:
		_bump()


func _update_tint() -> void:
	if face_down:
		_sprite.modulate = Color(1, 1, 1, 1)
		return
	if interactive and not playable:
		# Dim illegal cards so the legal ones read instantly.
		_sprite.modulate = Color(0.62, 0.64, 0.70, 1)
	else:
		_sprite.modulate = Color(1, 1, 1, 1)


func _update_glow() -> void:
	if _glow == null:
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null

	var show_glow = playable and interactive
	if not show_glow and not focused:
		var fade = create_tween()
		fade.tween_property(_glow, "modulate:a", 0.0, _anim(0.16))
		return

	var tint = CardTypes.color_value(card_data.effective_color()) if card_data != null else Color.white
	if focused:
		tint = Color(1.0, 0.86, 0.35)
	tint.a = 0.0
	_glow.modulate = tint

	var peak = 0.85 if focused else 0.5
	# Gentle breathing pulse marks the cards you can actually play.
	_pulse_tween = create_tween()
	_pulse_tween.set_loops()
	_pulse_tween.tween_property(_glow, "modulate:a", peak, _anim(0.55)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_pulse_tween.tween_property(_glow, "modulate:a", peak * 0.35, _anim(0.55)) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
# Move to a new resting place. When `animated` is false the card snaps (used on
# window resize so nothing appears to slide around).
func move_to(target: Vector2, target_rotation: float, z: int,
		animated: bool = true, delay: float = 0.0) -> void:
	rest_position = target
	rest_rotation = target_rotation
	rest_z = z
	z_index = z

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	if not animated:
		position = target
		rotation_degrees = target_rotation
		return

	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	var duration = _anim(0.34)
	_move_tween.tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	_move_tween.tween_property(self, "rotation_degrees", target_rotation, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	if not _is_hovered:
		_move_tween.tween_property(self, "scale", _base(), duration * 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)


# Arc a card from the deck into the hand - a straight lerp looks lifeless.
func deal_from(origin: Vector2, target: Vector2, target_rotation: float, z: int, delay: float) -> void:
	rest_position = target
	rest_rotation = target_rotation
	rest_z = z
	z_index = z
	position = origin
	rotation_degrees = rand_range(-25, 25)
	scale = _base() * 0.75
	modulate.a = 0.0

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	var duration = _anim(0.42)
	_move_tween = create_tween()
	_move_tween.tween_interval(delay)
	_move_tween.chain()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "rotation_degrees", target_rotation, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "scale", _base(), duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "modulate:a", 1.0, duration * 0.5)


# Fly to the discard pile with a small overshoot and settle.
func play_to(target: Vector2, target_rotation: float, z: int,
		on_complete_target = null, on_complete_method: String = "") -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null

	_glow.modulate.a = 0.0
	z_index = z
	set_interactive(false)

	var duration = _anim(0.36)
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "rotation_degrees", target_rotation, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Lift then settle sells the "throw" onto the pile.
	_move_tween.tween_property(self, "scale", _base() * 1.16, duration * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.chain().tween_property(self, "scale", _base(), duration * 0.5) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if on_complete_target != null and on_complete_method != "":
		_move_tween.chain().tween_callback(on_complete_target, on_complete_method, [self])


# Fly off toward a hand and free the node - used when a card leaves the table.
func fly_out(target: Vector2) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var duration = _anim(0.3)
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "position", target, duration).set_trans(Tween.TRANS_CUBIC)
	_move_tween.tween_property(self, "scale", _base() * 0.4, duration)
	_move_tween.tween_property(self, "modulate:a", 0.0, duration)
	_move_tween.chain().tween_callback(self, "queue_free")


# ---------------------------------------------------------------------------
# Flip
# ---------------------------------------------------------------------------
# Pseudo-3D flip: squash horizontally to zero, swap the texture at the midpoint,
# then expand again.
func flip_to(show_face: bool, duration: float = 0.34) -> void:
	if face_down != show_face:
		# Already showing the requested side.
		if (show_face and not face_down) or (not show_face and face_down):
			return

	if _flip_tween != null and _flip_tween.is_valid():
		_flip_tween.kill()

	var scaled = _anim(duration)
	_flip_tween = create_tween()
	_flip_tween.tween_property(_sprite, "scale:x", 0.0, scaled * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_flip_tween.tween_callback(self, "_swap_face", [show_face])
	_flip_tween.tween_property(_sprite, "scale:x", 1.0, scaled * 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _swap_face(show_face: bool) -> void:
	face_down = not show_face
	var texture = _front_texture if show_face else _back_texture
	_sprite.texture = texture
	_shadow.texture = texture
	_glow.texture = texture
	_update_tint()


func set_face_immediate(show_face: bool) -> void:
	_swap_face(show_face)
	_sprite.scale.x = 1.0


# ---------------------------------------------------------------------------
# Feedback animations
# ---------------------------------------------------------------------------
func shake_invalid() -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	var origin = rest_position
	var duration = _anim(0.055)
	_move_tween = create_tween()
	for i in range(3):
		var amount = 13.0 - i * 3.5
		_move_tween.tween_property(self, "position:x", origin.x - amount, duration) \
			.set_trans(Tween.TRANS_SINE)
		_move_tween.tween_property(self, "position:x", origin.x + amount, duration) \
			.set_trans(Tween.TRANS_SINE)
	_move_tween.tween_property(self, "position:x", origin.x, duration).set_trans(Tween.TRANS_SINE)

	# Flash red so the rejection reads even with sound off.
	var flash = create_tween()
	flash.tween_property(_sprite, "modulate", Color(1.4, 0.45, 0.45, 1), _anim(0.08))
	flash.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), _anim(0.22))


func _bump() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", _base() * 1.08, _anim(0.09)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _base(), _anim(0.13)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# Celebratory spin, used on the winning card.
func celebrate() -> void:
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "rotation_degrees", rotation_degrees + 360.0, _anim(0.7)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", _base() * 1.3, _anim(0.35)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", _base(), _anim(0.35)) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)


# ---------------------------------------------------------------------------
# Hover / input
# ---------------------------------------------------------------------------
func _on_mouse_entered() -> void:
	if not interactive or _is_dragging:
		return
	_is_hovered = true
	emit_signal("card_hovered", self)
	_apply_hover(true)


func _on_mouse_exited() -> void:
	if not _is_hovered:
		return
	_is_hovered = false
	emit_signal("card_unhovered", self)
	if not _is_dragging:
		_return_to_rest()


func _apply_hover(active: bool) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	# Lift above neighbours while hovered, then restore the fan order on exit.
	z_index = rest_z + (60 if active else 0)

	var target_position = rest_position + (_lift() if active else Vector2.ZERO)
	var target_scale = _hover() if active else _base()
	var target_rotation = 0.0 if active else rest_rotation

	_hover_tween = create_tween()
	_hover_tween.set_parallel(true)
	var duration = _anim(0.16)
	_hover_tween.tween_property(self, "position", target_position, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "scale", target_scale, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(self, "rotation_degrees", target_rotation, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# The shadow drops further away as the card lifts.
	_hover_tween.tween_property(_shadow, "position",
		SHADOW_OFFSET + (SHADOW_LIFT_OFFSET if active else Vector2.ZERO), duration)


func _return_to_rest() -> void:
	_apply_hover(false)


func _on_area_input(_viewport, event, _shape_idx) -> void:
	if not interactive:
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed:
			_drag_ready = true
			_press_position = get_global_mouse_position()
			_drag_offset = position - get_global_mouse_position()
			set_process_input(true)
		# Release is handled in _input so a drag that ends off the card still works.


func _input(event) -> void:
	if not _drag_ready:
		return

	if event is InputEventMouseMotion:
		var distance = get_global_mouse_position().distance_to(_press_position)
		if not _is_dragging and distance > DRAG_THRESHOLD:
			_begin_drag()
		if _is_dragging:
			position = get_global_mouse_position() + _drag_offset
			# Tilt into the direction of travel for a physical feel.
			rotation_degrees = clamp(event.relative.x * 0.7, -18, 18)

	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
		var was_dragging = _is_dragging
		_drag_ready = false
		set_process_input(false)
		if was_dragging:
			_is_dragging = false
			emit_signal("drag_ended", self, get_global_mouse_position())
		else:
			emit_signal("card_pressed", self)


func _begin_drag() -> void:
	_is_dragging = true
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	z_index = rest_z + 200
	var tween = create_tween()
	tween.tween_property(self, "scale", _drag(), _anim(0.12)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	emit_signal("drag_started", self)


# Called by the controller when a drag did not land on a valid drop target.
func cancel_drag() -> void:
	_is_dragging = false
	_drag_ready = false
	set_process_input(false)
	move_to(rest_position, rest_rotation, rest_z, true)


func is_dragging() -> bool:
	return _is_dragging
