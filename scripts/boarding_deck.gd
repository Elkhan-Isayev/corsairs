## Third-person boarding fight on the enemy deck, like the original game:
## your captain fights with a cutlass while both crews clash around him.
## WASD — move, Space/LMB — strike, RMB — camera. Winning takes the prize.
extends Node3D

const World := preload("res://core/world.gd")
const Boarding := preload("res://core/boarding.gd")
const Person := preload("res://scripts/person.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")

const MOVE_SPEED := 6.5
const ATTACK_RANGE := 2.1
const ATTACK_CD := 0.6

var player_ship: RefCounted
var enemy_ship: RefCounted
var enemy_nation: String

var enemy_deck: Node3D
var deck_len: float
var deck_halfw: float

# The captain.
var player: Dictionary   # Person.build dict
var player_hp: float
var player_cd := 0.0

# Crew fighters: {p: person dict, side: "ally"/"enemy", hp, cd, phase, repr}
var _fighters: Array = []
var _ally_reserve := 0
var _enemy_reserve := 0

var camera: Camera3D
var cam_yaw := 160.0
var cam_pitch := 30.0
var cam_dist := 13.0
var _orbiting := false
var _over := false
var _time := 0.0

var hud: CanvasLayer
var _lbl_ours: Label
var _lbl_theirs: Label
var _hp_bar: ProgressBar
var _hint: Label


func _ready() -> void:
	Music.play_battle()
	player_ship = Game.state.ship
	enemy_ship = Game.boarding_ctx["enemy"]
	enemy_nation = Game.boarding_ctx["nation"]
	_build_environment()
	_build_ships()
	_build_combatants()
	_build_hud()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 50, 0)
	sun.light_energy = 1.5
	sun.light_color = Color(1.0, 0.88, 0.7)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("27548c")
	sky_mat.sky_horizon_color = Color("e8cfa8")
	sky_mat.ground_bottom_color = Color("0a2438")
	sky_mat.ground_horizon_color = Color("d8c4a0")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.45
	env.environment = e
	add_child(env)

	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1500, 1500)
	plane.subdivide_width = 80
	plane.subdivide_depth = 80
	water.mesh = plane
	water.position.y = -0.8
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

	camera = Camera3D.new()
	camera.far = 4000.0
	camera.fov = 62.0
	add_child(camera)


func _vis_len(ship: RefCounted) -> float:
	return 18.0 + (8 - int(ship.spec()["rank"])) * 5.0


func _build_ships() -> void:
	deck_len = _vis_len(enemy_ship)
	enemy_deck = Node3D.new()
	enemy_deck.set_script(ShipVisualScript)
	add_child(enemy_deck)
	enemy_deck.build(deck_len, Color(World.NATIONS[enemy_nation]["color"]), false, enemy_ship.type_id)
	enemy_deck.set_sail_amount(0.06)
	deck_halfw = enemy_deck._beam * 0.5 * 0.92

	# Your ship grappled alongside.
	var own_len := _vis_len(player_ship)
	var own := Node3D.new()
	own.set_script(ShipVisualScript)
	add_child(own)
	own.build(own_len, Color(World.NATIONS[Game.state.character.nation]["color"]), false, player_ship.type_id)
	own.set_sail_amount(0.06)
	own.position = Vector3(-(deck_len + own_len) * 0.16, 0, deck_len * 0.05)

	# Grappling ropes between the hulls.
	for i in 3:
		var z := -deck_len * 0.2 + i * deck_len * 0.2
		var rope := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.04
		cm.height = (deck_len + own_len) * 0.18
		rope.mesh = cm
		rope.position = Vector3(-(deck_len + own_len) * 0.08, _deck_y_at(0.5) + 0.8, z)
		rope.rotation_degrees = Vector3(0, 0, 80)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color("2a2015")
		rope.material_override = rmat
		add_child(rope)


## Deck height under a local z position on the enemy ship.
func _deck_y_at(t: float) -> float:
	return enemy_deck._deck_y(clampf(t, 0.0, 1.0))


func _deck_y_at_z(z: float) -> float:
	return _deck_y_at((z + deck_len / 2.0) / deck_len)


