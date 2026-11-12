#!/usr/bin/env python3
"""Downloads the CC0 source textures (Poly Haven, https://polyhaven.com, license CC0 1.0) used to
build the block texture set. Sources are cached outside the repository; only the processed,
downscaled results produced by build_textures.py are shipped in the APK.

usage: fetch_textures.py <cache_dir>
"""
import json, os, sys, urllib.request, concurrent.futures

SOURCES = [
    "leafy_grass", "withered_grass", "dirt_floor", "brown_mud_dry", "rock_05", "rock_04", "sand_01", "sand_02",
    "gravel_ground_01", "clay_floor_001", "snow_02", "jolcham_oak_bark_01", "pine_bark", "palm_tree_bark",
    "knotted_pine_bark", "mossy_rock", "sandstone_cracks", "brown_mud_02", "forest_ground_04", "forest_leaves_03",
    "wood_planks", "hinoki_planks", "weathered_planks", "cobblestone_05", "mossy_cobblestone", "brick_4",
    "thatch_roof_angled", "metal_plate_02", "metal_plate", "rusty_metal_02", "farm_soil", "dark_rock",
    "aerial_grass_rock", "rock_face_03",
]
UA = {"User-Agent": "texture-fetch/1.0"}

def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()

def fetch(name, cache):
    out = os.path.join(cache, name)
    os.makedirs(out, exist_ok=True)
    wanted = {"Diffuse": "diff", "nor_gl": "nor", "Rough": "rough"}
    if all(os.path.exists(os.path.join(out, v + ".jpg")) for v in wanted.values()):
        return name, "cached"
    info = json.loads(get(f"https://api.polyhaven.com/files/{name}"))
    for key, short in wanted.items():
        dst = os.path.join(out, short + ".jpg")
        if os.path.exists(dst):
            continue
        entry = info.get(key)
        if entry is None and key == "Rough":
            entry = info.get("arm")  # some assets only ship packed AO/Rough/Metal
            short_note = "arm"
        if entry is None:
            continue
        url = entry["1k"]["jpg"]["url"]
        data = get(url)
        with open(dst, "wb") as f:
            f.write(data)
        if key == "Rough" and "Rough" not in info:
            open(os.path.join(out, "rough_is_arm"), "w").close()
    return name, "ok"

if __name__ == "__main__":
    cache = sys.argv[1]
    os.makedirs(cache, exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(6) as ex:
        for name, status in ex.map(lambda n: fetch(n, cache), SOURCES):
            print(name, status)
