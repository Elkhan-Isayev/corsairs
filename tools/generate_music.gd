## Offline music synthesizer — renders the game's audio into WAV files.
## Run once: godot --headless --path . -s tools/generate_music.gd
## Produces: assets/music/theme.wav, battle.wav, waves.wav (all loopable).
extends SceneTree

const RATE := 22050


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/music"))
	_save(_render_theme(), "res://assets/music/theme.wav")
	print("theme.wav done")
	_save(_render_battle(), "res://assets/music/battle.wav")
	print("battle.wav done")
	_save(_render_waves(), "res://assets/music/waves.wav")
	print("waves.wav done")
	quit(0)


func _save(buf: PackedFloat32Array, path: String) -> void:
	# Short fade at both ends to avoid loop clicks.
	var fade := int(RATE * 0.04)
	for i in fade:
		var k := float(i) / fade
		buf[i] *= k
		buf[buf.size() - 1 - i] *= k
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i], -1.0, 1.0) * 32000.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	wav.save_to_wav(ProjectSettings.globalize_path(path))


## Add a tone with simple harmonics and an attack/release envelope.
func _tone(buf: PackedFloat32Array, start_s: float, dur_s: float, freq: float,
		amp: float, attack_s: float, release_s: float, harmonics: Array) -> void:
	var start := int(start_s * RATE)
	var n := int(dur_s * RATE)
	var atk := maxi(int(attack_s * RATE), 1)
	var rel := maxi(int(release_s * RATE), 1)
	var w := TAU * freq / RATE
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var env := 1.0
		if i < atk:
			env = float(i) / atk
		if i > n - rel:
			env = minf(env, float(n - i) / rel)
		var s := 0.0
		for h in harmonics.size():
			s += harmonics[h] * sin(w * (h + 1) * i)
		buf[idx] += s * amp * env


## Plucked-string style: harmonics with exponential decay.
func _pluck(buf: PackedFloat32Array, start_s: float, freq: float, amp: float, decay_s: float) -> void:
	var start := int(start_s * RATE)
	var n := int(decay_s * RATE * 3.0)
	var w := TAU * freq / RATE
	var d := decay_s * RATE
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var env := exp(-float(i) / d)
		var s := sin(w * i) + 0.45 * sin(w * 2.0 * i) * exp(-float(i) / (d * 0.5)) \
			+ 0.2 * sin(w * 3.0 * i) * exp(-float(i) / (d * 0.3))
		buf[idx] += s * amp * env


## Percussive noise burst (snare / surf splash).
func _noise_burst(buf: PackedFloat32Array, start_s: float, amp: float, decay_s: float, rng: RandomNumberGenerator) -> void:
	var start := int(start_s * RATE)
	var n := int(decay_s * RATE * 3.0)
	var d := decay_s * RATE
	var lp := 0.0
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		lp += 0.35 * (rng.randf_range(-1, 1) - lp)
		buf[idx] += lp * amp * exp(-float(i) / d)


# --- Tracks ---

## Calm main theme: D dorian, 70 bpm, 8 bars — pads, harp plucks, soft bass.
func _render_theme() -> PackedFloat32Array:
	var bpm := 70.0
	var bar := 4.0 * 60.0 / bpm
	var total := bar * 8.0
	var buf := PackedFloat32Array()
	buf.resize(int(total * RATE))

	# Chord progression: Dm  Bb  F  C  Dm  Bb  C  Dm
	var chords := [
		[146.83, 174.61, 220.0],   # Dm: D3 F3 A3
		[116.54, 146.83, 174.61],  # Bb: Bb2 D3 F3
		[174.61, 220.0, 261.63],   # F:  F3 A3 C4
		[130.81, 164.81, 196.0],   # C:  C3 E3 G3
		[146.83, 174.61, 220.0],
		[116.54, 146.83, 174.61],
		[130.81, 164.81, 196.0],
		[146.83, 174.61, 220.0],
	]
	var bass := [73.42, 58.27, 87.31, 65.41, 73.42, 58.27, 65.41, 73.42]
	var pad_h := [1.0, 0.4, 0.18, 0.08]
	for b in 8:
		var t0 := b * bar
		for f in chords[b]:
			_tone(buf, t0, bar, f, 0.055, bar * 0.35, bar * 0.35, pad_h)
		_tone(buf, t0, bar * 0.9, bass[b], 0.10, 0.02, bar * 0.4, [1.0, 0.25])
		_tone(buf, t0 + bar * 0.5, bar * 0.45, bass[b] * 1.5, 0.05, 0.02, bar * 0.2, [1.0, 0.25])

	# Harp motif, two notes per bar (D dorian).
	var melody := [
		587.33, 698.46,  440.0, 587.33,  698.46, 783.99,  880.0, 783.99,
		698.46, 587.33,  783.99, 698.46,  659.25, 523.25,  587.33, 440.0,
	]
	for i in melody.size():
		var t := (i / 2) * bar + (i % 2) * bar * 0.5 + 0.02 * (i % 3)
		_pluck(buf, t, melody[i], 0.12, 0.9)
		# Sparse octave echo.
		if i % 4 == 2:
			_pluck(buf, t + bar * 0.25, melody[i] * 0.5, 0.06, 1.1)
	return buf


## Tense battle track: D minor drone, 100 bpm, drums and an ostinato.
func _render_battle() -> PackedFloat32Array:
	var bpm := 100.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var total := bar * 8.0
	var buf := PackedFloat32Array()
	buf.resize(int(total * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Drone: D2 + A2 all the way through.
	_tone(buf, 0.0, total, 73.42, 0.06, 1.0, 1.0, [1.0, 0.5, 0.28, 0.12])
	_tone(buf, 0.0, total, 110.0, 0.035, 1.5, 1.5, [1.0, 0.4, 0.2])

	# Ostinato eighths: D3 D3 F3 D3 | D3 D3 G3 F3
	var ost := [146.83, 146.83, 174.61, 146.83, 146.83, 146.83, 196.0, 174.61]
	for b in 8:
		for e in 8:
			var t := b * bar + e * beat * 0.5
			_pluck(buf, t, ost[e], 0.09, 0.16)
		# Strings swell every other bar: D4 -> Eb4 (menace).
		if b % 2 == 0:
			_tone(buf, b * bar, bar * 0.9, 293.66, 0.05, bar * 0.3, bar * 0.3, [1.0, 0.5, 0.25])
		else:
			_tone(buf, b * bar, bar * 0.9, 311.13, 0.05, bar * 0.3, bar * 0.3, [1.0, 0.5, 0.25])
	# Drums: low thump each beat, snare on 2 & 4.
	for b in 8:
		for k in 4:
			var t := b * bar + k * beat
			_tone(buf, t, 0.22, 55.0, 0.28, 0.004, 0.18, [1.0])
			if k % 2 == 1:
				_noise_burst(buf, t, 0.16, 0.07, rng)
	return buf


## Looping ocean ambience: low-passed noise with slow swell.
func _render_waves() -> PackedFloat32Array:
	var total := 16.0
	var n := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		lp += 0.045 * (rng.randf_range(-1, 1) - lp)
		lp2 += 0.012 * (lp - lp2)
		# Two overlapping swell cycles so the loop feels irregular.
		var swell := 0.5 + 0.28 * sin(TAU * t / 8.0) + 0.22 * sin(TAU * t / 5.3 + 1.7)
		buf[i] = (lp * 0.7 + lp2 * 0.6) * swell * 0.5
	return buf
