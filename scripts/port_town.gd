## Walkable 3D port town: quay, anchored ship, colonial streets, tavern /
## store / shipyard / governor's mansion, lamp posts, a well, a market stall.
## Walk with WASD, orbit the camera with RMB, press E near a door to enter.
## Everything is procedural — no imported assets.
extends Node3D

const World := preload("res://core/world.gd")
const Sailing := preload("res://core/sailing.gd")
const ShipVisualScript := preload("res://scripts/ship_visual.gd")
const Person := preload("res://scripts/person.gd")

const WALK_SPEED := 9.0
const SAIL_SPEED_SCALE := 2.6
const ANCHOR_POS := Vector3(22, -0.8, -48)
const ANCHOR_ROT_Y := 65.0

var player: Node3D
var camera: Camera3D
var cam_yaw := 180.0
var cam_pitch := 18.0
var cam_dist := 15.0
var _orbiting := false
var _time := 0.0
var _ship_node: Node3D

# {pos: Vector3, label: String, action: Callable}
var _interactables: Array = []
## Building footprints the player cannot walk through (XZ rects).
var _colliders: Array = []   # Rect2: position = min corner (x, z)

# Interiors: rooms are built far below the town; entering teleports there.
var _interior_count := 0
var _inside := false
var _room_bounds := Rect2()
var _room_floor_y := 0.0
var _return_pos := Vector3.ZERO

# Harbor sailing: the player boards the ship and steers it around the bay.
var _sailing := false
var _ship_heading := 0.0
var _ship_len := 25.0
var _hint: Label
var _rng := RandomNumberGenerator.new()

# Player limb pivots for the walk cycle.
var _limbs := {}
var _walk_phase := 0.0
var _moving := false

const TIMBER := Color("3a2d1c")
const WALL_COLORS := [Color("efe6d2"), Color("e6d3a8"), Color("d9b8a0"), Color("c9dcd4"), Color("e0c6c0")]
const ROOF_COLORS := [Color("9a4a2e"), Color("7d3b26"), Color("5d4024")]


func _ready() -> void:
	Music.play_theme()
	_rng.seed = hash(Game.state.current_island)
	_build_environment()
	_build_terrain()
	_build_quay_and_ship()
	_build_town()
	_build_props()
	_build_player()
	_build_npcs()
	_build_hud()


func _island() -> Dictionary:
	return World.island(Game.state.current_island)


# --- Environment & terrain ---

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-34, 48, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-55, -130, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.78, 0.95)
	add_child(fill)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("2f6698")
	sky_mat.sky_horizon_color = Color("e8d8b8")
	sky_mat.sky_curve = 0.14
	sky_mat.ground_bottom_color = Color("2a3c28")
	sky_mat.ground_horizon_color = Color("e8d8b8")
	sky_mat.sun_angle_max = 25.0
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.45
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.fog_enabled = true
	e.fog_light_color = Color("dcc9a6")
	e.fog_density = 0.0012
	env.environment = e
	add_child(env)

	camera = Camera3D.new()
	camera.far = 3000.0
	camera.fov = 65.0
	add_child(camera)


func _build_terrain() -> void:
	# Grass starts BEHIND the quay — the bay stays pure water.
	var ground := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(500, 360)
	ground.mesh = gm
	ground.position = Vector3(0, 0, 186)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color("55713a")
	gmat.albedo_texture = _noise_tex(0.05, Color(0.85, 0.85, 0.78))
	gmat.uv1_triplanar = true
	gmat.uv1_scale = Vector3(0.5, 0.5, 0.5)
	ground.material_override = gmat
	add_child(ground)

	# A sandy shoreline strip between the quay and the grass.
	var sand := MeshInstance3D.new()
	var sm := PlaneMesh.new()
	sm.size = Vector2(500, 10)
	sand.mesh = sm
	sand.position = Vector3(0, 0.02, 5)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color("c2a878")
	smat.albedo_texture = _noise_tex(0.15, Color(0.88, 0.85, 0.8))
	smat.uv1_triplanar = true
	sand.material_override = smat
	add_child(sand)

	# Cobblestone main street and square.
	for cobble in [
		{"size": Vector2(14, 60), "pos": Vector3(0, 0.04, 32)},
		{"size": Vector2(70, 12), "pos": Vector3(0, 0.04, 14)},
	]:
		var street := MeshInstance3D.new()
		var stm := PlaneMesh.new()
		stm.size = cobble["size"]
		street.mesh = stm
		street.position = cobble["pos"]
		var stmat := StandardMaterial3D.new()
		stmat.albedo_color = Color("7d7466")
		stmat.albedo_texture = _noise_tex(0.4, Color(0.75, 0.73, 0.7))
		stmat.uv1_triplanar = true
		stmat.uv1_scale = Vector3(2, 2, 2)
		street.material_override = stmat
		add_child(street)

	# Bay water with the same animated shader as at sea.
	var water := MeshInstance3D.new()
	var wm := PlaneMesh.new()
	wm.size = Vector2(1200, 810)
	wm.subdivide_width = 60
	wm.subdivide_depth = 40
	water.mesh = wm
	# Ends just past the quay so wave crests never poke through the land.
	water.position = Vector3(0, -0.8, -407)
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
		# Keep the near slope behind the town: no hill may reach past z = 90.
		var hill_z: float = _rng.randf_range(90.0 + hm.radius, 200.0 + hm.radius)
		hill.position = Vector3(_rng.randf_range(-220, 220), -8, hill_z)
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color("42592f").lerp(Color("5d7040"), _rng.randf())
		hill.material_override = hmat
		add_child(hill)

	# Palms.
	for i in 14:
		var x := _rng.randf_range(-90, 90)
		var z := _rng.randf_range(4, 90)
		if absf(x) < 40.0 and z < 66.0:
			continue  # keep the town clear
		_palm(Vector3(x, 0, z))


