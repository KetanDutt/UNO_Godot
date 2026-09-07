extends Node2D
# EffectsDirector
# ---------------
# All the "juice": particle bursts, confetti, screen shake, floating text,
# radial shockwaves and colour flashes.
#
# Performance notes:
#   * CPUParticles2D emitters are pooled and reused. The original code allocated
#     a fresh emitter (and a one-shot timer) per burst, which churned the scene
#     tree during penalty draws.
#   * Every effect respects the `particles_enabled` / `screen_shake` settings so
#     low-end and motion-sensitive players can turn them off.
#   * Effects draw above the table but below the HUD (see z_index in setup).

const POOL_SIZE = 10
const FLOAT_TEXT_POOL = 8

var settings = null
var _camera_target: Node = null

var _particle_pool: Array = []
var _particle_index: int = 0

var _float_labels: Array = []
var _float_index: int = 0

var _shake_amount: float = 0.0
var _shake_decay: float = 6.0
var _shake_offset: Vector2 = Vector2.ZERO

var _flash_rect: ColorRect = null
var _vignette: ColorRect = null


func _ready() -> void:
	name = "EffectsDirector"
	z_index = 90
	_build_pools()
	set_process(true)


func configure(settings_ref, camera_target: Node) -> void:
	settings = settings_ref
	_camera_target = camera_target


func _particles_on() -> bool:
	return settings == null or settings.particles_enabled


func _shake_on() -> bool:
	return settings == null or settings.screen_shake


# ---------------------------------------------------------------------------
# Pools
# ---------------------------------------------------------------------------
func _build_pools() -> void:
	for i in range(POOL_SIZE):
		var particles = CPUParticles2D.new()
		particles.name = "Burst%d" % i
		particles.emitting = false
		particles.one_shot = true
		particles.local_coords = false
		particles.z_index = 5
		add_child(particles)
		_particle_pool.append(particles)

	# Float text is Control-based, so it lives under a Node2D host that carries
	# the z_index (Control has no z_index of its own in Godot 3).
	var text_host = Node2D.new()
	text_host.name = "FloatTextHost"
	text_host.z_index = 20
	add_child(text_host)

	for i in range(FLOAT_TEXT_POOL):
		var label = Label.new()
		label.name = "FloatText%d" % i
		label.visible = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.align = Label.ALIGN_CENTER
		label.valign = Label.VALIGN_CENTER
		label.rect_size = Vector2(320, 48)
		label.rect_pivot_offset = Vector2(160, 24)
		text_host.add_child(label)
		_float_labels.append(label)


func _next_emitter() -> CPUParticles2D:
	var emitter = _particle_pool[_particle_index]
	_particle_index = (_particle_index + 1) % _particle_pool.size()
	return emitter


func _next_label() -> Label:
	var label = _float_labels[_float_index]
	_float_index = (_float_index + 1) % _float_labels.size()
	return label


# ---------------------------------------------------------------------------
# Particle effects
# ---------------------------------------------------------------------------
# A quick radial spray - used when a card lands.
func burst(position: Vector2, color: Color, amount: int = 22, speed: float = 210.0) -> void:
	if not _particles_on():
		return
	var emitter = _next_emitter()
	emitter.emitting = false
	emitter.position = position
	emitter.amount = amount
	emitter.lifetime = 0.6
	emitter.explosiveness = 0.95
	emitter.randomness = 0.6
	emitter.direction = Vector2.UP
	emitter.spread = 180.0
	emitter.gravity = Vector2(0, 420)
	emitter.initial_velocity = speed
	emitter.initial_velocity_random = 0.5
	emitter.scale_amount = 3.4
	emitter.scale_amount_random = 0.6
	emitter.color = color
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 12.0
	emitter.damping = 40.0
	emitter.angular_velocity = 180.0
	emitter.angular_velocity_random = 1.0
	_apply_fade_ramp(emitter, color)
	emitter.restart()
	emitter.emitting = true


# Upward sparkle, used for UNO calls and positive feedback.
func sparkle(position: Vector2, color: Color, amount: int = 18) -> void:
	if not _particles_on():
		return
	var emitter = _next_emitter()
	emitter.emitting = false
	emitter.position = position
	emitter.amount = amount
	emitter.lifetime = 0.9
	emitter.explosiveness = 0.8
	emitter.randomness = 0.5
	emitter.direction = Vector2.UP
	emitter.spread = 45.0
	emitter.gravity = Vector2(0, -60)
	emitter.initial_velocity = 130.0
	emitter.initial_velocity_random = 0.7
	emitter.scale_amount = 2.6
	emitter.color = color
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	emitter.emission_sphere_radius = 30.0
	emitter.damping = 20.0
	_apply_fade_ramp(emitter, color)
	emitter.restart()
	emitter.emitting = true


