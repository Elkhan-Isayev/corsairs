"""Turns the Higgsfield (Hunyuan3D) character meshes into rigged game models.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P tools/blender/build_people.py -- SRC_DIR [--preview DIR]

SRC_DIR holds <name>_raw.glb for every entry in PEOPLE: textured A-pose
meshes generated with Higgsfield (gpt_image_2_5 concept → hunyuan3d_v3
image-to-3d). Each one is scaled to its height, decimated to a game
budget, given a humanoid skeleton and distance-based skin weights, and
exported to assets/people/<name>.gltf.

Skeleton contract read by scripts/person.gd (character faces -Z in Godot,
its right hand on +X): Hips, Spine, Chest, Neck, Head, UpperArm_L/R,
LowerArm_L/R, Hand_L/R, UpperLeg_L/R, LowerLeg_L/R, Foot_L/R.
"""

import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "people")

# name: (height in metres including headwear, triangle budget)
PEOPLE = {
    "captain": (1.84, 6000),
    "sailor": (1.78, 5000),
    "townsman": (1.84, 5000),
    "woman": (1.68, 5000),
}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def import_mesh(path, height, budget):
    bpy.ops.import_scene.gltf(filepath=path)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for o in list(bpy.context.scene.objects):
        if o != obj and o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Face +Y in Blender (-Z in Godot) and stand on the origin at the right height.
    obj.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ obj.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.array([v.co[:] for v in obj.data.vertices])
    mn, mx = co.min(axis=0), co.max(axis=0)
    k = height / (mx[2] - mn[2])
    centre = Vector(((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]))
    obj.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-centre))
    mod = obj.modifiers.new("dec", "DECIMATE")
    mod.ratio = min(1.0, budget / max(len(obj.data.polygons), 1))
    bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = True
    # Shrink the baked texture to a game-friendly size.
    for m in obj.data.materials:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                n.image.name = os.path.splitext(os.path.basename(path))[0].replace("_raw", "") + "_skin"
                if n.image.size[0] > 1024:
                    n.image.scale(1024, 1024)
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Roughness"].default_value = 0.85
            bsdf.inputs["Metallic"].default_value = 0.0
    obj.name = "Body"
    return obj


def joints(obj, H):
    """Joint positions from body proportions plus the mesh's real hands and legs."""
    co = np.array([v.co[:] for v in obj.data.vertices])
    j = {
        "Hips": Vector((0, 0, 0.53 * H)), "Spine": Vector((0, 0, 0.62 * H)),
        "Chest": Vector((0, 0, 0.72 * H)), "Neck": Vector((0, 0, 0.845 * H)),
        "Head": Vector((0, 0, 0.885 * H)), "HeadTop": Vector((0, 0, 1.0 * H)),
    }
    for s, tag in ((1, "R"), (-1, "L")):
        band = co[(co[:, 2] > 0.30 * H) & (co[:, 2] < 0.66 * H)]
        tip = band[np.argmax(band[:, 0] * s)]
        shoulder = Vector((s * 0.115 * H, 0, 0.815 * H))
        tipv = Vector(tip)
        d = (tipv - shoulder).normalized()
        wrist = tipv - d * 0.105 * H
        elbow = shoulder.lerp(wrist, 0.5) + Vector((0, -0.012 * H, 0))
        j["UpperArm_" + tag] = shoulder
        j["LowerArm_" + tag] = elbow
        j["Hand_" + tag] = wrist
        j["HandTip_" + tag] = tipv
        knee_band = co[(co[:, 2] > 0.22 * H) & (co[:, 2] < 0.32 * H) & (co[:, 0] * s > 0.01 * H)]
        kx = float(np.median(knee_band[:, 0])) if len(knee_band) else s * 0.06 * H
        j["UpperLeg_" + tag] = Vector((s * 0.055 * H, 0, 0.52 * H))
        j["LowerLeg_" + tag] = Vector((kx, 0.01 * H, 0.285 * H))
        j["Foot_" + tag] = Vector((kx * 1.05, -0.01 * H, 0.05 * H))
        j["Toe_" + tag] = Vector((kx * 1.1, 0.075 * H, 0.012 * H))
    return j


