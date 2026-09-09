extends CanvasLayer
# HudLayer
# --------
# In-game heads-up display: status banner, active-colour indicator, deck/discard
# counters, per-seat name plates, score strip, action buttons and the turn banner.
#
# Built with real container nodes and anchors (the original positioned every
# widget with hand-computed margins, which broke at non-720p sizes). Everything
# here is presentation only - it raises signals and never touches the rules.

signal draw_pressed
signal pass_pressed
signal uno_pressed
signal sort_pressed
signal menu_pressed
signal catch_pressed

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const PlayerIdentity = preload("res://Scripts/Core/PlayerIdentity.gd")
const ThemeFactory = preload("res://Scripts/Systems/ThemeFactory.gd")
const TableLayout = preload("res://Scripts/UI/TableLayout.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")

var settings = null

var _root: Control = null
var _status_panel: PanelContainer = null
var _status_label: Label = null
var _color_chip: Panel = null
var _color_label: Label = null
var _deck_label: Label = null
var _score_label: Label = null
var _turn_banner: Label = null
var _direction_icon: Label = null
var _stack_label: Label = null

var _draw_button: Button = null
var _pass_button: Button = null
var _uno_button: Button = null
var _sort_button: Button = null
var _menu_button: Button = null
var _catch_button: Button = null

var _seat_plates: Array = []
var _seat_active: Array = []
var _seat_pop: SceneTreeTween = null
var _button_bar: VBoxContainer = null

# Remote/keyboard selection of the action buttons: index into get_buttons(),
# -1 when the buttons are not selected. Mirrors the card selection model.
var _button_selection: int = -1
var _selection_strips: Array = []
var _button_pop: SceneTreeTween = null

var _status_tween = null
var _chip_tween = null
var _uno_pulse = null
var _direction_tween = null
var _last_direction: int = 0


func _ready() -> void:
	name = "HudLayer"
	layer = 5
	pause_mode = Node.PAUSE_MODE_PROCESS


func build(settings_ref, theme: Theme) -> void:
	settings = settings_ref

	var root = Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.theme = theme
	add_child(root)
	_root = root

	_build_status(root)
	_build_color_indicator(root)
	_build_deck_readout(root)
	_build_scoreboard(root)
	_build_buttons(root)
	_build_turn_banner(root)



# Swap the theme live (the high-contrast toggle), without rebuilding widgets.
func apply_theme(theme: Theme) -> void:
	if _root != null:
		_root.theme = theme


# --- status banner ---------------------------------------------------------
# Every widget is positioned from TableLayout so the composition is defined in
# one place and verified by Tests/TestLayout.gd.
func _build_status(root: Control) -> void:
	_status_panel = PanelContainer.new()
	_status_panel.name = "StatusPanel"
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box = ThemeFactory.flat_box(Color(0.05, 0.06, 0.09, 0.74), 16, 1, Color(1, 1, 1, 0.10))
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	_status_panel.add_stylebox_override("panel", box)
	root.add_child(_status_panel)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.align = Label.ALIGN_CENTER
	_status_label.valign = Label.VALIGN_CENTER
	_status_label.autowrap = true
	_status_label.add_font_override("font", ThemeFactory.make_font(18, "medium"))
	_status_panel.add_child(_status_label)


# --- active colour ---------------------------------------------------------
func _build_color_indicator(root: Control) -> void:
	_color_chip = Panel.new()
	_color_chip.name = "ColorChip"
	_color_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_color_chip)

	_color_label = Label.new()
	_color_label.name = "ColorLabel"
	_color_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_label.anchor_right = 1.0
	_color_label.anchor_bottom = 1.0
	_color_label.align = Label.ALIGN_CENTER
	_color_label.valign = Label.VALIGN_CENTER
	_color_label.add_font_override("font", ThemeFactory.make_font(16, "black", 3))
	_color_chip.add_child(_color_label)

	_direction_icon = Label.new()
	_direction_icon.name = "DirectionIcon"
	_direction_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_direction_icon.align = Label.ALIGN_CENTER
	_direction_icon.valign = Label.VALIGN_CENTER
	_direction_icon.add_font_override("font", ThemeFactory.make_font(26, "bold", 3))
	root.add_child(_direction_icon)

	_stack_label = Label.new()
	_stack_label.name = "StackLabel"
	_stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack_label.visible = false
	_stack_label.align = Label.ALIGN_CENTER
	_stack_label.valign = Label.VALIGN_CENTER
	_stack_label.add_font_override("font", ThemeFactory.make_font(22, "black", 3))
	_stack_label.add_color_override("font_color", Color(1.0, 0.45, 0.35))
	root.add_child(_stack_label)


