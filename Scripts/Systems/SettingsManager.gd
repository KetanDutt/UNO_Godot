extends Node
# SettingsManager
# ---------------
# Persists player preferences and career stats to `user://settings.cfg`
# (an OS-appropriate writable location, and IndexedDB-backed on HTML5).
#
# Everything is defensive: a missing, truncated or hand-edited config falls back
# to defaults rather than crashing, and unknown keys are ignored.

signal settings_changed

const SAVE_PATH = "user://settings.cfg"
const CONFIG_VERSION = 2

# --- audio ---
var master_volume: float = 1.0
var sfx_volume: float = 0.85
var music_volume: float = 0.4
var sfx_enabled: bool = true
var music_enabled: bool = true

# --- gameplay ---
var difficulty: int = 1              # AIPlayer.Difficulty
var opponent_count: int = 1          # 1-3 CPU opponents
var target_score: int = 500
var rule_stacking: bool = false
var rule_draw_until_playable: bool = false
var rule_seven_zero: bool = false
var rule_force_play: bool = false
var rule_jump_in: bool = false           # identical card may be played out of turn

# --- presentation / accessibility ---
var animation_speed: float = 1.0     # 0.5 = relaxed, 2.0 = snappy
var table_variant: int = 1           # Table_0 .. Table_4
var show_hints: bool = true          # highlight legal cards
var colorblind_glyphs: bool = false  # add shape glyphs to colour UI
var screen_shake: bool = true
var particles_enabled: bool = true
var high_contrast: bool = false

# --- career stats ---
var stat_games_played: int = 0
var stat_games_won: int = 0
var stat_rounds_played: int = 0
var stat_rounds_won: int = 0
var stat_cards_played: int = 0
var stat_best_score: int = 0
var stat_uno_calls: int = 0

var _loaded: bool = false


func _ready() -> void:
	name = "SettingsManager"
	pause_mode = Node.PAUSE_MODE_PROCESS
	load_settings()


func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SAVE_PATH)
	if err != OK:
		_loaded = true
		return

	master_volume = _read(config, "audio", "master_volume", master_volume)
	sfx_volume = _read(config, "audio", "sfx_volume", sfx_volume)
	music_volume = _read(config, "audio", "music_volume", music_volume)
	sfx_enabled = _read(config, "audio", "sfx_enabled", sfx_enabled)
	music_enabled = _read(config, "audio", "music_enabled", music_enabled)

	difficulty = _read(config, "gameplay", "difficulty", difficulty)
	opponent_count = _read(config, "gameplay", "opponent_count", opponent_count)
	target_score = _read(config, "gameplay", "target_score", target_score)
	rule_stacking = _read(config, "gameplay", "rule_stacking", rule_stacking)
	rule_draw_until_playable = _read(config, "gameplay", "rule_draw_until_playable", rule_draw_until_playable)
	rule_seven_zero = _read(config, "gameplay", "rule_seven_zero", rule_seven_zero)
	rule_force_play = _read(config, "gameplay", "rule_force_play", rule_force_play)
	rule_jump_in = _read(config, "gameplay", "rule_jump_in", rule_jump_in)

	animation_speed = _read(config, "display", "animation_speed", animation_speed)
	table_variant = _read(config, "display", "table_variant", table_variant)
	show_hints = _read(config, "display", "show_hints", show_hints)
	colorblind_glyphs = _read(config, "display", "colorblind_glyphs", colorblind_glyphs)
	screen_shake = _read(config, "display", "screen_shake", screen_shake)
	particles_enabled = _read(config, "display", "particles_enabled", particles_enabled)
	high_contrast = _read(config, "display", "high_contrast", high_contrast)

	stat_games_played = _read(config, "stats", "games_played", stat_games_played)
	stat_games_won = _read(config, "stats", "games_won", stat_games_won)
	stat_rounds_played = _read(config, "stats", "rounds_played", stat_rounds_played)
	stat_rounds_won = _read(config, "stats", "rounds_won", stat_rounds_won)
	stat_cards_played = _read(config, "stats", "cards_played", stat_cards_played)
	stat_best_score = _read(config, "stats", "best_score", stat_best_score)
	stat_uno_calls = _read(config, "stats", "uno_calls", stat_uno_calls)

	_sanitise()
	_loaded = true


