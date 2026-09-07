extends Sprite

const HOVER_OFFSET = Vector2(0, -26)
const HOVER_SCALE = Vector2(0.43, 0.43)
const NORMAL_SCALE = Vector2(0.4, 0.4)

var color: String = "Deck"
var number: String = "-1"
var texture_key: String = "Deck"
var face_texture: Texture = null
var back_texture: Texture = null
var is_face_down: bool = false
var playable: bool = false
var interaction_enabled: bool = true
var home_position: Vector2 = Vector2.ZERO

onready var _tween = Tween.new()

func _ready():
	add_child(_tween)
	home_position = position
	set_process_unhandled_input(false)

func set_card_data(card_data: Dictionary, face_down: bool, deck_texture: Texture) -> void:
	color = str(card_data.get("color", "Deck"))
	number = str(card_data.get("number", "-1"))
	texture_key = str(card_data.get("texture_key", "Deck"))
	face_texture = card_data.get("texture", null)
	back_texture = deck_texture
	is_face_down = face_down
	texture = back_texture if is_face_down else face_texture
	modulate = Color(1, 1, 1, 1)
	playable = false
	interaction_enabled = true

func reveal() -> void:
	if face_texture == null:
		return
	is_face_down = false
	texture = face_texture
	modulate = Color(1, 1, 1, 1)

func hide_face() -> void:
	if back_texture == null:
		return
	is_face_down = true
	texture = back_texture
	set_playable(false)

func set_home_position(value: Vector2) -> void:
	home_position = value

func set_interaction_enabled(value: bool) -> void:
	interaction_enabled = value
	if not value:
		_tween.stop_all()
		scale = NORMAL_SCALE

func set_playable(value: bool) -> void:
	playable = value and not is_face_down
	if playable:
		modulate = Color(1.18, 1.18, 1.18, 1)
	else:
		modulate = Color(1, 1, 1, 1)

func animate_feedback_invalid() -> void:
	_tween.stop_all()
	var start = position
	_tween.interpolate_property(self, "position", start, start + Vector2(-10, 0), 0.045, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	_tween.interpolate_property(self, "position", start + Vector2(-10, 0), start + Vector2(10, 0), 0.09, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.045)
	_tween.interpolate_property(self, "position", start + Vector2(10, 0), start, 0.045, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.135)
	_tween.start()

func _on_Area2D_input_event(_viewport, event, _shape_idx) -> void:
	if not interaction_enabled:
		return
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		get_parent().CardClicked(self)

func _on_Area2D_mouse_entered() -> void:
	if not interaction_enabled or not playable:
		return
	raise()
	_tween.stop_all()
	_tween.interpolate_property(self, "position", position, home_position + HOVER_OFFSET, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween.interpolate_property(self, "scale", scale, HOVER_SCALE, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween.start()

func _on_Area2D_mouse_exited() -> void:
	if not interaction_enabled:
		return
	_tween.stop_all()
	_tween.interpolate_property(self, "position", position, home_position, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween.interpolate_property(self, "scale", scale, NORMAL_SCALE, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)
	_tween.start()
