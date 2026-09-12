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
# Depth: every resting card sits in its DrawOrder band (deck, discard, hands).
# While a card is in transit - dealt, drawn, played, or leaving the table - it
# flies in the DrawOrder.FLYING band above every resting card, and settles
# into its resting band only when the flight completes. Hover and drag lift
# the card into their own bands without disturbing its resting depth.
#
# Presentation features: pseudo-3D flip (x-scale through zero), spring hover,
# drag-to-play, playable glow, disabled dimming, and a shadow that tracks lift.

signal card_pressed(view)
signal card_hovered(view)
signal card_unhovered(view)
signal drag_started(view)
signal drag_ended(view, global_pos)

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")

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

# Cards on the discard pile rest at the pile centre plus this hand-stacked
# jitter. It is stored so a window resize can re-place the pile without
# snapping every card to the exact same spot.
var discard_offset: Vector2 = Vector2.ZERO

# True between the start of a deal/draw/play flight and the moment it lands.
# While set, the card draws in the DrawOrder.FLYING band (see _settle).
var _in_flight: bool = false

var _sprite: Sprite = null
var _shadow: Sprite = null
var _glow: Sprite = null
var _area: Area2D = null
var _collision: CollisionShape2D = null

var _hover_tween = null
var _move_tween = null
var _flip_tween = null
var _pulse_tween = null
var _glow_fade_tween = null

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
	var changed = interactive != value
	interactive = value
	# Toggling pickability is far cheaper than leaving every card in the physics
	# broadphase and filtering in the handler.
	_area.input_pickable = value
	if changed:
		# A card leaving the hand (it just landed on the discard pile) must
		# shed the illegal-card dimming it wore in the fan, otherwise the
		# cards on the centre pile stay grey while face-down opponents do not.
		_update_tint()
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
	if _glow_fade_tween != null and _glow_fade_tween.is_valid():
		# An in-flight fade-out would otherwise land its final alpha on top of
		# a freshly started pulse.
		_glow_fade_tween.kill()
		_glow_fade_tween = null

	var show_glow = playable and interactive
	if not show_glow and not focused:
		_glow_fade_tween = create_tween()
		_glow_fade_tween.tween_property(_glow, "modulate:a", 0.0, _anim(0.16))
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
# The z a card should show while it is parked at its resting place: the hover
# band when lifted, otherwise its resting band.
func _hover_or_rest_z() -> int:
	if _is_hovered and not _in_flight:
		return DrawOrder.HOVER
	if _in_flight:
		# Hover does not lift a flying card out of the flight band.
		return DrawOrder.FLYING
	return rest_z


# Called when a flight completes: leave the flight band and settle into the
# resting (or hover) band.
func _settle() -> void:
	_in_flight = false
	# Whatever owned this card on the way in, a landed card is fully opaque -
	# an interrupted fade-in must never leave a ghost sitting in the fan.
	modulate.a = 1.0
	z_index = _hover_or_rest_z()


# Update a resting card's depth without disturbing an active flight, hover or
# drag. The discard pile re-stamps its whole stack on every play.
func set_rest_z(z: int) -> void:
	rest_z = z
	if not _in_flight and not _is_dragging:
		z_index = _hover_or_rest_z()


