extends Node

enum Cue { SHOT, SWING, LOOT, HURT, PURCHASE, DEPLOY, CLEAR }

const SAMPLE_RATE := 22050
# Seconds, starting/ending pitch, noise mix, and gain.
const VOICES := [
	[0.068, 210.0, 64.0, 0.71, 0.31],
	[0.105, 180.0, 85.0, 0.62, 0.22],
	[0.095, 450.0, 1060.0, 0.05, 0.33],
	[0.145, 134.0, 52.0, 0.43, 0.36],
	[0.105, 390.0, 680.0, 0.03, 0.26],
	[0.240, 220.0, 440.0, 0.04, 0.29],
	[0.310, 340.0, 750.0, 0.04, 0.31],
]

var muted := false
var _voices: Array[AudioStreamPlayer] = []
var _next := PackedInt64Array()


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_next.resize(VOICES.size())
	for settings in VOICES:
		var voice := AudioStreamPlayer.new()
		voice.stream = _synthesize(settings)
		voice.max_polyphony = 2
		voice.volume_db = -12.0
		add_child(voice)
		_voices.append(voice)


func play(cue: int) -> void:
	var now := Time.get_ticks_msec()
	if not muted and not _voices.is_empty() and now >= _next[cue]:
		_next[cue] = now + 55
		_voices[cue].play()


func _synthesize(settings: Array) -> AudioStreamWAV:
	var duration: float = settings[0]
	var start_pitch: float = settings[1]
	var end_pitch: float = settings[2]
	var noise_mix: float = settings[3]
	var gain: float = settings[4]
	var count := roundi(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in range(count):
		var t := float(i) / SAMPLE_RATE
		var ramp := t / duration
		var phase := TAU * t * (start_pitch + (end_pitch - start_pitch) * ramp * 0.5)
		var tone := sin(phase) * 0.80 + sin(phase * 2.0) * 0.20
		var noise := sin(t * 18957.3) * sin(t * 9583.1)
		var envelope := minf(1.0, t * 350.0) * pow(1.0 - ramp, 2.2)
		pcm.encode_s16(i * 2, roundi(lerpf(tone, noise, noise_mix) * envelope * gain * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.data = pcm
	return stream
