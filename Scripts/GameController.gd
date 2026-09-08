extends Node2D
# GameController
# --------------
# The conductor. Owns the rules engine, spawns card views, replays rule events
# as animation, drives the AI, routes input, and wires the HUD and menus.
#
# Architecture
#   GameRules (pure) --events--> GameController --> CardView / HudLayer / VFX
#
# The rules resolve instantly and completely; this layer then plays the result
# back over time. That means an animation can never desync the simulation, and
# input arriving mid-animation is simply queued behind `_busy`.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")
const CardData = preload("res://Scripts/Core/CardData.gd")
const GameRules = preload("res://Scripts/Core/GameRules.gd")
const AIPlayer = preload("res://Scripts/Core/AIPlayer.gd")

const CardView = preload("res://Scripts/UI/CardView.gd")
const TableLayout = preload("res://Scripts/UI/TableLayout.gd")
const DrawOrder = preload("res://Scripts/UI/DrawOrder.gd")
const EventPresenter = preload("res://Scripts/UI/EventPresenter.gd")
const HudLayer = preload("res://Scripts/UI/HudLayer.gd")
const MenuLayer = preload("res://Scripts/UI/MenuLayer.gd")
const ColorPickerOverlay = preload("res://Scripts/UI/ColorPicker.gd")

const AudioDirector = preload("res://Scripts/Systems/AudioDirector.gd")
const SettingsManager = preload("res://Scripts/Systems/SettingsManager.gd")
const EffectsDirector = preload("res://Scripts/Systems/EffectsDirector.gd")
const ThemeFactory = preload("res://Scripts/Systems/ThemeFactory.gd")
const ReactionDirector = preload("res://Scripts/Systems/ReactionDirector.gd")

const ASSET_DIR = "res://Assets/Uno Game Assets/"

# --- systems ---
var settings = null
var audio = null
var effects = null
var hud = null
var menus = null
var color_picker = null
var rules = null
var ai_players: Array = []

# --- view state ---
var _textures: Dictionary = {}
var _back_texture: Texture = null
var _table: Sprite = null
var _deck_stack: Node2D = null
var _shake_root: Node2D = null
var _card_root: Node2D = null

# uid -> CardView for every card currently on the table.
var _views: Dictionary = {}
var _discard_views: Array = []

var presenter = null

# Delayed opponent reactions (UNO-catch windows, AI jump-ins).
var reactions = null

var _busy: bool = false

# Safety net: if an AI turn is ever dropped (a timer lost to a scene rebuild,
# for example) the game must not freeze. This counts up while we are blocked on
# an opponent and forces the turn to be re-dispatched.
var _turn_watchdog: float = 0.0
const TURN_WATCHDOG_TIMEOUT = 6.0
var _game_active: bool = false
var _selected_index: int = 0
var _catch_available: bool = false
var _catch_target: int = -1
var _pending_wild_card = null
var _last_viewport_size: Vector2 = Vector2.ZERO
var _joy_axis_lock: int = 0
var _theme: Theme = null
var _theme_high_contrast: bool = false
var _drop_zone_radius: float = 150.0
var _ai_turn_token: int = 0


# ---------------------------------------------------------------------------
# Boot
# ---------------------------------------------------------------------------
func _ready() -> void:
	randomize()
	name = "GameController"

	_load_textures()
	_setup_systems()
	_setup_scene()
	_setup_ui()
	_connect_signals()

	get_viewport().connect("size_changed", self, "_on_viewport_resized")
	_last_viewport_size = _viewport_size()

	set_process_unhandled_input(true)
	_show_main_menu()


func _setup_systems() -> void:
	settings = SettingsManager.new()
	add_child(settings)

	audio = AudioDirector.new()
	add_child(audio)
	_apply_audio_settings()

	_theme = ThemeFactory.build_theme(settings.high_contrast)
	_theme_high_contrast = settings.high_contrast

	# Presentation layer: replays the rules engine's event queue as animation,
	# sound and HUD updates. Created last so it can see the finished systems.
	presenter = EventPresenter.new(self)

	# Delayed opponent reactions: UNO-catch windows and AI jump-ins.
	reactions = ReactionDirector.new(self)