# Move to a new resting place. When `animated` is false the card snaps (used on
# window resize so nothing appears to slide around).
func move_to(target: Vector2, target_rotation: float, z: int,
		animated: bool = true, delay: float = 0.0) -> void:
	# A card already flying to exactly this slot keeps its staggered flight;
	# re-targeting here would collapse the deal into one simultaneous clump
	# and drop the card out of the flight band mid-air. The flight must be
	# alive, though: SceneTreeTween.kill() does not clear is_valid(), so the
	# liveness test is is_running() - a killed or finished tween is going
	# nowhere, and deferring to it would strand the card in the flight band
	# forever.
	var en_route = animated and _in_flight \
		and _move_tween != null and _move_tween.is_valid() and _move_tween.is_running() \
		and z == rest_z \
		and target.distance_to(rest_position) < 0.5 \
		and abs(target_rotation - rest_rotation) < 0.1

	rest_position = target
	rest_rotation = target_rotation
	rest_z = z

	# A drag owns the card completely; a re-layout must not fight it.
	if _is_dragging or en_route:
		return

	# Already parked at exactly this pose? A refresh runs after every event
	# batch; without this check each one would restart an identical 0.34s
	# tween per resting card for as long as the round lasts.
	if animated and not _is_hovered and not _in_flight \
			and position.distance_to(target) < 0.5 \
			and abs(rotation_degrees - target_rotation) < 0.5 \
			and scale.distance_to(_base()) < 0.02 \
			and z_index == _hover_or_rest_z() \
			and modulate.a > 0.999:
		return

	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()

	if not animated:
		_in_flight = false
		position = target
		rotation_degrees = target_rotation
		z_index = _hover_or_rest_z()
		modulate.a = 1.0
		return

	# A card already in transit keeps the flight band until it lands; anything
	# else drops straight into its resting (or hover) band.
	if not _in_flight:
		z_index = _hover_or_rest_z()

	# A hovered card tweens to its lifted pose so a re-layout mid-hover does
	# not yank it back down into the fan.
	var flight_target = target + (_lift() if _is_hovered and not _in_flight else Vector2.ZERO)
	var flight_rotation = 0.0 if _is_hovered and not _in_flight else target_rotation

	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	var duration = _anim(0.34)
	_move_tween.tween_property(self, "position", flight_target, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	_move_tween.tween_property(self, "rotation_degrees", flight_rotation, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	if not _is_hovered:
		_move_tween.tween_property(self, "scale", _base(), duration * 0.8) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(delay)
	# Taking over a card whose fade-in was interrupted must finish that fade,
	# or the card lands as a permanent ghost.
	if modulate.a < 0.999:
		_move_tween.tween_property(self, "modulate:a", 1.0, min(_anim(0.18), duration)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(delay)
	if _in_flight:
		_move_tween.chain().tween_callback(self, "_settle")


# Arc a card from the deck into its fan slot - a straight lerp looks lifeless.
# The card flies above everything at rest and settles when it lands.
func deal_from(origin: Vector2, target: Vector2, target_rotation: float, z: int, delay: float) -> void:
	rest_position = target
	rest_rotation = target_rotation
	rest_z = z
	_in_flight = true
	z_index = DrawOrder.FLYING
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
	_move_tween.chain().tween_callback(self, "_settle")


# Fly to the discard pile with a small overshoot and settle.
func play_to(target: Vector2, target_rotation: float, z: int,
		on_complete_target = null, on_complete_method: String = "") -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
		_pulse_tween = null

	_glow.modulate.a = 0.0
	rest_position = target
	rest_rotation = target_rotation
	rest_z = z
	_in_flight = true
	z_index = DrawOrder.FLYING
	set_interactive(false)

	var duration = _anim(0.36)
	_move_tween = create_tween()
	_move_tween.set_parallel(true)
	_move_tween.tween_property(self, "position", target, duration) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "rotation_degrees", target_rotation, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Lift, then squash on landing: the card hits the pile, dips and settles
	# back to its rest scale. The squash sells the impact far better than a
	# plain ease-out.
	_move_tween.tween_property(self, "scale", _base() * 1.16, duration * 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.chain().tween_property(self, "scale", _base() * Vector2(1.06, 0.93), duration * 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_move_tween.chain().tween_property(self, "scale", _base(), duration * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_move_tween.chain().tween_callback(self, "_settle")
	if on_complete_target != null and on_complete_method != "":
		_move_tween.chain().tween_callback(on_complete_target, on_complete_method, [self])


# Fly off toward a hand and free the node - used when a card leaves the table.
func fly_out(target: Vector2) -> void:
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_in_flight = true
	z_index = DrawOrder.FLYING
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
	# Already showing the requested side? Nothing to flip.
	if face_down == (not show_face):
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

	# The shake replaced whatever owned this card - including a deal flight
	# whose fade-in it killed. Land it properly afterwards (full pose, opacity,
	# flight state), so a rejected click on a card still flying in from the
	# deck cannot strand it in the flight band as a click-swallowing ghost.
	_move_tween.tween_property(self, "position", origin, _anim(0.12)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_move_tween.tween_property(self, "rotation_degrees", rest_rotation, _anim(0.12)) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if modulate.a < 0.999:
		_move_tween.tween_property(self, "modulate:a", 1.0, _anim(0.15)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _in_flight:
		_move_tween.tween_callback(self, "_settle")

	# Flash red so the rejection reads even with sound off.
	var flash = create_tween()
	flash.tween_property(_sprite, "modulate", Color(1.4, 0.45, 0.45, 1), _anim(0.08))
	flash.tween_property(_sprite, "modulate", Color(1, 1, 1, 1), _anim(0.12))
	# Restore the card's real tint - an illegal fan card must end dimmed
	# again, not stay bright white after the red wash fades.
	flash.tween_callback(self, "_update_tint")


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
	# Lift into the hover band, then restore the resting depth on exit (a card
	# in transit stays in the flight band until it lands).
	if _in_flight:
		z_index = DrawOrder.FLYING
	else:
		z_index = DrawOrder.HOVER if active else _hover_or_rest_z()

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
	z_index = DrawOrder.DRAG
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


# True while a deal/draw/play flight is still running.
func is_in_flight() -> bool:
	return _in_flight