# --- deck counters ---------------------------------------------------------
func _build_deck_readout(root: Control) -> void:
	_deck_label = Label.new()
	_deck_label.name = "DeckLabel"
	_deck_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deck_label.add_font_override("font", ThemeFactory.make_font(15, "medium", 3))
	_deck_label.add_color_override("font_color", Color(0.86, 0.89, 0.95))
	root.add_child(_deck_label)


# --- scoreboard ------------------------------------------------------------
func _build_scoreboard(root: Control) -> void:
	_score_label = Label.new()
	_score_label.name = "ScoreLabel"
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_label.align = Label.ALIGN_RIGHT
	_score_label.add_font_override("font", ThemeFactory.make_font(15, "medium", 3))
	root.add_child(_score_label)


# Create one floating name plate per seat: an avatar and the player's name.
func setup_seats(names: Array, avatar_keys: Array = []) -> void:
	for plate in _seat_plates:
		if is_instance_valid(plate["panel"]):
			plate["panel"].queue_free()
	_seat_plates.clear()
	_seat_active.clear()

	var root = get_node("Root")
	for i in range(names.size()):
		var panel = PanelContainer.new()
		panel.name = "SeatPlate%d" % i
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box = ThemeFactory.flat_box(Color(0.05, 0.06, 0.09, 0.80), 14, 2, Color(1, 1, 1, 0.10))
		box.content_margin_left = 13
		box.content_margin_right = 13
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		panel.add_stylebox_override("panel", box)
		root.add_child(panel)

		var row = HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_constant_override("separation", 7)
		panel.add_child(row)

		var avatar = TextureRect.new()
		avatar.name = "Avatar"
		avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.rect_min_size = Vector2(24, 24)
		avatar.expand = true
		avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if i < avatar_keys.size():
			avatar.texture = load(PlayerIdentity.avatar_path(avatar_keys[i]))
		row.add_child(avatar)

		var label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.align = Label.ALIGN_CENTER
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_font_override("font", ThemeFactory.make_font(15, "bold"))
		row.add_child(label)

		_seat_plates.append({"panel": panel, "label": label, "box": box,
			"avatar": avatar, "has_avatar": avatar.texture != null})
		_seat_active.append(false)


