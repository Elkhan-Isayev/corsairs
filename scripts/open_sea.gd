## The open sea — the sailable world map, Sea Dogs style: your miniature
## ship among the islands, other sails on the horizon, some of them hostile.
## WASD — sails/rudder, E — drop anchor at an island, M — sea chart.
extends Node3D

const Sailing := preload("res://core/sailing.gd")
const World := preload("res://core/world.gd")
const OpenSea := preload("res://core/open_sea.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")

const SPEED_SCALE := 3.0      # knots -> world units per second on the chart
const SHIP_LEN := 11.0
const NPC_LEN := 10.0
const NPC_LIMIT := 5
const BATTLE_RANGE := 24.0    # a hostile sail this close forces the battle

var camera: Camera3D
var cam_yaw := 180.0
var cam_pitch := 33.0
var cam_dist := 85.0
var _orbiting := false

var _ship_node: Node3D
var _heading := 0.0
var _time := 0.0
var _distance_acc := 0.0
## Other sails: {node, heading, speed, enc}
var _npcs: Array = []

var hud: CanvasLayer
var _status: Label
var _hint: Label
var _log_lbl: Label
var _log_until := 0.0
var _chart: SeaChart


func _ready() -> void:
	Music.play_theme()
	_build_environment()
	_build_ocean()
	for id in World.island_ids():
		_build_island(id)
	_build_player_ship()
	_place_player()
	_build_hud()
	# A couple of distant sails so the sea never feels empty.
	for i in 2:
		_spawn_sail(320.0 + i * 120.0)


# --- World building ---

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 47, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.93, 0.8)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 500.0
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2c5d96")
	sky_mat.sky_horizon_color = Color("cfe0e8")
	sky_mat.sky_curve = 0.14
	sky_mat.ground_bottom_color = Color("0a2438")
	sky_mat.ground_horizon_color = Color("bcd2d8")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	e.fog_enabled = true
	e.fog_light_color = Color("c9d8dc")
	e.fog_density = 0.00035
	e.fog_sky_affect = 0.15
	add_child(env)
	env.environment = e


func _build_ocean() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3600, 3000)
	plane.subdivide_width = 130
	plane.subdivide_depth = 110
	water.mesh = plane
	water.position = OpenSea.map_center()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/water.gdshader")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.008
	noise.fractal_octaves = 4
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.seamless = true
	ntex.width = 512
	ntex.height = 512
	mat.set_shader_parameter("noise_tex", ntex)
	water.material_override = mat
	add_child(water)


