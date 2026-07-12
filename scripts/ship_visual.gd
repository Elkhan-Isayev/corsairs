## Процедурный визуал парусника: корпус, мачты, паруса, флаг.
## Никаких внешних ассетов — только примитивы.
extends Node3D

var hull_color := Color("6b4a2b")
var sail_color := Color("e8e2d0")
var flag_color := Color("c62828")
## Длина корпуса в метрах — масштабируется от ранга корабля.
var length := 30.0

var _sails: Array = []   # MeshInstance3D парусов, скалируем по постановке
var _root: Node3D


func build(p_length: float, p_flag: Color) -> void:
	length = p_length
	flag_color = p_flag
	_root = Node3D.new()
	add_child(_root)
	var w := length * 0.22
	var h := length * 0.10

	# Корпус: основной блок + нос + корма.
	_box(Vector3(w, h, length * 0.7), Vector3(0, 0, 0), hull_color)
	_box(Vector3(w * 0.7, h * 0.8, length * 0.18), Vector3(0, h * 0.05, -length * 0.42), hull_color.darkened(0.1))
	_box(Vector3(w * 0.9, h * 1.4, length * 0.16), Vector3(0, h * 0.35, length * 0.38), hull_color.darkened(0.2))
	# Палуба.
	_box(Vector3(w * 0.85, h * 0.1, length * 0.66), Vector3(0, h * 0.52, 0), Color("8a6a3f"))

	# Мачты и паруса (2-3 мачты в зависимости от размера).
	var mast_count := 2 if length < 28.0 else 3
	var mast_h := length * 0.9
	for i in mast_count:
		var z := -length * 0.25 + i * (length * 0.5 / maxf(mast_count - 1, 1))
		_mast(Vector3(0, mast_h / 2.0, z), mast_h)
		_sail(Vector3(0, mast_h * 0.62, z), Vector3(w * 2.2, mast_h * 0.45, 0.3))
		_sail(Vector3(0, mast_h * 0.30, z), Vector3(w * 2.6, mast_h * 0.28, 0.3))

	# Флаг на корме.
	var flag := _box(Vector3(0.2, length * 0.06, length * 0.12), Vector3(0, mast_h * 0.95, -length * 0.25), flag_color)
	flag.name = "Flag"


func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	mi.material_override = mat
	_root.add_child(mi)
	return mi


func _mast(pos: Vector3, height: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.25
	mesh.bottom_radius = 0.45
	mesh.height = height
	mi.mesh = mesh
	mi.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4a3520")
	mi.material_override = mat
	_root.add_child(mi)


func _sail(pos: Vector3, size: Vector3) -> void:
	var mi := _box(size, pos, sail_color)
	_sails.append({"node": mi, "full_size": size, "pos": pos})


## Паруса визуально сворачиваются при 0 и раскрываются при 1.
func set_sail_amount(frac: float) -> void:
	frac = clampf(frac, 0.05, 1.0)
	for s in _sails:
		var node: MeshInstance3D = s["node"]
		node.scale = Vector3(1, frac, 1)
		var full: Vector3 = s["full_size"]
		var pos: Vector3 = s["pos"]
		node.position = Vector3(pos.x, pos.y + full.y * (1.0 - frac) * 0.5, pos.z)


## Лёгкая качка на волнах.
func bob(time: float, phase: float) -> void:
	position.y = sin(time * 1.1 + phase) * 0.4 + 0.2
	rotation.x = sin(time * 0.9 + phase) * 0.02
	rotation.z = cos(time * 0.7 + phase) * 0.035