func _noise_tex(freq: float, dark: Color) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = freq
	var ramp := Gradient.new()
	ramp.set_color(0, dark)
	ramp.set_color(1, Color(1, 1, 1))
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.color_ramp = ramp
	ntex.width = 256
	ntex.height = 256
	return ntex


func _palm(pos: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.15
	tm.bottom_radius = 0.3
	tm.height = 6.0
	trunk.mesh = tm
	trunk.position = pos + Vector3(0, 3, 0)
	trunk.rotation_degrees = Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
	trunk.material_override = _mat(Color("6b4a2b"))
	add_child(trunk)
	for i in 5:
		var leaf := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 1.6
		lm.height = 0.5
		leaf.mesh = lm
		var ang := TAU * i / 5.0
		leaf.position = pos + Vector3(cos(ang) * 1.2, 6.1, sin(ang) * 1.2)
		leaf.rotation_degrees = Vector3(8, 0, 0)
		leaf.material_override = _mat(Color("3f6b2f"))
		add_child(leaf)


func _mat(c: Color, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.8
	return m


func _mesh_box(size: Vector3, pos: Vector3, c: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = _mat(c, emissive)
	add_child(mi)
	return mi


func _mesh_cyl(r_top: float, r_bot: float, h: float, pos: Vector3, c: Color, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _mat(c, emissive)
	add_child(mi)
	return mi


# --- Quay & ship ---

func _build_quay_and_ship() -> void:
	var quay := _mesh_box(Vector3(140, 3.0, 10), Vector3(0, -0.6, -5), Color("948a76"))
	quay.material_override.albedo_texture = _noise_tex(0.3, Color(0.7, 0.68, 0.64))
	quay.material_override.uv1_triplanar = true

	# Mooring posts along the edge.
	for i in 8:
		_mesh_cyl(0.22, 0.25, 1.4, Vector3(-56 + i * 16, 1.4, -9.2), Color("3a2d1c"))

	# Props: barrels and crates on the quay.
	for i in 10:
		var x := _rng.randf_range(-55, 55)
		if _rng.randf() < 0.5:
			_mesh_cyl(0.5, 0.55, 1.2, Vector3(x, 1.5, _rng.randf_range(-7, -3)), Color("5d4024"))
		else:
			var crate := _mesh_box(Vector3(1.1, 1.1, 1.1), Vector3(x, 1.45, _rng.randf_range(-7, -3)), Color("8a6a3f"))
			crate.rotation_degrees = Vector3(0, _rng.randf_range(0, 90), 0)

	# The player's ship anchored in the bay.
	_ship_node = Node3D.new()
	_ship_node.set_script(ShipVisualScript)
	add_child(_ship_node)
	var rank: int = Game.state.ship.spec()["rank"]
	_ship_len = 18.0 + (8 - rank) * 5.0
	_ship_node.build(_ship_len, Color(World.NATIONS[Game.state.character.nation]["color"]), true, Game.state.ship.type_id)
	_ship_node.position = ANCHOR_POS
	_ship_node.rotation_degrees = Vector3(0, ANCHOR_ROT_Y, 0)
	_ship_node.set_sail_amount(0.06)

	_interactables.append({
		"pos": Vector3(14, 1.0, -9),
		"label": "Board your ship",
		"action": func(): _board_ship(),
	})
	_interactables.append({
		"pos": Vector3(0, 1.0, -8),
		"label": "Depart from %s — choose destination" % _island()["name"],
		"action": func(): Game.goto_map(),
	})


# --- Town ---

func _build_town() -> void:
	# Plain colonial houses along two streets.
	for i in 9:
		var x := -52.0 + i * 13.0 + _rng.randf_range(-2, 2)
		if absf(x) < 9.0:
			continue  # leave the main street open
		_house(Vector3(x, 0, 26 + _rng.randf_range(-2, 2)), Vector3(7, 5, 6))
	for i in 7:
		var x := -45.0 + i * 15.0 + _rng.randf_range(-2, 2)
		if absf(x) < 9.0:
			continue
		_house(Vector3(x, 0, 44 + _rng.randf_range(-2, 2)), Vector3(8, 5.5, 7))

	# Special buildings with signs and interactions.
	_special_building(Vector3(-26, 0, 12), Vector3(12, 7, 9), Color("b0765a"), "Tavern",
		"Tavern — hire crew, quests", "tavern", 0)
	_special_building(Vector3(26, 0, 12), Vector3(12, 7, 9), Color("e6d3a8"), "Store",
		"Store — trade goods", "store", 1)
	_special_building(Vector3(52, 0, 2), Vector3(14, 6, 12), Color("c9b8a0"), "Shipyard",
		"Shipyard — ships, ammo, repairs", "shipyard", 2)
	var gpos := Vector3(0, 0, 62)
	_special_building(gpos, Vector3(18, 9, 12), Color("f2ede0"), "Governor",
		"Governor — quests and audience", "governor", 0)
	for cx in [-6.0, -2.0, 2.0, 6.0]:
		_mesh_cyl(0.45, 0.45, 7.0, gpos + Vector3(cx, 3.5, -6.8), Color("f5f1e6"))


## A colonial house: timber-framed walls, windows with shutters, a door,
## a roof with an overhang, sometimes a chimney. Registers a collider and
## builds an enterable interior behind its door.
func _house(pos: Vector3, size: Vector3, wall_c: Color = Color.TRANSPARENT, roof_c: Color = Color.TRANSPARENT,
		kind: String = "house", title: String = "the house", ui_tab: int = -1) -> void:
	var wall: Color = wall_c if wall_c.a > 0.0 else WALL_COLORS[_rng.randi_range(0, WALL_COLORS.size() - 1)]
	var roof: Color = roof_c if roof_c.a > 0.0 else ROOF_COLORS[_rng.randi_range(0, ROOF_COLORS.size() - 1)]

	var body := _mesh_box(size, pos + Vector3(0, size.y / 2.0, 0), wall)
	body.material_override.albedo_texture = _noise_tex(0.5, Color(0.9, 0.89, 0.86))
	body.material_override.uv1_triplanar = true

	# Timber frame: corner posts + a horizontal beam.
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		_mesh_box(Vector3(0.28, size.y, 0.28),
			pos + Vector3(corner.x * size.x / 2.0, size.y / 2.0, corner.z * size.z / 2.0), TIMBER)
	_mesh_box(Vector3(size.x + 0.1, 0.22, 0.1), pos + Vector3(0, size.y * 0.55, -size.z / 2.0 - 0.06), TIMBER)

	# Roof with overhang + sometimes a chimney.
	var roof_mesh := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(size.x + 1.4, size.y * 0.55, size.z + 1.4)
	roof_mesh.mesh = pm
	roof_mesh.position = pos + Vector3(0, size.y + size.y * 0.275, 0)
	roof_mesh.material_override = _mat(roof)
	add_child(roof_mesh)
	if _rng.randf() < 0.5:
		_mesh_box(Vector3(0.8, size.y * 0.8, 0.8), pos + Vector3(size.x * 0.25, size.y + size.y * 0.5, 0), Color("6e6257"))

	# Door with a frame and a step.
	_mesh_box(Vector3(1.5, 2.6, 0.12), pos + Vector3(0, 1.3, -size.z / 2.0 - 0.10), TIMBER)
	_mesh_box(Vector3(1.15, 2.3, 0.16), pos + Vector3(0, 1.15, -size.z / 2.0 - 0.14), Color("5d4024"))
	_mesh_box(Vector3(2.0, 0.24, 1.0), pos + Vector3(0, 0.12, -size.z / 2.0 - 0.5), Color("8d8577"))

	# Two windows with white frames and colored shutters.
	var shutter: Color = [Color("3f6b58"), Color("35405c"), Color("8d3a2e")][_rng.randi_range(0, 2)]
	for wx in [-size.x * 0.28, size.x * 0.28]:
		_mesh_box(Vector3(1.3, 1.5, 0.10), pos + Vector3(wx, size.y * 0.55, -size.z / 2.0 - 0.08), Color("f5f1e6"))
		_mesh_box(Vector3(1.0, 1.2, 0.14), pos + Vector3(wx, size.y * 0.55, -size.z / 2.0 - 0.10), Color("20303c"))
		for sx in [-0.85, 0.85]:
			_mesh_box(Vector3(0.45, 1.3, 0.08), pos + Vector3(wx + sx, size.y * 0.55, -size.z / 2.0 - 0.09), shutter)

	_colliders.append(Rect2(pos.x - size.x / 2.0 - 0.6, pos.z - size.z / 2.0 - 0.6, size.x + 1.2, size.z + 1.2))

	# Every building is enterable: the door leads to a furnished room.
	var room := _build_interior(kind, title, ui_tab)
	_interactables.append({
		"pos": pos + Vector3(0, 1.0, -size.z / 2.0 - 1.2),
		"label": "Enter %s" % title,
		"action": func(): _enter_interior(room),
	})


func _special_building(pos: Vector3, size: Vector3, wall: Color, sign_text: String,
		hint: String, kind: String, ui_tab: int) -> void:
	_house(pos, size, wall, Color.TRANSPARENT, kind, "the %s" % sign_text.to_lower(), ui_tab)
	var sign := Label3D.new()
	sign.text = sign_text
	sign.font_size = 220
	sign.pixel_size = 0.01
	sign.modulate = Color("ffe9b0")
	sign.outline_size = 24
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.position = pos + Vector3(0, size.y * 1.75 + 1.4, 0)
	add_child(sign)
	# A hanging wooden signboard by the door too.
	_mesh_box(Vector3(1.6, 1.0, 0.1), pos + Vector3(size.x * 0.4, 3.2, -size.z / 2.0 - 0.4), Color("5d4024"))


## Street furniture: lamp posts, a well, a market stall.
func _build_props() -> void:
	for z in [8.0, 22.0, 36.0, 50.0]:
		for x in [-7.5, 7.5]:
			_mesh_cyl(0.09, 0.12, 3.4, Vector3(x, 1.7, z), TIMBER)
			var lamp := MeshInstance3D.new()
			var lm := SphereMesh.new()
			lm.radius = 0.24
			lm.height = 0.48
			lamp.mesh = lm
			lamp.position = Vector3(x, 3.5, z)
			lamp.material_override = _mat(Color(1.0, 0.8, 0.45), true)
			add_child(lamp)

	# Town well on the square.
	_mesh_cyl(1.3, 1.4, 1.0, Vector3(-4, 0.5, 16), Color("8d8577"))
	_mesh_cyl(0.09, 0.09, 2.2, Vector3(-5.1, 1.9, 16), TIMBER)
	_mesh_cyl(0.09, 0.09, 2.2, Vector3(-2.9, 1.9, 16), TIMBER)
	var well_roof := MeshInstance3D.new()
	var wrm := PrismMesh.new()
	wrm.size = Vector3(3.2, 1.0, 2.4)
	well_roof.mesh = wrm
	well_roof.position = Vector3(-4, 3.3, 16)
	well_roof.material_override = _mat(Color("7d3b26"))
	add_child(well_roof)
	_colliders.append(Rect2(-5.6, 14.4, 3.2, 3.2))

	# Market stall near the store: striped awning over crates.
	for px in [21.0, 25.0]:
		for pz in [17.0, 20.0]:
			_mesh_cyl(0.08, 0.08, 2.6, Vector3(px, 1.3, pz), TIMBER)
	var awning := MeshInstance3D.new()
	var am := PrismMesh.new()
	am.size = Vector3(5.4, 0.9, 4.2)
	awning.mesh = am
	awning.position = Vector3(23, 3.0, 18.5)
	awning.material_override = _mat(Color("a8453a"))
	add_child(awning)
	_mesh_box(Vector3(3.6, 1.0, 2.4), Vector3(23, 0.5, 18.5), Color("8a6a3f"))
	for i in 4:
		_mesh_box(Vector3(0.8, 0.5, 0.6),
			Vector3(21.8 + (i % 2) * 2.4, 1.25, 17.8 + int(i / 2.0) * 1.4),
			[Color("b0765a"), Color("6b7d4a"), Color("c9a24a"), Color("8d3a2e")][i])
	_colliders.append(Rect2(20.0, 16.0, 6.0, 5.0))


# --- Interiors ---

## Build a furnished room for a building and return its entry data.
## kind: "tavern" | "store" | "shipyard" | "governor" | "house"
func _build_interior(kind: String, title: String, ui_tab: int) -> Dictionary:
	var base := Vector3(300 + _interior_count * 50, -60, 0)
	_interior_count += 1
	var w := 13.0
	var d := 10.0
	var h := 4.2
	var wall_c := Color("d9cfb8")
	var floor_c := Color("6b5233")

	# Shell: floor, ceiling, four walls.
	_mesh_box(Vector3(w, 0.3, d), base + Vector3(0, -0.15, 0), floor_c)
	_mesh_box(Vector3(w, 0.3, d), base + Vector3(0, h, 0), Color("3a2d1c"))
	_mesh_box(Vector3(w, h, 0.3), base + Vector3(0, h / 2.0, -d / 2.0), wall_c)
	_mesh_box(Vector3(w, h, 0.3), base + Vector3(0, h / 2.0, d / 2.0), wall_c)
	_mesh_box(Vector3(0.3, h, d), base + Vector3(-w / 2.0, h / 2.0, 0), wall_c)
	_mesh_box(Vector3(0.3, h, d), base + Vector3(w / 2.0, h / 2.0, 0), wall_c)
	# Door mark on the front wall + glowing windows + warm light.
	_mesh_box(Vector3(1.3, 2.5, 0.1), base + Vector3(0, 1.25, d / 2.0 - 0.12), Color("3a2513"))
	for wx in [-w * 0.3, w * 0.3]:
		_mesh_box(Vector3(1.4, 1.2, 0.1), base + Vector3(wx, 2.3, -d / 2.0 + 0.12), Color(1.0, 0.87, 0.6), true)
	var light := OmniLight3D.new()
	light.position = base + Vector3(0, h - 0.8, 0)
	light.light_color = Color(1.0, 0.85, 0.62)
	light.light_energy = 1.6
	light.omni_range = 16.0
	add_child(light)

	_furnish(kind, base, w, d, ui_tab, title)

	var spawn := base + Vector3(0, 0.1, d / 2.0 - 1.6)
	_interactables.append({
		"pos": base + Vector3(0, 1.0, d / 2.0 - 0.8),
		"label": "Leave %s" % title,
		"action": func(): _exit_interior(),
	})
	return {
		"spawn": spawn,
		"bounds": Rect2(base.x - w / 2.0 + 0.7, base.z - d / 2.0 + 0.7, w - 1.4, d - 1.4),
		"floor_y": base.y,
	}


func _furnish(kind: String, base: Vector3, w: float, d: float, ui_tab: int, title: String) -> void:
	match kind:
		"tavern":
			# Bar counter, kegs, tables with stools, a fireplace.
			_mesh_box(Vector3(0.9, 1.1, d * 0.55), base + Vector3(w / 2.0 - 1.3, 0.55, 0), Color("4a2e15"))
			for i in 3:
				_mesh_cyl(0.42, 0.46, 1.0, base + Vector3(w / 2.0 - 0.7, 0.5, -d * 0.28 + i * 1.4), Color("5d4024"))
			for tp in [Vector3(-2.5, 0, 1.2), Vector3(-3.2, 0, -2.2), Vector3(1.2, 0, -1.6)]:
				_table_with_stools(base + tp)
			_fireplace(base + Vector3(-w / 2.0 + 0.7, 0, -d * 0.2))
			_room_npc(base + Vector3(w / 2.0 - 2.4, 0, 0), Color("8d3a2e"),
				"Barkeeper — crew, quests & rumors", ui_tab)
		"store":
			for sx in [-w * 0.28, w * 0.05]:
				_shelf(base + Vector3(sx, 0, -d / 2.0 + 0.9))
			_mesh_box(Vector3(2.6, 1.05, 0.8), base + Vector3(w * 0.28, 0.52, 0.5), Color("4a2e15"))
			for i in 5:
				_mesh_box(Vector3(0.7, 0.7, 0.7),
					base + Vector3(-w * 0.3 + i * 0.9, 0.35, d * 0.28),
					[Color("b0765a"), Color("6b7d4a"), Color("c9a24a"), Color("8d3a2e"), Color("35405c")][i])
			_room_npc(base + Vector3(w * 0.28, 0, -0.6), Color("6b7d4a"),
				"Merchant — buy & sell goods", ui_tab)
		"shipyard":
			for i in 3:
				var log := _mesh_cyl(0.28, 0.28, 5.0, base + Vector3(-w * 0.25, 0.3 + i * 0.5, -d * 0.3 + i * 0.1), Color("6b4a2b"))
				log.rotation_degrees = Vector3(0, 0, 90)
			_mesh_box(Vector3(3.2, 0.9, 1.2), base + Vector3(w * 0.22, 0.45, -d * 0.25), Color("4a2e15"))
			_mesh_box(Vector3(0.5, 0.5, 2.6), base + Vector3(w * 0.22, 1.15, -d * 0.25), Color("8a6a3f"))
			for i in 4:
				_mesh_cyl(0.3, 0.34, 0.8, base + Vector3(-w * 0.15 + i * 1.1, 0.4, d * 0.28), Color("5d4024"))
			_room_npc(base + Vector3(w * 0.22, 0, 0.8), Color("35405c"),
				"Shipwright — ships, ammo & repairs", ui_tab)
		"governor":
			_mesh_box(Vector3(w * 0.6, 0.06, d * 0.5), base + Vector3(0, 0.03, 0), Color("7a2c2c"))
			_mesh_box(Vector3(2.8, 0.9, 1.3), base + Vector3(0, 0.45, -d * 0.22), Color("4a2e15"))
			_mesh_box(Vector3(0.7, 1.3, 0.7), base + Vector3(0, 0.65, -d * 0.36), Color("6e3a28"))
			for cx in [-w * 0.3, w * 0.3]:
				_mesh_cyl(0.35, 0.4, 4.0, base + Vector3(cx, 2.0, -d * 0.1), Color("f0ece0"))
			_shelf(base + Vector3(w * 0.32, 0, -d / 2.0 + 0.9))
			_room_npc(base + Vector3(0, 0, -d * 0.16), Color("35405c"),
				"Governor — quests and audience", ui_tab)
		_:
			# A commoner's home: bed, table, chest, sometimes someone in.
			_mesh_box(Vector3(2.2, 0.5, 1.2), base + Vector3(-w * 0.28, 0.25, -d * 0.3), Color("6e3a28"))
			_mesh_box(Vector3(0.6, 0.18, 1.0), base + Vector3(-w * 0.36, 0.6, -d * 0.3), Color("e8e2d0"))
			_table_with_stools(base + Vector3(w * 0.15, 0, 0.4))
			_mesh_box(Vector3(1.1, 0.7, 0.7), base + Vector3(w * 0.3, 0.35, -d * 0.32), Color("5d4024"))
			_fireplace(base + Vector3(-w / 2.0 + 0.7, 0, d * 0.15))
			if _rng.randf() < 0.6:
				_room_npc(base + Vector3(w * 0.1, 0, -d * 0.15),
					NPC_CLOTHES[_rng.randi_range(0, NPC_CLOTHES.size() - 1)], "", -1)


func _table_with_stools(pos: Vector3) -> void:
	_mesh_cyl(0.8, 0.8, 0.08, pos + Vector3(0, 0.78, 0), Color("8a6a3f"))
	_mesh_cyl(0.09, 0.11, 0.76, pos + Vector3(0, 0.38, 0), Color("4a2e15"))
	for i in 3:
		var ang := TAU * i / 3.0 + 0.5
		_mesh_cyl(0.26, 0.26, 0.45, pos + Vector3(cos(ang) * 1.15, 0.22, sin(ang) * 1.15), Color("5d4024"))


func _shelf(pos: Vector3) -> void:
	_mesh_box(Vector3(3.0, 2.4, 0.5), pos + Vector3(0, 1.2, 0), Color("4a2e15"))
	for row in 3:
		for i in 4:
			_mesh_box(Vector3(0.45, 0.4, 0.4),
				pos + Vector3(-1.1 + i * 0.75, 0.55 + row * 0.75, -0.1),
				NPC_CLOTHES[(row * 4 + i) % NPC_CLOTHES.size()])


func _fireplace(pos: Vector3) -> void:
	_mesh_box(Vector3(1.6, 2.2, 0.9), pos + Vector3(0, 1.1, 0), Color("6e6257"))
	_mesh_box(Vector3(0.9, 0.8, 0.5), pos + Vector3(0, 0.5, 0.25), Color(1.0, 0.55, 0.15), true)


## A static NPC standing in a room; optional Talk interaction opens a UI tab.
func _room_npc(pos: Vector3, cloth: Color, talk_label: String, ui_tab: int) -> void:
	var person := Person.build(cloth, Color("d9a97a"), false, 0 if talk_label == "" else 1)
	var npc: Node3D = person["root"]
	npc.position = pos
	npc.rotation.y = PI  # face the door
	add_child(npc)
	# Arms resting slightly outward.
	person["l_arm"].rotation.z = 0.18
	person["r_arm"].rotation.z = -0.18
	if talk_label != "":
		_interactables.append({
			"pos": pos + Vector3(0, 1.0, 0),
			"label": talk_label,
			"action": func(): Game.goto_port_ui(ui_tab),
		})


func _enter_interior(room: Dictionary) -> void:
	_return_pos = player.position
	_inside = true
	_room_bounds = room["bounds"]
	_room_floor_y = room["floor_y"]
	player.position = room["spawn"]
	camera.position = player.position + Vector3(0, 3, 6)


func _exit_interior() -> void:
	_inside = false
	player.position = _return_pos
	camera.position = player.position + Vector3(0, 4, 10)


# --- Harbor sailing ---

func _board_ship() -> void:
	_sailing = true
	_ship_heading = wrapf(-ANCHOR_ROT_Y, 0.0, 360.0)
	Game.state.ship.sail_setting = 0.5
	Game.state.ship.heading = _ship_heading
	# Put the captain on the quarterdeck; he now moves with the ship.
	player.get_parent().remove_child(player)
	_ship_node.add_child(player)
	player.position = Vector3(0, _ship_node._deck_y(0.8) + 0.6, _ship_len * 0.30)
	player.rotation.y = 0.0
	cam_dist = 46.0
	cam_pitch = 16.0
	_hint.text = ""


func _dock_ship() -> void:
	_sailing = false
	Game.state.ship.sail_setting = 0.0
	_ship_node.set_sail_amount(0.06)
	_ship_node.position = ANCHOR_POS
	_ship_node.rotation_degrees = Vector3(0, ANCHOR_ROT_Y, 0)
	# The captain steps back onto the quay.
	_ship_node.remove_child(player)
	add_child(player)
	player.position = Vector3(14, 0.95, 2)
	cam_dist = 15.0
	Game.save_game()


func _sail_tick(delta: float) -> void:
	var ship = Game.state.ship
	var wind: Dictionary = Game.state.wind
	var nav: int = Game.state.character.skill("navigation")

	if Input.is_action_just_pressed("sails_up"):
		ship.sail_setting = clampf(ship.sail_setting + 0.5, 0.0, 1.0)
	if Input.is_action_just_pressed("sails_down"):
		ship.sail_setting = clampf(ship.sail_setting - 0.5, 0.0, 1.0)

	ship.heading = _ship_heading
	var speed: float = Sailing.ship_speed(ship, wind["from"], wind["strength"], nav)
	var turn: float = Sailing.turn_speed(ship, speed, nav)
	if Input.is_action_pressed("turn_left"):
		_ship_heading = wrapf(_ship_heading - turn * delta, 0.0, 360.0)
	if Input.is_action_pressed("turn_right"):
		_ship_heading = wrapf(_ship_heading + turn * delta, 0.0, 360.0)

	var fwd := Vector3(sin(deg_to_rad(_ship_heading)), 0, -cos(deg_to_rad(_ship_heading)))
	_ship_node.position += fwd * speed * SAIL_SPEED_SCALE * delta
	_ship_node.rotation.y = -deg_to_rad(_ship_heading)
	# Keep the ship inside the bay (the quay wall and map edges).
	_ship_node.position.x = clampf(_ship_node.position.x, -400.0, 400.0)
	_ship_node.position.z = clampf(_ship_node.position.z, -700.0, -16.0)
	_ship_node.set_sail_amount(maxf(ship.sail_setting, 0.06))
	_ship_node.set_speed_visual(speed)
	_ship_node.bob(_time, 0.7)
	_ship_node.position.y += -0.8

	# Camera orbits the ship.
	var yr := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var off := Vector3(sin(yr) * cos(pr), sin(pr), cos(yr) * cos(pr)) * maxf(cam_dist, 25.0)
	camera.position = camera.position.lerp(_ship_node.position + Vector3(0, 8, 0) + off, 6.0 * delta)
	camera.look_at(_ship_node.position + Vector3(0, 6, 0))

	# Contextual hints: dock near the quay, or sail out to the open sea.
	# Enter always leaves for the world map, from anywhere in the bay.
	var near_dock: bool = _ship_node.position.distance_to(ANCHOR_POS) < 40.0
	var far_out: bool = _ship_node.position.z < -260.0
	if near_dock:
		_hint.text = "[E]  Dock at the quay   |   [Enter]  Open sea — world map"
		if Input.is_action_just_pressed("interact"):
			_dock_ship()
	elif far_out:
		_hint.text = "[E / Enter]  Set sail for the open sea"
		if Input.is_action_just_pressed("interact"):
			Game.goto_open_sea_from_port()
	else:
		_hint.text = "W/S — sails, A/D — rudder | %.1f kn | [Enter]  Open sea — world map" % speed
	if Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER):
		Game.goto_open_sea_from_port()


# --- Townsfolk ---

## Wandering NPCs: {root, l_leg, r_leg (may be null for skirts), target, speed, phase}
var _npcs: Array = []

const NPC_CLOTHES := [Color("8d3a2e"), Color("6b7d4a"), Color("b0765a"), Color("35405c"), Color("c9a24a"), Color("7d5a7a")]


func _build_npcs() -> void:
	for i in 9:
		var cloth: Color = NPC_CLOTHES[i % NPC_CLOTHES.size()]
		var skin := Color("d9a97a").lerp(Color("8d6a4a"), _rng.randf() * 0.6)
		var skirted := _rng.randf() < 0.45
		var person := Person.build(cloth, skin, skirted, _rng.randi_range(0, 2))
		var npc: Node3D = person["root"]
		add_child(npc)
		npc.position = _npc_spot()
		_npcs.append({
			"root": npc, "l_leg": person["l_leg"], "r_leg": person["r_leg"],
			"l_arm": person["l_arm"], "r_arm": person["r_arm"],
			"target": _npc_spot(), "speed": _rng.randf_range(1.6, 3.0), "phase": _rng.randf() * TAU,
		})


## A random walkable point on the streets, outside building footprints.
func _npc_spot() -> Vector3:
	for attempt in 12:
		var p := Vector3(_rng.randf_range(-55, 55), 0.08, _rng.randf_range(2, 52))
		var p2 := Vector2(p.x, p.z)
		var blocked := false
		for rect: Rect2 in _colliders:
			if rect.grow(0.5).has_point(p2):
				blocked = true
				break
		if not blocked:
			return p
	return Vector3(0, 0.08, 10)


func _process_npcs(delta: float) -> void:
	for n in _npcs:
		var root: Node3D = n["root"]
		var to_target: Vector3 = n["target"] - root.position
		to_target.y = 0.0
		if to_target.length() < 0.5:
			n["target"] = _npc_spot()
			continue
		var step: Vector3 = to_target.normalized() * n["speed"] * delta
		root.position += step
		root.rotation.y = atan2(-step.x, -step.z)
		n["phase"] += delta * 6.0 * n["speed"]
		var swing: float = sin(n["phase"]) * 0.5
		if n["l_leg"] != null:
			n["l_leg"].rotation.x = swing
			n["r_leg"].rotation.x = -swing
		else:
			root.position.y = 0.08 + absf(sin(n["phase"])) * 0.05
		n["l_arm"].rotation.x = -swing * 0.6
		n["r_arm"].rotation.x = swing * 0.6


# --- Player ---

func _build_player() -> void:
	player = Node3D.new()
	add_child(player)
	player.position = Vector3(0, 0.95, 2)

	# Legs (pivot at the hip, mesh hangs down).
	for leg in [["l_leg", -0.13], ["r_leg", 0.13]]:
		var hip := Node3D.new()
		hip.position = Vector3(leg[1], 0.86, 0)
		player.add_child(hip)
		var thigh := MeshInstance3D.new()
		var tc := CylinderMesh.new()
		tc.top_radius = 0.09
		tc.bottom_radius = 0.075
		tc.height = 0.72
		thigh.mesh = tc
		thigh.position = Vector3(0, -0.36, 0)
		thigh.material_override = _mat(Color("3a3226"))
		hip.add_child(thigh)
		var boot := MeshInstance3D.new()
		var bc := BoxMesh.new()
		bc.size = Vector3(0.16, 0.14, 0.3)
		boot.mesh = bc
		boot.position = Vector3(0, -0.79, -0.05)
		boot.material_override = _mat(Color("1d1208"))
		hip.add_child(boot)
		_limbs[leg[0]] = hip

	# Coat (flared), belt, chest.
	var coat := MeshInstance3D.new()
	var cc := CylinderMesh.new()
	cc.top_radius = 0.23
	cc.bottom_radius = 0.33
	cc.height = 0.62
	coat.mesh = cc
	coat.position = Vector3(0, 1.17, 0)
	coat.material_override = _mat(Color("2c3a5c"))
	player.add_child(coat)
	var belt := MeshInstance3D.new()
	var blc := CylinderMesh.new()
	blc.top_radius = 0.25
	blc.bottom_radius = 0.25
	blc.height = 0.09
	belt.mesh = blc
	belt.position = Vector3(0, 0.95, 0)
	belt.material_override = _mat(Color("1d1208"))
	player.add_child(belt)
	var chest := MeshInstance3D.new()
	var chc := BoxMesh.new()
	chc.size = Vector3(0.34, 0.2, 0.2)
	chest.mesh = chc
	chest.position = Vector3(0, 1.52, 0)
	chest.material_override = _mat(Color("2c3a5c"))
	player.add_child(chest)
	# White shirt collar.
	var collar := MeshInstance3D.new()
	var coc := BoxMesh.new()
	coc.size = Vector3(0.16, 0.14, 0.1)
	collar.mesh = coc
	collar.position = Vector3(0, 1.56, -0.12)
	collar.material_override = _mat(Color("f5f1e6"))
	player.add_child(collar)

	# Arms (pivot at the shoulder).
	for arm in [["l_arm", -0.30], ["r_arm", 0.30]]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(arm[1], 1.55, 0)
		player.add_child(shoulder)
		var sleeve := MeshInstance3D.new()
		var sc := CapsuleMesh.new()
		sc.radius = 0.07
		sc.height = 0.62
		sleeve.mesh = sc
		sleeve.position = Vector3(0, -0.26, 0)
		sleeve.material_override = _mat(Color("2c3a5c"))
		shoulder.add_child(sleeve)
		var hand := MeshInstance3D.new()
		var hc := SphereMesh.new()
		hc.radius = 0.06
		hc.height = 0.12
		hand.mesh = hc
		hand.position = Vector3(0, -0.58, 0)
		hand.material_override = _mat(Color("d9a97a"))
		shoulder.add_child(hand)
		_limbs[arm[0]] = shoulder

	# Head, hair, nose, tricorn hat.
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.155
	hm.height = 0.31
	head.mesh = hm
	head.position = Vector3(0, 1.78, 0)
	head.material_override = _mat(Color("d9a97a"))
	player.add_child(head)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.035
	nm.height = 0.07
	nose.mesh = nm
	nose.position = Vector3(0, 1.77, -0.15)
	nose.material_override = _mat(Color("cf9868"))
	player.add_child(nose)
	var hair := MeshInstance3D.new()
	var hrm := SphereMesh.new()
	hrm.radius = 0.16
	hrm.height = 0.28
	hair.mesh = hrm
	hair.position = Vector3(0, 1.83, 0.05)
	hair.material_override = _mat(Color("3a2513"))
	player.add_child(hair)
	var brim := MeshInstance3D.new()
	var brc := CylinderMesh.new()
	brc.top_radius = 0.27
	brc.bottom_radius = 0.27
	brc.height = 0.05
	brim.mesh = brc
	brim.position = Vector3(0, 1.93, 0)
	brim.material_override = _mat(Color("1d1208"))
	player.add_child(brim)
	var crown := MeshInstance3D.new()
	var crc := CylinderMesh.new()
	crc.top_radius = 0.13
	crc.bottom_radius = 0.16
	crc.height = 0.14
	crown.mesh = crc
	crown.position = Vector3(0, 2.02, 0)
	crown.material_override = _mat(Color("1d1208"))
	player.add_child(crown)


var _hud: CanvasLayer
var _status: Label


func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.09, 0.14, 0.8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(12, 10)
	_hud.add_child(panel)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("e8c872"))
	_status.add_theme_font_size_override("font_size", 15)
	var isl := _island()
	_status.text = "%s (%s) | Day %d | %d gold | WASD — walk, E — enter, RMB — camera, Tab — port menu" % [
		isl["name"], World.NATIONS[isl["nation"]]["name"], Game.state.day, Game.state.character.gold]
	panel.add_child(_status)

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
	if _sailing:
		_sail_tick(delta)
		_process_npcs(delta)
		return
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
	_moving = dir != Vector2.ZERO
	if _moving:
		dir = dir.normalized()
		var yr := deg_to_rad(cam_yaw)
		var fwd := Vector3(-sin(yr), 0, -cos(yr))
		var right := Vector3(-fwd.z, 0, fwd.x)
		var motion := (fwd * dir.y + right * dir.x) * WALK_SPEED * delta
		player.position += motion
		if _inside:
			player.position.x = clampf(player.position.x, _room_bounds.position.x, _room_bounds.end.x)
			player.position.z = clampf(player.position.z, _room_bounds.position.y, _room_bounds.end.y)
		else:
			player.position.x = clampf(player.position.x, -70.0, 70.0)
			player.position.z = clampf(player.position.z, -9.0, 80.0)
			_resolve_collisions()
		player.rotation.y = atan2(-motion.x, -motion.z)

	# Snap to the ground: room floor inside, quay top or grass outside.
	var target_y: float
	if _inside:
		target_y = _room_floor_y + 0.08
	else:
		target_y = 0.95 if player.position.z < 1.5 else 0.08
	player.position.y = lerpf(player.position.y, target_y, 12.0 * delta)

	_animate_walk(delta)
	_process_npcs(delta)

	# Ship bobbing at anchor.
	if _ship_node != null:
		_ship_node.bob(_time, 0.7)
		_ship_node.position.y += -0.8

	# Orbit camera around the player (pulled in close indoors).
	var yr2 := deg_to_rad(cam_yaw)
	var pr := deg_to_rad(cam_pitch)
	var eff_dist := minf(cam_dist, 6.5) if _inside else cam_dist
	var off := Vector3(sin(yr2) * cos(pr), sin(pr), cos(yr2) * cos(pr)) * eff_dist
	camera.position = camera.position.lerp(player.position + Vector3(0, 1.6, 0) + off, 10.0 * delta)
	if _inside:
		# Keep the camera inside the room walls.
		camera.position.x = clampf(camera.position.x, _room_bounds.position.x + 0.3, _room_bounds.end.x - 0.3)
		camera.position.z = clampf(camera.position.z, _room_bounds.position.y + 0.3, _room_bounds.end.y - 0.3)
		camera.position.y = clampf(camera.position.y, _room_floor_y + 1.2, _room_floor_y + 3.6)
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


## Push the player out of building footprints (simple AABB resolution).
func _resolve_collisions() -> void:
	var p := Vector2(player.position.x, player.position.z)
	for rect: Rect2 in _colliders:
		if not rect.has_point(p):
			continue
		var left := p.x - rect.position.x
		var right := rect.position.x + rect.size.x - p.x
		var near := p.y - rect.position.y
		var far := rect.position.y + rect.size.y - p.y
		var m := minf(minf(left, right), minf(near, far))
		if m == left:
			p.x = rect.position.x
		elif m == right:
			p.x = rect.position.x + rect.size.x
		elif m == near:
			p.y = rect.position.y
		else:
			p.y = rect.position.y + rect.size.y
	player.position.x = p.x
	player.position.z = p.y


## Swing arms and legs while walking, settle when idle.
func _animate_walk(delta: float) -> void:
	if _moving:
		_walk_phase += delta * 9.0
	var target := sin(_walk_phase) * 0.55 if _moving else 0.0
	for pair in [["l_leg", 1.0], ["r_leg", -1.0], ["l_arm", -0.6], ["r_arm", 0.6]]:
		var pivot: Node3D = _limbs[pair[0]]
		pivot.rotation.x = lerpf(pivot.rotation.x, target * pair[1], 14.0 * delta)
