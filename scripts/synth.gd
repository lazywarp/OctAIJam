extends Node
## Tiny code-only synthesizer: renders and caches short samples, plays them on a voice pool.

const MIX_RATE := 22050
const VOICES := 16
const PAD_VOICES := 6 # long pads get their own pool so they never steal ticks or jump notes
const LENGTHS := {"tick": 0.05, "thud": 0.15, "note": 0.6, "bass": 1.0, "melt": 0.9, "sizzle": 0.5, "drip": 0.08, "pad": 2.6, "chime": 0.5, "refreeze": 0.7}
const PAD_ATTACK := 0.25
const PAD_RELEASE := 0.9

var _players: Array[AudioStreamPlayer] = []
var _pad_players: Array[AudioStreamPlayer] = []
var _next := 0
var _pad_next := 0
var _cache := {}
var _stopped := false # set on shutdown: no new sounds


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in PAD_VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pad_players.append(p)


# Quitting while voices are mid-note leaves their streams and playbacks alive in the audio
# server, which Godot reports as leaked objects at exit. main.gd calls this, then waits a
# moment for the mixer to let go, before quitting.
func stop_all() -> void:
	_stopped = true
	for p in _players + _pad_players:
		p.stop()
		p.stream = null
	_cache.clear()


func play(kind: String, freq := 440.0, volume_db := 0.0) -> void:
	if _stopped:
		return
	var p: AudioStreamPlayer
	if kind == "pad":
		p = _pad_players[_pad_next]
		_pad_next = (_pad_next + 1) % PAD_VOICES
	else:
		p = _players[_next]
		_next = (_next + 1) % VOICES
	p.stream = _sample(kind, freq)
	p.volume_db = volume_db
	p.play()


## Render and cache samples ahead of time, so long ones (pads) don't hitch on first play.
func prerender(kind: String, freqs: Array[float]) -> void:
	for f in freqs:
		_sample(kind, f)


func _sample(kind: String, freq: float) -> AudioStreamWAV:
	var key := "%s:%.2f" % [kind, freq]
	if _cache.has(key):
		return _cache[key]

	var length: float = LENGTHS.get(kind, 0.4)
	var n := int(MIX_RATE * length)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var t := float(i) / MIX_RATE
		var s := 0.0
		match kind:
			"tick":
				s = sin(TAU * freq * t) * exp(-t * 90.0)
			"thud":
				s = sin(TAU * freq * (1.0 - t * 2.0) * t) * exp(-t * 25.0) * 0.8
			"note":
				s = (sin(TAU * freq * t) + 0.35 * sin(TAU * freq * 2.0 * t) + 0.15 * sin(TAU * freq * 3.0 * t))
				s *= exp(-t * 6.0) * 0.6 * minf(1.0, t * 200.0)
			"bass":
				var tri := 2.0 * absf(2.0 * fposmod(freq * t, 1.0) - 1.0) - 1.0
				s = tri * exp(-t * 3.0) * 0.6 * minf(1.0, t * 100.0)
			"melt":
				phase += TAU * freq * (1.0 - 0.75 * t / length) / MIX_RATE
				s = sin(phase + 2.0 * sin(phase * 0.5)) * (1.0 - t / length) * 0.5
			"sizzle":
				s = randf_range(-1.0, 1.0) * exp(-t * 5.0) * 0.4
			"drip":
				# Water drop: sine whose pitch sweeps up fast, with a quick decay.
				phase += TAU * freq * (1.0 + 1.5 * minf(1.0, t / 0.03)) / MIX_RATE
				s = sin(phase) * exp(-t * 55.0) * 0.5 * minf(1.0, t * 1000.0)
			"chime":
				# Two-note sparkle: freq, then a fifth above 70 ms later. Bell-ish inharmonic partial.
				var hi := 1.4983
				s = (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.76 * t)) * exp(-t * 14.0)
				if t > 0.07:
					var u := t - 0.07
					s += (sin(TAU * freq * hi * u) + 0.3 * sin(TAU * freq * hi * 2.76 * u)) * exp(-u * 10.0)
				s *= 0.3 * minf(1.0, t * 400.0)
			"refreeze":
				# Crystalline upward sweep with a shimmering octave, ending on a soft ring.
				phase += TAU * freq * (0.6 + 0.6 * minf(1.0, t / 0.25)) / MIX_RATE
				s = sin(phase) + 0.4 * sin(phase * 2.0) * (0.5 + 0.5 * sin(TAU * 18.0 * t))
				s *= exp(-t * 4.5) * 0.35 * minf(1.0, t * 300.0)
			"pad":
				# Warm pad: sine plus a slightly detuned sine (chorus) and a touch of octave,
				# smooth attack, gently sagging sustain, cosine release to exactly zero.
				s = sin(TAU * freq * t) + 0.6 * sin(TAU * freq * 1.004 * t + 1.3) + 0.12 * sin(TAU * freq * 2.0 * t)
				var env := 1.0 - 0.25 * t / length
				if t < PAD_ATTACK:
					env *= 0.5 - 0.5 * cos(PI * t / PAD_ATTACK)
				var rel := length - t
				if rel < PAD_RELEASE:
					env *= 0.5 - 0.5 * cos(PI * maxf(rel - 1.0 / MIX_RATE, 0.0) / PAD_RELEASE)
				s *= env * 0.3
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	_cache[key] = wav
	return wav