func _read(config: ConfigFile, section: String, key: String, fallback):
	if not config.has_section_key(section, key):
		return fallback
	var value = config.get_value(section, key, fallback)
	# Reject type drift from a hand-edited file.
	if typeof(value) != typeof(fallback):
		if typeof(fallback) == TYPE_REAL and typeof(value) == TYPE_INT:
			return float(value)
		if typeof(fallback) == TYPE_INT and typeof(value) == TYPE_REAL:
			return int(value)
		return fallback
	return value


func _sanitise() -> void:
	master_volume = clamp(master_volume, 0.0, 1.0)
	sfx_volume = clamp(sfx_volume, 0.0, 1.0)
	music_volume = clamp(music_volume, 0.0, 1.0)
	difficulty = int(clamp(difficulty, 0, 2))
	opponent_count = int(clamp(opponent_count, 1, 3))
	target_score = int(clamp(target_score, 100, 1000))
	animation_speed = clamp(animation_speed, 0.5, 2.0)
	table_variant = int(clamp(table_variant, 0, 4))
	stat_games_played = int(max(0, stat_games_played))
	stat_games_won = int(max(0, stat_games_won))
	stat_rounds_played = int(max(0, stat_rounds_played))
	stat_rounds_won = int(max(0, stat_rounds_won))
	stat_cards_played = int(max(0, stat_cards_played))
	stat_best_score = int(max(0, stat_best_score))
	stat_uno_calls = int(max(0, stat_uno_calls))


func save_settings() -> void:
	if not _loaded:
		return
	var config = ConfigFile.new()
	config.set_value("meta", "version", CONFIG_VERSION)

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_enabled", sfx_enabled)
	config.set_value("audio", "music_enabled", music_enabled)

	config.set_value("gameplay", "difficulty", difficulty)
	config.set_value("gameplay", "opponent_count", opponent_count)
	config.set_value("gameplay", "target_score", target_score)
	config.set_value("gameplay", "rule_stacking", rule_stacking)
	config.set_value("gameplay", "rule_draw_until_playable", rule_draw_until_playable)
	config.set_value("gameplay", "rule_seven_zero", rule_seven_zero)
	config.set_value("gameplay", "rule_force_play", rule_force_play)
	config.set_value("gameplay", "rule_jump_in", rule_jump_in)

	config.set_value("display", "animation_speed", animation_speed)
	config.set_value("display", "table_variant", table_variant)
	config.set_value("display", "show_hints", show_hints)
	config.set_value("display", "colorblind_glyphs", colorblind_glyphs)
	config.set_value("display", "screen_shake", screen_shake)
	config.set_value("display", "particles_enabled", particles_enabled)
	config.set_value("display", "high_contrast", high_contrast)

	config.set_value("stats", "games_played", stat_games_played)
	config.set_value("stats", "games_won", stat_games_won)
	config.set_value("stats", "rounds_played", stat_rounds_played)
	config.set_value("stats", "rounds_won", stat_rounds_won)
	config.set_value("stats", "cards_played", stat_cards_played)
	config.set_value("stats", "best_score", stat_best_score)
	config.set_value("stats", "uno_calls", stat_uno_calls)

	config.save(SAVE_PATH)
	emit_signal("settings_changed")


func reset_to_defaults() -> void:
	master_volume = 1.0
	sfx_volume = 0.85
	music_volume = 0.4
	sfx_enabled = true
	music_enabled = true
	difficulty = 1
	opponent_count = 1
	target_score = 500
	rule_stacking = false
	rule_draw_until_playable = false
	rule_seven_zero = false
	rule_force_play = false
	rule_jump_in = false
	animation_speed = 1.0
	table_variant = 1
	show_hints = true
	colorblind_glyphs = false
	screen_shake = true
	particles_enabled = true
	high_contrast = false
	save_settings()


func reset_stats() -> void:
	stat_games_played = 0
	stat_games_won = 0
	stat_rounds_played = 0
	stat_rounds_won = 0
	stat_cards_played = 0
	stat_best_score = 0
	stat_uno_calls = 0
	save_settings()


func win_rate() -> float:
	if stat_games_played <= 0:
		return 0.0
	return float(stat_games_won) / float(stat_games_played) * 100.0


func round_win_rate() -> float:
	if stat_rounds_played <= 0:
		return 0.0
	return float(stat_rounds_won) / float(stat_rounds_played) * 100.0


# Duration multiplier applied to every tween in the game.
func anim_scale(duration: float) -> float:
	return duration / max(animation_speed, 0.05)
