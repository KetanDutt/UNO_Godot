extends TextureRect

const STARTING_HAND_SIZE = 7
const CARD_SPACING = 54.0
const MIN_CARD_SPACING = 30.0
const AI_THINK_TIME = 0.75
const COLORS = ["Red", "Yellow", "Green", "Blue"]
const VALUES = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "Skip", "Reverse", "Draw"]
const ACTION_VALUES = ["Skip", "Reverse", "Draw", "Wild_Draw"]
const COLOR_MAP = {
	"Red": Color(0.9, 0.12, 0.1, 1),
	"Yellow": Color(1.0, 0.82, 0.08, 1),
	"Green": Color(0.08, 0.65, 0.22, 1),
	"Blue": Color(0.08, 0.33, 0.9, 1),
	"Wild": Color(0.15, 0.15, 0.18, 1)
}

const CardObject = preload("res://Scenes/Card.tscn")
const Decktexture = preload("res://Assets/Uno Game Assets/Deck.png")
const RobotoMedium = preload("res://Assets/Roboto/Roboto-Medium.ttf")
const RobotoBold = preload("res://Assets/Roboto/Roboto-Bold.ttf")

var CardTextures: Dictionary = {}
var PlayerCards: Array = []
var AICards: Array = []
var CenterCards: Array = []
var DiscardData: Array = []
var DrawPile: Array = []

var PlayerTurn: bool = false
var drawn_this_turn: bool = false
var busy: bool = false
var pending_wild_choice: bool = false
var pending_wild_card = null
var active_color: String = ""
var turn_count: int = 0

var status_label: Label = null
var counts_label: Label = null
var color_label: Label = null
var color_chip: ColorRect = null
var pass_button: Button = null
var draw_button: Button = null
var color_picker: Control = null
var sfx_players: Dictionary = {}
var sfx_streams: Dictionary = {}

func _ready() -> void:
	randomize()
	loadTextures()
	setup_runtime_ui()
	setup_audio()
	get_viewport().connect("size_changed", self, "_on_viewport_size_changed")
	start_new_game()

func start_new_game() -> void:
	clear_table()
	DrawPile = build_uno_deck()
	DrawPile.shuffle()
	PlayerCards = []
	AICards = []
	CenterCards = []
	DiscardData = []
	PlayerTurn = false
	drawn_this_turn = false
	busy = true
	pending_wild_choice = false
	pending_wild_card = null
	active_color = ""
	turn_count = 1
	$ColorRect.visible = false
	if color_picker != null:
		color_picker.visible = false

	for _i in range(STARTING_HAND_SIZE):
		PlayerCards.append(spawn_card_from_deck(false))
		AICards.append(spawn_card_from_deck(true))

	var first_card = draw_starting_discard()
	var center_card = create_card_node(first_card, false)
	center_card.position = get_center_position()
	center_card.rotation_degrees = rand_range(-7, 7)
	center_card.set_interaction_enabled(false)
	CenterCards.append(center_card)
	DiscardData.append(first_card)
	active_color = str(first_card["color"])

	reposition_all_hands(false)
	busy = false
	PlayerTurn = true
	set_status("Your turn. Match the color, number, or play a wild card.")
	play_sfx("start")
	update_ui()
	animate_turn_banner()

func clear_table() -> void:
	for card in PlayerCards + AICards + CenterCards:
		if is_instance_valid(card):
			card.queue_free()
	PlayerCards.clear()
	AICards.clear()
	CenterCards.clear()
	DiscardData.clear()

func build_uno_deck() -> Array:
	var deck = []
	for color in COLORS:
		deck.append(make_card_data(color, "0"))
		for i in range(2):
			for n in range(1, 10):
				deck.append(make_card_data(color, str(n)))
			deck.append(make_card_data(color, "Skip"))
			deck.append(make_card_data(color, "Reverse"))
			deck.append(make_card_data(color, "Draw"))
	for _i in range(4):
		deck.append(make_wild_data("Wild"))
		deck.append(make_wild_data("Wild_Draw"))
	return deck

