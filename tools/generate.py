#!/usr/bin/env python3
"""Generates the Hyper Realms add-on (behavior pack + resource pack) for
Minecraft Bedrock Edition and packages it as .mcaddon / .mcpack.

Usage:  python3 tools/generate.py
"""
import json
import math
import random
import shutil
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "HyperRealms"
BP = OUT / "behavior_pack"
RP = OUT / "resource_pack"
DIST = ROOT / "dist"

VERSION = [1, 0, 0]
MIN_ENGINE = [1, 26, 0]
BP_UUID = "21d6208f-4975-4a5d-afb1-d9a4fd3f731a"
BP_DATA_UUID = "3b35154a-7352-4a37-af0b-7b8e60f28dcf"
BP_SCRIPT_UUID = "c50d644a-4ea8-4c22-a000-27a7622ba6d3"
RP_UUID = "951461f1-37a0-44c6-b48b-085273d1f12a"
RP_MODULE_UUID = "0e0f6d66-7773-4ca2-bb5a-502b4a08597a"

NS = "hyper"


def mc(name):
    return name if ":" in name else "minecraft:" + name


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(obj, str):
        path.write_text(obj, encoding="utf-8")
    else:
        path.write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


# ---------------------------------------------------------------------------
# Biomes (behavior pack)
# ---------------------------------------------------------------------------

def surface(top, mid, foundation="stone", sea_floor="gravel"):
    return {
        "builder": {
            "type": "minecraft:overworld",
            "sea_floor_depth": 7,
            "sea_floor_material": mc(sea_floor),
            "foundation_material": mc(foundation),
            "mid_material": mc(mid),
            "top_material": mc(top),
            "sea_material": "minecraft:water",
        }
    }


def adjust(materials, noise=None, height=None, freq=0.0625):
    a = {"materials": {k: mc(v) for k, v in materials.items()}}
    if height is not None:
        a["height_range"] = list(height)
    if noise is not None:
        a["noise_frequency_scale"] = freq
        a["noise_range"] = list(noise)
    return a


def replace(targets, amount, freq):
    return {
        "dimension": "minecraft:overworld",
        "targets": list(targets),
        "amount": amount,
        "noise_frequency_scale": freq,
    }


def steep(material):
    return {
        "steep_material_adjustment": {
            "material": mc(material),
            "north_slopes": True,
            "east_slopes": True,
            "south_slopes": True,
            "west_slopes": True,
        },
        "top_slide": {"enabled": False},
    }


BIOMES = {
    # ----- real mountains ---------------------------------------------------
    "titan_peaks": {
        "climate": {"downfall": 0.9, "snow_accumulation": [0.125, 0.5], "temperature": -0.7},
        "surface": surface("snow", "stone"),
        "mountain": steep("deepslate"),
        "adjustments": [
            adjust({"top_material": "stone", "mid_material": "stone"}, height=(0, 150)),
            adjust({"top_material": "tuff", "mid_material": "tuff"}, noise=(0.25, 1.0), height=(0, 165)),
            adjust({"top_material": "packed_ice", "mid_material": "packed_ice"}, noise=(-1.0, -0.45), height=(190, 400)),
        ],
        "replace": [replace(["jagged_peaks"], 0.65, 4.0), replace(["frozen_peaks"], 0.55, 4.0)],
        "tags": ["mountains", "monster", "overworld", "frozen", "jagged_peaks",
                 "spawns_cold_variant_farm_animals", "spawns_cold_variant_frogs",
                 "spawns_snow_foxes", "spawns_white_rabbits"],
    },
    "frostfang_slopes": {
        "climate": {"downfall": 0.9, "snow_accumulation": [0.25, 0.75], "temperature": -0.5},
        "surface": surface("snow", "snow"),
        "mountain": steep("packed_ice"),
        "adjustments": [
            adjust({"top_material": "packed_ice", "mid_material": "packed_ice"}, noise=(0.3, 1.0)),
            adjust({"top_material": "blue_ice", "mid_material": "packed_ice"}, noise=(0.62, 1.0)),
        ],
        "replace": [replace(["snowy_slopes"], 0.55, 4.0), replace(["grove"], 0.25, 4.0)],
        "tags": ["frozen", "mountains", "monster", "overworld", "snowy_slopes",
                 "spawns_cold_variant_frogs", "spawns_snow_foxes", "spawns_white_rabbits",
                 "spawns_cold_variant_farm_animals"],
    },
    "sunset_crags": {
        "climate": {"downfall": 0.2, "temperature": 1.0},
        "surface": surface("granite", "granite"),
        "mountain": steep("hardened_clay"),
        "adjustments": [
            adjust({"top_material": "grass_block", "mid_material": "dirt"}, noise=(0.2, 1.0)),
            adjust({"top_material": "coarse_dirt", "mid_material": "coarse_dirt"}, noise=(-1.0, -0.55)),
            adjust({"top_material": "orange_terracotta", "mid_material": "orange_terracotta"}, height=(92, 98)),
            adjust({"top_material": "white_terracotta", "mid_material": "white_terracotta"}, height=(112, 116)),
            adjust({"top_material": "red_terracotta", "mid_material": "red_terracotta"}, height=(128, 136)),
            adjust({"top_material": "yellow_terracotta", "mid_material": "yellow_terracotta"}, height=(150, 155)),
            adjust({"top_material": "orange_terracotta", "mid_material": "orange_terracotta"}, height=(168, 176)),
            adjust({"top_material": "calcite", "mid_material": "calcite"}, height=(196, 400)),
        ],
        "replace": [replace(["stony_peaks"], 0.7, 4.0)],
        "tags": ["mountains", "monster", "overworld", "animal", "spawns_warm_variant_farm_animals"],
    },
    "emerald_highlands": {
        "climate": {"downfall": 0.9, "temperature": 0.45},
        "surface": surface("grass_block", "dirt"),
        "mountain": steep("stone"),
        "adjustments": [
            adjust({"top_material": "moss_block"}, noise=(0.35, 1.0)),
            adjust({"top_material": "podzol"}, noise=(-1.0, -0.5)),
            adjust({"top_material": "snow", "mid_material": "stone"}, height=(172, 400)),
        ],
        "replace": [replace(["meadow"], 0.55, 4.0), replace(["grove"], 0.3, 4.0)],
        "village": "default",
        "map_tints": {"grass": {"type": "tint", "tint": "#3fc46b"}, "foliage": "#2fa85a"},
        "tags": ["mountains", "monster", "overworld", "animal", "meadow", "bee_habitat",
                 "has_structure_abandoned_camp"],
    },
    # ----- living lowlands --------------------------------------------------
    "glowwood_forest": {
        "climate": {"downfall": 0.9, "temperature": 0.7},
        "surface": surface("grass_block", "dirt"),
        "adjustments": [
            adjust({"top_material": "moss_block"}, noise=(0.15, 1.0)),
            adjust({"top_material": "podzol"}, noise=(-1.0, -0.55)),
        ],
        "replace": [replace(["forest"], 0.3, 6.0), replace(["roofed_forest"], 0.3, 6.0),
                    replace(["birch_forest"], 0.2, 6.0)],
        "humid": True,
        "map_tints": {"grass": {"type": "tint", "tint": "#35b38a"}, "foliage": "#249c7c"},
        "tags": ["animal", "forest", "monster", "overworld", "bee_habitat"],
    },
    "autumn_woods": {
        "climate": {"downfall": 0.7, "temperature": 0.6},
        "surface": surface("grass_block", "dirt"),
        "adjustments": [
            adjust({"top_material": "podzol"}, noise=(0.3, 1.0)),
            adjust({"top_material": "coarse_dirt"}, noise=(-1.0, -0.6)),
        ],
        "replace": [replace(["forest"], 0.3, 6.0), replace(["birch_forest"], 0.3, 6.0),
                    replace(["taiga"], 0.15, 6.0)],
        "map_tints": {"grass": {"type": "tint", "tint": "#b9a23a"}, "foliage": "#d8691e"},
        "tags": ["animal", "forest", "monster", "overworld", "bee_habitat",
                 "has_structure_abandoned_camp"],
    },
    "crystal_fields": {
        "climate": {"downfall": 0.5, "temperature": 0.8},
        "surface": surface("grass_block", "dirt"),
        "adjustments": [
            adjust({"top_material": "calcite", "mid_material": "calcite"}, noise=(0.6, 1.0)),
        ],
        "replace": [replace(["plains"], 0.25, 6.0), replace(["sunflower_plains"], 0.4, 6.0)],
        "village": "default",
        "map_tints": {"grass": {"type": "tint", "tint": "#6fd8b4"}, "foliage": "#58c7a6"},
        "tags": ["animal", "monster", "overworld", "plains", "bee_habitat"],
    },
}


