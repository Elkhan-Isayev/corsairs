## Procedural square-rigger modeled after early-1600s ships: smooth rounded
## hull with tumblehome, ochre gun strakes, quarterdeck and forecastle,
## three sail tiers, jibs, a gaff spanker, shrouds with ratlines, cannons,
## stern lanterns. No external assets — everything is generated.
extends Node3D

const COLOR_BOTTOM := Color("1d1208")
const COLOR_LOWER := Color("3a2513")
const COLOR_UPPER := Color("2a1a0c")
const COLOR_STRAKE := Color("b5893b")
const COLOR_TRIM := Color("caa14e")
const COLOR_DECK := Color("9a7947")
const COLOR_MAST := Color("4a3520")
const COLOR_ROPE := Color("2a2015")
const COLOR_SAIL := Color("d6cdb2")

var length := 30.0
var flag_color := Color("c62828")
var type_id := ""

var _sails: Array = []   # pivots scaled to furl/unfurl
var _crew: Array = []    # wandering deck sailors: {node, target, speed}
var _flag: MeshInstance3D
var _wake: MeshInstance3D
var _wake_mat: StandardMaterial3D
var _root: Node3D
var _beam: float
var _depth: float

var _wood_mat: StandardMaterial3D
var _sail_mat: StandardMaterial3D
## Muzzle positions per side (-1 port, 1 starboard) for volley smoke.
var _gun_ports := {-1: [], 1: []}

## Rig & hull profile per ship class: mast count, rows of gunports,
## square-sail tiers per mast, stern castle stages, lateen rig for the
## small Mediterranean hulls.
const PROFILES := {
	"tartane":    {"masts": 1, "rows": 0, "tiers": 0, "castle": 0, "lateen": true},
	"lugger":     {"masts": 2, "rows": 1, "tiers": 0, "castle": 0, "lateen": true},
	"sloop":      {"masts": 2, "rows": 1, "tiers": 2, "castle": 0, "lateen": false},
	"schooner":   {"masts": 2, "rows": 1, "tiers": 2, "castle": 0, "lateen": false},
	"barque":     {"masts": 3, "rows": 1, "tiers": 2, "castle": 1, "lateen": false},
	"brig":       {"masts": 2, "rows": 1, "tiers": 3, "castle": 1, "lateen": false},
	"galleon":    {"masts": 3, "rows": 2, "tiers": 3, "castle": 2, "lateen": false},
	"corvette":   {"masts": 3, "rows": 1, "tiers": 3, "castle": 1, "lateen": false},
	"frigate":    {"masts": 3, "rows": 2, "tiers": 3, "castle": 1, "lateen": false},
	"battleship": {"masts": 3, "rows": 2, "tiers": 4, "castle": 2, "lateen": false},
	"manowar":    {"masts": 3, "rows": 3, "tiers": 4, "castle": 2, "lateen": false},
}

var _masts_n := 2
var _gun_rows := 1
var _tiers_n := 3
var _castle := 1
var _lateen := false


func build(p_length: float, p_flag: Color, with_crew := true, p_type := "") -> void:
	length = p_length
	flag_color = p_flag
	type_id = p_type
	var prof: Dictionary = _profile_for(p_type)
	_masts_n = int(prof["masts"])
	_gun_rows = int(prof["rows"])
	_tiers_n = int(prof["tiers"])
	_castle = int(prof["castle"])
	_lateen = bool(prof["lateen"])
	_root = Node3D.new()
	add_child(_root)
	# Heavier classes are beamier and deeper: a man-of-war is a wall of oak.
	_beam = length * (0.26 + 0.014 * _gun_rows)
	_depth = length * (0.115 + 0.020 * maxi(_gun_rows - 1, 0))
	_make_shared_materials()

	_build_hull()
	_build_bulwark_and_strakes()
	_build_decks_and_stern()
	_build_cannons()
	_build_deck_guns()
	_build_masts()
	_build_bowsprit_and_jibs()
	if with_crew:
		_build_crew()
	_build_wake()


