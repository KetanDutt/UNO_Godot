extends Sprite

var color = "Deck"
var number = "-1"

func _ready():
	pass

func _on_TextureButton_pressed():
	get_parent().CardClicked(self)
	pass
