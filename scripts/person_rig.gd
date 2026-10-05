## Drives a character skeleton from simple limb pivots: each pivot's
## rotation (in the figure's own space, e.g. rotation.x = swing forward)
## is applied to its bone around the joint, so scene scripts animate a
## skinned model the same way they animated the old primitive figures.
extends Node3D

var _skel: Skeleton3D
var _drive := {}       # pivot Node3D -> bone index
var _rest_global := {} # bone index -> rest rotation in skeleton space
var _rest_local := {}  # bone index -> rest rotation relative to parent
var _base := {}        # pivot -> resting pose in figure space (arms lowered from the A-pose)


func setup(skel: Skeleton3D, drive: Dictionary, base := {}) -> void:
	_skel = skel
	_drive = drive
	_base = base
	for bone: int in drive.values():
		_rest_global[bone] = skel.get_bone_global_rest(bone).basis.get_rotation_quaternion()
		_rest_local[bone] = skel.get_bone_rest(bone).basis.get_rotation_quaternion()


func _process(_delta: float) -> void:
	if _skel == null:
		return
	# Skeleton space may be rotated/scaled relative to the figure root.
	var to_skel: Quaternion = (global_basis.inverse() * _skel.global_basis).get_rotation_quaternion() \
		if is_inside_tree() else Quaternion.IDENTITY
	for pivot: Node3D in _drive:
		var bone: int = _drive[pivot]
		var g: Quaternion = _rest_global[bone]
		# The pivot's rotation, re-expressed in skeleton space, about the joint.
		var q: Quaternion = to_skel.inverse() * (pivot.quaternion * _base.get(pivot, Quaternion.IDENTITY)) * to_skel
		var delta_local: Quaternion = g.inverse() * q * g
		_skel.set_bone_pose_rotation(bone, _rest_local[bone] * delta_local)
