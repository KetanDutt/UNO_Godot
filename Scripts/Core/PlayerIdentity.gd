extends Reference
# PlayerIdentity
# --------------
# Opponent identities: a random name and a matching avatar per CPU seat.
#
# The pick is seeded by the match seed, so a given match always fields the
# same table - which also keeps the "next round" flow consistent (identities
# are chosen once per match, not per round) and would make replays with a
# persisted seed reproduce the exact same opponents.

const NAMES = [
	"Ada", "Bruno", "Cleo", "Dashi", "Elke", "Fenn",
	"Gigi", "Hugo", "Ines", "Juno", "Kira", "Lupo",
	"Mabel", "Nico", "Otto", "Pia", "Ravi", "Suki",
	"Tavo", "Uma", "Vito", "Wren"
]

# Avatar art lives in Assets/Uno Game Assets/Avatars/ (256x256, circle-masked).
const AVATARS = ["fox", "robot", "cat", "astronaut", "owl", "penguin"]
const PLAYER_AVATAR = "player"

# Human-readable labels for the help text, in avatar order.
const AVATAR_LABELS = {
	"fox": "the fox", "robot": "the robot", "cat": "the cat",
	"astronaut": "the astronaut", "owl": "the owl", "penguin": "the penguin",
	"player": "you"
}


static func pick_names(opponent_count: int, seed_value: int) -> Array:
	# `count` unique names, shuffled by the match seed.
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool = NAMES.duplicate()
	var picked = []
	for _i in range(opponent_count):
		if pool.empty():
			picked.append("CPU")
			continue
		var index = rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove(index)
	return picked


static func pick_avatars(opponent_count: int, seed_value: int) -> Array:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 7919
	var pool = AVATARS.duplicate()
	var picked = []
	for _i in range(opponent_count):
		if pool.empty():
			# More opponents than avatar art: reuse from the start.
			pool = AVATARS.duplicate()
		var index = rng.randi_range(0, pool.size() - 1)
		picked.append(pool[index])
		pool.remove(index)
	return picked


static func avatar_path(key: String) -> String:
	return "res://Assets/Uno Game Assets/Avatars/%s.png" % key
