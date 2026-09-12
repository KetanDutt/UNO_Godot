extends Node2D
# TurnRing
# --------
# The turn-direction indicator: a slowly spinning arc with an arrowhead,
# circling the discard pile in the direction play actually flows on screen.
#
# The old HUD glyph (a guillemet up in the status bar) told you the direction
# only abstractly - players repeatedly read it the wrong way. A ring around
# the pile, turning the way the turn passes seat-to-seat, is unambiguous: the
# arrow sweeps from the current player towards the next one.
#
# It is pure presentation: the controller feeds it position, radius, direction
# and the active colour, and it never reads the rules itself.


const SPIN_SPEED = 0.7          # radians per second, scaled below
const ARC_SPAN = deg2rad(300.0) # the visible sweep; the gap makes rotation read
const ARC_POINTS = 72

var direction: int = 1 setget set_direction
var ring_color: Color = Color(1, 1, 1, 0.5) setget set_ring_color
var radius: float = 120.0 setget set_radius
var line_width: float = 3.0

var _spin_rate: float = SPIN_SPEED
var _pulse_tween: SceneTreeTween = null
var _anim_scale: float = 1.0


func _ready() -> void:
	name = "TurnRing"
	z_index = 8 # table felt is 0, deck backs 10-14, pile 20-26
	visible = false
	set_process(true)


func configure(settings) -> void:
	if settings != null:
		_anim_scale = settings.anim_scale(1.0)
		_spin_rate = SPIN_SPEED / max(_anim_scale, 0.1)


# Feed it the rules state every refresh. Cheap enough to call per event batch.
func set_direction(value: int) -> void:
	var new_direction = 1 if value >= 0 else -1
	var flipped = new_direction != direction and value != 0 and direction != 0
	direction = new_direction
	if flipped:
		# The arrowhead and the arc sweep live in _draw, so they must be
		# repainted - reversing only the spin rate would leave the arrow
		# pointing the way play used to flow.
		update()
		pulse()


func set_ring_color(color: Color) -> void:
	var c = color
	c.a = 0.55
	ring_color = c
	update()


func set_radius(value: float) -> void:
	radius = max(value, 10.0)
	line_width = max(2.0, radius * 0.03)
	update()


func pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var d = 0.35 * max(_anim_scale, 0.1)
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(self, "scale", Vector2(1.14, 1.14), d * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_pulse_tween.tween_property(self, "scale", Vector2.ONE, d * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	# The ring turns the way the turn passes. Node rotation animates the arc;
	# the arrowhead is drawn at the arc's end so it always leads the sweep.
	rotation += direction * _spin_rate * delta


func _draw() -> void:
	# The arc sweeps in the direction of play: a positive angle turns
	# clockwise on screen (Godot's y points down), a negative one turns
	# counter-clockwise. The arrowhead rides the arc's leading end, tangent
	# to the circle, so reversing play flips both the sweep and the head.
	var end_angle = ARC_SPAN * direction
	draw_arc(Vector2.ZERO, radius, 0.0, end_angle, ARC_POINTS, ring_color, line_width, true)
	# Arrowhead at the leading end of the arc, pointing along the sweep.
	var tip_angle = end_angle
	var tip = Vector2(cos(tip_angle), sin(tip_angle)) * radius
	# Tangent that points along increasing angle, flipped for the reverse
	# sweep so the head always leads the rotation of the node.
	var along = Vector2(-sin(tip_angle), cos(tip_angle)) * direction
	var head_length = radius * 0.22
	var head_half = radius * 0.11
	var normal = Vector2(cos(tip_angle), sin(tip_angle))
	var points = PoolVector2Array([
		tip + along * head_length,
		tip + normal * head_half,
		tip - normal * head_half
	])
	draw_colored_polygon(points, Color(ring_color.r, ring_color.g, ring_color.b, 0.85))
