"""Builds every ship class as a glTF model with Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_ships.py \
        -- [--only brig,frigate] [--preview DIR] [--no-export]

Writes assets/ships/<type>.gltf (+ .bin, textures/*.jpg). Every hull is built at MODEL_LENGTH metres
and scaled at runtime by scripts/ship_visual.gd, which keeps the same deck
measurements (beam, depth, deck sheer, half-width) for crew and boarding —
keep half_width/deck_y/bottom_y here in sync with that script.

Everything is generated: lofted hull from station curves, textures painted
with numpy (planking, liveries, copper sheathing, sailcloth), gunports with
open lids, carved stern galleries, masts, yards, sails and rigging.

Node contract read by ship_visual.gd:
  Sail_*        sail meshes, origin on the yard; scaling local Y furls them
  Flag, Pennant flag meshes, origin at the hoist; recolored per nation
  Muzzle_P_*, Muzzle_S_*   empties where broadside smoke spawns
"""

import math
import os
import sys
import zlib

import bpy
import numpy as np
from mathutils import Matrix, Vector

MODEL_LENGTH = 30.0
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "ships")
TMP_DIR = os.path.join(os.environ.get("TMPDIR", "/tmp"), "corsairs_ship_tex")
# Source art generated with Higgsfield: heraldic emblems, sailcloth, planking.
SRC_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")
NATION_DIR = os.path.join(OUT_DIR, "nations")

# Sailcloth per nation (sails are recolored at runtime by ship_visual.gd).
NATION_SAILS = {
    "england": "e9e2cf", "france": "2c3d6b", "spain": "efe9d8",
    "holland": "e6d6b6", "pirates": "2a2522",
}

# Mirrors PROFILES in the old procedural builder: masts, gun rows, square
# sail tiers, stern castle stages, lateen rig, rank (sets the gun count) and
# a historical livery.
PROFILES = {
    "tartane": {"masts": 1, "rows": 0, "tiers": 0, "castle": 0, "lateen": True, "rank": 7,
        "livery": {"bottom": "d8d2c0", "wale": "6b4f30", "upper": "5a3f26",
            "band": "c9b891", "lid": "1a140e", "trim": "8a6a40", "sail": "a5502f"}},
    "lugger": {"masts": 2, "rows": 1, "tiers": 0, "castle": 0, "lateen": True, "rank": 7,
        "livery": {"bottom": "d8d2c0", "wale": "2e241b", "upper": "3a2c1f",
            "band": "cfc4a6", "lid": "16110c", "trim": "8a6a40", "sail": "a5502f"}},
    "sloop": {"masts": 2, "rows": 1, "tiers": 2, "castle": 0, "lateen": False, "rank": 6,
        "livery": {"bottom": "d8d2c0", "wale": "8a6a43", "upper": "2f4f6a",
            "band": "e8e0c8", "lid": "1a140e", "trim": "caa14e", "sail": "ded5b8"}},
    "schooner": {"masts": 2, "rows": 1, "tiers": 2, "castle": 0, "lateen": False, "rank": 6,
        "livery": {"bottom": "9a5b3c", "wale": "15120e", "upper": "1d1a15",
            "band": "e8e0c8", "lid": "0d0b08", "trim": "b89a5a", "sail": "e6dfc8"}},
    "barque": {"masts": 3, "rows": 1, "tiers": 2, "castle": 1, "lateen": False, "rank": 5,
        "livery": {"bottom": "d8d2c0", "wale": "4a3826", "upper": "2f4a35",
            "band": "d9cfa8", "lid": "12100c", "trim": "caa14e", "sail": "dbd2b6"}},
    "brig": {"masts": 2, "rows": 1, "tiers": 3, "castle": 1, "lateen": False, "rank": 5,
        "livery": {"bottom": "9a5b3c", "wale": "1c1610", "upper": "1d1813",
            "band": "c9a54f", "lid": "0d0b08", "trim": "caa14e", "sail": "dbd2b6"}},
    "galleon": {"masts": 3, "rows": 2, "tiers": 3, "castle": 2, "lateen": False, "rank": 4,
        "livery": {"bottom": "d8d2c0", "wale": "6a4b2b", "upper": "7a2020",
            "band": "d4af37", "lid": "3a2416", "trim": "d4af37", "sail": "e2d9bd"}},
    "corvette": {"masts": 3, "rows": 1, "tiers": 3, "castle": 1, "lateen": False, "rank": 3,
        "livery": {"bottom": "9a5b3c", "wale": "20242e", "upper": "1f2f5c",
            "band": "e5e0d0", "lid": "12141c", "trim": "d4af37", "sail": "e6dfc8"}},
    "frigate": {"masts": 3, "rows": 2, "tiers": 3, "castle": 1, "lateen": False, "rank": 2,
        "livery": {"bottom": "9a5b3c", "wale": "141210", "upper": "17140f",
            "band": "d9b96a", "lid": "0b0906", "trim": "c9a54f", "sail": "e0d8bd"}},
    "battleship": {"masts": 3, "rows": 2, "tiers": 4, "castle": 2, "lateen": False, "rank": 1,
        "livery": {"bottom": "9a5b3c", "wale": "141210", "upper": "15130e",
            "band": "c9a54f", "lid": "0a0806", "trim": "d4af37", "sail": "e0d8bd"}},
    # Sea Dogs look: light oak planking, verdigris-teal upperworks, gilt.
    "manowar": {"masts": 3, "rows": 3, "tiers": 4, "castle": 2, "lateen": False, "rank": 1,
        "livery": {"bottom": "d8d2c0", "wale": "a8854e", "topside": "c9a866",
            "upper": "3f7d74", "band": "b9955f", "lid": "7a4526",
            "trim": "d4af37", "sail": "e0d8c4"}},
}


# --------------------------------------------------------------------------
# Small math helpers. Geometry is written in Godot axes (Y up, bow at -Z,
# starboard +X) and converted to Blender axes only when a mesh is created.

def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def to_bl(p):
    return Vector((p[0], -p[2], p[1]))


def hexcol(h, k=1.0):
    h = h.lstrip("#")
    return [min(int(h[i:i + 2], 16) / 255.0 * k, 1.0) for i in (0, 2, 4)]


def to_linear(c):
    """sRGB colour (0..1) to the linear values Blender and glTF factors expect."""
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


def interp_curve(pts, x):
    """Cubic Hermite through (x, y) control points with finite-difference tangents."""
    if x <= pts[0][0]:
        return pts[0][1]
    if x >= pts[-1][0]:
        return pts[-1][1]
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        if x <= x1:
            def slope(j):
                a = pts[max(j - 1, 0)]
                b = pts[min(j + 1, len(pts) - 1)]
                return (b[1] - a[1]) / (b[0] - a[0])
            h = x1 - x0
            t = (x - x0) / h
            m0 = slope(i) * h
            m1 = slope(i + 1) * h
            t2, t3 = t * t, t * t * t
            return ((2 * t3 - 3 * t2 + 1) * y0 + (t3 - 2 * t2 + t) * m0
                    + (-2 * t3 + 3 * t2) * y1 + (t3 - t2) * m1)
    return pts[-1][1]


def frame_for(tangent):
    """Two unit vectors perpendicular to `tangent`."""
    t = tangent.normalized()
    ref = Vector((0, 1, 0)) if abs(t.y) < 0.9 else Vector((1, 0, 0))
    a = t.cross(ref).normalized()
    b = t.cross(a).normalized()
    return a, b


# --------------------------------------------------------------------------
# Mesh builder: accumulates faces per material, then emits one bpy object.

class MeshBuilder:
    def __init__(self):
        self.verts = []
        self.faces = []   # (vertex indices, uvs or None, material name, smooth)

    def v(self, p):
        self.verts.append(Vector(p))
        return len(self.verts) - 1

    def face(self, idx, mat, uvs=None, smooth=False):
        self.faces.append((idx, uvs, mat, smooth))

    def quad(self, a, b, c, d, mat, uvs=None, smooth=False):
        self.face([self.v(a), self.v(b), self.v(c), self.v(d)], mat, uvs, smooth)

    def grid(self, rows, mat, uv_rows=None, smooth=True, closed_u=False):
        """rows: list of lists of points (v-major). Quads between neighbours."""
        idx = [[self.v(p) for p in row] for row in rows]
        nv = len(rows)
        nu = len(rows[0])
        for j in range(nv - 1):
            for i in range(nu - 1 + (1 if closed_u else 0)):
                i1 = (i + 1) % nu
                f = [idx[j][i], idx[j][i1], idx[j + 1][i1], idx[j + 1][i]]
                uvs = None
                if uv_rows is not None:
                    uvs = [uv_rows[j][i], uv_rows[j][i1 if not closed_u or i1 else nu],
                           uv_rows[j + 1][i1 if not closed_u or i1 else nu], uv_rows[j + 1][i]]
                self.face(f, mat, uvs, smooth)

    def box(self, center, size, mat, axes=None, smooth=False):
        """Oriented box. axes = (x, y, z) unit vectors; size along each."""
        ax = axes or (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
        c = Vector(center)
        hx, hy, hz = (ax[0] * size[0] / 2, ax[1] * size[1] / 2, ax[2] * size[2] / 2)
        p = [c + sx * hx + sy * hy + sz * hz
             for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
        # index = (sx>0)*4 + (sy>0)*2 + (sz>0)
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], mat, smooth=smooth)

    def tube(self, pts, radii, mat, sides=6, caps=False, smooth=True, scale_xy=None):
        """Generalised cylinder along a polyline (parallel-transported frame)."""
        if not isinstance(radii, (list, tuple)):
            radii = [radii] * len(pts)
        pts = [Vector(p) for p in pts]
        tangents = []
        for i in range(len(pts)):
            a = pts[max(i - 1, 0)]
            b = pts[min(i + 1, len(pts) - 1)]
            tangents.append((b - a).normalized())
        n1, n2 = frame_for(tangents[0])
        rings = []
        for i, p in enumerate(pts):
            if i > 0:
                # Parallel transport: remove the tangent component.
                n1 = (n1 - tangents[i] * n1.dot(tangents[i])).normalized()
                n2 = tangents[i].cross(n1).normalized()
            sx, sy = scale_xy[i] if scale_xy else (1.0, 1.0)
            ring = []
            for s in range(sides):
                ang = 2 * math.pi * s / sides
                ring.append(p + (n1 * math.cos(ang) * sx + n2 * math.sin(ang) * sy) * radii[i])
            rings.append(ring)
        self.grid(rings, mat, smooth=smooth, closed_u=True)
        if caps:
            self.face([self.v(q) for q in reversed(rings[0])], mat)
            self.face([self.v(q) for q in rings[-1]], mat)

    def cyl(self, a, b, r1, r2, mat, sides=8, caps=True, smooth=True):
        self.tube([a, b], [r1, r2], mat, sides, caps, smooth)

    def sphere(self, center, r, mat, segs=10, rings=6, scale=(1, 1, 1)):
        c = Vector(center)
        rows = []
        for j in range(rings + 1):
            th = math.pi * j / rings
            row = []
            for i in range(segs):
                ph = 2 * math.pi * i / segs
                row.append(c + Vector((math.sin(th) * math.cos(ph) * r * scale[0],
                                       -math.cos(th) * r * scale[1],
                                       math.sin(th) * math.sin(ph) * r * scale[2])))
            rows.append(row)
        self.grid(rows, mat, smooth=True, closed_u=True)

    def build(self, name, materials, origin=(0, 0, 0), tri_counter=None):
        """Create the bpy object. Vertices are relative to `origin` (Godot axes)."""
        if not self.faces:
            return None
        org = Vector(origin)
        mesh = bpy.data.meshes.new(name)
        verts = [to_bl(p - org) for p in self.verts]
        polys = [f[0] for f in self.faces]
        mesh.from_pydata(verts, [], polys)
        mesh.update()
        mat_names = []
        for f in self.faces:
            if f[2] not in mat_names:
                mat_names.append(f[2])
        for m in mat_names:
            mesh.materials.append(materials[m])
        mesh.polygons.foreach_set("material_index", [mat_names.index(f[2]) for f in self.faces])
        mesh.polygons.foreach_set("use_smooth", [f[3] for f in self.faces])
        # UVs: explicit where given, otherwise box-projected in metres.
        uv = mesh.uv_layers.new(name="UVMap")
        loop_uvs = []
        for fi, f in enumerate(self.faces):
            if f[1] is not None:
                loop_uvs.extend(f[1])
                continue
            pts = [self.verts[i] for i in f[0]]
            n = Vector((0, 0, 0))
            for k in range(len(pts)):
                n += pts[k].cross(pts[(k + 1) % len(pts)])
            ax = max(range(3), key=lambda a: abs(n[a]))
            for p in pts:
                if ax == 0:
                    loop_uvs.append((p.z / 2.0, p.y / 2.0))
                elif ax == 1:
                    loop_uvs.append((p.z / 2.0, p.x / 2.0))
                else:
                    loop_uvs.append((p.x / 2.0, p.y / 2.0))
        flat = [c for u in loop_uvs for c in u]
        uv.data.foreach_set("uv", flat)
        mesh.validate(clean_customdata=False)
        obj = bpy.data.objects.new(name, mesh)
        obj.location = to_bl(org)
        bpy.context.scene.collection.objects.link(obj)
        if tri_counter is not None:
            tri_counter[0] += sum(len(f[0]) - 2 for f in self.faces)
        return obj