func make_card_data(color: String, value: String) -> Dictionary:
	var key = color + "_" + value
	return {"color": color, "number": value, "texture_key": key, "texture": CardTextures[key]}

func make_wild_data(value: String) -> Dictionary:
	return {"color": "Wild", "number": value, "texture_key": value, "texture": CardTextures[value]}

func draw_starting_discard() -> Dictionary:
	for _i in range(80):
		var data = take_card_data()
		if data.empty():
			break
		if str(data["color"]) != "Wild" and not ACTION_VALUES.has(str(data["number"])):
			return data
		DrawPile.insert(0, data)
		DrawPile.shuffle()
	return take_card_data()

func take_card_data() -> Dictionary:
	if DrawPile.empty():
		reshuffle_discard_into_deck()
	if DrawPile.empty():
		return {}
	return DrawPile.pop_back()

func reshuffle_discard_into_deck() -> void:
	if DiscardData.size() <= 1:
		return
	var top_data = DiscardData[DiscardData.size() - 1]
	DrawPile = DiscardData.slice(0, DiscardData.size() - 2)
	DiscardData = [top_data]
	DrawPile.shuffle()

	var top_card = CenterCards[CenterCards.size() - 1]
	for i in range(CenterCards.size() - 1):
		if is_instance_valid(CenterCards[i]):
			CenterCards[i].queue_free()
	CenterCards = [top_card]
	set_status("The discard pile was shuffled back into the deck.")

func create_card_node(card_data: Dictionary, face_down: bool):
	var card = CardObject.instance()
	card.set_card_data(card_data, face_down, Decktexture)
	add_child(card)
	return card

func spawn_card_from_deck(face_down: bool):
	var data = take_card_data()
	if data.empty():
		return null
	return create_card_node(data, face_down)

func draw_card_to_hand(hand: Array, face_down: bool):
	var card = spawn_card_from_deck(face_down)
	if card == null:
		set_status("No cards are left to draw.")
		return null
	hand.append(card)
	card.position = get_deck_position()
	card.rotation_degrees = rand_range(-4, 4)
	play_sfx("draw")
	return card

func CardClicked(playingCard) -> void:
	if busy or pending_wild_choice or not PlayerTurn:
		return
	if not PlayerCards.has(playingCard):
		return
	if isValidMove(playingCard, get_top_card()):
		PlayerCards.erase(playingCard)
		drawn_this_turn = false
		playingCard.set_interaction_enabled(false)
		set_status("You played " + describe_card(playingCard) + ".")
		repositionCards(PlayerCards, get_player_hand_center(), true)
		PlayCard(playingCard)
	else:
		playingCard.animate_feedback_invalid()
		play_sfx("error")
		set_status("That card cannot be played. Match " + active_color + " or " + get_top_card().number + ".")

func AI_Turn() -> void:
	if busy or PlayerTurn:
		return
	busy = true
	update_ui()
	set_status("Computer is thinking...")
	yield(get_tree().create_timer(AI_THINK_TIME), "timeout")

	var validCards = findValidCards(AICards, get_top_card())
	if validCards.size() > 0:
		var selectedCard = choose_ai_card(validCards)
		AICards.erase(selectedCard)
		selectedCard.set_interaction_enabled(false)
		if selectedCard.color == "Wild":
			active_color = choose_ai_color()
		set_status("Computer played " + describe_card(selectedCard) + ".")
		repositionCards(AICards, get_ai_hand_center(), true)
		busy = false
		PlayCard(selectedCard)
	else:
		var drawn = draw_card_to_hand(AICards, true)
		repositionCards(AICards, get_ai_hand_center(), true)
		yield(get_tree().create_timer(0.35), "timeout")
		if drawn != null and isValidMove(drawn, get_top_card()):
			AICards.erase(drawn)
			drawn.set_interaction_enabled(false)
			if drawn.color == "Wild":
				active_color = choose_ai_color()
			set_status("Computer drew and played " + describe_card(drawn) + ".")
			repositionCards(AICards, get_ai_hand_center(), true)
			busy = false
			PlayCard(drawn)
		else:
			busy = false
			set_status("Computer drew a card and passed.")
			complete_turn(null)

