extends TextureRect

var Colors = ["Red","Yellow","Green","Blue"]
var CardObject = preload("res://Scenes/Card.tscn")
var Decktexture = preload("res://Assets/Uno Game Assets/Deck.png")
var CardTextures = {}

var PlayerCards = []
var AICards = []
var CenterCards = []

const DECK_SIZE = 10
const CARD_SPACING = 50

func _ready():
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
	pass

func SpawnCard(flipped: bool = false):
	var card = CardObject.instance()
	var random = CardTextures.keys()
	random = random[randi() % random.size()]
	card.texture = CardTextures[random]
	card.id = random
	card.flip_h = flipped
#	if(flipped):
#		card.texture = Decktexture
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
		for n in 10:
			CardTextures[color + "_" + str(n)] = load("res://Assets/Uno Game Assets/" + color + "_" + str(n) + ".png")
	pass
