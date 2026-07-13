## "Game" autoload: holds the session state and routes between scenes.
extends Node

const GameState := preload("res://core/game_state.gd")

var state: RefCounted = null
## Encounter awaiting a sea battle: {"nation", "ship_type", "hostile"}
var pending_encounter: Dictionary = {}
## Log of the last voyage (shown on the map).
var last_sail_log: Dictionary = {}
## Tab the port UI should open on (-1 = keep last).
var port_tab: int = -1
## Context for the on-deck boarding fight: {"enemy": Ship, "nation": String}
var boarding_ctx: Dictionary = {}


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


## The walkable 3D town — the default view when in a port.
func goto_port() -> void:
	get_tree().change_scene_to_file("res://scenes/port_town.tscn")


## The port menu UI (tabs); tab -1 keeps the last one open.
func goto_port_ui(tab: int = -1) -> void:
	port_tab = tab
	get_tree().change_scene_to_file("res://scenes/port.tscn")


func goto_sea_battle(encounter: Dictionary) -> void:
	pending_encounter = encounter
	get_tree().change_scene_to_file("res://scenes/sea.tscn")


## Third-person melee on the enemy deck; the fight decides the encounter.
func start_boarding(enemy: RefCounted, nation: String) -> void:
	boarding_ctx = {"enemy": enemy, "nation": nation}
	get_tree().change_scene_to_file("res://scenes/boarding.tscn")


## Sail from the map. Returns true if a sea battle started.
func sail_to(island_id: String) -> bool:
	last_sail_log = state.sail_to(island_id)
	save_game()
	var enc = last_sail_log.get("encounter")
	if enc != null and enc["hostile"]:
		goto_sea_battle(enc)
		return true
	return false
