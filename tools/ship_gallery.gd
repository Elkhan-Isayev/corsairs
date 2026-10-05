## Captures every ship class in the battle scene from a three-quarter view.
## Run windowed: godot --path . -s tools/ship_gallery.gd -- OUT_DIR [type,type...]
extends SceneTree

const SHOTS := [
	["tartane", "pirates"], ["lugger", "holland"], ["sloop", "england"],
	["schooner", "france"], ["barque", "holland"], ["brig", "france"],
	["galleon", "spain"], ["corvette", "england"], ["frigate", "france"],
	["battleship", "england"], ["manowar", "spain"],
]

var _out := "user://ship_gallery"
var _queue: Array = []
var _frames := 0
var _current: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	var only: Array = args[1].split(",") if args.size() > 1 else []
	for s in SHOTS:
		if only.is_empty() or only.has(s[0]):
			_queue.append(s)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 5:
		_next()
	elif _current.size() > 0 and current_scene != null and current_scene.name == "SeaBattle":
		var b = current_scene
		var len: float = b.player_len
		b.cam_yaw = 128.0
		b.cam_pitch = 11.0
		b.cam_dist = len * 1.9
		b.player_ship.sail_setting = 1.0
		# Keep the enemy out of frame.
		b.enemy_node.position = b.player_node.position + Vector3(-400, 0, 600)
		if _frames % 90 == 0:
			_shoot()
	return false


func _next() -> void:
	if _queue.is_empty():
		print("GALLERY DONE")
		quit(0)
		return
	_current = _queue.pop_front()
	var game = root.get_node("Game")
	game.state = load("res://core/game_state.gd").new_game("Gallery", _current[1], 3)
	var ship = load("res://core/ship.gd").create(_current[0])
	ship.custom_name = "Gallery"
	game.state.ship = ship
	game.pending_encounter = {"nation": "pirates", "ship_type": "sloop", "hostile": true}
	_frames = 6
	change_scene_to_file("res://scenes/sea.tscn")


func _shoot() -> void:
	_capture_async("%s_%s" % [_current[0], _current[1]])
	_current = []
	_frames = 0


func _capture_async(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [_out, name])
	img.save_png(path)
	print("shot ", path)
