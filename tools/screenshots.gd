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
		200:
			# Step inside the tavern for an interior shot.
			if current_scene != null and current_scene.name == "PortTown":
				var town = current_scene
				for it in town._interactables:
					if String(it["label"]).begins_with("Enter the tavern"):
						it["action"].call()
						break
				town.player.position += Vector3(0, 0, -3.0)
				town.cam_yaw = 25.0
				town.cam_pitch = 20.0
				town.cam_dist = 7.0
		240:
			_capture("interior")
		250:
			var game = root.get_node("Game")
			game.open_sea_ctx = {"from_island": "oxbay"}
			game.state.depart()
			change_scene_to_file("res://scenes/open_sea.tscn")
		265:
			# Stage the shot: full sails, two extra sails nearby, chase camera.
			if current_scene != null and current_scene.name == "OpenSea":
				var sea = current_scene
				root.get_node("Game").state.ship.sail_setting = 1.0
				sea._spawn_sail(90.0)
				sea._spawn_sail(140.0)
				sea.cam_yaw = 205.0
				sea.cam_pitch = 24.0
				sea.cam_dist = 95.0
		300:
			_capture("map")
		320:
			var game = root.get_node("Game")
			game.pending_encounter = {"nation": "pirates", "ship_type": "brig", "hostile": true}
			change_scene_to_file("res://scenes/sea.tscn")
		335:
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
		590:
			var game = root.get_node("Game")
			game.boarding_ctx = {
				"enemy": load("res://core/game_state.gd").new_game("Foe", "pirates", 5).ship,
				"nation": "pirates",
			}
			change_scene_to_file("res://scenes/boarding.tscn")
		600:
			if current_scene != null and current_scene.name == "BoardingDeck":
				current_scene.cam_yaw = 150.0
				current_scene.cam_pitch = 32.0
				current_scene.cam_dist = 14.0
		660:
			_capture("boarding")
		700:
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
