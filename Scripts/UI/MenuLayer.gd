extends CanvasLayer
# MenuLayer
# ---------
# Every full-screen overlay: main menu, pause, settings, how-to-play, stats,
# round summary and the match-over screen.
#
# Each screen is a Panel built from containers so it reflows at any resolution.
# Screens fade/scale in and out, focus is grabbed automatically for gamepad and
# TV-remote play, and the whole layer processes while the tree is paused.

signal start_game
signal resume_game
signal restart_game
signal quit_to_menu
signal quit_game
signal next_round
signal settings_changed
signal screen_changed(screen)

const ThemeFactory = preload("res://Scripts/Systems/ThemeFactory.gd")
const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const AIPlayer = preload("res://Scripts/Core/AIPlayer.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")

const SCREEN_NONE = ""
const SCREEN_MAIN = "main"
const SCREEN_PAUSE = "pause"
const SCREEN_SETTINGS = "settings"
const SCREEN_HELP = "help"
const SCREEN_STATS = "stats"
const SCREEN_ROUND = "round"
const SCREEN_MATCH = "match"

var settings = null
# How-to-play copy, kept out of the builder so the layout code stays readable.
const HELP_GOAL = \
	"Be the first to empty your hand. The winner scores the value of every card still " + \
	"held by the other players. First to the target score wins the match."
const HELP_PLAY = \
	"Play a card that matches the active colour or the value on top of the discard pile. " + \
	"Wild cards can be played any time and let you name the next colour. Click, tap or " + \
	"drag a card onto the pile to play it."
const HELP_ACTIONS = \
	"Skip - the next player loses their turn.\n" + \
	"Reverse - flips the direction of play; heads-up it acts as a Skip.\n" + \
	"Draw Two - the next player draws two and is skipped.\n" + \
	"Wild - choose the next colour.\n" + \
	"Wild Draw Four - choose the colour; the next player draws four and is skipped."
const HELP_DRAWING = \
	"If you cannot or will not play, press DRAW. You may play the drawn card if it is " + \
	"legal, otherwise press PASS to end your turn."
const HELP_UNO = \
	"When you are about to reach one card, press UNO! If you drop to one card without " + \
	"calling it, your opponent can CATCH you and you draw two. You can also catch them."
const HELP_SCORING = \
	"Number cards score their face value. Skip, Reverse and Draw Two score 20. Wild and " + \
	"Wild Draw Four score 50."
const HELP_HOUSE_RULES = \
	"The SETTINGS screen can switch on five optional house rules:\n" + \
	"Stack +2 / +4 - the victim may answer a draw card with their own and pass the " + \
	"growing pile along.\n" + \
	"Draw until playable - drawing keeps going until something legal turns up.\n" + \
	"Seven-Zero - a 7 swaps hands, a 0 rotates every hand.\n" + \
	"Force play - you must play when you hold a legal card.\n" + \
	"Jump-in - a card identical to the top of the pile (same colour AND value) may be " + \
	"played out of turn by anyone, including you. Play then resumes from the jumper."
const HELP_CONTROLS = \
	"Remote / gamepad - D-pad moves the selection, Enter or A confirms, Back pauses " + \
	"and goes back. In your hand, Up or Down leaves the cards for the action buttons; " + \
	"keep pressing Up to return to your cards. When CATCH! appears it is selected for " + \
	"you automatically. The colour wheel and every menu use the same D-pad controls.\n" + \
	"Mouse / touch - click or drag a card onto the pile. Hover to preview.\n" + \
	"Keyboard - Left/Right select, Enter or Space plays, D draws, P passes, U calls " + \
	"UNO, C catches, S sorts, Esc pauses."

var current_screen: String = SCREEN_NONE

var _root: Control = null
var _dim: ColorRect = null
var _screens: Dictionary = {}
var _first_focus: Dictionary = {}
var _theme: Theme = null

# Settings widgets that need refreshing when values change externally.
var _difficulty_button: Button = null
var _opponents_button: Button = null
var _target_button: Button = null
var _table_button: Button = null
var _speed_button: Button = null
var _rule_buttons: Dictionary = {}
var _toggle_buttons: Dictionary = {}
var _sliders: Dictionary = {}