func _setup_scene() -> void:
	# Everything that should shake lives under this node.
	_shake_root = Node2D.new()
	_shake_root.name = "ShakeRoot"
	add_child(_shake_root)

	_table = Sprite.new()
	_table.name = "Table"
	_table.centered = false
	_table.z_index = DrawOrder.TABLE
	_shake_root.add_child(_table)
	_apply_table_texture()

	_deck_stack = Node2D.new()
	_deck_stack.name = "DeckStack"
	_shake_root.add_child(_deck_stack)
	_build_deck_stack()

	_card_root = Node2D.new()
	_card_root.name = "Cards"
	_shake_root.add_child(_card_root)

	effects = EffectsDirector.new()
	_shake_root.add_child(effects)
	effects.configure(settings, _shake_root)


func _setup_ui() -> void:
	hud = HudLayer.new()
	add_child(hud)
	hud.build(settings, _theme)
	hud.apply_layout(_viewport_size())

	color_picker = ColorPickerOverlay.new()
	add_child(color_picker)
	color_picker.build(settings, _theme)

	menus = MenuLayer.new()
	add_child(menus)
	menus.build(settings, _theme)

	# Flash overlay sits above the world and the HUD, below the picker and menus.
	var flash_host = Control.new()
	flash_host.name = "FlashHost"
	flash_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_host.anchor_right = 1.0
	flash_host.anchor_bottom = 1.0
	var flash_layer = CanvasLayer.new()
	flash_layer.name = "FlashLayer"
	flash_layer.layer = DrawOrder.LAYER_FLASH
	flash_layer.add_child(flash_host)
	add_child(flash_layer)
	effects.attach_overlays(flash_host)


func _connect_signals() -> void:
	hud.connect("draw_pressed", self, "_on_draw_pressed")
	hud.connect("pass_pressed", self, "_on_pass_pressed")
	hud.connect("uno_pressed", self, "_on_uno_pressed")
	hud.connect("sort_pressed", self, "_on_sort_pressed")
	hud.connect("catch_pressed", self, "_on_catch_pressed")
	hud.connect("menu_pressed", self, "_on_menu_pressed")
	for button in hud.get_buttons():
		if button != null:
			button.connect("mouse_entered", self, "_play_cue", ["hover"])
			button.connect("pressed", self, "_play_cue", ["button"])

	menus.connect("start_game", self, "_on_start_game")
	menus.connect("resume_game", self, "_on_resume_game")
	menus.connect("restart_game", self, "_on_restart_game")
	menus.connect("quit_to_menu", self, "_show_main_menu")
	menus.connect("quit_game", self, "_on_quit_game")
	menus.connect("next_round", self, "_on_next_round")
	menus.connect("settings_changed", self, "_on_settings_changed")

	color_picker.connect("color_selected", self, "_on_color_selected")


func _load_textures() -> void:
	# Preloading every face once avoids a hitch the first time a colour appears.
	for color in CardTypes.PLAYABLE_COLORS:
		for value in range(CardTypes.CardValue.DRAW_TWO + 1):
			var key = CardTypes.asset_key(color, value)
			var path = ASSET_DIR + key + ".png"
			if ResourceLoader.exists(path):
				_textures[key] = load(path)
	for key in ["Wild", "Wild_Draw"]:
		var path = ASSET_DIR + key + ".png"
		if ResourceLoader.exists(path):
			_textures[key] = load(path)
	_back_texture = load(ASSET_DIR + "Deck.png")


func _texture_for(card) -> Texture:
	var key = card.asset_key()
	if _textures.has(key):
		return _textures[key]
	return _back_texture


# ---------------------------------------------------------------------------
# Layout helpers
# ---------------------------------------------------------------------------
func _viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _apply_table_texture() -> void:
	var path = ASSET_DIR + "Table_%d.png" % settings.table_variant
	if not ResourceLoader.exists(path):
		path = ASSET_DIR + "Table_1.png"
	_table.texture = load(path)
	_resize_table()


# The table art is 1280x720; scale it to cover any window without letterboxing.
func _resize_table() -> void:
	if _table == null or _table.texture == null:
		return
	var size = _viewport_size()
	var texture_size = _table.texture.get_size()
	var scale_factor = max(size.x / texture_size.x, size.y / texture_size.y)
	_table.scale = Vector2(scale_factor, scale_factor)
	_table.position = (size - texture_size * scale_factor) * 0.5