def build_biomes():
    for name, b in BIOMES.items():
        comps = {
            "minecraft:climate": b["climate"],
            "minecraft:surface_builder": b["surface"],
        }
        if "adjustments" in b:
            comps["minecraft:surface_material_adjustments"] = {"adjustments": b["adjustments"]}
        if "mountain" in b:
            comps["minecraft:mountain_parameters"] = b["mountain"]
        if "map_tints" in b:
            comps["minecraft:map_tints"] = b["map_tints"]
        if b.get("humid"):
            comps["minecraft:humidity"] = {"is_humid": True}
        if "village" in b:
            comps["minecraft:village_type"] = {"type": b["village"]}
        comps["minecraft:replace_biomes"] = {"replacements": b["replace"]}
        comps["minecraft:tags"] = {"tags": b["tags"] + [f"{NS}_{name}"]}
        write(BP / "biomes" / f"{name}.biome.json", {
            "format_version": "1.26.0",
            "minecraft:biome": {
                "description": {"identifier": f"{NS}:{name}"},
                "components": comps,
            },
        })


# ---------------------------------------------------------------------------
# Features (behavior pack)
# ---------------------------------------------------------------------------

HEIGHTMAP = "query.heightmap(variable.worldx, variable.worldz)"

SOFT = ["air", "short_grass", "fern", "snow_layer", "moss_carpet", "leaf_litter", "pink_petals",
        "wildflowers", "dandelion", "poppy", "deadbush", "bush"]
GROUND = ["grass_block", "dirt", "coarse_dirt", "podzol", "moss_block", "stone", "snow",
          "granite", "andesite", "diorite", "tuff", "deepslate", "calcite", "gravel",
          "packed_ice", "powder_snow", "hardened_clay", "orange_terracotta", "white_terracotta",
          "red_terracotta", "yellow_terracotta"]
ROCK_REPLACE = [mc(b) for b in SOFT + GROUND]
SOIL = [mc(b) for b in ["grass_block", "dirt", "coarse_dirt", "podzol", "moss_block",
                         "dirt_with_roots", "farmland", "mud", "mycelium"]]
TREE_REPLACE = [mc(b) for b in [
    "air", "oak_leaves", "spruce_leaves", "birch_leaves", "jungle_leaves", "acacia_leaves",
    "dark_oak_leaves", "azalea_leaves", "azalea_leaves_flowered", "cherry_leaves", "short_grass",
    "fern", "tall_grass", "large_fern", "snow_layer", "moss_carpet", "leaf_litter", "pink_petals",
    "wildflowers", "dandelion", "poppy", "bush", "firefly_bush", "sweet_berry_bush", "vine"]]
TREE_THROUGH = [mc(b) for b in [
    "dirt", "grass_block", "short_grass", "fern", "tall_grass", "large_fern", "snow_layer",
    "moss_carpet", "leaf_litter", "pink_petals", "wildflowers", "dandelion", "poppy", "bush"]]

features = {}   # name -> json
rules = {}      # name -> json


def fid(name):
    return f"{NS}:{name}"


def add_feature(kind, name, body, fmt="1.13.0"):
    assert name not in features, name
    features[name] = {
        "format_version": fmt,
        f"minecraft:{kind}": {"description": {"identifier": fid(name)}, **body},
    }
    return fid(name)


def uniform(a, b):
    return {"distribution": "uniform", "extent": [a, b]}


def gaussian(a, b):
    return {"distribution": "gaussian", "extent": [a, b]}


def chance(n, d):
    return {"numerator": n, "denominator": d}


def add_rule(name, feature, biome, placement, distribution):
    assert name not in rules, name
    rules[name] = {
        "format_version": "1.13.0",
        "minecraft:feature_rules": {
            "description": {"identifier": fid(name), "places_feature": feature},
            "conditions": {
                "placement_pass": placement,
                "minecraft:biome_filter": [
                    {"test": "has_biome_tag", "operator": "==", "value": f"{NS}_{biome}"}
                ],
            },
            "distribution": distribution,
        },
    }


def block(name, states=None):
    return {"name": mc(name), "states": states} if states else mc(name)


def blob(name, material, count):
    """A lump of rock (ore-style vein that may also replace air)."""
    return add_feature("ore_feature", name, {
        "count": count,
        "replace_rules": [{"places_block": mc(material), "may_replace": ROCK_REPLACE}],
    })


def mixed(name, choices):
    return add_feature("weighted_random_feature", name, {"features": [[f, w] for f, w in choices]})


def structure_feature(name, variants):
    """Places one of several pre-built rock formations (see build_structures)."""
    choices = []
    for variant in variants:
        choices.append([add_feature("structure_template_feature", f"{variant}_feature", {
            "structure_name": f"{NS}:{variant}",
            "adjustment_radius": 0,
            "facing_direction": "random",
            "constraints": {},
        }), 1])
    return add_feature("weighted_random_feature", f"{name}_feature", {"features": choices})


def formation(rule, feature, biome, odds, sink=4):
    """Rock formations go in first, sunk into the slope so they grow out of it."""
    add_rule(rule, feature, biome, "first_pass", {
        "iterations": 1,
        "scatter_chance": chance(*odds),
        "x": uniform(0, 15),
        "y": f"{HEIGHTMAP} - {sink}",
        "z": uniform(0, 15),
    })


def column(name, tip, frustum, middle, base, hmin, hmax, on):
    return add_feature("multipart_block_column_feature", name, {
        "tip_block": tip, "frustum_block": frustum, "middle_block": middle, "base_block": base,
        "height_range": {"range_min": hmin, "range_max": hmax},
        "direction": "UP",
        "may_place_on": [mc(b) for b in on],
        "may_replace": [mc(b) for b in SOFT],
    })


def plant(name, blk, survive=True, attach=None):
    body = {
        "places_block": blk,
        "enforce_placement_rules": survive,
        "enforce_survivability_rules": survive,
        "may_replace": ["minecraft:air"],
    }
    if attach:
        body["may_attach_to"] = {"bottom": [mc(b) for b in attach]}
    return add_feature("single_block_feature", f"{name}_feature", body, fmt="1.21.40")


def patch(name, blk, biome, count, odds=None, clump=False, survive=True, attach=None):
    """Ground cover placed straight from the feature rule: `count` attempts per
    chunk, either spread evenly or gathered into a clump."""
    spread = gaussian if clump else uniform
    dist = {"iterations": count, "x": spread(0, 15), "y": HEIGHTMAP, "z": spread(0, 15)}
    if odds:
        dist["scatter_chance"] = chance(*odds)
    add_rule(f"{biome}_{name}_rule", plant(name, blk, survive, attach), biome, "after_surface_pass", dist)


def on_surface(rule, feature, biome, iterations=1, odds=None, placement="surface_pass"):
    dist = {"iterations": iterations, "x": uniform(0, 15), "y": HEIGHTMAP, "z": uniform(0, 15)}
    if odds:
        dist["scatter_chance"] = chance(*odds)
    add_rule(rule, feature, biome, placement, dist)


def tree(name, parts, grow_on=None, base="dirt"):
    return add_feature("tree_feature", f"{name}_feature", {
        **parts,
        "base_block": [mc(base)],
        "may_grow_on": grow_on or SOIL,
        "may_replace": TREE_REPLACE,
        "may_grow_through": TREE_THROUGH,
    })


def oak_parts(log, leaves, hmin=4, hmax=7):
    return {
        "trunk": {"trunk_height": {"range_min": hmin, "range_max": hmax}, "trunk_block": mc(log)},
        "canopy": {
            "canopy_offset": {"min": -3, "max": 0},
            "min_width": 1,
            "canopy_slope": {"rise": 2, "run": 1},
            "variation_chance": [chance(1, 2), chance(1, 2), chance(1, 2), chance(1, 1)],
            "leaf_block": mc(leaves),
        },
    }


def fancy_parts(log, leaves, base=5, variance=12):
    return {
        "fancy_trunk": {
            "trunk_height": {"base": base, "variance": variance, "scale": 0.618},
            "trunk_width": 1,
            "branches": {"slope": 0.381, "density": 1.0, "min_altitude_factor": 0.2},
            "trunk_block": mc(log),
            "width_scale": 1.0,
            "foliage_altitude_factor": 0.3,
        },
        "fancy_canopy": {"height": 4, "radius": 3, "leaf_block": mc(leaves)},
    }


def spruce_parts(hmin=6, hmax=10):
    return {
        "trunk": {
            "trunk_height": {"range_min": hmin, "range_max": hmax},
            "height_modifier": {"range_min": -2, "range_max": 1},
            "trunk_block": "minecraft:spruce_log",
        },
        "spruce_canopy": {
            "lower_offset": {"range_min": 1, "range_max": 3},
            "upper_offset": {"range_min": 1, "range_max": 3},
            "max_radius": {"range_min": 2, "range_max": 4},
            "leaf_block": "minecraft:spruce_leaves",
        },
    }


