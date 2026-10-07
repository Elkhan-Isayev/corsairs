"""Prepares the Poly Haven ship models (CC0, polyhaven.com) for the game.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P tools/blender/import_ships.py -- SRC_DIR

SRC_DIR holds one folder per model with Poly Haven's 2k glTF download
(api.polyhaven.com/files/<id> → gltf → 2k). For each model this script:

- turns the bow to Godot -Z, centres the hull and keeps the waterline at y=0;
- splits the sails into one node per sail ("Sail_<n>", origin on the yard,
  so scaling local Y furls it) and adds a "Flag" on the ensign staff and a
  "Pennant" at the main truck;
- samples the deck height and hull half-width along the hull into
  assets/ships/<id>.json, which scripts/ship_visual.gd uses to place the
  crew, boarders and gun smoke;
- exports assets/ships/<id>.gltf with textures downsized for the web.

It also renders the nation ensigns (assets/ships/nations/<nation>_flag.jpg)
from the Higgsfield heraldry in tools/blender/textures/.
"""

import glob
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "ships")
SRC_TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")
MODELS = ["dutch_ship_medium", "dutch_ship_large_01", "dutch_ship_large_02", "ship_pinnace"]
SAMPLES = 41
# Max texture edge per map; the hull's colour map keeps more detail.
TEX_MAX = {"hull_diff": 2048, "default": 1024}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for item in list(coll):
            coll.remove(item)


def bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    return (Vector([min(p[i] for p in pts) for i in range(3)]),
            Vector([max(p[i] for p in pts) for i in range(3)]))


def orient(model_id):
    """Rotate/translate everything so the bow points +Y (Godot -Z), hull centred."""
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    hull = [o for o in meshes if o.name.endswith("_hull")][0]
    rig = [o for o in meshes if o.name.endswith("_rigging")][0]
    hmn, hmx = bounds([hull])
    rmn, rmx = bounds([rig])
    ext = hmx - hmn
    axis = 0 if ext.x > ext.y else 1
    # The bowsprit pokes far past the hull at the bow end.
    bow_positive = (rmx[axis] - hmx[axis]) > (hmn[axis] - rmn[axis])
    angle = {(0, True): math.pi / 2, (0, False): -math.pi / 2,
             (1, True): 0.0, (1, False): math.pi}[(axis, bow_positive)]
    centre = (hmn + hmx) / 2
    xf = Matrix.Rotation(angle, 4, "Z") @ Matrix.Translation(Vector((-centre.x, -centre.y, 0)))
    for o in meshes:
        o.matrix_world = xf @ o.matrix_world
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return meshes


def split_sails(sails):
    """One object per loose sail, origin at its top edge."""
    bpy.ops.object.select_all(action="DESELECT")
    sails.select_set(True)
    bpy.context.view_layer.objects.active = sails
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="LOOSE")
    bpy.ops.object.mode_set(mode="OBJECT")
    parts = [o for o in bpy.context.selected_objects]
    # Order fore → aft, low → high for stable names.
    def key(o):
        mn, mx = bounds([o])
        return (-round((mn.y + mx.y) / 2, 1), mn.z)
    parts.sort(key=key)
    for i, o in enumerate(parts):
        mn, mx = bounds([o])
        top = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mx.z))
        o.data.transform(Matrix.Translation(-top))
        o.location = top
        o.name = "Sail_%d" % i
    return parts


def flag_mesh(name, origin, width, height, mat):
    """A gently waving flag flying aft (Godot +Z = Blender -Y) from `origin`."""
    me = bpy.data.meshes.new(name)
    cols, rows = 8, 4
    verts, faces, uvs = [], [], []
    for j in range(rows + 1):
        for i in range(cols + 1):
            u, v = i / cols, j / rows
            verts.append((math.sin(u * 5.0 + v) * 0.08 * width * u, -u * width, -v * height))
    for j in range(rows):
        for i in range(cols):
            a = j * (cols + 1) + i
            faces.append((a, a + 1, a + cols + 2, a + cols + 1))
    me.from_pydata(verts, [], faces)
    uv = me.uv_layers.new()
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            i, j = vi % (cols + 1), vi // (cols + 1)
            uv.data[li].uv = (i / cols, 1.0 - j / rows)
    me.materials.append(mat)
    o = bpy.data.objects.new(name, me)
    o.location = origin
    bpy.context.scene.collection.objects.link(o)
    return o


def add_flags(meshes):
    rig = [o for o in meshes if o.name.endswith("_rigging")][0]
    hull = [o for o in meshes if o.name.endswith("_hull")][0]
    hmn, hmx = bounds([hull])
    co = np.array([v.co[:] for v in rig.data.vertices])
    # Ensign staff: the highest rigging point over the last stretch of the stern.
    stern = co[co[:, 1] < hmn.y + (hmx.y - hmn.y) * 0.06]
    staff = stern[np.argmax(stern[:, 2])]
    truck = co[np.argmax(co[:, 2])]
    mat = bpy.data.materials.new("flag")
    mat.use_nodes = True
    L = hmx.y - hmn.y
    flag = flag_mesh("Flag", Vector(staff) + Vector((0, 0, -0.1)), L * 0.11, L * 0.07, mat)
    pennant = flag_mesh("Pennant", Vector(truck) + Vector((0, 0, -0.1)), L * 0.16, L * 0.012, mat)
    return [flag, pennant]


