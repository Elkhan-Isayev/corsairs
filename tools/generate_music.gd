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
	_save(_render_shanty(), "res://assets/music/shanty.wav")
	print("shanty.wav done")
	for nation in TOWN_TUNES:
		_save(_render_town(TOWN_TUNES[nation]), "res://assets/music/town_%s.wav" % nation)
		print("town_%s.wav done" % nation)
	_save(_render_waves(), "res://assets/music/waves.wav")
	print("waves.wav done")
	quit(0)


func _save(buf: PackedFloat32Array, path: String) -> void:
	# Soft limiter: scale down only if the mix clips.
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	if peak > 0.95:
		var k := 0.95 / peak
		for i in buf.size():
			buf[i] *= k
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

## Soft lead voice: near-sine with gentle vibrato, slow attack/release.
func _lead(buf: PackedFloat32Array, start_s: float, dur_s: float, freq: float, amp: float) -> void:
	var start := int(start_s * RATE)
	var n := int(dur_s * RATE)
	var atk := int(0.06 * RATE)
	var rel := int(0.22 * RATE)
	for i in n:
		var idx := start + i
		if idx >= buf.size():
			break
		var env := 1.0
		if i < atk:
			env = float(i) / atk
		if i > n - rel:
			env = minf(env, float(n - i) / rel)
		# Vibrato eases in so the note starts clean.
		var vib := 1.0 + 0.004 * sin(TAU * 5.0 * i / RATE) * minf(float(i) / (0.4 * RATE), 1.0)
		var ph := TAU * freq * vib * i / RATE
		buf[idx] += (sin(ph) + 0.10 * sin(ph * 2.0)) * amp * env


# Note frequencies used by the tracks (A4 = 440).
const A1 := 55.0
const E2 := 82.41
const F2 := 87.31
const G2 := 98.0
const A2 := 110.0
const C3 := 130.81
const D3 := 146.83
const E3 := 164.81
const F3 := 174.61
const G3 := 196.0
const A3 := 220.0
const C4 := 261.63
const D4 := 293.66
const E4 := 329.63
const F4 := 349.23
const G4 := 392.0
const A4 := 440.0
const C5 := 523.25
const D5 := 587.33
const E5 := 659.26
const C2 := 65.41
const D2 := 73.42
const FS3 := 185.0
const B3 := 246.94
const FS4 := 369.99
const B4 := 493.88


## Bright main theme: C major, 78 bpm, 16 bars — majors only, no minor
## chord anywhere, so it cannot sound melancholic.
## Guitar-style broken chords, soft bass, and a pentatonic melody that only
## uses tones of the current chord — nothing can clash by construction.
func _render_theme() -> PackedFloat32Array:
	var bpm := 78.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var total := bar * 16.0
	var buf := PackedFloat32Array()
	buf.resize(int(total * RATE))

	# Two passes over: C  F  C  G — all sunshine.
	var chords := [
		{"bass": C2, "arp": [C3, E3, G3, C4]},
		{"bass": F2, "arp": [F2, A2, C3, F3]},
		{"bass": C2, "arp": [C3, E3, G3, C4]},
		{"bass": G2, "arp": [G2, D3, G3, D4]},
	]
	# Gentle fingerpicking: low - mid - high - mid, twice a bar.
	var pick := [0, 1, 2, 3, 2, 1, 2, 1]
	for b in 16:
		var ch: Dictionary = chords[b % 4]
		var t0 := b * bar
		var arp: Array = ch["arp"]
		for e in 8:
			var f: float = arp[pick[e]]
			_pluck(buf, t0 + e * beat * 0.5, f, 0.055, 0.7)
		# Bass: root on 1, a lighter fifth on 3.
		_tone(buf, t0, beat * 1.8, ch["bass"], 0.085, 0.015, beat * 0.8, [1.0, 0.18])
		_tone(buf, t0 + beat * 2.0, beat * 1.6, float(arp[2]) * 0.5, 0.045, 0.015, beat * 0.7, [1.0, 0.18])

	# Melody phrase over 8 bars: [start_beat, freq, dur_beats].
	# Every long note is a tone of the chord sounding under it.
	var phrase := [
		[0.0, E4, 2.0], [2.0, G4, 1.5],                    # C
		[4.0, A4, 2.0], [6.0, C5, 1.5],                    # F
		[8.0, G4, 2.0], [10.0, E4, 2.0],                   # C
		[12.0, D5, 2.5],                                   # G
		[16.0, E5, 1.0], [17.0, D5, 1.0], [18.0, C5, 2.0], # C
		[20.0, A4, 2.0], [22.0, F4, 1.5],                  # F
		[24.0, G4, 1.0], [25.0, E4, 1.0], [26.0, G4, 2.0], # C
		[28.0, D5, 2.0], [30.0, G4, 1.5],                  # G
	]
	# Pass 1: harp plucks.  Pass 2: a soft flute takes the same phrase.
	for note in phrase:
		var t: float = float(note[0]) * beat
		_pluck(buf, t, float(note[1]), 0.10, 1.1)
	for note in phrase:
		var t: float = bar * 8.0 + float(note[0]) * beat
		_lead(buf, t, float(note[2]) * beat, float(note[1]), 0.055)
		_pluck(buf, t, float(note[1]) * 0.5, 0.035, 1.2)
	return buf