func _deck_position() -> Vector2:
	return TableLayout.deck_position(_viewport_size())


func _discard_position() -> Vector2:
	return TableLayout.discard_position(_viewport_size())


# Visual stack of face-down cards representing the stock.
func _build_deck_stack() -> void:
	for child in _deck_stack.get_children():
		child.queue_free()
	var card_scale = TableLayout.player_card_scale(_viewport_size())
	for i in range(DrawOrder.DECK_DEPTH):
		var sprite = Sprite.new()
		sprite.texture = _back_texture
		sprite.scale = Vector2(card_scale, card_scale)
		sprite.position = Vector2(-i * 1.5, -i * 3.0)
		sprite.z_index = DrawOrder.deck_back(i)
		_deck_stack.add_child(sprite)

	# A clickable hotspot so players can tap the deck to draw.
	var area = Area2D.new()
	area.name = "DeckHotspot"
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	var half = TableLayout.card_size(card_scale) * 0.5
	shape.extents = half
	collision.shape = shape
	area.add_child(collision)
	area.connect("input_event", self, "_on_deck_input")
	area.connect("mouse_entered", self, "_on_deck_hover", [true])
	area.connect("mouse_exited", self, "_on_deck_hover", [false])
	_deck_stack.add_child(area)

	_deck_stack.position = _deck_position()


func _on_deck_hover(entered: bool) -> void:
	if not _can_act():
		return
	var target = Vector2(1.06, 1.06) if entered else Vector2.ONE
	if entered:
		_play_cue("hover")
	var tween = create_tween()
	tween.tween_property(_deck_stack, "scale", target, settings.anim_scale(0.14)) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_deck_input(_viewport, event, _shape_idx) -> void:
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		_on_draw_pressed()


# ---------------------------------------------------------------------------
# Event presentation
# ---------------------------------------------------------------------------
# Animation, sound and HUD updates all live in EventPresenter; the controller
# owns state and input. These thin wrappers keep the call sites - and the test
# suites, which drive the same entry points the UI does - unchanged.
func _process_events(events: Array) -> void:
	presenter.process_events(events)


func _on_color_selected(color: int) -> void:
	presenter.on_color_selected(color)


func _pulse_deck() -> void:
	presenter.pulse_deck()


# ---------------------------------------------------------------------------
# Match lifecycle
# ---------------------------------------------------------------------------
func _show_main_menu() -> void:
	_game_active = false
	_busy = false
	_clear_table()
	hud.set_hud_visible(false)
	color_picker.close()
	menus.return_screen = MenuLayer.SCREEN_MAIN
	menus.show_screen(MenuLayer.SCREEN_MAIN)
	get_tree().paused = false
	audio.set_music_playing(settings.music_enabled)


func _on_start_game() -> void:
	_start_match()


func _on_restart_game() -> void:
	_start_match()


func _start_match() -> void:
	menus.hide_all()
	hud.set_hud_visible(true)
	get_tree().paused = false

	var ruleset = GameRules.Ruleset.new()
	ruleset.stacking = settings.rule_stacking
	ruleset.draw_until_playable = settings.rule_draw_until_playable
	ruleset.seven_zero = settings.rule_seven_zero
	ruleset.force_play = settings.rule_force_play
	ruleset.jump_in = settings.rule_jump_in
	ruleset.target_score = settings.target_score

	var player_count = settings.opponent_count + 1
	rules = GameRules.new(player_count, ruleset)

	# Name the seats: you plus however many CPUs.
	rules.player_names[0] = "You"
	for i in range(1, player_count):
		rules.player_names[i] = "CPU %d" % i if player_count > 2 else "CPU"

	ai_players.clear()
	for i in range(1, player_count):
		var ai = AIPlayer.new(i, settings.difficulty)
		ai.reset_memory(player_count)
		ai_players.append(ai)

	hud.setup_seats(rules.player_names)
	settings.stat_games_played += 1
	settings.save_settings()

	_clear_table()
	rules.start_match(player_count)
	_process_events(rules.consume_events())


func _on_next_round() -> void:
	menus.hide_all()
	hud.set_hud_visible(true)
	_clear_table()
	# The previous round's winner deals and leads the next one.
	rules.start_round(rules.current_player)
	_process_events(rules.consume_events())


