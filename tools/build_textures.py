#!/usr/bin/env python3
"""Builds the block texture set of WILD FRONTIER.

Photo-scanned CC0 sources (see fetch_textures.py) are colour-corrected, made tileable where they are
cropped, and combined with procedurally drawn layers (foliage, plants, ores, crafted blocks).

Outputs into app/src/main/assets/textures/:
  blocks/<name>.jpg|png   albedo (sRGB; PNG when the layer needs alpha)
  blocks/<name>_n.jpg     RG = tangent-space normal xy, B = roughness
  noise.png               tiling RGB noise (clouds, fur detail)
  water_normal.png        tiling water normal map (RG) + foam noise (B)

usage: build_textures.py <source_cache_dir> <assets_dir>
"""
import math, os, random, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

SRC, OUT = sys.argv[1], sys.argv[2]
BLOCKS = os.path.join(OUT, "textures", "blocks")
os.makedirs(BLOCKS, exist_ok=True)
A = 512   # albedo size
N = 256   # normal size
S = 256   # sprite size

# ----------------------------------------------------------------------------- helpers

def load(name, kind):
    return Image.open(os.path.join(SRC, name, kind + ".jpg")).convert("RGB")

def rough_of(name):
    p = os.path.join(SRC, name, "rough.jpg")
    if not os.path.exists(p):
        return Image.new("L", (1024, 1024), 220)
    img = Image.open(p).convert("RGB")
    if os.path.exists(os.path.join(SRC, name, "rough_is_arm")):
        return img.split()[1]
    return img.convert("L")

def grade(img, bright=1.0, sat=1.0, contrast=1.0, tint=None, gray=0.0):
    if gray > 0:
        g = img.convert("L").convert("RGB")
        img = Image.blend(img, g, gray)
    if sat != 1.0: img = ImageEnhance.Color(img).enhance(sat)
    if contrast != 1.0: img = ImageEnhance.Contrast(img).enhance(contrast)
    if bright != 1.0: img = ImageEnhance.Brightness(img).enhance(bright)
    if tint is not None:
        a = np.asarray(img).astype(np.float32) * np.array(tint, np.float32)
        img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    return img

def flatten(img, strength=0.75):
    """Removes large-scale brightness variation so the texture tiles without visible blotches."""
    a = np.asarray(img).astype(np.float32)
    low = np.asarray(img.resize((16, 16), Image.BOX).resize(img.size, Image.BICUBIC)).astype(np.float32)
    mean = a.reshape(-1, 3).mean(axis=0)
    out = a - (low - mean) * strength
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))