func _build_combatants() -> void:
	var c = Game.state.character
	player = Person.build(Color("2c3a5c"), Color("d9a97a"), false, 1, true)
	var proot: Node3D = player["root"]
	add_child(proot)
	proot.position = Vector3(-deck_halfw * 0.5, 0, deck_len * 0.18)
	proot.position.y = _deck_y_at_z(proot.position.z)
	player_hp = c.max_hp

	# Visible fighters represent chunks of both crews; 30% stay as reserve.
	var n_allies := clampi(int(player_ship.crew / 8.0), 2, 8)
	var n_enemies := clampi(int(enemy_ship.crew / 8.0), 3, 9)
	var ally_field := int(player_ship.crew * 0.7)
	var enemy_field := int(enemy_ship.crew * 0.7)
	_ally_reserve = player_ship.crew - ally_field
	_enemy_reserve = enemy_ship.crew - enemy_field

	for i in n_allies:
		_spawn_fighter("ally", Vector3(-deck_halfw * 0.7 + randf() * deck_halfw * 0.5,
			0, deck_len * 0.05 + randf() * deck_len * 0.18),
			maxi(int(ally_field / float(n_allies)), 1))
	for i in n_enemies:
		_spawn_fighter("enemy", Vector3(-deck_halfw * 0.6 + randf() * deck_halfw * 1.4,
			0, -deck_len * 0.28 + randf() * deck_len * 0.25),
			maxi(int(enemy_field / float(n_enemies)), 1))


func _spawn_fighter(side: String, pos: Vector3, repr: int) -> void:
	var cloth := Color("6b7d4a") if side == "ally" else Color("8d3a2e")
	var p := Person.build(cloth, Color("d9a97a").lerp(Color("8d6a4a"), randf() * 0.6),
		false, 3 if side == "enemy" else 0, true)
	var root: Node3D = p["root"]
	add_child(root)
	pos.y = _deck_y_at_z(pos.z)
	root.position = pos
	_fighters.append({
		"p": p, "side": side, "hp": 34.0, "cd": randf() * 0.8,
		"phase": randf() * TAU, "repr": repr,
	})


func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)

	var title := Label.new()
	title.text = "BOARDING — %s (%s)" % [enemy_ship.custom_name, World.NATIONS[enemy_nation]["name"]]
	title.position = Vector2(420, 12)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("e8c872"))
	hud.add_child(title)

	_lbl_ours = Label.new()
	_lbl_ours.position = Vector2(16, 12)
	_lbl_ours.add_theme_color_override("font_color", Color("81c784"))
	_lbl_ours.add_theme_font_size_override("font_size", 17)
	hud.add_child(_lbl_ours)

	_lbl_theirs = Label.new()
	_lbl_theirs.position = Vector2(1080, 12)
	_lbl_theirs.add_theme_color_override("font_color", Color("e57373"))
	_lbl_theirs.add_theme_font_size_override("font_size", 17)
	hud.add_child(_lbl_theirs)

	_hp_bar = ProgressBar.new()
	_hp_bar.position = Vector2(16, 660)
	_hp_bar.size = Vector2(240, 18)
	_hp_bar.max_value = Game.state.character.max_hp
	_hp_bar.show_percentage = false
	hud.add_child(_hp_bar)
	var hp_lbl := Label.new()
	hp_lbl.text = "Captain's health"
	hp_lbl.position = Vector2(16, 636)
	hp_lbl.add_theme_color_override("font_color", Color("cfe3f5"))
	hud.add_child(hp_lbl)

	_hint = Label.new()
	_hint.text = "WASD — move, Space / LMB — strike, RMB — camera"
	_hint.position = Vector2(430, 690)
	_hint.add_theme_color_override("font_color", Color("9db4c8"))
	hud.add_child(_hint)


func _ally_crew_now() -> int:
	var total := _ally_reserve
	for f in _fighters:
		if f["side"] == "ally" and f["hp"] > 0:
			total += f["repr"]
	return total