func _build_island(id: String) -> void:
	var isl: Dictionary = World.island(id)
	var tier: int = int(isl["tier"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var root := Node3D.new()
	root.position = OpenSea.island_pos(id)
	add_child(root)
	var to_center: Vector3 = (OpenSea.map_center() - root.position)
	to_center.y = 0.0
	to_center = to_center.normalized()

	# Beach base: a wide, flat sandy shelf.
	var top_r: float = 42.0 + tier * 6.0
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = top_r
	bm.bottom_radius = top_r + 18.0
	bm.height = 3.0
	base.mesh = bm
	base.position.y = 0.4
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("d8c489")
	base.material_override = sand
	root.add_child(base)

	# Green hills inland.
	for i in 2 + tier:
		var hill := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = rng.randf_range(10.0, 16.0 + tier * 3.0)
		hm.height = rng.randf_range(10.0, 18.0)
		hill.mesh = hm
		var ang := rng.randf_range(0.0, TAU)
		var r := rng.randf_range(0.0, top_r * 0.45)
		hill.position = Vector3(cos(ang) * r, 1.5, sin(ang) * r)
		var grass := StandardMaterial3D.new()
		grass.albedo_color = Color("4c6a34").lerp(Color("64804a"), rng.randf())
		hill.material_override = grass
		root.add_child(hill)

	# The town huddles on the shore that faces open water.
	var town_dir: Vector3 = to_center
	for i in 2 + tier * 2:
		var spread := Vector3(-town_dir.z, 0, town_dir.x) * rng.randf_range(-14.0, 14.0)
		var hp: Vector3 = town_dir * (top_r * rng.randf_range(0.55, 0.8)) + spread
		var house := MeshInstance3D.new()
		var hb := BoxMesh.new()
		hb.size = Vector3(3.5, 2.6, 3.0)
		house.mesh = hb
		house.position = hp + Vector3(0, 3.2, 0)
		var wall := StandardMaterial3D.new()
		wall.albedo_color = Color("e6d9b8").lerp(Color("d9c1a0"), rng.randf())
		house.material_override = wall
		root.add_child(house)
		var roof := MeshInstance3D.new()
		var rm := PrismMesh.new()
		rm.size = Vector3(3.9, 1.6, 3.4)
		roof.mesh = rm
		roof.position = hp + Vector3(0, 5.3, 0)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("9c5540")
		roof.material_override = rmat
		root.add_child(roof)

	# A watchtower for the big colonies.
	if tier >= 3:
		var tower := MeshInstance3D.new()
		var tm := CylinderMesh.new()
		tm.top_radius = 2.2
		tm.bottom_radius = 2.8
		tm.height = 10.0
		tower.mesh = tm
		tower.position = town_dir * (top_r * 0.35) + Vector3(0, 7.0, 0)
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color("9a938a")
		tower.material_override = stone
		root.add_child(tower)

	# Palms along the beach.
	for i in 5:
		var ang2 := rng.randf_range(0.0, TAU)
		var pp := Vector3(cos(ang2), 0, sin(ang2)) * top_r * rng.randf_range(0.82, 0.95)
		var trunk := MeshInstance3D.new()
		var tkm := CylinderMesh.new()
		tkm.top_radius = 0.3
		tkm.bottom_radius = 0.5
		tkm.height = 7.0
		trunk.mesh = tkm
		trunk.position = pp + Vector3(0, 5.0, 0)
		var bark := StandardMaterial3D.new()
		bark.albedo_color = Color("8a6a45")
		trunk.material_override = bark
		root.add_child(trunk)
		var crown := MeshInstance3D.new()
		var cm := SphereMesh.new()
		cm.radius = 2.6
		cm.height = 2.2
		crown.mesh = cm
		crown.position = pp + Vector3(0, 8.8, 0)
		var leaf := StandardMaterial3D.new()
		leaf.albedo_color = Color("3f6d2f")
		crown.material_override = leaf
		root.add_child(crown)

	# Nation flag on a pole above the town.
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.25
	pm.bottom_radius = 0.25
	pm.height = 16.0
	pole.mesh = pm
	pole.position = town_dir * (top_r * 0.6) + Vector3(0, 10.0, 0)
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(5.0, 3.0, 0.2)
	flag.mesh = fm
	flag.position = pole.position + Vector3(2.6, 6.0, 0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(World.NATIONS[isl["nation"]]["color"])
	flag.material_override = fmat
	root.add_child(flag)

	# Floating name, readable from any direction.
	var name_lbl := Label3D.new()
	name_lbl.text = isl["name"]
	name_lbl.font_size = 40
	name_lbl.outline_size = 10
	name_lbl.modulate = Color(1, 0.97, 0.88)
	name_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Constant on-screen size, always in front: readable across the map.
	name_lbl.fixed_size = true
	name_lbl.no_depth_test = true
	name_lbl.pixel_size = 0.0014
	name_lbl.position = Vector3(0, 34.0, 0)
	root.add_child(name_lbl)


func _build_player_ship() -> void:
	_ship_node = Node3D.new()
	_ship_node.set_script(ShipVisualScript)
	add_child(_ship_node)
	_ship_node.build(SHIP_LEN, Color(World.NATIONS[Game.state.character.nation]["color"]), false)
	_ship_node.set_sail_amount(maxf(Game.state.ship.sail_setting, 0.06))
	camera = Camera3D.new()
	camera.far = 4500.0
	add_child(camera)


func _place_player() -> void:
	var ctx: Dictionary = Game.open_sea_ctx
	Game.open_sea_ctx = {}
	if ctx.has("pos"):
		_ship_node.position = ctx["pos"]
		_heading = float(ctx["heading"])
	elif ctx.has("from_island"):
		var from: String = ctx["from_island"]
		_ship_node.position = OpenSea.departure_pos(from)
		_heading = OpenSea.departure_heading(from)
	elif Game.state.current_island != "":
		var isl: String = Game.state.current_island
		Game.state.depart()
		_ship_node.position = OpenSea.departure_pos(isl)
		_heading = OpenSea.departure_heading(isl)
	else:
		_ship_node.position = OpenSea.map_center()
	_ship_node.position.y = -0.5
	_ship_node.rotation.y = -deg_to_rad(_heading)
	camera.position = _ship_node.position + Vector3(0, 40, 80)


# --- HUD ---

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_color_override("font_color", Color("f3d98a"))
	_status.add_theme_font_size_override("font_size", 17)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.1, 0.14, 0.82)
	bg.content_margin_left = 12.0
	bg.content_margin_right = 12.0
	bg.content_margin_top = 6.0
	bg.content_margin_bottom = 6.0
	_status.add_theme_stylebox_override("normal", bg)
	hud.add_child(_status)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-260, -64)
	_hint.custom_minimum_size = Vector2(520, 0)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color("ffe9a8"))
	_hint.add_theme_font_size_override("font_size", 19)
	_hint.add_theme_stylebox_override("normal", bg)
	hud.add_child(_hint)

	_log_lbl = Label.new()
	_log_lbl.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_log_lbl.position = Vector2(-260, -110)
	_log_lbl.custom_minimum_size = Vector2(520, 0)
	_log_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_log_lbl.add_theme_color_override("font_color", Color("bfe0ff"))
	_log_lbl.add_theme_font_size_override("font_size", 16)
	hud.add_child(_log_lbl)

	_chart = SeaChart.new()
	_chart.set_anchors_preset(Control.PRESET_CENTER)
	_chart.custom_minimum_size = Vector2(640, 512)
	_chart.position = Vector2(-320, -256)
	_chart.visible = false
	hud.add_child(_chart)