func _clear_table() -> void:
	for uid in _views.keys():
		var view = _views[uid]
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	for view in _discard_views:
		if is_instance_valid(view):
			view.queue_free()
	_discard_views.clear()
	_selected_index = 0
	_catch_available = false
	_catch_target = -1
	_pending_wild_card = null
	# Anything scheduled against the old table (catch windows, AI jump-ins)
	# is dead; a firing timer retires on the token check.
	if reactions != null:
		reactions.invalidate()


# ---------------------------------------------------------------------------
# Card views
# ---------------------------------------------------------------------------
func _spawn_view(card, face_down: bool):
	var view = CardView.new()
	_card_root.add_child(view)
	view.setup(card, _texture_for(card), _back_texture, face_down, settings)
	view.set_card_scale(TableLayout.player_card_scale(_viewport_size()))
	view.connect("card_pressed", self, "_on_card_pressed")
	view.connect("card_hovered", self, "_on_card_hovered")
	view.connect("drag_ended", self, "_on_card_drag_ended")
	_views[card.uid] = view
	return view


# Rebuild every hand view from scratch (used after a 7-0 hand swap).
func _rebuild_all_views() -> void:
	for uid in _views.keys():
		var view = _views[uid]
		if is_instance_valid(view):
			view.queue_free()
	_views.clear()
	for player in range(rules.player_count()):
		for card in rules.hands[player]:
			var view = _spawn_view(card, player != 0)
			view.position = _anchor_for(player)
	_layout_hands(true)


func _anchor_for(player: int) -> Vector2:
	var size = _viewport_size()
	if player == 0:
		return TableLayout.player_anchor(size)
	return TableLayout.opponent_anchor(size, player - 1, rules.player_count() - 1)


# The fan slots for one hand: position, rotation and index for every card.
func _fan_layout(player: int) -> Array:
	var size = _viewport_size()
	var is_local = player == 0
	var anchor = _anchor_for(player)
	var card_scale = TableLayout.player_card_scale(size) if is_local \
		else TableLayout.opponent_card_scale(size)
	var width = TableLayout.player_fan_width(size) if is_local \
		else TableLayout.opponent_fan_width(size, rules.player_count() - 1)
	return TableLayout.fan(anchor, rules.hands[player].size(), width, is_local, card_scale)


# The slot a single card occupies in its hand's fan, including the rendered
# card scale and the DrawOrder depth it rests at. Dealt and drawn cards are
# sent straight here so their flight lands on the exact slot the layout
# solver expects - the refresh that follows then recognises the flight and
# leaves the stagger alone instead of collapsing it.
func _fan_slot(player: int, index: int) -> Dictionary:
	var size = _viewport_size()
	var card_scale = TableLayout.player_card_scale(size) if player == 0 \
		else TableLayout.opponent_card_scale(size)
	var layout = _fan_layout(player)
	if layout.empty():
		return {
			"position": _anchor_for(player),
			"rotation": 0.0,
			"z": DrawOrder.hand(0),
			"scale": card_scale
		}
	var slot = layout[clamp(index, 0, layout.size() - 1)]
	return {
		"position": slot["position"],
		"rotation": slot["rotation"],
		"z": DrawOrder.hand(slot["z"]),
		"scale": card_scale
	}


# Position every card in every hand according to the fan layout.
func _layout_hands(animated: bool = true) -> void:
	if rules == null:
		return
	var size = _viewport_size()

	for player in range(rules.player_count()):
		var hand = rules.hands[player]
		var is_local = player == 0
		var card_scale = TableLayout.player_card_scale(size) if is_local \
			else TableLayout.opponent_card_scale(size)
		var layout = _fan_layout(player)

		for i in range(hand.size()):
			var card = hand[i]
			if not _views.has(card.uid):
				continue
			var view = _views[card.uid]
			if not is_instance_valid(view) or view.is_dragging():
				continue
			var slot = layout[i]
			view.set_card_scale(card_scale)
			view.move_to(slot["position"], slot["rotation"], DrawOrder.hand(slot["z"]), animated)


