## "Music" autoload: looping background tracks with a soft crossfade.
extends Node

var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active: AudioStreamPlayer
var _current_track := ""


func _ready() -> void:
	_player_a = _make_player()
	_player_b = _make_player()
	_active = _player_a


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -80.0
	add_child(p)
	return p


func _load_loop(path: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load(path)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2  # 16-bit mono frames
	return stream


func play_theme() -> void:
	_play("res://assets/music/theme.wav", -9.0)


func play_battle() -> void:
	_play("res://assets/music/battle.wav", -8.0)


func _play(path: String, target_db: float) -> void:
	if _current_track == path and _active.playing:
		return
	_current_track = path
	var next := _player_b if _active == _player_a else _player_a
	next.stream = _load_loop(path)
	next.volume_db = -40.0
	next.play()
	var old := _active
	_active = next
	var tw := create_tween()
	tw.parallel().tween_property(next, "volume_db", target_db, 1.5)
	tw.parallel().tween_property(old, "volume_db", -60.0, 1.5)
	tw.tween_callback(old.stop)
