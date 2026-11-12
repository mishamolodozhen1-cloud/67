#!/usr/bin/env python3
"""Builds UI assets: the signed-distance-style font atlas and the item/interface icon atlas.

Fonts used (both SIL Open Font License 1.1): Inter SemiBold for text, Noto Color Emoji for pictograms.
Block item icons are isometric renders of the block textures produced by build_textures.py.

Outputs into app/src/main/assets/ui/:
  font.png   8-bit coverage/distance atlas          font.bin   glyph metrics (little endian)
  icons.png  RGBA icon grid (64 px cells)           icons.txt  icon names in grid order

usage: build_ui_assets.py <assets_dir>
"""
import math, os, struct, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1]
UI = os.path.join(OUT, "ui")
BLOCKS = os.path.join(OUT, "textures", "blocks")
os.makedirs(UI, exist_ok=True)

INTER = "/usr/share/fonts/opentype/inter/Inter-SemiBold.otf"
EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"

# ----------------------------------------------------------------------------- font atlas

def build_font():
    size = 44          # nominal glyph size in atlas pixels
    pad = 6            # distance-field spread around each glyph
    ss = 4             # supersampling
    chars = [chr(c) for c in range(32, 127)]
    chars += [chr(c) for c in range(0x410, 0x450)] + ["Ё", "ё"]
    chars += list("«»—–…№°×•→←↑↓✓★♥±½“”„‘’€")
    font = ImageFont.truetype(INTER, size * ss)
    ascent, descent = font.getmetrics()
    line_h = (ascent + descent) / ss
    cell_h = int(math.ceil(line_h)) + pad * 2
    W = 1024
    x = y = 0
    atlas = Image.new("L", (W, 1024), 0)
    glyphs = []
    for ch in chars:
        adv = font.getlength(ch) / ss
        bbox = font.getbbox(ch)  # at ss scale, relative to the origin (left, top of ascent box)
        gw = max(1, int(math.ceil((bbox[2] - bbox[0]) / ss))) if bbox else 1
        cw = gw + pad * 2
        if x + cw > W:
            x = 0; y += cell_h
        big = Image.new("L", (cw * ss, cell_h * ss), 0)
        d = ImageDraw.Draw(big)
        ox = pad * ss - (bbox[0] if bbox else 0)
        d.text((ox, pad * ss), ch, font=font, fill=255)
        # blur the supersampled mask: 0.5 stays on the outline, values fall off smoothly either side
        soft = big.filter(ImageFilter.GaussianBlur(ss * 1.6)).resize((cw, cell_h), Image.LANCZOS)
        atlas.paste(soft, (x, y))
        glyphs.append((ord(ch), x, y, cw, cell_h, (bbox[0] / ss if bbox else 0) - pad, adv))
        x += cw
    H = 1 << (y + cell_h - 1).bit_length()
    atlas = atlas.crop((0, 0, W, H))
    atlas.save(os.path.join(UI, "font.png"), optimize=True)
    with open(os.path.join(UI, "font.bin"), "wb") as f:
        f.write(struct.pack("<iiffff", len(glyphs), size, line_h, ascent / ss, float(pad), float(W)))
        f.write(struct.pack("<f", float(H)))
        for cp, gx, gy, gw, gh, xoff, adv in glyphs:
            f.write(struct.pack("<iffffff", cp, gx, gy, gw, gh, xoff, adv))
    print("font atlas", atlas.size, len(glyphs), "glyphs")

# ----------------------------------------------------------------------------- icons

CELL = 64

def tex(name):
    for ext in (".jpg", ".png"):
        p = os.path.join(BLOCKS, name + ext)
        if os.path.exists(p):
            return Image.open(p).convert("RGBA")
    raise FileNotFoundError(name)