func _flash(msg: String) -> void:
	_log_lbl.text = msg
	_log_until = _time + 4.0


# --- Simulation ---

func _physics_process(delta: float) -> void:
	if Game.state == null:
		return
	_time += delta
	_sail(delta)
	_update_npcs(delta)
	_update_camera(delta)
	_update_hud()


func _sail(delta: float) -> void:
	var ship = Game.state.ship
	var wind: Dictionary = Game.state.wind
	var nav: int = Game.state.character.skill("navigation")

	if Input.is_action_just_pressed("sails_up"):
		ship.sail_setting = clampf(ship.sail_setting + 0.5, 0.0, 1.0)
	if Input.is_action_just_pressed("sails_down"):
		ship.sail_setting = clampf(ship.sail_setting - 0.5, 0.0, 1.0)

	ship.heading = _heading
	var speed: float = Sailing.ship_speed(ship, wind["from"], wind["strength"], nav)
	var turn: float = Sailing.turn_speed(ship, speed, nav)
	if Input.is_action_pressed("turn_left"):
		_heading = wrapf(_heading - turn * delta, 0.0, 360.0)
	if Input.is_action_pressed("turn_right"):
		_heading = wrapf(_heading + turn * delta, 0.0, 360.0)

	var fwd := Vector3(sin(deg_to_rad(_heading)), 0, -cos(deg_to_rad(_heading)))
	var moved: Vector3 = fwd * speed * SPEED_SCALE * delta
	_ship_node.position = OpenSea.clamp_to_bounds(_ship_node.position + moved)
	_ship_node.rotation.y = -deg_to_rad(_heading)
	_ship_node.set_sail_amount(maxf(ship.sail_setting, 0.06))
	_ship_node.set_speed_visual(speed)
	_ship_node.bob(_time, 0.4)
	_ship_node.position.y = -0.5

	# Sailing eats calendar days: wages, provisions, wind drift.
	_distance_acc += moved.length()
	while _distance_acc >= OpenSea.DAY_DISTANCE:
		_distance_acc -= OpenSea.DAY_DISTANCE
		_on_day_passed()

	# Docking.
	var dock_id: String = OpenSea.dockable_island(_ship_node.position)
	if dock_id != "":
		var isl: Dictionary = World.island(dock_id)
		if Game.state.world.is_port_hostile(dock_id):
			_hint.text = "%s: the port is closed to you (reputation)" % isl["name"]
		else:
			_hint.text = "[E]  Drop anchor at %s" % isl["name"]
			if Input.is_action_just_pressed("interact"):
				_dock(dock_id)
	else:
		var near: String = OpenSea.nearest_island(_ship_node.position)
		_hint.text = "W/S — sails, A/D — rudder | %.1f kn | course for %s" % [speed, World.island(near)["name"]]


