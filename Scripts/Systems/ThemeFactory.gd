extends Reference
# ThemeFactory
# ------------
# Builds the game's UI Theme in code so the look is defined in one place and
# stays consistent across every menu, button and label.
#
# Godot 3 themes are verbose to author by hand; generating them keeps the design
# tokens (palette, radii, spacing, type scale) readable and tweakable at the top.

const RobotoBold = preload("res://Assets/Roboto/Roboto-Bold.ttf")
const RobotoMedium = preload("res://Assets/Roboto/Roboto-Medium.ttf")
const RobotoRegular = preload("res://Assets/Roboto/Roboto-Regular.ttf")
const RobotoBlack = preload("res://Assets/Roboto/Roboto-Black.ttf")

# --- design tokens ---------------------------------------------------------
const INK = Color(0.96, 0.97, 1.0, 1.0)
const INK_DIM = Color(0.72, 0.75, 0.82, 1.0)
const INK_FAINT = Color(0.55, 0.58, 0.66, 1.0)

const SURFACE = Color(0.09, 0.10, 0.14, 0.97)
const SURFACE_RAISED = Color(0.14, 0.16, 0.21, 0.98)
const OUTLINE = Color(1, 1, 1, 0.12)

const ACCENT = Color(0.96, 0.68, 0.15, 1.0)
const ACCENT_DEEP = Color(0.85, 0.45, 0.08, 1.0)
const DANGER = Color(0.88, 0.24, 0.24, 1.0)
const SUCCESS = Color(0.20, 0.75, 0.42, 1.0)

const RADIUS_SM = 8
const RADIUS_MD = 14
const RADIUS_LG = 22


static func make_font(size: int, weight: String = "medium", outline: int = 0) -> DynamicFont:
	var font = DynamicFont.new()
	match weight:
		"black":
			font.font_data = RobotoBlack
		"bold":
			font.font_data = RobotoBold
		"regular":
			font.font_data = RobotoRegular
		_:
			font.font_data = RobotoMedium
	font.size = size
	font.use_filter = true
	# Slight extra spacing improves legibility at small sizes on TV screens.
	font.extra_spacing_top = 1
	font.extra_spacing_bottom = 1
	if outline > 0:
		font.outline_size = outline
		font.outline_color = Color(0, 0, 0, 0.75)
	return font


static func flat_box(bg: Color, radius: int, border: int = 0, border_color: Color = OUTLINE) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	if border > 0:
		box.set_border_width_all(border)
		box.border_color = border_color
	box.anti_aliasing = true
	return box


static func button_box(bg: Color, radius: int, border_color: Color, border: int = 2) -> StyleBoxFlat:
	var box = flat_box(bg, radius, border, border_color)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	return box