var _round_title: Label = null
var _round_body: Label = null
var _round_button: Button = null
var _match_title: Label = null
var _match_body: Label = null
var _stats_body: Label = null

# ScrollContainers that must respond to the D-pad, keyed by screen id.
var _screen_scrolls: Dictionary = {}

var _transition_tween = null


func _ready() -> void:
	name = "MenuLayer"
	layer = 20
	pause_mode = Node.PAUSE_MODE_PROCESS
	# The layer answers Back itself while the tree is paused (the
	# GameController's input is frozen then) and pages scrollable screens.
	set_process_unhandled_input(true)


func build(settings_ref, theme: Theme) -> void:
	settings = settings_ref
	_theme = theme

	var root = Control.new()
	root.name = "Root"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = theme
	add_child(root)
	_root = root

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.anchor_right = 1.0
	_dim.anchor_bottom = 1.0
	_dim.color = Color(0.02, 0.03, 0.05, 0.0)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_dim)

	_build_main(root)
	_build_pause(root)
	_build_settings(root)
	_build_help(root)
	_build_stats(root)
	_build_round_summary(root)
	_build_match_over(root)

	# Keep focused controls visible inside every scroll area.
	for screen_id in _screen_scrolls.keys():
		_bind_focus_follow(_screen_scrolls[screen_id])

	hide_all(true)


# Connect every focusable control inside a scroll area so D-pad focus
# movement scrolls the area to keep it on screen.
func _bind_focus_follow(scroll: ScrollContainer) -> void:
	var stack = [scroll]
	while not stack.empty():
		var node = stack.pop_back()
		if node is Control and node.focus_mode != Control.FOCUS_NONE \
				and not node.is_connected("focus_entered", self, "_on_scroll_child_focused"):
			node.connect("focus_entered", self, "_on_scroll_child_focused", [scroll])
		for child in node.get_children():
			stack.append(child)


func _on_scroll_child_focused(scroll: ScrollContainer) -> void:
	call_deferred("_reveal_focused", scroll)


# Godot 3 ScrollContainers do not reliably pull a newly focused row into view,
# so scroll just enough to keep the focused control on screen.
func _reveal_focused(scroll: ScrollContainer) -> void:
	if not is_instance_valid(scroll) or not scroll.visible:
		return
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner == null or not is_instance_valid(focus_owner):
		return
	var ancestor = focus_owner.get_parent()
	while ancestor != null and ancestor != scroll:
		ancestor = ancestor.get_parent()
	if ancestor != scroll:
		return
	var top = focus_owner.global_position.y - scroll.global_position.y + scroll.get_v_scroll()
	var bottom = top + focus_owner.rect_size.y
	var v = scroll.get_v_scroll()
	var view_h = scroll.rect_size.y
	if top < v:
		# Range clamps the value to [min, max] itself, no scrollbar lookup.
		scroll.set_v_scroll(top - 10.0)
	elif bottom > v + view_h:
		scroll.set_v_scroll(bottom - view_h + 10.0)


# Swap the theme live (the high-contrast toggle), without rebuilding widgets.
func apply_theme(theme: Theme) -> void:
	if _root != null:
		_root.theme = theme


# ---------------------------------------------------------------------------
# Screen construction helpers
# ---------------------------------------------------------------------------
func _make_panel(id: String, root: Control, width: float, height: float) -> Panel:
	var panel = Panel.new()
	panel.name = id.capitalize() + "Panel"
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.margin_left = -width * 0.5
	panel.margin_right = width * 0.5
	panel.margin_top = -height * 0.5
	panel.margin_bottom = height * 0.5
	panel.rect_pivot_offset = Vector2(width * 0.5, height * 0.5)
	root.add_child(panel)
	_screens[id] = panel
	return panel


func _make_vbox(panel: Panel, separation: int = 12) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.name = "Content"
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.margin_left = 30
	box.margin_right = -30
	box.margin_top = 26
	box.margin_bottom = -26
	box.add_constant_override("separation", separation)
	panel.add_child(box)
	return box