func _profile_for(p_type: String) -> Dictionary:
	if PROFILES.has(p_type):
		return PROFILES[p_type]
	# Unknown/legacy callers: infer something sensible from the size.
	if length < 26.0:
		return PROFILES["sloop"]
	return PROFILES["brig"] if length < 34.0 else PROFILES["frigate"]


func _make_shared_materials() -> void:
	# Subtle triplanar noise = wood grain without any texture assets.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.8, 0.76, 0.7))
	ramp.set_color(1, Color(1, 1, 1))
	var ntex := NoiseTexture2D.new()
	ntex.noise = noise
	ntex.color_ramp = ramp
	ntex.width = 128
	ntex.height = 128
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.vertex_color_use_as_albedo = true
	_wood_mat.albedo_texture = ntex
	_wood_mat.uv1_triplanar = true
	_wood_mat.uv1_scale = Vector3(3, 3, 3)
	_wood_mat.roughness = 0.85
	# Hand-built hull quads have mixed winding — never cull them.
	_wood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_sail_mat = StandardMaterial3D.new()
	_sail_mat.albedo_color = COLOR_SAIL
	_sail_mat.albedo_texture = ntex
	_sail_mat.uv1_triplanar = true
	_sail_mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	_sail_mat.roughness = 1.0
	_sail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


# --- Hull ---

## Half-width along the hull, t: 0 = bow, 1 = stern.
func _half_width(t: float) -> float:
	var w: float
	if t < 0.38:
		w = lerpf(0.03, 1.0, smoothstep(0.0, 0.38, t))
	elif t < 0.72:
		w = 1.0
	else:
		w = lerpf(1.0, 0.58, smoothstep(0.72, 1.0, t))
	return _beam * 0.5 * w


## Deck sheer line — rises toward bow and stern.
func _deck_y(t: float) -> float:
	return _depth * (0.70 + 0.5 * pow(absf(t - 0.42) / 0.58, 1.8))


func _bottom_y(t: float) -> float:
	# Deep keel: most of the hull below y=0 stays under the waterline,
	# so ships never look like they hover over the sea.
	var rise := smoothstep(0.12, 0.0, t) * 0.5 + smoothstep(0.86, 1.0, t) * 0.45
	return -_depth * 0.85 + _depth * rise * 0.4


## Hull cross-section rows: [x multiplier, y fraction bottom→deck].
const ROWS := [
	[0.0, 0.0],
	[0.62, 0.16],
	[0.95, 0.42],
	[1.0, 0.72],
	[0.92, 1.0],
]


func _row_color(r: int) -> Color:
	match r:
		0: return COLOR_BOTTOM
		1: return COLOR_BOTTOM
		2: return COLOR_LOWER
		_: return COLOR_UPPER


func _station(t: float, z: float, side: float, r: int) -> Vector3:
	var w := _half_width(t)
	var yb := _bottom_y(t)
	var yd := _deck_y(t)
	var row: Array = ROWS[r]
	# Raked transom: the upper stern leans aft, like a real counter-stern.
	var rake: float = row[1] * length * 0.045 * smoothstep(0.88, 1.0, t)
	return Vector3(side * w * row[0], yb + (yd - yb) * row[1], z + rake)


