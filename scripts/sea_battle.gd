## 3D sea battle: the player against an encounter ship.
## WASD — sails/rudder, Q/E — broadsides, R — ammo type, B — board.
## With no pending encounter this is free sailing: just you and the sea
## (Enter/Esc returns to the world map).
extends Node3D

const Sailing := preload("res://core/sailing.gd")
const Combat := preload("res://core/combat.gd")
const Boarding := preload("res://core/boarding.gd")
const Ammo := preload("res://core/ammo.gd")
const World := preload("res://core/world.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")
const DayCycle := preload("res://scripts/day_cycle.gd")

## Weather baseline for the battle sea (day/night modulates it).
const SEA_LOOK := {"sky_top": "27548c", "horizon": "e8cfa8", "fog": 0.0005,
	"fog_color": "d9c6a4", "sun_energy": 1.5, "sun_color": "ffe6b8"}

var _sun: DirectionalLight3D
var _env_res: Environment

const SPEED_SCALE := 2.6      # knots -> m/s (sped up for arcade pacing)
const ESCAPE_DISTANCE := 1600.0

var player_ship: RefCounted
## The enemy squadron (1..4 sail): {ship, node, len, heading, sail, ammo, sunk_handled}
var enemies: Array = []
## Nearest afloat enemy — kept in sync every frame for HUD/targeting.
var enemy_ship: RefCounted
var enemy_node: Node3D
var enemy_nation: String
var enemy_skills := {"accuracy": 3, "cannons": 3, "boarding": 3, "fencing": 3}

## True when there is no enemy — sailing the deck-scale sea for its own sake.
var free_sail := false
## Peaceful sails cruising alongside in free-sail mode (visual only):
## {node, heading, speed}. They neither fire nor get fired at.
var company: Array = []

var player_node: Node3D
var player_len := 25.0
var camera: Camera3D
var battle_over := false
var _time := 0.0

# Orbit camera (RMB drag to rotate, wheel to zoom).
var cam_yaw := 0.0
var cam_pitch := 18.0
var cam_dist := 70.0
var _orbiting := false

# HUD
var hud: CanvasLayer
var lbl_player: Label
var lbl_enemy: Label
var lbl_wind: Label
var lbl_log: Label
var bar_reload: ProgressBar
var bar_reload_r: ProgressBar


func _ready() -> void:
	player_ship = Game.state.ship
	var enc: Dictionary = Game.pending_encounter
	free_sail = enc.is_empty()
	if free_sail:
		Music.play_shanty()
	else:
		Music.play_battle()
		enemy_nation = enc["nation"]
		var count: int = clampi(int(enc.get("count", 1)), 1, 4)
		for i in count:
			var ship = Game.state.spawn_encounter_ship(enc)
			enemies.append({"ship": ship, "node": null, "len": 25.0,
				"heading": 180.0, "sail": 1.0, "ammo": "balls", "sunk_handled": false})
		enemy_ship = enemies[0]["ship"]
	_build_environment()
	_build_ships()
	_build_hud()
	_start_ocean_ambience()
	if free_sail:
		_log("Open waters. Wind %d°.  [Enter] — back to the world map." % int(Game.state.wind["from"]))
		if company.size() == 1:
			var comp: Dictionary = Game.free_sail_company
			_log("A %s %s cruises nearby." % [
				World.NATIONS[comp["nation"]]["name"], comp["ship_type"]])
		elif company.size() > 1:
			_log("A %s squadron passes by — %d sail." % [
				World.NATIONS[Game.free_sail_company["nation"]]["name"], company.size()])
	elif enemies.size() > 1:
		_log("Enemy squadron: %d sail of %s (%s). Wind %d°." % [
			enemies.size(), enemy_ship.spec()["name"],
			World.NATIONS[enemy_nation]["name"], int(Game.state.wind["from"])])
	else:
		_log("Enemy: %s \"%s\" (%s). Wind %d°." % [
			enemy_ship.spec()["name"], enemy_ship.custom_name,
			World.NATIONS[enemy_nation]["name"], int(Game.state.wind["from"])])