# ---------------------------------------------------------------------------
# Turn flow
# ---------------------------------------------------------------------------
func _begin_turn() -> void:
	if rules == null or not rules.round_active:
		return
	if rules.awaiting_color_choice:
		return

	var player = rules.current_player
	_turn_watchdog = 0.0
	_refresh_all()

	if player == 0:
		_busy = false
		var legal = rules.playable_cards(0).size()
		if rules.pending_draw > 0:
			hud.set_status("You must answer the +%d or draw it." % rules.pending_draw)
		elif legal > 0:
			hud.set_status("Your turn - %d playable card%s." % [legal, "" if legal == 1 else "s"])
		else:
			hud.set_status("Your turn - no legal card. Draw from the deck.")
		_play_cue("turn")
	else:
		_busy = true
		hud.set_status("%s is thinking..." % rules.player_names[player])
		_ai_turn_token += 1
		var token = _ai_turn_token
		var ai = _ai_for(player)
		var timer = get_tree().create_timer(settings.anim_scale(ai.think_time()), false)
		timer.connect("timeout", self, "_run_ai_turn", [player, token])


func _ai_for(player: int):
	var index = player - 1
	if index < 0 or index >= ai_players.size():
		return ai_players[0]
	return ai_players[index]


func _run_ai_turn(player: int, token: int) -> void:
	# A restart or menu action may have invalidated this scheduled turn: a newer
	# token owns the flow, so this one simply retires.
	if token != _ai_turn_token or rules == null or not rules.round_active:
		return
	if rules.current_player != player:
		# The turn moved on while this timer was pending. Dropping out here
		# would strand the game with _busy stuck true and nothing scheduled,
		# so hand control back to the turn dispatcher instead.
		_busy = false
		_begin_turn()
		return

	var ai = _ai_for(player)

	# A missed UNO call is punished by the scheduled catch window
	# (ReactionDirector), not here - catching at the top of the turn would
	# leave the human no window at all to self-call.

	var legal = rules.playable_cards(player)
	if legal.size() > 0:
		var choice = ai.choose_card(rules, legal)
		# Declare UNO before dropping to a single card.
		if rules.hands[player].size() == 2 and ai.should_call_uno():
			rules.call_uno(player)
		var color = ai.choose_color(rules) if choice.is_wild() else -1
		rules.play_card(player, choice, color)
		_process_events(rules.consume_events())
	elif rules.can_draw(player):
		rules.draw_for_turn(player)
		_process_events(rules.consume_events())
		# Play the drawn card if it happens to be legal.
		var drawn = rules.drawn_playable_card
		if drawn != null and rules.is_playable(drawn):
			var pause = get_tree().create_timer(settings.anim_scale(0.45), false)
			pause.connect("timeout", self, "_ai_play_drawn", [player, token])
			return
		if rules.can_pass(player):
			rules.pass_turn(player)
			_process_events(rules.consume_events())
	elif rules.can_pass(player):
		rules.pass_turn(player)
		_process_events(rules.consume_events())

	_busy = false
	_begin_turn()


func _ai_play_drawn(player: int, token: int) -> void:
	if token != _ai_turn_token or rules == null or not rules.round_active:
		return
	if rules.current_player != player:
		_busy = false
		_begin_turn()
		return
	var ai = _ai_for(player)
	var card = rules.drawn_playable_card
	if card != null and rules.is_playable(card):
		if rules.hands[player].size() == 2 and ai.should_call_uno():
			rules.call_uno(player)
		var color = ai.choose_color(rules) if card.is_wild() else -1
		rules.play_card(player, card, color)
		_process_events(rules.consume_events())
	elif rules.can_pass(player):
		rules.pass_turn(player)
		_process_events(rules.consume_events())
	_busy = false
	_begin_turn()


# Is any opponent currently catchable for a missed UNO call?
func _evaluate_catch_opportunity() -> void:
	_catch_available = false
	_catch_target = -1
	if rules == null:
		return
	for i in range(1, rules.player_count()):
		if rules.uno_vulnerable[i]:
			_catch_available = true
			_catch_target = i
			break


func _can_act() -> bool:
	return rules != null and rules.round_active and not _busy \
		and rules.current_player == 0 and not rules.awaiting_color_choice \
		and not menus.is_open() and not color_picker.is_open()


