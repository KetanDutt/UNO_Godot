extends TextureRect

const DECK_SIZE = 10
const CARD_SPACING = 50

const Colors = ["Red","Yellow","Green","Blue"]
const Numbers = [0,1,2,3,4,5,6,7,8,9,"Skip"]
const CardObject = preload("res://Scenes/Card.tscn")
const Decktexture = preload("res://Assets/Uno Game Assets/Deck.png")

var tween = Tween.new()
var CardTextures = {}
var PlayerCards = []
var AICards = []
var CenterCards = []
var PlayerTurn = false

func _ready():
	randomize()
	loadTextures()
	
	var screenSize = get_viewport().get_visible_rect().size
	
	for n in DECK_SIZE:
		PlayerCards.append(SpawnCard())
	for n in DECK_SIZE:
		AICards.append(SpawnCard(true))
	
	CenterCards.append(SpawnCard())
	CenterCards[0].position = screenSize/2
	
	repositionCards(PlayerCards,screenSize/2 + Vector2(0,screenSize.y*.4))
	repositionCards(AICards,screenSize/2 + Vector2(0,-screenSize.y*.4))
	
	PlayerTurn = true
	$ColorRect.visible = false
	pass
	
func CardClicked(playingCard):
	if(!PlayerTurn):
		return
	
	var centerCardIndex = CenterCards.size() - 1
	
	if isValidMove(playingCard, CenterCards[centerCardIndex]):
		PlayerCards.erase(playingCard)
		PlayCard(playingCard)
	else:
		# Handle invalid move, e.g., show a message, play a sound, etc.
		print("Invalid move!"+"\tplayingCard: "+playingCard.color+"_"+playingCard.number+"\tCenterCards:"+CenterCards[centerCardIndex].color+"_"+CenterCards[centerCardIndex].number)

func AI_Turn():
	var validCards = findValidCards(AICards, CenterCards[CenterCards.size()-1])
	
	if validCards.size() > 0:
		var randomIndex = randi() % validCards.size()
		var selectedCardIndex = validCards[randomIndex]
		var selectedCard = AICards[selectedCardIndex]

		# Play the selected card by moving it to the center position
		PlayCard(selectedCard)

		# Remove the played card from AI's hand
		AICards.remove(selectedCardIndex)
	else:
		var card = SpawnCard(true)
		AICards.append(card)
		var screenSize = get_viewport().get_visible_rect().size
		repositionCards(AICards,screenSize/2 + Vector2(0,-screenSize.y*.4))
		turn_Completed(card)
	pass

func PlayCard(playingCard):
	var centerCardIndex = CenterCards.size() - 1
	var tween = Tween.new()
	add_child(tween)
	
	if(playingCard.texture == Decktexture):
		playingCard.texture = CardTextures[playingCard.color + "_" + playingCard.number]
	
	# Store the initial position and rotation of the card
	var initialPosition = playingCard.position
	var initialRotation = playingCard.rotation_degrees
	
	# Generate a random rotation direction and rotation angle
	var randomRotationDirection = 1 if(randf() > 0.5) else -1
	var randomRotationAngle = rand_range(180, 360)
	
	# Generate a random offset for the center card position
	var randomOffset = Vector2(rand_range(-10, 10), rand_range(-10, 10))
	
	# Set up the tween to interpolate the card's position and rotation
	tween.interpolate_property(playingCard, "position", initialPosition, CenterCards[centerCardIndex].position+randomOffset, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	tween.interpolate_property(playingCard, "rotation_degrees", initialRotation, initialRotation + randomRotationDirection * randomRotationAngle, 0.5, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	tween.start()
	
	# Bring the card in front of previously placed center cards
	playingCard.raise()
	
	# Connect a callback to remove the tween node after the animation is done
	tween.connect("tween_completed", self, "_on_tween_completed")
	
	# Add the card to the center cards array
	CenterCards.append(playingCard)
	
func _on_tween_completed(obj, key):
	if key == ":position":
		turn_Completed(obj)

func turn_Completed(card):
	if(PlayerCards.size()==0):
		win(true)
		return
	if(AICards.size()==0):
		win(false)
		return
	
	PlayerTurn = !PlayerTurn
	if(card.number =="Skip"):
		PlayerTurn = !PlayerTurn
	if !PlayerTurn:
		AI_Turn()
	pass

func win(playerWon):
	if(playerWon):
		$ColorRect/Label.text = "You Won!!"
	else:
		$ColorRect/Label.text = "Computer Won"
	$ColorRect.visible = true
	$ColorRect.raise()
	pass

func isValidMove(playingCard, centerCard):
	if playingCard.color == centerCard.color or playingCard.number == centerCard.number:
		return true

	return false

func findValidCards(playerDeck, centerCard):
	var validIndices := []

	for i in range(playerDeck.size()):
		var card = playerDeck[i]
		if isValidMove(card, centerCard):
			validIndices.append(i)

	return validIndices
	
func SpawnCard(flipped: bool = false):
	var card = CardObject.instance()
	var random = CardTextures.keys()
	random = random[randi() % random.size()]
	card.texture = CardTextures[random]
	card.color = random.split("_")[0]
	card.number = random.split("_")[1]
	card.flip_h = flipped
	if(flipped):
		card.texture = Decktexture
	add_child(card)
	return card

func repositionCards(cards: Array,centerScreenPoint: Vector2):
	var totalWidth = (cards.size() - 1) * CARD_SPACING
	var startingPosition = centerScreenPoint - Vector2(totalWidth / 2, 0)

	for i in range(cards.size()):
		var card = cards[i]
		card.position = startingPosition + Vector2(i * CARD_SPACING, 0)
	pass

func loadTextures():
	for color in Colors:
		for n in Numbers:
			CardTextures[color + "_" + str(n)] = load("res://Assets/Uno Game Assets/" + color + "_" + str(n) + ".png")
	pass


func _on_Draw_Button_pressed():
	var card = SpawnCard()
	PlayerCards.append(card)
	var screenSize = get_viewport().get_visible_rect().size
	repositionCards(PlayerCards,screenSize/2 + Vector2(0,screenSize.y*.4))
	turn_Completed(card)
	pass # Replace with function body.


func _on_Replay_Button_pressed():
	get_tree().reload_current_scene()
	pass
