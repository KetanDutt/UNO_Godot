extends Node
# AudioDirector
# -------------
# Procedural audio engine. Every sound is synthesised at boot into an
# AudioStreamSample, so the repository stays free of binary audio blobs while
# the game still has a full SFX bed and adaptive music.
#
# Design notes:
#   * Samples are generated once and cached; playback just re-points a player.
#   * A small pool of AudioStreamPlayers round-robins so overlapping sounds
#     (dealing seven cards) never cut each other off.
#   * Separate master / SFX / music volumes, each persisted by SettingsManager.
#   * Music is a seamless looping chord bed with a gentle arpeggio, rendered
#     once and looped by the audio server (no per-frame cost).

const MIX_RATE = 44100
const SFX_POOL_SIZE = 10
const MAX_AMPLITUDE = 32767.0

# Semitone offsets from A4 used by the melodic cues.
const NOTE_C5 = 523.25
const NOTE_D5 = 587.33
const NOTE_E5 = 659.25
const NOTE_G5 = 783.99
const NOTE_A5 = 880.00
const NOTE_C6 = 1046.50

var _streams: Dictionary = {}
var _pool: Array = []
var _pool_index: int = 0
var _music_player: AudioStreamPlayer = null

var sfx_enabled: bool = true
var music_enabled: bool = true
var master_volume: float = 1.0
var sfx_volume: float = 0.85
var music_volume: float = 0.4

# Guards against the same cue firing many times in one frame (e.g. a burst of
# penalty draws) which would otherwise sound like clipping noise.
var _last_played: Dictionary = {}
var _min_repeat_gap: float = 0.035


func _ready() -> void:
	name = "AudioDirector"
	pause_mode = Node.PAUSE_MODE_PROCESS
	_build_streams()
	_build_pool()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func play(cue: String, pitch: float = 1.0) -> void:
	if not sfx_enabled or not _streams.has(cue):
		return
	var now = OS.get_ticks_msec() / 1000.0
	if _last_played.has(cue) and now - _last_played[cue] < _min_repeat_gap:
		return
	_last_played[cue] = now

	var player = _pool[_pool_index]
	_pool_index = (_pool_index + 1) % _pool.size()
	player.stream = _streams[cue]
	player.pitch_scale = clamp(pitch, 0.4, 2.4)
	player.volume_db = linear2db(clamp(master_volume * sfx_volume, 0.0, 1.0))
	player.play()


# Deal a run of cards with a rising pitch - cheap but very satisfying.
func play_sequence(cue: String, count: int, start_pitch: float = 0.94, step: float = 0.045) -> void:
	for i in range(count):
		play(cue, start_pitch + i * step)


func set_music_playing(enabled: bool) -> void:
	music_enabled = enabled
	if _music_player == null:
		return
	if enabled and master_volume > 0.0 and music_volume > 0.0:
		if not _music_player.playing:
			_music_player.play()
	else:
		_music_player.stop()


func apply_volumes() -> void:
	if _music_player != null:
		var level = clamp(master_volume * music_volume, 0.0, 1.0)
		_music_player.volume_db = linear2db(max(level, 0.0001))
		if level <= 0.001 or not music_enabled:
			_music_player.stop()
		elif music_enabled and not _music_player.playing:
			_music_player.play()


# Duck the music briefly - used for the win sting so it lands cleanly.
func duck_music(duration: float = 1.6) -> void:
	if _music_player == null or not _music_player.playing:
		return
	var normal = linear2db(max(clamp(master_volume * music_volume, 0.0, 1.0), 0.0001))
	var tween = create_tween()
	tween.tween_property(_music_player, "volume_db", normal - 14.0, 0.18)
	tween.tween_interval(duration)
	tween.tween_property(_music_player, "volume_db", normal, 0.9)