# Wider gate used for card interaction: with the jump-in house rule on, an
# exact twin of the top discard is playable even off-turn. Legality itself is
# still decided by the rules engine in _try_play().
func _can_interact() -> bool:
	return rules != null and rules.round_active and not _busy \
		and not menus.is_open() and not color_picker.is_open()


# ---------------------------------------------------------------------------
# Player actions
# ---------------------------------------------------------------------------
func _on_card_pressed(view) -> void:
	if not _can_interact():
		return
	_try_play(view)


func _on_card_hovered(view) -> void:
	if _can_interact() and view.playable:
		_play_cue("hover", rand_range(0.96, 1.06))


func _on_card_drag_ended(view, global_position: Vector2) -> void:
	if not is_instance_valid(view):
		return
	if not _can_interact():
		view.cancel_drag()
		return
	# Dropping anywhere near the discard pile counts as a play.
	if global_position.distance_to(_discard_position()) <= _drop_zone_radius:
		_try_play(view)
	else:
		view.cancel_drag()
		_play_cue("select", 0.8)


func _try_play(view) -> void:
	# The view may have been culled or freed between the click and this call
	# (a fast double-play, or a round ending mid-drag).
	if not is_instance_valid(view):
		return
	var card = view.card_data
	if card == null:
		return
	var my_turn = rules.current_player == 0 and not rules.awaiting_color_choice
	# Off-turn, the only legal play is a jump-in with an exact twin of the
	# top card. Anything else is rejected with a shake but no misleading
	# "match colour/value" advice.
	if not my_turn and not rules.can_jump_in(0, card):
		view.cancel_drag()
		view.shake_invalid()
		_play_cue("error")
		return
	if not rules.is_playable(card):
		view.cancel_drag()
		view.shake_invalid()
		_play_cue("error")
		var top = rules.top_card()
		hud.set_status("Cannot play that - match %s or %s." % [
			CardTypes.color_name(rules.active_color),
			CardTypes.value_name(top.value) if top != null else "the pile"
		])
		return

	_busy = true
	rules.play_card(0, card)
	_process_events(rules.consume_events())

	if rules.awaiting_color_choice:
		# The picker opens on a timer; keep input locked until it resolves.
		return
	_busy = false
	_begin_turn()


func _on_draw_pressed() -> void:
	if not _can_act() or not rules.can_draw(0):
		return
	_busy = true
	rules.draw_for_turn(0)
	_process_events(rules.consume_events())
	_pulse_deck()
	_busy = false

	if rules.current_player != 0:
		_begin_turn()
	else:
		if rules.drawn_playable_card != null:
			hud.set_status("You drew a playable card - play it or pass.")
		else:
			hud.set_status("Nothing playable. Press PASS to end your turn.")
		_refresh_all()


func _on_pass_pressed() -> void:
	if not _can_act() or not rules.can_pass(0):
		return
	rules.pass_turn(0)
	_process_events(rules.consume_events())
	_begin_turn()


func _on_uno_pressed() -> void:
	if rules == null or not rules.round_active:
		return
	if rules.call_uno(0):
		_process_events(rules.consume_events())
	else:
		_play_cue("error")


func _on_catch_pressed() -> void:
	if rules == null or not _catch_available or _catch_target < 0:
		return
	if rules.catch_uno(0, _catch_target):
		_process_events(rules.consume_events())
		_refresh_all()
	else:
		# The opening vanished between the refresh and the click (the target
		# drew or self-called). Say so instead of failing silently.
		_play_cue("error")
		hud.set_status("Too late - %s is safe." % rules.player_names[_catch_target])
		_refresh_all()


func _on_sort_pressed() -> void:
	if rules == null or rules.hands[0].size() < 2:
		return
	rules.hands[0].sort_custom(self, "_compare_cards")
	_selected_index = 0
	_layout_hands(true)
	_play_cue("select")
	hud.set_status("Hand sorted by colour and value.")


static func _compare_cards(a, b) -> bool:
	if a.color == b.color:
		return a.value < b.value
	return a.color < b.color


func _on_menu_pressed() -> void:
	_toggle_pause()