func _make_title(text: String, size: int = 44) -> Label:
	var label = Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.add_font_override("font", ThemeFactory.make_font(size, "black", 3))
	label.add_color_override("font_color", ThemeFactory.ACCENT)
	return label


func _make_body(text: String, size: int = 17) -> Label:
	var label = Label.new()
	label.text = text
	label.align = Label.ALIGN_CENTER
	label.autowrap = true
	label.add_font_override("font", ThemeFactory.make_font(size, "medium"))
	label.add_color_override("font_color", ThemeFactory.INK_DIM)
	return label


func _make_button(text: String, method: String, args: Array = []) -> Button:
	var button = Button.new()
	button.text = text
	button.rect_min_size = Vector2(0, 46)
	button.focus_mode = Control.FOCUS_ALL
	button.connect("pressed", self, method, args)
	return button


func _spacer(height: int) -> Control:
	var control = Control.new()
	control.rect_min_size = Vector2(0, height)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return control


# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------
func _build_main(root: Control) -> void:
	var panel = _make_panel(SCREEN_MAIN, root, 460, 560)
	var box = _make_vbox(panel)

	box.add_child(_make_title("UNO", 82))
	var subtitle = _make_body("Classic card duelling against a thinking opponent.")
	box.add_child(subtitle)
	box.add_child(_spacer(14))

	var start = _make_button("PLAY", "_on_start")
	ThemeFactory.accent_button_styles(start, ThemeFactory.ACCENT)
	start.rect_min_size = Vector2(0, 56)
	box.add_child(start)
	_first_focus[SCREEN_MAIN] = start

	box.add_child(_make_button("SETTINGS", "_on_show", [SCREEN_SETTINGS]))
	box.add_child(_make_button("HOW TO PLAY", "_on_show", [SCREEN_HELP]))
	box.add_child(_make_button("STATISTICS", "_on_show", [SCREEN_STATS]))

	# Quitting is meaningless in a browser tab, so hide it on HTML5.
	if OS.get_name() != "HTML5":
		box.add_child(_make_button("QUIT", "_on_quit_game"))

	var hint = _make_body("D-pad to navigate  -  Enter to confirm  -  Back to pause", 14)
	hint.add_color_override("font_color", ThemeFactory.INK_FAINT)
	box.add_child(_spacer(6))
	box.add_child(hint)

	# Small print: the running version, sourced from project.godot.
	if ProjectSettings.has_setting("application/config/version"):
		var version = str(ProjectSettings.get_setting("application/config/version"))
		if version != "":
			var label = _make_body("v" + version, 13)
			label.add_color_override("font_color", ThemeFactory.INK_FAINT)
			box.add_child(label)


# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------
func _build_pause(root: Control) -> void:
	var panel = _make_panel(SCREEN_PAUSE, root, 420, 480)
	var box = _make_vbox(panel)

	box.add_child(_make_title("PAUSED", 46))
	box.add_child(_spacer(10))

	var resume = _make_button("RESUME", "_on_resume")
	ThemeFactory.accent_button_styles(resume, ThemeFactory.ACCENT)
	box.add_child(resume)
	_first_focus[SCREEN_PAUSE] = resume

	box.add_child(_make_button("SETTINGS", "_on_show", [SCREEN_SETTINGS]))
	box.add_child(_make_button("HOW TO PLAY", "_on_show", [SCREEN_HELP]))
	box.add_child(_make_button("RESTART MATCH", "_on_restart"))
	box.add_child(_make_button("MAIN MENU", "_on_quit_to_menu"))


# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------
func _build_settings(root: Control) -> void:
	var panel = _make_panel(SCREEN_SETTINGS, root, 640, 640)
	var outer = _make_vbox(panel, 8)
	outer.add_child(_make_title("SETTINGS", 40))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	outer.add_child(scroll)
	_screen_scrolls[SCREEN_SETTINGS] = scroll

	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_constant_override("separation", 9)
	scroll.add_child(box)

	box.add_child(_section_header("AUDIO"))
	_sliders["master"] = _add_slider(
		box, "Master volume", settings.master_volume, "_on_volume_changed", ["master"])
	_sliders["sfx"] = _add_slider(box, "Sound effects", settings.sfx_volume, "_on_volume_changed", ["sfx"])
	_sliders["music"] = _add_slider(box, "Music", settings.music_volume, "_on_volume_changed", ["music"])

	box.add_child(_section_header("GAME"))
	_difficulty_button = _add_cycle(box, "Difficulty", "_on_cycle_difficulty")
	_opponents_button = _add_cycle(box, "Opponents", "_on_cycle_opponents")
	_target_button = _add_cycle(box, "Score to win", "_on_cycle_target")

	box.add_child(_section_header("HOUSE RULES"))
	_rule_buttons["stacking"] = _add_toggle(box, "Stack +2 / +4", "_on_toggle_rule", ["stacking"],
		"Let the victim answer a draw card with their own, passing the pile along.")
	_rule_buttons["draw_until"] = _add_toggle(box, "Draw until playable", "_on_toggle_rule", ["draw_until"],
		"Keep drawing until a legal card turns up instead of drawing exactly one.")
	_rule_buttons["seven_zero"] = _add_toggle(box, "Seven-Zero", "_on_toggle_rule", ["seven_zero"],
		"Playing a 7 swaps hands; playing a 0 rotates every hand around the table.")
	_rule_buttons["force_play"] = _add_toggle(box, "Force play", "_on_toggle_rule", ["force_play"],
		"You must play a legal card if you hold one - no drawing to stall.")
	_rule_buttons["jump_in"] = _add_toggle(box, "Jump-in", "_on_toggle_rule", ["jump_in"],
		"A card identical to the top of the pile may be played out of turn - by anyone.")

	box.add_child(_section_header("PRESENTATION"))
	_speed_button = _add_cycle(box, "Animation speed", "_on_cycle_speed")
	_table_button = _add_cycle(box, "Table design", "_on_cycle_table")
	_toggle_buttons["hints"] = _add_toggle(box, "Highlight playable cards", "_on_toggle_display", ["hints"])
	_toggle_buttons["glyphs"] = _add_toggle(box, "Colour-blind glyphs", "_on_toggle_display", ["glyphs"],
		"Add a distinct shape to every colour indicator.")
	_toggle_buttons["shake"] = _add_toggle(box, "Screen shake", "_on_toggle_display", ["shake"])
	_toggle_buttons["particles"] = _add_toggle(box, "Particle effects", "_on_toggle_display", ["particles"])
	_toggle_buttons["contrast"] = _add_toggle(box, "High contrast UI", "_on_toggle_display", ["contrast"])

	box.add_child(_spacer(8))
	box.add_child(_make_button("RESET TO DEFAULTS", "_on_reset_defaults"))

	var back = _make_button("BACK", "_on_back")
	ThemeFactory.accent_button_styles(back, ThemeFactory.ACCENT)
	outer.add_child(back)
	_first_focus[SCREEN_SETTINGS] = back


func _section_header(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_font_override("font", ThemeFactory.make_font(14, "black"))
	label.add_color_override("font_color", ThemeFactory.ACCENT)
	return label


# A labelled row with a control on the right.
func _row(parent: VBoxContainer, label_text: String, tooltip: String = "") -> HBoxContainer:
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 10)
	if tooltip != "":
		row.hint_tooltip = tooltip
	parent.add_child(row)

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_font_override("font", ThemeFactory.make_font(17, "medium"))
	if tooltip != "":
		label.hint_tooltip = tooltip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(label)
	return row


func _add_slider(parent: VBoxContainer, label_text: String, value: float,
		method: String, args: Array) -> HSlider:
	var row = _row(parent, label_text)
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.rect_min_size = Vector2(230, 30)
	slider.focus_mode = Control.FOCUS_ALL
	slider.connect("value_changed", self, method, args)
	row.add_child(slider)
	return slider


func _add_cycle(parent: VBoxContainer, label_text: String, method: String) -> Button:
	var row = _row(parent, label_text)
	var button = Button.new()
	button.rect_min_size = Vector2(230, 40)
	button.focus_mode = Control.FOCUS_ALL
	button.connect("pressed", self, method)
	row.add_child(button)
	return button