func _enemy_crew_now() -> int:
	var total := _enemy_reserve
	for f in _fighters:
		if f["side"] == "enemy" and f["hp"] > 0:
			total += f["repr"]
	return total


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_try_attack()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clampf(cam_dist * 0.9, 6.0, 30.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clampf(cam_dist * 1.1, 6.0, 30.0)
	elif event is InputEventMouseMotion and _orbiting:
		cam_yaw = wrapf(cam_yaw - event.relative.x * 0.35, 0.0, 360.0)
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.25, 8.0, 60.0)


func _physics_process(delta: float) -> void:
	if _over:
		return
	_time += delta
	var proot: Node3D = player["root"]

	# --- Captain movement ---
	var dir := Vector2.ZERO
	if Input.is_action_pressed("sails_up"):
		dir.y += 1.0
	if Input.is_action_pressed("sails_down"):
		dir.y -= 1.0
	if Input.is_action_pressed("turn_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("turn_right"):
		dir.x += 1.0
	var moving := dir != Vector2.ZERO
	if moving:
		dir = dir.normalized()
		var yr := deg_to_rad(cam_yaw)
		var fwd := Vector3(-sin(yr), 0, -cos(yr))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var motion := (fwd * dir.y + right * dir.x) * MOVE_SPEED * delta
		proot.position += motion
		proot.rotation.y = atan2(-motion.x, -motion.z)
	proot.position.x = clampf(proot.position.x, -deck_halfw, deck_halfw)
	proot.position.z = clampf(proot.position.z, -deck_len * 0.30, deck_len * 0.26)
	proot.position.y = _deck_y_at_z(proot.position.z)
	# Walk cycle.
	var swing := sin(_time * 9.0) * 0.5 if moving else 0.0
	player["l_leg"].rotation.x = lerpf(player["l_leg"].rotation.x, swing, 14.0 * delta)
	player["r_leg"].rotation.x = lerpf(player["r_leg"].rotation.x, -swing, 14.0 * delta)
	player["l_arm"].rotation.x = lerpf(player["l_arm"].rotation.x, -swing * 0.5, 14.0 * delta)

	player_cd = maxf(player_cd - delta, 0.0)
	if Input.is_action_just_pressed("attack"):
		_try_attack()
	# Sword arm returns to guard.
	if player_cd < ATTACK_CD * 0.5:
		player["r_arm"].rotation.x = lerpf(player["r_arm"].rotation.x, -0.5, 8.0 * delta)

	_fighters_ai(delta)

	# --- Camera ---
	var yr2 := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(yr2) * cos(pr), sin(pr), cos(yr2) * cos(pr)) * cam_dist
	camera.position = camera.position.lerp(proot.position + Vector3(0, 1.5, 0) + off, 9.0 * delta)
	camera.look_at(proot.position + Vector3(0, 1.4, 0))

	# --- HUD & end conditions ---
	_lbl_ours.text = "Our crew: %d" % _ally_crew_now()
	_lbl_theirs.text = "Enemy crew: %d" % _enemy_crew_now()
	_hp_bar.value = player_hp

	var enemies_left := false
	for f in _fighters:
		if f["side"] == "enemy" and f["hp"] > 0:
			enemies_left = true
			break
	if not enemies_left:
		_win()
	elif player_hp <= 0.0:
		_retreat()


func _try_attack() -> void:
	if _over or player_cd > 0.0:
		return
	player_cd = ATTACK_CD
	# Sword slash animation.
	var arm: Node3D = player["r_arm"]
	arm.rotation.x = -2.3
	var tw := create_tween()
	tw.tween_property(arm, "rotation:x", 0.7, 0.18)
	# Hit every enemy in a short front cone.
	var proot: Node3D = player["root"]
	var fwd := -proot.global_transform.basis.z
	var dmg: float = 20.0 + Game.state.character.skill("fencing") * 2.5
	for f in _fighters:
		if f["side"] != "enemy" or f["hp"] <= 0:
			continue
		var to_f: Vector3 = f["p"]["root"].position - proot.position
		if to_f.length() < ATTACK_RANGE and to_f.normalized().dot(fwd) > 0.35:
			_hurt_fighter(f, dmg)


