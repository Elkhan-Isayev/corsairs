## Procedural sailing-ship visual: a real tapered hull built with SurfaceTool,
## masts with yards, billowed sails, standing rigging, gunports, wake foam.
## No external assets — everything is generated at runtime.
extends Node3D

const COLOR_BOTTOM := Color("241505")
const COLOR_HULL := Color("6b4a2b")
const COLOR_STRAKE := Color("8a6540")
const COLOR_TRIM := Color("c9a24a")
const COLOR_DECK := Color("a3814f")
const COLOR_MAST := Color("4a3520")
const COLOR_SAIL := Color("ded6bd")

var length := 30.0
var flag_color := Color("c62828")

var _sails: Array = []   # {"node": Node3D at the yard, ...} — scaled to furl
var _flag: MeshInstance3D
var _wake: MeshInstance3D
var _wake_mat: StandardMaterial3D
var _root: Node3D


func build(p_length: float, p_flag: Color) -> void:
	length = p_length
	flag_color = p_flag
	_root = Node3D.new()
	add_child(_root)

	var beam := length * 0.27
	var depth := length * 0.11

	_build_hull(length, beam, depth)
	_build_stern_castle(length, beam, depth)
	_build_gunports(length, beam, depth)
	_build_masts_and_sails(length, beam, depth)
	_build_bowsprit(length, depth)
	_build_wake(length, beam)


# --- Hull ---

## Half-width profile along the hull, t: 0 = bow, 1 = stern.
func _half_width(t: float, beam: float) -> float:
	var w: float
	if t < 0.35:
		w = lerpf(0.04, 1.0, smoothstep(0.0, 0.35, t))
	elif t < 0.72:
		w = 1.0
	else:
		w = lerpf(1.0, 0.62, smoothstep(0.72, 1.0, t))
	return beam * 0.5 * w


## Deck sheer line: rises toward bow and stern.
func _deck_y(t: float, depth: float) -> float:
	return depth * (0.72 + 0.45 * pow(absf(t - 0.45) / 0.55, 2.0))


func _bottom_y(t: float, depth: float) -> float:
	var rise := smoothstep(0.0, 0.12, 0.12 - t) * 0.35 + smoothstep(0.88, 1.0, t) * 0.2
	return -depth * 0.45 + depth * rise


func _build_hull(L: float, beam: float, depth: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	# Row profile: keel edge, waterline bulge, deck edge (as x-multipliers).
	var row_x := [0.35, 1.0, 0.95]

	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var z0 := -L / 2.0 + t0 * L
		var z1 := -L / 2.0 + t1 * L
		for side in [-1.0, 1.0]:
			for r in 2:
				var pts := _station_points(t0, z0, beam, depth, side, row_x)
				var pts1 := _station_points(t1, z1, beam, depth, side, row_x)
				var col := COLOR_BOTTOM if r == 0 else COLOR_HULL
				if r == 1:
					col = COLOR_HULL
				_quad(st, pts[r], pts[r + 1], pts1[r + 1], pts1[r], col, side > 0.0)
		# Bottom face between keels.
		var b0l := Vector3(-_half_width(t0, beam) * row_x[0], _bottom_y(t0, depth), z0)
		var b0r := Vector3(_half_width(t0, beam) * row_x[0], _bottom_y(t0, depth), z0)
		var b1l := Vector3(-_half_width(t1, beam) * row_x[0], _bottom_y(t1, depth), z1)
		var b1r := Vector3(_half_width(t1, beam) * row_x[0], _bottom_y(t1, depth), z1)
		_quad(st, b0l, b0r, b1r, b1l, COLOR_BOTTOM, false)
		# Deck face.
		var d0l := Vector3(-_half_width(t0, beam) * row_x[2], _deck_y(t0, depth), z0)
		var d0r := Vector3(_half_width(t0, beam) * row_x[2], _deck_y(t0, depth), z0)
		var d1l := Vector3(-_half_width(t1, beam) * row_x[2], _deck_y(t1, depth), z1)
		var d1r := Vector3(_half_width(t1, beam) * row_x[2], _deck_y(t1, depth), z1)
		_quad(st, d0r, d0l, d1l, d1r, COLOR_DECK, false)

	# Transom (stern cap).
	var tt := 1.0
	var zt := L / 2.0
	var pl := _station_points(tt, zt, beam, depth, -1.0, row_x)
	var pr := _station_points(tt, zt, beam, depth, 1.0, row_x)
	_quad(st, pl[0], pr[0], pr[1], pl[1], COLOR_HULL, false)
	_quad(st, pl[1], pr[1], pr[2], pl[2], COLOR_STRAKE, false)

	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vertex_color_material()
	_root.add_child(mi)

	# Gold trim stripe along the sheer.
	var trim := _strip_along_hull(L, beam, depth, row_x[2], 0.985, 0.10)
	trim.material_override = _flat_material(COLOR_TRIM)
	_root.add_child(trim)


func _station_points(t: float, z: float, beam: float, depth: float, side: float, row_x: Array) -> Array:
	var w := _half_width(t, beam)
	var yb := _bottom_y(t, depth)
	var yd := _deck_y(t, depth)
	var ym := yb + (yd - yb) * 0.55
	return [
		Vector3(side * w * row_x[0], yb, z),
		Vector3(side * w * row_x[1], ym, z),
		Vector3(side * w * row_x[2], yd, z),
	]


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, flip: bool) -> void:
	st.set_color(col)
	var order := [a, b, c, a, c, d] if not flip else [a, c, b, a, d, c]
	for v in order:
		st.set_color(col)
		st.add_vertex(v)


