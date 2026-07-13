## Headless walk through every scene: godot --headless --path . -s tests/smoke_scenes.gd
## Verifies that each scene loads and survives a few frames without errors.
extends SceneTree

var _step := 0
var _frames := 0
var _errors: Array = []


func _initialize() -> void:
	# The Game autoload must be present.
	if root.get_node_or_null("Game") == null:
		print("FATAL: Game autoload is missing")
		quit(1)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 20 != 0:
		return false
	var game = root.get_node("Game")
	# Advance BEFORE running the step so a crashing step can't loop forever.
	var step := _step
	_step += 1
	match step:
		0:
			_check_scene("res://scenes/main_menu.tscn", "main_menu")
			change_scene_to_file("res://scenes/main_menu.tscn")
		1:
			game.state = load("res://core/game_state.gd").new_game("Smoke", "england", 99)
			change_scene_to_file("res://scenes/port.tscn")
		2:
			_expect(current_scene != null and current_scene.name == "Port", "port UI opened")
			change_scene_to_file("res://scenes/port_town.tscn")
		3:
			_expect(current_scene != null and current_scene.name == "PortTown", "port town opened")
			_expect(current_scene.player != null, "town player built")
			change_scene_to_file("res://scenes/world_map.tscn")
		4:
			_expect(current_scene != null and current_scene.name == "WorldMap", "map opened")
			game.pending_encounter = {"nation": "pirates", "ship_type": "sloop", "hostile": true}
			change_scene_to_file("res://scenes/sea.tscn")
		5:
			_expect(current_scene != null and current_scene.name == "SeaBattle", "sea battle started")
			var battle = current_scene
			_expect(battle.enemy_ship != null, "enemy created")
			_expect(battle.player_node != null, "player ship built")
		6:
			# Let the battle physics run a couple more seconds.
			pass
		7:
			game.boarding_ctx = {
				"enemy": load("res://core/game_state.gd").new_game("Foe", "pirates", 5).ship,
				"nation": "pirates",
			}
			change_scene_to_file("res://scenes/boarding.tscn")
		8:
			_expect(current_scene != null and current_scene.name == "BoardingDeck", "boarding deck started")
			_expect(current_scene.player != null and not current_scene.player.is_empty(), "captain spawned")
			_expect(current_scene._fighters.size() > 0, "fighters spawned")
		9:
			for e in _errors:
				print("FAIL: %s" % e)
			print("SMOKE %s" % ("PASSED" if _errors.is_empty() else "FAILED"))
			quit(0 if _errors.is_empty() else 1)
	return false


func _check_scene(path: String, label: String) -> void:
	var packed = load(path)
	_expect(packed != null, "%s loads" % label)


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		_errors.append(what)