func _hurt_fighter(f: Dictionary, dmg: float) -> void:
	f["hp"] = float(f["hp"]) - dmg
	var root: Node3D = f["p"]["root"]
	if f["hp"] <= 0:
		# The fallen stay on deck.
		root.rotation.x = PI / 2.0 * (1 if randf() < 0.5 else -1)
		root.position.y -= 0.4
	else:
		# Flinch.
		root.position += -root.global_transform.basis.z * -0.3


func _fighters_ai(delta: float) -> void:
	var proot: Node3D = player["root"]
	var defense: int = Game.state.character.skill("defense")
	for f in _fighters:
		if f["hp"] <= 0:
			continue
		var root: Node3D = f["p"]["root"]
		f["cd"] = maxf(float(f["cd"]) - delta, 0.0)
		# Pick the nearest opponent (enemies may also hunt the captain).
		var target_pos := Vector3.ZERO
		var target = null
		var best := 1e9
		for g in _fighters:
			if g["side"] == f["side"] or g["hp"] <= 0:
				continue
			var d: float = g["p"]["root"].position.distance_to(root.position)
			if d < best:
				best = d
				target = g
				target_pos = g["p"]["root"].position
		if f["side"] == "enemy":
			var dp := proot.position.distance_to(root.position)
			if target == null or dp < best * 0.8:
				target = "player"
				best = dp
				target_pos = proot.position
		if target == null:
			continue

		if best > 1.4:
			var step: Vector3 = (target_pos - root.position).normalized() * 2.3 * delta
			root.position += step
			root.position.x = clampf(root.position.x, -deck_halfw, deck_halfw)
			root.position.z = clampf(root.position.z, -deck_len * 0.30, deck_len * 0.26)
			root.position.y = _deck_y_at_z(root.position.z)
			root.rotation.y = atan2(-step.x, -step.z)
			f["phase"] = float(f["phase"]) + delta * 8.0
			var sw := sin(f["phase"]) * 0.5
			f["p"]["l_leg"].rotation.x = sw
			f["p"]["r_leg"].rotation.x = -sw
		elif f["cd"] <= 0.0:
			f["cd"] = 1.0
			var arm: Node3D = f["p"]["r_arm"]
			arm.rotation.x = -2.2
			var tw := create_tween()
			tw.tween_property(arm, "rotation:x", 0.5, 0.2)
			if target is String:  # the captain takes the hit
				var dmg: float = maxf(9.0 + randf() * 5.0 - defense * 0.7, 2.0)
				player_hp -= dmg
			else:
				_hurt_fighter(target, 9.0 + randf() * 6.0)


func _win() -> void:
	_over = true
	player_ship.crew = _ally_crew_now()
	enemy_ship.crew = 0
	var c = Game.state.character
	var lt: Dictionary = Boarding.loot(enemy_ship, Game.state.rng)
	c.earn(lt["gold"])
	for g in lt["cargo"]:
		player_ship.add_cargo(g, mini(int(lt["cargo"][g]), player_ship.cargo_free()))
	for a in lt["ammo"]:
		player_ship.ammo_stock[a] = int(player_ship.ammo_stock.get(a, 0)) + int(lt["ammo"][a])
	var outcome: Dictionary = Game.state.on_enemy_sunk(enemy_ship, enemy_nation)
	Game.save_game()
	var msg := "The deck is ours! Seized %d gold and the cargo. XP +%d.%s" % [
		lt["gold"], outcome["xp"], " Level up!" if outcome["level_up"] else ""]
	_end_dialog("Victory", msg, func(): Game.goto_map())


func _retreat() -> void:
	_over = true
	player_ship.crew = _ally_crew_now()
	Game.save_game()
	if player_ship.is_crew_critical():
		_end_dialog("Defeat", "The boarding failed and too few hands remain.\nGame over — load a save or start anew.",
			func(): Game.goto_menu())
	else:
		_end_dialog("Repelled", "Wounded, you are carried back aboard.\nThe enemy cuts the ropes and slips away.",
			func(): Game.goto_map())


func _end_dialog(title: String, msg: String, on_close: Callable) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = title
	dlg.dialog_text = msg
	dlg.confirmed.connect(on_close)
	dlg.canceled.connect(on_close)
	hud.add_child(dlg)
	dlg.popup_centered()