func _toggle_pause() -> void:
	if not _game_active:
		return
	if menus.is_open():
		if menus.current_screen == MenuLayer.SCREEN_PAUSE:
			_on_resume_game()
		else:
			menus.show_screen(MenuLayer.SCREEN_PAUSE)
	else:
		get_tree().paused = true
		menus.return_screen = MenuLayer.SCREEN_PAUSE
		menus.show_screen(MenuLayer.SCREEN_PAUSE)


func _on_resume_game() -> void:
	menus.hide_all()
	get_tree().paused = false
	_refresh_all()


func _on_quit_game() -> void:
	settings.save_settings()
	get_tree().quit()


# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------
func _refresh_all() -> void:
	if rules == null:
		return
	_layout_hands(true)
	_refresh_card_states()
	_refresh_hud()
	if reactions != null:
		reactions.evaluate()


func _refresh_card_states() -> void:
	var my_turn = rules.current_player == 0 and rules.round_active \
		and not rules.awaiting_color_choice and not _busy
	var hints = settings.show_hints
	# Under the jump-in rule an exact twin of the top card stays playable (and
	# highlighted) even while another seat is on turn.
	var jump_ready = not my_turn and rules.round_active \
		and not rules.awaiting_color_choice and rules.rules.jump_in

	for i in range(rules.hands[0].size()):
		var card = rules.hands[0][i]
		if not _views.has(card.uid):
			continue
		var view = _views[card.uid]
		if not is_instance_valid(view):
			continue
		var playable = rules.is_playable(card) if my_turn else rules.can_jump_in(0, card)
		view.set_interactive(my_turn or playable)
		view.set_playable(playable and hints)
		view.set_focused((my_turn or jump_ready) and i == _selected_index)

	# Opponent cards are never interactive.
	for player in range(1, rules.player_count()):
		for card in rules.hands[player]:
			if not _views.has(card.uid):
				continue
			var view = _views[card.uid]
			if is_instance_valid(view):
				view.set_interactive(false)
				view.set_playable(false)


func _refresh_hud() -> void:
	hud.set_active_color(rules.active_color, false)
	hud.set_direction(rules.direction)
	hud.set_pending_stack(rules.pending_draw)
	hud.set_deck_counts(rules.deck.draw_count(), rules.deck.discard_count())
	hud.set_scores(rules.player_names, rules.scores, rules.rules.target_score, rules.round_number)

	# Recompute the catch opening from live rules state every refresh so the
	# CATCH button appears (and disappears) exactly when it is legal.
	_evaluate_catch_opportunity()

	var my_turn = rules.current_player == 0 and rules.round_active and not _busy
	# UNO may also be called late: after dropping to one card without calling,
	# the call is still legal (and the button pulses) until an opponent
	# catches you or you play again.
	var uno_legal = rules.round_active and \
		((my_turn and not rules.awaiting_color_choice and rules.hands[0].size() == 2) \
		or rules.uno_vulnerable[0])
	hud.set_button_states(
		my_turn and rules.can_draw(0),
		my_turn and rules.can_pass(0),
		uno_legal,
		rules.hands[0].size() >= 2,
		_catch_available
	)

	# Seat plates are placed by TableLayout so they never collide with a fan.
	var size = _viewport_size()
	var opponents = rules.player_count() - 1
	for i in range(rules.player_count()):
		var text = "%s   %d" % [rules.player_names[i], rules.hand_size(i)]
		if rules.uno_vulnerable[i]:
			text += "   !"
		hud.update_seat(i, TableLayout.seat_plate_position(size, i, opponents), text,
			rules.current_player == i and rules.round_active,
			rules.hand_size(i) == 1)


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
# Watchdog tick. Only ever fires if an opponent turn was somehow dropped; in
# normal play the turn is re-dispatched long before this expires.
func _process(delta: float) -> void:
	if rules == null or not rules.round_active or not _busy:
		_turn_watchdog = 0.0
		return
	if rules.awaiting_color_choice or rules.current_player == 0:
		_turn_watchdog = 0.0
		return

	_turn_watchdog += delta
	if _turn_watchdog < TURN_WATCHDOG_TIMEOUT:
		return

	push_warning("Turn watchdog fired for seat %d - re-dispatching." % rules.current_player)
	_turn_watchdog = 0.0
	_busy = false
	_begin_turn()