# Move a seat plate to a screen position and refresh its contents.
func update_seat(index: int, position: Vector2, text: String, active: bool, danger: bool) -> void:
	if index < 0 or index >= _seat_plates.size():
		return
	var plate = _seat_plates[index]
	var panel = plate["panel"]
	var label = plate["label"]
	var box = plate["box"]

	label.text = text
	# The avatar adds a fixed chunk next to the name.
	var extras = 64.0 if plate["has_avatar"] else 36.0
	var width = max(132.0, label.get_font("font").get_string_size(text).x + extras)
	panel.rect_size = Vector2(width, 34)
	panel.rect_position = position - Vector2(width * 0.5, 17)

	var border = Color(1, 1, 1, 0.10)
	if danger:
		border = Color(1.0, 0.32, 0.28, 0.95)
	elif active:
		border = ThemeFactory.ACCENT
	box.border_color = border
	box.bg_color = Color(0.10, 0.12, 0.18, 0.93) if active else Color(0.05, 0.06, 0.09, 0.80)
	label.add_color_override("font_color", Color(1, 1, 1) if active else Color(0.76, 0.79, 0.86))

	# A seat taking the turn pops - with random opponent names and avatars the
	# plates now carry identity, so the hand-off deserves to be legible.
	if active and not _seat_active[index]:
		if _seat_pop != null and _seat_pop.is_valid():
			_seat_pop.kill()
		panel.rect_pivot_offset = panel.rect_size * 0.5
		var d = settings.anim_scale(0.32) if settings != null else 0.32
		_seat_pop = create_tween()
		_seat_pop.tween_property(panel, "rect_scale", Vector2(1.16, 1.16), d * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_seat_pop.tween_property(panel, "rect_scale", Vector2.ONE, d * 0.6) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_seat_active[index] = active


# --- action buttons --------------------------------------------------------
# A vertical column on the right keeps the buttons clear of the card fan, which
# is what collided in the original horizontal layout.
func _build_buttons(root: Control) -> void:
	_button_bar = VBoxContainer.new()
	_button_bar.name = "ButtonColumn"
	_button_bar.add_constant_override("separation", 8)
	root.add_child(_button_bar)

	_draw_button = _make_action_button("DRAW", "Draw a card  (D)", "draw_pressed")
	_pass_button = _make_action_button("PASS", "End your turn after drawing  (P)", "pass_pressed")
	_uno_button = _make_action_button(
		"UNO!", "Call UNO before playing your second-to-last card  (U)", "uno_pressed")
	_catch_button = _make_action_button(
		"CATCH!", "Catch an opponent who forgot to call UNO  (C)", "catch_pressed")
	_sort_button = _make_action_button("SORT", "Sort your hand  (S)", "sort_pressed")

	ThemeFactory.accent_button_styles(_uno_button, Color(0.92, 0.62, 0.10))
	ThemeFactory.accent_button_styles(_catch_button, Color(0.85, 0.22, 0.28))
	_catch_button.visible = false

	_menu_button = Button.new()
	_menu_button.name = "MenuButton"
	_menu_button.text = "MENU"
	_menu_button.hint_tooltip = "Pause  (Esc)"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.connect("pressed", self, "_on_button", ["menu_pressed"])
	root.add_child(_menu_button)

	# A visible accent strip on whichever button the remote selection points at.
	for button in get_buttons():
		var strip = ColorRect.new()
		strip.name = "FocusStrip"
		strip.color = ThemeFactory.ACCENT
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		strip.anchor_top = 0.0
		strip.anchor_bottom = 1.0
		strip.margin_left = 3
		strip.margin_right = 7
		strip.margin_top = 5
		strip.margin_bottom = -5
		strip.visible = false
		button.add_child(strip)
		_selection_strips.append(strip)


func _make_action_button(text: String, tooltip: String, signal_name: String) -> Button:
	var button = Button.new()
	button.name = text.replace("!", "") + "Button"
	button.text = text
	button.hint_tooltip = tooltip
	# No engine focus: during play the D-pad drives a custom two-zone
	# selection (cards <-> buttons) instead, and a focused button would
	# swallow Enter presses meant for the hand.
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.connect("pressed", self, "_on_button", [signal_name])
	_button_bar.add_child(button)
	return button


func _on_button(signal_name: String) -> void:
	# Each signal is emitted through a string literal so the compiler can see
	# the declaration is used; a parameterised emit_signal(name) reads as
	# "declared but never emitted" in the editor warnings.
	match signal_name:
		"draw_pressed":
			emit_signal("draw_pressed")
		"pass_pressed":
			emit_signal("pass_pressed")
		"uno_pressed":
			emit_signal("uno_pressed")
		"catch_pressed":
			emit_signal("catch_pressed")
		"sort_pressed":
			emit_signal("sort_pressed")
		"menu_pressed":
			emit_signal("menu_pressed")


func get_buttons() -> Array:
	return [_draw_button, _pass_button, _uno_button, _catch_button, _sort_button, _menu_button]


func seat_avatar_texture(index: int):
	if index < 0 or index >= _seat_plates.size():
		return null
	return _seat_plates[index]["avatar"].texture


# --- remote / keyboard button selection ------------------------------------
# A TV remote has a D-pad and Enter only, so the action buttons join the same
# kind of selection model the hand uses: one button is marked selected, the
# controller cycles it and activates it.

func set_button_selection(index: int) -> void:
	_button_selection = index
	var buttons = get_buttons()
	for i in range(buttons.size()):
		var selected = i == index
		if _selection_strips.size() > i and _selection_strips[i] != null:
			_selection_strips[i].visible = selected
		var button = buttons[i]
		if button == null:
			continue
		if not selected:
			button.modulate = Color(1, 1, 1)
			continue
		button.modulate = Color(1.14, 1.14, 1.14)
		if _button_pop != null and _button_pop.is_valid():
			_button_pop.kill()
		button.rect_pivot_offset = button.rect_size * 0.5
		var d = settings.anim_scale(0.22) if settings != null else 0.22
		_button_pop = create_tween()
		_button_pop.tween_property(button, "rect_scale", Vector2(1.06, 1.06), d * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_button_pop.tween_property(button, "rect_scale", Vector2.ONE, d * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func is_button_selectable(index: int) -> bool:
	var buttons = get_buttons()
	if index < 0 or index >= buttons.size():
		return false
	var button = buttons[index]
	return button != null and button.visible and not button.disabled


# Re-place every widget for the current viewport size. Called on boot and on
# every window resize.
func apply_layout(viewport: Vector2) -> void:
	var s = TableLayout.scale_factor(viewport)

	var status = TableLayout.status_rect(viewport)
	_status_panel.rect_position = status["position"]
	_status_panel.rect_size = status["size"]
	_status_panel.rect_pivot_offset = status["size"] * 0.5

	var counts = TableLayout.deck_counts_rect(viewport)
	_deck_label.rect_position = counts["position"]
	_deck_label.rect_size = counts["size"]

	var score = TableLayout.score_rect(viewport)
	_score_label.rect_position = score["position"]
	_score_label.rect_size = score["size"]

	var chip = TableLayout.color_chip_rect(viewport)
	_color_chip.rect_position = chip["position"]
	_color_chip.rect_size = chip["size"]
	_color_chip.rect_pivot_offset = chip["size"] * 0.5

	var direction = TableLayout.direction_rect(viewport)
	_direction_icon.rect_position = direction["position"]
	_direction_icon.rect_size = direction["size"]

	var stack = TableLayout.stack_rect(viewport)
	_stack_label.rect_position = stack["position"]
	_stack_label.rect_size = stack["size"]

	var column = TableLayout.button_column_rect(viewport, 5)
	_button_bar.rect_position = column["position"]
	_button_bar.rect_size = column["size"]
	_button_bar.add_constant_override("separation", int(column["separation"]))
	for button in [_draw_button, _pass_button, _uno_button, _catch_button, _sort_button]:
		if button != null:
			button.rect_min_size = Vector2(column["size"].x, column["button_height"])

	if _menu_button != null:
		var menu_size = Vector2(column["size"].x, 40.0 * s)
		_menu_button.rect_size = menu_size
		_menu_button.rect_position = Vector2(column["position"].x, viewport.y - menu_size.y - 16.0 * s)

	if _turn_banner != null:
		var banner_size = Vector2(viewport.x * 0.8, 90.0 * s)
		_turn_banner.rect_size = banner_size
		_turn_banner.rect_position = Vector2(
			TableLayout.play_center_x(viewport) - banner_size.x * 0.5,
			viewport.y * 0.5 - banner_size.y - 40.0 * s)
		_turn_banner.rect_pivot_offset = banner_size * 0.5


# --- turn banner -----------------------------------------------------------
func _build_turn_banner(root: Control) -> void:
	_turn_banner = Label.new()
	_turn_banner.name = "TurnBanner"
	_turn_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_turn_banner.align = Label.ALIGN_CENTER
	_turn_banner.valign = Label.VALIGN_CENTER
	_turn_banner.modulate = Color(1, 1, 1, 0)
	_turn_banner.add_font_override("font", ThemeFactory.make_font(54, "black", 6))
	root.add_child(_turn_banner)


# Big centred announcement that sweeps in and out.
func announce(text: String, color: Color = Color(1, 1, 1)) -> void:
	if _turn_banner == null:
		return
	_turn_banner.text = text
	_turn_banner.add_color_override("font_color", color)
	_turn_banner.modulate = Color(1, 1, 1, 0)
	_turn_banner.rect_scale = Vector2(0.7, 0.7)

	var d = settings.anim_scale(1.0) if settings != null else 1.0
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(_turn_banner, "modulate:a", 1.0, d * 0.16)
	tween.tween_property(_turn_banner, "rect_scale", Vector2(1.0, 1.0), d * 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(d * 0.5)
	tween.chain().set_parallel(true)
	tween.tween_property(_turn_banner, "modulate:a", 0.0, d * 0.28)
	tween.tween_property(_turn_banner, "rect_scale", Vector2(1.12, 1.12), d * 0.28) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


# ---------------------------------------------------------------------------
# Updates
# ---------------------------------------------------------------------------
func set_status(text: String, animate: bool = true) -> void:
	if _status_label == null or _status_label.text == text:
		return
	_status_label.text = text
	if not animate or _status_panel == null:
		return
	if _status_tween != null and _status_tween.is_valid():
		_status_tween.kill()
	_status_panel.rect_pivot_offset = _status_panel.rect_size * 0.5
	var d = settings.anim_scale(0.22) if settings != null else 0.22
	_status_tween = create_tween()
	_status_tween.tween_property(_status_panel, "rect_scale", Vector2(1.035, 1.06), d * 0.4) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_status_tween.tween_property(_status_panel, "rect_scale", Vector2.ONE, d * 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func set_active_color(color: int, animate: bool = true) -> void:
	if _color_chip == null:
		return
	var tint = CardTypes.color_value(color)
	var box = ThemeFactory.flat_box(tint, 14, 3, tint.lightened(0.45))
	_color_chip.add_stylebox_override("panel", box)

	var text = CardTypes.color_name(color).to_upper()
	if settings != null and settings.colorblind_glyphs:
		text = CardTypes.color_glyph(color) + "  " + text
	_color_label.text = text
	# Dark text on yellow keeps contrast readable.
	# Yellow needs dark text to stay legible.
	var ink = Color(0.1, 0.09, 0.05) if color == CardTypes.CardColor.YELLOW else Color(1, 1, 1)
	_color_label.add_color_override("font_color", ink)

	if not animate:
		return
	if _chip_tween != null and _chip_tween.is_valid():
		_chip_tween.kill()
	var d = settings.anim_scale(0.34) if settings != null else 0.34
	_chip_tween = create_tween()
	_chip_tween.tween_property(_color_chip, "rect_scale", Vector2(1.16, 1.16), d * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_chip_tween.tween_property(_color_chip, "rect_scale", Vector2.ONE, d * 0.65) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_direction(direction: int) -> void:
	if _direction_icon == null:
		return
	# Roboto ships no arrow glyphs, so guillemets stand in for turn order.
	_direction_icon.text = "\u00BB" if direction > 0 else "\u00AB"
	if direction == _last_direction:
		_direction_icon.add_color_override("font_color", Color(0.85, 0.88, 0.95))
		return
	# A reversal deserves a flourish: the marker swells and flashes.
	var changed = _last_direction != 0
	_last_direction = direction
	_direction_icon.add_color_override("font_color", Color(0.85, 0.88, 0.95))
	if not changed:
		return
	if _direction_tween != null and _direction_tween.is_valid():
		_direction_tween.kill()
	_direction_icon.rect_pivot_offset = _direction_icon.rect_size * 0.5
	_direction_icon.modulate = ThemeFactory.ACCENT
	var d = settings.anim_scale(0.5) if settings != null else 0.5
	_direction_tween = create_tween()
	_direction_tween.set_parallel(true)
	_direction_tween.tween_property(_direction_icon, "rect_scale", Vector2(1.7, 1.7), d * 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_direction_tween.chain().tween_property(_direction_icon, "rect_scale", Vector2.ONE, d * 0.65) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_direction_tween.tween_property(_direction_icon, "modulate",
		Color(0.85, 0.88, 0.95), d * 0.8).set_delay(d * 0.2)


func set_pending_stack(amount: int) -> void:
	if _stack_label == null:
		return
	var show = amount > 0
	if _stack_label.visible != show:
		_stack_label.visible = show
		if show:
			_stack_label.rect_scale = Vector2(0.5, 0.5)
			var tween = create_tween()
			tween.tween_property(_stack_label, "rect_scale", Vector2.ONE, 0.28) \
				.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if show:
		_stack_label.text = "+%d" % amount


func set_deck_counts(draw_count: int, discard_count: int) -> void:
	if _deck_label == null:
		return
	_deck_label.text = "DECK  %d\nPILE  %d" % [draw_count, discard_count]
	# Warn when the stock is running low: the next recycle is about to swing
	# the discard pile back into play.
	if draw_count <= 5:
		_deck_label.add_color_override("font_color", Color(1.0, 0.45, 0.38))
	elif draw_count <= 12:
		_deck_label.add_color_override("font_color", Color(1.0, 0.78, 0.38))
	else:
		_deck_label.add_color_override("font_color", Color(0.86, 0.89, 0.95))


func set_scores(names: Array, scores: Array, target: int, round_number: int) -> void:
	if _score_label == null:
		return
	# Shorten the header when the panel is narrow so it cannot run off-screen.
	var header = "ROUND %d   -   FIRST TO %d" % [round_number, target]
	var font = _score_label.get_font("font")
	if font != null and font.get_string_size(header).x > _score_label.rect_size.x:
		header = "R%d  /  %d" % [round_number, target]

	var lines = [header]
	for i in range(names.size()):
		lines.append("%s   %d" % [names[i], scores[i]])
	_score_label.text = PoolStringArray(lines).join("\n")


func set_button_states(can_draw: bool, can_pass: bool, can_uno: bool,
		can_sort: bool, can_catch: bool) -> void:
	if _draw_button != null:
		_draw_button.disabled = not can_draw
	if _pass_button != null:
		_pass_button.disabled = not can_pass
	if _sort_button != null:
		_sort_button.disabled = not can_sort
	if _uno_button != null:
		_uno_button.disabled = not can_uno
		_set_uno_pulse(can_uno)
	if _catch_button != null:
		if _catch_button.visible != can_catch:
			_catch_button.visible = can_catch
			if can_catch:
				_catch_button.rect_scale = Vector2(0.6, 0.6)
				var tween = create_tween()
				tween.tween_property(_catch_button, "rect_scale", Vector2.ONE, 0.3) \
					.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_catch_button.disabled = not can_catch


# Draw attention to the UNO button exactly when it becomes legal.
func _set_uno_pulse(active: bool) -> void:
	if _uno_pulse != null and _uno_pulse.is_valid():
		_uno_pulse.kill()
		_uno_pulse = null
	if _uno_button == null:
		return
	_uno_button.rect_pivot_offset = _uno_button.rect_size * 0.5
	if not active:
		_uno_button.rect_scale = Vector2.ONE
		return
	_uno_pulse = create_tween()
	_uno_pulse.set_loops()
	_uno_pulse.tween_property(_uno_button, "rect_scale", Vector2(1.08, 1.08), 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_uno_pulse.tween_property(_uno_button, "rect_scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func set_hud_visible(value: bool) -> void:
	var root = get_node_or_null("Root")
	if root != null:
		root.visible = value
