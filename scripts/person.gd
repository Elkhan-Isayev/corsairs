## Shared human figure: a rigged, textured character model (generated with
## Higgsfield, rigged in Blender by tools/blender/build_people.py). Returns
## the root node and limb pivots for walk/attack animation — plain nodes the
## scene scripts rotate exactly as before; person_rig.gd mirrors their
## rotations onto the skeleton's shoulder and hip bones every frame.
extends RefCounted

const SKIN_DEFAULT := Color("d9a97a")
const RIG := preload("res://scripts/person_rig.gd")
const LIMBS := [["l_leg", "UpperLeg_L"], ["r_leg", "UpperLeg_R"],
	["l_arm", "UpperArm_L"], ["r_arm", "UpperArm_R"]]

static var _scenes := {}


## Which character model fits the old procedural parameters.
## headwear: 0 hair, 1 brimmed hat, 2 headscarf, 3 bandana
static func kind_for(cloth: Color, skirted: bool, headwear: int, with_sword: bool) -> String:
	if skirted:
		return "woman"
	if with_sword:
		return "captain" if headwear == 1 else "sailor"
	if headwear == 1:
		return "townsman"
	if headwear == 3:
		return "sailor"
	return "sailor" if int(cloth.r8 + cloth.g8 * 3 + cloth.b8 * 7) % 2 == 0 else "townsman"


static func _scene(kind: String) -> PackedScene:
	if not _scenes.has(kind):
		_scenes[kind] = load("res://assets/people/%s.gltf" % kind)
	return _scenes[kind]


static func build(cloth: Color, skin: Color = SKIN_DEFAULT, skirted := false,
		headwear := 0, with_sword := false, kind := "") -> Dictionary:
	if kind == "":
		kind = kind_for(cloth, skirted, headwear, with_sword)
	var root := Node3D.new()
	root.set_script(RIG)
	var model: Node3D = _scene(kind).instantiate()
	root.add_child(model)
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	# A light wash of the cloth color tells crews and townsfolk apart.
	if cloth != Color.WHITE:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			if src != null:
				var m: BaseMaterial3D = src.duplicate()
				m.albedo_color = Color.WHITE.lerp(cloth.lightened(0.25), 0.35)
				mi.material_override = m
	var out := {"root": root, "l_leg": null, "r_leg": null, "l_arm": null, "r_arm": null, "sword": null}
	var drive := {}
	var base := {}
	for limb: Array in LIMBS:
		# Skirts hide the legs: their pivots stay null, as callers expect.
		if kind == "woman" and String(limb[0]).ends_with("leg"):
			continue
		var pivot := Node3D.new()
		pivot.name = limb[0]
		root.add_child(pivot)
		out[limb[0]] = pivot
		drive[pivot] = skel.find_bone(limb[1])
		# The models are rigged in an A-pose: let the arms hang at the sides.
		if limb[0] == "l_arm":
			base[pivot] = Quaternion(Vector3.BACK, 0.62)
		elif limb[0] == "r_arm":
			base[pivot] = Quaternion(Vector3.BACK, -0.62)
	root.setup(skel, drive, base)

	if with_sword:
		# A cutlass in the right hand, blade forward.
		var hand := BoneAttachment3D.new()
		hand.bone_name = "Hand_R"
		skel.add_child(hand)
		var grip := Node3D.new()
		grip.rotation_degrees = Vector3(90, 0, 0)
		hand.add_child(grip)
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(0.04, 0.8, 0.08)
		blade.mesh = blm
		blade.position = Vector3(0, 0.5, 0)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color("cfd4d9")
		steel.metallic = 0.8
		steel.roughness = 0.25
		blade.material_override = steel
		grip.add_child(blade)
		var guard := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.06
		gm.height = 0.12
		guard.mesh = gm
		guard.position = Vector3(0, 0.08, 0)
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color("c9a24a")
		brass.metallic = 0.6
		brass.roughness = 0.35
		guard.material_override = brass
		grip.add_child(guard)
		out["sword"] = blade
	return out