# bone: (head joint, tail joint, parent)
BONES = [
    ("Hips", "Hips", "Spine", None), ("Spine", "Spine", "Chest", "Hips"),
    ("Chest", "Chest", "Neck", "Spine"), ("Neck", "Neck", "Head", "Chest"),
    ("Head", "Head", "HeadTop", "Neck"),
]
for _t in ("L", "R"):
    BONES += [
        ("UpperArm_" + _t, "UpperArm_" + _t, "LowerArm_" + _t, "Chest"),
        ("LowerArm_" + _t, "LowerArm_" + _t, "Hand_" + _t, "UpperArm_" + _t),
        ("Hand_" + _t, "Hand_" + _t, "HandTip_" + _t, "LowerArm_" + _t),
        ("UpperLeg_" + _t, "UpperLeg_" + _t, "LowerLeg_" + _t, "Hips"),
        ("LowerLeg_" + _t, "LowerLeg_" + _t, "Foot_" + _t, "UpperLeg_" + _t),
        ("Foot_" + _t, "Foot_" + _t, "Toe_" + _t, "LowerLeg_" + _t),
    ]


def build_armature(j):
    arm_data = bpy.data.armatures.new("Rig")
    arm = bpy.data.objects.new("Rig", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    for name, h, t, parent in BONES:
        eb = arm_data.edit_bones.new(name)
        eb.head = j[h]
        eb.tail = j[t]
        if (eb.tail - eb.head).length < 1e-3:
            eb.tail = eb.head + Vector((0, 0, 0.05))
        eb.align_roll(Vector((0, 1, 0)) if abs((eb.tail - eb.head).normalized().y) < 0.9 else Vector((0, 0, 1)))
        if parent:
            eb.parent = arm_data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def skin(obj, arm, j, H):
    """Distance-based weights with side gating so limbs never pull the other side."""
    co = np.array([v.co[:] for v in obj.data.vertices])
    x, z = co[:, 0], co[:, 2]
    names = [b[0] for b in BONES]
    W = np.zeros((len(co), len(names)))
    for k, (name, h, t, _parent) in enumerate(BONES):
        d = seg_dist(co, np.array(j[h][:]), np.array(j[t][:]))
        w = 1.0 / (d + 0.012 * H) ** 6
        if "Arm" in name or "Hand" in name:
            s = 1 if name.endswith("_R") else -1
            w *= (x * s > 0.075 * H) & (z > 0.30 * H)
        elif "Leg" in name or "Foot" in name:
            s = 1 if name.endswith("_R") else -1
            w *= (z < 0.56 * H) & (x * s > -0.015 * H)
        else:
            w *= (np.abs(x) < 0.17 * H) | (z > 0.8 * H)
        W[:, k] = w
    # Keep the four strongest influences per vertex.
    order = np.argsort(-W, axis=1)
    keep = np.zeros_like(W, dtype=bool)
    np.put_along_axis(keep, order[:, :4], True, axis=1)
    W = np.where(keep, W, 0)
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    for k, name in enumerate(names):
        vg = obj.vertex_groups.new(name=name)
        idx = np.nonzero(W[:, k] > 0.01)[0]
        for i in idx:
            vg.add([int(i)], float(W[i, k]), "REPLACE")
    obj.parent = arm
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm


def export(name, arm, obj):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    obj.select_set(True)
    path = os.path.join(OUT_DIR, name + ".gltf")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
        use_selection=True, export_image_format="JPEG", export_jpeg_quality=85,
        export_skins=True, export_animations=False, export_yup=True,
        export_cameras=False, export_lights=False)
    return path


def preview(name, arm, out_dir):
    """Front render with the right arm and left leg swung forward."""
    pb = arm.pose.bones
    pb["UpperArm_R"].rotation_mode = "XYZ"
    pb["UpperArm_R"].rotation_euler = (math.radians(-50), 0, 0)
    pb["UpperLeg_L"].rotation_mode = "XYZ"
    pb["UpperLeg_L"].rotation_euler = (math.radians(-30), 0, 0)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = 500
    sc.render.resolution_y = 500
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.5
    cd = bpy.data.cameras.new("c")
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = (2.2, 2.6, 1.1)
    cam.rotation_euler = (Vector((0, 0, 0.9)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    for b in pb:
        b.rotation_euler = (0, 0, 0)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = argv[0]
    prev = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    for name, (height, budget) in PEOPLE.items():
        clear()
        obj = import_mesh(os.path.join(src, name + "_raw.glb"), height, budget)
        j = joints(obj, height)
        arm = build_armature(j)
        skin(obj, arm, j, height)
        print(name, len(obj.data.polygons), "faces ->", export(name, arm, obj))
        if prev:
            os.makedirs(prev, exist_ok=True)
            preview(name, arm, prev)


main()