func _unhandled_input(event) -> void:
	# Release the analogue stick lock when it returns to centre.
	if event is InputEventJoypadMotion and event.axis == 0 and abs(event.axis_value) < 0.35:
		_joy_axis_lock = 0
		return

	if _is_cancel(event):
		_handle_cancel()
		get_tree().set_input_as_handled()
		return

	if menus.is_open() or color_picker.is_open():
		return
	if not _can_interact():
		return

	if _is_left(event):
		_move_selection(-1)
	elif _is_right(event):
		_move_selection(1)
	elif _is_accept(event):
		_play_selected()
	elif _is_key(event, KEY_D) or _is_pad(event, JOY_XBOX_X):
		_on_draw_pressed()
	elif _is_key(event, KEY_P) or _is_pad(event, JOY_XBOX_Y):
		_on_pass_pressed()
	elif _is_key(event, KEY_U) or _is_pad(event, JOY_R):
		_on_uno_pressed()
	elif _is_key(event, KEY_C):
		_on_catch_pressed()
	elif _is_key(event, KEY_S) or _is_pad(event, JOY_L):
		_on_sort_pressed()
	else:
		return
	get_tree().set_input_as_handled()


func _handle_cancel() -> void:
	if color_picker.is_open():
		# The colour choice is mandatory - nudge instead of closing.
		_play_cue("error")
		return
	if menus.is_open():
		match menus.current_screen:
			MenuLayer.SCREEN_SETTINGS, MenuLayer.SCREEN_HELP, MenuLayer.SCREEN_STATS:
				menus.show_screen(menus.return_screen)
			MenuLayer.SCREEN_PAUSE:
				_on_resume_game()
		return
	_toggle_pause()


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


func _move_selection(direction: int) -> void:
	var count = rules.hands[0].size()
	if count == 0:
		return
	_selected_index = int(posmod(_selected_index + direction, count))
	_play_cue("select", 1.0 + _selected_index * 0.01)
	_refresh_card_states()


func _play_selected() -> void:
	var count = rules.hands[0].size()
	if count == 0:
		return
	_selected_index = int(clamp(_selected_index, 0, count - 1))
	var card = rules.hands[0][_selected_index]
	if _views.has(card.uid):
		_try_play(_views[card.uid])


# ---------------------------------------------------------------------------
# Settings / viewport
# ---------------------------------------------------------------------------
func _on_settings_changed() -> void:
	_apply_audio_settings()
	_apply_table_texture()
	# The high-contrast toggle rebuilds the theme and re-applies it to the
	# three UI roots live, so it takes effect without a restart.
	if _theme != null and _theme_high_contrast != settings.high_contrast:
		_theme_high_contrast = settings.high_contrast
		_theme = ThemeFactory.build_theme(settings.high_contrast)
		hud.apply_theme(_theme)
		menus.apply_theme(_theme)
		color_picker.apply_theme(_theme)
	if rules != null:
		_refresh_all()
	color_picker.refresh_labels()
	hud.set_active_color(rules.active_color if rules != null else 0, false)


func _apply_audio_settings() -> void:
	audio.master_volume = settings.master_volume
	audio.sfx_volume = settings.sfx_volume
	audio.music_volume = settings.music_volume
	audio.sfx_enabled = settings.sfx_enabled and settings.sfx_volume > 0.0
	audio.apply_volumes()
	audio.set_music_playing(settings.music_enabled and settings.music_volume > 0.0)


func _play_cue(cue: String, pitch: float = 1.0) -> void:
	if audio != null:
		audio.play(cue, pitch)


func _on_viewport_resized() -> void:
	var size = _viewport_size()
	if size == _last_viewport_size:
		return
	_last_viewport_size = size
	_resize_table()
	_build_deck_stack()
	hud.apply_layout(size)
	if rules == null:
		return
	# Snap rather than animate so a window drag does not look like a shuffle.
	_layout_hands(false)
	var discard_scale = TableLayout.player_card_scale(size)
	for view in _discard_views:
		if is_instance_valid(view):
			view.set_card_scale(discard_scale)
			view.position = _discard_position() + view.discard_offset
	_refresh_hud()


func _notification(what: int) -> void:
	# Persist settings when the window closes or the app is backgrounded.
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST or what == MainLoop.NOTIFICATION_WM_GO_BACK_REQUEST:
		if settings != null:
			settings.save_settings()