def mega_spruce_parts():
    return {
        "mega_trunk": {
            "trunk_width": 2,
            "trunk_height": {"base": 13, "intervals": [15, 3]},
            "trunk_block": "minecraft:spruce_log",
        },
        "mega_pine_canopy": {
            "canopy_height": {"range_min": 13, "range_max": 17},
            "base_radius": 0,
            "radius_step_modifier": 3.5,
            "core_width": 2,
            "leaf_block": "minecraft:spruce_leaves",
        },
    }


def leaning_trunk(log, base, interval):
    return {
        "trunk_width": 1,
        "trunk_height": {"base": base, "intervals": [interval], "min_height_for_canopy": 3},
        "trunk_block": mc(log),
        "trunk_lean": {
            "allow_diagonal_growth": True,
            "lean_height": {"range_min": 2, "range_max": 3},
            "lean_steps": {"range_min": 3, "range_max": 4},
            "lean_length": {"range_min": 1, "range_max": 2},
        },
    }


def build_features():
    # ---- Titan Peaks: black needles above the snow line -------------------
    b = "titan_peaks"
    formation("titan_spire_rule", structure_feature("titan_spire", STRUCTURES["titan_spire"]), b, (1, 4))
    rock = mixed("titan_rock_feature", [
        (blob("titan_deepslate_blob_feature", "deepslate", 22), 4),
        (blob("titan_tuff_blob_feature", "tuff", 18), 1),
        (blob("titan_cobbled_blob_feature", "cobbled_deepslate", 18), 1),
    ])
    on_surface("titan_boulder_rule", rock, b, odds=(1, 2))
    fang = column("ice_fang_feature", "minecraft:ice", "minecraft:packed_ice", "minecraft:packed_ice",
                  "minecraft:packed_ice", 3, 9,
                  ["snow", "packed_ice", "blue_ice", "stone", "deepslate", "tuff", "powder_snow"])
    on_surface("titan_ice_fang_rule", fang, b, iterations=2, odds=(1, 2))

    # ---- Frostfang Slopes: glacier teeth ----------------------------------
    b = "frostfang_slopes"
    formation("frost_spire_rule", structure_feature("frost_spire", STRUCTURES["frost_spire"]), b, (1, 3), sink=3)
    ice = mixed("frost_ice_feature", [
        (blob("frost_packed_blob_feature", "packed_ice", 18), 4),
        (blob("frost_blue_blob_feature", "blue_ice", 12), 2),
        (blob("frost_snow_blob_feature", "snow", 16), 1),
    ])
    on_surface("frost_boulder_rule", ice, b, odds=(1, 3))
    on_surface("frost_ice_fang_rule", fang, b, iterations=4)
    frozen_spruce = tree("frozen_spruce", spruce_parts(5, 8),
                         grow_on=SOIL + ["minecraft:snow", "minecraft:stone"], base="snow")
    on_surface("frost_spruce_rule", frozen_spruce, b, iterations=1, odds=(1, 2))

    # ---- Sunset Crags: terracotta hoodoos ---------------------------------
    b = "sunset_crags"
    formation("crag_hoodoo_rule", structure_feature("crag_hoodoo", STRUCTURES["crag_hoodoo"]), b, (1, 3), sink=3)
    warm = mixed("crag_rock_feature", [
        (blob("crag_granite_blob_feature", "granite", 16), 3),
        (blob("crag_orange_blob_feature", "orange_terracotta", 14), 2),
        (blob("crag_clay_blob_feature", "hardened_clay", 14), 2),
    ])
    on_surface("crag_boulder_rule", warm, b, odds=(1, 2))
    acacia = tree("crag_acacia", {
        "acacia_trunk": leaning_trunk("acacia_log", 5, 3),
        "acacia_canopy": {"canopy_size": 2, "leaf_block": "minecraft:acacia_leaves",
                          "simplify_canopy": False},
    })
    on_surface("crag_acacia_rule", acacia, b, iterations=1, odds=(1, 2))
    patch("crag_deadbush", "minecraft:deadbush", b, count=3, odds=(1, 2))
    patch("crag_grass", "minecraft:short_grass", b, count=14)

    # ---- Emerald Highlands: giant spruces on mossy alpine slopes ----------
    b = "emerald_highlands"
    on_surface("emerald_giant_spruce_rule", tree("giant_spruce", mega_spruce_parts()), b, odds=(1, 2))
    on_surface("emerald_spruce_rule", tree("alpine_spruce", spruce_parts()), b, iterations=3)
    mossy = mixed("mossy_rock_feature", [
        (blob("mossy_cobble_blob_feature", "mossy_cobblestone", 20), 3),
        (blob("mossy_stone_blob_feature", "stone", 20), 2),
        (blob("mossy_andesite_blob_feature", "andesite", 16), 1),
    ])
    on_surface("emerald_boulder_rule", mossy, b, odds=(1, 2))
    patch("emerald_fern", "minecraft:fern", b, count=18)
    patch("emerald_grass", "minecraft:short_grass", b, count=40)
    patch("emerald_cornflower", "minecraft:cornflower", b, count=9, odds=(1, 3), clump=True)
    patch("emerald_daisy", "minecraft:oxeye_daisy", b, count=9, odds=(1, 3), clump=True)
    patch("emerald_lily", "minecraft:lily_of_the_valley", b, count=7, odds=(1, 4), clump=True)
    patch("emerald_berries", block("sweet_berry_bush", {"growth": 3}), b, count=5, odds=(1, 5), clump=True)
    patch("emerald_fireflies", "minecraft:firefly_bush", b, count=3, odds=(1, 3))

    # ---- Glowwood Forest: lantern trees, moss and fireflies ---------------
    b = "glowwood_forest"
    glow_tree = tree("glowwood_tree", {
        "acacia_trunk": leaning_trunk("dark_oak_log", 5, 3),
        "random_spread_canopy": {
            "canopy_height": 2,
            "canopy_radius": 3,
            "leaf_placement_attempts": 60,
            "leaf_blocks": [["minecraft:azalea_leaves", 6], ["minecraft:azalea_leaves_flowered", 3],
                            ["minecraft:shroomlight", 1]],
        },
    }, base="dirt_with_roots")
    on_surface("glowwood_tree_rule", glow_tree, b, iterations=4)
    elder = tree("glowwood_elder", fancy_parts("dark_oak_log", "azalea_leaves_flowered", 6, 12))
    on_surface("glowwood_elder_rule", elder, b, odds=(1, 2))
    on_surface("glowwood_boulder_rule", mossy, b, odds=(1, 3))
    patch("glowwood_fireflies", "minecraft:firefly_bush", b, count=5)
    patch("glowwood_moss", "minecraft:moss_carpet", b, count=22, survive=False, attach=GROUND)
    patch("glowwood_fern", "minecraft:fern", b, count=16)
    patch("glowwood_orchid", "minecraft:blue_orchid", b, count=8, odds=(1, 3), clump=True)
    patch("glowwood_brown_mushroom", "minecraft:brown_mushroom", b, count=4, odds=(1, 3), clump=True)
    patch("glowwood_red_mushroom", "minecraft:red_mushroom", b, count=3, odds=(1, 4), clump=True)

    # ---- Autumn Woods: tinted oaks, leaf litter and pumpkins --------------
    b = "autumn_woods"
    on_surface("autumn_oak_rule", tree("autumn_oak", oak_parts("oak_log", "oak_leaves")), b, iterations=5)
    on_surface("autumn_big_oak_rule", tree("autumn_big_oak", fancy_parts("oak_log", "oak_leaves")), b)
    on_surface("autumn_dark_oak_rule",
               tree("autumn_dark_oak", oak_parts("dark_oak_log", "dark_oak_leaves", 5, 8)), b, iterations=2)
    fallen = tree("autumn_fallen_log", {
        "fallen_trunk": {"log_length": {"range_min": 3, "range_max": 6},
                         "trunk_block": "minecraft:oak_log"},
    })
    on_surface("autumn_fallen_log_rule", fallen, b, odds=(1, 3))
    patch("autumn_litter", block("leaf_litter", {"growth": 3}), b, count=45, survive=False, attach=GROUND)
    patch("autumn_pumpkin", "minecraft:pumpkin", b, count=4, odds=(1, 6), clump=True,
          survive=False, attach=GROUND)
    patch("autumn_bush", "minecraft:bush", b, count=6)
    patch("autumn_berries", block("sweet_berry_bush", {"growth": 3}), b, count=5, odds=(1, 5), clump=True)
    patch("autumn_red_mushroom", "minecraft:red_mushroom", b, count=3, odds=(1, 3), clump=True)
    patch("autumn_grass", "minecraft:short_grass", b, count=14)

    # ---- Crystal Fields: amethyst spikes in a mint meadow -----------------
    b = "crystal_fields"
    formation("crystal_shard_rule", structure_feature("crystal_shard", STRUCTURES["crystal_shard"]), b,
              (1, 5), sink=2)
    crystal = column("crystal_spike_feature",
                     block("amethyst_cluster", {"minecraft:block_face": "up"}),
                     "minecraft:amethyst_block", "minecraft:amethyst_block", "minecraft:calcite", 2, 7,
                     ["grass_block", "dirt", "calcite", "stone", "amethyst_block", "smooth_basalt"])
    on_surface("crystal_spike_rule", crystal, b, iterations=3, odds=(1, 2))
    gem = mixed("crystal_rock_feature", [
        (blob("crystal_amethyst_blob_feature", "amethyst_block", 12), 3),
        (blob("crystal_calcite_blob_feature", "calcite", 16), 2),
        (blob("crystal_basalt_blob_feature", "smooth_basalt", 14), 1),
    ])
    on_surface("crystal_boulder_rule", gem, b, odds=(1, 4))
    patch("crystal_petals", block("pink_petals", {"growth": 3}), b, count=40)
    patch("crystal_allium", "minecraft:allium", b, count=10, odds=(1, 2), clump=True)
    patch("crystal_cornflower", "minecraft:cornflower", b, count=8, odds=(1, 3), clump=True)
    patch("crystal_grass", "minecraft:short_grass", b, count=40)

    for name, data in features.items():
        write(BP / "features" / f"{name}.json", data)
    for name, data in rules.items():
        write(BP / "feature_rules" / f"{name}.json", data)


