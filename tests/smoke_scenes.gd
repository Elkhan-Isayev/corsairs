## Headless-обход всех сцен: godot --headless --path . -s tests/smoke_scenes.gd
## Проверяет, что каждая сцена загружается и живёт несколько кадров без ошибок.
extends SceneTree

var _step := 0
var _frames := 0
var _errors: Array = []


func _initialize() -> void:
	# Автозагрузка Game должна быть на месте.
	if root.get_node_or_null("Game") == null:
		print("FATAL: autoload Game отсутствует")
		quit(1)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames % 20 != 0:
		return false
	var game = root.get_node("Game")
	match _step:
		0:
			_check_scene("res://scenes/main_menu.tscn", "main_menu")
			change_scene_to_file("res://scenes/main_menu.tscn")
		1:
			game.state = load("res://core/game_state.gd").new_game("Смоук", "england", 99)
			change_scene_to_file("res://scenes/port.tscn")
		2:
			_expect(current_scene != null and current_scene.name == "Port", "порт открылся")
			change_scene_to_file("res://scenes/world_map.tscn")
		3:
			_expect(current_scene != null and current_scene.name == "WorldMap", "карта открылась")
			game.pending_encounter = {"nation": "pirates", "ship_type": "sloop", "hostile": true}
			change_scene_to_file("res://scenes/sea.tscn")
		4:
			_expect(current_scene != null and current_scene.name == "SeaBattle", "морской бой запустился")
			var battle = current_scene
			_expect(battle.enemy_ship != null, "враг создан")
			_expect(battle.player_node != null, "корабль игрока построен")
		5:
			# Дать бою покрутиться ещё пару секунд физики.
			pass
		6:
			for e in _errors:
				print("FAIL: %s" % e)
			print("SMOKE %s" % ("PASSED" if _errors.is_empty() else "FAILED"))
			quit(0 if _errors.is_empty() else 1)
	_step += 1
	return false


func _check_scene(path: String, label: String) -> void:
	var packed = load(path)
	_expect(packed != null, "%s загружается" % label)


func _expect(cond: bool, what: String) -> void:
	if cond:
		print("  ok: %s" % what)
	else:
		_errors.append(what)
