## A sailing ship: hull, rig and sails are Poly Haven's CC0 period ship
## models (prepared by tools/blender/import_ships.py), one per size band and
## scaled to the class. This script adds the living parts — deck crew, wake
## foam, broadside smoke, furling sails, sails and flags in the nation's
## colors — and exposes the deck measurements crew and boarders rely on.
extends Node3D

const Person := preload("res://scripts/person.gd")
const ShipTypes := preload("res://core/ship_types.gd")

## Which model carries each class.
const MODEL := {
	"tartane": "dutch_ship_medium", "lugger": "dutch_ship_medium",
	"sloop": "dutch_ship_medium", "schooner": "dutch_ship_medium",
	"barque": "dutch_ship_large_02", "brig": "dutch_ship_large_02",
	"corvette": "dutch_ship_large_02",
	"galleon": "dutch_ship_large_01", "frigate": "dutch_ship_large_01",
	"battleship": "ship_pinnace", "manowar": "ship_pinnace",
}
## Sailcloth tint per nation (multiplies the weathered canvas texture).
const SAIL_TINT := {
	"england": Color(1, 0.98, 0.94), "france": Color(0.42, 0.5, 0.78),
	"spain": Color(1, 0.96, 0.88), "holland": Color(1, 0.9, 0.78),
	"pirates": Color(0.36, 0.33, 0.31),
}

var length := 30.0
var flag_color := Color("c62828")
var type_id := ""
## Nation id ("england", "france", ...): picks sail tint and ensign.
var nation := ""

var _sails: Array = []   # sail nodes scaled along local Y to furl/unfurl
var _flags: Array = []   # flag & pennant nodes that flutter
var _crew: Array = []    # wandering deck sailors: {node, target, speed}
var _wake: MeshInstance3D
var _wake_mat: StandardMaterial3D
var _root: Node3D
var _beam: float
var _scale := 1.0
var _deck_samples: Array = []
var _half_samples: Array = []
## Muzzle positions per side (-1 port, 1 starboard) for volley smoke.
var _gun_ports := {-1: [], 1: []}

static var _profiles := {}


func build(p_length: float, p_flag: Color, with_crew := true, p_type := "", p_nation := "") -> void:
	length = p_length
	flag_color = p_flag
	nation = p_nation
	type_id = p_type if MODEL.has(p_type) else _type_for_length(p_length)
	_root = Node3D.new()
	add_child(_root)
	_load_model()
	if with_crew:
		_build_crew()
	_build_wake()


## The length (m) a class is shown at in battle, harbor and boarding.
static func class_length(p_type: String) -> float:
	var rank := int(ShipTypes.TYPES[p_type]["rank"]) if ShipTypes.TYPES.has(p_type) else 5
	return 20.0 + (8 - rank) * 3.0


## Unknown/legacy callers: infer something sensible from the size.
func _type_for_length(l: float) -> String:
	if l < 26.0:
		return "sloop"
	return "brig" if l < 34.0 else "frigate"


static func _profile(model_id: String) -> Dictionary:
	if not _profiles.has(model_id):
		var f := FileAccess.open("res://assets/ships/%s.json" % model_id, FileAccess.READ)
		_profiles[model_id] = JSON.parse_string(f.get_as_text())
	return _profiles[model_id]


func _load_model() -> void:
	var model_id: String = MODEL[type_id]
	var prof := _profile(model_id)
	_scale = length / float(prof["length"])
	_deck_samples = prof["deck"]
	_half_samples = prof["half"]
	var widest := 0.0
	for w in _half_samples:
		widest = maxf(widest, float(w))
	_beam = widest * 2.0 * _scale

	var model: Node3D = load("res://assets/ships/%s.gltf" % model_id).instantiate()
	model.scale = Vector3.ONE * _scale
	_root.add_child(model)
	var flag_mat := _flat_material(flag_color)
	var flag_path := "res://assets/ships/nations/%s_flag.jpg" % nation
	if nation != "" and ResourceLoader.exists(flag_path):
		flag_mat = _cloth_material(load(flag_path))
	var tint: Color = SAIL_TINT.get(nation, Color.WHITE)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var n := String(mi.name)
		if n.begins_with("Sail"):
			_sails.append(mi)
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			if src != null:
				var m: BaseMaterial3D = src.duplicate()
				m.albedo_color = tint
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				# Canvas lets the sun through: sails glow instead of going black
				# when the light is behind them.
				m.backlight_enabled = true
				m.backlight = tint.darkened(0.25)
				mi.material_override = m
		elif n.begins_with("Flag") or n.begins_with("Pennant"):
			mi.material_override = flag_mat
			_flags.append(mi)
	_place_guns()


## Broadside smoke comes from a row of ports along each side.
func _place_guns() -> void:
	var n := clampi(int(length / 3.5), 4, 14)
	for side in [-1, 1]:
		for i in n:
			var t := 0.2 + (float(i) + 0.5) / n * 0.6
			var z := -length / 2.0 + t * length
			var y := maxf(_deck_y(t) - 1.0 * _scale, 0.8)
			_gun_ports[side].append(Vector3(side * (_half_width(t) + 0.6), y, z))


# --- Deck measurements, sampled from the model ---

func _sample(arr: Array, t: float) -> float:
	var f := clampf(t, 0.0, 1.0) * (arr.size() - 1)
	var i := mini(int(f), arr.size() - 2)
	return lerpf(float(arr[i]), float(arr[i + 1]), f - i) * _scale


## Half-width of the hull at deck level, t: 0 = bow, 1 = stern.
func _half_width(t: float) -> float:
	return _sample(_half_samples, t)


