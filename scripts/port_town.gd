## Walkable 3D port town: quay, anchored ship, streets of houses, and the
## tavern / store / shipyard / governor's mansion. Walk with WASD, orbit the
## camera with RMB, press E near a door to enter. Everything is procedural.
extends Node3D

const World := preload("res://core/world.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")

const WALK_SPEED := 9.0

var player: Node3D
var camera: Camera3D
var cam_yaw := 180.0
var cam_pitch := 16.0
var cam_dist := 14.0
var _orbiting := false
var _time := 0.0
var _ship_node: Node3D

# {pos: Vector3, label: String, action: Callable}
var _interactables: Array = []
var _hint: Label
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	Music.play_theme()
	_rng.seed = hash(Game.state.current_island)
	_build_environment()
	_build_terrain()
	_build_quay_and_ship()
	_build_town()
	_build_player()
	_build_hud()


func _island() -> Dictionary:
	return World.island(Game.state.current_island)


# --- World building ---

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 40, 0)
	sun.light_energy = 1.4
	sun.light_color = Color(1.0, 0.92, 0.78)
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("3572ad")
	sky_mat.sky_horizon_color = Color("d9e2e8")
	sky_mat.ground_bottom_color = Color("2a3c28")
	sky_mat.ground_horizon_color = Color("d9e2e8")
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.glow_enabled = true
	e.glow_intensity = 0.4
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.1
	env.environment = e
	add_child(env)

	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 65.0
	add_child(camera)


func _build_terrain() -> void:
	# Land: a big sandy-green plane.
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(500, 400)
	ground.mesh = gm
	ground.position = Vector3(0, 0, 130)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color("8a9a5b")
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.78, 0.74, 0.6))
	ramp.set_color(1, Color(1, 1, 1))
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.color_ramp = ramp
	ntex.width = 256
	ntex.height = 256
	gmat.albedo_texture = ntex
	gmat.uv1_triplanar = true
	gmat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	ground.material_override = gmat
	add_child(ground)

	# Bay water with the same animated shader as at sea.
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(1200, 800)
	wm.subdivide_width = 60
	wm.subdivide_depth = 40
	water.mesh = wm
	water.position = Vector3(0, -0.8, -410)
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://assets/water.gdshader")
	var wnoise := FastNoiseLite.new()
	wnoise.frequency = 0.008
	wnoise.fractal_octaves = 4
	var wtex := NoiseTexture2D.new()
	wtex.noise = wnoise
	wtex.seamless = true
	wtex.width = 512
	wtex.height = 512
	wmat.set_shader_parameter("noise_tex", wtex)
	water.material_override = wmat
	add_child(water)

	# Hills as a backdrop.
	for i in 6:
		var hill := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = _rng.randf_range(60, 120)
		hm.height = _rng.randf_range(40, 80)
		hill.mesh = hm
		hill.position = Vector3(_rng.randf_range(-220, 220), -8, _rng.randf_range(150, 260))
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color("4d6b3c").lerp(Color("6b7d4a"), _rng.randf())
		hill.material_override = hmat
		add_child(hill)

	# Palms.
	for i in 14:
		var x := _rng.randf_range(-90, 90)
		var z := _rng.randf_range(4, 90)
		if absf(x) < 40.0 and z < 55.0:
			continue  # keep the town square clear
		_palm(Vector3(x, 0, z))


