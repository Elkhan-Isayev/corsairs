## "Game" autoload: holds the session state and routes between scenes.
extends Node

const GameState := preload("res://core/game_state.gd")

var state: RefCounted = null
## Encounter awaiting a sea battle: {"nation", "ship_type", "hostile"}
var pending_encounter: Dictionary = {}
## Tab the port UI should open on (-1 = keep last).
var port_tab: int = -1
## Context for the on-deck boarding fight: {"enemy": Ship, "nation": String}
var boarding_ctx: Dictionary = {}
## Where to put the ship on the open sea: {"pos", "heading"} to resume
## after a battle, or {"from_island"} when leaving a port.
var open_sea_ctx: Dictionary = {}
## A friendly/neutral encounter sailing alongside in free-sail mode:
## the same {"nation", "ship_type", "count"} dict, or {} for empty seas.
var free_sail_company: Dictionary = {}

## Visual clock for the day/night cycle: 0..24, a full day in 8 real minutes.
var time_of_day := 10.0

var _loading: CanvasLayer
var _loading_lbl: Label


func _ready() -> void:
	_build_loading_overlay()


func _process(delta: float) -> void:
	time_of_day = wrapf(time_of_day + delta * (24.0 / 480.0), 0.0, 24.0)


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


## The open sea — the sailable world map. Resumes from open_sea_ctx.
func goto_map() -> void:
	_change_scene("res://scenes/open_sea.tscn", "The open sea")


## Cast off from the current port and head for the open sea.
func goto_open_sea_from_port() -> void:
	open_sea_ctx = {"from_island": state.current_island}
	state.depart()
	goto_map()


## The walkable 3D town — the default view when in a port.
func goto_port() -> void:
	var title := "Landfall"
	if state != null and state.current_island != "":
		title = load("res://core/world.gd").island(state.current_island)["name"]
	_change_scene("res://scenes/port_town.tscn", title)


## The port menu UI (tabs); tab -1 keeps the last one open.
func goto_port_ui(tab: int = -1) -> void:
	port_tab = tab
	get_tree().change_scene_to_file("res://scenes/port.tscn")


func goto_sea_battle(encounter: Dictionary) -> void:
	pending_encounter = encounter
	_change_scene("res://scenes/sea.tscn", "Battle stations!")


## Deck-scale sailing with no enemy — Enter on the world map. A peaceful
## sail nearby comes along as company to look at.
func goto_free_sail(company: Dictionary = {}) -> void:
	pending_encounter = {}
	free_sail_company = company
	_change_scene("res://scenes/sea.tscn", "Open waters")


## Third-person melee on the enemy deck; the fight decides the encounter.
func start_boarding(enemy: RefCounted, nation: String) -> void:
	boarding_ctx = {"enemy": enemy, "nation": nation}
	_change_scene("res://scenes/boarding.tscn", "Boarding!")


# --- Loading screen ---

## Swap scenes behind a brief loading overlay (the 3D scenes build
## everything procedurally in _ready, which takes a visible moment).
func _change_scene(path: String, title: String) -> void:
	_loading_lbl.text = title
	_loading.visible = true
	# Give the overlay two frames to reach the screen before the hitch.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	_loading.visible = false


func _build_loading_overlay() -> void:
	_loading = CanvasLayer.new()
	_loading.layer = 100
	_loading.visible = false
	add_child(_loading)

	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.06, 0.09)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)

	# A drawn ship's wheel: the web build's font has no emoji glyphs.
	var wheel := Control.new()
	wheel.custom_minimum_size = Vector2(96, 96)
	wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wheel.draw.connect(func():
		var c := wheel.custom_minimum_size / 2.0
		var gold := Color("f3d98a")
		wheel.draw_arc(c, 30.0, 0.0, TAU, 48, gold, 4.0, true)
		wheel.draw_circle(c, 8.0, gold)
		for i in 8:
			var dir := Vector2.RIGHT.rotated(TAU * i / 8.0)
			wheel.draw_line(c + dir * 8.0, c + dir * 44.0, gold, 3.0))
	box.add_child(wheel)

	_loading_lbl = Label.new()
	_loading_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_lbl.add_theme_font_size_override("font_size", 30)
	_loading_lbl.add_theme_color_override("font_color", Color("f0e6d0"))
	box.add_child(_loading_lbl)

	var sub := Label.new()
	sub.text = "Loading..."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78))
	box.add_child(sub)