func _build_environment() -> void:
	# The sun follows the global day/night clock.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 400.0
	add_child(_sun)
	var sun := _sun

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-60, -120, 0)
	fill.light_energy = 0.25
	fill.light_color = Color(0.65, 0.75, 0.95)
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("27548c")
	sky_mat.sky_horizon_color = Color("e8cfa8")
	sky_mat.sky_curve = 0.12
	sky_mat.ground_bottom_color = Color("0a2438")
	sky_mat.ground_horizon_color = Color("d8c4a0")
	sky_mat.sun_angle_max = 30.0
	sky_mat.sun_curve = 0.08
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.08
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.04
	e.fog_enabled = true
	e.fog_light_color = Color("d9c6a4")
	e.fog_density = 0.0005
	e.fog_sky_affect = 0.2
	env.environment = e
	add_child(env)
	_env_res = e
	DayCycle.apply(_sun, _env_res, Game.time_of_day, SEA_LOOK)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4000, 4000)
	plane.subdivide_width = 160
	plane.subdivide_depth = 160
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/water.gdshader")
	# Seamless procedural noise drives both the chop and the ripple normals.
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

	camera = Camera3D.new()
	camera.far = 6000.0
	camera.fov = 60.0
	add_child(camera)


func _start_ocean_ambience() -> void:
	var waves := AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/music/waves.wav")
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / 2
	waves.stream = stream
	waves.volume_db = -10.0
	add_child(waves)
	waves.play()


## RMB drag orbits the camera, the wheel zooms.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clampf(cam_dist * 0.9, 30.0, 260.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clampf(cam_dist * 1.1, 30.0, 260.0)
	elif event is InputEventMouseMotion and _orbiting:
		cam_yaw = wrapf(cam_yaw - event.relative.x * 0.35, 0.0, 360.0)
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.25, 4.0, 70.0)
	elif event is InputEventKey and event.pressed and not event.echo and free_sail:
		# Only open waters can be left at will; battles must be finished.
		# open_sea_ctx still holds the map position we came from.
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			Game.goto_map()


func _flag_color(nation: String) -> Color:
	return Color(World.NATIONS[nation]["color"])


func _build_ships() -> void:
	player_node = Node3D.new()
	player_node.set_script(ShipVisualScript)
	add_child(player_node)
	player_len = _visual_length(player_ship)
	player_node.build(player_len, _flag_color(Game.state.character.nation), true, player_ship.type_id)
	player_node.position = Vector3(0, 0, 0)
	player_ship.heading = 0.0
	player_ship.sail_setting = 0.5
	player_ship.reload_left = 1.0
	player_ship.reload_right = 1.0
	if free_sail:
		_build_company()
		return

	# The squadron deploys in a loose line of battle.
	for i in enemies.size():
		var e: Dictionary = enemies[i]
		var node := Node3D.new()
		node.set_script(ShipVisualScript)
		add_child(node)
		var elen: float = _visual_length(e["ship"])
		node.build(elen, _flag_color(enemy_nation), true, e["ship"].type_id)
		node.position = Vector3(250 + i * 120 - (enemies.size() - 1) * 60, 0, -450 - (i % 2) * 90)
		e["node"] = node
		e["len"] = elen
		e["ship"].reload_left = 1.0
		e["ship"].reload_right = 1.0
	enemy_node = enemies[0]["node"]


## Peaceful company met on the world map: 1..4 sail abeam, just cruising.
func _build_company() -> void:
	var comp: Dictionary = Game.free_sail_company
	if comp.is_empty():
		return
	var count: int = clampi(int(comp.get("count", 1)), 1, 4)
	var rng: RandomNumberGenerator = Game.state.rng
	for i in count:
		var ship = Game.state.spawn_encounter_ship(comp)
		var node := Node3D.new()
		node.set_script(ShipVisualScript)
		add_child(node)
		node.build(_visual_length(ship), _flag_color(comp["nation"]), true, ship.type_id)
		# A loose column off the starboard beam, on our own course.
		node.position = Vector3(170 + (i % 2) * 90, 0, -160 - i * 150)
		node.set_sail_amount(1.0)
		company.append({"node": node,
			"heading": rng.randf_range(-8.0, 8.0), "speed": rng.randf_range(4.5, 7.5)})