## Height of the deck you'd stand on, t: 0 = bow, 1 = stern.
func _deck_y(t: float) -> float:
	return _sample(_deck_samples, t)


## Sailors wandering the deck (animated in _process).
func _build_crew() -> void:
	var count := clampi(3 + int(length / 8.0), 4, 10)
	for i in count:
		var p := Person.build(Color.WHITE, Person.SKIN_DEFAULT, false, 3, false, "sailor")
		var sailor: Node3D = p["root"]
		_root.add_child(sailor)
		sailor.position = _crew_spot()
		_crew.append({"node": sailor, "target": _crew_spot(), "speed": randf_range(1.0, 2.0),
			"limbs": p, "phase": randf() * TAU})
	set_process(true)


func _crew_spot() -> Vector3:
	var t := randf_range(0.22, 0.70)
	var z := -length / 2.0 + t * length
	var x := randf_range(-1.0, 1.0) * _half_width(t) * 0.55
	return Vector3(x, _deck_y(t) + 0.05, z)


func _process(delta: float) -> void:
	for s in _crew:
		var node: Node3D = s["node"]
		var target: Vector3 = s["target"]
		var to_target := target - node.position
		if to_target.length() < 0.3:
			s["target"] = _crew_spot()
			continue
		var step: Vector3 = to_target.normalized() * s["speed"] * delta
		node.position += step
		node.rotation.y = atan2(-step.x, -step.z)
		s["phase"] += delta * 6.0 * s["speed"]
		var swing := sin(s["phase"]) * 0.5
		var limbs: Dictionary = s["limbs"]
		limbs["l_leg"].rotation.x = swing
		limbs["r_leg"].rotation.x = -swing
		limbs["l_arm"].rotation.x = -swing * 0.6
		limbs["r_arm"].rotation.x = swing * 0.6


## Double-sided sailcloth/flag material from a nation texture.
func _cloth_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = 0.95
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat_material(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --- Wake ---

func _build_wake() -> void:
	_wake = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(_beam * 0.9, length * 1.1)
	_wake.mesh = pm
	_wake.position = Vector3(0, 0.15, length * 0.95)
	_wake_mat = StandardMaterial3D.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.55))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.12)
	gtex.fill_to = Vector2(0.5, 1.0)
	_wake_mat.albedo_texture = gtex
	_wake_mat.albedo_color = Color(1, 1, 1, 0.0)
	_wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wake.material_override = _wake_mat
	_root.add_child(_wake)


## Wake foam grows with speed.
func set_speed_visual(speed: float) -> void:
	if _wake_mat == null:
		return
	var k := clampf(speed / 12.0, 0.0, 1.0)
	_wake_mat.albedo_color = Color(1, 1, 1, k * 0.35)
	_wake.scale = Vector3(1.0, 1.0, 0.5 + k * 0.9)


# --- Broadside FX ---

## A ragged volley: muzzle flash + drifting smoke at every gun of `side`.
func fire_broadside_fx(side: int) -> void:
	for p in _gun_ports.get(side, []):
		_muzzle_smoke(p, float(side))


func _muzzle_smoke(local_pos: Vector3, side: float) -> void:
	var delay := randf() * 0.22
	# Flash.
	var flash := MeshInstance3D.new()
	var fmesh := SphereMesh.new()
	fmesh.radius = 0.45
	fmesh.height = 0.9
	flash.mesh = fmesh
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(1.0, 0.75, 0.3)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.6, 0.15)
	fmat.emission_energy_multiplier = 4.0
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = fmat
	flash.position = local_pos
	flash.visible = false
	_root.add_child(flash)
	var ft := flash.create_tween()
	ft.tween_interval(delay)
	ft.tween_callback(func(): flash.visible = true)
	ft.tween_property(flash, "transparency", 1.0, 0.15)
	ft.tween_callback(flash.queue_free)
	# Smoke cloud rolling out to the side.
	var puff := MeshInstance3D.new()
	var smesh := SphereMesh.new()
	smesh.radius = 0.8
	smesh.height = 1.6
	puff.mesh = smesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.93, 0.93, 0.9, 0.85)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.roughness = 1.0
	puff.material_override = smat
	puff.position = local_pos
	puff.scale = Vector3(0.4, 0.4, 0.4)
	puff.visible = false
	_root.add_child(puff)
	var tw := puff.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func(): puff.visible = true)
	tw.tween_property(puff, "position",
		local_pos + Vector3(side * randf_range(3.0, 4.5), randf_range(0.6, 1.4), randf_range(-0.6, 0.6)), 1.2)
	tw.parallel().tween_property(puff, "scale", Vector3(3.4, 3.4, 3.4), 1.2)
	tw.parallel().tween_property(puff, "transparency", 1.0, 1.2)
	tw.tween_callback(puff.queue_free)


# --- Animation hooks ---

## Sails visually furl at 0 and unfurl at 1 (pivots sit at yards/heads).
func set_sail_amount(frac: float) -> void:
	frac = clampf(frac, 0.06, 1.0)
	for pivot in _sails:
		# Squash the belly too, so a furled sail is a tight roll on its spar.
		pivot.scale = Vector3(1, frac, frac)


## Gentle bobbing on the waves; the flag flutters.
func bob(time: float, phase: float) -> void:
	position.y = sin(time * 1.1 + phase) * 0.35 + 0.1
	rotation.x = sin(time * 0.9 + phase) * 0.02
	rotation.z = cos(time * 0.7 + phase) * 0.035
	for f in _flags:
		f.rotation.y = sin(time * 3.0 + phase) * 0.25
