## Captures screenshots of every scene into docs/screenshots/.
## Run windowed (NOT headless): godot --path . -s tools/screenshots.gd
extends SceneTree

const OUT_DIR := "res://docs/screenshots"

var _frames := 0
var _done := false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


func _process(_delta: float) -> bool:
	_frames += 1
	match _frames:
		5:
			# With -s the main scene does not load by itself.
			change_scene_to_file("res://scenes/main_menu.tscn")
		40:
			_capture("menu")
		60:
			var game = root.get_node("Game")
			game.state = load("res://core/game_state.gd").new_game("Nathaniel", "england", 7)
			change_scene_to_file("res://scenes/port.tscn")
		100:
			_capture("port")
		120:
			change_scene_to_file("res://scenes/port_town.tscn")
		140:
			if current_scene != null and current_scene.name == "PortTown":
				current_scene.cam_yaw = 195.0
				current_scene.cam_pitch = 14.0
				current_scene.cam_dist = 22.0
		190:
			_capture("town")
		210:
			change_scene_to_file("res://scenes/world_map.tscn")
		260:
			_capture("map")
		280:
			var game = root.get_node("Game")
			game.pending_encounter = {"nation": "pirates", "ship_type": "brig", "hostile": true}
			change_scene_to_file("res://scenes/sea.tscn")
		290:
			# Full sails and a cinematic three-quarter camera angle.
			if current_scene != null and current_scene.name == "SeaBattle":
				current_scene.player_ship.sail_setting = 1.0
				current_scene.cam_yaw = 132.0
				current_scene.cam_pitch = 10.0
				current_scene.cam_dist = 55.0
		560:
			# Stage the shot: enemy up close, hit flashes for drama.
			if current_scene != null and current_scene.name == "SeaBattle":
				var b = current_scene
				b.enemy_node.position = b.player_node.position + Vector3(-70, 0, 110)
				b._spawn_shot_visuals(b.enemy_node, 8)
		572:
			_capture("battle")
		620:
			if not _done:
				_done = true
				print("SCREENSHOTS DONE")
				quit(0)
	return false


func _capture(name: String) -> void:
	_capture_async(name)


func _capture_async(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name])
	var err := img.save_png(path)
	print("shot %s -> %s (%s)" % [name, path, "ok" if err == OK else "ERROR %d" % err])