func _palm(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15
	tm.bottom_radius = 0.3
	tm.height = 6.0
	trunk.mesh = tm
	trunk.position = pos + Vector3(0, 3, 0)
	trunk.rotation_degrees = Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("6b4a2b")
	trunk.material_override = tmat
	add_child(trunk)
	for i in 5:
		var leaf := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 1.6
		lm.height = 0.5
		leaf.mesh = lm
		var ang := TAU * i / 5.0
		leaf.position = pos + Vector3(cos(ang) * 1.2, 6.1, sin(ang) * 1.2)
		leaf.rotation_degrees = Vector3(rad_to_deg(sin(ang)) * 0.06 + 8, 0, rad_to_deg(cos(ang)) * 0.06)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color("3f6b2f")
		leaf.material_override = lmat
		add_child(leaf)


func _build_quay_and_ship() -> void:
	# Stone quay along the waterfront.
	var quay := MeshInstance3D.new()
	var qm := BoxMesh.new()
	qm.size = Vector3(140, 3.0, 10)
	quay.mesh = qm
	quay.position = Vector3(0, -0.6, -5)
	var qmat := StandardMaterial3D.new()
	qmat.albedo_color = Color("8d8577")
	quay.material_override = qmat
	add_child(quay)

	# Props: barrels and crates.
	for i in 10:
		var x := _rng.randf_range(-55, 55)
		if _rng.randf() < 0.5:
			var barrel := MeshInstance3D.new()
			var bm := CylinderMesh.new()
			bm.top_radius = 0.5
			bm.bottom_radius = 0.55
			bm.height = 1.2
			barrel.mesh = bm
			barrel.position = Vector3(x, 1.5, _rng.randf_range(-7, -3))
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color("5d4024")
			barrel.material_override = bmat
			add_child(barrel)
		else:
			var crate := MeshInstance3D.new()
			var cmesh := BoxMesh.new()
			cmesh.size = Vector3(1.1, 1.1, 1.1)
			crate.mesh = cmesh
			crate.position = Vector3(x, 1.45, _rng.randf_range(-7, -3))
			crate.rotation_degrees = Vector3(0, _rng.randf_range(0, 90), 0)
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = Color("8a6a3f")
			crate.material_override = cmat
			add_child(crate)

	# The player's ship anchored in the bay.
	_ship_node = Node3D.new()
	_ship_node.set_script(ShipVisualScript)
	add_child(_ship_node)
	var rank: int = Game.state.ship.spec()["rank"]
	_ship_node.build(18.0 + (8 - rank) * 5.0, Color(World.NATIONS[Game.state.character.nation]["color"]))
	_ship_node.position = Vector3(18, -0.8, -38)
	_ship_node.rotation_degrees = Vector3(0, 65, 0)
	_ship_node.set_sail_amount(0.06)

	_interactables.append({
		"pos": Vector3(0, 1.0, -8),
		"label": "Set sail — world map",
		"action": func(): Game.goto_map(),
	})


func _build_town() -> void:
	# Plain houses along two streets.
	for i in 9:
		var x := -52.0 + i * 13.0 + _rng.randf_range(-2, 2)
		if absf(x) < 8.0:
			continue  # leave the main street open
		_house(Vector3(x, 0, 24 + _rng.randf_range(-2, 2)), Vector3(7, 5, 6), _wall_color(), _roof_color())
	for i in 7:
		var x := -45.0 + i * 15.0 + _rng.randf_range(-2, 2)
		_house(Vector3(x, 0, 42 + _rng.randf_range(-2, 2)), Vector3(8, 5.5, 7), _wall_color(), _roof_color())

	# Special buildings with signs and interactions.
	_special_building(Vector3(-26, 0, 12), Vector3(12, 7, 9), Color("b0765a"), "Tavern",
		"Tavern — hire crew, quests", func(): Game.goto_port_ui(0))
	_special_building(Vector3(26, 0, 12), Vector3(12, 7, 9), Color("d9c9a8"), "Store",
		"Store — trade goods", func(): Game.goto_port_ui(1))
	_special_building(Vector3(52, 0, 4), Vector3(14, 6, 12), Color("7d6a4f"), "Shipyard",
		"Shipyard — ships, ammo, repairs", func(): Game.goto_port_ui(2))
	# Governor's mansion: bigger, whitewashed, with columns.
	var gpos := Vector3(0, 0, 56)
	_special_building(gpos, Vector3(18, 9, 12), Color("e8e2d4"), "Governor",
		"Governor — quests and audience", func(): Game.goto_port_ui(0))
	for cx in [-6.0, -2.0, 2.0, 6.0]:
		var col := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.45
		cm.bottom_radius = 0.45
		cm.height = 7.0
		col.mesh = cm
		col.position = gpos + Vector3(cx, 3.5, -6.8)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color("f0ece0")
		col.material_override = cmat
		add_child(col)


func _wall_color() -> Color:
	return [Color("e3d7bd"), Color("d9c9a8"), Color("c9b8a0"), Color("b8a488")][_rng.randi_range(0, 3)]


func _roof_color() -> Color:
	return [Color("8a4a32"), Color("6e3a28"), Color("5d4024")][_rng.randi_range(0, 2)]


func _house(pos: Vector3, size: Vector3, wall: Color, roof: Color) -> void:
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	body.position = pos + Vector3(0, size.y / 2.0, 0)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = wall
	body.material_override = wmat
	add_child(body)

	var roof_mesh := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x + 0.8, size.y * 0.5, size.z + 0.8)
	roof_mesh.mesh = pm
	roof_mesh.position = pos + Vector3(0, size.y + size.y * 0.25, 0)
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = roof
	roof_mesh.material_override = rmat
	add_child(roof_mesh)

	# Door on the street side.
	var door := MeshInstance3D.new()
	var dm := BoxMesh.new()
	dm.size = Vector3(1.2, 2.2, 0.2)
	door.mesh = dm
	door.position = pos + Vector3(0, 1.1, -size.z / 2.0 - 0.05)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color("3a2513")
	door.material_override = dmat
	add_child(door)