# ---------------------------------------------------------------------------
# Stream construction
# ---------------------------------------------------------------------------
func _build_pool() -> void:
	for i in range(SFX_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.pause_mode = Node.PAUSE_MODE_PROCESS
		add_child(player)
		_pool.append(player)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.pause_mode = Node.PAUSE_MODE_PROCESS
	_music_player.stream = _streams["music"]
	add_child(_music_player)
	apply_volumes()


func _build_streams() -> void:
	_streams["card_place"] = _make_card_place()
	_streams["card_draw"] = _make_card_draw()
	_streams["card_flip"] = _make_noise_swish(0.09, 1600.0, 0.22)
	_streams["deal"] = _make_noise_swish(0.07, 2100.0, 0.18)
	_streams["hover"] = _make_blip(1180.0, 0.028, 0.10)
	_streams["select"] = _make_blip(880.0, 0.045, 0.16)
	_streams["error"] = _make_error()
	_streams["skip"] = _make_sweep(700.0, 240.0, 0.22, 0.24)
	_streams["reverse"] = _make_sweep(320.0, 760.0, 0.26, 0.22)
	_streams["draw_penalty"] = _make_thud()
	_streams["wild"] = _make_arpeggio([NOTE_C5, NOTE_E5, NOTE_G5, NOTE_C6], 0.075, 0.20)
	_streams["uno"] = _make_arpeggio([NOTE_G5, NOTE_C6], 0.13, 0.26)
	_streams["win"] = _make_fanfare(true)
	_streams["lose"] = _make_fanfare(false)
	_streams["turn"] = _make_blip(560.0, 0.05, 0.12)
	_streams["button"] = _make_blip(660.0, 0.038, 0.15)
	_streams["shuffle"] = _make_shuffle()
	_streams["music"] = _make_music_bed()


# --- helpers ---------------------------------------------------------------

# Convert a float array in [-1, 1] to a 16-bit mono AudioStreamSample.
func _finalise(samples: PoolRealArray, loop: bool = false) -> AudioStreamSample:
	var bytes = PoolByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var clamped = clamp(samples[i], -1.0, 1.0)
		var value = int(clamped * MAX_AMPLITUDE)
		if value < 0:
			value += 65536
		bytes.set(i * 2, value & 255)
		bytes.set(i * 2 + 1, (value >> 8) & 255)

	var stream = AudioStreamSample.new()
	stream.format = AudioStreamSample.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamSample.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func _new_buffer(seconds: float) -> PoolRealArray:
	var buffer = PoolRealArray()
	buffer.resize(int(MIX_RATE * seconds))
	for i in range(buffer.size()):
		buffer[i] = 0.0
	return buffer


# Exponential decay envelope with a short attack to avoid clicks.
func _envelope(index: int, total: int, attack: float = 0.01, curve: float = 3.2) -> float:
	var t = float(index) / float(max(total, 1))
	var attack_samples = max(attack * MIX_RATE, 1.0)
	var attack_gain = min(float(index) / attack_samples, 1.0)
	return attack_gain * pow(1.0 - t, curve)


func _make_blip(freq: float, seconds: float, volume: float) -> AudioStreamSample:
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	for i in range(count):
		var t = float(i) / MIX_RATE
		var env = _envelope(i, count, 0.004, 2.6)
		buffer[i] = sin(TAU * freq * t) * volume * env
	return _finalise(buffer)


# Wooden "clack" of a card landing: a low body plus a filtered noise transient.
func _make_card_place() -> AudioStreamSample:
	var seconds = 0.16
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = 42
	var noise_state = 0.0
	for i in range(count):
		var t = float(i) / MIX_RATE
		var env = _envelope(i, count, 0.002, 4.0)
		var body = sin(TAU * 196.0 * t) * 0.5 + sin(TAU * 293.0 * t) * 0.22
		# One-pole low-passed noise gives the papery slap.
		noise_state = lerp(noise_state, rng.randf_range(-1.0, 1.0), 0.45)
		var transient = noise_state * exp(-t * 90.0) * 0.5
		buffer[i] = (body * 0.34 + transient) * env * 0.5
	return _finalise(buffer)


# Sliding a card off the stock: band-passed noise with a rising edge.
func _make_card_draw() -> AudioStreamSample:
	var seconds = 0.2
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var low = 0.0
	var prev = 0.0
	for i in range(count):
		var t = float(i) / MIX_RATE
		var progress = float(i) / float(count)
		var env = sin(PI * progress) * pow(1.0 - progress, 0.7)
		var white = rng.randf_range(-1.0, 1.0)
		low = lerp(low, white, 0.25 + progress * 0.3)
		var band = low - prev
		prev = low
		buffer[i] = band * env * 0.85
	return _finalise(buffer)


func _make_noise_swish(seconds: float, brightness: float, volume: float) -> AudioStreamSample:
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = int(brightness)
	var low = 0.0
	var prev = 0.0
	var alpha = clamp(brightness / 8000.0, 0.05, 0.9)
	for i in range(count):
		var progress = float(i) / float(count)
		var env = sin(PI * progress)
		low = lerp(low, rng.randf_range(-1.0, 1.0), alpha)
		var band = low - prev
		prev = low
		buffer[i] = band * env * volume * 3.0
	return _finalise(buffer)


func _make_error() -> AudioStreamSample:
	var seconds = 0.22
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	for i in range(count):
		var t = float(i) / MIX_RATE
		var env = _envelope(i, count, 0.005, 2.0)
		# Detuned pair produces an unpleasant beating - reads as "no".
		var tone = sin(TAU * 146.83 * t) + sin(TAU * 155.0 * t) * 0.8
		buffer[i] = tone * 0.16 * env
	return _finalise(buffer)


func _make_sweep(from_freq: float, to_freq: float, seconds: float, volume: float) -> AudioStreamSample:
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var phase = 0.0
	for i in range(count):
		var progress = float(i) / float(count)
		var freq = lerp(from_freq, to_freq, ease(progress, 0.6))
		phase += TAU * freq / MIX_RATE
		var env = _envelope(i, count, 0.008, 2.0)
		buffer[i] = (sin(phase) * 0.7 + sin(phase * 2.0) * 0.18) * volume * env
	return _finalise(buffer)


func _make_thud() -> AudioStreamSample:
	var seconds = 0.34
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var phase = 0.0
	for i in range(count):
		var progress = float(i) / float(count)
		# Pitch drop gives weight.
		var freq = lerp(180.0, 62.0, ease(progress, 0.4))
		phase += TAU * freq / MIX_RATE
		var env = pow(1.0 - progress, 2.2)
		buffer[i] = sin(phase) * 0.55 * env
	return _finalise(buffer)


func _make_arpeggio(freqs: Array, note_seconds: float, volume: float) -> AudioStreamSample:
	var total = note_seconds * freqs.size() + 0.25
	var buffer = _new_buffer(total)
	var count = buffer.size()
	for n in range(freqs.size()):
		var start = int(n * note_seconds * MIX_RATE)
		var length = int((total - n * note_seconds) * MIX_RATE)
		for i in range(length):
			var index = start + i
			if index >= count:
				break
			var t = float(i) / MIX_RATE
			var env = pow(1.0 - float(i) / float(length), 2.6)
			var value = sin(TAU * freqs[n] * t) * 0.6 + sin(TAU * freqs[n] * 2.0 * t) * 0.12
			buffer[index] += value * volume * env
	return _finalise(buffer)


func _make_fanfare(victorious: bool) -> AudioStreamSample:
	var notes = [NOTE_C5, NOTE_E5, NOTE_G5, NOTE_C6] if victorious else [NOTE_G5, NOTE_E5, 415.30, 349.23]
	var note_seconds = 0.14
	var total = note_seconds * notes.size() + 0.7
	var buffer = _new_buffer(total)
	var count = buffer.size()
	for n in range(notes.size()):
		var start = int(n * note_seconds * MIX_RATE)
		var length = int((total - n * note_seconds) * MIX_RATE)
		for i in range(length):
			var index = start + i
			if index >= count:
				break
			var t = float(i) / MIX_RATE
			var env = pow(1.0 - float(i) / float(length), 2.0)
			# Three partials make it feel like a small brass/bell hybrid.
			var value = sin(TAU * notes[n] * t) * 0.5 \
				+ sin(TAU * notes[n] * 2.0 * t) * 0.18 \
				+ sin(TAU * notes[n] * 3.0 * t) * 0.07
			buffer[index] += value * 0.3 * env
	return _finalise(buffer)


func _make_shuffle() -> AudioStreamSample:
	var seconds = 0.55
	var buffer = _new_buffer(seconds)
	var count = buffer.size()
	var rng = RandomNumberGenerator.new()
	rng.seed = 313
	var low = 0.0
	var prev = 0.0
	# Several riffle bursts in sequence.
	for i in range(count):
		var progress = float(i) / float(count)
		var burst = abs(sin(progress * PI * 7.0))
		low = lerp(low, rng.randf_range(-1.0, 1.0), 0.4)
		var band = low - prev
		prev = low
		var env = sin(PI * progress)
		buffer[i] = band * burst * env * 1.6
	return _finalise(buffer)


# Seamless four-bar loop: soft pad chords with a sparse plucked arpeggio.
# Rendered once at boot (~8 seconds) and looped by the audio server.
func _make_music_bed() -> AudioStreamSample:
	var bpm = 84.0
	var beat = 60.0 / bpm
	var bars = 4
	var seconds = beat * 4.0 * bars
	var buffer = _new_buffer(seconds)
	var count = buffer.size()

	# I - vi - IV - V in C major, voiced low and warm.
	var chords = [
		[130.81, 164.81, 196.00],
		[110.00, 130.81, 164.81],
		[87.31, 130.81, 174.61],
		[98.00, 146.83, 196.00]
	]

	for bar in range(bars):
		var chord = chords[bar % chords.size()]
		var start = int(bar * beat * 4.0 * MIX_RATE)
		var length = int(beat * 4.0 * MIX_RATE)
		for i in range(length):
			var index = start + i
			if index >= count:
				break
			var t = float(i) / MIX_RATE
			var bar_progress = float(i) / float(length)
			# Slow swell in and out so bar joins are inaudible.
			var env = sin(PI * bar_progress) * 0.55 + 0.45
			var value = 0.0
			for note in chord:
				value += sin(TAU * note * t) * 0.16
				value += sin(TAU * note * 2.0 * t) * 0.03
			# Gentle tremolo keeps the pad alive.
			value *= 0.85 + 0.15 * sin(TAU * 0.6 * t)
			buffer[index] += value * env * 0.5

		# Sparse arpeggio on beats 1 and 3.
		for pluck in range(2):
			var note_index = (bar + pluck) % chord.size()
			var freq = chord[note_index] * 4.0
			var pluck_start = start + int(pluck * 2.0 * beat * MIX_RATE)
			var pluck_len = int(beat * 1.2 * MIX_RATE)
			for i in range(pluck_len):
				var index2 = pluck_start + i
				if index2 >= count:
					break
				var t2 = float(i) / MIX_RATE
				var env2 = pow(1.0 - float(i) / float(pluck_len), 3.0)
				buffer[index2] += sin(TAU * freq * t2) * 0.09 * env2

	# Normalise so the loop never clips after summation.
	var peak = 0.0
	for i in range(count):
		peak = max(peak, abs(buffer[i]))
	if peak > 0.001:
		var gain = 0.82 / peak
		for i in range(count):
			buffer[i] *= gain

	return _finalise(buffer, true)