# ---------------------------------------------------------------------------
# Rock formations (.mcstructure files, behavior pack)
# ---------------------------------------------------------------------------
# Custom biomes cannot reshape terrain noise, so the extra relief is modelled
# here: needles, glacier teeth, hoodoos and crystal clusters that grow out of
# the vanilla mountain slopes.

BLOCK_VERSION = 18163713  # 1.21.40.1
BLOCK_STATES = {"minecraft:deepslate": {"pillar_axis": "y"}}


def nbt_string(text):
    raw = text.encode("utf-8")
    return struct.pack("<H", len(raw)) + raw


def nbt_payload(value):
    """Little-endian NBT payload for ints, strings, lists and dicts."""
    if isinstance(value, bool):
        raise TypeError("bool is not supported")
    if isinstance(value, int):
        return 3, struct.pack("<i", value)
    if isinstance(value, str):
        return 8, nbt_string(value)
    if isinstance(value, dict):
        out = b""
        for key, item in value.items():
            tag, payload = nbt_payload(item)
            out += bytes([tag]) + nbt_string(key) + payload
        return 10, out + b"\x00"
    if isinstance(value, list):
        items = [nbt_payload(item) for item in value]
        tag = items[0][0] if items else 0
        assert all(t == tag for t, _ in items), "mixed list"
        return 9, bytes([tag]) + struct.pack("<i", len(items)) + b"".join(p for _, p in items)
    raise TypeError(type(value))


def mcstructure(cells):
    """cells: {(x, y, z): block id}.  Empty cells stay structure void (-1), so
    the terrain around a formation is left untouched."""
    xs, ys, zs = zip(*cells)
    ox, oy, oz = min(xs), min(ys), min(zs)
    sx, sy, sz = max(xs) - ox + 1, max(ys) - oy + 1, max(zs) - oz + 1
    assert max(sx, sz) <= 13 and sy <= 64, (sx, sy, sz)
    palette = sorted(set(cells.values()))
    index = [-1] * (sx * sy * sz)
    for (x, y, z), name in cells.items():
        index[((x - ox) * sy + (y - oy)) * sz + (z - oz)] = palette.index(name)
    _, payload = nbt_payload({
        "format_version": 1,
        "size": [sx, sy, sz],
        "structure": {
            "block_indices": [index, [-1] * len(index)],
            "entities": [],
            "palette": {"default": {
                "block_palette": [{"name": name, "states": BLOCK_STATES.get(name, {}),
                                   "version": BLOCK_VERSION} for name in palette],
                "block_position_data": {},
            }},
        },
        "structure_world_origin": [0, 0, 0],
    })
    return b"\x0a" + nbt_string("") + payload


def carve(rng, height, radius_at, material_at, lean=(0.0, 0.0), rough=0.35):
    """Stack of rough discs.  radius_at(t) and material_at(t, x, y, z) take the
    relative height t in 0..1."""
    cells = {}
    for y in range(height):
        t = y / max(1, height - 1)
        cx, cz = lean[0] * y, lean[1] * y
        r = radius_at(t)
        reach = int(r) + 2
        for x in range(round(cx) - reach, round(cx) + reach + 1):
            for z in range(round(cz) - reach, round(cz) + reach + 1):
                if math.hypot(x - cx, z - cz) <= r + rng.uniform(-rough, rough):
                    cells[(x, y, z)] = material_at(t, x, y, z)
    return cells


def cap_tops(cells, block_id, from_y):
    """Dust every exposed top face above from_y (snow on ledges)."""
    for (x, y, z) in list(cells):
        if y >= from_y and (x, y + 1, z) not in cells:
            cells[(x, y, z)] = block_id