func _build_hull() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var steps := 22
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var z0 := -length / 2.0 + t0 * length
		var z1 := -length / 2.0 + t1 * length
		for side in [-1.0, 1.0]:
			for r in ROWS.size() - 1:
				var col := _row_color(r)
				_quad(st,
					_station(t0, z0, side, r), _station(t0, z0, side, r + 1),
					_station(t1, z1, side, r + 1), _station(t1, z1, side, r),
					col, side > 0.0)
		# Deck surface.
		var d0l := _station(t0, z0, -1.0, ROWS.size() - 1)
		var d0r := _station(t0, z0, 1.0, ROWS.size() - 1)
		var d1l := _station(t1, z1, -1.0, ROWS.size() - 1)
		var d1r := _station(t1, z1, 1.0, ROWS.size() - 1)
		_quad(st, d0r, d0l, d1l, d1r, COLOR_DECK, false)
	# Transom.
	var zt := length / 2.0
	for r in ROWS.size() - 1:
		_quad(st,
			_station(1.0, zt, -1.0, r), _station(1.0, zt, 1.0, r),
			_station(1.0, zt, 1.0, r + 1), _station(1.0, zt, -1.0, r + 1),
			COLOR_UPPER if r >= 2 else COLOR_BOTTOM, false)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _wood_mat
	_root.add_child(mi)

	# Curved stem: a clipper-style sweep from the waterline up and forward
	# to the figurehead — no straight-post bow.
	var p0 := Vector3(0, -_depth * 0.15, -length * 0.487)
	var p1 := Vector3(0, _depth * 0.55, -length * 0.552)   # curve control
	var p2 := Vector3(0, _depth * 1.30, -length * 0.560)
	var prev := p0
	var segs := 5
	for i in range(1, segs + 1):
		var f := float(i) / segs
		var pt := p0.lerp(p1, f).lerp(p1.lerp(p2, f), f)  # quadratic bezier
		var r := lerpf(0.30, 0.15, f)
		_root.add_child(_spar(prev, pt, r, COLOR_UPPER))
		prev = pt
	var mesh_s := SphereMesh.new()
	mesh_s.radius = 0.30
	mesh_s.height = 0.60
	var fig := MeshInstance3D.new()
	fig.mesh = mesh_s
	fig.position = p2
	fig.material_override = _flat_material(COLOR_TRIM)
	_root.add_child(fig)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip: bool) -> void:
	var order := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for v in order:
		st.set_color(col)
		st.add_vertex(v)