def one_block(img):
    """Use one block worth of a multi-block tile so icons show the same scale as in the world."""
    w = img.size[0]
    return img.crop((0, 0, w // 2, w // 2))

def iso_cube(top, side, crop=True):
    S = 256
    t = (one_block(tex(top)) if crop else tex(top)).resize((S, S), Image.LANCZOS)
    s = (one_block(tex(side)) if crop else tex(side)).resize((S, S), Image.LANCZOS)
    def shade(img, k):
        a = np.asarray(img).astype(np.float32); a[..., :3] *= k
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    out = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    cx = S; hx = int(S * 0.86); hy = int(S * 0.43); h = int(S * 0.98)
    y0 = 20
    # affine maps: output (x, y) -> source (u, v)
    def paste(img, corners):
        (x0, y0_), (x1, y1), (x3, y3) = corners  # top-left, top-right, bottom-left of the parallelogram
        ax = (x1 - x0) / S; ay = (y1 - y0_) / S; bx = (x3 - x0) / S; by = (y3 - y0_) / S
        det = ax * by - bx * ay
        ia = by / det; ib = -bx / det; ic = -ay / det; id_ = ax / det
        coeff = (ia, ib, -(ia * x0 + ib * y0_), ic, id_, -(ic * x0 + id_ * y0_))
        layer = img.transform(out.size, Image.AFFINE, coeff, Image.BICUBIC)
        mask = Image.new("L", out.size, 0)
        x2 = x1 + (x3 - x0); y2 = y1 + (y3 - y0_)
        ImageDraw.Draw(mask).polygon([(x0, y0_), (x1, y1), (x2, y2), (x3, y3)], fill=255)
        layer.putalpha(Image.composite(layer.split()[3], Image.new("L", out.size, 0), mask))
        out.alpha_composite(layer)
    paste(shade(t, 1.0), ((cx, y0), (cx + hx, y0 + hy), (cx - hx, y0 + hy)))
    paste(shade(s, 0.78), ((cx - hx, y0 + hy), (cx, y0 + 2 * hy), (cx - hx, y0 + hy + h)))
    paste(shade(s, 0.58), ((cx, y0 + 2 * hy), (cx + hx, y0 + hy), (cx, y0 + 2 * hy + h)))
    return out.resize((CELL, CELL), Image.LANCZOS)

def flat(name):
    return tex(name).resize((CELL, CELL), Image.LANCZOS)

_emoji_font = ImageFont.truetype(EMOJI, 109)

def emoji(ch, tint=None, scale=0.92):
    img = Image.new("RGBA", (136, 128), (0, 0, 0, 0))
    ImageDraw.Draw(img).text((0, 0), ch, font=_emoji_font, embedded_color=True)
    bbox = img.getbbox()
    if bbox is None:
        return None
    img = img.crop(bbox)
    if tint is not None:
        a = np.asarray(img).astype(np.float32)
        g = a[..., :3].mean(axis=-1, keepdims=True)
        a[..., :3] = np.clip(g * np.array(tint, np.float32) / 128.0, 0, 255)
        img = Image.fromarray(a.astype(np.uint8))
    s = int(CELL * scale)
    img.thumbnail((s, s), Image.LANCZOS)
    out = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    out.alpha_composite(img, ((CELL - img.size[0]) // 2, (CELL - img.size[1]) // 2))
    return out

def canvas():
    return Image.new("RGBA", (CELL * 4, CELL * 4), (0, 0, 0, 0))

def done(img):
    return img.resize((CELL, CELL), Image.LANCZOS)

WOOD = (126, 86, 48, 255); WOOD_D = (92, 60, 32, 255)
TIER = {"stone": ((150, 152, 156, 255), (104, 106, 110, 255)), "copper": ((214, 128, 74, 255), (160, 86, 44, 255)),
        "iron": ((206, 212, 220, 255), (140, 148, 158, 255))}

def handle(d, x0, y0, x1, y1, w=16):
    d.line((x0, y0, x1, y1), fill=WOOD_D, width=w + 6)
    d.line((x0, y0, x1, y1), fill=WOOD, width=w)

def tool(kind, tier):
    img = canvas(); d = ImageDraw.Draw(img); c, cd = TIER[tier]
    if kind == "axe":
        handle(d, 60, 215, 180, 60)
        d.polygon([(150, 30), (232, 62), (226, 136), (168, 104), (140, 86)], fill=cd)
        d.polygon([(156, 40), (222, 68), (216, 122), (170, 96), (150, 82)], fill=c)
    elif kind == "pickaxe":
        handle(d, 56, 214, 168, 72)
        d.line([(86, 70), (130, 42), (180, 40), (224, 62), (240, 100)], fill=cd, width=34, joint="curve")
        d.line([(90, 68), (130, 46), (180, 44), (220, 64), (234, 96)], fill=c, width=20, joint="curve")
    elif kind == "shovel":
        handle(d, 60, 214, 150, 104)
        d.polygon([(138, 76), (190, 40), (228, 78), (192, 130), (150, 118)], fill=cd)
        d.polygon([(148, 80), (190, 52), (216, 80), (188, 118), (156, 110)], fill=c)
    elif kind == "knife":
        handle(d, 62, 204, 112, 150, 22)
        d.polygon([(104, 150), (212, 36), (228, 52), (132, 172)], fill=cd)
        d.polygon([(112, 150), (208, 48), (216, 56), (132, 162)], fill=c)
    elif kind == "hoe":
        handle(d, 56, 214, 176, 64)
        d.polygon([(150, 44), (200, 54), (230, 110), (206, 118), (182, 82), (146, 70)], fill=cd)
        d.polygon([(156, 50), (196, 60), (220, 106), (208, 108), (186, 74), (154, 64)], fill=c)
    elif kind == "sickle":
        handle(d, 70, 214, 116, 150, 20)
        d.arc((70, 30, 220, 180), 200, 20, fill=cd, width=30)
        d.arc((76, 36, 214, 174), 204, 16, fill=c, width=16)
    elif kind == "spear":
        handle(d, 44, 220, 188, 70, 12)
        d.polygon([(176, 84), (236, 22), (206, 94)], fill=cd); d.polygon([(186, 78), (226, 34), (206, 84)], fill=c)
    elif kind == "arrow":
        handle(d, 60, 204, 186, 78, 8)
        d.polygon([(176, 90), (226, 34), (198, 96)], fill=TIER["stone"][0])
        d.polygon([(60, 204), (44, 176), (84, 190)], fill=(230, 230, 236, 255)); d.polygon([(60, 204), (88, 222), (74, 182)], fill=(200, 200, 210, 255))
    return done(img)

def nugget(col, hi):
    img = canvas(); d = ImageDraw.Draw(img)
    for (x, y, r) in ((104, 150, 58), (166, 128, 50), (128, 100, 42)):
        d.ellipse((x - r, y - r, x + r, y + r), fill=tuple(int(v * 0.7) for v in col) + (255,))
        d.ellipse((x - r + 8, y - r + 6, x + r - 6, y + r - 12), fill=col + (255,))
        d.ellipse((x - r * 0.5, y - r * 0.6, x, y - r * 0.2), fill=hi + (255,))
    return done(img)

def ingot(col, hi):
    img = canvas(); d = ImageDraw.Draw(img)
    dark = tuple(int(v * 0.62) for v in col) + (255,)
    d.polygon([(36, 150), (84, 96), (220, 96), (228, 150), (196, 196), (56, 196)], fill=dark)
    d.polygon([(84, 96), (220, 96), (196, 140), (64, 140)], fill=col + (255,))
    d.polygon([(96, 104), (204, 104), (196, 116), (90, 116)], fill=hi + (255,))
    return done(img)

def stick():
    img = canvas(); d = ImageDraw.Draw(img)
    handle(d, 56, 210, 200, 50, 18); d.line((130, 128, 170, 120), fill=WOOD, width=10)
    return done(img)

def pouch(full):
    img = canvas(); d = ImageDraw.Draw(img)
    d.ellipse((60, 84, 200, 230), fill=(120, 80, 50, 255)); d.ellipse((72, 96, 188, 218), fill=(150, 104, 66, 255))
    d.rectangle((112, 40, 148, 96), fill=(120, 80, 50, 255)); d.rectangle((104, 30, 156, 52), fill=(80, 54, 34, 255))
    if full:
        d.ellipse((96, 140, 164, 208), fill=(70, 150, 220, 255)); d.polygon([(130, 104), (104, 160), (156, 160)], fill=(70, 150, 220, 255))
    return done(img)

def bucket(full):
    img = canvas(); d = ImageDraw.Draw(img)
    d.polygon([(60, 86), (196, 86), (176, 222), (80, 222)], fill=(150, 156, 166, 255))
    d.ellipse((60, 66, 196, 108), fill=(70, 150, 220, 255) if full else (96, 100, 108, 255), outline=(190, 196, 206, 255), width=8)
    d.arc((60, 20, 196, 150), 190, 350, fill=(110, 114, 122, 255), width=8)
    return done(img)

def sheet(col, fold):
    img = canvas(); d = ImageDraw.Draw(img)
    d.polygon([(50, 70), (196, 50), (210, 190), (64, 208)], fill=col + (255,))
    d.polygon([(196, 50), (210, 190), (180, 170), (170, 70)], fill=fold + (255,))
    return done(img)

ICONS = []   # (name, image)

def add(name, img):
    if img is None:
        img = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        d = ImageDraw.Draw(img); d.ellipse((8, 8, 56, 56), fill=(200, 60, 160, 255))
        print("WARNING: icon fallback for", name)
    ICONS.append((name, img))

def build_icons():
    add("missing", emoji("❓"))
    cubes = {
        "grass": ("grass_top", "grass_side"), "dirt": ("dirt", "dirt"), "stone": ("stone", "stone"), "sand": ("sand", "sand"),
        "gravel": ("gravel", "gravel"), "clay": ("clay", "clay"), "snow": ("snow", "snow"), "ice": ("ice", "ice"),
        "mossy_stone": ("mossy_stone", "mossy_stone"), "sandstone": ("sandstone", "sandstone"), "mud": ("mud", "mud"),
        "forest_floor": ("forest_floor", "dirt"), "grass_lush": ("grass_lush", "lush_side"), "grass_dry": ("grass_dry", "dry_side"),
        "snowy_grass": ("snow", "snow_side"), "coal_ore": ("coal_ore", "coal_ore"), "copper_ore": ("copper_ore", "copper_ore"),
        "iron_ore": ("iron_ore", "iron_ore"), "gold_ore": ("gold_ore", "gold_ore"), "crystal_ore": ("crystal_ore", "crystal_ore"),
        "planks_oak": ("planks_oak", "planks_oak"), "planks_pine": ("planks_pine", "planks_pine"), "cobblestone": ("cobblestone", "cobblestone"),
        "stone_bricks": ("stone_bricks", "stone_bricks"), "bricks": ("bricks", "bricks"), "thatch": ("thatch", "thatch"),
        "metal_panel": ("metal_panel", "metal_panel"), "lab_floor": ("lab_floor", "lab_floor"), "rusty_metal": ("rusty_metal", "rusty_metal"),
        "oak_leaves": ("oak_leaves", "oak_leaves"), "pine_leaves": ("pine_leaves", "pine_leaves"), "birch_leaves": ("birch_leaves", "birch_leaves"),
        "palm_leaves": ("palm_leaves", "palm_leaves"), "jungle_leaves": ("jungle_leaves", "jungle_leaves"), "fruit_leaves": ("fruit_leaves", "fruit_leaves"),
    }
    whole = {
        "oak_log": ("oak_top", "oak_bark"), "pine_log": ("pine_top", "pine_bark"), "birch_log": ("birch_top", "birch_bark"),
        "palm_log": ("palm_top", "palm_bark"), "workbench": ("workbench_top", "workbench_side"), "furnace": ("furnace_top", "furnace_side"),
        "chest": ("chest_top", "chest_side"), "farmland": ("farmland", "dirt"), "lamp": ("lamp", "lamp"), "crate": ("crate", "crate"),
        "glass": ("glass", "glass"), "campfire": ("campfire", "campfire"), "bedroll": ("bedroll", "bedroll"),
    }
    for k, (t, s) in cubes.items(): add("b_" + k, iso_cube(t, s, True))
    for k, (t, s) in whole.items(): add("b_" + k, iso_cube(t, s, False))
    add("b_torch", emoji("🔥", scale=0.8))
    for k in ("tall_grass", "fern", "flower_red", "flower_yellow", "flower_blue", "mushroom", "reeds", "berry_bush", "dead_bush", "sapling"):
        add("b_" + k, flat(k))

    add("stick", stick())
    add("plant_fiber", emoji("🌿"))
    add("flint", nugget((70, 74, 84), (150, 156, 170)))
    add("clay_ball", nugget((176, 130, 108), (220, 184, 164)))
    add("coal", nugget((34, 34, 38), (96, 96, 108)))
    add("raw_copper", nugget((196, 110, 62), (255, 190, 130)))
    add("raw_iron", nugget((150, 124, 110), (226, 206, 194)))
    add("raw_gold", nugget((226, 176, 44), (255, 244, 170)))
    add("crystal", emoji("💎"))
    add("copper_ingot", ingot((214, 128, 74), (255, 196, 150)))
    add("iron_ingot", ingot((196, 202, 212), (245, 248, 252)))
    add("gold_ingot", ingot((236, 190, 54), (255, 246, 180)))
    add("rope", emoji("🪢") or emoji("➰"))
    add("leather", sheet((150, 100, 60), (112, 72, 42)))
    add("bone", emoji("🦴"))
    add("feather", emoji("🪶") or sheet((236, 236, 240), (200, 200, 210)))
    add("brick", emoji("🧱"))
    add("cloth", sheet((214, 206, 182), (176, 168, 146)))
    add("charcoal", nugget((52, 46, 44), (110, 100, 96)))
    add("berries", emoji("🍒"))
    add("apple", emoji("🍎"))
    add("mushroom_item", emoji("🍄"))
    add("raw_meat", emoji("🥩"))
    add("cooked_meat", emoji("🍖"))
    add("carrot", emoji("🥕"))
    add("wheat", emoji("🌾"))
    add("bread", emoji("🍞"))
    add("raw_fish", emoji("🐟"))
    add("cooked_fish", emoji("🐟", tint=(230, 150, 80)))
    add("coconut", emoji("🥥"))
    add("stew", emoji("🍲"))
    add("wheat_seeds", emoji("🌱"))
    for tier in ("stone", "copper", "iron"):
        for kind in ("axe", "pickaxe", "shovel"):
            add(f"{tier}_{kind}", tool(kind, tier))
    add("stone_knife", tool("knife", "stone")); add("iron_knife", tool("knife", "iron"))
    add("hoe", tool("hoe", "stone")); add("sickle", tool("sickle", "copper")); add("spear", tool("spear", "stone"))
    add("bow", emoji("🏹")); add("arrow", tool("arrow", "stone")); add("fishing_rod", emoji("🎣"))
    add("waterskin", pouch(False)); add("waterskin_full", pouch(True))
    add("bucket", bucket(False)); add("bucket_water", bucket(True))
    add("flint_striker", emoji("🔥"))
    add("fiber_shirt", emoji("👕", tint=(150, 170, 110))); add("leather_jacket", emoji("🧥"))
    add("fur_coat", emoji("🧥", tint=(190, 170, 150))); add("leather_boots", emoji("🥾") or emoji("👢")); add("backpack", emoji("🎒"))
    add("raft", emoji("🛶")); add("note", emoji("📜")); add("keycard", emoji("💳")); add("map_fragment", emoji("🗺"))
    add("radio_part", emoji("📻"))

    # interface pictograms
    ui = {"ui_heart": "❤", "ui_food": "🍗", "ui_water": "💧", "ui_energy": "⚡", "ui_temp": "🌡", "ui_settings": "⚙",
          "ui_map": "🧭", "ui_bag": "🎒", "ui_craft": "🔨", "ui_journal": "📖", "ui_paw": "🐾", "ui_pause": "⏸",
          "ui_jump": "⬆", "ui_hand": "✋", "ui_mine": "⛏", "ui_place": "🧱", "ui_camera": "🎥", "ui_run": "🏃",
          "ui_crouch": "⬇", "ui_save": "💾", "ui_sun": "☀", "ui_moon": "🌙", "ui_cloud": "☁", "ui_rain": "🌧",
          "ui_storm": "⛈", "ui_skull": "☠", "ui_ok": "✅", "ui_no": "❌", "ui_lock": "🔒", "ui_star": "⭐", "ui_play": "▶",
          "ui_home": "🏠", "ui_fog": "🌫", "ui_snow": "❄", "ui_rotate": "🔄", "ui_trash": "🗑", "ui_sleep": "💤",
          "ui_eat": "🍴", "ui_marker": "📍", "ui_flag": "🚩", "ui_wind": "💨", "ui_fire": "🔥", "ui_info": "ℹ"}
    for k, ch in ui.items(): add(k, emoji(ch))
    animals = {"deer": "🦌", "wolf": "🐺", "rabbit": "🐇", "fox": "🦊", "bear": "🐻", "boar": "🐗", "squirrel": "🐿", "horse": "🐎",
               "moose": "🫎", "lynx": "🐈", "eagle": "🦅", "owl": "🦉", "crow": "🐦", "gull": "🕊", "duck": "🦆", "goose": "🪿",
               "parrot": "🦜", "woodpecker": "🐤", "fish": "🐟", "shark": "🦈", "dolphin": "🐬", "turtle": "🐢", "crab": "🦀",
               "octopus": "🐙", "jellyfish": "🪼", "seal": "🦭", "snake": "🐍", "lizard": "🦎", "crocodile": "🐊", "frog": "🐸",
               "butterfly": "🦋", "bee": "🐝", "ant": "🐜", "dragonfly": "🪰", "beetle": "🪲", "firefly": "✨", "mosquito": "🦟",
               "hare": "🐰", "roe": "🦌", "falcon": "🦅", "pigeon": "🕊", "songbird": "🐦", "toad": "🐸", "salamander": "🦎"}
    for k, ch in animals.items(): add("a_" + k, emoji(ch))

    cols = 16
    rows = (len(ICONS) + cols - 1) // cols
    H = 1 << (rows * CELL - 1).bit_length()
    atlas = Image.new("RGBA", (cols * CELL, H), (0, 0, 0, 0))
    for i, (name, img) in enumerate(ICONS):
        atlas.alpha_composite(img, ((i % cols) * CELL, (i // cols) * CELL))
    atlas.save(os.path.join(UI, "icons.png"), optimize=True)
    with open(os.path.join(UI, "icons.txt"), "w") as f:
        f.write("\n".join(n for n, _ in ICONS) + "\n")
    print("icon atlas", atlas.size, len(ICONS), "icons")

build_font()
build_icons()