func _visual_length(ship: RefCounted) -> float:
	return 18.0 + (8 - int(ship.spec()["rank"])) * 5.0


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	lbl_player = Label.new()
	lbl_player.position = Vector2(16, 12)
	lbl_player.add_theme_color_override("font_color", Color("e8f2fa"))
	lbl_player.add_theme_font_size_override("font_size", 15)
	hud.add_child(lbl_player)

	lbl_enemy = Label.new()
	lbl_enemy.position = Vector2(940, 12)
	lbl_enemy.add_theme_color_override("font_color", Color("f5c6c6"))
	lbl_enemy.add_theme_font_size_override("font_size", 15)
	hud.add_child(lbl_enemy)

	lbl_wind = Label.new()
	lbl_wind.position = Vector2(560, 12)
	lbl_wind.add_theme_color_override("font_color", Color("e8c872"))
	hud.add_child(lbl_wind)

	# One reload bar per battery: port on the left, starboard on the right.
	bar_reload = ProgressBar.new()
	bar_reload.position = Vector2(16, 660)
	bar_reload.size = Vector2(126, 16)
	bar_reload.max_value = 1.0
	bar_reload.show_percentage = false
	hud.add_child(bar_reload)
	bar_reload_r = ProgressBar.new()
	bar_reload_r.position = Vector2(150, 660)
	bar_reload_r.size = Vector2(126, 16)
	bar_reload_r.max_value = 1.0
	bar_reload_r.show_percentage = false
	hud.add_child(bar_reload_r)
	var lbl_bars := Label.new()
	lbl_bars.position = Vector2(16, 678)
	lbl_bars.text = "Q — port battery          E — starboard"
	lbl_bars.add_theme_font_size_override("font_size", 12)
	lbl_bars.add_theme_color_override("font_color", Color("9fb4c8"))
	hud.add_child(lbl_bars)

	lbl_log = Label.new()
	lbl_log.position = Vector2(16, 596)
	lbl_log.add_theme_color_override("font_color", Color("cfe3f5"))
	hud.add_child(lbl_log)


var _log_lines: Array = []
func _log(msg: String) -> void:
	_log_lines.append(msg)
	if _log_lines.size() > 3:
		_log_lines.pop_front()
	if lbl_log != null:
		lbl_log.text = "\n".join(_log_lines)


func _physics_process(delta: float) -> void:
	if battle_over:
		return
	_time += delta
	DayCycle.apply(_sun, _env_res, Game.time_of_day, SEA_LOOK)
	var wind: Dictionary = Game.state.wind
	var nav: int = Game.state.character.skill("navigation")
	var cann: int = Game.state.character.skill("cannons")

	# --- Player ---
	if Input.is_action_just_pressed("sails_up"):
		player_ship.sail_setting = clampf(player_ship.sail_setting + 0.5, 0.0, 1.0)
	if Input.is_action_just_pressed("sails_down"):
		player_ship.sail_setting = clampf(player_ship.sail_setting - 0.5, 0.0, 1.0)
	if Input.is_action_just_pressed("next_ammo"):
		player_ship.current_ammo = Ammo.next_type(player_ship.current_ammo)
		_log("Loading: %s" % Ammo.get_type(player_ship.current_ammo)["name"])

	var p_speed: float = Sailing.ship_speed(player_ship, wind["from"], wind["strength"], nav)
	var turn: float = Sailing.turn_speed(player_ship, p_speed, nav)
	if Input.is_action_pressed("turn_left"):
		player_ship.heading = wrapf(player_ship.heading - turn * delta, 0.0, 360.0)
	if Input.is_action_pressed("turn_right"):
		player_ship.heading = wrapf(player_ship.heading + turn * delta, 0.0, 360.0)
	_move_ship(player_node, player_ship.heading, p_speed, delta)
	player_node.set_sail_amount(player_ship.sail_setting)
	player_node.bob(_time, 0.0)
	player_node.set_speed_visual(p_speed)
	Combat.tick_reload(player_ship, delta, cann)

	# --- Peaceful company on open waters: they just sail on. ---
	for c: Dictionary in company:
		c["heading"] = wrapf(float(c["heading"])
			+ sin(_time * 0.18 + float(c["node"].position.x) * 0.01) * 2.0 * delta, 0.0, 360.0)
		_move_ship(c["node"], float(c["heading"]), float(c["speed"]), delta)
		c["node"].bob(_time, float(c["node"].position.x) * 0.1)
		c["node"].set_speed_visual(float(c["speed"]))

	# --- Player fire / enemy squadron (skipped on open waters) ---
	var dist: float = INF
	if not free_sail:
		_refresh_nearest_enemy()
		dist = _nearest_dist()
		if Input.is_action_just_pressed("fire_left"):
			_try_player_fire(-1)
		if Input.is_action_just_pressed("fire_right"):
			_try_player_fire(1)
		if Input.is_action_just_pressed("board_enemy"):
			_try_boarding(dist)

		for e: Dictionary in enemies:
			if not e["ship"].is_sunk():
				_enemy_ai_one(e, delta, wind)
		_separate_hulls()
		dist = _nearest_dist()

	# --- Camera: free orbit around the player's ship ---
	var yr := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * cam_dist
	var target_pos: Vector3 = player_node.position + off
	camera.position = camera.position.lerp(target_pos, 8.0 * delta)
	camera.look_at(player_node.position + Vector3(0, 8, 0))

	_update_hud(dist, p_speed)
	_check_battle_end(dist)