func choose_ai_card(validCards: Array):
	var best_card = validCards[0]
	var best_score = -999
	for card in validCards:
		var score = 0
		if card.number == "Wild_Draw":
			score += 40
		elif card.number == "Draw":
			score += 30
		elif card.number == "Skip" or card.number == "Reverse":
			score += 20
		elif card.color == active_color:
			score += 8
		score += int(rand_range(0, 6))
		if score > best_score:
			best_score = score
			best_card = card
	return best_card

func choose_ai_color() -> String:
	var counts = {"Red": 0, "Yellow": 0, "Green": 0, "Blue": 0}
	for card in AICards:
		if counts.has(card.color):
			counts[card.color] += 1
	var best_color = "Red"
	var best_count = -1
	for color in COLORS:
		if counts[color] > best_count:
			best_count = counts[color]
			best_color = color
	return best_color

func PlayCard(playingCard) -> void:
	busy = true
	update_playable_hints()
	if playingCard.is_face_down:
		playingCard.reveal()

	if playingCard.color != "Wild":
		active_color = playingCard.color

	var center = get_center_position()
	var randomOffset = Vector2(rand_range(-14, 14), rand_range(-10, 10))
	var randomRotation = rand_range(-15, 15)
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(playingCard, "position", playingCard.position, center + randomOffset, 0.38, Tween.TRANS_BACK, Tween.EASE_OUT)
	tween.interpolate_property(playingCard, "rotation_degrees", playingCard.rotation_degrees, randomRotation, 0.38, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.interpolate_property(playingCard, "scale", playingCard.scale, Vector2(0.4, 0.4), 0.2, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.connect("tween_all_completed", self, "_on_play_card_animation_done", [tween, playingCard])
	tween.start()

	playingCard.raise()
	CenterCards.append(playingCard)
	DiscardData.append(card_data_from_node(playingCard))
	play_sfx("play")
	spawn_card_burst(center + randomOffset, get_color_value(active_color if active_color != "" else playingCard.color))

func _on_play_card_animation_done(tween: Tween, card) -> void:
	if is_instance_valid(tween):
		tween.queue_free()
	busy = false
	if card.color == "Wild" and PlayerTurn:
		pending_wild_choice = true
		pending_wild_card = card
		show_color_picker()
		return
	complete_turn(card)

func complete_turn(card) -> void:
	if check_for_winner():
		return

	var current_player_is_player = PlayerTurn
	var keep_turn = false
	if card != null:
		var value = str(card.number)
		if value == "Draw":
			draw_penalty(not current_player_is_player, 2)
			keep_turn = true
		elif value == "Wild_Draw":
			draw_penalty(not current_player_is_player, 4)
			keep_turn = true
		elif value == "Skip" or value == "Reverse":
			keep_turn = true
			set_status(("You" if current_player_is_player else "Computer") + " skipped the opponent.")

	if not keep_turn:
		PlayerTurn = not PlayerTurn
	drawn_this_turn = false
	turn_count += 1
	update_ui()
	animate_turn_banner()

	if not PlayerTurn:
		AI_Turn()
	else:
		if card != null and card.color == "Wild":
			set_status("Computer chose " + active_color + ". Your turn.")
		elif not player_has_valid_card():
			set_status("Your turn. No playable card is visible; draw from the deck.")
		else:
			set_status("Your turn.")

func draw_penalty(target_is_player: bool, count: int) -> void:
	var hand = PlayerCards if target_is_player else AICards
	for _i in range(count):
		draw_card_to_hand(hand, not target_is_player)
	repositionCards(hand, get_player_hand_center() if target_is_player else get_ai_hand_center(), true)
	set_status(("You draw " if target_is_player else "Computer draws ") + str(count) + " cards.")

func check_for_winner() -> bool:
	if PlayerCards.size() == 0:
		win(true)
		return true
	if AICards.size() == 0:
		win(false)
		return true
	return false

func win(playerWon: bool) -> void:
	busy = true
	PlayerTurn = false
	update_playable_hints()
	var result = "You Won!" if playerWon else "Computer Won"
	$ColorRect/Label.text = result + "\nTurns: " + str(turn_count) + "\nCards left - You: " + str(PlayerCards.size()) + "  Computer: " + str(AICards.size())
	$ColorRect.visible = true
	$ColorRect.raise()
	play_sfx("win")
	spawn_confetti()

func isValidMove(playingCard, centerCard) -> bool:
	if playingCard == null or centerCard == null:
		return false
	if playingCard.color == "Wild":
		return true
	if playingCard.color == active_color:
		return true
	if playingCard.number == centerCard.number:
		return true
	return false

func findValidCards(playerDeck: Array, centerCard) -> Array:
	var valid = []
	for card in playerDeck:
		if isValidMove(card, centerCard):
			valid.append(card)
	return valid

func player_has_valid_card() -> bool:
	return findValidCards(PlayerCards, get_top_card()).size() > 0

func get_top_card():
	if CenterCards.empty():
		return null
	return CenterCards[CenterCards.size() - 1]

func card_data_from_node(card) -> Dictionary:
	return {"color": card.color, "number": card.number, "texture_key": card.texture_key, "texture": card.face_texture}

func describe_card(card) -> String:
	if card == null:
		return "a card"
	if card.color == "Wild":
		return "Wild Draw Four" if card.number == "Wild_Draw" else "Wild"
	var value = "Draw Two" if card.number == "Draw" else card.number
	return card.color + " " + value

func reposition_all_hands(animated: bool = true) -> void:
	repositionCards(PlayerCards, get_player_hand_center(), animated)
	repositionCards(AICards, get_ai_hand_center(), animated)

func repositionCards(cards: Array, centerScreenPoint: Vector2, animated: bool = true) -> void:
	if cards.empty():
		return
	var available_width = max(260.0, get_viewport().get_visible_rect().size.x - 260.0)
	var spacing = CARD_SPACING
	if cards.size() > 1:
		spacing = clamp(available_width / float(cards.size() - 1), MIN_CARD_SPACING, CARD_SPACING)
	var totalWidth = (cards.size() - 1) * spacing
	var startingPosition = centerScreenPoint - Vector2(totalWidth / 2.0, 0)

	for i in range(cards.size()):
		var card = cards[i]
		if card == null:
			continue
		var target = startingPosition + Vector2(i * spacing, 0)
		card.set_home_position(target)
		card.z_index = i
		card.rotation_degrees = lerp(-5, 5, float(i) / max(1, cards.size() - 1))
		if animated:
			var tween = Tween.new()
			add_child(tween)
			tween.interpolate_property(card, "position", card.position, target, 0.22, Tween.TRANS_QUAD, Tween.EASE_OUT)
			tween.connect("tween_all_completed", tween, "queue_free")
			tween.start()
		else:
			card.position = target
	update_playable_hints()

func update_playable_hints() -> void:
	for card in PlayerCards:
		card.set_interaction_enabled(PlayerTurn and not busy and not pending_wild_choice)
		card.set_playable(PlayerTurn and not busy and not pending_wild_choice and isValidMove(card, get_top_card()))
	for card in AICards:
		card.set_interaction_enabled(false)
		card.set_playable(false)
	for card in CenterCards:
		if is_instance_valid(card):
			card.set_interaction_enabled(false)
			card.set_playable(false)

func setup_runtime_ui() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Deck.mouse_filter = Control.MOUSE_FILTER_IGNORE
	draw_button = $Deck/Button
	draw_button.mouse_filter = Control.MOUSE_FILTER_STOP
	draw_button.text = "DRAW"
	draw_button.hint_tooltip = "Draw one card. If it can be played, you may play it or pass."

	pass_button = Button.new()
	pass_button.name = "PassButton"
	pass_button.mouse_filter = Control.MOUSE_FILTER_STOP
	pass_button.text = "PASS"
	pass_button.rect_min_size = Vector2(100, 48)
	pass_button.anchor_left = 0.0
	pass_button.anchor_top = 0.5
	pass_button.anchor_right = 0.0
	pass_button.anchor_bottom = 0.5
	pass_button.margin_left = 100
	pass_button.margin_top = 220
	pass_button.margin_right = 200
	pass_button.margin_bottom = 268
	pass_button.connect("pressed", self, "_on_Pass_Button_pressed")
	$Deck.add_child(pass_button)

	var hud = Control.new()
	hud.name = "HUD"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.anchor_right = 1.0
	hud.anchor_bottom = 1.0
	add_child(hud)

	status_label = create_label(22, true)
	status_label.name = "StatusLabel"
	status_label.anchor_left = 0.5
	status_label.anchor_right = 0.5
	status_label.margin_left = -390
	status_label.margin_top = 22
	status_label.margin_right = 390
	status_label.margin_bottom = 76
	status_label.align = Label.ALIGN_CENTER
	hud.add_child(status_label)

	counts_label = create_label(18, false)
	counts_label.name = "CountsLabel"
	counts_label.anchor_left = 1.0
	counts_label.anchor_right = 1.0
	counts_label.margin_left = -310
	counts_label.margin_top = 22
	counts_label.margin_right = -24
	counts_label.margin_bottom = 96
	counts_label.align = Label.ALIGN_RIGHT
	hud.add_child(counts_label)

	color_chip = ColorRect.new()
	color_chip.name = "ColorChip"
	color_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_chip.anchor_left = 0.5
	color_chip.anchor_right = 0.5
	color_chip.margin_left = -80
	color_chip.margin_top = 92
	color_chip.margin_right = 80
	color_chip.margin_bottom = 126
	hud.add_child(color_chip)

	color_label = create_label(16, true)
	color_label.name = "ColorLabel"
	color_label.anchor_right = 1.0
	color_label.anchor_bottom = 1.0
	color_label.align = Label.ALIGN_CENTER
	color_label.valign = Label.VALIGN_CENTER
	color_chip.add_child(color_label)

	create_color_picker()
	hud.raise()
	$Deck.raise()
	$ColorRect.raise()

func create_label(size: int, bold: bool) -> Label:
	var label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font = DynamicFont.new()
	font.size = size
	font.font_data = RobotoBold if bold else RobotoMedium
	label.add_font_override("font", font)
	label.add_color_override("font_color", Color(1, 1, 1, 1))
	label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	label.add_constant_override("shadow_offset_x", 2)
	label.add_constant_override("shadow_offset_y", 2)
	return label

func create_color_picker() -> void:
	color_picker = ColorRect.new()
	color_picker.name = "ColorPicker"
	color_picker.mouse_filter = Control.MOUSE_FILTER_STOP
	color_picker.visible = false
	color_picker.anchor_left = 0.5
	color_picker.anchor_top = 0.5
	color_picker.anchor_right = 0.5
	color_picker.anchor_bottom = 0.5
	color_picker.margin_left = -240
	color_picker.margin_top = -130
	color_picker.margin_right = 240
	color_picker.margin_bottom = 130
	color_picker.color = Color(0.04, 0.04, 0.05, 0.92)
	add_child(color_picker)

	var title = create_label(24, true)
	title.text = "Choose a color"
	title.anchor_right = 1.0
	title.margin_top = 18
	title.margin_bottom = 58
	title.align = Label.ALIGN_CENTER
	color_picker.add_child(title)

	for i in range(COLORS.size()):
		var color_name = COLORS[i]
		var button = Button.new()
		button.text = color_name.to_upper()
		button.anchor_left = 0.5
		button.anchor_top = 0.5
		button.anchor_right = 0.5
		button.anchor_bottom = 0.5
		button.margin_left = -210 + i * 105
		button.margin_top = -12
		button.margin_right = -120 + i * 105
		button.margin_bottom = 58
		button.modulate = get_color_value(color_name)
		button.connect("pressed", self, "_on_color_selected", [color_name])
		color_picker.add_child(button)

func show_color_picker() -> void:
	pending_wild_choice = true
	color_picker.visible = true
	color_picker.raise()
	set_status("Wild card played. Choose the next color.")
	update_ui()

func _on_color_selected(color_name: String) -> void:
	if not pending_wild_choice:
		return
	active_color = color_name
	pending_wild_choice = false
	color_picker.visible = false
	set_status("You chose " + color_name + ".")
	spawn_card_burst(get_center_position(), get_color_value(color_name))
	complete_turn(pending_wild_card)
	pending_wild_card = null

func update_ui() -> void:
	update_playable_hints()
	if counts_label != null:
		counts_label.text = "Computer: " + str(AICards.size()) + " cards\nYou: " + str(PlayerCards.size()) + " cards\nDeck: " + str(DrawPile.size())
	if color_chip != null:
		color_chip.color = get_color_value(active_color)
	if color_label != null:
		color_label.text = "ACTIVE: " + active_color.to_upper()
	if draw_button != null:
		draw_button.disabled = busy or pending_wild_choice or not PlayerTurn or drawn_this_turn
	if pass_button != null:
		pass_button.disabled = busy or pending_wild_choice or not PlayerTurn or not drawn_this_turn
	if has_node("HUD"):
		$HUD.raise()
	$Deck.raise()
	if color_picker != null and color_picker.visible:
		color_picker.raise()
	$ColorRect.raise()

func set_status(message: String) -> void:
	if status_label != null:
		status_label.text = message
		pulse_node(status_label, 1.0, 1.045, 0.16)

func animate_turn_banner() -> void:
	if color_chip != null:
		pulse_node(color_chip, 1.0, 1.09, 0.18)

func pulse_node(node, from_scale: float, to_scale: float, duration: float) -> void:
	if not (node is Control):
		return
	var tween = Tween.new()
	add_child(tween)
	node.rect_pivot_offset = node.rect_size / 2.0
	tween.interpolate_property(node, "rect_scale", Vector2(from_scale, from_scale), Vector2(to_scale, to_scale), duration, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.interpolate_property(node, "rect_scale", Vector2(to_scale, to_scale), Vector2(from_scale, from_scale), duration, Tween.TRANS_QUAD, Tween.EASE_IN, duration)
	tween.connect("tween_all_completed", tween, "queue_free")
	tween.start()

func spawn_card_burst(pos: Vector2, burst_color: Color) -> void:
	var particles = CPUParticles2D.new()
	particles.position = pos
	particles.amount = 36
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.randomness = 0.65
	particles.initial_velocity = 170
	particles.spread = 180
	particles.scale_amount = 4
	particles.color = burst_color
	add_child(particles)
	particles.emitting = true
	yield(get_tree().create_timer(1.0), "timeout")
	if is_instance_valid(particles):
		particles.queue_free()

func spawn_confetti() -> void:
	for color_name in COLORS:
		spawn_card_burst(Vector2(rand_range(220, 1060), rand_range(120, 560)), get_color_value(color_name))

func get_color_value(color_name: String) -> Color:
	if COLOR_MAP.has(color_name):
		return COLOR_MAP[color_name]
	return COLOR_MAP["Wild"]

func get_center_position() -> Vector2:
	return get_viewport().get_visible_rect().size / 2.0

func get_player_hand_center() -> Vector2:
	var size = get_viewport().get_visible_rect().size
	return size / 2.0 + Vector2(0, size.y * 0.39)

func get_ai_hand_center() -> Vector2:
	var size = get_viewport().get_visible_rect().size
	return size / 2.0 + Vector2(0, -size.y * 0.39)

func get_deck_position() -> Vector2:
	var size = get_viewport().get_visible_rect().size
	return Vector2(150, size.y / 2.0 - 60)

func loadTextures() -> void:
	CardTextures.clear()
	for color in COLORS:
		for value in VALUES:
			var path = "res://Assets/Uno Game Assets/" + color + "_" + value + ".png"
			if ResourceLoader.exists(path):
				CardTextures[color + "_" + value] = load(path)
	CardTextures["Wild"] = load("res://Assets/Uno Game Assets/Wild.png")
	CardTextures["Wild_Draw"] = load("res://Assets/Uno Game Assets/Wild_Draw.png")

func setup_audio() -> void:
	sfx_streams["start"] = make_tone(440, 0.08, 0.18)
	sfx_streams["draw"] = make_tone(260, 0.07, 0.15)
	sfx_streams["play"] = make_tone(660, 0.09, 0.18)
	sfx_streams["error"] = make_tone(130, 0.13, 0.2)
	sfx_streams["win"] = make_chime()
	for name in sfx_streams.keys():
		var player = AudioStreamPlayer.new()
		player.name = "SFX_" + name
		player.volume_db = -10
		add_child(player)
		sfx_players[name] = player

func play_sfx(name: String) -> void:
	if not sfx_players.has(name) or not sfx_streams.has(name):
		return
	var player = sfx_players[name]
	player.stream = sfx_streams[name]
	player.play()

func make_tone(freq: float, seconds: float, volume: float) -> AudioStreamSample:
	var mix_rate = 22050
	var sample_count = int(mix_rate * seconds)
	var bytes = PoolByteArray()
	for i in range(sample_count):
		var t = float(i) / float(mix_rate)
		var envelope = 1.0 - (float(i) / float(sample_count))
		var sample = int(sin(PI * 2.0 * freq * t) * 32767.0 * volume * envelope)
		if sample < 0:
			sample += 65536
		bytes.append(sample & 255)
		bytes.append((sample >> 8) & 255)
	var stream = AudioStreamSample.new()
	stream.format = AudioStreamSample.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func make_chime() -> AudioStreamSample:
	var mix_rate = 22050
	var seconds = 0.55
	var sample_count = int(mix_rate * seconds)
	var bytes = PoolByteArray()
	for i in range(sample_count):
		var t = float(i) / float(mix_rate)
		var envelope = 1.0 - (float(i) / float(sample_count))
		var tone = sin(PI * 2.0 * 523.25 * t) + sin(PI * 2.0 * 659.25 * t) + sin(PI * 2.0 * 783.99 * t)
		var sample = int((tone / 3.0) * 32767.0 * 0.2 * envelope)
		if sample < 0:
			sample += 65536
		bytes.append(sample & 255)
		bytes.append((sample >> 8) & 255)
	var stream = AudioStreamSample.new()
	stream.format = AudioStreamSample.FORMAT_16_BITS
	stream.mix_rate = mix_rate
	stream.stereo = false
	stream.data = bytes
	return stream

func _on_Draw_Button_pressed() -> void:
	if busy or pending_wild_choice or not PlayerTurn or drawn_this_turn:
		return
	var card = draw_card_to_hand(PlayerCards, false)
	drawn_this_turn = true
	repositionCards(PlayerCards, get_player_hand_center(), true)
	if card != null and isValidMove(card, get_top_card()):
		set_status("You drew a playable card. Play it, or press PASS.")
	else:
		set_status("You drew a card. Press PASS to end your turn.")
	update_ui()

func _on_Pass_Button_pressed() -> void:
	if busy or pending_wild_choice or not PlayerTurn or not drawn_this_turn:
		return
	set_status("You passed.")
	complete_turn(null)

func _on_Replay_Button_pressed() -> void:
	start_new_game()

func _on_viewport_size_changed() -> void:
	reposition_all_hands(false)
	if get_top_card() != null:
		get_top_card().position = get_center_position()