func _add_toggle(parent: VBoxContainer, label_text: String, method: String,
		args: Array, tooltip: String = "") -> Button:
	var row = _row(parent, label_text, tooltip)
	var button = Button.new()
	button.rect_min_size = Vector2(230, 40)
	button.focus_mode = Control.FOCUS_ALL
	button.connect("pressed", self, method, args)
	row.add_child(button)
	return button


# ---------------------------------------------------------------------------
# How to play
# ---------------------------------------------------------------------------
func _build_help(root: Control) -> void:
	var panel = _make_panel(SCREEN_HELP, root, 760, 620)
	var outer = _make_vbox(panel, 10)
	outer.add_child(_make_title("HOW TO PLAY", 40))

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	outer.add_child(scroll)
	_screen_scrolls[SCREEN_HELP] = scroll

	var box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_constant_override("separation", 6)
	scroll.add_child(box)

	box.add_child(_help_heading("Goal"))
	box.add_child(_help_text(HELP_GOAL))

	box.add_child(_help_heading("Playing a card"))
	box.add_child(_help_text(HELP_PLAY))

	box.add_child(_help_heading("Action cards"))
	box.add_child(_help_text(HELP_ACTIONS))

	box.add_child(_help_heading("Drawing"))
	box.add_child(_help_text(HELP_DRAWING))

	box.add_child(_help_heading("Calling UNO"))
	box.add_child(_help_text(HELP_UNO))

	box.add_child(_help_heading("Scoring"))
	box.add_child(_help_text(HELP_SCORING))

	box.add_child(_help_heading("House rules"))
	box.add_child(_help_text(HELP_HOUSE_RULES))

	box.add_child(_help_heading("Controls"))
	box.add_child(_help_text(HELP_CONTROLS))

	var back = _make_button("BACK", "_on_back")
	ThemeFactory.accent_button_styles(back, ThemeFactory.ACCENT)
	outer.add_child(back)
	_first_focus[SCREEN_HELP] = back