def speckle(rng, base, accents):
    """Material picker: base rock with clumpy veins of accent rock."""
    table = {}

    def pick(t, x, y, z):
        key = (x // 2, y // 3, z // 2)
        if key not in table:
            roll = rng.random()
            table[key] = base
            for name, share in accents:
                if roll < share:
                    table[key] = name
                    break
                roll -= share
        return table[key]

    return pick


def crop(cells, limit=13):
    """Keep the formation inside a limit x limit footprint."""
    xs = [x for x, _, _ in cells]
    zs = [z for _, _, z in cells]
    cx, cz = (min(xs) + max(xs)) // 2, (min(zs) + max(zs)) // 2
    half = limit // 2
    return {k: v for k, v in cells.items() if abs(k[0] - cx) <= half and abs(k[2] - cz) <= half}


STRUCTURES = {
    "titan_spire": [f"titan_spire_{i}" for i in range(1, 5)],
    "frost_spire": [f"frost_spire_{i}" for i in range(1, 4)],
    "crag_hoodoo": [f"crag_hoodoo_{i}" for i in range(1, 4)],
    "crystal_shard": [f"crystal_shard_{i}" for i in range(1, 4)],
}


def build_structures():
    rng = random.Random(20261111)
    out = {}

    # Titan needles: 24-40 blocks of dark rock with snow on every ledge.
    for name, height in zip(STRUCTURES["titan_spire"], (24, 30, 35, 40)):
        base = rng.uniform(4.6, 5.4)
        lean = (rng.uniform(-0.06, 0.06), rng.uniform(-0.06, 0.06))
        cells = carve(rng, height, lambda t, b=base: b * (1 - t) ** 0.8 + 0.4,
                      speckle(rng, "minecraft:deepslate", [("minecraft:tuff", 0.14),
                                                           ("minecraft:cobbled_deepslate", 0.12),
                                                           ("minecraft:blackstone", 0.08)]), lean)
        cap_tops(cells, "minecraft:snow", height // 3)
        out[name] = crop(cells)

    # Glacier teeth: shorter, sharper, blue-veined.
    for name, height in zip(STRUCTURES["frost_spire"], (15, 20, 26)):
        base = rng.uniform(3.4, 4.4)
        lean = (rng.uniform(-0.1, 0.1), rng.uniform(-0.1, 0.1))
        cells = carve(rng, height, lambda t, b=base: b * (1 - t) ** 1.1 + 0.4,
                      speckle(rng, "minecraft:packed_ice", [("minecraft:blue_ice", 0.3)]), lean, rough=0.25)
        cap_tops(cells, "minecraft:snow", height // 2)
        out[name] = crop(cells)

    # Hoodoos: banded neck with a wide cap rock.
    bands = ["minecraft:granite", "minecraft:orange_terracotta", "minecraft:hardened_clay",
             "minecraft:white_terracotta", "minecraft:orange_terracotta", "minecraft:red_terracotta",
             "minecraft:yellow_terracotta"]
    for name, height in zip(STRUCTURES["crag_hoodoo"], (14, 18, 23)):
        shift = rng.randrange(len(bands))

        def profile(t):
            if t < 0.6:
                return 3.4 - 3.2 * t          # base narrowing into the neck
            if t < 0.8:
                return 1.5 + (t - 0.6) * 9.0  # flares out under the cap
            return 3.3 - (t - 0.8) * 7.0      # rounded cap

        def strata(t, x, y, z, shift=shift):
            if t >= 0.78:
                return "minecraft:red_terracotta"
            return bands[(y // 2 + shift) % len(bands)]

        out[name] = crop(carve(rng, height, profile, strata, rough=0.3))

    # Crystal clusters: a few leaning amethyst prisms on a calcite foot.
    for name, count in zip(STRUCTURES["crystal_shard"], (3, 4, 5)):
        cells = {}
        gem = speckle(rng, "minecraft:amethyst_block", [("minecraft:budding_amethyst", 0.1)])
        for i in range(count):
            height = rng.randint(7, 15) if i else rng.randint(13, 17)
            width = rng.uniform(1.3, 2.1)
            angle = rng.uniform(0, math.tau)
            tilt = rng.uniform(0.12, 0.3) if i else 0.05
            lean = (math.cos(angle) * tilt, math.sin(angle) * tilt)
            prism = carve(rng, height, lambda t, w=width: w * (1 - t ** 3) + 0.2, gem, lean, rough=0.1)
            cells.update(prism)
        foot = carve(rng, 3, lambda t: 4.2 - 1.6 * t,
                     speckle(rng, "minecraft:calcite", [("minecraft:smooth_basalt", 0.35)]))
        for key, value in foot.items():
            cells.setdefault(key, value)
        out[name] = crop(cells)

    for name, cells in out.items():
        path = BP / "structures" / NS / f"{name}.mcstructure"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(mcstructure(cells))
    return out


# ---------------------------------------------------------------------------
# Vibrant Visuals ("hyper shaders") settings - resource pack
# ---------------------------------------------------------------------------

def k(t):
    return f"{t:.6f}"


def lighting(identifier, sun_tint=(1.0, 1.0, 1.0), moon=0.8, ambient=0.03, ambient_color="#DCE8FF",
             tilt=15.0):
    def tint(c):
        return [min(255, round(v * m)) for v, m in zip(c, sun_tint)]

    sun_color = {
        0.0: (255, 240, 224), 0.12: (255, 226, 196), 0.19: (255, 190, 120), 0.235: (255, 140, 60),
        0.262: (255, 105, 45), 0.30: (255, 120, 110), 0.5: (255, 105, 0), 0.70: (255, 125, 120),
        0.738: (255, 110, 50), 0.765: (255, 150, 70), 0.81: (255, 195, 125), 0.88: (255, 228, 198),
        1.0: (255, 240, 224),
    }
    return {
        "format_version": "1.21.80",
        "minecraft:lighting_settings": {
            "description": {"identifier": identifier},
            "directional_lights": {
                "orbital": {
                    "sun": {
                        "illuminance": {
                            k(0.0): 100.0, k(0.05): 100.0, k(0.282): 1.0, k(0.2915): 0.01,
                            k(0.292): 0.0, k(0.709): 0.0, k(0.719): 1.0, k(0.95): 100.0, k(1.0): 100.0,
                        },
                        "color": {k(t): tint(c) for t, c in sun_color.items()},
                    },
                    "moon": {
                        "illuminance": {
                            k(0.0): 0.0, k(0.2): 0.0, k(0.225): moon, k(0.735): moon, k(0.75): 0.0,
                            k(1.0): 0.0,
                        },
                        "color": {k(0.0): [150, 180, 255], k(1.0): [150, 180, 255]},
                    },
                    "orbital_offset_degrees": tilt,
                },
                "flash": {"illuminance": 10.0, "color": [228, 93, 255]},
            },
            "emissive": {"desaturation": 0.0},
            "ambient": {"color": ambient_color, "illuminance": ambient},
            "sky": {"intensity": 1.0},
        },
    }


def atmosphere(identifier, zenith_day, zenith_night, horizon_day, horizon_night, sunset, dusk,
               rayleigh=(10.0, 5.0), sun_glow=0.9, moon_glow=0.2):
    r_day, r_dusk = rayleigh
    return {
        "format_version": "1.21.40",
        "minecraft:atmosphere_settings": {
            "description": {"identifier": identifier},
            "horizon_blend_stops": {
                "min": {k(0.0): 0.0, k(1.0): 0.0},
                "start": {k(0.0): 0.8, k(0.25): 0.5, k(0.300912): 0.25, k(0.75): 0.25,
                          k(0.827004): 0.5, k(1.0): 0.8},
                "mie_start": {k(0.0): 0.5, k(0.1): 0.5, k(0.2): 1.0, k(0.8): 1.0, k(0.9): 0.5,
                              k(1.0): 0.5},
                "max": {k(0.0): 0.25, k(1.0): 0.25},
            },
            "rayleigh_strength": {
                k(0.0): r_day, k(0.138743): r_day, k(0.25): r_dusk, k(0.330402): r_dusk,
                k(0.640704): r_dusk, k(0.717412): r_dusk, k(0.92931): r_day, k(1.0): r_day,
            },
            "sun_mie_strength": {
                k(0.0): 0.1, k(0.2): 0.15, k(0.25): sun_glow, k(0.3): 0.0, k(0.7): 0.0,
                k(0.75): sun_glow, k(0.8): 0.15, k(1.0): 0.1,
            },
            "moon_mie_strength": {k(0.0): 0.0, k(0.25): 0.0, k(0.35): moon_glow, k(0.65): moon_glow,
                                  k(0.75): 0.0, k(1.0): 0.0},
            "sun_glare_shape": {
                k(0.0): 0.02, k(0.2): 0.03, k(0.25): 0.074, k(0.3): 0.0, k(0.7): 0.0,
                k(0.75): 0.05, k(0.8): 0.03, k(1.0): 0.02,
            },
            "sky_zenith_color": {
                k(0.0): list(zenith_day), k(0.199685): list(zenith_day), k(0.35256): list(zenith_night),
                k(0.64488): list(zenith_night), k(0.800315): list(zenith_day), k(1.0): list(zenith_day),
            },
            "sky_horizon_color": {
                k(0.0): list(horizon_day), k(0.167053): list(horizon_day), k(0.217114): list(sunset),
                k(0.239274): list(dusk), k(0.276382): [120, 96, 120], k(0.361464): list(horizon_night),
                k(0.616996): list(horizon_night), k(0.654508): [130, 120, 210],
                k(0.706861): list(dusk), k(0.748744): list(sunset), k(0.786432): [232, 214, 190],
                k(0.830049): list(horizon_day), k(1.0): list(horizon_day),
            },
        },
    }


def grading(identifier, contrast=1.25, saturation=1.2, temperature=6500, gain=(1.0, 1.0, 1.0)):
    return {
        "format_version": "1.21.90",
        "minecraft:color_grading_settings": {
            "description": {"identifier": identifier},
            "color_grading": {
                "midtones": {
                    "contrast": [contrast] * 3,
                    "gain": list(gain),
                    "gamma": [2.2, 2.2, 2.2],
                    "offset": [0.0, 0.0, 0.0],
                    "saturation": [saturation] * 3,
                },
                "temperature": {"enabled": True, "temperature": temperature, "type": "color_temperature"},
            },
            "tone_mapping": {"operator": "generic"},
        },
    }


def water(identifier, chlorophyll=0.1, sediment=0.05, cdom=0.05, wave_depth=1.2, caustic_power=2):
    return {
        "format_version": "1.21.120",
        "minecraft:water_settings": {
            "description": {"identifier": identifier},
            "particle_concentrations": {"chlorophyll": chlorophyll, "suspended_sediment": sediment,
                                        "cdom": cdom},
            "caustics": {"enabled": True, "frame_length": 0.07, "scale": 0.6, "power": caustic_power},
            "waves": {
                "enabled": True, "frequency": 1, "octaves": 16, "depth": wave_depth, "speed": 2,
                "shape": 1.5, "pull": 0.38, "mix": 0.2, "frequency_scaling": 1.2, "speed_scaling": 1.03,
            },
        },
    }


def water_fog(color):
    return {
        "fog_start": 0, "fog_end": 60.0, "fog_color": color, "render_distance_type": "fixed",
        "transition_fog": {
            "init_fog": {"fog_start": 0.0, "fog_end": 0.01, "fog_color": color,
                         "render_distance_type": "fixed"},
            "min_percent": 0.25, "mid_seconds": 5, "mid_percent": 0.6, "max_seconds": 30,
        },
    }


def volumetric_fog(density, low, high, scattering, g):
    """Haze is thickest at `low` and gone by `high`, so peaks rise out of it."""
    return {
        "density": {"air": {"max_density": density, "max_density_height": low,
                            "zero_density_height": high}},
        "media_coefficients": {"air": {"scattering": list(scattering), "absorption": [0.0, 0.0, 0.0]}},
        "henyey_greenstein_g": {"air": {"henyey_greenstein_g": g}},
    }


def fog(identifier, air_color="#ABD2FF", water_color="#44AFF5", density=0.06, low=64.0, high=280.0,
        scattering=(0.05, 0.055, 0.065), g=0.7, air_start=0.92):
    return {
        "format_version": "1.21.90",
        "minecraft:fog_settings": {
            "description": {"identifier": identifier},
            "distance": {
                "air": {"fog_start": air_start, "fog_end": 1.0, "fog_color": air_color,
                        "render_distance_type": "render"},
                "water": water_fog(water_color),
            },
            "volumetric": volumetric_fog(density, low, high, scattering, g),
        },
    }


# Vanilla overworld fogs without a volumetric section, with their own water
# fog colour (kept as in vanilla).
VANILLA_FOG_WATER = {
    "plains": "#44AFF5", "forest": "#1E97F2", "forest_hills": "#056bd1", "birch_forest": "#0677ce",
    "birch_forest_hills": "#0a74c4", "cherry_grove": "#5db7ef", "extreme_hills": "#007BF7",
    "extreme_hills_edge": "#045cd5", "extreme_hills_mutated": "#0E63AB", "savanna": "#2C8B9C",
    "savanna_mutated": "#2590A8", "savanna_plateau": "#2590A8", "river": "#0084FF",
    "ocean": "#1165b0", "deep_ocean": "#1463a5", "cold_ocean": "#14559b",
    "deep_cold_ocean": "#185390", "stone_beach": "#0d67bb", "cold_beach": "#1463a5",
    "mesa_mutated": "#497F99", "dappled_forest": "#1E97F2", "mega_spruce_taiga": "#2d6d77",
    "mega_spruce_taiga_mutated": "#2d6d77", "mega_taiga_mutated": "#2d6d77",
}


# Look of each custom biome.  All colours are picked to read well both with
# Vibrant Visuals and with the classic renderer (fog / sky / water / tint).
LOOKS = {
    "titan_peaks": {
        "sky": "#5E9BFF", "water_color": "#3F8FE0", "grass": "#7FA08A", "foliage": "#5F8F78",
        "atmos": dict(zenith_day=(46, 104, 214), zenith_night=(12, 16, 38), horizon_day=(176, 210, 245),
                      horizon_night=(60, 86, 140), sunset=(255, 170, 120), dusk=(255, 130, 150)),
        "grade": dict(contrast=1.32, saturation=1.1, temperature=7400),
        "water": dict(chlorophyll=0.02, sediment=0.0, cdom=0.0, wave_depth=1.0),
        "fog": dict(air_color="#C4DDFF", water_color="#3F8FE0", density=0.09, low=90.0, high=190.0,
                    scattering=(0.05, 0.058, 0.075), g=0.75),
        "music": "jagged_peaks", "precipitation": {"white_ash": 1.5},
    },
    "frostfang_slopes": {
        "sky": "#8FC4FF", "water_color": "#52B8E8", "grass": "#86B5A0", "foliage": "#6FA595",
        "atmos": dict(zenith_day=(84, 150, 230), zenith_night=(14, 22, 48), horizon_day=(205, 230, 250),
                      horizon_night=(70, 100, 150), sunset=(255, 190, 170), dusk=(230, 160, 220)),
        "grade": dict(contrast=1.22, saturation=1.05, temperature=8200),
        "water": dict(chlorophyll=0.05, sediment=0.0, cdom=0.0, wave_depth=0.8, caustic_power=3),
        "fog": dict(air_color="#DCEEFF", water_color="#52B8E8", density=0.11, low=80.0, high=200.0,
                    scattering=(0.06, 0.068, 0.08), g=0.65),
        "music": "snowy_slopes", "precipitation": {"white_ash": 2.5},
    },
    "sunset_crags": {
        "sky": "#7FB2F0", "water_color": "#3FB5C9", "grass": "#B7A04A", "foliage": "#A9953B",
        "atmos": dict(zenith_day=(70, 122, 205), zenith_night=(22, 16, 40), horizon_day=(235, 205, 170),
                      horizon_night=(96, 80, 120), sunset=(255, 140, 70), dusk=(255, 96, 86),
                      rayleigh=(8.0, 4.0), sun_glow=1.3),
        "grade": dict(contrast=1.3, saturation=1.25, temperature=5200),
        "water": dict(chlorophyll=0.2, sediment=1.5, cdom=0.3, wave_depth=1.0),
        "fog": dict(air_color="#F0CFA3", water_color="#3FB5C9", density=0.08, low=70.0, high=230.0,
                    scattering=(0.075, 0.055, 0.035), g=0.8),
        "music": "stony_peaks", "precipitation": {"ash": 0.04},
    },
    "emerald_highlands": {
        "sky": "#6CB2FF", "water_color": "#2FD0C0", "grass": "#3FC46B", "foliage": "#2FA85A",
        "atmos": dict(zenith_day=(52, 120, 220), zenith_night=(12, 20, 42), horizon_day=(180, 220, 240),
                      horizon_night=(64, 96, 140), sunset=(255, 178, 110), dusk=(255, 140, 130)),
        "grade": dict(contrast=1.26, saturation=1.3, temperature=6300),
        "water": dict(chlorophyll=0.6, sediment=0.05, cdom=0.05, wave_depth=1.2),
        "fog": dict(air_color="#BFE3E0", water_color="#2FD0C0", density=0.1, low=70.0, high=170.0,
                    scattering=(0.05, 0.065, 0.06), g=0.72),
        "music": "meadow",
    },
    "glowwood_forest": {
        "sky": "#4E9C9C", "water_color": "#1FD6B4", "grass": "#35B38A", "foliage": "#249C7C",
        "atmos": dict(zenith_day=(44, 110, 150), zenith_night=(8, 26, 40), horizon_day=(150, 215, 200),
                      horizon_night=(40, 110, 120), sunset=(250, 190, 130), dusk=(190, 140, 220),
                      moon_glow=0.5),
        "grade": dict(contrast=1.2, saturation=1.35, temperature=6000, gain=(0.96, 1.03, 1.02)),
        "water": dict(chlorophyll=2.2, sediment=0.2, cdom=0.4, wave_depth=0.8),
        "fog": dict(air_color="#7FCDB8", water_color="#1FD6B4", density=0.22, low=62.0, high=110.0,
                    scattering=(0.03, 0.075, 0.062), g=0.6, air_start=0.75),
        "music": "lush_caves", "precipitation": {"blue_spores": 0.35},
    },
    "autumn_woods": {
        "sky": "#86B6E8", "water_color": "#4FA8C0", "grass": "#B9A23A", "foliage": "#D8691E",
        "atmos": dict(zenith_day=(74, 128, 204), zenith_night=(18, 18, 40), horizon_day=(232, 214, 186),
                      horizon_night=(84, 84, 126), sunset=(255, 160, 84), dusk=(255, 118, 100),
                      rayleigh=(9.0, 4.5), sun_glow=1.1),
        "grade": dict(contrast=1.24, saturation=1.28, temperature=5400),
        "water": dict(chlorophyll=0.3, sediment=0.8, cdom=1.0, wave_depth=0.9),
        "fog": dict(air_color="#E8D0A8", water_color="#4FA8C0", density=0.13, low=62.0, high=130.0,
                    scattering=(0.07, 0.058, 0.04), g=0.78, air_start=0.85),
        "music": "forest",
    },
    "crystal_fields": {
        "sky": "#8AA8FF", "water_color": "#5FE0E8", "grass": "#6FD8B4", "foliage": "#58C7A6",
        "atmos": dict(zenith_day=(80, 104, 226), zenith_night=(22, 14, 54), horizon_day=(206, 204, 250),
                      horizon_night=(96, 70, 160), sunset=(255, 170, 190), dusk=(214, 130, 240),
                      moon_glow=0.6),
        "grade": dict(contrast=1.22, saturation=1.32, temperature=6900, gain=(1.02, 0.98, 1.04)),
        "water": dict(chlorophyll=0.25, sediment=0.0, cdom=0.0, wave_depth=1.0, caustic_power=3),
        "fog": dict(air_color="#CFC8FF", water_color="#5FE0E8", density=0.08, low=62.0, high=140.0,
                    scattering=(0.06, 0.05, 0.08), g=0.7),
        "music": "cherry_grove",
    },
}


def build_visuals():
    # Global look (vanilla identifiers are overridden so every biome benefits).
    write(RP / "lighting" / "global.json", lighting("minecraft:default_lighting"))
    write(RP / "atmospherics" / "atmospherics.json", atmosphere(
        "minecraft:default_atmospherics", zenith_day=(58, 118, 216), zenith_night=(14, 20, 44),
        horizon_day=(178, 212, 244), horizon_night=(70, 100, 150), sunset=(255, 170, 110),
        dusk=(255, 132, 124)))
    write(RP / "atmospherics" / "warmish_atmospherics.json", atmosphere(
        "minecraft:warmish_atmospherics", zenith_day=(60, 124, 214), zenith_night=(16, 20, 44),
        horizon_day=(196, 218, 236), horizon_night=(76, 100, 146), sunset=(255, 164, 96),
        dusk=(255, 124, 108), sun_glow=1.0))
    write(RP / "color_grading" / "color_grading.json", grading("minecraft:default_color_grading"))
    write(RP / "color_grading" / "cold_color_grading.json",
          grading("minecraft:cold_color_grading", contrast=1.25, saturation=1.1, temperature=8000))
    write(RP / "color_grading" / "coolish_color_grading.json",
          grading("minecraft:coolish_color_grading", contrast=1.25, saturation=1.15, temperature=7200))
    write(RP / "color_grading" / "warmish_color_grading.json",
          grading("minecraft:warmish_color_grading", contrast=1.27, saturation=1.22, temperature=5600))
    write(RP / "color_grading" / "hot_color_grading.json",
          grading("minecraft:hot_color_grading", contrast=1.32, saturation=1.2, temperature=4400))
    write(RP / "water" / "water.json", water("minecraft:default_water"))
    # Light shafts for the overworld biomes that ship without volumetric fog.
    # The shared default fog is left alone on purpose: every dimension falls
    # back to it, and the Nether should not fill up with haze.
    for biome, water_color in VANILLA_FOG_WATER.items():
        write(RP / "fogs" / f"{biome}_fog_setting.json", {
            "format_version": "1.21.90",
            "minecraft:fog_settings": {
                "description": {"identifier": f"minecraft:fog_{biome}"},
                "distance": {"water": water_fog(water_color)},
                "volumetric": volumetric_fog(0.06, 64.0, 280.0, (0.05, 0.055, 0.065), 0.7),
            },
        })
    write(RP / "shadows" / "global.json", {
        "format_version": "1.21.80",
        "minecraft:shadow_settings": {"shadow_style": "soft_shadows", "texel_size": 16},
    })

    # Per-biome moods.
    for name, look in LOOKS.items():
        write(RP / "atmospherics" / f"{NS}_{name}_atmospherics.json",
              atmosphere(f"{NS}:{name}_atmospherics", **look["atmos"]))
        write(RP / "color_grading" / f"{NS}_{name}_color_grading.json",
              grading(f"{NS}:{name}_color_grading", **look["grade"]))
        write(RP / "water" / f"{NS}_{name}_water.json", water(f"{NS}:{name}_water", **look["water"]))
        write(RP / "fogs" / f"{NS}_{name}_fog_setting.json", fog(f"{NS}:fog_{name}", **look["fog"]))
        comps = {
            "minecraft:sky_color": {"sky_color": look["sky"]},
            "minecraft:fog_appearance": {"fog_identifier": f"{NS}:fog_{name}"},
            "minecraft:water_appearance": {"surface_color": look["water_color"]},
            "minecraft:grass_appearance": {"color": look["grass"]},
            "minecraft:foliage_appearance": {"color": look["foliage"]},
            "minecraft:atmosphere_identifier": {"atmosphere_identifier": f"{NS}:{name}_atmospherics"},
            "minecraft:color_grading_identifier": {"color_grading_identifier": f"{NS}:{name}_color_grading"},
            "minecraft:lighting_identifier": {"lighting_identifier": "minecraft:default_lighting"},
            "minecraft:water_identifier": {"water_identifier": f"{NS}:{name}_water"},
            "minecraft:ambient_sounds": {
                "underwater_addition": {"asset": "ambient.underwater.additions", "chance": 0.01},
                "underwater_loop": "ambient.underwater.loop",
            },
            "minecraft:biome_music": {"music_definition": look["music"]},
        }
        if "precipitation" in look:
            comps["minecraft:precipitation"] = look["precipitation"]
        write(RP / "biomes" / f"{name}.client_biome.json", {
            "format_version": "1.21.120",
            "minecraft:client_biome": {
                "description": {"identifier": f"{NS}:{name}"},
                "components": comps,
            },
        })


# ---------------------------------------------------------------------------
# Ambient particles (resource pack) - spawned by scripts/main.js
# ---------------------------------------------------------------------------

def particle(name, material, size, lifetime, colors, accel, drag=0.0, speed=0.0, fade=True,
             spin=False, collide=False, init=None, update=None):
    comps = {
        "minecraft:emitter_lifetime_once": {},
        "minecraft:emitter_rate_instant": {"num_particles": 1},
        "minecraft:emitter_shape_point": {},
        "minecraft:particle_appearance_billboard": {
            "size": [size, size],
            "facing_camera_mode": "lookat_xyz",
            "uv": {"texture_width": 1, "texture_height": 1, "uv": [0, 0], "uv_size": [1, 1]},
        },
        "minecraft:particle_appearance_tinting": {"color": colors},
        "minecraft:particle_initial_speed": speed,
        "minecraft:particle_lifetime_expression": {"max_lifetime": lifetime},
        "minecraft:particle_motion_dynamic": {"linear_acceleration": accel,
                                              "linear_drag_coefficient": drag},
    }
    if init or update:
        comps["minecraft:emitter_initialization"] = {}
        if init:
            comps["minecraft:emitter_initialization"]["creation_expression"] = init
        if update:
            comps["minecraft:emitter_initialization"]["per_update_expression"] = update
    if spin:
        comps["minecraft:particle_initial_spin"] = {"rotation": "math.random(0, 360)",
                                                    "rotation_rate": "math.random(-120, 120)"}
    if collide:
        comps["minecraft:particle_motion_collision"] = {"collision_radius": size,
                                                        "expire_on_contact": True}
    return {
        "format_version": "1.10.0",
        "particle_effect": {
            "description": {
                "identifier": f"{NS}:{name}",
                "basic_render_parameters": {"material": material, "texture": "textures/particle/pixel"},
            },
            "components": comps,
        },
    }


def glow(rgb):
    r, g, b = rgb
    return {
        "gradient": {"0.0": [r, g, b, 0], "0.25": [r, g, b, 1], "0.6": [r, g, b, 1], "1.0": [r, g, b, 0]},
        "interpolant": "v.particle_age / v.particle_lifetime",
    }


WANDER_INIT = ("v.ax = math.random(-3, 3); v.ay = math.random(-2, 2); v.az = math.random(-3, 3);")
WANDER_UPDATE = ("v.turn = math.random(0, 1) <= 0.06; v.turn ? (v.ax = math.random(-3, 3));"
                 " v.turn ? (v.ay = math.random(-2, 2)); v.turn ? (v.az = math.random(-3, 3));")


def build_particles():
    p = RP / "particles"
    write(p / "hyper_firefly.json", particle(
        "firefly", "particles_blend", 0.05, "math.random(6, 11)", glow((0.82, 1.0, 0.42)),
        ["v.ax", "v.ay", "v.az"], drag=3.0, speed=0.4, init=WANDER_INIT, update=WANDER_UPDATE))
    write(p / "hyper_crystal_mote.json", particle(
        "crystal_mote", "particles_blend", 0.045, "math.random(5, 9)", glow((0.78, 0.55, 1.0)),
        ["math.sin(v.particle_age * 90 + v.particle_random_1 * 360) * 0.4", 0.35,
         "math.cos(v.particle_age * 90 + v.particle_random_2 * 360) * 0.4"], drag=2.0))
    write(p / "hyper_falling_leaf.json", particle(
        "falling_leaf", "particles_alpha", 0.07, "math.random(6, 10)", {
            "gradient": {"0.0": "#FFD24A", "0.5": "#FF8A1F", "1.0": "#C8321E"},
            "interpolant": "v.particle_random_3",
        },
        ["math.sin(v.particle_age * 120 + v.particle_random_1 * 360) * 1.6", -0.9,
         "math.cos(v.particle_age * 100 + v.particle_random_2 * 360) * 1.6"],
        drag=1.6, spin=True, collide=True))
    write(p / "hyper_snow_glint.json", particle(
        "snow_glint", "particles_blend", 0.04, "math.random(3, 6)", glow((0.9, 0.97, 1.0)),
        [1.2, "math.sin(v.particle_age * 200 + v.particle_random_1 * 360) * 0.5 - 0.15",
         "math.random(-0.4, 0.4)"], drag=1.2))
    write(p / "hyper_ember_dust.json", particle(
        "ember_dust", "particles_blend", 0.04, "math.random(4, 8)", glow((1.0, 0.62, 0.28)),
        [0.5, "0.15 + math.sin(v.particle_age * 150 + v.particle_random_1 * 360) * 0.3",
         "math.random(-0.3, 0.3)"], drag=1.5))


# ---------------------------------------------------------------------------
# Script: ambient life + biome name banner
# ---------------------------------------------------------------------------

SCRIPT = r'''import { world, system } from "@minecraft/server";

// Hyper Realms - ambient life for the new biomes.
// Every entry: particle id, how many per pulse by day / by night, and the box
// around the player (horizontal radius, lowest and highest offset) to fill.
const AMBIENT = {
  "hyper:glowwood_forest": { particle: "hyper:firefly", day: 3, night: 9, radius: 14, low: -1, high: 6 },
  "hyper:emerald_highlands": { particle: "hyper:firefly", day: 0, night: 5, radius: 14, low: 0, high: 5 },
  "hyper:autumn_woods": { particle: "hyper:falling_leaf", day: 6, night: 3, radius: 12, low: 3, high: 9 },
  "hyper:crystal_fields": { particle: "hyper:crystal_mote", day: 2, night: 7, radius: 13, low: 0, high: 4 },
  "hyper:titan_peaks": { particle: "hyper:snow_glint", day: 6, night: 3, radius: 14, low: 0, high: 8 },
  "hyper:frostfang_slopes": { particle: "hyper:snow_glint", day: 7, night: 4, radius: 14, low: 0, high: 8 },
  "hyper:sunset_crags": { particle: "hyper:ember_dust", day: 4, night: 2, radius: 14, low: 0, high: 7 },
};

const PULSE_TICKS = 10;
const lastBiome = new Map();

function between(min, max) {
  return min + Math.random() * (max - min);
}

function isNight() {
  const time = world.getTimeOfDay();
  return time > 12800 && time < 23200;
}

function biomeIdAt(player) {
  try {
    return player.dimension.getBiome(player.location).id;
  } catch {
    return undefined;
  }
}

function pulse(player, night) {
  if (player.dimension.id !== "minecraft:overworld") return;
  const biomeId = biomeIdAt(player);
  if (biomeId === undefined) return;

  if (lastBiome.get(player.id) !== biomeId) {
    lastBiome.set(player.id, biomeId);
    if (biomeId in AMBIENT) {
      player.onScreenDisplay.setActionBar({ translate: `hyper.biome.${biomeId.split(":")[1]}` });
    }
  }

  const ambient = AMBIENT[biomeId];
  if (!ambient) return;
  const count = night ? ambient.night : ambient.day;
  const { x, y, z } = player.location;
  for (let i = 0; i < count; i++) {
    const spot = {
      x: x + between(-ambient.radius, ambient.radius),
      y: y + between(ambient.low, ambient.high),
      z: z + between(-ambient.radius, ambient.radius),
    };
    try {
      player.spawnParticle(ambient.particle, spot);
    } catch {
      // Outside the loaded world - skip this one.
    }
  }
}

system.runInterval(() => {
  const night = isNight();
  for (const player of world.getAllPlayers()) {
    try {
      pulse(player, night);
    } catch {
      // The player left mid-tick.
    }
  }
}, PULSE_TICKS);

world.afterEvents.playerSpawn.subscribe((event) => {
  if (event.initialSpawn) {
    event.player.sendMessage({ translate: "hyper.welcome" });
  }
});

world.afterEvents.playerLeave.subscribe((event) => {
  lastBiome.delete(event.playerId);
});
'''


# ---------------------------------------------------------------------------
# Texts, manifests, icons
# ---------------------------------------------------------------------------

BIOME_NAMES = {
    "titan_peaks": ("Titan Peaks", "Пики Титанов"),
    "frostfang_slopes": ("Frostfang Slopes", "Ледяные Клыки"),
    "sunset_crags": ("Sunset Crags", "Закатные Утёсы"),
    "emerald_highlands": ("Emerald Highlands", "Изумрудное Нагорье"),
    "glowwood_forest": ("Glowwood Forest", "Сияющий Лес"),
    "autumn_woods": ("Autumn Woods", "Осенняя Роща"),
    "crystal_fields": ("Crystal Fields", "Кристальные Поля"),
}

TEXTS = {
    "en_US": {
        "bp_name": "Hyper Realms - Biomes & Mountains",
        "bp_desc": "7 new living biomes and real mountains. Turn on the Custom Biomes experiment.",
        "rp_name": "Hyper Realms - Hyper Shaders",
        "rp_desc": "Vibrant Visuals tuning: sky, sun, soft shadows, waves, god rays.",
        "welcome": "§bHyper Realms§r is active. Find a biome: §e/locate biome hyper:titan_peaks",
    },
    "ru_RU": {
        "bp_name": "Hyper Realms - Биомы и горы",
        "bp_desc": "7 новых живых биомов и настоящие горы. Включи эксперимент «Пользовательские биомы».",
        "rp_name": "Hyper Realms - Гипер-шейдеры",
        "rp_desc": "Настройка «Ярких визуальных эффектов»: небо, солнце, мягкие тени, волны, лучи.",
        "welcome": "§bHyper Realms§r работает. Найти биом: §e/locate biome hyper:titan_peaks",
    },
}


def build_texts():
    for index, (lang, t) in enumerate(TEXTS.items()):
        write(BP / "texts" / f"{lang}.lang",
              f"pack.name={t['bp_name']}\npack.description={t['bp_desc']}\n")
        lines = [f"pack.name={t['rp_name']}", f"pack.description={t['rp_desc']}",
                 f"hyper.welcome={t['welcome']}"]
        lines += [f"hyper.biome.{name}=§l{names[index]}" for name, names in BIOME_NAMES.items()]
        write(RP / "texts" / f"{lang}.lang", "\n".join(lines) + "\n")
    for pack in (BP, RP):
        write(pack / "texts" / "languages.json", list(TEXTS))


def build_manifests():
    write(BP / "manifest.json", {
        "format_version": 2,
        "header": {
            "name": "pack.name", "description": "pack.description",
            "uuid": BP_UUID, "version": VERSION, "min_engine_version": MIN_ENGINE,
        },
        "modules": [
            {"type": "data", "uuid": BP_DATA_UUID, "version": VERSION},
            {"type": "script", "language": "javascript", "uuid": BP_SCRIPT_UUID,
             "entry": "scripts/main.js", "version": VERSION},
        ],
        "dependencies": [
            {"uuid": RP_UUID, "version": VERSION},
            {"module_name": "@minecraft/server", "version": "2.5.0"},
        ],
    })
    write(RP / "manifest.json", {
        "format_version": 2,
        "header": {
            "name": "pack.name", "description": "pack.description",
            "uuid": RP_UUID, "version": VERSION, "min_engine_version": MIN_ENGINE,
        },
        "modules": [{"type": "resources", "uuid": RP_MODULE_UUID, "version": VERSION}],
        "capabilities": ["pbr"],
    })


def build_icon(path, sky_top, sky_bottom, sun, layers):
    from PIL import Image, ImageDraw
    import math
    import random

    size = 256
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line([(0, y), (size, y)],
                  fill=tuple(round(a + (b - a) * t) for a, b in zip(sky_top, sky_bottom)))
    # Sun with a soft halo.
    cx, cy = 176, 92
    halo = 78
    px = img.load()
    for y in range(max(0, cy - halo), min(size, cy + halo)):
        for x in range(max(0, cx - halo), min(size, cx + halo)):
            dist = math.hypot(x - cx, y - cy)
            if dist < halo:
                t = (1 - dist / halo) ** 2
                px[x, y] = tuple(round(b + (s - b) * t) for s, b in zip(sun, px[x, y]))
    draw.ellipse([cx - 20, cy - 20, cx + 20, cy + 20], fill=sun)
    # Blocky mountain ridges, back to front.
    rnd = random.Random(7)
    step = 8
    for base, amp, color, snow in layers:
        phase = rnd.uniform(0, 6.28)
        for x in range(0, size, step):
            h = base + amp * (0.6 * math.sin(x / 31 + phase) + 0.4 * math.sin(x / 13 + phase * 2))
            top = int((size - h) // step * step)
            draw.rectangle([x, top, x + step - 1, size], fill=color)
            if snow and h > base + amp * 0.25:
                draw.rectangle([x, top, x + step - 1, top + step - 1], fill=snow)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


def build_icons():
    build_icon(BP / "pack_icon.png", (34, 84, 190), (168, 214, 250), (255, 244, 214), [
        (150, 46, (70, 84, 120), (240, 246, 255)),
        (112, 34, (48, 110, 96), None),
        (70, 22, (36, 150, 92), None),
    ])
    build_icon(RP / "pack_icon.png", (40, 28, 96), (255, 150, 90), (255, 232, 170), [
        (140, 44, (86, 52, 110), (255, 196, 170)),
        (100, 30, (58, 40, 92), None),
        (62, 18, (30, 26, 60), None),
    ])


def zip_packs(target, packs):
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for prefix, folder in packs:
            for f in sorted(folder.rglob("*")):
                if f.is_file():
                    arc = f.relative_to(folder).as_posix()
                    z.write(f, f"{prefix}/{arc}" if prefix else arc)


def main():
    for pack in (BP, RP):
        if pack.exists():
            shutil.rmtree(pack)
    build_biomes()
    build_structures()
    build_features()
    build_visuals()
    build_particles()
    write(BP / "scripts" / "main.js", SCRIPT)
    build_texts()
    build_manifests()
    build_icons()
    zip_packs(DIST / "HyperRealms.mcaddon",
              [("HyperRealms_BP", BP), ("HyperRealms_RP", RP)])
    zip_packs(DIST / "HyperShaders_only.mcpack", [("", RP)])
    count = sum(1 for f in OUT.rglob("*") if f.is_file())
    print(f"Generated {count} files, {len(features)} features, {len(rules)} feature rules")
    print("Packages:", ", ".join(p.name for p in sorted(DIST.iterdir())))


if __name__ == "__main__":
    main()
