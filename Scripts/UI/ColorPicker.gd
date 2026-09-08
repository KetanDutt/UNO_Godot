extends CanvasLayer
# ColorPickerOverlay
# ------------------
# Modal wheel shown when a wild card needs a colour. Four large, high-contrast
# targets with hover/focus feedback, full keyboard and gamepad support, and a
# suggestion hint showing which colour you hold the most of.

signal color_selected(color)

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const ThemeFactory = preload("res://Scripts/Systems/ThemeFactory.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")

var settings = null

var _panel: Panel = null
var _dim: ColorRect = null
var _buttons: Array = []
var _hint: Label = null
var _root: Control = null


func _ready() -> void:
	name = "ColorPickerOverlay"
	layer = 15
	pause_mode = Node.PAUSE_MODE_PROCESS


func build(settings_ref, theme: Theme) -> void:
	settings = settings_ref

	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = theme
	_root.visible = false
	add_child(_root)

	_dim = ColorRect.new()
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.color = Color(0.02, 0.03, 0.05, 0.0)
	_root.add_child(_dim)

	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.margin_left = -290
	_panel.margin_right = 290
	_panel.margin_top = -190
	_panel.margin_bottom = 190
	_panel.rect_pivot_offset = Vector2(290, 190)
	_root.add_child(_panel)

	var box = VBoxContainer.new()
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.margin_left = 26
	box.margin_right = -26
	box.margin_top = 22
	box.margin_bottom = -22
	box.add_constant_override("separation", 14)
	_panel.add_child(box)

	var title = Label.new()
	title.text = "CHOOSE A COLOUR"
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", ThemeFactory.make_font(30, "black", 3))
	title.add_color_override("font_color", ThemeFactory.ACCENT)
	box.add_child(title)

	_hint = Label.new()
	_hint.align = Label.ALIGN_CENTER
	_hint.add_font_override("font", ThemeFactory.make_font(15, "medium"))
	_hint.add_color_override("font_color", ThemeFactory.INK_FAINT)
	box.add_child(_hint)

	# 2x2 grid reads faster than a row of four and gives bigger touch targets.
	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_constant_override("hseparation", 14)
	grid.add_constant_override("vseparation", 14)
	box.add_child(grid)

	for color in CardTypes.PLAYABLE_COLORS:
		var button = Button.new()
		button.name = CardTypes.color_name(color) + "Button"
		var label = CardTypes.color_name(color).to_upper()
		if settings != null and settings.colorblind_glyphs:
			label = CardTypes.color_glyph(color) + "  " + label
		button.text = label
		button.rect_min_size = Vector2(240, 88)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
		button.add_font_override("font", ThemeFactory.make_font(26, "black"))
		ThemeFactory.accent_button_styles(button, CardTypes.color_value(color))
		button.connect("pressed", self, "_on_pressed", [color])
		button.connect("mouse_entered", self, "_on_hover", [button])
		button.connect("focus_entered", self, "_on_hover", [button])
		grid.add_child(button)
		_buttons.append(button)


# `suggested` is the colour the player holds most of; -1 to omit the hint.
func open(suggested: int = -1) -> void:
	_root.visible = true
	refresh_labels()

	if suggested >= 0:
		_hint.text = "You hold the most %s" % CardTypes.color_name(suggested)
	else:
		_hint.text = "This colour becomes active for the next play"

	var d = settings.anim_scale(0.3) if settings != null else 0.3
	_dim.color.a = 0.0
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.rect_scale = Vector2(0.8, 0.8)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.72, d)
	tween.tween_property(_panel, "modulate:a", 1.0, d * 0.7)
	tween.tween_property(_panel, "rect_scale", Vector2.ONE, d) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Stagger the buttons in so the panel feels assembled rather than pasted.
	for i in range(_buttons.size()):
		var button = _buttons[i]
		button.modulate = Color(1, 1, 1, 0)
		button.rect_scale = Vector2(0.85, 0.85)
		button.rect_pivot_offset = button.rect_size * 0.5
		var stagger = create_tween()
		stagger.tween_interval(d * 0.35 + i * d * 0.09)
		stagger.set_parallel(true)
		stagger.tween_property(button, "modulate:a", 1.0, d * 0.5)
		stagger.tween_property(button, "rect_scale", Vector2.ONE, d * 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var focus_index = 0
	if suggested >= 0:
		focus_index = CardTypes.PLAYABLE_COLORS.find(suggested)
		focus_index = int(max(focus_index, 0))
	yield(get_tree(), "idle_frame")
	if _root.visible and focus_index < _buttons.size():
		_buttons[focus_index].grab_focus()


func refresh_labels() -> void:
	for i in range(_buttons.size()):
		var color = CardTypes.PLAYABLE_COLORS[i]
		var label = CardTypes.color_name(color).to_upper()
		if settings != null and settings.colorblind_glyphs:
			label = CardTypes.color_glyph(color) + "  " + label
		_buttons[i].text = label


func close() -> void:
	if not _root.visible:
		return
	var d = settings.anim_scale(0.2) if settings != null else 0.2
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_dim, "color:a", 0.0, d)
	tween.tween_property(_panel, "modulate:a", 0.0, d)
	tween.tween_property(_panel, "rect_scale", Vector2(0.9, 0.9), d)
	tween.chain().tween_callback(_root, "hide")


func is_open() -> bool:
	return _root != null and _root.visible


func _on_pressed(color: int) -> void:
	emit_signal("color_selected", color)


func _on_hover(button: Button) -> void:
	button.rect_pivot_offset = button.rect_size * 0.5
	var tween = create_tween()
	tween.tween_property(button, "rect_scale", Vector2(1.05, 1.05), 0.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "rect_scale", Vector2.ONE, 0.14) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
