## "Music" autoload: looping background tracks with a soft crossfade.
## The score was composed with Suno (assets/music/*.mp3); towns have no
## music — only the ambient surf of the harbor (waves.wav).
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


func _load_loop(path: String) -> AudioStream:
	var stream: AudioStream = load(path)
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / 2  # 16-bit mono frames
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	return stream


## Main menu and the port screens.
func play_theme() -> void:
	_play("res://assets/music/theme.mp3", -8.0)


func play_battle() -> void:
	_play("res://assets/music/battle.mp3", -8.0)


## Sailing the open sea and free sailing after a battle.
func play_sea() -> void:
	_play("res://assets/music/sea.mp3", -9.0)


## Towns: no music, just the surf and the harbor.
func play_ambience() -> void:
	_play("res://assets/music/waves.wav", -12.0)


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