def profile(meshes):
    """Deck height (first downward hit on the hull/decks) and hull half-width
    at the deck, sampled bow (t=0) → stern (t=1)."""
    solid = [o for o in meshes if any(o.name.endswith(s) for s in ("_hull", "_deck", "_aft"))]
    bm = bmesh.new()
    for o in solid:
        tmp = bmesh.new()
        tmp.from_mesh(o.data)
        tmp.transform(o.matrix_world)
        me = bpy.data.meshes.new("tmp")
        tmp.to_mesh(me)
        bm.from_mesh(me)
        bpy.data.meshes.remove(me)
        tmp.free()
    bvh = BVHTree.FromBMesh(bm)
    hull = [o for o in meshes if o.name.endswith("_hull")][0]
    hmn, hmx = bounds([hull])
    deck, half = [], []
    for k in range(SAMPLES):
        t = k / (SAMPLES - 1)
        y = hmx.y - t * (hmx.y - hmn.y)
        hit = bvh.ray_cast(Vector((0, y, 60)), Vector((0, 0, -1)))
        d = hit[0].z if hit[0] is not None else 0.0
        w = 0.0
        hit2 = bvh.ray_cast(Vector((30, y, d - 0.4)), Vector((-1, 0, 0)))
        if hit2[0] is not None:
            w = hit2[0].x
        deck.append(round(max(d, 0.0), 3))
        half.append(round(max(w, 0.0), 3))
    bm.free()
    return {"length": round(hmx.y - hmn.y, 3), "deck": smooth(deck), "half": smooth(half)}


def smooth(vals, win=5):
    """Fill misses (0) from neighbours, then a running median: hatches,
    gratings and gun carriages shouldn't make the deck jump."""
    v = np.array(vals, dtype=float)
    good = v > 0.05
    idx = np.arange(len(v))
    v = np.interp(idx, idx[good], v[good])
    out = [float(np.median(v[max(0, i - win // 2):i + win // 2 + 1])) for i in range(len(v))]
    return [round(x, 3) for x in out]


def shrink_textures():
    for img in bpy.data.images:
        if img.size[0] == 0:
            continue
        cap = TEX_MAX["hull_diff"] if img.name.endswith("hull_diff") or "hull_diff" in img.name else TEX_MAX["default"]
        if img.size[0] > cap:
            img.scale(cap, int(cap * img.size[1] / img.size[0]))


def export(model_id, objs):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT_DIR, model_id + ".gltf")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
        use_selection=True, export_image_format="AUTO", export_yup=True,
        export_apply=True, export_animations=False, export_cameras=False, export_lights=False)
    return path


# --- nation ensigns -------------------------------------------------------

def load_src(name):
    im = bpy.data.images.load(os.path.join(SRC_TEX, name + ".png"))
    w, h = im.size
    a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(im)
    return a


def resample(a, h, w):
    H, W = a.shape[:2]
    ys = np.clip((np.arange(h) + 0.5) * H / h, 0, H - 1).astype(int)
    xs = np.clip((np.arange(w) + 0.5) * W / w, 0, W - 1).astype(int)
    return a[ys][:, xs]


def emblem(nation, size):
    e = load_src(nation + "_emblem").copy()
    if e[..., 3].mean() > 0.95:          # flat background → key out by saturation
        mx, mn = e[..., :3].max(axis=2), e[..., :3].min(axis=2)
        e[..., 3] = np.clip(((mx - mn) / np.maximum(mx, 1e-3) - 0.22) * 5.0, 0, 1)
    return resample(e, size, size)


def hexcol(h):
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def build_flags():
    out = os.path.join(OUT_DIR, "nations")
    os.makedirs(out, exist_ok=True)
    canvas = load_src("canvas")
    for nation in ("england", "france", "spain", "holland", "pirates"):
        w, h = 256, 160
        yy, xx = np.mgrid[0:h, 0:w]
        rgb = np.ones((h, w, 3), np.float32) * hexcol("f2efe6")
        mark = None
        if nation == "england":
            rgb[(np.abs(yy - h / 2) < h * 0.1) | (np.abs(xx - w / 2) < h * 0.1)] = hexcol("c8202a")
        elif nation == "holland":
            rgb[yy >= h * 2 / 3] = hexcol("ae1c28")
            rgb[yy < h / 3] = hexcol("21468b")
        elif nation == "pirates":
            rgb[:] = hexcol("141414")
            mark = "pirates"
        else:
            mark = nation
        if mark:
            es = int(h * 0.82)
            em = emblem(mark, es)
            y0, x0 = (h - es) // 2, (w - es) // 2
            a = em[..., 3:4]
            rgb[y0:y0 + es, x0:x0 + es] = rgb[y0:y0 + es, x0:x0 + es] * (1 - a) + em[..., :3] * a
        lum = resample(canvas, h, w)[..., :3].mean(axis=2)
        rgb *= (0.8 + 0.35 * lum / lum.mean())[..., None]
        img = bpy.data.images.new(nation + "_flag", w, h)
        img.pixels.foreach_set(np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1), np.float32)], 2).ravel())
        img.filepath_raw = os.path.join(out, nation + "_flag.jpg")
        img.file_format = "JPEG"
        img.save()
        bpy.data.images.remove(img)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    src = argv[0]
    profiles = {}
    for model_id in MODELS:
        clear()
        bpy.ops.import_scene.gltf(filepath=glob.glob(os.path.join(src, model_id, "*.gltf"))[0])
        meshes = orient(model_id)
        prof = profile(meshes)
        sails = [o for o in meshes if o.name.endswith("_sails")][0]
        parts = split_sails(sails)
        flags = add_flags(meshes)
        shrink_textures()
        objs = [o for o in meshes if o != sails] + parts + flags
        path = export(model_id, objs)
        with open(os.path.join(OUT_DIR, model_id + ".json"), "w") as f:
            json.dump(prof, f)
        profiles[model_id] = prof
        print(model_id, "len", prof["length"], "sails", len(parts), "->", path)
    clear()
    build_flags()


main()
