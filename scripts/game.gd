## Автозагрузка «Game»: держит состояние партии и переключает сцены.
extends Node

const GameState := preload("res://core/game_state.gd")

var state: RefCounted = null
## Встреча, ожидающая морского боя: {"nation", "ship_type", "hostile"}
var pending_encounter: Dictionary = {}
## Журнал последнего перехода (для показа на карте).
var last_sail_log: Dictionary = {}


func new_game(captain_name: String, nation: String) -> void:
	state = GameState.new_game(captain_name, nation)
	goto_port()


func continue_game() -> bool:
	var loaded = GameState.load_from_file()
	if loaded == null:
		return false
	state = loaded
	goto_port()
	return true


func save_game() -> bool:
	if state == null:
		return false
	return state.save_to_file()


func goto_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func goto_map() -> void:
	get_tree().change_scene_to_file("res://scenes/world_map.tscn")


func goto_port() -> void:
	get_tree().change_scene_to_file("res://scenes/port.tscn")


func goto_sea_battle(encounter: Dictionary) -> void:
	pending_encounter = encounter
	get_tree().change_scene_to_file("res://scenes/sea.tscn")


## Плавание с карты. Возвращает true, если начался морской бой.
func sail_to(island_id: String) -> bool:
	last_sail_log = state.sail_to(island_id)
	save_game()
	var enc = last_sail_log.get("encounter")
	if enc != null and enc["hostile"]:
		goto_sea_battle(enc)
		return true
	return false
