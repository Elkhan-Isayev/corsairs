## Archipelago map styled as a sea chart: procedural island shapes,
## textured water, a compass rose. Click an island to sail there.
extends Control

const World := preload("res://core/world.gd")

const MAP_W := 1000.0
const MAP_H := 800.0

var _status: Label
var _log_label: RichTextLabel
var _map_area: Control


func _ready() -> void:
	Music.play_theme()
	_build_ocean()

	var top_panel := PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.04, 0.09, 0.14, 0.85)
	top_style.content_margin_left = 12
	top_style.content_margin_right = 12
	top_style.content_margin_top = 6
	top_style.content_margin_bottom = 6
	top_panel.add_theme_stylebox_override("panel", top_style)
	add_child(top_panel)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	top_panel.add_child(top)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("e8c872"))
	top.add_child(_status)

	var back := Button.new()
	back.text = "To port"
	back.pressed.connect(func(): Game.goto_port())
	top.add_child(back)

	var menu_btn := Button.new()
	menu_btn.text = "Menu"
	menu_btn.pressed.connect(func(): Game.save_game(); Game.goto_menu())
	top.add_child(menu_btn)

	_map_area = Control.new()
	_map_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.offset_top = 48
	_map_area.offset_bottom = -140
	add_child(_map_area)

	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	log_panel.offset_top = -132
	var log_style := StyleBoxFlat.new()
	log_style.bg_color = Color(0.04, 0.09, 0.14, 0.8)
	log_style.content_margin_left = 12
	log_style.content_margin_top = 8
	log_panel.add_theme_stylebox_override("panel", log_style)
	add_child(log_panel)

	_log_label = RichTextLabel.new()
	_log_label.bbcode_enabled = true
	_log_label.add_theme_color_override("default_color", Color("cfe3f5"))
	log_panel.add_child(_log_label)

	_build_islands()
	_refresh_status()
	_show_last_log()


## Layered ocean: deep base + two scrolling-scale noise textures.
func _build_ocean() -> void:
	var base := ColorRect.new()
	base.color = Color("0e3963")
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(base)

	for layer in [
		{"freq": 0.004, "modulate": Color(0.35, 0.62, 0.85, 0.30)},
		{"freq": 0.015, "modulate": Color(0.55, 0.80, 0.95, 0.12)},
	]:
		var noise := FastNoiseLite.new()
		noise.frequency = layer["freq"]
		noise.fractal_octaves = 3
		var ntex := NoiseTexture2D.new()
		ntex.noise = noise
		ntex.seamless = true
		ntex.width = 512
		ntex.height = 512
		var tr := TextureRect.new()
		tr.texture = ntex
		tr.stretch_mode = TextureRect.STRETCH_TILE
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.modulate = layer["modulate"]
		add_child(tr)


func _map_to_screen(pos: Array) -> Vector2:
	var size := _map_area.size
	if size.x < 10:
		size = Vector2(1280, 530)
	return Vector2(pos[0] / MAP_W * size.x, pos[1] / MAP_H * size.y)


func _build_islands() -> void:
	await get_tree().process_frame  # wait for layout so the area size is known
	for id in World.island_ids():
		var isl := World.island(id)
		var center := _map_to_screen(isl["pos"])
		var here: bool = Game.state.current_island == id
		var closed: bool = Game.state.world.is_port_hostile(id)
		_draw_island_shape(id, center, int(isl["tier"]))
		_place_island_label(id, isl, center, here, closed)
	_add_compass_rose()


## Irregular island blob: shoal ring, beach, land, highland.
func _draw_island_shape(id: String, center: Vector2, tier: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var base_r := 26.0 + tier * 9.0
	var points := PackedVector2Array()
	var n := 14
	for i in n:
		var ang := float(i) / n * TAU
		var r := base_r * (0.72 + rng.randf() * 0.55)
		points.append(Vector2(cos(ang), sin(ang) * 0.8) * r)

	var layers := [
		{"scale": 1.45, "color": Color(0.45, 0.78, 0.82, 0.35)},  # shoal water
		{"scale": 1.14, "color": Color("cbb182")},                 # beach
		{"scale": 1.0, "color": Color("4d7c44")},                  # land
		{"scale": 0.52, "color": Color("3a6234")},                 # highland
	]
	for layer in layers:
		var poly := Polygon2D.new()
		var scaled := PackedVector2Array()
		for p in points:
			scaled.append(p * layer["scale"])
		poly.polygon = scaled
		poly.color = layer["color"]
		poly.position = center
		_map_area.add_child(poly)


func _place_island_label(id: String, isl: Dictionary, center: Vector2, here: bool, closed: bool) -> void:
	var btn := Button.new()
	var nation_name: String = World.NATIONS[isl["nation"]]["name"]
	btn.text = "%s%s (%s)%s" % ["⚓ " if here else "", isl["name"], nation_name, "  ✖" if closed else ""]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.11, 0.75)
	style.border_color = Color("e8c87255")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	btn.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.10, 0.18, 0.26, 0.9)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	var text_color := Color(World.NATIONS[isl["nation"]]["color"]).lightened(0.35)
	if isl["nation"] == "pirates":
		text_color = Color("b0bec5")
	btn.add_theme_color_override("font_color", text_color)
	btn.add_theme_color_override("font_hover_color", text_color.lightened(0.2))
	btn.disabled = here
	btn.pressed.connect(_on_island_clicked.bind(id))
	_map_area.add_child(btn)
	# Center the label under the island blob.
	await get_tree().process_frame
	btn.position = center + Vector2(-btn.size.x / 2.0, 30.0 + isl["tier"] * 9.0)