func _help_heading(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_font_override("font", ThemeFactory.make_font(19, "black"))
	label.add_color_override("font_color", ThemeFactory.ACCENT)
	return label


func _help_text(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.autowrap = true
	label.add_font_override("font", ThemeFactory.make_font(16, "medium"))
	label.add_color_override("font_color", ThemeFactory.INK_DIM)
	return label


# ---------------------------------------------------------------------------
# Statistics
# ---------------------------------------------------------------------------
func _build_stats(root: Control) -> void:
	var panel = _make_panel(SCREEN_STATS, root, 520, 480)
	var box = _make_vbox(panel)
	box.add_child(_make_title("STATISTICS", 40))

	_stats_body = Label.new()
	_stats_body.align = Label.ALIGN_CENTER
	_stats_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_body.add_font_override("font", ThemeFactory.make_font(19, "medium"))
	box.add_child(_stats_body)

	box.add_child(_make_button("RESET STATISTICS", "_on_reset_stats"))
	var back = _make_button("BACK", "_on_back")
	ThemeFactory.accent_button_styles(back, ThemeFactory.ACCENT)
	box.add_child(back)
	_first_focus[SCREEN_STATS] = back


func _refresh_stats() -> void:
	if _stats_body == null or settings == null:
		return
	var lines = [
		"Matches played        %d" % settings.stat_games_played,
		"Matches won           %d" % settings.stat_games_won,
		"Match win rate        %.0f%%" % settings.win_rate(),
		"Rounds played         %d" % settings.stat_rounds_played,
		"Rounds won            %d" % settings.stat_rounds_won,
		"Round win rate        %.0f%%" % settings.round_win_rate(),
		"Cards played          %d" % settings.stat_cards_played,
		"UNO calls             %d" % settings.stat_uno_calls,
		"Best round score      %d" % settings.stat_best_score
	]
	_stats_body.text = PoolStringArray(lines).join("\n\n")


# ---------------------------------------------------------------------------
# Round summary
# ---------------------------------------------------------------------------
func _build_round_summary(root: Control) -> void:
	var panel = _make_panel(SCREEN_ROUND, root, 560, 460)
	var box = _make_vbox(panel)

	_round_title = _make_title("ROUND OVER", 44)
	box.add_child(_round_title)

	_round_body = Label.new()
	_round_body.align = Label.ALIGN_CENTER
	_round_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_round_body.add_font_override("font", ThemeFactory.make_font(19, "medium"))
	box.add_child(_round_body)

	_round_button = _make_button("NEXT ROUND", "_on_next_round")
	ThemeFactory.accent_button_styles(_round_button, ThemeFactory.ACCENT)
	_round_button.rect_min_size = Vector2(0, 54)
	box.add_child(_round_button)
	box.add_child(_make_button("MAIN MENU", "_on_quit_to_menu"))
	_first_focus[SCREEN_ROUND] = _round_button


func show_round_summary(won: bool, points: int, lines: Array) -> void:
	_round_title.text = "ROUND WON" if won else "ROUND LOST"
	_round_title.add_color_override("font_color", ThemeFactory.SUCCESS if won else ThemeFactory.DANGER)
	var body = []
	if won:
		body.append("You scored %d points" % points)
	else:
		body.append("Opponent scored %d points" % points)
	body.append("")
	for line in lines:
		body.append(line)
	_round_body.text = PoolStringArray(body).join("\n")
	show_screen(SCREEN_ROUND)


# ---------------------------------------------------------------------------
# Match over
# ---------------------------------------------------------------------------
func _build_match_over(root: Control) -> void:
	var panel = _make_panel(SCREEN_MATCH, root, 560, 480)
	var box = _make_vbox(panel)

	_match_title = _make_title("VICTORY", 60)
	box.add_child(_match_title)

	_match_body = Label.new()
	_match_body.align = Label.ALIGN_CENTER
	_match_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_match_body.add_font_override("font", ThemeFactory.make_font(20, "medium"))
	box.add_child(_match_body)

	var again = _make_button("PLAY AGAIN", "_on_restart")
	ThemeFactory.accent_button_styles(again, ThemeFactory.ACCENT)
	again.rect_min_size = Vector2(0, 54)
	box.add_child(again)
	box.add_child(_make_button("MAIN MENU", "_on_quit_to_menu"))
	_first_focus[SCREEN_MATCH] = again


func show_match_over(won: bool, lines: Array) -> void:
	_match_title.text = "VICTORY!" if won else "DEFEAT"
	_match_title.add_color_override("font_color", ThemeFactory.SUCCESS if won else ThemeFactory.DANGER)
	_match_body.text = PoolStringArray(lines).join("\n")
	show_screen(SCREEN_MATCH)


# ---------------------------------------------------------------------------
# Screen transitions
# ---------------------------------------------------------------------------
func show_screen(id: String) -> void:
	if not _screens.has(id):
		return

	var previous = current_screen
	current_screen = id

	if id == SCREEN_SETTINGS:
		refresh_settings_labels()
	elif id == SCREEN_STATS:
		_refresh_stats()

	for key in _screens.keys():
		var panel = _screens[key]
		if key == id:
			continue
		panel.visible = false

	var target = _screens[id]
	target.visible = true
	get_node("Root").visible = true

	var d = settings.anim_scale(0.26) if settings != null else 0.26
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()

	# Only fade the dimmer in when coming from nothing, so screen-to-screen
	# navigation does not flicker the background.
	if previous == SCREEN_NONE:
		_dim.color.a = 0.0
		_transition_tween = create_tween()
		_transition_tween.tween_property(_dim, "color:a", 0.78, d)

	target.modulate = Color(1, 1, 1, 0)
	target.rect_scale = Vector2(0.94, 0.94)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(target, "modulate:a", 1.0, d)
	tween.tween_property(target, "rect_scale", Vector2.ONE, d) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	_grab_focus_for(id)
	emit_signal("screen_changed", id)


func _grab_focus_for(id: String) -> void:
	if not _first_focus.has(id):
		return
	var control = _first_focus[id]
	if is_instance_valid(control):
		# One frame of delay so the control is laid out before focusing.
		yield(get_tree(), "idle_frame")
		if is_instance_valid(control) and current_screen == id:
			control.grab_focus()


func hide_all(immediate: bool = false) -> void:
	current_screen = SCREEN_NONE
	if immediate:
		for key in _screens.keys():
			_screens[key].visible = false
		_dim.color.a = 0.0
		get_node("Root").visible = false
		emit_signal("screen_changed", SCREEN_NONE)
		return

	var d = settings.anim_scale(0.2) if settings != null else 0.2
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.tween_property(_dim, "color:a", 0.0, d)
	_transition_tween.tween_callback(self, "_finish_hide")
	emit_signal("screen_changed", SCREEN_NONE)


func _finish_hide() -> void:
	for key in _screens.keys():
		_screens[key].visible = false
	get_node("Root").visible = false


func is_open() -> bool:
	return current_screen != SCREEN_NONE


# ---------------------------------------------------------------------------
# Settings callbacks
# ---------------------------------------------------------------------------
func refresh_settings_labels() -> void:
	if settings == null:
		return
	if _difficulty_button != null:
		_difficulty_button.text = AIPlayer.DIFFICULTY_NAMES[settings.difficulty]
	if _opponents_button != null:
		var plural = "" if settings.opponent_count == 1 else "s"
		_opponents_button.text = "%d opponent%s" % [settings.opponent_count, plural]
	if _target_button != null:
		_target_button.text = "%d points" % settings.target_score
	if _table_button != null:
		_table_button.text = "Table %d" % (settings.table_variant + 1)
	if _speed_button != null:
		_speed_button.text = _speed_name(settings.animation_speed)

	_set_toggle(_rule_buttons, "stacking", settings.rule_stacking)
	_set_toggle(_rule_buttons, "draw_until", settings.rule_draw_until_playable)
	_set_toggle(_rule_buttons, "seven_zero", settings.rule_seven_zero)
	_set_toggle(_rule_buttons, "force_play", settings.rule_force_play)
	_set_toggle(_rule_buttons, "jump_in", settings.rule_jump_in)

	_set_toggle(_toggle_buttons, "hints", settings.show_hints)
	_set_toggle(_toggle_buttons, "glyphs", settings.colorblind_glyphs)
	_set_toggle(_toggle_buttons, "shake", settings.screen_shake)
	_set_toggle(_toggle_buttons, "particles", settings.particles_enabled)
	_set_toggle(_toggle_buttons, "contrast", settings.high_contrast)

	if _sliders.has("master"):
		_sliders["master"].value = settings.master_volume
	if _sliders.has("sfx"):
		_sliders["sfx"].value = settings.sfx_volume
	if _sliders.has("music"):
		_sliders["music"].value = settings.music_volume


func _set_toggle(collection: Dictionary, key: String, value: bool) -> void:
	if not collection.has(key):
		return
	var button = collection[key]
	button.text = "ON" if value else "OFF"
	button.add_color_override("font_color", ThemeFactory.SUCCESS if value else ThemeFactory.INK_FAINT)


func _speed_name(speed: float) -> String:
	if speed <= 0.75:
		return "Relaxed"
	if speed <= 1.05:
		return "Normal"
	if speed <= 1.55:
		return "Fast"
	return "Instant"


func _on_volume_changed(value: float, channel: String) -> void:
	match channel:
		"master":
			settings.master_volume = value
		"sfx":
			settings.sfx_volume = value
		"music":
			settings.music_volume = value
	settings.save_settings()
	emit_signal("settings_changed")


func _on_cycle_difficulty() -> void:
	settings.difficulty = (settings.difficulty + 1) % 3
	_commit_settings()


func _on_cycle_opponents() -> void:
	settings.opponent_count = settings.opponent_count % 3 + 1
	_commit_settings()


func _on_cycle_target() -> void:
	var options = [100, 200, 300, 500, 750]
	var index = options.find(settings.target_score)
	settings.target_score = options[(index + 1) % options.size()]
	_commit_settings()


func _on_cycle_table() -> void:
	settings.table_variant = (settings.table_variant + 1) % 5
	_commit_settings()


func _on_cycle_speed() -> void:
	var options = [0.65, 1.0, 1.4, 2.0]
	var index = 0
	for i in range(options.size()):
		if abs(options[i] - settings.animation_speed) < 0.01:
			index = i
			break
	settings.animation_speed = options[(index + 1) % options.size()]
	_commit_settings()


func _on_toggle_rule(key: String) -> void:
	match key:
		"stacking":
			settings.rule_stacking = not settings.rule_stacking
		"draw_until":
			settings.rule_draw_until_playable = not settings.rule_draw_until_playable
		"seven_zero":
			settings.rule_seven_zero = not settings.rule_seven_zero
		"force_play":
			settings.rule_force_play = not settings.rule_force_play
		"jump_in":
			settings.rule_jump_in = not settings.rule_jump_in
	_commit_settings()


func _on_toggle_display(key: String) -> void:
	match key:
		"hints":
			settings.show_hints = not settings.show_hints
		"glyphs":
			settings.colorblind_glyphs = not settings.colorblind_glyphs
		"shake":
			settings.screen_shake = not settings.screen_shake
		"particles":
			settings.particles_enabled = not settings.particles_enabled
		"contrast":
			settings.high_contrast = not settings.high_contrast
	_commit_settings()


func _commit_settings() -> void:
	settings.save_settings()
	refresh_settings_labels()
	emit_signal("settings_changed")


func _on_reset_defaults() -> void:
	settings.reset_to_defaults()
	refresh_settings_labels()
	emit_signal("settings_changed")


func _on_reset_stats() -> void:
	settings.reset_stats()
	_refresh_stats()


# ---------------------------------------------------------------------------
# Navigation callbacks
# ---------------------------------------------------------------------------
func _on_start() -> void:
	emit_signal("start_game")


func _on_resume() -> void:
	emit_signal("resume_game")


func _on_restart() -> void:
	emit_signal("restart_game")


func _on_quit_to_menu() -> void:
	emit_signal("quit_to_menu")


func _on_quit_game() -> void:
	emit_signal("quit_game")


func _on_next_round() -> void:
	emit_signal("next_round")


func _on_show(id: String) -> void:
	show_screen(id)


# Back returns to whichever screen makes sense for the current context.
var return_screen: String = SCREEN_MAIN


func _on_back() -> void:
	show_screen(return_screen)


# ---------------------------------------------------------------------------
# TV remote / gamepad
# ---------------------------------------------------------------------------
func _unhandled_input(event) -> void:
	if current_screen == SCREEN_NONE:
		return
	# While paused the GameController receives no input, so the Back button
	# has to be answered from here: it closes sub-screens and resumes play.
	if get_tree().paused and _is_remote_press(event, "ui_cancel"):
		_handle_remote_back()
		get_tree().set_input_as_handled()
		return
	# D-pad paging of scrollable screens. This only reaches unhandled input
	# when focus navigation had no further neighbour to jump to, so it never
	# fights the engine's own D-pad focus movement.
	var scroll = _screen_scrolls.get(current_screen, null)
	if scroll != null and scroll.visible:
		var step = max(72.0, scroll.rect_size.y * 0.8)
		if _is_remote_press(event, "ui_up"):
			scroll.set_v_scroll(scroll.get_v_scroll() - step)
			get_tree().set_input_as_handled()
		elif _is_remote_press(event, "ui_down"):
			scroll.set_v_scroll(scroll.get_v_scroll() + step)
			get_tree().set_input_as_handled()


func _handle_remote_back() -> void:
	match current_screen:
		SCREEN_SETTINGS, SCREEN_HELP, SCREEN_STATS:
			show_screen(return_screen)
		SCREEN_PAUSE:
			emit_signal("resume_game")


# Edge-triggered press from a D-pad: keyboard arrow or a hat button. Held
# analogue sticks are deliberately excluded - they fire every frame and would
# page-scroll past the content before it can be read.
func _is_remote_press(event, action: String) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.is_action(action)
	if event is InputEventJoypadButton:
		return event.pressed and event.is_action(action)
	return false
