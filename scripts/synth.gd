extends Node
## Tiny code-only synthesizer: renders and caches short samples, plays them on a voice pool.

const MIX_RATE := 22050
const VOICES := 16
const LENGTHS := {"tick": 0.05, "thud": 0.15, "note": 0.6, "bass": 1.0, "melt": 0.9, "sizzle": 0.5, "drip": 0.08}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _cache := {}


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(kind: String, freq := 440.0, volume_db := 0.0) -> void:
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = _sample(kind, freq)
	p.volume_db = volume_db
	p.play()


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
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	_cache[key] = wav
	return wav