def tileable(img):
    """Cross-fades the image with a half-offset copy so that a cropped region wraps seamlessly."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    b = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    m = np.clip((np.maximum(x, y) - 0.6) / 0.35, 0, 1)
    m = (m * m * (3 - 2 * m))[..., None]
    return Image.fromarray(np.clip(a * (1 - m) + b * m, 0, 255).astype(np.uint8))

def save_albedo(name, img, alpha=False):
    if alpha:
        img.save(os.path.join(BLOCKS, name + ".png"), optimize=True)
    else:
        img.convert("RGB").save(os.path.join(BLOCKS, name + ".jpg"), quality=88)

def save_normal(name, nor, rough):
    nor = nor.resize((N, N), Image.LANCZOS)
    rough = rough.resize((N, N), Image.LANCZOS)
    r, g, _ = nor.split()
    Image.merge("RGB", (r, g, rough)).save(os.path.join(BLOCKS, name + "_n.jpg"), quality=90)

def flat_normal(name, rough=225):
    Image.new("RGB", (N, N), (128, 128, rough)).save(os.path.join(BLOCKS, name + "_n.jpg"), quality=90)

def normal_from_height(h, strength=2.0):
    """Tangent-space normal (RG) from a height array in 0..1 (wrapping)."""
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    nx = -dx / l; ny = -dy / l
    r = (nx * 0.5 + 0.5) * 255; g = (ny * 0.5 + 0.5) * 255
    return Image.merge("RGB", (Image.fromarray(r.astype(np.uint8)), Image.fromarray(g.astype(np.uint8)), Image.new("L", h.shape[::-1], 255)))

def match_mean(img, target):
    a = np.asarray(img).astype(np.float32)
    mean = a.reshape(-1, 3).mean(axis=0)
    return Image.fromarray(np.clip(a * (np.array(target, np.float32) / mean), 0, 255).astype(np.uint8))

def photo(name, src, crop=None, tile=False, rough_scale=1.0, flat=0.6, mean=None, **g):
    """Full pipeline for a photo-based layer. crop = (x, y, size) region of the 1k source."""
    d = load(src, "diff"); n = load(src, "nor"); r = rough_of(src)
    if crop:
        box = (crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[2])
        d, n, r = d.crop(box), n.crop(box), r.crop(box)
        if tile:
            d, n, r = tileable(d), tileable(n), tileable(r.convert("RGB")).convert("L")
    d = d.resize((A, A), Image.LANCZOS)
    if flat > 0: d = flatten(d, flat)
    d = grade(d, **g)
    if mean is not None: d = match_mean(d, mean)
    if rough_scale != 1.0:
        r = Image.fromarray(np.clip(np.asarray(r).astype(np.float32) * rough_scale, 0, 255).astype(np.uint8))
    save_albedo(name, d)
    save_normal(name, n, r)
    return d

def tile_noise(size, period, rng):
    """Smooth value noise that wraps every `size` pixels; `period` lattice cells across."""
    g = rng.random((period, period)).astype(np.float32)
    t = np.arange(size) * period / size
    i0 = np.floor(t).astype(int); f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % period
    a = g[i0][:, i0]; b = g[i0][:, i1]; c = g[i1][:, i0]; d = g[i1][:, i1]
    fx = f[None, :]; fy = f[:, None]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy

def fbm(size, base_period, octaves, rng, gain=0.5):
    out = np.zeros((size, size), np.float32); amp = 1.0; norm = 0.0; p = base_period
    for _ in range(octaves):
        out += tile_noise(size, p, rng) * amp; norm += amp; amp *= gain; p *= 2
    return out / norm

# ----------------------------------------------------------------------------- photo layers

rng = np.random.default_rng(7)
random.seed(7)

grass = photo("grass_top", "leafy_grass", sat=1.2, mean=(84, 122, 50))
photo("grass_lush", "leafy_grass", sat=1.35, mean=(52, 116, 44))
photo("grass_dry", "withered_grass", sat=1.05, mean=(146, 138, 76))
dirt = photo("dirt", "brown_mud_dry", bright=0.95, sat=0.95, tint=(1.0, 0.93, 0.84))
stone = photo("stone", "rock_05", gray=0.6, contrast=1.05, mean=(122, 124, 126))
photo("sand", "sand_02", sat=0.8, mean=(178, 160, 120), rough_scale=1.7)
photo("gravel", "gravel_ground_01", gray=0.35, mean=(134, 130, 122))
photo("clay", "clay_floor_001", sat=0.8, mean=(168, 132, 112))
snow = photo("snow", "snow_02", bright=1.04, tint=(0.97, 0.99, 1.0), flat=0.8, rough_scale=0.8)
photo("mossy_stone", "mossy_rock", bright=0.95, sat=1.1)
photo("sandstone", "sandstone_cracks", bright=1.0, sat=0.9)
photo("mud", "brown_mud_02", bright=0.85, sat=0.9, rough_scale=0.55)
photo("forest_floor", "forest_ground_04", bright=0.9, sat=1.05)
photo("bedrock", "dark_rock", bright=0.7)
photo("planks_oak", "wood_planks", bright=1.0, sat=0.95, flat=0.3)
photo("planks_pine", "hinoki_planks", bright=0.95, sat=0.9, flat=0.3)
photo("cobblestone", "cobblestone_05", gray=0.35, bright=0.95, flat=0.4)
photo("stone_bricks", "mossy_cobblestone", gray=0.25, bright=0.95, flat=0.4)
photo("bricks", "brick_4", bright=0.92, flat=0.4)
photo("thatch", "thatch_roof_angled", bright=1.1, sat=1.1, tint=(1.05, 0.98, 0.8))
photo("metal_panel", "metal_plate_02", bright=1.25, gray=0.5, tint=(0.92, 0.97, 1.02), flat=0.3, rough_scale=0.6)
photo("lab_floor", "metal_plate", bright=1.3, gray=0.6, flat=0.3, rough_scale=0.55)
photo("rusty_metal", "rusty_metal_02", bright=0.95, flat=0.3, rough_scale=0.8)

# bark: one block per tile -> crop half of the source and make it wrap
oak_bark = photo("oak_bark", "jolcham_oak_bark_01", crop=(256, 256, 512), tile=True, bright=1.05, flat=0.5)
pine_bark = photo("pine_bark", "pine_bark", crop=(256, 256, 512), tile=True, bright=0.9, sat=0.9, flat=0.5)
palm_bark = photo("palm_bark", "palm_tree_bark", crop=(200, 200, 640), tile=True, bright=1.0, flat=0.5)

# ice: snow relief, tinted and glossy
ice = grade(load("snow_02", "diff").resize((A, A), Image.LANCZOS), bright=0.9, tint=(0.62, 0.84, 1.0))
ia = np.asarray(ice).astype(np.float32)
cr = fbm(A, 4, 5, rng)
cracks = np.clip(1.0 - np.abs(cr - 0.5) * 22.0, 0, 1)[..., None]
ia = ia * (1 - cracks * 0.25) + cracks * 30
save_albedo("ice", Image.fromarray(np.clip(ia, 0, 255).astype(np.uint8)))
save_normal("ice", load("snow_02", "nor"), Image.new("L", (N, N), 40))

# birch bark: procedural (white with dark lenticels), one block per tile
bn = fbm(A, 8, 4, rng)
base = 205 + bn * 40
ba = np.stack([base, base * 0.985, base * 0.95], -1)
bimg = Image.fromarray(np.clip(ba, 0, 255).astype(np.uint8))
bd = ImageDraw.Draw(bimg)
for _ in range(70):
    x = random.randrange(A); y = random.randrange(A); w = random.randrange(14, 70); t = random.randrange(2, 7)
    col = random.randrange(25, 70)
    for xo in (-A, 0, A):
        bd.ellipse((x + xo, y, x + xo + w, y + t), fill=(col, col - 5, col - 8))
for _ in range(7):
    x = random.randrange(A); y = random.randrange(A)
    for xo in (-A, 0, A):
        for yo in (-A, 0, A):
            bd.polygon([(x + xo, y + yo), (x + xo + 46, y + yo + 10), (x + xo + 30, y + yo + 44), (x + xo - 12, y + yo + 30)], fill=(48, 42, 38))
bimg = bimg.filter(ImageFilter.GaussianBlur(1.2))
save_albedo("birch_bark", bimg)
bh = np.asarray(bimg.convert("L")).astype(np.float32) / 255.0
save_normal("birch_bark", normal_from_height(bh, 3.0), Image.new("L", (A, A), 170))

def log_top(name, bark_img, wood, ring):
    """End grain: growth rings inside a ring of bark."""
    bark_col = np.asarray(bark_img).reshape(-1, 3).mean(axis=0)
    yy, xx = np.mgrid[0:A, 0:A].astype(np.float32)
    cx = cy = A / 2
    wob = fbm(A, 4, 3, rng) * 26
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) + wob
    rings = 0.5 + 0.5 * np.sin(r * 0.42)
    w = np.array(wood, np.float32); d = np.array(ring, np.float32)
    col = w[None, None, :] * (1 - rings[..., None] * 0.55) + d[None, None, :] * rings[..., None] * 0.55
    col *= (0.92 + fbm(A, 16, 3, rng)[..., None] * 0.16)
    edge = np.clip((np.maximum(np.abs(xx - cx), np.abs(yy - cy)) - (A / 2 - 34)) / 12, 0, 1)[..., None]
    col = col * (1 - edge) + bark_col[None, None, :] * 0.8 * edge
    img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8))
    save_albedo(name, img)
    save_normal(name, normal_from_height(rings * 0.5 + edge[..., 0], 1.5), Image.new("L", (A, A), 200))

log_top("oak_top", oak_bark, (176, 138, 88), (120, 86, 50))
log_top("pine_top", pine_bark, (200, 160, 104), (150, 104, 60))
log_top("birch_top", bimg, (222, 200, 160), (176, 150, 110))
log_top("palm_top", palm_bark, (190, 160, 110), (150, 120, 80))

# ----------------------------------------------------------------------------- composite cube layers

def one_block(src_img, x=128, y=128, size=256):
    """Region of a 4-blocks-per-tile albedo that corresponds to one block, wrapped to tile."""
    return tileable(src_img.resize((1024, 1024), Image.LANCZOS).crop((x, y, x + size, y + size))).resize((A, A), Image.LANCZOS)

def side_overlay(name, top_img, strip, ragged=26):
    """Dirt side with the top material creeping over the upper edge."""
    base = one_block(dirt).convert("RGB")
    top = one_block(top_img).convert("RGB")
    edge = strip + (tile_noise(A, 16, rng)[0] * ragged * 2 - ragged) + (tile_noise(A, 64, rng)[0] * 14 - 7)
    yy = np.arange(A)[:, None].astype(np.float32)
    m = np.clip((edge[None, :] - yy) / 5.0, 0, 1)[..., None]
    a = np.asarray(base).astype(np.float32); t = np.asarray(top).astype(np.float32)
    shade = 1.0 - 0.35 * np.clip(1 - np.abs(edge[None, :] - yy) / 10.0, 0, 1)[..., None] * (1 - m)
    img = Image.fromarray(np.clip((a * (1 - m) * shade + t * m), 0, 255).astype(np.uint8))
    save_albedo(name, img)
    flat_normal(name, 235)

side_overlay("grass_side", grass, 96)
side_overlay("lush_side", Image.open(os.path.join(BLOCKS, "grass_lush.jpg")), 110)
side_overlay("dry_side", Image.open(os.path.join(BLOCKS, "grass_dry.jpg")), 80)
side_overlay("snow_side", snow, 150, ragged=18)

def ore(name, color, shine, count, rough):
    a = np.asarray(stone).astype(np.float32)
    mask = Image.new("L", (A, A), 0); md = ImageDraw.Draw(mask)
    for _ in range(count):
        x = random.randrange(A); y = random.randrange(A)
        for _ in range(random.randrange(3, 7)):
            ox = x + random.randrange(-22, 22); oy = y + random.randrange(-22, 22); r = random.randrange(5, 15)
            for wx in (-A, 0, A):
                for wy in (-A, 0, A):
                    pts = [(ox + wx + math.cos(k * 1.05 + ox) * r * random.uniform(0.6, 1.1), oy + wy + math.sin(k * 1.05 + ox) * r * random.uniform(0.6, 1.1)) for k in range(6)]
                    md.polygon(pts, fill=255)
    m = np.asarray(mask.filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32)[..., None] / 255.0
    facet = (0.75 + fbm(A, 32, 2, rng) * 0.6)[..., None]
    c = np.array(color, np.float32)[None, None, :] * facet + np.array(shine, np.float32)[None, None, :] * np.clip(facet - 1.05, 0, 1) * 3
    out = a * (1 - m) + c * m
    out *= 1 - 0.35 * np.clip(np.asarray(mask.filter(ImageFilter.GaussianBlur(4))).astype(np.float32)[..., None] / 255.0 - m, 0, 1)
    save_albedo(name, Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)))
    rr = np.asarray(rough_of("rock_05").resize((A, A))).astype(np.float32)
    rr = rr * (1 - m[..., 0]) + rough * m[..., 0]
    save_normal(name, load("rock_05", "nor"), Image.fromarray(rr.astype(np.uint8)))

ore("coal_ore", (28, 28, 32), (70, 70, 80), 26, 90)
ore("copper_ore", (196, 110, 62), (255, 190, 130), 22, 70)
ore("iron_ore", (172, 140, 122), (235, 215, 200), 22, 80)
ore("gold_ore", (232, 186, 52), (255, 245, 170), 16, 40)
ore("crystal_ore", (70, 225, 235), (220, 255, 255), 18, 20)

planks = Image.open(os.path.join(BLOCKS, "planks_oak.jpg")).convert("RGB")
planks_pine = Image.open(os.path.join(BLOCKS, "planks_pine.jpg")).convert("RGB")
cobble = Image.open(os.path.join(BLOCKS, "cobblestone.jpg")).convert("RGB")
metal = Image.open(os.path.join(BLOCKS, "metal_panel.jpg")).convert("RGB")

def framed(base, frame_col, width=30, inner_shadow=True):
    img = base.copy(); d = ImageDraw.Draw(img)
    for i in range(width):
        k = 0.75 + 0.25 * (i / width)
        c = tuple(int(v * k) for v in frame_col)
        d.rectangle((i, i, A - 1 - i, A - 1 - i), outline=c)
    if inner_shadow:
        d.rectangle((width, width, A - 1 - width, A - 1 - width), outline=(20, 16, 12), width=4)
    return img

# workbench
wb = framed(planks, (96, 66, 38), 26)
d = ImageDraw.Draw(wb)
d.line((120, 150, 380, 360), fill=(60, 60, 66), width=16)      # saw blade
d.rectangle((90, 120, 150, 180), fill=(120, 80, 40))
d.rectangle((300, 110, 420, 150), fill=(70, 70, 76)); d.rectangle((350, 150, 372, 300), fill=(130, 90, 50))  # hammer
save_albedo("workbench_top", wb); flat_normal("workbench_top", 200)
ws = framed(planks, (96, 66, 38), 26); d = ImageDraw.Draw(ws)
d.rectangle((60, 250, A - 60, 270), fill=(70, 46, 26)); d.rectangle((90, 270, 130, A - 30), fill=(80, 54, 30)); d.rectangle((A - 130, 270, A - 90, A - 30), fill=(80, 54, 30))
save_albedo("workbench_side", ws); flat_normal("workbench_side", 200)

# furnace
ft = framed(cobble, (70, 70, 74), 22); save_albedo("furnace_top", ft); flat_normal("furnace_top", 215)
fs = framed(cobble, (70, 70, 74), 22); d = ImageDraw.Draw(fs)
d.rounded_rectangle((120, 250, A - 120, A - 70), 34, fill=(18, 14, 12))
for i in range(22):
    x = 140 + i * 11; h = 40 + int(30 * math.sin(i * 1.3)) + random.randrange(0, 25)
    d.polygon([(x - 9, A - 74), (x, A - 74 - h), (x + 9, A - 74)], fill=(255, 140 + random.randrange(0, 80), 30))
d.rounded_rectangle((150, 90, A - 150, 170), 12, fill=(30, 26, 24))
save_albedo("furnace_side", fs); flat_normal("furnace_side", 215)

# chest & crate
ch = framed(planks, (58, 40, 26), 20); d = ImageDraw.Draw(ch)
d.rectangle((0, 150, A, 178), fill=(54, 56, 62)); d.rectangle((226, 140, 286, 220), fill=(196, 170, 70)); d.rectangle((246, 170, 266, 200), fill=(40, 34, 20))
save_albedo("chest_side", ch); flat_normal("chest_side", 190)
ct = framed(planks, (58, 40, 26), 20); d = ImageDraw.Draw(ct)
d.rectangle((0, 110, A, 134), fill=(54, 56, 62)); d.rectangle((0, A - 134, A, A - 110), fill=(54, 56, 62))
save_albedo("chest_top", ct); flat_normal("chest_top", 190)
cr8 = framed(grade(planks_pine, bright=0.78), (86, 70, 50), 34); d = ImageDraw.Draw(cr8)
d.line((34, 34, A - 34, A - 34), fill=(86, 70, 50), width=34); d.line((A - 34, 34, 34, A - 34), fill=(86, 70, 50), width=34)
d.rectangle((176, 216, 336, 296), fill=(214, 206, 180)); d.text((196, 236), "EXP-7", fill=(40, 40, 40))
save_albedo("crate", cr8); flat_normal("crate", 205)

# farmland
soil = load("farm_soil", "diff")
fl = tileable(soil.crop((256, 256, 768, 768))).resize((A, A), Image.LANCZOS)
fa = np.asarray(fl).astype(np.float32)
fur = (0.72 + 0.28 * np.abs(np.sin(np.arange(A) * math.pi * 4 / A)))[None, :, None]
save_albedo("farmland", Image.fromarray(np.clip(fa * fur * 1.05, 0, 255).astype(np.uint8)))
save_albedo("farmland_wet", Image.fromarray(np.clip(fa * fur * 0.62, 0, 255).astype(np.uint8)))
save_normal("farmland", load("farm_soil", "nor").crop((256, 256, 768, 768)), Image.new("L", (N, N), 230))
save_normal("farmland_wet", load("farm_soil", "nor").crop((256, 256, 768, 768)), Image.new("L", (N, N), 90))

# lamp, terminal
lamp = framed(metal, (150, 156, 164), 40); d = ImageDraw.Draw(lamp)
d.rounded_rectangle((70, 70, A - 70, A - 70), 30, fill=(255, 244, 205))
d.rounded_rectangle((120, 120, A - 120, A - 120), 30, fill=(255, 255, 240))
save_albedo("lamp", lamp); flat_normal("lamp", 120)
term = framed(metal, (120, 126, 134), 30); d = ImageDraw.Draw(term)
d.rounded_rectangle((70, 80, A - 70, 330), 14, fill=(8, 30, 28))
for i in range(9):
    w = random.randrange(120, 330)
    d.rectangle((96, 104 + i * 24, 96 + w, 114 + i * 24), fill=(70, 235, 170))
d.rectangle((90, 370, A - 90, 440), fill=(40, 44, 50))
for i in range(10):
    d.rectangle((104 + i * 31, 384, 126 + i * 31, 400), fill=(150, 156, 164)); d.rectangle((104 + i * 31, 412, 126 + i * 31, 428), fill=(150, 156, 164))
save_albedo("terminal", term); flat_normal("terminal", 110)

# campfire (charred logs + embers), torch tip, bedroll
cf = one_block(Image.open(os.path.join(BLOCKS, "bedrock.jpg")), 0, 0, 256); d = ImageDraw.Draw(cf)
for i in range(7):
    y = 40 + i * 66
    d.rounded_rectangle((20, y, A - 20, y + 44), 20, fill=(52 + i * 3, 36, 26))
for _ in range(160):
    x = random.randrange(A); y = random.randrange(A); r = random.randrange(3, 10)
    d.ellipse((x, y, x + r, y + r), fill=(255, random.randrange(90, 200), 20))
save_albedo("campfire", cf); flat_normal("campfire", 235)
tg = np.zeros((A, A, 3), np.float32)
g = fbm(A, 8, 3, rng)
tg[..., 0] = 255; tg[..., 1] = 150 + g * 100; tg[..., 2] = 40 + g * 60
save_albedo("torch", Image.fromarray(np.clip(tg, 0, 255).astype(np.uint8))); flat_normal("torch", 230)
br = Image.new("RGB", (A, A), (92, 108, 74)); d = ImageDraw.Draw(br)
for i in range(0, A, 32):
    d.line((0, i, A, i), fill=(74, 88, 60), width=5)
for i in range(0, A, 64):
    d.line((i, 0, i, A), fill=(110, 126, 90), width=3)
ba2 = np.asarray(br).astype(np.float32) * (0.85 + fbm(A, 32, 3, rng)[..., None] * 0.3)
save_albedo("bedroll", Image.fromarray(np.clip(ba2, 0, 255).astype(np.uint8))); flat_normal("bedroll", 240)

# glass: opaque frame, clear pane with a few reflection streaks (alpha tested)
gl = Image.new("RGBA", (A, A), (200, 225, 235, 0)); d = ImageDraw.Draw(gl)
d.rectangle((0, 0, A - 1, A - 1), outline=(176, 186, 190, 255), width=22)
d.line((90, 200, 200, 90), fill=(235, 245, 250, 255), width=7)
d.line((130, 250, 270, 110), fill=(235, 245, 250, 255), width=4)
d.line((330, 420, 420, 330), fill=(235, 245, 250, 255), width=5)
save_albedo("glass", gl, alpha=True); flat_normal("glass", 30)

# ----------------------------------------------------------------------------- foliage (alpha)

SS = 2  # supersampling factor for drawn sprites

def new_canvas(base, size=S):
    return Image.new("RGBA", (size * SS, size * SS), (base[0], base[1], base[2], 0))

def finish(img, name, size=S):
    img = img.resize((size, size), Image.LANCZOS)
    # harden alpha a little so mipmaps keep coverage
    r, g, b, a = img.split()
    a = a.point(lambda v: min(255, int(v * 1.35)))
    img = Image.merge("RGBA", (r, g, b, a))
    save_albedo(name, img, alpha=True)
    flat_normal(name, 215)
    return img

def jitter(col, amt):
    return tuple(max(0, min(255, int(c + random.uniform(-amt, amt)))) for c in col)

def leaf_poly(cx, cy, length, width, ang):
    pts = []
    for k in range(13):
        t = k / 12.0
        w = math.sin(t * math.pi) ** 0.8 * width * 0.5
        pts.append((t * length, w))
    for k in range(12, -1, -1):
        t = k / 12.0
        w = math.sin(t * math.pi) ** 0.8 * width * 0.5
        pts.append((t * length, -w))
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in pts]

def leaves_tex(name, base, light, count, length, width, hole_keep=True, extra=None):
    """Tileable canopy texture made from hundreds of overlapping leaves with see-through gaps."""
    W = A * SS // 2 * 1  # author at 512 for crispness on HIGH
    W = 512
    img = Image.new("RGBA", (W * SS, W * SS), (base[0], base[1], base[2], 0))
    d = ImageDraw.Draw(img)
    T = W * SS
    # darker inner layer first, brighter leaves on top
    for layer in range(3):
        k = layer / 2.0
        col_a = tuple(int(base[i] * (0.55 + 0.45 * k) + light[i] * 0.0) for i in range(3))
        col_b = tuple(int(base[i] * (1 - k) + light[i] * k) for i in range(3))
        n = int(count * (1.0 if layer == 0 else 0.75))
        for _ in range(n):
            x = random.uniform(0, T); y = random.uniform(0, T)
            ang = random.uniform(0, math.tau)
            L = length * SS * random.uniform(0.7, 1.25); Wd = width * SS * random.uniform(0.7, 1.2)
            c = jitter(col_a if layer == 0 else col_b, 14)
            for ox in (-T, 0, T):
                for oy in (-T, 0, T):
                    if -L < x + ox < T + L and -L < y + oy < T + L:
                        poly = leaf_poly(x + ox, y + oy, L, Wd, ang)
                        d.polygon(poly, fill=c + (255,))
                        # midrib
                        d.line((x + ox, y + oy, x + ox + math.cos(ang) * L, y + oy + math.sin(ang) * L), fill=tuple(int(v * 0.8) for v in c) + (255,), width=max(1, SS))
            if extra and layer == 2 and random.random() < 0.035:
                extra(d, x, y, T)
    img = img.resize((A, A), Image.LANCZOS)
    r, g, b, a = img.split()
    a = a.point(lambda v: 255 if v > 110 else 0)
    img = Image.merge("RGBA", (r, g, b, a))
    save_albedo(name, img, alpha=True)
    flat_normal(name, 205)

def apples(d, x, y, T):
    r = 15 * SS
    for ox in (-T, 0, T):
        for oy in (-T, 0, T):
            d.ellipse((x + ox - r, y + oy - r, x + ox + r, y + oy + r), fill=(196, 34, 30, 255))
            d.ellipse((x + ox - r * 0.5, y + oy - r * 0.6, x + ox, y + oy - r * 0.1), fill=(240, 120, 100, 255))

leaves_tex("oak_leaves", (34, 74, 24), (78, 128, 44), 620, 44, 24)
leaves_tex("birch_leaves", (58, 100, 28), (124, 160, 54), 900, 28, 20)
leaves_tex("jungle_leaves", (18, 64, 22), (52, 122, 44), 340, 74, 34)
leaves_tex("fruit_leaves", (36, 80, 26), (84, 136, 48), 620, 44, 24, extra=apples)

def needles_tex(name, base, light, twigs):
    W = 512; T = W * SS
    img = Image.new("RGBA", (T, T), (base[0], base[1], base[2], 0)); d = ImageDraw.Draw(img)
    for layer in range(2):
        for _ in range(twigs):
            x = random.uniform(0, T); y = random.uniform(0, T); ang = random.uniform(0, math.tau)
            L = random.uniform(70, 130) * SS
            col = jitter(base if layer == 0 else light, 12)
            twig = (58, 40, 26, 255)
            for ox in (-T, 0, T):
                for oy in (-T, 0, T):
                    if not (-L < x + ox < T + L and -L < y + oy < T + L): continue
                    ex = x + ox + math.cos(ang) * L; ey = y + oy + math.sin(ang) * L
                    d.line((x + ox, y + oy, ex, ey), fill=twig, width=2 * SS)
                    steps = int(L / (5 * SS))
                    for k in range(steps):
                        t = k / steps
                        px = x + ox + math.cos(ang) * L * t; py = y + oy + math.sin(ang) * L * t
                        nl = (22 - 10 * t) * SS
                        for side in (-1, 1):
                            a2 = ang + side * 1.0
                            d.line((px, py, px + math.cos(a2) * nl, py + math.sin(a2) * nl), fill=col + (255,), width=2 * SS)
    img = img.resize((A, A), Image.LANCZOS)
    r, g, b, a = img.split(); a = a.point(lambda v: 255 if v > 90 else 0)
    save_albedo(name, Image.merge("RGBA", (r, g, b, a)), alpha=True); flat_normal(name, 205)

needles_tex("pine_leaves", (20, 56, 32), (46, 94, 52), 260)

def palm_tex(name):
    W = 512; T = W * SS
    base = (46, 110, 34)
    img = Image.new("RGBA", (T, T), base + (0,)); d = ImageDraw.Draw(img)
    for _ in range(26):
        x = random.uniform(0, T); y = random.uniform(0, T); ang = random.uniform(0, math.tau); L = random.uniform(260, 420) * SS
        for ox in (-T, 0, T):
            for oy in (-T, 0, T):
                if not (-L < x + ox < T + L and -L < y + oy < T + L): continue
                sx, sy = x + ox, y + oy
                d.line((sx, sy, sx + math.cos(ang) * L, sy + math.sin(ang) * L), fill=(120, 140, 60, 255), width=4 * SS)
                steps = int(L / (11 * SS))
                for k in range(steps):
                    t = k / steps
                    px = sx + math.cos(ang) * L * t; py = sy + math.sin(ang) * L * t
                    ll = (70 * math.sin(t * math.pi) + 18) * SS
                    for side in (-1, 1):
                        a2 = ang + side * 1.15
                        col = jitter((60, 138, 44), 16)
                        d.polygon(leaf_poly(px, py, ll, 9 * SS, a2), fill=col + (255,))
    img = img.resize((A, A), Image.LANCZOS)
    r, g, b, a = img.split(); a = a.point(lambda v: 255 if v > 100 else 0)
    save_albedo(name, Image.merge("RGBA", (r, g, b, a)), alpha=True); flat_normal(name, 190)

palm_tex("palm_leaves")

# ----------------------------------------------------------------------------- plant sprites

def blade(d, x0, y0, height, lean, width, col_base, col_tip, segs=10):
    left = []; right = []
    for k in range(segs + 1):
        t = k / segs
        x = x0 + lean * t * t; y = y0 - height * t
        w = width * (1 - t) ** 0.8 * 0.5
        left.append((x - w, y)); right.append((x + w, y))
    poly = left + right[::-1]
    c = tuple(int(col_base[i] * 0.5 + col_tip[i] * 0.5) for i in range(3))
    d.polygon(poly, fill=c + (255,))
    # brighter upper half
    half = segs // 2
    d.polygon(left[half:] + right[half:][::-1], fill=tuple(col_tip) + (255,))
    d.polygon(left[:3] + right[:3][::-1], fill=tuple(col_base) + (255,))

def grass_sprite(name, n, hmin, hmax, base, tip, spread=0.42):
    img = new_canvas(tip); d = ImageDraw.Draw(img); W = S * SS
    for _ in range(n):
        x = W * (0.5 + random.uniform(-spread, spread))
        h = random.uniform(hmin, hmax) * W
        blade(d, x, W, h, random.uniform(-0.28, 0.28) * W, random.uniform(0.022, 0.04) * W, jitter(base, 12), jitter(tip, 18))
    return finish(img, name)

grass_sprite("tall_grass", 46, 0.45, 0.98, (40, 86, 24), (120, 168, 60))

def fern_sprite(name):
    img = new_canvas((60, 120, 40)); d = ImageDraw.Draw(img); W = S * SS
    for i in range(9):
        ang = -math.pi / 2 + (i - 4) * 0.27 + random.uniform(-0.06, 0.06)
        L = W * random.uniform(0.62, 0.95)
        sx, sy = W * 0.5, W * 0.99
        steps = 26
        px, py = sx, sy
        for k in range(steps):
            t = k / steps
            a = ang + (i - 4) * 0.10 * t * 2.2   # fronds arch outward
            nx = px + math.cos(a) * L / steps; ny = py + math.sin(a) * L / steps
            d.line((px, py, nx, ny), fill=(70, 96, 40, 255), width=3 * SS)
            ll = W * 0.115 * math.sin(min(1.0, t * 1.25) * math.pi) + 2
            for side in (-1, 1):
                a2 = a + side * 1.25
                d.polygon(leaf_poly(nx, ny, ll, W * 0.02, a2), fill=jitter((52, 122, 40), 16) + (255,))
            px, py = nx, ny
    return finish(img, name)

fern_sprite("fern")

def flower_sprite(name, petal, center, n_flowers=5):
    img = new_canvas((70, 130, 50)); d = ImageDraw.Draw(img); W = S * SS
    for _ in range(18):
        x = W * (0.5 + random.uniform(-0.36, 0.36))
        blade(d, x, W, random.uniform(0.2, 0.5) * W, random.uniform(-0.15, 0.15) * W, 0.03 * W, (40, 90, 26), jitter((100, 160, 56), 16))
    for i in range(n_flowers):
        x = W * (0.2 + 0.6 * (i + 0.5) / n_flowers + random.uniform(-0.05, 0.05))
        h = W * random.uniform(0.55, 0.9)
        d.line((x, W, x + random.uniform(-10, 10), W - h), fill=(60, 110, 40, 255), width=3 * SS)
        cx, cy = x, W - h
        r = W * random.uniform(0.055, 0.075)
        for k in range(7):
            a = k * math.tau / 7 + random.uniform(-0.1, 0.1)
            d.ellipse((cx + math.cos(a) * r - r * 0.62, cy + math.sin(a) * r - r * 0.62, cx + math.cos(a) * r + r * 0.62, cy + math.sin(a) * r + r * 0.62), fill=jitter(petal, 14) + (255,))
        d.ellipse((cx - r * 0.45, cy - r * 0.45, cx + r * 0.45, cy + r * 0.45), fill=center + (255,))
    return finish(img, name)

flower_sprite("flower_red", (214, 40, 34), (40, 30, 20))
flower_sprite("flower_yellow", (244, 206, 40), (190, 120, 20))
flower_sprite("flower_blue", (70, 110, 226), (240, 220, 120))

def mushroom_sprite(name):
    img = new_canvas((150, 110, 80)); d = ImageDraw.Draw(img); W = S * SS
    for x, h, r in ((0.32, 0.42, 0.15), (0.6, 0.6, 0.2), (0.8, 0.3, 0.1)):
        cx = W * x; top = W * (1 - h)
        d.rounded_rectangle((cx - W * 0.035, top, cx + W * 0.035, W), 8, fill=(226, 214, 190, 255))
        d.pieslice((cx - W * r, top - W * r * 0.75, cx + W * r, top + W * r * 0.75), 180, 360, fill=(146, 84, 44, 255))
        d.ellipse((cx - W * r, top - W * 0.02, cx + W * r, top + W * 0.03), fill=(196, 168, 130, 255))
        for _ in range(5):
            sx = cx + random.uniform(-0.7, 0.7) * W * r; sy = top - random.uniform(0.15, 0.6) * W * r * 0.75
            d.ellipse((sx - 5, sy - 4, sx + 5, sy + 4), fill=(190, 130, 80, 255))
    return finish(img, name)

mushroom_sprite("mushroom")

def reeds_sprite(name):
    img = new_canvas((90, 130, 60)); d = ImageDraw.Draw(img); W = S * SS
    for i in range(13):
        x = W * (0.12 + 0.76 * i / 12 + random.uniform(-0.03, 0.03))
        h = W * random.uniform(0.7, 0.99)
        lean = random.uniform(-0.06, 0.06) * W
        blade(d, x, W, h, lean, 0.03 * W, (60, 104, 40), jitter((132, 164, 74), 14))
        if i % 3 == 0:
            cx = x + lean * 0.8; cy = W - h * 0.9
            d.rounded_rectangle((cx - W * 0.022, cy, cx + W * 0.022, cy + W * 0.15), 9, fill=(96, 60, 34, 255))
    return finish(img, name)

reeds_sprite("reeds")

def bush_sprite(name, berries):
    img = new_canvas((40, 96, 34)); d = ImageDraw.Draw(img); W = S * SS
    for _ in range(9):
        a = random.uniform(-1.0, 1.0)
        d.line((W * 0.5, W, W * 0.5 + math.sin(a) * W * 0.4, W * 0.42), fill=(76, 52, 32, 255), width=5 * SS)
    for layer in range(3):
        for _ in range(170):
            a = random.uniform(0, math.pi); r = random.uniform(0, 1) ** 0.6
            x = W * 0.5 + math.cos(a) * r * W * 0.47; y = W * 0.98 - math.sin(a) * r * W * 0.86 - W * 0.04
            col = jitter((30 + layer * 22, 78 + layer * 30, 24 + layer * 10), 12)
            d.polygon(leaf_poly(x, y, W * 0.085, W * 0.05, random.uniform(0, math.tau)), fill=col + (255,))
    if berries:
        for _ in range(26):
            a = random.uniform(0.15, math.pi - 0.15); r = random.uniform(0.2, 0.92)
            x = W * 0.5 + math.cos(a) * r * W * 0.42; y = W * 0.96 - math.sin(a) * r * W * 0.8
            rr = W * 0.026
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=(190, 24, 60, 255))
            d.ellipse((x - rr * 0.5, y - rr * 0.6, x, y - rr * 0.1), fill=(250, 150, 170, 255))
    return finish(img, name)

bush_sprite("berry_bush", True)
bush_sprite("berry_bush_empty", False)

def twig(d, x, y, ang, length, width, depth, col):
    if depth == 0 or length < 6: return
    ex = x + math.cos(ang) * length; ey = y + math.sin(ang) * length
    d.line((x, y, ex, ey), fill=col + (255,), width=max(1, int(width)))
    for _ in range(2 + (depth > 2)):
        twig(d, x + (ex - x) * random.uniform(0.4, 1.0), y + (ey - y) * random.uniform(0.4, 1.0),
             ang + random.uniform(-0.8, 0.8), length * random.uniform(0.5, 0.75), width * 0.65, depth - 1, col)

def dead_bush_sprite(name):
    img = new_canvas((120, 92, 60)); d = ImageDraw.Draw(img); W = S * SS
    for i in range(6):
        twig(d, W * 0.5 + random.uniform(-14, 14), W, -math.pi / 2 + (i - 2.5) * 0.36, W * 0.36, 7 * SS, 4, jitter((112, 84, 54), 12))
    return finish(img, name)

dead_bush_sprite("dead_bush")

def sapling_sprite(name):
    img = new_canvas((60, 120, 40)); d = ImageDraw.Draw(img); W = S * SS
    d.line((W * 0.5, W, W * 0.5 + 6, W * 0.28), fill=(96, 68, 40, 255), width=7 * SS)
    for i in range(16):
        t = 0.25 + 0.72 * random.random()
        x = W * 0.5 + 6 * t; y = W - (W * 0.72) * t
        side = 1 if i % 2 else -1
        d.polygon(leaf_poly(x, y, W * random.uniform(0.14, 0.24), W * 0.085, -math.pi / 2 + side * random.uniform(0.6, 1.5)), fill=jitter((70, 150, 50), 18) + (255,))
    return finish(img, name)

sapling_sprite("sapling")

def wheat_sprite(stage):
    img = new_canvas((150, 150, 60)); d = ImageDraw.Draw(img); W = S * SS
    h = (0.3, 0.52, 0.76, 0.96)[stage]
    green = (70, 140, 44) if stage < 3 else (176, 150, 60)
    tip = (130, 180, 66) if stage < 3 else (226, 190, 86)
    for i in range(26):
        x = W * (0.06 + 0.88 * i / 25 + random.uniform(-0.015, 0.015))
        hh = W * h * random.uniform(0.8, 1.0); lean = random.uniform(-0.05, 0.05) * W
        blade(d, x, W, hh, lean, 0.026 * W, green, jitter(tip, 12))
        if stage >= 2:
            cx = x + lean; cy = W - hh
            col = (150, 170, 70) if stage == 2 else (230, 186, 70)
            for k in range(6):
                yy = cy + k * W * 0.022
                d.ellipse((cx - W * 0.018, yy - W * 0.016, cx + W * 0.018, yy + W * 0.016), fill=jitter(col, 12) + (255,))
    return finish(img, "wheat_%d" % stage)

for st in range(4): wheat_sprite(st)

def carrot_sprite(stage):
    img = new_canvas((70, 150, 50)); d = ImageDraw.Draw(img); W = S * SS
    h = (0.26, 0.4, 0.56, 0.7)[stage]
    for cxn in (0.2, 0.5, 0.8):
        cx = W * cxn
        for i in range(7 + stage * 2):
            ang = -math.pi / 2 + random.uniform(-0.75, 0.75)
            L = W * h * random.uniform(0.7, 1.0)
            ex = cx + math.cos(ang) * L; ey = W + math.sin(ang) * L
            d.line((cx, W, ex, ey), fill=(64, 130, 44, 255), width=2 * SS)
            for k in range(6):
                t = 0.35 + 0.65 * k / 6
                px = cx + (ex - cx) * t; py = W + (ey - W) * t
                for side in (-1, 1):
                    d.polygon(leaf_poly(px, py, W * 0.05, W * 0.022, ang + side * 0.9), fill=jitter((74, 160, 50), 16) + (255,))
        if stage == 3:
            d.pieslice((cx - W * 0.05, W - W * 0.05, cx + W * 0.05, W + W * 0.05), 180, 360, fill=(236, 120, 30, 255))
    return finish(img, "carrot_%d" % stage)

for st in range(4): carrot_sprite(st)

def flames_sprite(name):
    img = new_canvas((255, 160, 40)); d = ImageDraw.Draw(img); W = S * SS
    for layer, col in enumerate(((230, 70, 16), (255, 140, 24), (255, 220, 90))):
        for i in range(9 - layer * 2):
            x = W * (0.5 + random.uniform(-0.34, 0.34) * (1 - layer * 0.25))
            h = W * random.uniform(0.45, 0.95) * (1 - layer * 0.22); w = W * random.uniform(0.09, 0.16) * (1 - layer * 0.2)
            pts = [(x - w, W)]
            for k in range(1, 9):
                t = k / 9
                pts.append((x - w * (1 - t) ** 0.7 + math.sin(t * 7 + i) * w * 0.25, W - h * t))
            pts.append((x + math.sin(i) * w * 0.3, W - h))
            for k in range(8, 0, -1):
                t = k / 9
                pts.append((x + w * (1 - t) ** 0.7 + math.sin(t * 7 + i) * w * 0.25, W - h * t))
            pts.append((x + w, W))
            d.polygon(pts, fill=col + (255,))
    return finish(img, name)

flames_sprite("flames")

# ----------------------------------------------------------------------------- shared lookups

nz = np.stack([fbm(256, 4, 5, rng), fbm(256, 8, 4, rng), fbm(256, 16, 4, rng)], -1)
nz = (nz - nz.min()) / (nz.max() - nz.min())
Image.fromarray((nz * 255).astype(np.uint8)).save(os.path.join(OUT, "textures", "noise.png"), optimize=True)

# water height field: many directional waves with sharpened crests (integer wave vectors => tileable) + fine noise
yy, xx = np.mgrid[0:256, 0:256].astype(np.float32)
wh = np.zeros((256, 256), np.float32)
for _ in range(22):
    kx = rng.integers(-9, 10); ky = rng.integers(-9, 10)
    k = math.hypot(kx, ky)
    if k < 1.5: continue
    ph = rng.random() * math.tau
    w = np.sin((kx * xx + ky * yy) * (math.tau / 256.0) + ph)
    wh += (1.0 - np.abs(w)) ** 1.6 / (k ** 1.15)
wh = wh / wh.max() + fbm(256, 16, 3, rng) * 0.12
wn = normal_from_height(wh, 11.0)
foam = fbm(256, 8, 4, rng)
foam = (foam - foam.min()) / (foam.max() - foam.min())
r, g, _ = wn.split()
Image.merge("RGB", (r, g, Image.fromarray((foam * 255).astype(np.uint8)))).save(os.path.join(OUT, "textures", "water_normal.png"), optimize=True)

print("built", len(os.listdir(BLOCKS)), "block texture files")