## Sea shanty for the open sea: D major jig, 100 bpm — oom-pah bass,
## strummed chords, a jaunty pentatonic tune and a foot-stomp beat.
func _render_shanty() -> PackedFloat32Array:
	var bpm := 100.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var total := bar * 16.0
	var buf := PackedFloat32Array()
	buf.resize(int(total * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21

	# D  G  D  A, twice per pass: [bass, chord tones]
	var prog := [
		{"bass": D2, "chord": [D3, FS3, A3]},
		{"bass": G2, "chord": [G3 / 2.0, B3 / 2.0, D3]},
		{"bass": D2, "chord": [D3, FS3, A3]},
		{"bass": A2 / 2.0, "chord": [A2, E3, A3]},
	]
	for b in 16:
		var ch: Dictionary = prog[b % 4]
		var t0 := b * bar
		# Oom-pah: root on 1 and 3, fifth on 2 and 4.
		for k in 4:
			var f: float = float(ch["bass"]) if k % 2 == 0 else float(ch["bass"]) * 1.5
			_tone(buf, t0 + k * beat, beat * 0.8, f, 0.10, 0.01, beat * 0.3, [1.0, 0.2])
		# Quick strum roll on every beat.
		for k in 4:
			var chord: Array = ch["chord"]
			for ci in chord.size():
				_pluck(buf, t0 + k * beat + ci * 0.018, float(chord[ci]), 0.045, 0.28)
		# Foot stomp on 1 and 3, clap on 2 and 4.
		for k in 4:
			if k % 2 == 0:
				_tone(buf, t0 + k * beat, 0.14, 60.0, 0.15, 0.004, 0.11, [1.0])
			else:
				_noise_burst(buf, t0 + k * beat, 0.07, 0.045, rng)

	# The tune: D major pentatonic, jig-like eighth runs. [beat, freq, dur].
	var tune := [
		[0.0, D4, 1.0], [1.0, E4, 0.5], [1.5, FS4, 0.5], [2.0, A4, 1.5],
		[4.0, B4, 1.0], [5.0, A4, 0.5], [5.5, G4, 0.5], [6.0, D4 * 2.0, 1.5],
		[8.0, A4, 1.0], [9.0, FS4, 0.5], [9.5, D4, 0.5], [10.0, FS4, 1.5],
		[12.0, E4, 1.0], [13.0, A4, 1.0], [14.0, E4 * 2.0, 1.5],
		[16.0, D4 * 2.0, 1.0], [17.0, B4, 0.5], [17.5, A4, 0.5], [18.0, FS4, 1.5],
		[20.0, G4, 1.0], [21.0, B4, 1.0], [22.0, D4 * 2.0, 1.5],
		[24.0, A4, 0.5], [24.5, B4, 0.5], [25.0, A4, 0.5], [25.5, FS4, 0.5], [26.0, D4, 1.5],
		[28.0, E4, 1.0], [29.0, FS4 / 2.0 * 3.0, 1.0], [30.0, D4, 2.0],
	]
	for pass_i in 2:
		for note in tune:
			var t: float = pass_i * bar * 8.0 + float(note[0]) * beat
			_pluck(buf, t, float(note[1]), 0.11, 0.5)
			if pass_i == 1:
				# Second pass: a fife doubles the tune an octave up.
				_lead(buf, t, float(note[2]) * beat, float(note[1]) * 2.0, 0.028)
	return buf


# Every nation's towns get their own character:
# England — a bouncy hornpipe; France — a gentle waltz; Spain — a guitar
# piece over the Andalusian cadence; Holland — a square folk dance;
# Pirates — a rowdy minor jig with stomps.
const TOWN_TUNES := {
	"england": {"bpm": 112.0, "beats": 4, "seed": 3, "lead": false, "perc": "soft",
		"prog": [
			{"bass": A1 * 2.0, "arp": [A3, 277.18, E4, A4]},
			{"bass": D3 / 2.0, "arp": [D3, FS3, A3, D4]},
			{"bass": A1 * 2.0, "arp": [A3, 277.18, E4, A4]},
			{"bass": E2, "arp": [E3, 207.65 * 2.0, B3, E4]}]},
	"france": {"bpm": 88.0, "beats": 3, "seed": 5, "lead": true, "perc": "waltz",
		"prog": [
			{"bass": F2, "arp": [F3, A3, C4, F4]},
			{"bass": 116.54, "arp": [116.54 * 2.0, D4, F4, 116.54 * 4.0]},
			{"bass": C2 * 2.0, "arp": [C3 * 2.0, E4, G4, C5]},
			{"bass": F2, "arp": [F3, A3, C4, F4]}]},
	"spain": {"bpm": 102.0, "beats": 4, "seed": 8, "lead": false, "perc": "none",
		"prog": [
			{"bass": A2, "arp": [A3, C4, E4, A4]},
			{"bass": G2, "arp": [G3, B3, D4, G4]},
			{"bass": F2 * 2.0, "arp": [F3, A3, C4, F4]},
			{"bass": E2 * 2.0, "arp": [E3, 207.65 * 2.0, B3, E4]}]},
	"holland": {"bpm": 96.0, "beats": 4, "seed": 11, "lead": true, "perc": "soft",
		"prog": [
			{"bass": G2, "arp": [G3, B3, D4, G4]},
			{"bass": C2 * 2.0, "arp": [C3 * 2.0, E4, G4, C5]},
			{"bass": D3 / 2.0, "arp": [D3, FS3, A3, D4]},
			{"bass": G2, "arp": [G3, B3, D4, G4]}]},
	"pirates": {"bpm": 108.0, "beats": 4, "seed": 13, "lead": false, "perc": "stomp",
		"prog": [
			{"bass": E2, "arp": [E3, G3, B3, E4]},
			{"bass": D3 / 2.0, "arp": [D3, FS3, A3, D4]},
			{"bass": E2, "arp": [E3, G3, B3, E4]},
			{"bass": 61.74, "arp": [B3 / 2.0, D3, FS3, B3]}]},
}


## Parametric town tune: oom-pah (or waltz) bass, strummed chords, and a
## melody improvised from chord tones — deterministic per nation seed.
func _render_town(cfg: Dictionary) -> PackedFloat32Array:
	var bpm: float = cfg["bpm"]
	var beats: int = cfg["beats"]
	var beat := 60.0 / bpm
	var bar := beat * float(beats)
	var prog: Array = cfg["prog"]
	var bars := prog.size() * 4
	var buf := PackedFloat32Array()
	buf.resize(int(bar * bars * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"])
	var perc: String = cfg["perc"]

	for b in bars:
		var ch: Dictionary = prog[b % prog.size()]
		var t0 := b * bar
		var arp: Array = ch["arp"]
		if beats == 3:
			# Waltz: bass on 1, chord on 2 and 3.
			_tone(buf, t0, beat * 0.9, float(ch["bass"]), 0.10, 0.01, beat * 0.35, [1.0, 0.2])
			for k in [1, 2]:
				for ci in 3:
					_pluck(buf, t0 + k * beat + ci * 0.015, float(arp[ci]), 0.04, 0.24)
		else:
			for k in beats:
				var f: float = float(ch["bass"]) if k % 2 == 0 else float(ch["bass"]) * 1.5
				_tone(buf, t0 + k * beat, beat * 0.8, f, 0.09, 0.01, beat * 0.3, [1.0, 0.2])
				if k % 2 == 1:
					for ci in 3:
						_pluck(buf, t0 + k * beat + ci * 0.015, float(arp[ci]), 0.042, 0.24)
		match perc:
			"soft":
				_noise_burst(buf, t0 + beat * (beats - 1), 0.05, 0.035, rng)
			"waltz":
				_noise_burst(buf, t0 + beat, 0.035, 0.03, rng)
				_noise_burst(buf, t0 + beat * 2.0, 0.035, 0.03, rng)
			"stomp":
				_tone(buf, t0, 0.13, 58.0, 0.14, 0.004, 0.10, [1.0])
				_tone(buf, t0 + beat * 2.0, 0.13, 58.0, 0.12, 0.004, 0.10, [1.0])
				_noise_burst(buf, t0 + beat * 3.0, 0.07, 0.04, rng)
		# Melody: chord tones only, so it can never clash.
		var n_notes := rng.randi_range(2, beats)
		for i in n_notes:
			var start := t0 + float(i) * bar / float(n_notes)
			var tone_f: float = float(arp[rng.randi_range(1, arp.size() - 1)])
			if rng.randf() < 0.35:
				tone_f *= 2.0
			_pluck(buf, start, tone_f, 0.10, 0.5)
			if bool(cfg["lead"]) and b >= bars / 2 and i == 0:
				_lead(buf, start, bar / float(n_notes) * 0.9, tone_f, 0.03)
	return buf


## Battle track: A minor, 96 bpm, 8 bars — driving low strings and war drums.
## Harmony stays on Am / F / E chord tones, so it is tense but never sour.
func _render_battle() -> PackedFloat32Array:
	var bpm := 96.0
	var beat := 60.0 / bpm
	var bar := beat * 4.0
	var total := bar * 8.0
	var buf := PackedFloat32Array()
	buf.resize(int(total * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# Low string ostinato, eighths: changes with the chord underneath.
	var ost_am := [A2, A2, C3, A2, E3, A2, C3, A2]
	var ost_f := [F2, F2, A2, F2, C3, F2, A2, F2]
	var ost_e := [E2, E2, G3 / 2.0, E2, 123.47, E2, G3 / 2.0, E2]  # E B G# -> E minor-major color
	# 8-bar arc: Am Am F Am | Am F E Am
	var bars := [ost_am, ost_am, ost_f, ost_am, ost_am, ost_f, ost_e, ost_am]
	var swell := [A3, A3, F3, A3, A3, F3, E3 * 2.0, A3]
	for b in 8:
		var ost: Array = bars[b]
		for e in 8:
			var t := b * bar + e * beat * 0.5
			_pluck(buf, t, float(ost[e]), 0.085, 0.20)
		# One restrained string swell per bar, always a chord tone.
		_tone(buf, b * bar, bar * 0.85, float(swell[b]), 0.04, bar * 0.35, bar * 0.35, [1.0, 0.35, 0.12])

	# War drums: deep hit on 1 and 3, snare answer on 4.
	for b in 8:
		for k in 4:
			var t := b * bar + k * beat
			if k % 2 == 0:
				_tone(buf, t, 0.20, 52.0, 0.20, 0.004, 0.16, [1.0, 0.3])
			if k == 3:
				_noise_burst(buf, t, 0.10, 0.06, rng)
		# A quiet double-tap leading into the next bar.
		_tone(buf, b * bar + 3.5 * beat, 0.12, 52.0, 0.11, 0.004, 0.10, [1.0])
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