## Bulwark wall above the deck plus ochre strakes along the gunport band.
func _build_bulwark_and_strakes() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 22
	var bh := length * 0.028
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var z0 := -length / 2.0 + t0 * length
		var z1 := -length / 2.0 + t1 * length
		for side in [-1.0, 1.0]:
			var a := _station(t0, z0, side, ROWS.size() - 1)
			var d := _station(t1, z1, side, ROWS.size() - 1)
			var b := a + Vector3(0, bh, 0)
			var c := d + Vector3(0, bh, 0)
			_quad(st, a, b, c, d, COLOR_UPPER, side > 0.0)
			_quad(st, a, b, c, d, COLOR_UPPER, side < 0.0)  # inner face too
			# Cap rail.
			_quad(st, b, b + Vector3(side * -0.3, 0.1, 0), c + Vector3(side * -0.3, 0.1, 0), c, COLOR_TRIM, side > 0.0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _wood_mat
	_root.add_child(mi)

	# An ochre strake framing every gun deck (plus one at the rail).
	var strake_fracs: Array = [0.86]
	for row_frac: float in _gun_row_fracs():
		strake_fracs.append(row_frac + 0.085)
	for frac: float in strake_fracs:
		var strip := SurfaceTool.new()
		strip.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var z0 := -length / 2.0 + t0 * length
			var z1 := -length / 2.0 + t1 * length
			for side in [-1.0, 1.0]:
				var w0 := _half_width(t0) * 1.005
				var w1 := _half_width(t1) * 1.005
				var y0 := _bottom_y(t0) + (_deck_y(t0) - _bottom_y(t0)) * frac
				var y1 := _bottom_y(t1) + (_deck_y(t1) - _bottom_y(t1)) * frac
				var h := length * 0.008
				_quad(strip,
					Vector3(side * w0, y0 - h, z0), Vector3(side * w0, y0 + h, z0),
					Vector3(side * w1, y1 + h, z1), Vector3(side * w1, y1 - h, z1),
					COLOR_STRAKE, side > 0.0)
		strip.generate_normals()
		var smi := MeshInstance3D.new()
		smi.mesh = strip.commit()
		smi.material_override = _flat_material(COLOR_STRAKE)
		_root.add_child(smi)


## A superstructure lofted along the hull: walls follow the plan shape and
## lean inboard (tumblehome), so bow and stern never read as boxes.
func _castle_loft(t0: float, t1: float, y0: float, h: float, w_mult: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var steps := 8
	var lean := 0.86
	for i in steps:
		var ta := lerpf(t0, t1, float(i) / steps)
		var tb := lerpf(t0, t1, float(i + 1) / steps)
		var za := -length / 2.0 + ta * length
		var zb := -length / 2.0 + tb * length
		var base_a := _deck_y(ta) + y0
		var base_b := _deck_y(tb) + y0
		var wa := _half_width(ta) * w_mult
		var wb := _half_width(tb) * w_mult
		for side in [-1.0, 1.0]:
			_quad(st,
				Vector3(side * wa, base_a, za), Vector3(side * wa * lean, base_a + h, za),
				Vector3(side * wb * lean, base_b + h, zb), Vector3(side * wb, base_b, zb),
				COLOR_UPPER, side > 0.0)
		# Roof deck.
		_quad(st,
			Vector3(wa * lean, base_a + h, za), Vector3(-wa * lean, base_a + h, za),
			Vector3(-wb * lean, base_b + h, zb), Vector3(wb * lean, base_b + h, zb),
			COLOR_DECK, false)
	# End walls.
	for tt: float in [t0, t1]:
		var z := -length / 2.0 + tt * length
		var base := _deck_y(tt) + y0
		var w := _half_width(tt) * w_mult
		_quad(st,
			Vector3(-w, base, z), Vector3(-w * lean, base + h, z),
			Vector3(w * lean, base + h, z), Vector3(w, base, z),
			COLOR_UPPER, false)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _wood_mat
	_root.add_child(mi)


func _build_decks_and_stern() -> void:
	# Stern castle and forecastle follow the hull's own curves.
	var qd_h := _depth * (0.28 + 0.22 * _castle)
	_castle_loft(0.70, 1.0, 0.0, qd_h, 0.97)
	var pd_h := 0.0
	if _castle >= 2:
		# Poop deck: the second step of a galleon's stern castle.
		pd_h = _depth * 0.32
		_castle_loft(0.84, 1.0, qd_h, pd_h, 0.90)
	if _castle >= 1:
		var fc_h := _depth * 0.35
		_castle_loft(0.02, 0.17, 0.0, fc_h, 0.92)

	# Stern: window bands (one per gun deck), gold mouldings, galleries.
	var top_y := _deck_y(1.0) + qd_h + pd_h
	var bands := clampi(_gun_rows, 1, 2) + (1 if _castle >= 2 else 0)
	for b in bands:
		var band_y := top_y - _depth * (0.30 + 0.34 * b)
		_box(Vector3(_beam * (0.60 - 0.06 * b), _depth * 0.22, 0.16), Vector3(0, band_y, length * 0.505), Color("14100a"))
		_box(Vector3(_beam * 0.66, _depth * 0.05, 0.2), Vector3(0, band_y + _depth * 0.15, length * 0.505), COLOR_TRIM)
	for side in [-1.0, 1.0]:
		_box(Vector3(_beam * 0.10, _depth * (0.4 + 0.25 * _castle), length * 0.10), Vector3(side * _beam * 0.40, top_y - _depth * 0.35, length * 0.44), COLOR_UPPER, _wood_mat)
		# Lantern: warm emissive sphere on a post.
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(1.0, 0.85, 0.5)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.72, 0.3)
		lm.emission_energy_multiplier = 2.0
		var lantern := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		lantern.mesh = sm
		lantern.position = Vector3(side * _beam * 0.34, top_y + 0.75, length * 0.50)
		lantern.material_override = lm
		_root.add_child(lantern)
		_cylinder(0.05, 0.05, 0.7, Vector3(side * _beam * 0.34, top_y + 0.3, length * 0.50), COLOR_MAST)
	if _castle >= 2:
		# The great center lantern of a first-rate.
		var lm2 := StandardMaterial3D.new()
		lm2.albedo_color = Color(1.0, 0.85, 0.5)
		lm2.emission_enabled = true
		lm2.emission = Color(1.0, 0.72, 0.3)
		lm2.emission_energy_multiplier = 2.0
		var big := MeshInstance3D.new()
		var bs := SphereMesh.new()
		bs.radius = 0.38
		bs.height = 0.76
		big.mesh = bs
		big.position = Vector3(0, top_y + 1.05, length * 0.505)
		big.material_override = lm2
		_root.add_child(big)
		_cylinder(0.06, 0.06, 0.9, Vector3(0, top_y + 0.45, length * 0.505), COLOR_MAST)


## Height (0..1 between keel and deck) of every gunport row.
func _gun_row_fracs() -> Array:
	# All rows sit clear of the waterline (the keel reaches -0.85 depth).
	match _gun_rows:
		0: return []
		1: return [0.76]
		2: return [0.64, 0.80]
		_: return [0.60, 0.72, 0.84]


func _build_cannons() -> void:
	var n := clampi(int(length / 6.0), 3, 10)
	var fracs: Array = _gun_row_fracs()
	for row in fracs.size():
		var frac: float = fracs[row]
		# Lower decks carry more, heavier guns; stagger rows like the real thing.
		var stagger: float = 0.5 * float(row % 2) / n
		for side in [-1.0, 1.0]:
			for i in n:
				var t := 0.26 + (float(i) / n + stagger) * 0.50
				var z := -length / 2.0 + t * length
				var x := _half_width(t)
				var y := _bottom_y(t) + (_deck_y(t) - _bottom_y(t)) * frac
				# Port lid frame, dark port, barrel poking out.
				var port_s := length * 0.030
				_box(Vector3(0.12, port_s * 1.25, port_s * 1.25), Vector3(side * x * 1.0, y, z), Color("6d4a26"))
				_box(Vector3(0.16, port_s, port_s), Vector3(side * x * 1.01, y, z), Color("0d0905"))
				var barrel := _cylinder(0.09, 0.11, 0.9, Vector3(side * (x + 0.35), y - 0.05, z), Color("15130f"))
				barrel.rotation_degrees = Vector3(0, 0, 90)
				_gun_ports[int(side)].append(Vector3(side * (x + 0.9), y, z))


## Carriage guns standing on the open deck, barrels out over the rail.
func _build_deck_guns() -> void:
	var n := clampi(int(length / 8.0), 2, 5)
	for side in [-1.0, 1.0]:
		for i in n:
			var t := 0.34 + float(i) / n * 0.34
			var z := -length / 2.0 + t * length
			var deck := _deck_y(t)
			var x: float = _half_width(t) * 0.66 * side
			# Carriage.
			_box(Vector3(0.6, 0.35, 0.9), Vector3(x, deck + 0.30, z), Color("4a2e15"))
			# Wheels.
			for dz in [-0.3, 0.3]:
				var wheel := _cylinder(0.16, 0.16, 0.12, Vector3(x, deck + 0.16, z + dz), Color("2a1a0c"))
				wheel.rotation_degrees = Vector3(0, 0, 90)
			# Barrel pointing out over the side.
			var barrel := _cylinder(0.10, 0.14, 1.5, Vector3(x + side * 0.55, deck + 0.55, z), Color("15130f"))
			barrel.rotation_degrees = Vector3(0, 0, side * 80.0)
			_gun_ports[int(side)].append(Vector3(x + side * 1.4, deck + 0.6, z))


## Little sailors wandering the deck (animated in _process).
func _build_crew() -> void:
	var count := clampi(3 + int(length / 8.0), 4, 10)
	var shirt_colors := [Color("e8e2d0"), Color("8d3a2e"), Color("35405c"), Color("6b7d4a")]
	for i in count:
		var sailor := Node3D.new()
		_root.add_child(sailor)
		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.20
		cm.height = 1.0
		body.mesh = cm
		body.position = Vector3(0, 0.5, 0)
		body.material_override = _flat_material(shirt_colors[i % shirt_colors.size()])
		sailor.add_child(body)
		var head := MeshInstance3D.new()
		var hm := SphereMesh.new()
		hm.radius = 0.16
		hm.height = 0.32
		head.mesh = hm
		head.position = Vector3(0, 1.15, 0)
		head.material_override = _flat_material(Color("d9a97a"))
		sailor.add_child(head)
		var spot := _crew_spot()
		sailor.position = spot
		_crew.append({"node": sailor, "target": _crew_spot(), "speed": randf_range(1.0, 2.0)})
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


# --- Masts, sails, rigging ---

func _mast_positions() -> Array:
	# [t along hull, height multiplier, has_course_sail]
	match _masts_n:
		1:
			return [[0.42, 1.0, true]]
		2:
			return [[0.24, 0.92, true], [0.60, 1.0, true]]
		_:
			return [[0.18, 0.94, true], [0.48, 1.05, true], [0.78, 0.78, false]]


## Square-sail tiers bottom-up: [y fraction, width multiplier, sail height fraction].
func _sail_tiers() -> Array:
	match _tiers_n:
		2:
			return [[0.40, 1.0, 0.26], [0.70, 0.76, 0.18]]
		4:
			return [[0.36, 1.0, 0.24], [0.60, 0.84, 0.18], [0.78, 0.66, 0.14], [0.92, 0.48, 0.10]]
		_:
			return [[0.40, 1.0, 0.26], [0.68, 0.82, 0.20], [0.88, 0.60, 0.14]]


func _build_masts() -> void:
	var masts := _mast_positions()
	var main_h := 0.0
	var main_z := 0.0
	for m in range(masts.size()):
		var t: float = masts[m][0]
		var h: float = length * 0.92 * masts[m][1]
		var z := -length / 2.0 + t * length
		var deck := _deck_y(t)
		if m == mini(1, masts.size() - 1):
			main_h = h
			main_z = z
		# Tapered mast in two segments with a slight aft rake.
		var rake := deg_to_rad(3.5)
		var mast_root := Node3D.new()
		mast_root.position = Vector3(0, deck, z)
		mast_root.rotation.x = -rake
		_root.add_child(mast_root)
		_mast_seg(mast_root, 0.30, 0.42, h * 0.60, h * 0.30)
		_mast_seg(mast_root, 0.16, 0.24, h * 0.45, h * 0.60 + h * 0.185)
		# Fighting top.
		var top := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.85
		cm.bottom_radius = 0.65
		cm.height = 0.30
		top.mesh = cm
		top.position = Vector3(0, h * 0.60, 0)
		top.material_override = _flat_material(COLOR_MAST)
		mast_root.add_child(top)

		# Sails: lateen rig for the small Mediterranean hulls, square tiers
		# for everything else.
		var wb := _beam * 2.0 * (1.0 - m * 0.08)
		if _lateen:
			_lateen_sail(mast_root, h)
		else:
			var tiers: Array = _sail_tiers()
			for ti in tiers.size():
				if ti == 0 and not masts[m][2]:
					continue  # aft mast of a three-master carries no course
				var tier: Array = tiers[ti]
				_yard_with_sail(mast_root, h * tier[0], wb * tier[1], h * tier[2])
			# Spanker on the aft-most mast of 3-masted ships.
			if masts.size() == 3 and m == 2:
				_spanker(mast_root, h)

		# Shrouds with ratlines.
		_shrouds(z, deck, h * 0.60)

	# Stays fore and aft + flag on the mainmast.
	_rig_line(Vector3(0, _deck_y(0.5) + main_h * 0.95, main_z), Vector3(0, _depth * 1.5, -length * 0.60))
	_flag = _box(Vector3(0.10, length * 0.045, length * 0.09),
		Vector3(0, _deck_y(0.5) + main_h * 1.02, main_z + length * 0.04), flag_color)
	_flag.material_override = _flat_material(flag_color, true)


func _mast_seg(parent: Node3D, r_top: float, r_bot: float, h: float, y0: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	mi.position = Vector3(0, y0 + h / 2.0, 0)
	mi.material_override = _flat_material(COLOR_MAST)
	parent.add_child(mi)


func _yard_with_sail(mast_root: Node3D, y: float, width: float, sail_h: float) -> void:
	var yard := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.09
	cm.bottom_radius = 0.16
	cm.height = width
	yard.mesh = cm
	yard.rotation_degrees = Vector3(0, 0, 90)
	yard.position = Vector3(0, y, 0)
	yard.material_override = _flat_material(COLOR_MAST)
	mast_root.add_child(yard)

	var pivot := Node3D.new()
	pivot.position = Vector3(0, y - 0.15, 0)
	mast_root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _square_sail_mesh(width * 0.96, width * 0.74, sail_h, width * 0.17)
	mi.material_override = _sail_mat
	pivot.add_child(mi)
	_sails.append(pivot)


## Square sail: trapezoid grid, billowing toward the bow (-z), curved foot.
func _square_sail_mesh(w_bottom: float, w_top: float, h: float, billow: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var cols := 10
	var rows := 6
	for r in rows:
		for c in cols:
			var pts := []
			for offset in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var u := float(c + offset[0]) / cols
				var v := float(r + offset[1]) / rows
				var w := lerpf(w_top, w_bottom, v)
				var x := (u - 0.5) * w
				# The foot of the sail arcs upward at the middle.
				var y := -v * h + sin(PI * u) * h * 0.06 * v
				var z := -billow * sin(PI * u) * sin(PI * clampf(v * 0.8 + 0.15, 0.0, 1.0))
				pts.append(Vector3(x, y, z))
			st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
			st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	st.generate_normals()
	return st.commit()


## Lateen rig: one long slanted yard with a triangular sail — the look of
## tartanes and luggers.
func _lateen_sail(mast_root: Node3D, h: float) -> void:
	var fore := Vector3(0, h * 0.32, -length * 0.26)
	var peak := Vector3(0, h * 1.00, length * 0.16)
	mast_root.add_child(_spar(fore, peak, 0.09))
	var clew := Vector3(0, h * 0.14, length * 0.30)
	var pivot := Node3D.new()
	pivot.position = fore
	mast_root.add_child(pivot)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var yard_v: Vector3 = peak - fore
	var clew_v: Vector3 = clew - fore
	var grid := 6
	for r in grid:
		for c in grid:
			var pts := []
			for offset in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var u := float(c + offset[0]) / grid
				var v := float(r + offset[1]) / grid
				var on_yard: Vector3 = yard_v * u
				var p: Vector3 = on_yard.lerp(clew_v * u, v)
				p.x += sin(PI * u) * sin(PI * v) * length * 0.03
				pts.append(p)
			st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
			st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _sail_mat
	pivot.add_child(mi)
	_sails.append(pivot)


## Gaff spanker: the fore-and-aft sail on the aft mast.
func _spanker(mast_root: Node3D, h: float) -> void:
	var gaff_in := Vector3(0, h * 0.52, 0)
	var gaff_out := Vector3(0, h * 0.62, length * 0.22)
	var boom_out := Vector3(0, h * 0.10, length * 0.26)
	var boom_in := Vector3(0, h * 0.10, 0)
	for pair in [[gaff_in, gaff_out], [boom_in, boom_out]]:
		var line := _spar(pair[0], pair[1], 0.10)
		mast_root.add_child(line)
	var pivot := Node3D.new()
	pivot.position = gaff_in
	mast_root.add_child(pivot)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var quad := [Vector3.ZERO, gaff_out - gaff_in, boom_out - gaff_in, boom_in - gaff_in]
	var grid := 6
	for r in grid:
		for c in grid:
			var pts := []
			for offset in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var u := float(c + offset[0]) / grid
				var v := float(r + offset[1]) / grid
				var p_top: Vector3 = quad[0].lerp(quad[1], u)
				var p_bot: Vector3 = quad[3].lerp(quad[2], u)
				var p: Vector3 = p_top.lerp(p_bot, v)
				p.x += sin(PI * u) * sin(PI * v) * length * 0.02
				pts.append(p)
			st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
			st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _sail_mat
	pivot.add_child(mi)
	_sails.append(pivot)


func _shrouds(z: float, deck: float, top_y: float) -> void:
	for side in [-1.0, 1.0]:
		var top := Vector3(0, deck + top_y, z)
		var anchors := [
			Vector3(side * _beam * 0.52, deck + 0.3, z - length * 0.07),
			Vector3(side * _beam * 0.54, deck + 0.3, z),
			Vector3(side * _beam * 0.52, deck + 0.3, z + length * 0.07),
		]
		for a in anchors:
			_root.add_child(_spar(top, a, 0.045, COLOR_ROPE))
		# Ratlines: horizontal steps between the outer shrouds.
		for i in range(1, 6):
			var f := float(i) / 7.0
			var p1: Vector3 = top.lerp(anchors[0], 1.0 - f)
			var p2: Vector3 = top.lerp(anchors[2], 1.0 - f)
			_root.add_child(_spar(p1, p2, 0.025, COLOR_ROPE))


func _build_bowsprit_and_jibs() -> void:
	var base := Vector3(0, _depth * 1.15, -length * 0.46)
	var tip := Vector3(0, _depth * 2.6, -length * 0.78)
	_root.add_child(_spar(base, tip, 0.20))
	# Two triangular jibs hanging from the fore stay.
	var masts := _mast_positions()
	var fore_t: float = masts[0][0]
	var fore_h: float = length * 0.92 * masts[0][1]
	var fore_z := -length / 2.0 + fore_t * length
	var head1 := Vector3(0, _deck_y(fore_t) + fore_h * 0.82, fore_z)
	var head2 := Vector3(0, _deck_y(fore_t) + fore_h * 0.58, fore_z)
	_root.add_child(_spar(head1, tip, 0.045, COLOR_ROPE))
	for jib in [
		{"head": head1, "tack": tip, "sag": 0.30},
		{"head": head2, "tack": tip.lerp(head2, 0.22), "sag": 0.42},
	]:
		var pivot := Node3D.new()
		pivot.position = jib["head"]
		_root.add_child(pivot)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(0)
		var head: Vector3 = Vector3.ZERO
		var tack: Vector3 = jib["tack"] - jib["head"]
		var clew: Vector3 = tack.lerp(Vector3.ZERO, jib["sag"]) + Vector3(0, -tack.length() * 0.18, tack.length() * 0.30)
		var grid := 5
		for r in grid:
			for c in grid:
				var pts := []
				for offset in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var u := minf(float(c + offset[0]) / grid, 1.0)
					var v := minf(float(r + offset[1]) / grid, 1.0)
					var edge := head.lerp(tack, u)
					var p := edge.lerp(clew, v * u)
					p.x += sin(PI * minf(u, 1.0)) * sin(PI * v) * length * 0.012
					pts.append(p)
				st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
				st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _sail_mat
		pivot.add_child(mi)
		_sails.append(pivot)


## A spar/rope: a thin cylinder between two points.
func _spar(from: Vector3, to: Vector3, radius: float, color := COLOR_MAST) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = from.distance_to(to)
	mi.mesh = cm
	mi.position = (from + to) / 2.0
	mi.material_override = _flat_material(color)
	var axis := (to - from).normalized()
	if absf(axis.dot(Vector3.UP)) < 0.999:
		var rot_axis := Vector3.UP.cross(axis).normalized()
		mi.rotate(rot_axis, Vector3.UP.angle_to(axis))
	return mi


func _rig_line(from: Vector3, to: Vector3) -> void:
	_root.add_child(_spar(from, to, 0.05, COLOR_ROPE))


func _box(size: Vector3, pos: Vector3, color: Color, mat: StandardMaterial3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	if mat != null:
		mi.material_override = mat
		# Vertex color comes from the mesh's modulate; bake via material copy.
		var m2: StandardMaterial3D = mat.duplicate()
		m2.vertex_color_use_as_albedo = false
		m2.albedo_color = color
		mi.material_override = m2
	else:
		mi.material_override = _flat_material(color)
	_root.add_child(mi)
	return mi


func _cylinder(r_top: float, r_bot: float, h: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	mi.mesh = cm
	mi.position = pos
	mi.material_override = _flat_material(color)
	_root.add_child(mi)
	return mi


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
	position.y = sin(time * 1.1 + phase) * 0.5 + 0.55
	rotation.x = sin(time * 0.9 + phase) * 0.02
	rotation.z = cos(time * 0.7 + phase) * 0.035
	if _flag != null:
		_flag.rotation.y = sin(time * 3.0 + phase) * 0.25