func _move_ship(node: Node3D, heading: float, speed: float, delta: float) -> void:
	var fwd := Vector3(sin(deg_to_rad(heading)), 0, -cos(deg_to_rad(heading)))
	node.position += fwd * speed * SPEED_SCALE * delta
	node.rotation.y = -deg_to_rad(heading)


## side: -1 port, 1 starboard.
func _in_arc(from_node: Node3D, heading: float, to_node: Node3D, side: int) -> bool:
	var to_target := (to_node.position - from_node.position).normalized()
	var fwd := Vector3(sin(deg_to_rad(heading)), 0, -cos(deg_to_rad(heading)))
	var right := Vector3(fwd.z, 0, -fwd.x) * -1.0  # starboard side
	return to_target.dot(right * side) > 0.35


## Nearest afloat enemy and helpers over the squadron.

func _refresh_nearest_enemy() -> void:
	var best_d := INF
	for e: Dictionary in enemies:
		if e["ship"].is_sunk():
			continue
		var d: float = player_node.position.distance_to(e["node"].position)
		if d < best_d:
			best_d = d
			enemy_ship = e["ship"]
			enemy_node = e["node"]


func _nearest_dist() -> float:
	var best := INF
	for e: Dictionary in enemies:
		if not e["ship"].is_sunk():
			best = minf(best, player_node.position.distance_to(e["node"].position))
	return best


func _alive_count() -> int:
	var n := 0
	for e: Dictionary in enemies:
		if not e["ship"].is_sunk():
			n += 1
	return n


## Hulls never overlap: player vs every enemy, and enemies among themselves.
func _separate_hulls() -> void:
	for e: Dictionary in enemies:
		if e["ship"].is_sunk():
			continue
		var min_d: float = (player_len + float(e["len"])) * 0.45
		var node: Node3D = e["node"]
		var between: Vector3 = player_node.position - node.position
		between.y = 0.0
		if between.length() < min_d:
			var n := between.normalized() if between.length() > 0.01 else Vector3(1, 0, 0)
			var push := (min_d - between.length()) * 0.5
			player_node.position += n * push
			node.position -= n * push
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a: Dictionary = enemies[i]
			var b: Dictionary = enemies[j]
			if a["ship"].is_sunk() or b["ship"].is_sunk():
				continue
			var min_d2: float = (float(a["len"]) + float(b["len"])) * 0.45
			var betw: Vector3 = a["node"].position - b["node"].position
			betw.y = 0.0
			if betw.length() < min_d2:
				var n2 := betw.normalized() if betw.length() > 0.01 else Vector3(1, 0, 0)
				var push2 := (min_d2 - betw.length()) * 0.5
				a["node"].position += n2 * push2
				b["node"].position -= n2 * push2


