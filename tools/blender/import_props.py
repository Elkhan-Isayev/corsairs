"""Prepares Poly Haven prop models (CC0) for the port towns.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P tools/blender/import_props.py -- SRC_DIR [--preview DIR]

For each prop: import Poly Haven's 1k glTF, decimate to a game budget,
put the origin at the bottom centre and export assets/props/<id>.gltf.
"""

import glob
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "props")

# id: triangle budget
PROPS = {
    "wine_barrel_01": 6000,
    "wooden_crate_01": 3000,
    "wooden_crate_02": 3000,
    "cannon_01": 9000,
    "wooden_lantern_01": 2500,
}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def prepare(pid, budget):
    bpy.ops.import_scene.gltf(filepath=glob.glob(os.path.join(SRC, pid, "*.gltf"))[0])
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    tris = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    if tris > budget:
        ratio = budget / tris
        for o in meshes:
            if o.data.shape_keys is not None:
                o.shape_key_clear()
            mod = o.modifiers.new("dec", "DECIMATE")
            mod.ratio = ratio
            mod.use_collapse_triangulate = True
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.modifier_apply(modifier=mod.name)
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    mn = Vector([min(p[i] for p in pts) for i in range(3)])
    mx = Vector([max(p[i] for p in pts) for i in range(3)])
    offset = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
    for o in meshes:
        o.data.transform(Matrix.Translation(-offset))
        o.location = (0, 0, 0)
    for img in bpy.data.images:
        if img.size[0] > 1024:
            img.scale(1024, int(1024 * img.size[1] / img.size[0]))
    after = sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)
    return meshes, tris, after, mx - mn


def export(pid, meshes):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(OUT_DIR, pid + ".gltf"), export_format="GLTF_SEPARATE",
        export_texture_dir="textures", use_selection=True, export_image_format="AUTO",
        export_yup=True, export_apply=True, export_animations=False)


def preview(pid, size, out):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.render.resolution_x = sc.render.resolution_y = 400
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.2
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3
    sun.rotation_euler = (math.radians(50), 0, math.radians(140))
    sc.collection.objects.link(sun)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    L = max(size)
    target = Vector((0, 0, size.z / 2))
    cam.location = target + Vector((L * 1.2, -L * 1.2, L * 0.5))
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out, pid + ".png")
    bpy.ops.render.render(write_still=True)


def tex_material(name, base, normal=None, alpha=False):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = bpy.data.images.load(base)
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
        m.blend_method = "CLIP" if hasattr(m, "blend_method") else None
        m.surface_render_method = "DITHERED"
    if normal:
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = bpy.data.images.load(normal)
        n.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bsdf.inputs["Roughness"].default_value = 0.85
    return m


def build_palm(pid, height, lean, seed):
    """Coconut palm: a leaning, tapering ringed trunk and a crown of drooping
    fronds (alpha cards textured with a Higgsfield-generated frond)."""
    import random
    rnd = random.Random(seed)
    bark = tex_material("bark", os.path.join(ROOT, "assets/textures/palm_tree_bark/palm_tree_bark_diff.jpg"),
                        os.path.join(ROOT, "assets/textures/palm_tree_bark/palm_tree_bark_nor_gl.jpg"))
    frond = tex_material("frond", os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures/palm_frond.png"),
                         alpha=True)
    # Trunk: a curved tube, 10 sides.
    verts, faces, uvs = [], [], []
    rings, sides = 18, 10
    for j in range(rings + 1):
        f = j / rings
        bend = lean * (f ** 1.7)
        c = Vector((bend, 0, f * height))
        r = 0.26 * (1.0 - 0.4 * f) + (0.06 if f < 0.06 else 0.0)  # flared foot
        for i in range(sides):
            a = 2 * math.pi * i / sides
            verts.append(c + Vector((math.cos(a) * r, math.sin(a) * r, 0)))
    for j in range(rings):
        for i in range(sides):
            a, b = j * sides + i, j * sides + (i + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    me = bpy.data.meshes.new("trunk")
    me.from_pydata([tuple(v) for v in verts], [], faces)
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for k, li in enumerate(poly.loop_indices):
            vi = me.loops[li].vertex_index
            j, i = vi // sides, vi % sides
            if k in (1, 2) and i == 0:
                i = sides
            uv.data[li].uv = (i / sides, j / rings * height / 1.2)
        poly.use_smooth = True
    me.materials.append(bark)
    trunk = bpy.data.objects.new("Trunk", me)
    bpy.context.scene.collection.objects.link(trunk)
    top = Vector((lean, 0, height))
    # Crown: fronds radiating out and arching down.
    fv, ff, fuv = [], [], []
    n = 16
    for k in range(n):
        az = 2 * math.pi * k / n + rnd.uniform(-0.2, 0.2)
        length = rnd.uniform(3.2, 4.2)
        lift = rnd.uniform(0.15, 0.7) if k % 3 else rnd.uniform(1.2, 1.8)
        width = length * 0.36
        d = Vector((math.cos(az), math.sin(az), 0))
        side = Vector((-d.y, d.x, 0))
        seg = 8
        base = len(fv)
        for j in range(seg + 1):
            u = j / seg
            along = d * (u * length)
            drop = lift * u - 1.6 * (u ** 2.2) * length / 3.6
            centre = top + along + Vector((0, 0, drop))
            # Leaflets droop: the card folds down along its rib.
            for sgn in (-1, 1):
                fv.append(centre + side * sgn * width / 2 + Vector((0, 0, -0.18 * width)))
            fv.insert(len(fv) - 1, centre)
        for j in range(seg):
            r0 = base + j * 3
            r1 = r0 + 3
            ff.append((r0, r0 + 1, r1 + 1, r1))
            ff.append((r0 + 1, r0 + 2, r1 + 2, r1 + 1))
        for j in range(seg + 1):
            fuv.extend([(0.0, j / seg), (0.5, j / seg), (1.0, j / seg)])
    fme = bpy.data.meshes.new("fronds")
    fme.from_pydata([tuple(v) for v in fv], [], ff)
    fl = fme.uv_layers.new()
    for poly in fme.polygons:
        for li in poly.loop_indices:
            fl.data[li].uv = fuv[fme.loops[li].vertex_index]
    fme.materials.append(frond)
    fronds = bpy.data.objects.new("Fronds", fme)
    bpy.context.scene.collection.objects.link(fronds)
    return [trunk, fronds], Vector((lean + 4, 8, height + 1))


argv = sys.argv[sys.argv.index("--") + 1:]
SRC = argv[0]
PREV = argv[argv.index("--preview") + 1] if "--preview" in argv else None
for pid, (h, lean, seed) in {"palm_01": (8.5, 1.4, 1), "palm_02": (6.5, 0.8, 2), "palm_03": (10.0, 2.2, 3)}.items():
    clear()
    objs, size = build_palm(pid, h, lean, seed)
    export(pid, objs)
    print(pid, "built")
    if PREV:
        os.makedirs(PREV, exist_ok=True)
        preview(pid, size, PREV)
for pid, budget in PROPS.items():
    clear()
    meshes, before, after, size = prepare(pid, budget)
    export(pid, meshes)
    print(pid, before, "->", after, "tris, size", [round(x, 2) for x in size])
    if PREV:
        os.makedirs(PREV, exist_ok=True)
        preview(pid, size, PREV)