# Build the complete application theme.
static func build_theme(high_contrast: bool = false) -> Theme:
	var theme = Theme.new()

	var ink = INK if not high_contrast else Color(1, 1, 1, 1)
	var surface = SURFACE if not high_contrast else Color(0.02, 0.02, 0.03, 1.0)
	var outline = OUTLINE if not high_contrast else Color(1, 1, 1, 0.55)

	var font_button = make_font(19, "bold")
	var font_label = make_font(18, "medium")

	theme.default_font = font_label

	# --- Button ---
	var normal = button_box(Color(0.17, 0.19, 0.25, 0.96), RADIUS_MD, outline)
	var hover = button_box(Color(0.25, 0.28, 0.36, 0.99), RADIUS_MD, ACCENT.linear_interpolate(outline, 0.35), 2)
	var pressed = button_box(Color(0.12, 0.13, 0.18, 1.0), RADIUS_MD, ACCENT, 2)
	var disabled = button_box(Color(0.12, 0.13, 0.16, 0.55), RADIUS_MD, Color(1, 1, 1, 0.06))
	var focus = button_box(Color(0.24, 0.27, 0.35, 0.2), RADIUS_MD, ACCENT, 3)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_font("font", "Button", font_button)
	theme.set_color("font_color", "Button", ink)
	theme.set_color("font_color_hover", "Button", Color(1, 1, 1, 1))
	theme.set_color("font_color_pressed", "Button", ACCENT)
	theme.set_color("font_color_disabled", "Button", Color(1, 1, 1, 0.28))

	# --- Panel ---
	var panel = flat_box(surface, RADIUS_LG, 2, outline)
	panel.shadow_color = Color(0, 0, 0, 0.55)
	panel.shadow_size = 18
	panel.content_margin_left = 26
	panel.content_margin_right = 26
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	theme.set_stylebox("panel", "Panel", panel)

	var container_panel = flat_box(Color(0.10, 0.11, 0.15, 0.86), RADIUS_MD, 1, outline)
	theme.set_stylebox("panel", "PanelContainer", container_panel)

	# --- Label ---
	theme.set_font("font", "Label", font_label)
	theme.set_color("font_color", "Label", ink)
	theme.set_color("font_color_shadow", "Label", Color(0, 0, 0, 0.0))

	# --- CheckBox / CheckButton ---
	theme.set_font("font", "CheckBox", font_button)
	theme.set_color("font_color", "CheckBox", ink)
	theme.set_stylebox("normal", "CheckBox", flat_box(Color(0, 0, 0, 0), RADIUS_SM))
	theme.set_stylebox("hover", "CheckBox", flat_box(Color(1, 1, 1, 0.06), RADIUS_SM))
	theme.set_stylebox("pressed", "CheckBox", flat_box(Color(1, 1, 1, 0.09), RADIUS_SM))
	theme.set_stylebox("focus", "CheckBox", flat_box(Color(0, 0, 0, 0), RADIUS_SM, 2, ACCENT))

	# --- HSlider ---
	var slider_bg = flat_box(Color(1, 1, 1, 0.13), 6)
	slider_bg.content_margin_top = 5
	slider_bg.content_margin_bottom = 5
	theme.set_stylebox("slider", "HSlider", slider_bg)
	var grabber_area = flat_box(ACCENT, 6)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", flat_box(ACCENT.lightened(0.2), 6))

	# --- ScrollContainer ---
	theme.set_stylebox("bg", "ScrollContainer", flat_box(Color(0, 0, 0, 0), 0))

	# --- Tooltip ---
	var tooltip = flat_box(Color(0.05, 0.06, 0.09, 0.97), RADIUS_SM, 1, outline)
	tooltip.content_margin_left = 10
	tooltip.content_margin_right = 10
	tooltip.content_margin_top = 6
	tooltip.content_margin_bottom = 6
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_font("font", "TooltipLabel", make_font(15, "medium"))
	theme.set_color("font_color", "TooltipLabel", ink)

	return theme


# A pill-shaped, colour-tinted button style used for the wild colour picker and
# the primary call-to-action buttons.
static func accent_button_styles(button: Button, tint: Color) -> void:
	var base = tint
	base.a = 0.92
	var normal = button_box(base.darkened(0.15), RADIUS_MD, tint.lightened(0.25), 2)
	var hover = button_box(base.lightened(0.12), RADIUS_MD, Color(1, 1, 1, 0.85), 3)
	var pressed = button_box(base.darkened(0.35), RADIUS_MD, Color(1, 1, 1, 0.9), 3)
	var focus = button_box(Color(1, 1, 1, 0.05), RADIUS_MD, Color(1, 1, 1, 0.95), 4)
	button.add_stylebox_override("normal", normal)
	button.add_stylebox_override("hover", hover)
	button.add_stylebox_override("pressed", pressed)
	button.add_stylebox_override("focus", focus)
	button.add_color_override("font_color", Color(1, 1, 1, 1))
	button.add_color_override("font_color_hover", Color(1, 1, 1, 1))
	button.add_color_override("font_color_pressed", Color(1, 1, 1, 1))
