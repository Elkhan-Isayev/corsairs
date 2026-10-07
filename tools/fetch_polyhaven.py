"""Downloads the CC0 Poly Haven assets the game uses (polyhaven.com).

    python3 tools/fetch_polyhaven.py textures        # → assets/textures/<id>/
    python3 tools/fetch_polyhaven.py models DEST     # raw glTF for tools/blender/*

Textures come as 1k JPEGs: <id>_diff (colour), <id>_nor_gl (OpenGL normal)
and <id>_arm (AO / roughness / metal — Godot's ORM layout).
"""

import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
API = "https://api.polyhaven.com"

TEXTURES = [
    "painted_plaster_wall",  # house walls (tinted per house)
    "plaster_stone_wall_01", # governor's mansion, warehouses
    "clay_roof_tiles_02",    # roofs
    "dark_wooden_planks",    # timber frames, doors, shutters, furniture
    "brown_planks_05",       # wooden floors, crates on the quay
    "cobblestone_floor_05",  # streets
    "coast_sand_01",         # beach strip
    "grass_ground",          # town ground
    "seaworn_stone_tiles",   # quay
    "rocky_terrain_02",      # hills
    "palm_tree_bark",        # palm trunks
]

MODELS = ["dutch_ship_medium", "dutch_ship_large_01", "dutch_ship_large_02", "ship_pinnace",
          "wine_barrel_01", "wooden_crate_01", "wooden_crate_02", "cannon_01",
          "wooden_lantern_01", "island_tree_02"]


def get(url, dest):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    subprocess.run(["curl", "-s", "-A", "Mozilla/5.0", "-o", dest, url], check=True)


def files(asset_id):
    out = subprocess.run(["curl", "-s", "-A", "Mozilla/5.0", f"{API}/files/{asset_id}"],
                         check=True, capture_output=True).stdout
    return json.loads(out)


def fetch_textures():
    for tid in TEXTURES:
        f = files(tid)
        for key, name in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("arm", "arm")):
            entry = f[key]["1k"].get("jpg")
            get(entry["url"], os.path.join(ROOT, "assets", "textures", tid, f"{tid}_{name}.jpg"))
        print("texture", tid)


def fetch_models(dest, res="2k"):
    for mid in MODELS:
        g = files(mid)["gltf"][res if mid.startswith(("dutch", "ship")) else "1k"]["gltf"]
        if os.path.exists(os.path.join(dest, mid, os.path.basename(g["url"]))):
            continue
        get(g["url"], os.path.join(dest, mid, os.path.basename(g["url"])))
        for rel, v in g["include"].items():
            get(v["url"], os.path.join(dest, mid, rel))
        print("model", mid)


if __name__ == "__main__":
    if sys.argv[1] == "textures":
        fetch_textures()
    else:
        fetch_models(sys.argv[2])