func _try_player_fire(side: int) -> void:
	if Combat.reload_progress(player_ship, side) < 1.0:
		_log("The %s battery is still reloading!" % ("port" if side < 0 else "starboard"))
		return
	# Aim at the nearest afloat enemy inside this side's arc.
	var target: Dictionary = {}
	var best_d := INF
	for e: Dictionary in enemies:
		if e["ship"].is_sunk():
			continue
		var d: float = player_node.position.distance_to(e["node"].position)
		if d < best_d and _in_arc(player_node, player_ship.heading, e["node"], side):
			best_d = d
			target = e
	if target.is_empty():
		_log("No target in the %s arc!" % ("port" if side < 0 else "starboard"))
		return
	var skills := {"accuracy": Game.state.character.skill("accuracy"), "cannons": Game.state.character.skill("cannons")}
	var r: Dictionary = Combat.fire_broadside(player_ship, target["ship"], best_d, skills, Game.state.rng, side)
	if int(r["fired"]) > 0:
		player_node.fire_broadside_fx(side)
	_report_broadside(r, "Our broadside", target["node"])


func _report_broadside(r: Dictionary, who: String, target_node: Node3D) -> void:
	if r["no_ammo"]:
		_log("%s: out of shot!" % who)
	elif r["out_of_range"]:
		_log("%s: out of range." % who)
	elif r["fired"] > 0:
		_log("%s: %d guns, %d hits." % [who, r["fired"], r["hits"]])
		_spawn_shot_visuals(target_node, int(r["hits"]))


func _spawn_shot_visuals(target: Node3D, hits: int) -> void:
	for i in mini(hits, 8):
		var puff := MeshInstance3D.new()
		var m := SphereMesh.new()
		m.radius = 1.5
		m.height = 3.0
		puff.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.6, 0.2, 0.9)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1)
		puff.material_override = mat
		add_child(puff)
		puff.position = target.position + Vector3(randf_range(-8, 8), randf_range(2, 10), randf_range(-8, 8))
		var tw := create_tween()
		tw.tween_property(puff, "scale", Vector3(3, 3, 3), 0.5)
		tw.parallel().tween_property(puff, "transparency", 1.0, 0.5)
		tw.tween_callback(puff.queue_free)


func _enemy_ai_one(e: Dictionary, delta: float, wind: Dictionary) -> void:
	var ship = e["ship"]
	var node: Node3D = e["node"]
	var heading: float = e["heading"]
	var to_player: Vector3 = player_node.position - node.position
	var dist := to_player.length()
	var bearing := rad_to_deg(atan2(to_player.x, -to_player.z))
	var range_limit := Combat.max_range(ship.caliber, String(e["ammo"]))
	var desired: float
	if dist > range_limit * 0.75:
		desired = bearing            # chase
		e["sail"] = 1.0
	else:
		# Turn broadside-on: perpendicular to the bearing, whichever is closer.
		var opt_a := wrapf(bearing + 90.0, 0.0, 360.0)
		var opt_b := wrapf(bearing - 90.0, 0.0, 360.0)
		var da := absf(wrapf(opt_a - heading, -180.0, 180.0))
		var db := absf(wrapf(opt_b - heading, -180.0, 180.0))
		desired = opt_a if da < db else opt_b
		e["sail"] = 0.55

	ship.sail_setting = e["sail"]
	var e_speed: float = Sailing.ship_speed(ship, wind["from"], wind["strength"], 3)
	var e_turn: float = Sailing.turn_speed(ship, e_speed, 3)
	var diff := wrapf(desired - heading, -180.0, 180.0)
	heading = wrapf(heading + clampf(diff, -e_turn * delta, e_turn * delta), 0.0, 360.0)
	e["heading"] = heading
	_move_ship(node, heading, e_speed, delta)
	node.set_sail_amount(ship.sail_setting)
	node.bob(_time, 2.1 + node.position.x * 0.01)
	node.set_speed_visual(e_speed)
	Combat.tick_reload(ship, delta, 3)

	# Ammo choice: far — cannonballs; close with a crew advantage — grapeshot.
	if dist < range_limit * 0.4 and ship.crew > player_ship.crew:
		e["ammo"] = "grapeshot"
	else:
		e["ammo"] = "balls"
	ship.current_ammo = e["ammo"]

	for side: int in [-1, 1]:
		if Combat.reload_progress(ship, side) >= 1.0 \
				and _in_arc(node, heading, player_node, side):
			var r: Dictionary = Combat.fire_broadside(ship, player_ship, dist, enemy_skills, Game.state.rng, side)
			if r["fired"] > 0:
				node.fire_broadside_fx(side)
				_report_broadside(r, "Enemy broadside", player_node)
			break