# Long-lived falling confetti for the victory screen.
func confetti(area_size: Vector2, colors: Array) -> void:
	if not _particles_on():
		return
	for i in range(min(colors.size(), _particle_pool.size())):
		var emitter = _next_emitter()
		emitter.emitting = false
		emitter.position = Vector2(area_size.x * 0.5, -40)
		emitter.amount = 46
		emitter.lifetime = 3.2
		emitter.explosiveness = 0.05
		emitter.randomness = 0.9
		emitter.direction = Vector2.DOWN
		emitter.spread = 28.0
		emitter.gravity = Vector2(0, 190)
		emitter.initial_velocity = 120.0
		emitter.initial_velocity_random = 0.8
		emitter.scale_amount = 4.5
		emitter.scale_amount_random = 0.7
		emitter.color = colors[i]
		emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		emitter.emission_rect_extents = Vector2(area_size.x * 0.52, 8)
		emitter.angular_velocity = 320.0
		emitter.angular_velocity_random = 1.0
		emitter.damping = 6.0
		_apply_fade_ramp(emitter, colors[i])
		emitter.restart()
		emitter.emitting = true


# Dust kicked up when a heavy penalty lands.
func impact_ring(position: Vector2, color: Color) -> void:
	if not _particles_on():
		return
	var emitter = _next_emitter()
	emitter.emitting = false
	emitter.position = position
	emitter.amount = 26
	emitter.lifetime = 0.45
	emitter.explosiveness = 1.0
	emitter.randomness = 0.15
	emitter.spread = 180.0
	emitter.gravity = Vector2.ZERO
	emitter.initial_velocity = 320.0
	emitter.initial_velocity_random = 0.1
	emitter.scale_amount = 2.2
	emitter.color = color
	emitter.damping = 260.0
	_apply_fade_ramp(emitter, color)
	emitter.restart()
	emitter.emitting = true


# Fade particles out over their lifetime instead of popping.
func _apply_fade_ramp(emitter: CPUParticles2D, color: Color) -> void:
	var ramp = Gradient.new()
	var bright = color.lightened(0.25)
	bright.a = 1.0
	var gone = color
	gone.a = 0.0
	ramp.set_color(0, bright)
	ramp.set_color(1, gone)
	emitter.color_ramp = ramp


# ---------------------------------------------------------------------------
# Floating combat text
# ---------------------------------------------------------------------------
func float_text(text: String, position: Vector2, color: Color, size: int = 30, rise: float = 74.0) -> void:
	var label = _next_label()
	var font = load("res://Scripts/Systems/ThemeFactory.gd").make_font(size, "black", 4)
	label.add_font_override("font", font)
	label.add_color_override("font_color", color)
	label.text = text
	label.visible = true
	label.modulate = Color(1, 1, 1, 0)
	label.rect_scale = Vector2(0.6, 0.6)
	label.rect_position = position - Vector2(160, 24)

	var duration = 0.9
	if settings != null:
		duration = settings.anim_scale(0.9)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, duration * 0.18)
	tween.tween_property(label, "rect_scale", Vector2(1.0, 1.0), duration * 0.32) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "rect_position:y", label.rect_position.y - rise, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(duration * 0.25)
	tween.chain().tween_property(label, "modulate:a", 0.0, duration * 0.35)
	tween.chain().tween_callback(label, "hide")


# ---------------------------------------------------------------------------
# Screen shake
# ---------------------------------------------------------------------------
func shake(amount: float = 8.0, decay: float = 6.0) -> void:
	if not _shake_on():
		return
	_shake_amount = max(_shake_amount, amount)
	_shake_decay = decay


func _process(delta: float) -> void:
	if _camera_target == null:
		return
	if _shake_amount <= 0.01:
		if _shake_offset != Vector2.ZERO:
			_shake_offset = Vector2.ZERO
			_apply_shake_offset(Vector2.ZERO)
		return
	_shake_amount = max(0.0, _shake_amount - _shake_decay * delta * 60.0 * delta)
	_shake_amount = lerp(_shake_amount, 0.0, clamp(delta * _shake_decay, 0.0, 1.0))
	var offset = Vector2(
		rand_range(-_shake_amount, _shake_amount),
		rand_range(-_shake_amount, _shake_amount)
	)
	_shake_offset = offset
	_apply_shake_offset(offset)


func _apply_shake_offset(offset: Vector2) -> void:
	if _camera_target == null:
		return
	if _camera_target is Node2D:
		_camera_target.position = offset
	elif _camera_target is Control:
		_camera_target.rect_position = offset


# ---------------------------------------------------------------------------
# Full-screen flash / vignette
# ---------------------------------------------------------------------------
func attach_overlays(parent: CanvasItem) -> void:
	_flash_rect = ColorRect.new()
	_flash_rect.name = "FlashOverlay"
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.anchor_right = 1.0
	_flash_rect.anchor_bottom = 1.0
	_flash_rect.color = Color(1, 1, 1, 0)
	parent.add_child(_flash_rect)


func flash(color: Color, strength: float = 0.4, duration: float = 0.35) -> void:
	if _flash_rect == null or not _particles_on():
		return
	_flash_rect.raise()
	var tint = color
	tint.a = strength
	_flash_rect.color = tint
	var scaled = duration
	if settings != null:
		scaled = settings.anim_scale(duration)
	var tween = create_tween()
	tween.tween_property(_flash_rect, "color:a", 0.0, scaled).set_trans(Tween.TRANS_QUAD)