func _dock(island_id: String) -> void:
	# Quest rewards are paid inside arrive().
	Game.state.arrive(island_id)
	Game.save_game()
	Game.goto_port()


func _on_day_passed() -> void:
	var log: Dictionary = Game.state.sea_day()
	if int(log["starved"]) > 0:
		_flash("Provisions ran out — %d sailors starved!" % int(log["starved"]))
	var rng: RandomNumberGenerator = Game.state.rng
	if _npcs.size() < NPC_LIMIT and rng.randf() < OpenSea.ENCOUNTER_CHANCE_PER_DAY:
		_spawn_sail(rng.randf_range(260.0, 420.0))


## A new sail appears at `dist` units from the player, on a random bearing.
func _spawn_sail(dist: float) -> void:
	var rng: RandomNumberGenerator = Game.state.rng
	var enc: Dictionary = Game.state.roll_sea_encounter(OpenSea.nearest_island(_ship_node.position))
	var ang := rng.randf_range(0.0, TAU)
	var pos := OpenSea.clamp_to_bounds(_ship_node.position + Vector3(cos(ang), 0, sin(ang)) * dist)
	pos.y = -0.5
	var node := Node3D.new()
	node.set_script(ShipVisualScript)
	add_child(node)
	node.build(NPC_LEN, Color(World.NATIONS[enc["nation"]]["color"]), false)
	node.position = pos
	node.set_sail_amount(1.0)
	_npcs.append({
		"node": node,
		"heading": rng.randf_range(0.0, 360.0),
		"speed": rng.randf_range(7.0, 11.0),
		"enc": enc,
	})
	if enc["hostile"]:
		_flash("A hostile sail on the horizon — %s %s!" % [
			World.NATIONS[enc["nation"]]["name"], enc["ship_type"]])


func _update_npcs(delta: float) -> void:
	var survivors: Array = []
	for n in _npcs:
		var node: Node3D = n["node"]
		var hostile: bool = n["enc"]["hostile"]
		var to_player: Vector3 = _ship_node.position - node.position
		to_player.y = 0.0
		var d := to_player.length()

		if hostile and d < 300.0:
			# Pursuit: steer toward the player.
			var want := rad_to_deg(atan2(to_player.x, -to_player.z))
			var diff := wrapf(want - float(n["heading"]), -180.0, 180.0)
			n["heading"] = wrapf(float(n["heading"]) + clampf(diff, -40.0 * delta, 40.0 * delta), 0.0, 360.0)
		else:
			# Lazy cruising with a slow wander.
			n["heading"] = wrapf(float(n["heading"]) + sin(_time * 0.25 + node.position.x) * 6.0 * delta, 0.0, 360.0)

		var h := deg_to_rad(float(n["heading"]))
		var fwd := Vector3(sin(h), 0, -cos(h))
		node.position = OpenSea.clamp_to_bounds(node.position + fwd * float(n["speed"]) * delta)
		node.rotation.y = -h
		node.bob(_time, node.position.x * 0.1)
		node.position.y = -0.5
		node.set_speed_visual(float(n["speed"]) / SPEED_SCALE)

		if hostile and d < BATTLE_RANGE:
			_start_battle(n)
			return
		if not hostile and d < 14.0:
			node.position -= to_player.normalized() * (14.0 - d)

		if d > 900.0:
			node.queue_free()
		else:
			survivors.append(n)
	_npcs = survivors


