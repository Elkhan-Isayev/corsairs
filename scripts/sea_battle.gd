## 3D sea battle: the player against an encounter ship.
## WASD — sails/rudder, Q/E — broadsides, R — ammo type, B — board.
extends Node3D

const Sailing := preload("res://core/sailing.gd")
const Combat := preload("res://core/combat.gd")
const Boarding := preload("res://core/boarding.gd")
const Ammo := preload("res://core/ammo.gd")
const World := preload("res://core/world.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")

const SPEED_SCALE := 2.0      # knots -> m/s (sped up for pacing)
const ESCAPE_DISTANCE := 1600.0

var player_ship: RefCounted
var enemy_ship: RefCounted
var enemy_nation: String
var enemy_skills := {"accuracy": 3, "cannons": 3, "boarding": 3, "fencing": 3}
var enemy_heading := 0.0
var enemy_sail := 1.0
var enemy_current_ammo := "balls"

var player_node: Node3D
var enemy_node: Node3D
var camera: Camera3D
var battle_over := false
var _time := 0.0

# HUD
var hud: CanvasLayer
var lbl_player: Label
var lbl_enemy: Label
var lbl_wind: Label
var lbl_log: Label
var bar_reload: ProgressBar


func _ready() -> void:
	player_ship = Game.state.ship
	var enc: Dictionary = Game.pending_encounter
	enemy_ship = Game.state.spawn_encounter_ship(enc)
	enemy_nation = enc["nation"]
	_build_environment()
	_build_ships()
	_build_hud()
	_log("Enemy: %s \"%s\" (%s). Wind %d°." % [
		enemy_ship.spec()["name"], enemy_ship.custom_name,
		World.NATIONS[enemy_nation]["name"], int(Game.state.wind["from"])])


func _build_environment() -> void:
	# Late-afternoon sun: warm, low, with a visible disc in the sky.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 55, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.87, 0.68)
	add_child(sun)

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


func _flag_color(nation: String) -> Color:
	return Color(World.NATIONS[nation]["color"])


func _build_ships() -> void:
	player_node = Node3D.new()
	player_node.set_script(ShipVisualScript)
	add_child(player_node)
	player_node.build(_visual_length(player_ship), _flag_color(Game.state.character.nation))
	player_node.position = Vector3(0, 0, 0)
	player_ship.heading = 0.0
	player_ship.sail_setting = 0.5
	player_ship.reload_progress = 1.0

	enemy_node = Node3D.new()
	enemy_node.set_script(ShipVisualScript)
	add_child(enemy_node)
	enemy_node.build(_visual_length(enemy_ship), _flag_color(enemy_nation))
	enemy_node.position = Vector3(250, 0, -450)
	enemy_heading = 180.0
	enemy_ship.reload_progress = 1.0


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

	bar_reload = ProgressBar.new()
	bar_reload.position = Vector2(16, 660)
	bar_reload.size = Vector2(260, 16)
	bar_reload.max_value = 1.0
	bar_reload.show_percentage = false
	hud.add_child(bar_reload)

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

	# --- Player fire ---
	var dist: float = player_node.position.distance_to(enemy_node.position)
	if Input.is_action_just_pressed("fire_left"):
		_try_player_fire(dist, -1)
	if Input.is_action_just_pressed("fire_right"):
		_try_player_fire(dist, 1)
	if Input.is_action_just_pressed("board_enemy"):
		_try_boarding(dist)

	# --- Enemy ---
	_enemy_ai(delta, dist, wind)

	# --- Camera ---
	var back := Vector3(sin(deg_to_rad(player_ship.heading)), 0, -cos(deg_to_rad(player_ship.heading)))
	var target_pos: Vector3 = player_node.position - back * 62.0 + Vector3(0, 26, 0)
	camera.position = camera.position.lerp(target_pos, 2.5 * delta)
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


func _try_player_fire(dist: float, side: int) -> void:
	if player_ship.reload_progress < 1.0:
		return
	if not _in_arc(player_node, player_ship.heading, enemy_node, side):
		_log("Target is outside the %s arc!" % ("port" if side < 0 else "starboard"))
		return
	var skills := {"accuracy": Game.state.character.skill("accuracy"), "cannons": Game.state.character.skill("cannons")}
	var r: Dictionary = Combat.fire_broadside(player_ship, enemy_ship, dist, skills, Game.state.rng)
	_report_broadside(r, "Our broadside", enemy_node)


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