## Boarding hands the encounter over to the on-deck melee scene.
func _try_boarding(dist: float) -> void:
	if not Combat.can_board(dist / SPEED_SCALE, enemy_ship) and dist > 120.0:
		_log("Close alongside to board!")
		return
	Game.save_game()
	Game.start_boarding(enemy_ship, enemy_nation)


func _update_hud(dist: float, p_speed: float) -> void:
	var wind: Dictionary = Game.state.wind
	lbl_player.text = "%s (%s)\nHull: %d%%  Sails: %d%%  Crew: %d\nAmmo: %s (%d)  Sails: %s  Speed: %.1f kn" % [
		player_ship.custom_name, player_ship.spec()["name"],
		int(player_ship.hull_frac() * 100), int(player_ship.sails_frac() * 100), player_ship.crew,
		Ammo.get_type(player_ship.current_ammo)["name"], player_ship.ammo_stock.get(player_ship.current_ammo, 0),
		["furled", "half", "full"][int(player_ship.sail_setting * 2.0)], p_speed]
	lbl_wind.text = "Wind: %d° / %.0f kn" % [int(wind["from"]), wind["strength"]]
	bar_reload.value = player_ship.reload_left
	bar_reload_r.value = player_ship.reload_right
	if free_sail:
		lbl_enemy.text = ""
		lbl_wind.text += "   [Enter — world map]"
		return
	var afloat := _alive_count()
	var squadron := "" if enemies.size() == 1 else "Squadron: %d/%d afloat\n" % [afloat, enemies.size()]
	lbl_enemy.text = "%s%s (%s)\nHull: %d%%  Sails: %d%%\nCrew: %d  Distance: %d m" % [
		squadron, enemy_ship.custom_name, World.NATIONS[enemy_nation]["name"],
		int(enemy_ship.hull_frac() * 100), int(enemy_ship.sails_frac() * 100),
		enemy_ship.crew, int(dist)]
	if dist < 120.0 and afloat > 0:
		lbl_wind.text += "   [B — BOARD!]"


func _check_battle_end(dist: float) -> void:
	if free_sail:
		return
	# Credit every ship the moment it goes down.
	for e: Dictionary in enemies:
		if e["ship"].is_sunk() and not bool(e["sunk_handled"]):
			e["sunk_handled"] = true
			var outcome: Dictionary = Game.state.on_enemy_sunk(e["ship"], enemy_nation)
			var msg := "%s is going down! XP +%d." % [e["ship"].spec()["name"], outcome["xp"]]
			if outcome["level_up"]:
				msg += " Level up!"
			for q in outcome["completed_quests"]:
				msg += " Quest completed: %s." % q["title"]
			_sink_visual(e["node"])
			_log(msg)
	if player_ship.is_sunk():
		_defeat("Your ship has been sunk...")
	elif player_ship.is_crew_critical():
		_defeat("Not enough crew left to handle the ship.")
	elif _alive_count() == 0:
		_victory_to_open_waters()
	elif dist > ESCAPE_DISTANCE:
		_finish_battle("You broke away from the enemy.")


func _sink_visual(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "position:y", -25.0, 4.0)
	tw.parallel().tween_property(node, "rotation:z", 0.6, 4.0)


## Victory: the sea is yours — sail on in open waters, no forced exit.
func _victory_to_open_waters() -> void:
	free_sail = true
	Music.play_shanty()
	Game.save_game()
	_log("The sea is clear. Sail on — or press Enter for the world map.")


## Breaking away still returns to the world map (you fled the fight).
func _finish_battle(msg: String) -> void:
	battle_over = true
	_log(msg)
	Game.save_game()
	var dlg := AcceptDialog.new()
	dlg.title = "Battle over"
	dlg.dialog_text = msg
	dlg.confirmed.connect(func(): Game.goto_map())
	dlg.canceled.connect(func(): Game.goto_map())
	hud.add_child(dlg)
	dlg.popup_centered()


func _defeat(msg: String) -> void:
	battle_over = true
	var dlg := AcceptDialog.new()
	dlg.title = "Defeat"
	dlg.dialog_text = msg + "\nGame over. Load a save or start anew."
	dlg.confirmed.connect(func(): Game.goto_menu())
	dlg.canceled.connect(func(): Game.goto_menu())
	hud.add_child(dlg)
	dlg.popup_centered()
