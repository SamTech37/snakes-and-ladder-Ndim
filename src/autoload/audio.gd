extends Node

## Every sound in the game, synthesised at startup. Autoloaded as `Audio`, because
## sound is the one thing that is genuinely global: `Audio.play("snake")` from wherever
## the snake happened.
##
## No audio files. The whole bank is a few hundred samples of arithmetic, which costs
## nothing to store, needs no licence tracking, and lands where the flat-vector look
## already is -- square and saw waves with hard decays, not recorded foley.
##
## Drop a CC0 loop at `res://assets/bgm.ogg` and it replaces the generated music.

const RATE := 22050

## name -> AudioStreamWAV. Filled in _ready().
var bank := {}

## Round-robin, so a hop landing on a snake does not cut the hop off.
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0

var music: AudioStreamPlayer
var muted := false


func _ready() -> void:
	# Fast attack, hard decay: a flat-vector board should not have soft edges.
	bank = {
		"roll": _noise(0.13, 0.5),
		"hop": _tone(660.0, 990.0, 0.09, "square"),
		"ladder": _tone(440.0, 1320.0, 0.28, "saw", 0.004),
		"snake": _tone(700.0, 150.0, 0.38, "saw", 0.006),
		"token": _tone(880.0, 1400.0, 0.16, "square", 0.01),
		"win": _chord([523.25, 659.25, 784.0], 1.1),
	}
	for i in 5:
		var p := AudioStreamPlayer.new()
		p.volume_db = -8.0
		add_child(p)
		voices.append(p)

	music = AudioStreamPlayer.new()
	music.volume_db = -20.0
	music.stream = _music()
	add_child(music)
	music.play()


func play(sound: String) -> void:
	if not bank.has(sound):
		return
	var p := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	p.stream = bank[sound]
	p.play()


## M. Silence is a setting, not a reason to skip building the sound.
func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)


## One wave, pitch sweeping from `f0` to `f1`, decaying to nothing. `detune` adds a
## second copy slightly off pitch -- two saws a few cents apart is the whole synthwave
## trick, and it costs one more line.
func _tone(f0: float, f1: float, secs: float, wave := "saw", detune := 0.0) -> AudioStreamWAV:
	var n := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var phase2 := 0.0
	for i in n:
		var u := float(i) / float(n)
		var f := lerpf(f0, f1, u)
		phase += f / RATE
		phase2 += f * (1.0 + detune) / RATE
		var s := _wave(phase, wave)
		if detune > 0.0:
			s = (s + _wave(phase2, wave)) * 0.5
		data.encode_s16(i * 2, int(clampf(s * _env(u), -1.0, 1.0) * 32767.0))
	return _wav(data)


## Filtered-ish noise for the die. A pitch sweep says "a thing moved"; a burst says
## "something was shaken", which is what a roll is.
func _noise(secs: float, tone: float) -> AudioStreamWAV:
	var n := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var last := 0.0
	for i in n:
		var u := float(i) / float(n)
		# One-pole lowpass on white noise: cheaper than a filter node and this is a
		# 3000-sample buffer, not a signal chain.
		last = lerpf(last, randf() * 2.0 - 1.0, tone)
		data.encode_s16(i * 2, int(clampf(last * _env(u), -1.0, 1.0) * 32767.0))
	return _wav(data)


func _chord(freqs: Array, secs: float) -> AudioStreamWAV:
	var n := int(RATE * secs)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phases := PackedFloat32Array()
	phases.resize(freqs.size())
	for i in n:
		var u := float(i) / float(n)
		var s := 0.0
		for k in freqs.size():
			phases[k] += freqs[k] / RATE
			s += _wave(phases[k], "square")
		s /= float(freqs.size())
		data.encode_s16(i * 2, int(clampf(s * _env(u), -1.0, 1.0) * 32767.0))
	return _wav(data)


## A looping pad: two detuned saws holding the chord, with an arpeggio picking through
## it. Four bars of A minor, because the board is black and violet and this is the
## music that goes with that.
func _music() -> AudioStream:
	# A hand-dropped CC0 track wins if there is one; this is what plays when there
	# isn't, so the game is never silent for want of an asset.
	if ResourceLoader.exists("res://assets/bgm.ogg"):
		var s := load("res://assets/bgm.ogg")
		if s is AudioStream:
			s.loop = true
			return s

	var roots := [110.0, 87.31, 130.81, 98.0]  # A2  F2  C3  G2
	var bar := 2.0
	var n := int(RATE * bar * roots.size())
	var data := PackedByteArray()
	data.resize(n * 2)
	var p1 := 0.0
	var p2 := 0.0
	var pa := 0.0
	for i in n:
		var t := float(i) / RATE
		var root: float = roots[int(t / bar) % roots.size()]
		p1 += root / RATE
		p2 += root * 1.006 / RATE
		# Arpeggio: root, fifth, octave, twelfth, one step per eighth note.
		var step := int(t * 4.0) % 4
		var mult: float = [1.0, 1.5, 2.0, 3.0][step]
		pa += root * mult * 2.0 / RATE
		var u := fmod(t * 4.0, 1.0)
		var pad := (_wave(p1, "saw") + _wave(p2, "saw")) * 0.5
		var arp := _wave(pa, "square") * pow(1.0 - u, 3.0)
		data.encode_s16(i * 2, int(clampf(pad * 0.5 + arp * 0.35, -1.0, 1.0) * 32767.0))
	var w := _wav(data)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n - 1
	return w


## Attack over the first 2%, then a cubic fall. Starting or stopping a wave at
## non-zero costs a click, which is the one sound nobody chose.
func _env(u: float) -> float:
	var attack := minf(u / 0.02, 1.0)
	return attack * pow(1.0 - u, 3.0)


func _wave(phase: float, kind: String) -> float:
	var f := fmod(phase, 1.0)
	match kind:
		"square":
			return 1.0 if f < 0.5 else -1.0
		"saw":
			return f * 2.0 - 1.0
	return sin(f * TAU)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