func _start_battle(npc: Dictionary) -> void:
	Game.open_sea_ctx = {"pos": _ship_node.position, "heading": _heading}
	Game.goto_sea_battle(npc["enc"])


func _update_camera(delta: float) -> void:
	var yr := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * cam_dist
	camera.position = camera.position.lerp(_ship_node.position + Vector3(0, 4, 0) + off, 5.0 * delta)
	camera.look_at(_ship_node.position + Vector3(0, 3, 0))


func _update_hud() -> void:
	var s = Game.state
	_status.text = "Day %d  |  %d gold  |  Provisions %d  |  Crew %d  |  Wind %d°, %d kn  |  M — sea chart" % [
		s.day, s.character.gold, int(s.ship.cargo.get("provisions", 0)), s.ship.crew,
		int(s.wind["from"]), int(s.wind["strength"])]
	if _time > _log_until:
		_log_lbl.text = ""
	if _chart.visible:
		_chart.player_pos = Vector2(_ship_node.position.x, _ship_node.position.z) / OpenSea.SCALE
		_chart.player_heading = _heading
		_chart.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clampf(cam_dist - 6.0, 30.0, 220.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clampf(cam_dist + 6.0, 30.0, 220.0)
	elif event is InputEventMouseMotion and _orbiting:
		cam_yaw = wrapf(cam_yaw - event.relative.x * 0.35, 0.0, 360.0)
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.25, 8.0, 70.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_M:
			_chart.visible = not _chart.visible
		elif event.physical_keycode == KEY_ESCAPE and _chart.visible:
			_chart.visible = false


## Parchment overlay: the archipelago chart with the player's position.
class SeaChart:
	extends Control

	const World := preload("res://core/world.gd")

	var player_pos := Vector2.ZERO
	var player_heading := 0.0

	func _draw() -> void:
		var sz := get_size()
		draw_rect(Rect2(Vector2.ZERO, sz), Color(0.13, 0.11, 0.08, 0.9))
		draw_rect(Rect2(Vector2(6, 6), sz - Vector2(12, 12)), Color(0.85, 0.76, 0.56, 0.97))
		draw_rect(Rect2(Vector2(14, 14), sz - Vector2(28, 28)), Color(0.62, 0.72, 0.72, 0.55))
		var font := get_theme_default_font()
		draw_string(font, Vector2(24, 34), "Sea chart  (M to close)",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.25, 0.18, 0.08))
		for id in World.island_ids():
			var isl: Dictionary = World.island(id)
			var p := _to_chart(Vector2(isl["pos"][0], isl["pos"][1]), sz)
			draw_circle(p, 9.0, Color(0.55, 0.52, 0.36))
			draw_circle(p, 6.0, Color(World.NATIONS[isl["nation"]]["color"]))
			draw_string(font, p + Vector2(12, 5), isl["name"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.14, 0.06))
		# The player: a heading arrow.
		var pp := _to_chart(player_pos, sz)
		var h := deg_to_rad(player_heading)
		var dir := Vector2(sin(h), -cos(h))
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([
			pp + dir * 12.0, pp - dir * 6.0 + side * 6.0, pp - dir * 6.0 - side * 6.0,
		]), Color(0.75, 0.12, 0.1))

	func _to_chart(chart_pos: Vector2, sz: Vector2) -> Vector2:
		var inner := Rect2(Vector2(24, 44), sz - Vector2(48, 68))
		return inner.position + Vector2(
			chart_pos.x / 1000.0 * inner.size.x,
			chart_pos.y / 800.0 * inner.size.y)
