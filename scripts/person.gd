## Shared procedural human figure: legs (or a skirt), arms with hands,
## torso, head, optional headwear and a cutlass. Returns the root node and
## limb pivots for walk/attack animation.
extends RefCounted

const SKIN_DEFAULT := Color("d9a97a")


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


## headwear: 0 hair, 1 brimmed hat, 2 headscarf, 3 bandana
static func build(cloth: Color, skin: Color = SKIN_DEFAULT, skirted := false,
		headwear := 0, with_sword := false) -> Dictionary:
	var root := Node3D.new()
	var out := {"root": root, "l_leg": null, "r_leg": null, "l_arm": null, "r_arm": null, "sword": null}

	if skirted:
		var skirt := MeshInstance3D.new()
		var sk := CylinderMesh.new()
		sk.top_radius = 0.16
		sk.bottom_radius = 0.34
		sk.height = 0.95
		skirt.mesh = sk
		skirt.position = Vector3(0, 0.48, 0)
		skirt.material_override = _mat(cloth)
		root.add_child(skirt)
	else:
		for leg in [["l_leg", -0.10], ["r_leg", 0.10]]:
			var hip := Node3D.new()
			hip.position = Vector3(leg[1], 0.78, 0)
			root.add_child(hip)
			var shin := MeshInstance3D.new()
			var lc := CylinderMesh.new()
			lc.top_radius = 0.075
			lc.bottom_radius = 0.065
			lc.height = 0.74
			shin.mesh = lc
			shin.position = Vector3(0, -0.37, 0)
			shin.material_override = _mat(Color("3a3226"))
			hip.add_child(shin)
			var boot := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.14, 0.1, 0.24)
			boot.mesh = bm
			boot.position = Vector3(0, -0.76, -0.04)
			boot.material_override = _mat(Color("1d1208"))
			hip.add_child(boot)
			out[leg[0]] = hip

	var torso := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.20
	tc.height = 0.78
	torso.mesh = tc
	torso.position = Vector3(0, 1.15, 0)
	torso.material_override = _mat(cloth)
	root.add_child(torso)

	for arm in [["l_arm", -0.27], ["r_arm", 0.27]]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(arm[1], 1.42, 0)
		root.add_child(shoulder)
		var sleeve := MeshInstance3D.new()
		var sc := CapsuleMesh.new()
		sc.radius = 0.06
		sc.height = 0.5
		sleeve.mesh = sc
		sleeve.position = Vector3(0, -0.2, 0)
		sleeve.material_override = _mat(cloth.darkened(0.1))
		shoulder.add_child(sleeve)
		var hand := MeshInstance3D.new()
		var hc := SphereMesh.new()
		hc.radius = 0.055
		hc.height = 0.11
		hand.mesh = hc
		hand.position = Vector3(0, -0.47, 0)
		hand.material_override = _mat(skin)
		shoulder.add_child(hand)
		out[arm[0]] = shoulder

	if with_sword:
		# A cutlass in the right hand, blade forward.
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(0.05, 0.85, 0.09)
		blade.mesh = blm
		blade.position = Vector3(0, -0.95, 0)
		var steel := StandardMaterial3D.new()
		steel.albedo_color = Color("cfd4d9")
		steel.metallic = 0.8
		steel.roughness = 0.25
		blade.material_override = steel
		out["r_arm"].add_child(blade)
		var guard := MeshInstance3D.new()
		var gm := SphereMesh.new()
		gm.radius = 0.09
		gm.height = 0.18
		guard.mesh = gm
		guard.position = Vector3(0, -0.5, 0)
		guard.material_override = _mat(Color("c9a24a"))
		out["r_arm"].add_child(guard)
		out["sword"] = blade

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.14
	hm.height = 0.28
	head.mesh = hm
	head.position = Vector3(0, 1.66, 0)
	head.material_override = _mat(skin)
	root.add_child(head)

	match headwear:
		1:  # brimmed hat
			var brim := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = 0.22
			bc.bottom_radius = 0.22
			bc.height = 0.05
			brim.mesh = bc
			brim.position = Vector3(0, 1.79, 0)
			brim.material_override = _mat(Color("5d4024"))
			root.add_child(brim)
		2:  # headscarf
			var scarf := MeshInstance3D.new()
			var scm := SphereMesh.new()
			scm.radius = 0.15
			scm.height = 0.22
			scarf.mesh = scm
			scarf.position = Vector3(0, 1.74, 0)
			scarf.material_override = _mat(cloth.lightened(0.2))
			root.add_child(scarf)
		3:  # bandana
			var band := MeshInstance3D.new()
			var bnm := SphereMesh.new()
			bnm.radius = 0.148
			bnm.height = 0.16
			band.mesh = bnm
			band.position = Vector3(0, 1.76, 0)
			band.material_override = _mat(Color("8d3a2e"))
			root.add_child(band)
		_:  # hair
			var hair := MeshInstance3D.new()
			var hrm := SphereMesh.new()
			hrm.radius = 0.145
			hrm.height = 0.24
			hair.mesh = hrm
			hair.position = Vector3(0, 1.72, 0.04)
			hair.material_override = _mat(Color("2a1a0c"))
			root.add_child(hair)
	return out
