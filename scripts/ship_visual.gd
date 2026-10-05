## A sailing ship: the hull, rig and sails come from a GLB model built in
## Blender by tools/blender/build_ships.py (one per ship class, all modeled
## at MODEL_LENGTH and scaled here). This script adds the living parts —
## deck crew, wake foam, broadside smoke, furling sails and a fluttering
## flag in the nation's colors — and exposes the deck measurements that
## crew placement and boarding rely on.
extends Node3D

const Person := preload("res://scripts/person.gd")

## Every model is built at this length (metres) — see build_ships.py.
const MODEL_LENGTH := 30.0
## Rows of gunports per class: beamier, deeper hulls carry more decks.
const GUN_ROWS := {
	"tartane": 0, "lugger": 1, "sloop": 1, "schooner": 1, "barque": 1, "brig": 1,
	"galleon": 2, "corvette": 1, "frigate": 2, "battleship": 2, "manowar": 3,
}

var length := 30.0
var flag_color := Color("c62828")
var type_id := ""
## Nation id ("england", "france", ...): picks sailcloth, heraldry and flag.
var nation := ""

var _sails: Array = []   # sail nodes scaled along local Y to furl/unfurl
var _flags: Array = []   # flag & pennant nodes that flutter
var _crew: Array = []    # wandering deck sailors: {node, target, speed}
var _wake: MeshInstance3D
var _wake_mat: StandardMaterial3D
var _root: Node3D
var _beam: float
var _depth: float
var _gun_rows := 1
## Muzzle positions per side (-1 port, 1 starboard) for volley smoke.
var _gun_ports := {-1: [], 1: []}


func build(p_length: float, p_flag: Color, with_crew := true, p_type := "", p_nation := "") -> void:
	length = p_length
	flag_color = p_flag
	nation = p_nation
	type_id = p_type if GUN_ROWS.has(p_type) else _type_for_length(p_length)
	_gun_rows = GUN_ROWS[type_id]
	_root = Node3D.new()
	add_child(_root)
	# Heavier classes are beamier and deeper: a man-of-war is a wall of oak.
	_beam = length * (0.26 + 0.014 * _gun_rows)
	_depth = length * (0.115 + 0.020 * maxi(_gun_rows - 1, 0))
	_load_model()
	if with_crew:
		_build_crew()
	_build_wake()


## Unknown/legacy callers: infer something sensible from the size.
func _type_for_length(l: float) -> String:
	if l < 26.0:
		return "sloop"
	return "brig" if l < 34.0 else "frigate"


func _load_model() -> void:
	var scene: PackedScene = load("res://assets/ships/%s.gltf" % type_id)
	var model: Node3D = scene.instantiate()
	model.scale = Vector3.ONE * (length / MODEL_LENGTH)
	_root.add_child(model)
	var flag_mat := _flat_material(flag_color)
	var sail_mat: Material = null
	var emblem_mat: Material = null
	var dir := "res://assets/ships/nations/"
	if nation != "" and ResourceLoader.exists(dir + nation + "_sail.jpg"):
		sail_mat = _cloth_material(load(dir + nation + "_sail.jpg"))
		emblem_mat = _cloth_material(load(dir + nation + "_sail_emblem.jpg"))
		flag_mat = _cloth_material(load(dir + nation + "_flag.jpg"))
	for node in model.find_children("*", "Node3D", true, false):
		var n := String(node.name)
		if n == "Hull":
			# Ambient occlusion is baked into the hull's vertex colors.
			var mesh: Mesh = (node as MeshInstance3D).mesh
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				if m != null:
					m.vertex_color_use_as_albedo = true
		elif n.begins_with("Sail"):
			_sails.append(node)
			# Sails ending in "_E" carry the nation's coat of arms.
			if sail_mat != null:
				(node as MeshInstance3D).material_override = emblem_mat if n.ends_with("_E") else sail_mat
		elif n.begins_with("Flag") or n.begins_with("Pennant"):
			(node as MeshInstance3D).material_override = flag_mat
			_flags.append(node)
		elif n.begins_with("Muzzle"):
			var p := _model_space(node, model)
			_gun_ports[1 if p.x > 0.0 else -1].append(p)


## Position of `node` in _root space (the model is scaled inside _root).
func _model_space(node: Node3D, model: Node3D) -> Vector3:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != model:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return (model.transform * xf).origin


# --- Deck measurements (keep in sync with build_ships.py) ---

## Half-width along the hull, t: 0 = bow, 1 = stern.
func _half_width(t: float) -> float:
	var w: float
	if t < 0.36:
		w = 1.0 - pow(1.0 - t / 0.36, 2.4)
	elif t < 0.70:
		w = 1.0
	else:
		w = 1.0 - 0.38 * smoothstep(0.70, 1.0, t)
	return _beam * 0.5 * maxf(w, 0.035)


## Deck sheer line — rises toward bow and stern.
func _deck_y(t: float) -> float:
	return _depth * (0.70 + 0.5 * pow(absf(t - 0.42) / 0.58, 1.8))


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
		pivot.scale = Vector3(1, frac, 1)


## Gentle bobbing on the waves; the flag flutters.
func bob(time: float, phase: float) -> void:
	position.y = sin(time * 1.1 + phase) * 0.35 + 0.1
	rotation.x = sin(time * 0.9 + phase) * 0.02
	rotation.z = cos(time * 0.7 + phase) * 0.035
	for f in _flags:
		f.rotation.y = sin(time * 3.0 + phase) * 0.25
