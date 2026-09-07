extends Reference
# CardData
# --------
# Immutable-ish value object describing a single card. Instances are created by
# `Deck` and passed around by reference; the presentation layer never mutates
# them except for `chosen_color`, which records the colour a wild was declared as.

const CardTypes = preload("res://Scripts/Core/CardTypes.gd")

var color: int = CardTypes.CardColor.RED
var value: int = CardTypes.CardValue.N0

# For wild cards this stores the colour the player declared. -1 when unset.
var chosen_color: int = -1

# Stable identifier so views can be pooled/matched without object identity games.
var uid: int = 0


func _init(p_color: int = CardTypes.CardColor.RED,
		p_value: int = CardTypes.CardValue.N0, p_uid: int = 0) -> void:
	color = p_color
	value = p_value
	uid = p_uid


func is_wild() -> bool:
	return CardTypes.is_wild(value)


func is_action() -> bool:
	return CardTypes.is_action(value)


func is_number() -> bool:
	return CardTypes.is_number(value)


# The colour this card currently represents on the table. Wilds report the
# colour they were declared as once played.
func effective_color() -> int:
	if is_wild() and chosen_color >= 0:
		return chosen_color
	return color


func asset_key() -> String:
	return CardTypes.asset_key(color, value)


func score() -> int:
	return CardTypes.score_for(value)


func display_name() -> String:
	if is_wild():
		return CardTypes.value_name(value)
	return CardTypes.color_name(color) + " " + CardTypes.value_name(value)


func duplicate_card():
	var copy = get_script().new(color, value, uid)
	copy.chosen_color = chosen_color
	return copy


func to_dict() -> Dictionary:
	return {"color": color, "value": value, "chosen_color": chosen_color, "uid": uid}


func _to_string() -> String:
	return "[Card %s #%d]" % [display_name(), uid]