# --------------------------------------------------------------------------
# Procedural textures (numpy, sRGB floats).

def _noise1(n, scale, rng):
    """Smooth 1-D value noise of length n."""
    k = max(int(n / scale) + 2, 2)
    pts = rng.random(k)
    x = np.linspace(0, k - 1.001, n)
    i = x.astype(int)
    f = x - i
    f = f * f * (3 - 2 * f)
    return pts[i] * (1 - f) + pts[i + 1] * f


def _noise2(h, w, sy, sx, rng):
    ky, kx = max(int(h / sy) + 2, 2), max(int(w / sx) + 2, 2)
    g = rng.random((ky, kx))
    y = np.linspace(0, ky - 1.001, h)
    x = np.linspace(0, kx - 1.001, w)
    iy, ix = y.astype(int), x.astype(int)
    fy, fx = y - iy, x - ix
    fy = (fy * fy * (3 - 2 * fy))[:, None]
    fx = (fx * fx * (3 - 2 * fx))[None, :]
    a = g[iy][:, ix]
    b = g[iy][:, ix + 1]
    c = g[iy + 1][:, ix]
    d = g[iy + 1][:, ix + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def planks(h, w, n_planks, butt_len_px, rng, seam=0.55, var=0.10):
    """Grayscale plank field (1 = plain wood). Planks run along x."""
    img = np.ones((h, w), dtype=np.float32)
    ph = h / n_planks
    rows = np.arange(h)
    plank_id = (rows / ph).astype(int)
    tone = 1.0 + (rng.random(n_planks + 1) - 0.5) * 2 * var
    img *= tone[plank_id][:, None]
    # Butt joints, staggered per plank, each piece its own tone.
    cols = np.arange(w)
    offs = rng.random(n_planks + 1) * butt_len_px
    piece = ((cols[None, :] + offs[plank_id][:, None]) / butt_len_px).astype(int)
    piece_tone = 1.0 + (rng.random((n_planks + 1, w // max(int(butt_len_px), 1) + 3)) - 0.5) * var
    img *= piece_tone[plank_id[:, None], np.minimum(piece, piece_tone.shape[1] - 1)]
    butt = ((cols[None, :] + offs[plank_id][:, None]) % butt_len_px) < 1.5
    img[butt] *= seam
    seam_rows = (rows % ph) < max(1.0, ph * 0.06)
    img[seam_rows, :] *= seam
    # Grain: streaks stretched along the planks.
    grain = _noise2(h, w, 2.0, 60.0, rng)
    img *= 0.92 + 0.16 * grain
    return np.clip(img, 0, 1.3)


def to_rgba(gray, color):
    c = np.array(color, dtype=np.float32)
    rgb = np.clip(gray[..., None] * c[None, None, :], 0, 1)
    a = np.ones(gray.shape + (1,), dtype=np.float32)
    return np.concatenate([rgb, a], axis=2)


_src_cache = {}


def load_src(name):
    """RGBA float array (bottom-up rows, like Blender) of a source texture."""
    if name not in _src_cache:
        im = bpy.data.images.load(os.path.join(SRC_DIR, name + ".png"))
        w, h = im.size
        a = np.array(im.pixels[:], dtype=np.float32).reshape(h, w, 4)
        bpy.data.images.remove(im)
        _src_cache[name] = a
    return _src_cache[name]


def resample(a, h, w):
    """Bilinear resize of an (H, W, C) array."""
    H, W = a.shape[:2]
    y = np.clip((np.arange(h) + 0.5) * H / h - 0.5, 0, H - 1)
    x = np.clip((np.arange(w) + 0.5) * W / w - 0.5, 0, W - 1)
    y0, x0 = y.astype(int), x.astype(int)
    y1, x1 = np.minimum(y0 + 1, H - 1), np.minimum(x0 + 1, W - 1)
    fy, fx = (y - y0)[:, None, None], (x - x0)[None, :, None]
    return ((a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx) * (1 - fy)
            + (a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx) * fy)


def detail(name, h, w, tiles_y, tiles_x, contrast=1.0):
    """Luminance of a tileable source repeated over (h, w), mean 1."""
    src = load_src(name)
    lum = (src[..., 0] * 0.3 + src[..., 1] * 0.59 + src[..., 2] * 0.11)[..., None]
    th = max(int(round(h / tiles_y)), 1)
    tw = max(int(round(w / tiles_x)), 1)
    tile = resample(lum, th, tw)[..., 0]
    out = np.tile(tile, (int(np.ceil(h / th)), int(np.ceil(w / tw))))[:h, :w]
    out = out / max(out.mean(), 1e-3)
    return 1.0 + (out - 1.0) * contrast


def emblem_rgba(nation, size):
    """Emblem art with alpha; flat cloth backgrounds are keyed out by saturation."""
    e = load_src(nation + "_emblem").copy()
    if e[..., 3].mean() > 0.95:
        mx, mn = e[..., :3].max(axis=2), e[..., :3].min(axis=2)
        sat = (mx - mn) / np.maximum(mx, 1e-3)
        e[..., 3] = np.clip((sat - 0.22) * 5.0, 0, 1)
    return resample(e, size, size)


def sail_cloth(color, nation=None, size=512):
    """Sailcloth: Higgsfield canvas tinted, darkened at the edges, optional emblem."""
    g = detail("canvas", size, size, 1, 1, contrast=0.7)
    yy, xx = np.mgrid[0:size, 0:size] / (size - 1.0)
    edge = np.minimum(np.minimum(xx, 1 - xx), np.minimum(yy, 1 - yy))
    g *= 0.78 + 0.22 * np.clip(edge * 9.0, 0, 1)          # sun-faded centre, grimy edges
    b = max(size // 128, 2)
    g[:, :b] *= 0.65
    g[:, -b:] *= 0.65
    g[:b, :] *= 0.65
    g[-b:, :] *= 0.7
    for rv in (0.86, 0.74):                                 # reef bands near the head
        r = int(rv * size)
        g[r - 1:r + 1, :] *= 0.75
        g[r - 4:r - 2, (np.arange(size) % 14) < 2] *= 0.55
    g *= 0.92 + 0.1 * np.clip(yy * 1.5, 0, 1)               # weathering toward the foot
    rgb = np.clip(g[..., None] * np.array(hexcol(color))[None, None, :] * 1.05, 0, 1)
    if nation is not None:
        es = int(size * 0.56)
        em = emblem_rgba(nation, es)
        y0 = int(size * 0.44 - es / 2)
        x0 = (size - es) // 2
        a = em[..., 3:4] * 0.95
        region = rgb[y0:y0 + es, x0:x0 + es]
        shade = g[y0:y0 + es, x0:x0 + es, None]
        rgb[y0:y0 + es, x0:x0 + es] = region * (1 - a) + np.clip(em[..., :3] * shade, 0, 1) * a
    return np.concatenate([rgb, np.ones((size, size, 1), np.float32)], axis=2)


def flag_cloth(nation, w=256, h=160):
    yy, xx = np.mgrid[0:h, 0:w]
    rgb = np.ones((h, w, 3), np.float32) * np.array(hexcol("f2efe6"))
    emblem = None
    if nation == "england":
        bar = (np.abs(yy - h / 2) < h * 0.1) | (np.abs(xx - w / 2) < h * 0.1)
        rgb[bar] = hexcol("c8202a")
    elif nation == "holland":
        rgb[yy >= h * 2 / 3] = hexcol("ae1c28")             # rows run bottom-up
        rgb[yy < h / 3] = hexcol("21468b")
    elif nation == "pirates":
        rgb[:] = hexcol("141414")
        emblem = "pirates"
    else:
        emblem = nation
    if emblem:
        es = int(h * 0.82)
        em = emblem_rgba(emblem, es)
        y0, x0 = (h - es) // 2, (w - es) // 2
        a = em[..., 3:4]
        rgb[y0:y0 + es, x0:x0 + es] = rgb[y0:y0 + es, x0:x0 + es] * (1 - a) + em[..., :3] * a
    rgb *= detail("canvas", h, w, 1, 1.6, contrast=0.35)[..., None]
    return np.concatenate([np.clip(rgb, 0, 1), np.ones((h, w, 1), np.float32)], axis=2)


def save_texture(path, rgba, fmt="JPEG"):
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(os.path.basename(path), w, h, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    img.filepath_raw = path
    img.file_format = fmt
    img.save()
    bpy.data.images.remove(img)


def build_nation_textures():
    os.makedirs(NATION_DIR, exist_ok=True)
    for nation, color in NATION_SAILS.items():
        save_texture(os.path.join(NATION_DIR, f"{nation}_sail.jpg"), sail_cloth(color))
        save_texture(os.path.join(NATION_DIR, f"{nation}_sail_emblem.jpg"), sail_cloth(color, nation))
        save_texture(os.path.join(NATION_DIR, f"{nation}_flag.jpg"), flag_cloth(nation))


def make_image(name, rgba):
    os.makedirs(TMP_DIR, exist_ok=True)
    h, w = rgba.shape[:2]
    img = bpy.data.images.new(name, w, h, alpha=False)
    img.pixels.foreach_set(rgba.astype(np.float32).ravel())
    path = os.path.join(TMP_DIR, name + ".png")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


# --------------------------------------------------------------------------

class ShipBuilder:
    def __init__(self, type_id):
        self.type_id = type_id
        p = PROFILES[type_id]
        self.p = p
        self.lv = p["livery"]
        self.L = MODEL_LENGTH
        self.rows = p["rows"]
        self.castle = p["castle"]
        self.beam = self.L * (0.26 + 0.014 * self.rows)
        self.depth = self.L * (0.115 + 0.020 * max(self.rows - 1, 0))
        self.class_len = 18.0 + (8 - p["rank"]) * 5.0
        self.rng = np.random.default_rng(zlib.crc32(type_id.encode()))
        self.body = MeshBuilder()
        self.extra_objs = []
        self.tris = [0]
        self.muzzles = {-1: [], 1: []}
        self.mats = {}

    # --- hull measures (shared contract with ship_visual.gd) ---

    def half_width(self, t):
        if t < 0.36:
            w = 1.0 - (1.0 - t / 0.36) ** 2.4
        elif t < 0.70:
            w = 1.0
        else:
            w = 1.0 - 0.38 * smoothstep(0.70, 1.0, t)
        return self.beam * 0.5 * max(w, 0.035)

    def deck_y(self, t):
        return self.depth * (0.70 + 0.5 * (abs(t - 0.42) / 0.58) ** 1.8)

    def bottom_y(self, t):
        rise = smoothstep(0.12, 0.0, t) * 0.5 + smoothstep(0.86, 1.0, t) * 0.45
        return -self.depth * 0.85 + self.depth * rise * 0.4

    SECTION = [(0.0, 0.05), (0.04, 0.32), (0.14, 0.64), (0.30, 0.88), (0.48, 0.98),
               (0.64, 1.0), (0.82, 0.975), (1.0, 0.91)]

    def section_x(self, t, f):
        if f <= 1.0:
            xm = interp_curve(self.SECTION, f)
        else:
            xm = 0.91 - 0.10 * (f - 1.0)
        end = 0.65 * (1.0 - smoothstep(0.0, 0.32, t)) + 0.55 * smoothstep(0.72, 1.0, t)
        xm *= 1.0 - end * (1.0 - min(f, 1.0)) ** 1.6
        return self.half_width(t) * xm

    def y_at(self, t, f):
        yb = self.bottom_y(t)
        return yb + (self.deck_y(t) - yb) * f

    def f_at(self, t, y):
        yb = self.bottom_y(t)
        return (y - yb) / (self.deck_y(t) - yb)

    def hull_pt(self, t, f, side):
        z = -self.L / 2 + t * self.L
        z += f * self.L * 0.045 * smoothstep(0.88, 1.0, t)               # raked counter
        z -= (max(f, 0.0) ** 1.3) * self.L * 0.035 * (1.0 - smoothstep(0.0, 0.22, t))  # flared bow
        return Vector((side * self.section_x(t, f), self.y_at(t, f), z))

    def hull_normal(self, t, f, side):
        e = 1e-3
        dt = self.hull_pt(min(t + e, 1), f, side) - self.hull_pt(max(t - e, 0), f, side)
        df = self.hull_pt(t, f + e, side) - self.hull_pt(t, f - e, side)
        n = dt.cross(df).normalized()
        if n.x * side < 0:
            n = -n
        return n

    def hull_axes(self, t, f, side):
        """(along hull toward stern, up along the side, outward normal)."""
        n = self.hull_normal(t, f, side)
        e = 1e-3
        along = (self.hull_pt(min(t + e, 1), f, side) - self.hull_pt(max(t - e, 0), f, side)).normalized()
        up = n.cross(along).normalized()
        if up.y < 0:
            up = -up
        along = up.cross(n).normalized()
        if along.z < 0:
            along = -along
        return along, up, n

    # --- materials ---

    def material(self, name, color, rough=0.8, metal=0.0, image=None, emission=None,
                 emit_strength=0.0, double=True):
        m = bpy.data.materials.new(f"{self.type_id}_{name}")
        m.use_nodes = True
        m.use_backface_culling = not double
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        bsdf.inputs["Base Color"].default_value = (*to_linear(color), 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
        if image is not None:
            tex = nt.nodes.new("ShaderNodeTexImage")
            tex.image = image
            nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if emission is not None:
            bsdf.inputs["Emission Color"].default_value = (*to_linear(emission), 1.0)
            bsdf.inputs["Emission Strength"].default_value = emit_strength
        self.mats[name] = m
        return m

    def make_materials(self):
        lv = self.lv
        self.material("hull", (1, 1, 1), 0.72, image=self.hull_texture())
        up = detail("planks", 256, 256, 1, 1, contrast=0.8) * planks(256, 256, 9, 150, self.rng, seam=0.85, var=0.05)
        up_tex = to_rgba(up, hexcol(lv["upper"]))
        self.material("upper", (1, 1, 1), 0.75, image=make_image(f"{self.type_id}_upper", up_tex))
        # One deck texture shared by every ship (fixed seed).
        deck = detail("planks", 256, 256, 1, 1, contrast=0.6) * planks(256, 256, 10, 210, np.random.default_rng(7), seam=0.7, var=0.08)
        yy, xx = np.mgrid[0:256, 0:256]
        nails = (((xx % 52) < 2) & (((yy + 6) % 25) < 2))          # treenails
        deck[nails] *= 0.6
        self.material("deck", (1, 1, 1), 0.85,
                      image=make_image("deck", to_rgba(deck, hexcol("b39468"))))
        self.material("trim", hexcol(lv["trim"], 0.8), 0.45, 0.4)
        self.material("rail", hexcol("3a2817"), 0.75)
        self.material("wale", hexcol(lv["wale"], 0.45), 0.7)
        self.material("dark", hexcol("0c0806"), 0.95)
        self.material("portred", hexcol("4e1610"), 0.85)
        self.material("lid", hexcol(lv["lid"], 0.8), 0.7)
        self.material("iron", hexcol("161514"), 0.5, 0.55)
        self.material("spar", hexcol("3e2b1a"), 0.7)
        self.material("spar_black", hexcol("14100c"), 0.7)
        self.material("rope", hexcol("17120d"), 0.9)
        self.material("grating", hexcol("4a3520"), 0.9)
        self.material("glass", hexcol("23303c"), 0.08, 0.3, emission=hexcol("ffc46a"), emit_strength=0.35)
        self.material("lantern", hexcol("ffe2a0"), 0.3, emission=hexcol("ffb44a"), emit_strength=5.0)
        self.material("sail", (1, 1, 1), 0.95,
                      image=make_image(f"{self.type_id}_sail", self.sail_texture()))
        self.material("flag", (1, 1, 1), 0.9)

    def hull_texture(self):
        """Hull atlas: u = t (bow→stern), v = height fraction keel→deck."""
        W, H = 2048, 512
        lv = self.lv
        rng = self.rng
        n_planks = int(round((self.deck_y(0.5) - self.bottom_y(0.5)) / 0.26))
        span_mid = self.deck_y(0.5) - self.bottom_y(0.5)
        # Higgsfield planking (≈9 planks per tile, tiles ≈2.3 m) under crisp seams.
        gray = detail("planks", H, W, span_mid / 2.3, self.L / 2.3, contrast=0.75) * \
            planks(H, W, n_planks, 160, rng, seam=0.8, var=0.05)
        img = np.zeros((H, W, 3), dtype=np.float32)
        v = (np.arange(H) + 0.5) / H
        ts = (np.arange(W) + 0.5) / W
        bottom = np.array(hexcol(lv["bottom"]))
        wale = np.array(hexcol(lv["wale"]))
        top = np.array(hexcol(lv.get("topside", lv["upper"])))
        band = np.array(hexcol(lv["band"]))
        trim = np.array(hexcol(lv["trim"]))
        copper = lv["bottom"].lower() == "9a5b3c"
        span = np.array([self.deck_y(t) - self.bottom_y(t) for t in ts])
        wl = np.array([self.f_at(t, 0.30) for t in ts])
        top_from = 0.80 if self.rows < 2 else 0.84
        V = v[:, None]
        base = np.where(V < top_from, 1.0, 0.0)[..., None] * wale + \
            np.where(V >= top_from, 1.0, 0.0)[..., None] * top
        img[:] = base
        # Painted bands along every gun deck.
        for fr in self.gun_row_fracs():
            hh = (self.L * 0.024) / span
            m = (np.abs(V - (fr + 0.012)) < hh[None, :])
            img[m] = band
        if self.rows == 0:
            m = np.abs(V - 0.80) < (self.L * 0.008) / span[None, :]
            img[m] = band
        # Gilt strake under the rail and boot-topping at the waterline.
        img[np.abs(V - 0.975) < (0.05 / span)[None, :]] = trim
        boot = (V >= wl[None, :]) & (V < wl[None, :] + 0.18 / span[None, :])
        img[boot] = np.array(hexcol("15110d"))
        under = V < wl[None, :]
        img[under] = bottom
        shade = gray.copy()
        if copper:
            # Copper sheathing: small plates with green patina blotches.
            yy, xx = np.mgrid[0:H, 0:W]
            plate = ((xx % 22) < 1) | ((yy % 14) < 1)
            tone = 1.0 + (rng.random((H // 14 + 1, W // 22 + 1)) - 0.5) * 0.18
            ctone = tone[yy // 14, xx // 22]
            ctone[plate] *= 0.75
            shade = np.where(under, ctone, shade)
            patina = _noise2(H, W, 40, 90, rng)
            pm = (under & (patina > 0.62))[..., None]
            img = np.where(pm, img * 0.55 + np.array(hexcol("4f8a72")) * 0.45, img)
        else:
            dirt = _noise2(H, W, 30, 120, rng)
            shade = np.where(under, shade * (0.85 + 0.2 * dirt) * (0.82 + 0.18 * V / np.maximum(wl[None, :], 0.01)), shade)
        img *= shade[..., None]
        # Weathering: grime streaks running down from each port, faint salt above the waterline.
        streak = _noise2(H, W, 400, 3, rng)
        streak_m = (streak > 0.7) & (~under)
        img[streak_m] *= 0.9
        salt = (V > wl[None, :]) & (V < wl[None, :] + 0.5 / span[None, :])
        img = np.where(salt[..., None], img * 0.9 + 0.08, img)
        rgba = np.concatenate([np.clip(img, 0, 1), np.ones((H, W, 1), np.float32)], axis=2)
        return make_image(f"{self.type_id}_hull", rgba)

    def sail_texture(self):
        S = 256
        rng = self.rng
        g = np.ones((S, S), dtype=np.float32)
        xx = np.arange(S)
        cloths = 12
        cw = S / cloths
        cid = (xx / cw).astype(int)
        g *= (1.0 + (rng.random(cloths + 1) - 0.5) * 0.08)[cid][None, :]
        g[:, (xx % cw) < 1] *= 0.82                              # cloth seams
        g[:, :3] *= 0.75                                         # bolt ropes
        g[:, -3:] *= 0.75
        g[:3, :] *= 0.75
        g[-3:, :] *= 0.78
        for rv in (0.84, 0.70):                                  # reef bands
            r = int(rv * S)
            g[r - 1:r + 1, :] *= 0.8
            dots = (xx % 12) < 2
            g[r - 3:r - 2, dots] *= 0.6
        g *= 0.93 + 0.12 * _noise2(S, S, 40, 40, rng)
        # Weather staining near the foot.
        yy = np.arange(S)[:, None] / S
        g *= 0.9 + 0.1 * np.clip(yy * 1.6, 0, 1)
        return sail_cloth(self.lv["sail"], size=S)

    # --- layout helpers ---

    def gun_row_fracs(self):
        return {0: [], 1: [0.76], 2: [0.64, 0.80]}.get(self.rows, [0.58, 0.73, 0.88])

    def port_count(self):
        return min(max(int(self.class_len / 3.8), 3), 14)

    def mast_positions(self):
        n = self.p["masts"]
        if n == 1:
            return [(0.42, 1.0, True)]
        if n == 2:
            return [(0.24, 0.92, True), (0.60, 1.0, True)]
        return [(0.18, 0.94, True), (0.48, 1.05, True), (0.78, 0.78, False)]

    def sail_tiers(self):
        return {2: [(0.40, 1.0), (0.70, 0.76)],
                4: [(0.36, 1.0), (0.60, 0.84), (0.78, 0.66), (0.92, 0.48)]}.get(
            self.p["tiers"], [(0.40, 1.0), (0.68, 0.82), (0.88, 0.60)])

    def castle_spans(self):
        """[(t0, t1, height above deck at base, stage height)]"""
        spans = []
        qd_h = self.depth * (0.28 + 0.22 * self.castle)
        if self.castle >= 1:
            spans.append(("quarterdeck", 0.70, 1.0, 0.0, qd_h))
            spans.append(("forecastle", 0.02, 0.17, 0.0, self.depth * 0.35))
        else:
            spans.append(("quarterdeck", 0.78, 1.0, 0.0, self.depth * 0.22))
        if self.castle >= 2:
            spans.append(("poop", 0.84, 1.0, qd_h, self.depth * 0.32))
        return spans

    def stern_top(self):
        top = 0.0
        for name, t0, t1, base, h in self.castle_spans():
            if t1 >= 1.0:
                top = max(top, base + h)
        return self.deck_y(1.0) + top

    # --- hull ---

    def build_hull(self):
        b = self.body
        N, M = 72, 26
        ts = [0.5 - 0.5 * math.cos(math.pi * i / N) for i in range(N + 1)]
        fs = [(j / M) ** 1.25 for j in range(M + 1)]
        for side in (-1, 1):
            rows = []
            uvs = []
            for f in fs:
                rows.append([self.hull_pt(t, f, side) for t in ts])
                uvs.append([(t, f) for t in ts])
            if side < 0:
                rows = [list(reversed(r)) for r in rows]
                uvs = [list(reversed(r)) for r in uvs]
            b.grid(rows, "hull", uvs, smooth=True)
        # Deck.
        deck_rows = []
        for t in ts:
            x = self.section_x(t, 1.0)
            y = self.deck_y(t)
            z = self.hull_pt(t, 1.0, 1).z
            deck_rows.append([Vector((-x + k * x / 4, y, z)) for k in range(9)])
        deck_uv = [[(p.z / 4.0, p.x / 4.0) for p in r] for r in deck_rows]
        b.grid(deck_rows, "deck", deck_uv, smooth=False)
        # Bulwarks and castles: the hull side carried up above the deck.
        bh = self.L * 0.028
        self.loft_upper(0.0, 1.0, lambda t: 0.0, lambda t: bh, inner=True)
        for name, t0, t1, base, h in self.castle_spans():
            self.loft_castle(name, t0, t1, base, h)
        # Transom.
        top = self.stern_top() + (0.9 if self.castle else bh)
        f_top = self.f_at(1.0, top)
        fs_t = [j / 20 * f_top for j in range(21)]
        rows = [[self.hull_pt(1.0, f, -1), self.hull_pt(1.0, f, 1)] for f in fs_t]
        b.grid(rows, "upper", smooth=False)
        self.build_keel_and_stem()

    def loft_upper(self, t0, t1, base_fn, h_fn, inner=False, steps=60, rail=True):
        """Upperworks wall following the hull from deck+base to deck+base+h."""
        b = self.body
        ts = [lerp(t0, t1, 0.5 - 0.5 * math.cos(math.pi * i / steps)) for i in range(steps + 1)]
        for side in (-1, 1):
            lo, hi, lo_in, hi_in = [], [], [], []
            for t in ts:
                y0 = self.deck_y(t) + base_fn(t)
                y1 = y0 + h_fn(t)
                p0 = self.hull_pt(t, self.f_at(t, y0), side)
                p1 = self.hull_pt(t, self.f_at(t, y1), side)
                lo.append(p0)
                hi.append(p1)
                inset = Vector((-side * 0.16, 0, 0))
                lo_in.append(p0 + inset)
                hi_in.append(p1 + inset)
            rows = [lo, hi] if side > 0 else [hi, lo]
            b.grid(rows, "upper", smooth=True)
            if inner:
                b.grid([hi_in, lo_in] if side > 0 else [lo_in, hi_in], "upper", smooth=True)
            if rail:
                # Cap rail along the top edge.
                cap = [p + Vector((-side * 0.08, 0.06, 0)) for p in hi]
                b.tube(cap, 0.11, "wale", sides=5, scale_xy=[(1.6, 0.7)] * len(cap))

    def loft_castle(self, name, t0, t1, base, h):
        b = self.body
        self.loft_upper(t0, t1, lambda t: base, lambda t: h, inner=False, steps=16, rail=True)
        # Roof deck.
        steps = 16
        rows = []
        for i in range(steps + 1):
            t = lerp(t0, t1, i / steps)
            y = self.deck_y(t) + base + h
            f = self.f_at(t, y)
            pr = self.hull_pt(t, f, 1)
            rows.append([Vector((lerp(-pr.x, pr.x, k / 6), y, pr.z)) for k in range(7)])
        b.grid(rows, "deck", [[(p.z / 4.0, p.x / 4.0) for p in r] for r in rows], smooth=False)
        # Bulkhead facing the waist, with doors and gilt pilasters.
        tf = t0 if name != "forecastle" else t1
        y0 = self.deck_y(tf) + base
        y1 = y0 + h
        pl = self.hull_pt(tf, self.f_at(tf, y0), 1)
        pu = self.hull_pt(tf, self.f_at(tf, y1), 1)
        b.quad(Vector((-pl.x, y0, pl.z)), Vector((pl.x, y0, pl.z)),
               Vector((pu.x, y1, pu.z)), Vector((-pu.x, y1, pu.z)), "upper")
        dz = -0.05 if name != "forecastle" else 0.05
        ndoor = 2 if pl.x > 2.5 else 1
        for k in range(ndoor):
            dx = 0.0 if ndoor == 1 else (-1 + 2 * k) * pl.x * 0.4
            dh = min(h * 0.75, 1.9)
            if dh > 0.9:
                b.box((dx, y0 + dh / 2, pl.z + dz), (0.9, dh, 0.06), "dark")
                b.box((dx, y0 + dh + 0.08, pl.z + dz * 1.5), (1.1, 0.12, 0.08), "trim")
        for k in range(-2, 3):
            b.box((k * pl.x * 0.45, (y0 + y1) / 2, pl.z + dz * 1.2), (0.12, h, 0.07), "trim")
        # Railing on the roof: posts and a top rail.
        rail_h = 0.85
        for side in (-1, 1):
            top_pts = []
            n = max(int((t1 - t0) * self.L / 0.7), 3)
            for i in range(n + 1):
                t = lerp(t0, t1, i / n)
                y = self.deck_y(t) + base + h
                p = self.hull_pt(t, self.f_at(t, y), side) + Vector((-side * 0.1, 0, 0))
                b.box(p + Vector((0, rail_h / 2, 0)), (0.08, rail_h, 0.08), "rail")
                top_pts.append(p + Vector((0, rail_h, 0)))
            b.tube(top_pts, 0.07, "trim" if self.castle >= 2 else "rail", sides=4)
        if name == "forecastle" or t1 < 1.0:
            return
        # Taffrail across the stern.
        yt = self.deck_y(1.0) + base + h
        pr = self.hull_pt(1.0, self.f_at(1.0, yt), 1)
        pts = [Vector((lerp(-pr.x, pr.x, k / 8), yt + rail_h, pr.z)) for k in range(9)]
        b.tube(pts, 0.07, "trim" if self.castle >= 2 else "rail", sides=4)
        for p in pts:
            b.box(p - Vector((0, rail_h / 2, 0)), (0.08, rail_h, 0.08), "rail")

    def build_keel_and_stem(self):
        b = self.body
        # Keel: a deep timber along the bottom.
        pts, sc = [], []
        for i in range(25):
            t = lerp(0.05, 0.985, i / 24)
            pts.append(Vector((0, self.bottom_y(t) - 0.12, -self.L / 2 + t * self.L)))
            sc.append((0.5, 1.6))
        b.tube(pts, 0.28, "wale", sides=4, smooth=False, scale_xy=sc)
        # Stem and cutwater: sweeps forward from the keel to the figurehead.
        yb = self.bottom_y(0.06)
        head_y = self.deck_y(0.0) * 0.82
        p0 = Vector((0, yb, -self.L / 2 + self.L * 0.06))
        p1 = Vector((0, yb * 0.2, -self.L / 2 - self.L * 0.012))
        p2 = Vector((0, head_y, -self.L / 2 - self.L * 0.055))
        stem = []
        for i in range(13):
            f = i / 12
            stem.append(p0.lerp(p1, f).lerp(p1.lerp(p2, f), f))
        widths = [(0.55, lerp(2.2, 1.2, i / 12)) for i in range(13)]
        b.tube(stem, 0.3, "wale", sides=4, smooth=False, scale_xy=widths)
        self.stem_head = p2
        # Figurehead: a gilt lion leaning out from the stem head.
        fig = p2 + Vector((0, 0.15, -0.55))
        b.sphere(fig, 0.30, "trim", segs=8, rings=6, scale=(0.7, 0.8, 1.6))
        b.sphere(fig + Vector((0, 0.32, -0.4)), 0.21, "trim", segs=8, rings=6)
        # Head rails from the bow sides to the figurehead.
        if self.castle >= 1 or self.rows >= 1:
            for side in (-1, 1):
                for k, f in enumerate((0.80, 0.92)):
                    a = self.hull_pt(0.07, f, side)
                    c = p2 + Vector((0, -0.25 * k, 0.2))
                    mid = a.lerp(c, 0.5) + Vector((side * 0.25, 0.35 - 0.2 * k, 0))
                    rail = [a.lerp(mid, s).lerp(mid.lerp(c, s), s) for s in (0, 0.25, 0.5, 0.75, 1.0)]
                    b.tube(rail, 0.08, "trim", sides=5)
        # Rudder.
        zt = self.hull_pt(1.0, 0.0, 1).z
        ytop = self.y_at(1.0, self.f_at(1.0, 0.8))
        r_pts = [Vector((0, self.bottom_y(1.0) - 0.15, zt + 0.35)), Vector((0, ytop, self.hull_pt(1.0, self.f_at(1.0, 0.8), 1).z + 0.35))]
        b.tube(r_pts, 0.5, "wale", sides=4, smooth=False, scale_xy=[(0.3, 1.6), (0.3, 1.0)])

    # --- sides: wales, ports, channels ---

    def build_wales(self):
        fr = self.gun_row_fracs()
        if fr:
            levels = [fr[0] - 0.075] + [(fr[i] + fr[i + 1]) / 2 for i in range(len(fr) - 1)]
            levels.append(fr[-1] + 0.07)
        else:
            levels = [0.66, 0.86]
        for side in (-1, 1):
            for f in levels:
                if f > 0.96:
                    continue
                pts = []
                for i in range(41):
                    t = lerp(0.035, 0.99, i / 40)
                    pts.append(self.hull_pt(t, f, side) + self.hull_normal(t, f, side) * 0.05)
                self.body.tube(pts, 0.12, "wale", sides=6, scale_xy=[(0.7, 1.4)] * len(pts))

    def build_gunports(self):
        b = self.body
        n = self.port_count()
        s = self.L * (0.030 if self.rows < 3 else 0.025)
        for row, fr in enumerate(self.gun_row_fracs()):
            for side in (-1, 1):
                for i in range(n):
                    t = 0.16 + (i + 0.5) / n * 0.66
                    f = fr
                    p = self.hull_pt(t, f, side)
                    al, up, nrm = self.hull_axes(t, f, side)
                    # Opening, red-painted surround, open lid hinged above.
                    b.box(p + nrm * 0.06, (s, s, 0.05), "dark", axes=(al, up, nrm))
                    th = math.radians(118)
                    hinge = p + up * (s * 0.59) + nrm * 0.08
                    d = (-up * math.cos(th) + nrm * math.sin(th)).normalized()
                    lid_n = al.cross(d).normalized()
                    if lid_n.y < 0:
                        lid_n = -lid_n
                    b.box(hinge + d * (s * 0.55), (s * 1.1, s * 1.1, 0.09), "lid", axes=(al, d, lid_n))
                    b.box(hinge + d * (s * 0.55) - lid_n * 0.05, (s * 0.95, s * 0.95, 0.02), "portred", axes=(al, d, lid_n))
                    # Gun barrel with a muzzle swell.
                    tip = p + nrm * 0.75 + up * (-0.04)
                    b.cyl(p - nrm * 0.2, tip, 0.13, 0.10, "iron", sides=8, caps=False)
                    b.cyl(tip - nrm * 0.12, tip, 0.135, 0.135, "iron", sides=8, caps=True)
                    self.muzzles[side].append(p + nrm * 1.0)

    def build_channels(self):
        """Chainwales with deadeyes; returns shroud anchor points per mast & side."""
        b = self.body
        anchors = {}
        for m, (t, hm, _course) in enumerate(self.mast_positions()):
            for side in (-1, 1):
                f = self.f_at(t, self.deck_y(t) - 0.35)
                pts = []
                span = self.L * (0.10 if m < 2 else 0.07)
                ncount = 4 if self.L * hm > 0 else 3
                for k in range(ncount + 1):
                    tt = t + (k / ncount - 0.5) * span / self.L
                    p = self.hull_pt(tt, f, side)
                    pts.append(p)
                c = pts[len(pts) // 2]
                al, up, nrm = self.hull_axes(t, f, side)
                b.box(c + nrm * 0.45, (span, 0.12, 0.9), "wale", axes=(al, up, nrm))
                sh = []
                for k in range(ncount):
                    tt = t + ((k + 0.5) / ncount - 0.5) * span / self.L
                    p = self.hull_pt(tt, f, side) + nrm * 0.85 + Vector((0, 0.35, 0))
                    b.sphere(p, 0.13, "spar_black", segs=6, rings=4, scale=(0.6, 1, 1))
                    sh.append(p)
                anchors[(m, side)] = sh
        return anchors

    # --- stern & bow decoration ---

    def build_stern(self):
        b = self.body
        top_y = self.stern_top()
        bands = min(max(self.rows, 1), 2) + (1 if self.castle >= 1 else 0)
        if self.castle == 0:
            bands = 1
        win_h = self.depth * 0.22
        for k in range(bands):
            y = top_y - self.depth * (0.30 + 0.36 * k)
            f = self.f_at(1.0, y)
            p = self.hull_pt(1.0, f, 1)
            z = p.z + 0.06
            half = p.x * 0.86
            nw = 4 + self.rows
            # Balcony ledge below the lower windows of big ships.
            if self.castle >= 2 and k == bands - 1:
                b.box((0, y - win_h * 0.9, z + 0.5), (half * 2.2, 0.14, 1.0), "trim")
                for i in range(13):
                    x = lerp(-half * 1.08, half * 1.08, i / 12)
                    b.box((x, y - win_h * 0.55, z + 0.95), (0.08, win_h * 0.7, 0.08), "trim")
                b.box((0, y - win_h * 0.2, z + 0.95), (half * 2.2, 0.08, 0.1), "trim")
            for i in range(nw):
                x = lerp(-half, half, (i + 0.5) / nw)
                ww = half * 2 / nw * 0.68
                b.box((x, y, z + 0.02), (ww, win_h, 0.06), "glass")
                b.box((x, y, z + 0.06), (0.05, win_h, 0.04), "trim")    # mullion
                b.box((x, y, z + 0.06), (ww, 0.05, 0.04), "trim")       # transom bar
            for i in range(nw + 1):
                x = lerp(-half, half, i / nw)
                b.box((x, y, z + 0.08), (0.14, win_h * 1.25, 0.1), "trim")  # pilasters
            b.box((0, y + win_h * 0.68, z + 0.08), (half * 2.15, 0.14, 0.14), "trim")
            b.box((0, y - win_h * 0.68, z + 0.08), (half * 2.15, 0.14, 0.14), "trim")
        # Gilt moulding framing the transom.
        f_lo = self.f_at(1.0, 0.8)
        f_hi = self.f_at(1.0, top_y)
        for side in (-1, 1):
            edge = [self.hull_pt(1.0, lerp(f_lo, f_hi, i / 10), side) + Vector((-side * 0.05, 0, 0.08)) for i in range(11)]
            b.tube(edge, 0.09, "trim", sides=5)
        # Carved crest above the windows: an oval cartouche.
        if self.castle >= 1:
            y = top_y - self.depth * 0.06
            p = self.hull_pt(1.0, self.f_at(1.0, y), 1)
            b.sphere((0, y, p.z + 0.1), self.depth * 0.13, "trim", segs=12, rings=6, scale=(1.3, 0.9, 0.25))
            # Quarter galleries: bay windows on each quarter.
            for side in (-1, 1):
                t = 0.95
                y_lo = top_y - self.depth * (0.30 + 0.36 * (bands - 1)) - win_h
                y_hi = top_y - self.depth * 0.22
                f_mid = self.f_at(t, (y_lo + y_hi) / 2)
                al, up, nrm = self.hull_axes(t, f_mid, side)
                c = self.hull_pt(t, f_mid, side)
                # A half-hexagon bay standing proud of the quarter.
                r = self.L * 0.024
                h = y_hi - y_lo
                al = Vector((0, 0, 1))
                out = Vector((side, 0, 0))
                prof = [(-1.0, -0.3), (-0.6, 0.75), (0.6, 0.75), (1.0, -0.3)]

                def gp(k, yy, grow=1.0):
                    a, o = prof[k]
                    return Vector((c.x, yy, c.z)) + al * a * r * 1.7 * grow + out * o * r * grow

                rings = [[gp(k, yy) for k in range(4)] for yy in (y_lo, y_hi)]
                if side < 0:
                    rings = [list(reversed(rr)) for rr in rings]
                b.grid(rings, "upper", smooth=False)
                for j in range(bands):
                    yy = y_hi - h * (j + 0.5) / bands
                    for k in range(3):
                        a0, a1 = gp(k, yy), gp(k + 1, yy)
                        mid = (a0 + a1) / 2
                        tang = (a1 - a0).normalized()
                        nrm = tang.cross(Vector((0, 1, 0))).normalized()
                        if nrm.x * side < 0:
                            nrm = -nrm
                        b.box(mid + nrm * 0.03, ((a1 - a0).length * 0.7, h / bands * 0.62, 0.05), "glass",
                              axes=(tang, Vector((0, 1, 0)), nrm))
                    # Gilt moulding between the tiers.
                    yb_ = y_hi - h * j / bands
                    b.tube([gp(k, yb_, 1.06) for k in range(4)], 0.07, "trim", sides=4)
                b.tube([gp(k, y_lo, 1.06) for k in range(4)], 0.07, "trim", sides=4)
                # Domed cap and tapering drop with a finial.
                ctr = Vector((c.x, 0, c.z)) + out * r * 0.25
                b.cyl(ctr + Vector((0, y_hi, 0)), ctr + Vector((0, y_hi + r * 0.7, 0)), r * 1.1, 0.04, "trim", sides=8)
                b.cyl(ctr + Vector((0, y_lo, 0)), ctr + Vector((0, y_lo - r * 1.2, 0)) - out * r * 0.4, r * 1.1, 0.05, "upper", sides=8)
                b.sphere(ctr + Vector((0, y_lo - r * 1.25, 0)) - out * r * 0.4, 0.12, "trim", segs=6, rings=4)
        # Stern lanterns.
        lan_y = top_y + 0.9 + 0.2
        pz = self.hull_pt(1.0, self.f_at(1.0, top_y), 1)
        spots = [0.0] if self.castle == 0 else [-pz.x * 0.75, pz.x * 0.75]
        if self.castle >= 2:
            spots.append(0.0)
        for x in spots:
            big = 1.45 if (x == 0.0 and self.castle >= 2) else 1.0
            base = Vector((x, lan_y, pz.z + 0.1))
            b.cyl(base - Vector((0, 0.9, 0)), base, 0.06, 0.06, "iron", sides=6)
            b.cyl(base, base + Vector((0, 0.75 * big, 0)), 0.22 * big, 0.3 * big, "lantern", sides=8)
            b.cyl(base + Vector((0, 0.75 * big, 0)), base + Vector((0, 1.15 * big, 0)), 0.34 * big, 0.04, "trim", sides=8)
            b.cyl(base - Vector((0, 0.12, 0)), base, 0.2 * big, 0.3 * big, "trim", sides=8)
        # Ensign staff.
        staff_base = Vector((0, top_y + 0.9, pz.z + 0.25))
        staff_top = staff_base + Vector((0, self.L * 0.16, self.L * 0.035))
        b.cyl(staff_base, staff_top, 0.09, 0.05, "spar", sides=6)
        self.ensign_at = staff_top - Vector((0, 0.1, 0))

    def build_bow(self):
        b = self.body
        if self.castle >= 1:
            # Beakhead platform with a grating.
            t = 0.02
            y = self.deck_y(t) - 0.35
            z0 = self.hull_pt(t, 1.0, 1).z
            b.box((0, y, z0 - self.L * 0.025), (self.half_width(0.06) * 1.2, 0.12, self.L * 0.05), "grating")
        # Catheads with anchors.
        for side in (-1, 1):
            t = 0.09
            y = self.deck_y(t) + (self.depth * 0.25 if self.castle >= 1 else 0.3)
            p = self.hull_pt(t, self.f_at(t, y), side)
            tip = p + Vector((side * 1.3, 0.1, -0.6))
            b.box((p + tip) / 2, ((tip - p).length, 0.32, 0.32), "wale",
                  axes=((tip - p).normalized(), Vector((0, 1, 0)), (tip - p).normalized().cross(Vector((0, 1, 0))).normalized()))
            # Anchor hanging from the cathead along the bow.
            top = tip + Vector((0, -0.3, 0))
            shank_bot = top + Vector((0, -self.L * 0.075, 0.25))
            b.cyl(top, shank_bot, 0.11, 0.13, "iron", sides=6)
            b.cyl(top + Vector((0, -0.25, -0.9)), top + Vector((0, -0.25, 0.9)), 0.07, 0.07, "wale", sides=5)
            for d in (-1, 1):
                arm = shank_bot + Vector((0, 0.7, d * 0.9))
                b.cyl(shank_bot, arm, 0.1, 0.07, "iron", sides=6)
                b.box(arm, (0.12, 0.35, 0.3), "iron")

    # --- deck furniture ---

    def build_deck_gear(self):
        b = self.body
        # Hatch gratings between the masts.
        masts = self.mast_positions()
        for i in range(len(masts) - 1):
            t = (masts[i][0] + masts[i + 1][0]) / 2
            y = self.deck_y(t)
            z = -self.L / 2 + t * self.L
            w = self.half_width(t) * 0.55
            b.box((0, y + 0.15, z), (w, 0.3, self.L * 0.06), "grating")
            b.box((0, y + 0.31, z), (w * 0.92, 0.03, self.L * 0.055), "dark")
        # Capstan and wheel.
        tc = 0.66 if self.castle else 0.70
        yc = self.deck_y(tc)
        zc = -self.L / 2 + tc * self.L
        b.cyl(Vector((0, yc, zc)), Vector((0, yc + 1.0, zc)), 0.38, 0.32, "spar", sides=10)
        b.cyl(Vector((0, yc + 1.0, zc)), Vector((0, yc + 1.15, zc)), 0.48, 0.48, "spar_black", sides=10)
        for k in range(4):
            a = k * math.pi / 4
            d = Vector((math.cos(a), 0, math.sin(a)))
            b.cyl(Vector((0, yc + 1.08, zc)) - d * 1.0, Vector((0, yc + 1.08, zc)) + d * 1.0, 0.04, 0.04, "spar", sides=4, caps=False)
        spans = self.castle_spans()
        qd = spans[0]
        tw = qd[1] + 0.02
        yw = self.deck_y(tw) + qd[3] + qd[4]
        zw = -self.L / 2 + tw * self.L
        b.box((0, yw + 0.5, zw), (0.2, 1.0, 0.2), "spar")
        rim = []
        for k in range(17):
            a = 2 * math.pi * k / 16
            rim.append(Vector((math.cos(a) * 0.55, yw + 1.25 + math.sin(a) * 0.55, zw - 0.15)))
        b.tube(rim, 0.04, "spar", sides=4)
        for k in range(4):
            a = k * math.pi / 4
            d = Vector((math.cos(a), math.sin(a), 0))
            c = Vector((0, yw + 1.25, zw - 0.15))
            b.cyl(c - d * 0.7, c + d * 0.7, 0.03, 0.03, "spar", sides=4, caps=False)
        # Ship's boat on the main hatch of the bigger hulls.
        if self.rows >= 1 and len(masts) >= 2:
            t = (masts[0][0] + masts[1][0]) / 2
            y = self.deck_y(t) + 0.42
            z = -self.L / 2 + t * self.L
            blen = self.L * 0.15
            rows = []
            for j in range(4):
                fj = j / 3
                row = []
                for i in range(13):
                    u = i / 12
                    w = math.sin(math.pi * u) ** 0.6 * 0.9
                    x = w * (0.25 + 0.75 * fj ** 0.7)
                    row.append(Vector((x, y + fj * 0.7 - 0.1 * math.sin(math.pi * u), z - blen / 2 + u * blen)))
                rows.append(row)
            mirror = [[Vector((-p.x, p.y, p.z)) for p in reversed(r)] for r in rows]
            b.grid(rows, "upper", smooth=True)
            b.grid(mirror, "upper", smooth=True)
        # Carriage guns on the open waist.
        n = min(max(int(self.class_len / 8.0), 2), 5)
        if self.rows == 0:
            n = 2
        for side in (-1, 1):
            for i in range(n):
                t = 0.34 + i / n * 0.34
                y = self.deck_y(t)
                z = -self.L / 2 + t * self.L
                x = self.section_x(t, 1.0) * 0.72 * side
                b.box((x, y + 0.28, z), (0.75, 0.38, 0.8), "portred")
                for dz in (-0.28, 0.28):
                    b.cyl(Vector((x - 0.3, y + 0.17, z + dz)), Vector((x + 0.3, y + 0.17, z + dz)), 0.17, 0.17, "wale", sides=8)
                a = Vector((x - side * 0.5, y + 0.58, z))
                tip = Vector((x + side * 1.35, y + 0.70, z))
                b.cyl(a, tip, 0.15, 0.10, "iron", sides=8)
                self.muzzles[side].append(tip + Vector((side * 0.4, 0, 0)))

    # --- masts, yards, sails, rigging ---

    def rake(self, foot, p, angle):
        """Rotate p around the mast foot by `angle` (top leans aft, +Z)."""
        d = p - foot
        c, s = math.cos(angle), math.sin(angle)
        return foot + Vector((d.x, d.y * c - d.z * s, d.y * s + d.z * c))

    def build_rig(self):
        b = self.body
        anchors = self.build_channels()
        masts = self.mast_positions()
        rake_a = math.radians(3.0)
        self.mastheads = []
        main_idx = min(1, len(masts) - 1)
        for m, (t, hm, course) in enumerate(masts):
            h = self.L * 0.92 * hm
            z = -self.L / 2 + t * self.L
            deck = self.deck_y(t)
            foot = Vector((0, deck, z))
            R = lambda p: self.rake(foot, p, rake_a)
            r0 = self.L * 0.0125 * (1.0 if m == main_idx else 0.9)
            lower_top = h * 0.60
            top_top = h * 0.84
            if self.p["lateen"]:
                # A single pole mast: two shrouds a side and the lateen yard.
                mh = h * 0.86
                b.cyl(foot - Vector((0, 1.0, 0)), foot + Vector((0, mh, 0)), r0 * 0.95, r0 * 0.6, "spar", sides=10)
                b.box(foot + Vector((0, mh - 0.4, 0)), (r0 * 2.2, 0.5, r0 * 2.2), "spar_black")
                head = foot + Vector((0, mh - 0.6, 0))
                for side in (-1, 1):
                    lines = [[a, head] for a in anchors[(m, side)][::2]]
                    for ln in lines:
                        b.tube(ln, 0.04, "rope", sides=4, smooth=False)
                    self.ratlines(lines, 0.42)
                top = foot + Vector((0, mh, 0))
                self.mastheads.append({"foot": foot, "lower": head, "top": top, "truck": top, "h": h})
                self.lateen_sail(m, foot, h, rake_a)
                continue
            # Lower mast with iron bands.
            b.cyl(R(foot - Vector((0, 1.5, 0))), R(foot + Vector((0, lower_top + 1.2, 0))), r0, r0 * 0.78, "spar", sides=12)
            for k in range(1, 6):
                yb_ = lower_top * k / 6
                b.cyl(R(foot + Vector((0, yb_, 0))), R(foot + Vector((0, yb_ + 0.12, 0))), r0 * 1.06, r0 * 1.06, "spar_black", sides=12)
            # Fighting top, crosstrees and cap.
            top_c = foot + Vector((0, lower_top, 0.15))
            b.cyl(R(top_c - Vector((0, 0.12, 0))), R(top_c + Vector((0, 0.12, 0))), self.L * 0.032, self.L * 0.032, "spar_black", sides=14)
            b.box(R(top_c - Vector((0, 0.3, 0))), (self.L * 0.06, 0.2, 0.25), "spar")
            b.box(R(foot + Vector((0, lower_top + 1.2, -r0 * 0.9))), (r0 * 1.8, 0.35, r0 * 4.2), "spar_black")
            # Topmast fidded forward of the lower masthead, then topgallant.
            tm_foot = foot + Vector((0, lower_top - 0.9, -r0 * 1.7))
            b.cyl(R(tm_foot), R(tm_foot + Vector((0, top_top - lower_top + 1.6, 0))), r0 * 0.62, r0 * 0.46, "spar", sides=10)
            tg_foot = tm_foot + Vector((0, top_top - lower_top + 0.6, -r0 * 1.0))
            truck = tg_foot + Vector((0, h * 1.03 - top_top + 0.3, 0))
            b.cyl(R(tm_foot + Vector((0, top_top - lower_top, 0))), R(tm_foot + Vector((0, top_top - lower_top + 0.15, 0))), self.L * 0.017, self.L * 0.017, "spar_black", sides=8)
            b.cyl(R(tg_foot), R(truck), r0 * 0.38, r0 * 0.16, "spar", sides=8)
            b.sphere(R(truck + Vector((0, 0.12, 0))), 0.16, "trim", segs=8, rings=4)
            self.mastheads.append({"foot": foot, "lower": R(foot + Vector((0, lower_top, 0))),
                                   "top": R(tm_foot + Vector((0, top_top - lower_top, 0))),
                                   "truck": R(truck), "h": h, "R": R, "top_c": R(top_c)})
            # Lower and topmast shrouds with ratlines.
            for side in (-1, 1):
                anc = anchors[(m, side)]
                head = R(foot + Vector((side * r0 * 0.9, lower_top - 0.5, 0)))
                lines = [[a, head] for a in anc]
                for ln in lines:
                    b.tube(ln, 0.04, "rope", sides=4, smooth=False)
                self.ratlines(lines, 0.42)
                top_edge = [R(top_c + Vector((side * self.L * 0.029, 0, dz))) for dz in (-0.6, 0.0, 0.6)]
                thead = R(tm_foot + Vector((side * r0 * 0.4, top_top - lower_top - 0.4, 0)))
                tl = [[e, thead] for e in top_edge]
                for ln in tl:
                    b.tube(ln, 0.03, "rope", sides=4, smooth=False)
                self.ratlines(tl, 0.42)
                # Backstays to the hull aft of the channel.
                bs_anchor = self.hull_pt(min(t + 0.07, 0.97), 1.0, side) + Vector((side * 0.3, 0.2, 0))
                b.tube([bs_anchor, R(tm_foot + Vector((0, top_top - lower_top - 0.2, 0)))], 0.035, "rope", sides=4, smooth=False)
            # Sails.
            wb = self.beam * 2.0 * (1.0 - m * 0.08)
            tiers = self.sail_tiers()
            yards = []
            for ti, (yf, wm) in enumerate(tiers):
                yards.append((h * yf, wb * wm))
            for ti, (yy, ww) in enumerate(yards):
                yc = R(foot + Vector((0, yy, -r0 * 1.2)))
                # Tapered yard in two halves with a sling cleat in the middle.
                b.tube([yc + Vector((-ww / 2, 0, 0)), yc + Vector((-ww / 4, 0, 0)), yc, yc + Vector((ww / 4, 0, 0)), yc + Vector((ww / 2, 0, 0))],
                       [0.06, 0.12, 0.17, 0.12, 0.06], "spar", sides=8)
                # Lifts from yardarms to the mast above.
                above = R(foot + Vector((0, (yards[ti + 1][0] if ti + 1 < len(yards) else h) - 0.4, 0)))
                for sx in (-1, 1):
                    arm = yc + Vector((sx * ww * 0.48, 0, 0))
                    b.tube([arm, above], 0.025, "rope", sides=3, smooth=False)
                    # Braces run aft to the next mast (or the quarterdeck rail).
                    if m + 1 < len(masts):
                        nt_ = masts[m + 1][0]
                        aft = Vector((sx * 0.3, self.deck_y(nt_) + yy * 0.55, -self.L / 2 + nt_ * self.L))
                    else:
                        aft = self.hull_pt(0.97, self.f_at(0.97, self.stern_top()), sx) + Vector((0, 0.9, 0))
                    b.tube([arm, aft], 0.022, "rope", sides=3, smooth=False)
                # Footrope sagging under the yard.
                foot_pts = [yc + Vector(((k / 6 - 0.5) * ww * 0.94, -0.75 - 0.25 * math.sin(math.pi * k / 6), 0.1)) for k in range(7)]
                b.tube(foot_pts, 0.02, "rope", sides=3, smooth=False)
                if ti == 0 and course:
                    # Sheets from the course clews down to the rail.
                    for sx in (-1, 1):
                        clew = R(foot + Vector((sx * ww * 0.47, h * 0.13, -r0 * 1.2)))
                        rail = self.hull_pt(min(t + 0.08, 0.95), 1.05, sx)
                        b.tube([clew, rail], 0.025, "rope", sides=3, smooth=False)
                if ti == 0 and not course:
                    continue
                below = yards[ti - 1] if ti > 0 else None
                if below is not None:
                    sail_h = yy - below[0] - 0.55
                    foot_w = below[1] * 0.9
                else:
                    sail_h = yy - h * 0.13
                    foot_w = ww * 1.0
                emblem = ti == (1 if len(yards) >= 3 else 0) and m < 2
                self.square_sail(f"Sail_{m}_{ti}" + ("_E" if emblem else ""), yc + Vector((0, -0.2, -0.15)), ww * 0.94, foot_w, sail_h, rake_a)
            if m == len(masts) - 1 and len(masts) >= 2:
                self.spanker(foot, h, rake_a)
        self.build_stays_and_bowsprit()

    def ratlines(self, lines, step):
        """Horizontal rope steps between the shroud lines."""
        a0, h0 = lines[0]
        length = (h0 - a0).length
        n = int(length * 0.82 / step)
        for i in range(1, n):
            f = i / (n + 2)
            pts = [ln[0].lerp(ln[1], f) for ln in lines]
            self.body.tube(pts, 0.018, "rope", sides=3, smooth=False)

    def square_sail(self, name, yard_pt, w_top, w_bot, h, rake_a):
        mb = MeshBuilder()
        cols, rows = 14, 9
        billow = (w_top + w_bot) * 0.5 * 0.13
        grid, uvs = [], []
        for r in range(rows + 1):
            v = r / rows
            row, urow = [], []
            for c in range(cols + 1):
                u = c / cols
                w = lerp(w_top, w_bot, v)
                x = (u - 0.5) * w
                y = -v * h + math.sin(math.pi * u) * h * 0.07 * v * v
                zb = -billow * math.sin(math.pi * u) * math.sin(math.pi * min(v * 0.85 + 0.12, 1.0))
                row.append(Vector((x, y, zb)))
                urow.append((u, 1.0 - v))
            grid.append(row)
            uvs.append(urow)
        mb.grid(grid, "sail", uvs, smooth=True)
        self.emit_part(name, mb, yard_pt, rake_a)

    def lateen_sail(self, m, foot, h, rake_a):
        b = self.body
        fore = Vector((0, h * 0.30, -self.L * 0.26 * (0.8 if self.p["masts"] == 2 else 1.0)))
        peak = Vector((0, h * 1.02, self.L * 0.15))
        yard_a = foot + fore
        yard_b = foot + peak
        b.tube([yard_a, yard_a.lerp(yard_b, 0.5), yard_b], [0.08, 0.15, 0.06], "spar", sides=8)
        clew = foot + Vector((0, h * 0.12, self.L * 0.22))
        mb = MeshBuilder()
        g = 10
        grid, uvs = [], []
        for r in range(g + 1):
            v = r / g
            row, urow = [], []
            for c in range(g + 1):
                u = c / g
                on_yard = (yard_b - yard_a) * u
                p = on_yard.lerp((clew - yard_a) * u, v)
                p += Vector((math.sin(math.pi * u) * math.sin(math.pi * v) * self.L * 0.035, 0, 0))
                row.append(p)
                urow.append((u, 1 - v * u))
            grid.append(row)
            uvs.append(urow)
        mb.grid(grid, "sail", uvs, smooth=True)
        self.emit_part(f"Sail_{m}_lateen", mb, yard_a, 0.0, yard_b - yard_a)

    def triangle_sail(self, name, head, tack, f0, f1, aft):
        """Fore-and-aft triangle: luff on the head→tack stay, clew `aft` of the tack."""
        hd = head.lerp(tack, f0)
        tk = head.lerp(tack, f1)
        clew = Vector((0, tk.y + (hd.y - tk.y) * 0.1, tk.z + abs(hd.z - tk.z) * aft + 0.5))
        mb = MeshBuilder()
        g = 7
        grid, uvs = [], []
        for r in range(g + 1):
            v = r / g
            row, urow = [], []
            for c in range(g + 1):
                u = c / g
                p = hd.lerp(tk, u).lerp(hd.lerp(clew, u), v) - hd
                p += Vector((math.sin(math.pi * u) * math.sin(math.pi * v) * self.L * 0.016, 0, 0))
                row.append(p)
                urow.append((u, 1 - v))
            grid.append(row)
            uvs.append(urow)
        mb.grid(grid, "sail", uvs, smooth=True)
        self.emit_part(name, mb, hd, 0.0, tk - hd)

    def spanker(self, foot, h, rake_a):
        b = self.body
        gaff_in = foot + Vector((0, h * 0.50, 0.35))
        gaff_out = foot + Vector((0, h * 0.62, self.L * 0.22))
        boom_in = foot + Vector((0, h * 0.10, 0.35))
        boom_out = foot + Vector((0, h * 0.13, self.L * 0.27))
        b.tube([gaff_in, gaff_out], [0.13, 0.07], "spar", sides=8)
        b.tube([boom_in, boom_out], [0.14, 0.08], "spar", sides=8)
        mb = MeshBuilder()
        g = 8
        grid, uvs = [], []
        for r in range(g + 1):
            v = r / g
            row, urow = [], []
            for c in range(g + 1):
                u = c / g
                top = gaff_in.lerp(gaff_out, u)
                bot = boom_in.lerp(boom_out, u)
                p = top.lerp(bot, v) - gaff_in
                p += Vector((math.sin(math.pi * u) * math.sin(math.pi * v) * self.L * 0.025, 0, 0))
                row.append(p)
                urow.append((u, 1 - v))
            grid.append(row)
            uvs.append(urow)
        mb.grid(grid, "sail", uvs, smooth=True)
        self.emit_part("Sail_spanker", mb, gaff_in, 0.0, gaff_out - gaff_in)

    def build_stays_and_bowsprit(self):
        b = self.body
        bow_deck = self.deck_y(0.0)
        base = Vector((0, bow_deck * 0.95, -self.L * 0.44))
        tip = Vector((0, bow_deck * 1.55, -self.L * 0.70))
        jib_tip = tip + (tip - base).normalized() * self.L * 0.10
        b.tube([base, tip], [0.30, 0.18], "spar", sides=10)
        b.tube([tip - (tip - base).normalized() * 1.2, jib_tip], [0.13, 0.07], "spar", sides=8)
        b.cyl(tip - (tip - base).normalized() * 0.3, tip, 0.24, 0.24, "spar_black", sides=8)
        # Spritsail under the bowsprit of the two-deckers and up.
        if self.rows >= 2:
            sp = base.lerp(tip, 0.62)
            sp_w = self.beam * 1.0
            b.tube([sp + Vector((-sp_w / 2, 0, 0)), sp, sp + Vector((sp_w / 2, 0, 0))], [0.06, 0.12, 0.06], "spar", sides=6)
            self.square_sail("Sail_sprit", sp + Vector((0, -0.15, 0)), sp_w * 0.92, sp_w * 0.95, sp_w * 0.42, 0.0)
        heads = self.mastheads
        # Fore stays to the bowsprit, other stays to the mast ahead.
        fore = heads[0]
        b.tube([fore["lower"], base.lerp(tip, 0.3)], 0.06, "rope", sides=4, smooth=False)
        b.tube([fore["top"], tip], 0.045, "rope", sides=4, smooth=False)
        b.tube([fore["truck"] - Vector((0, 0.6, 0)), jib_tip], 0.035, "rope", sides=4, smooth=False)
        for i in range(1, len(heads)):
            prev = heads[i - 1]
            cur = heads[i]
            b.tube([cur["lower"], prev["foot"] + Vector((0, 1.2, 0))], 0.055, "rope", sides=4, smooth=False)
            b.tube([cur["top"], prev["lower"] + Vector((0, 0.4, 0))], 0.04, "rope", sides=4, smooth=False)
            b.tube([cur["truck"] - Vector((0, 0.6, 0)), prev["top"]], 0.03, "rope", sides=4, smooth=False)
        # Staysails between the masts, hanked to the topmast stays.
        if not self.p["lateen"]:
            for i in range(1, len(heads)):
                self.triangle_sail(f"Sail_stay_{i}", heads[i]["top"], heads[i - 1]["lower"] + Vector((0, 0.4, 0)),
                                   0.08, 0.94, 0.75)
        # Jibs on the fore stays.
        if not self.p["lateen"]:
            for k, (head, tack) in enumerate([(fore["top"], tip), (fore["truck"] - Vector((0, 0.6, 0)), jib_tip)]):
                if k == 1 and self.p["tiers"] < 3:
                    continue
                # Luff along the stay, foot running aft from the tack.
                hd = head.lerp(tack, 0.22 + 0.1 * k)
                tk = head.lerp(tack, 0.97)
                clew = Vector((0, tk.y + (hd.y - tk.y) * 0.08, tk.z + (hd.z - tk.z) * 0.58))
                mb = MeshBuilder()
                g = 7
                grid, uvs = [], []
                for r in range(g + 1):
                    v = r / g
                    row, urow = [], []
                    for c in range(g + 1):
                        u = c / g
                        p = hd.lerp(tk, u).lerp(hd.lerp(clew, u), v) - hd
                        p += Vector((math.sin(math.pi * u) * math.sin(math.pi * v) * self.L * 0.018, 0, 0))
                        row.append(p)
                        urow.append((u, 1 - v))
                    grid.append(row)
                    uvs.append(urow)
                mb.grid(grid, "sail", uvs, smooth=True)
                self.emit_part(f"Sail_jib_{k}", mb, hd, 0.0, tk - hd)
        # Pennant streaming from the main truck.
        main = heads[min(1, len(heads) - 1)]
        pen = MeshBuilder()
        plen = self.L * 0.2
        rows = []
        for j in range(2):
            row = []
            for i in range(13):
                u = i / 12
                hh = self.L * 0.012 * (1 - u)
                row.append(Vector((math.sin(u * 7) * 0.25 * u, -j * hh, u * plen)))
            rows.append(row)
        pen.grid(rows, "flag", smooth=True)
        self.emit_part("Pennant", pen, main["truck"] - Vector((0, 0.05, 0)), 0.0)
        # Ensign at the stern staff.
        fl = MeshBuilder()
        fw, fh = self.L * 0.14, self.L * 0.09
        rows = []
        for j in range(5):
            row = []
            for i in range(9):
                u = i / 8
                row.append(Vector((math.sin(u * 5.0 + j * 0.3) * 0.18 * u, -fh * j / 4, u * fw)))
            rows.append(row)
        fl.grid(rows, "flag", smooth=True)
        self.emit_part("Flag", fl, self.ensign_at, 0.0)

    def emit_part(self, name, mb, origin, rake_a, spar_dir=None):
        """Separate node: mesh local to `origin`, rotated by the mast rake.

        With `spar_dir` (the yard/stay/gaff the sail is bent to, in Godot
        axes) the node's local X runs along that spar and local Y points
        away from the sail, so scaling Y furls the sail onto its spar."""
        rot = Matrix.Rotation(rake_a, 4, "X")
        if spar_dir is not None:
            ax = Vector(spar_dir).normalized()
            centre = sum((Vector(v) for v in mb.verts), Vector()) / max(len(mb.verts), 1)
            ay = -(centre - ax * centre.dot(ax)).normalized()
            az = ax.cross(ay).normalized()
            mb.verts = [Vector((v.dot(ax), v.dot(ay), v.dot(az))) for v in mb.verts]
            # Godot basis (ax, ay, az) expressed in Blender axes: C·M·C⁻¹.
            cols = [to_bl(ax), to_bl(-az), to_bl(ay)]
            rot = Matrix(((cols[0].x, cols[1].x, cols[2].x, 0), (cols[0].y, cols[1].y, cols[2].y, 0),
                          (cols[0].z, cols[1].z, cols[2].z, 0), (0, 0, 0, 1)))
        obj = mb.build(name, self.mats, origin=(0, 0, 0), tri_counter=self.tris)
        if obj is None:
            return
        obj.matrix_world = Matrix.Translation(to_bl(origin)) @ rot
        self.extra_objs.append(obj)

    def build(self):
        self.make_materials()
        self.build_hull()
        self.build_wales()
        self.build_gunports()
        self.build_stern()
        self.build_bow()
        self.build_deck_gear()
        self.build_rig()
        body = self.body.build("Hull", self.mats, tri_counter=self.tris)
        bake_ao(body, self.extra_objs)
        objs = [body] + self.extra_objs
        for side, pts in self.muzzles.items():
            for i, p in enumerate(pts):
                e = bpy.data.objects.new(f"Muzzle_{'P' if side < 0 else 'S'}_{i:02d}", None)
                e.location = to_bl(p)
                bpy.context.scene.collection.objects.link(e)
                objs.append(e)
        return objs


# --------------------------------------------------------------------------

def bake_ao(obj, hide):
    """Bake ambient occlusion into the body's vertex colours (glTF COLOR_0
    multiplies the base colour), so ports, rails and decks gain depth."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.cycles.device = "CPU"
    world = scene.world or bpy.data.worlds.new("World")
    scene.world = world
    world.light_settings.distance = 1.6
    for o in hide:
        o.hide_render = True
    mesh = obj.data
    attr = mesh.color_attributes.new("AO", "BYTE_COLOR", "CORNER")
    mesh.color_attributes.active_color = attr
    bpy.ops.object.select_all(action="DESELECT")
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    scene.render.bake.target = "VERTEX_COLORS"
    bpy.ops.object.bake(type="AO")
    n = len(attr.data)
    col = np.zeros(n * 4, dtype=np.float32)
    attr.data.foreach_get("color", col)
    col = col.reshape(n, 4)
    ao = np.clip(col[:, 0], 0, 1) ** 0.8
    v = 0.42 + 0.58 * ao
    col[:, 0] = col[:, 1] = col[:, 2] = v
    col[:, 3] = 1.0
    attr.data.foreach_set("color", col.ravel())
    for o in hide:
        o.hide_render = False


def show_ao_in_materials(obj):
    """Preview only: multiply the baked AO into the Blender materials."""
    for m in obj.data.materials:
        nt = m.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        base = bsdf.inputs["Base Color"]
        vc = nt.nodes.new("ShaderNodeVertexColor")
        vc.layer_name = "AO"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        col_a = [i for i in mix.inputs if i.name == "A" and i.type == "RGBA"][0]
        col_b = [i for i in mix.inputs if i.name == "B" and i.type == "RGBA"][0]
        col_out = [o for o in mix.outputs if o.type == "RGBA"][0]
        if base.is_linked:
            nt.links.new(base.links[0].from_socket, col_a)
        else:
            col_a.default_value = base.default_value
        nt.links.new(vc.outputs["Color"], col_b)
        nt.links.new(col_out, base)


def clear_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.cameras, bpy.data.lights):
        for item in list(coll):
            coll.remove(item)


def export(type_id, objs):
    os.makedirs(OUT_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT_DIR, type_id + ".gltf")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLTF_SEPARATE", export_texture_dir="textures",
        use_selection=True,
        export_image_format="JPEG", export_jpeg_quality=88,
        export_apply=True, export_yup=True, export_animations=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_cameras=False, export_lights=False)
    return path


def render_preview(type_id, out_dir, L):
    scene = bpy.context.scene
    show_ao_in_materials(bpy.data.objects["Hull"])
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.film_transparent = False
    world = bpy.data.worlds.get("World") or bpy.data.worlds.new("World")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.68, 0.85, 1)
    bg.inputs[1].default_value = 0.9
    # Sea plane.
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0.3))
    sea = bpy.context.active_object
    sm = bpy.data.materials.new("sea")
    sm.use_nodes = True
    p = sm.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (0.02, 0.12, 0.2, 1)
    p.inputs["Roughness"].default_value = 0.15
    sea.data.materials.append(sm)
    sun_data = bpy.data.lights.new("sun", "SUN")
    sun_data.energy = 4.0
    sun = bpy.data.objects.new("sun", sun_data)
    sun.rotation_euler = (math.radians(50), 0, math.radians(140))
    scene.collection.objects.link(sun)
    cam_data = bpy.data.cameras.new("cam")
    cam_data.lens = 35
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    shots = {
        "q": (Vector((L * 1.35, L * 1.25, L * 0.38)), Vector((0, 0, L * 0.36))),
        "side": (Vector((L * 2.0, 0, L * 0.16)), Vector((0, 0, L * 0.42))),
        "stern": (Vector((-L * 0.75, -L * 1.0, L * 0.25)), Vector((0, -L * 0.3, L * 0.2))),
    }
    for key, (pos, target) in shots.items():
        cam.location = pos
        cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{type_id}_{key}.png")
        bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    preview = None
    do_export = True
    i = 0
    while i < len(argv):
        if argv[i] == "--only":
            only = argv[i + 1].split(",")
            i += 1
        elif argv[i] == "--preview":
            preview = argv[i + 1]
            i += 1
        elif argv[i] == "--no-export":
            do_export = False
        i += 1
    if do_export:
        build_nation_textures()
    for type_id in PROFILES:
        if only and type_id not in only:
            continue
        clear_scene()
        sb = ShipBuilder(type_id)
        objs = sb.build()
        msg = f"{type_id}: {sb.tris[0]} tris, {len(objs)} nodes"
        if do_export:
            msg += " -> " + export(type_id, objs)
        print(msg)
        if preview:
            os.makedirs(preview, exist_ok=True)
            render_preview(type_id, preview, MODEL_LENGTH)


main()