func _enemy_ai(delta: float, dist: float, wind: Dictionary) -> void:
	if enemy_ship.is_sunk():
		return
	var to_player := player_node.position - enemy_node.position
	var bearing := rad_to_deg(atan2(to_player.x, -to_player.z))
	var range_limit := Combat.max_range(enemy_ship.caliber, enemy_current_ammo)
	var desired: float
	if dist > range_limit * 0.75:
		desired = bearing            # chase
		enemy_sail = 1.0
	else:
		# Turn broadside-on: perpendicular to the bearing, whichever is closer.
		var opt_a := wrapf(bearing + 90.0, 0.0, 360.0)
		var opt_b := wrapf(bearing - 90.0, 0.0, 360.0)
		var da := absf(wrapf(opt_a - enemy_heading, -180.0, 180.0))
		var db := absf(wrapf(opt_b - enemy_heading, -180.0, 180.0))
		desired = opt_a if da < db else opt_b
		enemy_sail = 0.55

	enemy_ship.sail_setting = enemy_sail
	var e_speed: float = Sailing.ship_speed(enemy_ship, wind["from"], wind["strength"], 3)
	var e_turn: float = Sailing.turn_speed(enemy_ship, e_speed, 3)
	var diff := wrapf(desired - enemy_heading, -180.0, 180.0)
	enemy_heading = wrapf(enemy_heading + clampf(diff, -e_turn * delta, e_turn * delta), 0.0, 360.0)
	_move_ship(enemy_node, enemy_heading, e_speed, delta)
	enemy_node.set_sail_amount(enemy_ship.sail_setting)
	enemy_node.bob(_time, 2.1)
	enemy_node.set_speed_visual(e_speed)
	Combat.tick_reload(enemy_ship, delta, 3)

	# Ammo choice: far — cannonballs; close with a crew advantage — grapeshot.
	if dist < range_limit * 0.4 and enemy_ship.crew > player_ship.crew:
		enemy_current_ammo = "grapeshot"
	else:
		enemy_current_ammo = "balls"
	enemy_ship.current_ammo = enemy_current_ammo

	if enemy_ship.reload_progress >= 1.0:
		for side in [-1, 1]:
			if _in_arc(enemy_node, enemy_heading, player_node, side):
				var r: Dictionary = Combat.fire_broadside(enemy_ship, player_ship, dist, enemy_skills, Game.state.rng)
				if r["fired"] > 0:
					_report_broadside(r, "Enemy broadside", player_node)
				break


func _try_boarding(dist: float) -> void:
	if not Combat.can_board(dist / SPEED_SCALE, enemy_ship) and dist > 120.0:
		_log("Close alongside to board!")
		return
	var c = Game.state.character
	var att_skills := {"boarding": c.skill("boarding"), "fencing": c.skill("fencing")}
	var res: Dictionary = Boarding.resolve(player_ship, att_skills, enemy_ship, enemy_skills, Game.state.rng)
	if res["winner"] == "attacker":
		var lt: Dictionary = Boarding.loot(enemy_ship, Game.state.rng)
		c.earn(lt["gold"])
		for g in lt["cargo"]:
			player_ship.add_cargo(g, mini(int(lt["cargo"][g]), player_ship.cargo_free()))
		for a in lt["ammo"]:
			player_ship.ammo_stock[a] = int(player_ship.ammo_stock.get(a, 0)) + int(lt["ammo"][a])
		var outcome: Dictionary = Game.state.on_enemy_sunk(enemy_ship, enemy_nation)
		_finish_battle("Boarding successful! Seized %d gold and cargo. Losses: %d. XP +%d." % [
			lt["gold"], res["att_losses"], outcome["xp"]])
	else:
		_log("Boarding repelled! Lost %d men." % res["att_losses"])
		if player_ship.crew <= 0:
			_defeat("Your entire crew fell in the boarding action.")


func _update_hud(dist: float, p_speed: float) -> void:
	var wind: Dictionary = Game.state.wind
	lbl_player.text = "%s (%s)\nHull: %d%%  Sails: %d%%  Crew: %d\nAmmo: %s (%d)  Sails: %s  Speed: %.1f kn" % [
		player_ship.custom_name, player_ship.spec()["name"],
		int(player_ship.hull_frac() * 100), int(player_ship.sails_frac() * 100), player_ship.crew,
		Ammo.get_type(player_ship.current_ammo)["name"], player_ship.ammo_stock.get(player_ship.current_ammo, 0),
		["furled", "half", "full"][int(player_ship.sail_setting * 2.0)], p_speed]
	lbl_enemy.text = "%s (%s)\nHull: %d%%  Sails: %d%%\nCrew: %d  Distance: %d m" % [
		enemy_ship.custom_name, World.NATIONS[enemy_nation]["name"],
		int(enemy_ship.hull_frac() * 100), int(enemy_ship.sails_frac() * 100),
		enemy_ship.crew, int(dist)]
	lbl_wind.text = "Wind: %d° / %.0f kn" % [int(wind["from"]), wind["strength"]]
	bar_reload.value = player_ship.reload_progress
	if dist < 120.0 and not enemy_ship.is_sunk():
		lbl_wind.text += "   [B — BOARD!]"


func _check_battle_end(dist: float) -> void:
	if enemy_ship.is_sunk():
		var outcome: Dictionary = Game.state.on_enemy_sunk(enemy_ship, enemy_nation)
		var msg := "The enemy is going down! XP +%d." % outcome["xp"]
		if outcome["level_up"]:
			msg += " Level up!"
		for q in outcome["completed_quests"]:
			msg += " Quest completed: %s." % q["title"]
		_sink_visual(enemy_node)
		_finish_battle(msg)
	elif player_ship.is_sunk():
		_defeat("Your ship has been sunk...")
	elif player_ship.is_crew_critical():
		_defeat("Not enough crew left to handle the ship.")
	elif dist > ESCAPE_DISTANCE:
		_finish_battle("You broke away from the enemy.")


func _sink_visual(node: Node3D) -> void:
	var tw := create_tween()
	tw.tween_property(node, "position:y", -25.0, 4.0)
	tw.parallel().tween_property(node, "rotation:z", 0.6, 4.0)


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