## A thin raised strip following the deck edge (trim / rubbing strake).
func _strip_along_hull(L: float, beam: float, depth: float, row_x: float, scale_w: float, h: float) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	for i in steps:
		var t0 := float(i) / steps
		var t1 := float(i + 1) / steps
		var z0 := -L / 2.0 + t0 * L
		var z1 := -L / 2.0 + t1 * L
		for side in [-1.0, 1.0]:
			var x0: float = side * _half_width(t0, beam) * row_x * scale_w
			var x1: float = side * _half_width(t1, beam) * row_x * scale_w
			var y0 := _deck_y(t0, depth) - h * 1.6
			var y1 := _deck_y(t1, depth) - h * 1.6
			var a := Vector3(x0, y0, z0)
			var b := Vector3(x0 * 1.05, y0 + h, z0)
			var c := Vector3(x1 * 1.05, y1 + h, z1)
			var d := Vector3(x1, y1, z1)
			_quad(st, a, b, c, d, COLOR_TRIM, side > 0.0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	return mi


func _vertex_color_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.85
	return m


func _flat_material(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --- Superstructure & details ---

func _build_stern_castle(L: float, beam: float, depth: float) -> void:
	var w := beam * 0.86
	var h := depth * 0.9
	var castle := _box(Vector3(w, h, L * 0.18), Vector3(0, _deck_y(0.9, depth) + h * 0.45, L * 0.40), COLOR_STRAKE)
	castle.name = "SternCastle"
	# Stern windows: a dark band with gold frame on the transom.
	_box(Vector3(w * 0.7, h * 0.28, 0.15), Vector3(0, _deck_y(1.0, depth) + h * 0.5, L * 0.492), Color("1a1208"))
	_box(Vector3(w * 0.74, h * 0.06, 0.18), Vector3(0, _deck_y(1.0, depth) + h * 0.66, L * 0.492), COLOR_TRIM)
	_box(Vector3(w * 0.74, h * 0.06, 0.18), Vector3(0, _deck_y(1.0, depth) + h * 0.36, L * 0.492), COLOR_TRIM)


func _build_gunports(L: float, beam: float, depth: float) -> void:
	var n := clampi(int(L / 7.0), 3, 7)
	var size := L * 0.030
	for side in [-1.0, 1.0]:
		for i in n:
			var t := 0.32 + float(i) / n * 0.42
			var z := -L / 2.0 + t * L
			var x := _half_width(t, beam) * 1.01
			var y := _bottom_y(t, depth) + (_deck_y(t, depth) - _bottom_y(t, depth)) * 0.52
			_box(Vector3(0.12, size, size), Vector3(side * x, y, z), Color("120b04"))


func _build_masts_and_sails(L: float, beam: float, depth: float) -> void:
	var mast_count := 2 if L < 28.0 else 3
	var mast_h := L * 0.9
	for i in mast_count:
		var frac := float(i) / maxf(mast_count - 1, 1.0)
		var z := -L * 0.30 + frac * (L * 0.58)
		var h := mast_h * (1.0 if i != mast_count - 1 else 0.85)
		var deck := _deck_y(0.5, depth)
		# Mast (two tapered segments).
		_cylinder(0.34, 0.22, h * 0.62, Vector3(0, deck + h * 0.31, z), COLOR_MAST)
		_cylinder(0.20, 0.10, h * 0.42, Vector3(0, deck + h * 0.62 + h * 0.21, z), COLOR_MAST)
		# Fighting top platform.
		_cylinder(0.9, 0.9, 0.3, Vector3(0, deck + h * 0.62, z), COLOR_MAST)
		# Yards + sails (two tiers).
		var wb := beam * (1.9 - frac * 0.2)
		_yard_with_sail(Vector3(0, deck + h * 0.88, z), wb * 0.72, h * 0.30)
		_yard_with_sail(Vector3(0, deck + h * 0.55, z), wb, h * 0.34)
		# Standing rigging: shrouds to the deck edges.
		var top := Vector3(0, deck + h * 0.62, z)
		for side in [-1.0, 1.0]:
			_rig_line(top, Vector3(side * beam * 0.5, deck + 0.2, z - L * 0.06))
			_rig_line(top, Vector3(side * beam * 0.5, deck + 0.2, z + L * 0.06))
	# Fore/back stays.
	var deck_y := _deck_y(0.5, depth)
	_rig_line(Vector3(0, deck_y + mast_h * 0.95, -L * 0.30), Vector3(0, depth * 1.05, -L * 0.62))
	_rig_line(Vector3(0, deck_y + mast_h * 0.80, L * 0.28), Vector3(0, _deck_y(1.0, depth) + depth, L * 0.48))

	# Flag on the mainmast.
	_flag = _box(Vector3(0.12, L * 0.05, L * 0.10), Vector3(0, deck_y + mast_h * 1.04, -L * 0.30 + L * 0.05), flag_color)
	_flag.material_override = _flat_material(flag_color, true)


func _yard_with_sail(yard_pos: Vector3, width: float, sail_h: float) -> void:
	# Yard — the horizontal spar the sail hangs from.
	var yard := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.14
	cm.bottom_radius = 0.14
	cm.height = width
	yard.mesh = cm
	yard.rotation_degrees = Vector3(0, 0, 90)
	yard.position = yard_pos
	yard.material_override = _flat_material(COLOR_MAST)
	_root.add_child(yard)

	# Sail: a curved grid, narrower at the head, billowing toward the bow (-z).
	var pivot := Node3D.new()
	pivot.position = yard_pos
	_root.add_child(pivot)
	var mi := MeshInstance3D.new()
	mi.mesh = _sail_mesh(width * 0.94, width * 0.70, sail_h, width * 0.16)
	var mat := _flat_material(COLOR_SAIL)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mi.material_override = mat
	pivot.add_child(mi)
	_sails.append(pivot)


func _sail_mesh(w_bottom: float, w_top: float, h: float, billow: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 8
	var rows := 5
	for r in rows:
		for c in cols:
			var pts := []
			for offset in [[0, 0], [1, 0], [1, 1], [0, 1]]:
				var u := float(c + offset[0]) / cols
				var v := float(r + offset[1]) / rows
				var w := lerpf(w_top, w_bottom, v)
				var x := (u - 0.5) * w
				var y := -v * h
				var z := -billow * sin(PI * u) * sin(PI * clampf(v * 0.85 + 0.1, 0.0, 1.0))
				pts.append(Vector3(x, y, z))
			st.add_vertex(pts[0]); st.add_vertex(pts[1]); st.add_vertex(pts[2])
			st.add_vertex(pts[0]); st.add_vertex(pts[2]); st.add_vertex(pts[3])
	st.generate_normals()
	return st.commit()


func _build_bowsprit(L: float, depth: float) -> void:
	var spar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.10
	cm.bottom_radius = 0.22
	cm.height = L * 0.34
	spar.mesh = cm
	spar.position = Vector3(0, depth * 1.15, -L * 0.58)
	spar.rotation_degrees = Vector3(-65, 0, 0)
	spar.material_override = _flat_material(COLOR_MAST)
	_root.add_child(spar)


func _rig_line(from: Vector3, to: Vector3) -> void:
	var mid := (from + to) / 2.0
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = from.distance_to(to)
	mi.mesh = cm
	mi.position = mid
	mi.material_override = _flat_material(Color("2a1f12"))
	_root.add_child(mi)
	# Aim the cylinder along the from→to axis.
	var axis := (to - from).normalized()
	if absf(axis.dot(Vector3.UP)) < 0.999:
		var rot_axis := Vector3.UP.cross(axis).normalized()
		mi.rotate(rot_axis, Vector3.UP.angle_to(axis))


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
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


# --- Wake ---

func _build_wake(L: float, beam: float) -> void:
	_wake = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(beam * 0.9, L * 1.1)
	_wake.mesh = pm
	_wake.position = Vector3(0, 0.15, L * 0.95)
	_wake_mat = StandardMaterial3D.new()
	# A teardrop foam patch: radial gradient fading away from the stern.
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


# --- Animation hooks ---

## Sails visually furl at 0 and unfurl at 1 (pivot sits at the yard).
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
