"""Prepares the Higgsfield (Hunyuan3D) house models for the port towns.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P tools/blender/import_houses.py -- SRC_DIR [--preview DIR]

SRC_DIR holds <id>_raw.glb for every entry in HOUSES — textured meshes
generated from Higgsfield concept art (gpt_image_2_5 → hunyuan3d_v3).
Each is turned so its front door faces Godot -Z, set on the ground with the
footprint centred on the origin, decimated, and exported to
assets/houses/<id>.gltf; assets/houses/houses.json records each footprint
(width x, depth z, height y in metres) so the town can fit them to a lot.
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "houses")

# id: (yaw in degrees that brings the door to the front, real width in metres, tri budget)
HOUSES = {
    "house_white": (180.0, 8.0, 14000),
    "house_yellow": (180.0, 9.0, 12000),
    "tavern": (180.0, 9.0, 14000),
}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def prepare(path, yaw, width, budget):
    bpy.ops.import_scene.gltf(filepath=path)
    obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)
    obj.parent = None
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    # Door to +Y in Blender = -Z in Godot.
    obj.matrix_world = Matrix.Rotation(math.radians(yaw), 4, "Z") @ obj.matrix_world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    co = np.array([v.co[:] for v in obj.data.vertices])
    mn, mx = co.min(axis=0), co.max(axis=0)
    k = width / (mx[0] - mn[0])
    centre = Vector(((mn[0] + mx[0]) / 2, (mn[1] + mx[1]) / 2, mn[2]))
    obj.data.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-centre))
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    if tris > budget:
        mod = obj.modifiers.new("dec", "DECIMATE")
        mod.ratio = budget / tris
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = False
    for m in obj.data.materials:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None:
                n.image.name = os.path.basename(path).replace("_raw.glb", "")
                if n.image.size[0] > 2048:
                    n.image.scale(2048, 2048)
        bsdf = m.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Roughness"].default_value = 0.9
            bsdf.inputs["Metallic"].default_value = 0.0
    co = np.array([v.co[:] for v in obj.data.vertices])
    size = co.max(axis=0) - co.min(axis=0)
    return obj, {"x": round(float(size[0]), 3), "z": round(float(size[1]), 3), "y": round(float(size[2]), 3)}


def preview(name, obj, out):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x, sc.render.resolution_y = 640, 480
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.4
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    dims = obj.dimensions
    L = max(dims)
    target = Vector((0, 0, dims.z / 2))
    # From the front (Blender +Y side), slightly to the right.
    cam.location = target + Vector((L * 0.7, L * 1.6, L * 0.35))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, name + ".png")
    bpy.ops.render.render(write_still=True)


argv = sys.argv[sys.argv.index("--") + 1:]
src = argv[0]
prev = argv[argv.index("--preview") + 1] if "--preview" in argv else None
sizes = {}
os.makedirs(OUT_DIR, exist_ok=True)
for hid, (yaw, width, budget) in HOUSES.items():
    if not os.path.exists(os.path.join(src, hid + "_raw.glb")):
        print(hid, "missing, skipped")
        continue
    clear()
    obj, size = prepare(os.path.join(src, hid + "_raw.glb"), yaw, width, budget)
    obj.name = hid
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, hid + ".gltf"), export_format="GLTF_SEPARATE",
        export_texture_dir="textures", use_selection=True, export_image_format="JPEG",
        export_jpeg_quality=86, export_yup=True, export_apply=True)
    sizes[hid] = size
    print(hid, size)
    if prev:
        os.makedirs(prev, exist_ok=True)
        preview(hid, obj, prev)
with open(os.path.join(OUT_DIR, "houses.json"), "w") as f:
    json.dump(sizes, f, indent=1)
