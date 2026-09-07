extends SceneTree

const TableLayout = preload("res://Scripts/UI/TableLayout.gd")
# Layout dumper (development aid).
#
#   godot --no-window -s Tests/DumpLayout.gd
#
# Boots the real game, plays a few turns, then writes the exact transform of
# every card and HUD element to user://layout_dump.json. Tools/preview_layout.py
# turns that into a PNG mock-up so composition can be reviewed without a GPU.
#
# This is a diagnostic tool, not part of the shipped game.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")

var _game = null


func _init() -> void:
	call_deferred("_boot")


func _boot() -> void:
	var scene = load("res://Scenes/Gameplay.tscn")
	var instance = scene.instance()
	get_root().add_child(instance)
	_game = instance

	yield(self, "idle_frame")
	yield(self, "idle_frame")

	_game.settings.opponent_count = int(_cli("opponents", "1"))
	_game.settings.animation_speed = 2.0
	_game.settings.show_hints = true
	_game.settings.table_variant = int(_cli("table", "0"))
	_game.settings.save_settings()

	var width = int(_cli("width", "0"))
	var height = int(_cli("height", "0"))
	if width > 0 and height > 0:
		OS.set_window_size(Vector2(width, height))
		get_root().set_size_override(true, Vector2(width, height))
		get_root().set_size_override_stretch(true)
		yield(self, "idle_frame")
		_game._on_viewport_resized()
		yield(self, "idle_frame")

	_game._on_start_game()
	yield(_advance(2.5), "completed")

	# Play a few turns so the discard pile and hand sizes look realistic.
	for _i in range(6):
		if not _game.rules.round_active:
			break
		yield(_take_turn(), "completed")

	yield(_advance(1.0), "completed")
	_dump()
	quit(0)


# Read --key=value pairs from the command line so one script can dump any
# resolution / seat count combination.
func _cli(key: String, fallback: String) -> String:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--%s=" % key):
			return arg.split("=")[1]
	return fallback


func _advance(seconds: float) -> void:
	var elapsed = 0.0
	while elapsed < seconds:
		yield(self, "idle_frame")
		elapsed += 0.016


func _take_turn() -> void:
	var rules = _game.rules
	if rules.awaiting_color_choice:
		if rules.awaiting_color_player == 0:
			_game._on_color_selected(CardTypes.CardColor.BLUE)
		yield(_advance(0.4), "completed")
		return
	if rules.current_player != 0:
		yield(_advance(0.5), "completed")
		return
	var legal = rules.playable_cards(0)
	if legal.size() > 0:
		var card = legal[0]
		if _game._views.has(card.uid):
			_game._try_play(_game._views[card.uid])
	elif rules.can_draw(0):
		_game._on_draw_pressed()
	elif rules.can_pass(0):
		_game._on_pass_pressed()
	yield(_advance(0.5), "completed")


func _dump() -> void:
	var rules = _game.rules
	var data = {}
	data["viewport"] = _v(_game._viewport_size())
	data["deck_position"] = _v(_game._deck_position())
	data["discard_position"] = _v(_game._discard_position())
	data["active_color"] = rules.active_color
	data["active_color_name"] = CardTypes.color_name(rules.active_color)
	data["direction"] = rules.direction
	data["draw_count"] = rules.deck.draw_count()
	data["discard_count"] = rules.deck.discard_count()
	data["scores"] = rules.scores
	data["names"] = rules.player_names
	data["round"] = rules.round_number
	data["target"] = rules.rules.target_score

	var cards = []
	for player in range(rules.player_count()):
		for card in rules.hands[player]:
			if not _game._views.has(card.uid):
				continue
			var view = _game._views[card.uid]
			cards.append({
				"owner": player,
				"asset": card.asset_key(),
				"face_down": view.face_down,
				"position": _v(view.rest_position),
				"rotation": view.rest_rotation,
				"z": view.rest_z,
				"playable": view.playable,
				"focused": view.focused,
				"scale": view.scale.x
			})
	data["cards"] = cards

	var discards = []
	for view in _game._discard_views:
		if not is_instance_valid(view) or view.card_data == null:
			continue
		discards.append({
			"asset": view.card_data.asset_key(),
			"position": _v(view.position),
			"rotation": view.rotation_degrees,
			"scale": view.scale.x
		})
	data["discards"] = discards

	var hud_info = {}
	hud_info["status"] = _game.hud._status_label.text
	hud_info["deck_label"] = _game.hud._deck_label.text
	hud_info["score_label"] = _game.hud._score_label.text
	hud_info["color_label"] = _game.hud._color_label.text
	hud_info["direction"] = _game.hud._direction_icon.text
	var seats = []
	for plate in _game.hud._seat_plates:
		seats.append({
			"text": plate["label"].text,
			"position": _v(plate["panel"].rect_position),
			"size": _v(plate["panel"].rect_size)
		})
	hud_info["seats"] = seats
	data["card_scale"] = TableLayout.player_card_scale(_game._viewport_size())
	data["table_variant"] = _game.settings.table_variant

	# Real widget rectangles so the preview renderer never has to guess.
	var vp = _game._viewport_size()
	hud_info["rects"] = {
		"status": _rect_of(_game.hud._status_panel),
		"deck_counts": _rect_of(_game.hud._deck_label),
		"score": _rect_of(_game.hud._score_label),
		"color_chip": _rect_of(_game.hud._color_chip),
		"direction": _rect_of(_game.hud._direction_icon),
		"stack": _rect_of(_game.hud._stack_label)
	}
	hud_info["stack_visible"] = _game.hud._stack_label.visible
	hud_info["stack_text"] = _game.hud._stack_label.text
	data["button_column"] = TableLayout.button_column_rect(vp, 5)

	var buttons = []
	for button in _game.hud.get_buttons():
		if button == null:
			continue
		buttons.append({
			"text": button.text,
			"position": _v(button.rect_global_position),
			"size": _v(button.rect_size),
			"disabled": button.disabled,
			"visible": button.visible
		})
	hud_info["buttons"] = buttons
	data["hud"] = hud_info

	var file = File.new()
	file.open(_cli("out", "user://layout_dump.json"), File.WRITE)
	file.store_string(JSON.print(data, "  "))
	file.close()
	print("layout written to user://layout_dump.json")


func _rect_of(control) -> Dictionary:
	if control == null:
		return {}
	return {
		"position": _v(control.rect_global_position),
		"size": _v(control.rect_size)
	}


func _v(vector: Vector2) -> Dictionary:
	return {"x": vector.x, "y": vector.y}
