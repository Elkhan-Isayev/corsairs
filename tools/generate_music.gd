## Offline synthesizer for the harbor surf ambience (the score itself is
## Suno-composed MP3s in assets/music/).
## Run once: godot --headless --path . -s tools/generate_music.gd
## Produces: assets/music/waves.wav (loopable).
extends SceneTree

const RATE := 22050


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/music"))
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