func _special_building(pos: Vector3, size: Vector3, wall: Color, sign_text: String,
		hint: String, action: Callable) -> void:
	_house(pos, size, wall, _roof_color())
	var sign := Label3D.new()
	sign.text = sign_text
	sign.font_size = 220
	sign.pixel_size = 0.01
	sign.modulate = Color("ffe9b0")
	sign.outline_size = 24
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = pos + Vector3(0, size.y + size.y * 0.5 + 1.6, 0)
	add_child(sign)
	_interactables.append({
		"pos": pos + Vector3(0, 1.0, -size.z / 2.0 - 1.5),
		"label": hint,
		"action": action,
	})


# --- Player ---

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	player.position = Vector3(0, 1.0, 2)
	# A tiny captain: boots-to-hat out of primitives.
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.42
	cm.height = 1.7
	body.mesh = cm
	body.position = Vector3(0, 0.85, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("35405c")
	body.material_override = bmat
	player.add_child(body)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.28
	hm.height = 0.56
	head.mesh = hm
	head.position = Vector3(0, 1.95, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color("d9a97a")
	head.material_override = hmat
	player.add_child(head)
	var hat := MeshInstance3D.new()
	var htm := CylinderMesh.new()
	htm.top_radius = 0.42
	htm.bottom_radius = 0.5
	htm.height = 0.16
	hat.mesh = htm
	hat.position = Vector3(0, 2.2, 0)
	var hatmat := StandardMaterial3D.new()
	hatmat.albedo_color = Color("1d1208")
	hat.material_override = hatmat
	player.add_child(hat)


var _hud: CanvasLayer
var _status: Label


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	_status = Label.new()
	_status.position = Vector2(16, 12)
	_status.add_theme_color_override("font_color", Color("e8c872"))
	_status.add_theme_font_size_override("font_size", 16)
	var isl := _island()
	_status.text = "%s (%s) | Day %d | %d gold | WASD — walk, E — enter, RMB — camera, Tab — port menu" % [
		isl["name"], World.NATIONS[isl["nation"]]["name"], Game.state.day, Game.state.character.gold]
	_hud.add_child(_status)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(440, 620)
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.add_theme_color_override("font_color", Color("ffffff"))
	_hud.add_child(_hint)


# --- Input & movement ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam_dist = clampf(cam_dist * 0.9, 6.0, 40.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam_dist = clampf(cam_dist * 1.1, 6.0, 40.0)
	elif event is InputEventMouseMotion and _orbiting:
		cam_yaw = wrapf(cam_yaw - event.relative.x * 0.35, 0.0, 360.0)
		cam_pitch = clampf(cam_pitch + event.relative.y * 0.25, 4.0, 60.0)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_TAB:
		Game.goto_port_ui()


func _physics_process(delta: float) -> void:
	_time += delta
	# Movement relative to the camera yaw.
	var dir := Vector2.ZERO
	if Input.is_action_pressed("sails_up"):
		dir.y += 1.0
	if Input.is_action_pressed("sails_down"):
		dir.y -= 1.0
	if Input.is_action_pressed("turn_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("turn_right"):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var yr := deg_to_rad(cam_yaw)
		var fwd := Vector3(-sin(yr), 0, -cos(yr))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var motion := (fwd * dir.y + right * dir.x) * WALK_SPEED * delta
		player.position += motion
		player.position.x = clampf(player.position.x, -70.0, 70.0)
		player.position.z = clampf(player.position.z, -9.0, 75.0)
		player.rotation.y = atan2(-motion.x, -motion.z)

	# Ship bobbing at anchor.
	if _ship_node != null:
		_ship_node.bob(_time, 0.7)
		_ship_node.position.y += -0.8

	# Orbit camera around the player.
	var yr2 := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(yr2) * cos(pr), sin(pr), cos(yr2) * cos(pr)) * cam_dist
	camera.position = camera.position.lerp(player.position + Vector3(0, 1.6, 0) + off, 10.0 * delta)
	camera.look_at(player.position + Vector3(0, 1.8, 0))

	# Nearest interactable within range.
	var best = null
	var best_d := 6.0
	for it in _interactables:
		var d: float = player.position.distance_to(it["pos"])
		if d < best_d:
			best_d = d
			best = it
	if best != null:
		_hint.text = "[E]  %s" % best["label"]
		if Input.is_action_just_pressed("interact"):
			best["action"].call()
	else:
		_hint.text = ""
