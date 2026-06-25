extends Sprite

var color: String = "Deck"
var number: String = "-1"

func _on_TextureButton_pressed():
	get_parent().CardClicked(self)
	pass