func _add_compass_rose() -> void:
	var rose := CompassRose.new()
	rose.position = Vector2(_map_area.size.x - 120, 110)
	_map_area.add_child(rose)


func _refresh_status() -> void:
	var s = Game.state
	var isl_name: String = World.island(s.current_island)["name"] if s.current_island != "" else "at sea"
	_status.text = "Day %d  |  %s  |  %s: %d gold  |  Ship: %s (crew %d)  |  Wind: %d° / %.0f kn" % [
		s.day, isl_name, s.character.char_name, s.character.gold,
		s.ship.custom_name, s.ship.crew, int(s.wind["from"]), s.wind["strength"]]


func _show_last_log() -> void:
	var log: Dictionary = Game.last_sail_log
	if log.is_empty():
		var here: String = World.island(Game.state.current_island)["name"] if Game.state.current_island != "" else "the open sea"
		_log_label.text = "Departing from %s — click a destination island." % here
		return
	var lines: Array = ["The passage took %d day(s). Wages paid: %d gold." % [log["days"], log["wages_paid"]]]
	if int(log.get("starved", 0)) > 0:
		lines.append("[color=#e57373]%d crew starved to death![/color]" % log["starved"])
	for q in log.get("completed_quests", []):
		lines.append("[color=#81c784]Quest completed: %s (+%d gold)[/color]" % [q["title"], q["reward"]])
	var enc = log.get("encounter")
	if enc != null and not enc["hostile"]:
		lines.append("Met a %s ship (%s) — passed peacefully." % [
			World.NATIONS[enc["nation"]]["name"], enc["ship_type"]])
	_log_label.text = "\n".join(lines)
	Game.last_sail_log = {}


func _on_island_clicked(id: String) -> void:
	if Game.state.world.is_port_hostile(id):
		_log_label.text = "[color=#e57373]The port of %s is closed to you: the colony is hostile. You can still anchor offshore...[/color]" % World.island(id)["name"]
	var battle: bool = Game.sail_to(id)
	if not battle:
		# Redraw the map on arrival.
		get_tree().reload_current_scene()


## A 8-point compass rose drawn with polygons.
class CompassRose extends Control:
	func _draw() -> void:
		var r := 70.0
		draw_circle(Vector2.ZERO, r + 8, Color(0.03, 0.07, 0.11, 0.55))
		draw_arc(Vector2.ZERO, r + 4, 0, TAU, 64, Color("e8c872"), 2.0)
		draw_arc(Vector2.ZERO, r - 16, 0, TAU, 64, Color("e8c87288"), 1.0)
		for i in 8:
			var ang := float(i) / 8.0 * TAU - PI / 2.0
			var tip := Vector2(cos(ang), sin(ang)) * (r if i % 2 == 0 else r * 0.62)
			var left := Vector2(cos(ang - 0.16), sin(ang - 0.16)) * r * 0.16
			var right := Vector2(cos(ang + 0.16), sin(ang + 0.16)) * r * 0.16
			draw_colored_polygon(PackedVector2Array([tip, left, Vector2.ZERO]), Color("e8c872"))
			draw_colored_polygon(PackedVector2Array([tip, Vector2.ZERO, right]), Color("8a6a3f"))
		var font := ThemeDB.fallback_font
		var labels := {"N": Vector2(0, -r - 14), "E": Vector2(r + 8, 0), "S": Vector2(0, r + 20), "W": Vector2(-r - 20, 0)}
		for t in labels:
			draw_string(font, labels[t] + Vector2(-5, 5), t, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, Color("e8c872"))
