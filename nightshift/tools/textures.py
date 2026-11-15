"""Текстуры для NIGHT SHIFT: ряды товаров на полках, помехи для камер."""
import random, sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1]
W, H = 1024, 256
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BRANDS = ["Зёрнышко", "Хрум", "Капля", "Ночка", "Утро", "Смена", "Добрый", "Луч", "Север", "Сытно", "Март", "Чистота", "Снежок", "Пчёлка"]

def font(size, bold=True):
    return ImageFont.truetype(BOLD if bold else REG, size)

def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3]) + ((c[3],) if len(c) > 3 else ())

def vgrad(d, box, c1, c2):
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        d.line([x0, y, x1, y], fill=tuple(int(a + (b - a) * t) for a, b in zip(c1, c2)) + (255,))

def hgrad_cyl(d, box, base):
    """Цилиндрическое затенение (бутылки, банки)."""
    x0, y0, x1, y1 = box
    for x in range(x0, x1):
        t = (x - x0) / max(1, x1 - x0)
        k = 0.55 + 0.6 * math.sin(math.pi * t) + (0.25 if 0.22 < t < 0.3 else 0)
        d.line([x, y0, x, y1], fill=shade(base, k) + (255,))

PALETTE = [(196, 40, 44), (240, 196, 40), (40, 110, 196), (30, 150, 80), (236, 120, 30), (120, 60, 160),
           (230, 230, 225), (60, 60, 70), (200, 80, 140), (110, 170, 220), (160, 110, 60), (250, 220, 150)]

def label(d, x, y, w, text, size, color=(255, 255, 255)):
    f = font(size)
    tw = d.textlength(text, font=f)
    if tw > w - 4:
        f = font(max(8, int(size * (w - 4) / tw)))
        tw = d.textlength(text, font=f)
    d.text((x + (w - tw) / 2, y), text, font=f, fill=color)

def boxes(rng):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 6
    while x < W - 40:
        w = rng.randint(58, 96); h = rng.randint(150, 236); c = rng.choice(PALETTE)
        n = rng.randint(2, 4)
        for i in range(n):
            if x + w > W - 4: break
            top = H - h
            vgrad(d, (x, top, x + w, H), shade(c, 1.12), shade(c, 0.78))
            d.rectangle([x, top, x + w, top + 6], fill=shade(c, 0.6) + (255,))
            d.rectangle([x + 6, top + 26, x + w - 6, top + 70], fill=(255, 255, 255, 230))
            label(d, x + 6, top + 34, w - 12, rng.choice(BRANDS), 18, shade(c, 0.6))
            d.ellipse([x + w * 0.25, top + 90, x + w * 0.75, top + 90 + w * 0.5], fill=shade(rng.choice(PALETTE), 1.0) + (255,))
            d.line([x + w - 1, top, x + w - 1, H], fill=(0, 0, 0, 120), width=2)
            x += w + 2
        x += rng.randint(4, 10)
    return img

def bottles(rng, tall=True):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 8
    while x < W - 30:
        c = rng.choice(PALETTE); w = rng.randint(36, 52); n = rng.randint(3, 6)
        h = rng.randint(190, 240) if tall else rng.randint(130, 170)
        for i in range(n):
            if x + w > W - 4: break
            top = H - h; neck = int(h * 0.22)
            hgrad_cyl(d, (x, top + neck, x + w, H - 2), c)
            d.polygon([(x + 4, top + neck), (x + w - 4, top + neck), (x + w * 0.65, top + 14), (x + w * 0.35, top + 14)], fill=shade(c, 0.85) + (255,))
            d.rectangle([x + w * 0.33, top, x + w * 0.67, top + 16], fill=shade(rng.choice(PALETTE), 0.9) + (255,))
            ly = top + neck + int(h * 0.25)
            d.rectangle([x + 1, ly, x + w - 1, ly + 46], fill=(250, 250, 245, 235))
            label(d, x + 1, ly + 12, w - 2, rng.choice(BRANDS), 13, shade(c, 0.55))
            x += w + 3
        x += rng.randint(6, 14)
    return img

def bags(rng):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 6
    while x < W - 60:
        c = rng.choice(PALETTE); w = rng.randint(80, 110); n = rng.randint(2, 4)
        for i in range(n):
            if x + w > W - 4: break
            top = H - rng.randint(170, 220)
            d.rounded_rectangle([x, top, x + w, H - 4], radius=18, fill=c + (255,))
            vgrad(d, (x + 8, top + 8, x + w - 8, top + 40), shade(c, 1.3), c)
            d.polygon([(x, top + 10), (x + w, top + 10), (x + w - 6, top - 4), (x + 6, top - 4)], fill=shade(c, 0.7) + (255,))
            label(d, x + 4, top + 50, w - 8, rng.choice(BRANDS), 22, (255, 255, 255))
            d.ellipse([x + w * 0.2, top + 90, x + w * 0.8, top + 150], fill=(240, 200, 90, 255))
            x += w + 4
        x += rng.randint(6, 12)
    return img

def cans(rng):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    for row in range(2):
        x = 6; base = H - row * 118
        while x < W - 40:
            c = rng.choice(PALETTE); w = rng.randint(54, 66); n = rng.randint(3, 7)
            for i in range(n):
                if x + w > W - 4: break
                top = base - 112
                hgrad_cyl(d, (x, top + 8, x + w, base - 4), c)
                d.ellipse([x, top, x + w, top + 16], fill=(200, 200, 205, 255))
                d.rectangle([x + 2, top + 40, x + w - 2, top + 72], fill=(250, 248, 240, 230))
                label(d, x + 2, top + 48, w - 4, rng.choice(BRANDS), 14, shade(c, 0.5))
                x += w + 2
            x += rng.randint(4, 10)
    return img

def dairy(rng):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 6
    while x < W - 40:
        kind = rng.random()
        if kind < 0.5:  # пакеты молока
            c = rng.choice([(40, 110, 196), (220, 60, 60), (30, 150, 80), (240, 196, 40)]); w = 58
            for i in range(rng.randint(3, 5)):
                if x + w > W - 4: break
                top = H - 220
                d.rectangle([x, top + 30, x + w, H - 4], fill=(246, 246, 242, 255))
                d.polygon([(x, top + 30), (x + w, top + 30), (x + w / 2, top)], fill=(236, 236, 232, 255))
                d.rectangle([x, top + 110, x + w, H - 4], fill=c + (255,))
                label(d, x + 2, top + 60, w - 4, "МОЛОКО", 11, c)
                label(d, x + 2, top + 130, w - 4, rng.choice(BRANDS), 13)
                x += w + 3
        else:  # стаканчики йогурта
            c = rng.choice(PALETTE); w = 46
            for i in range(rng.randint(4, 8)):
                if x + w > W - 4: break
                top = H - 96
                d.polygon([(x, top), (x + w, top), (x + w - 5, H - 4), (x + 5, H - 4)], fill=(250, 250, 248, 255))
                d.rectangle([x + 2, top + 30, x + w - 2, top + 60], fill=c + (255,))
                d.rectangle([x - 1, top - 6, x + w + 1, top], fill=(200, 200, 205, 255))
                x += w + 2
        x += rng.randint(6, 12)
    return img

def household(rng):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 8
    while x < W - 50:
        c = rng.choice([(40, 110, 196), (30, 150, 80), (236, 120, 30), (200, 80, 140), (110, 170, 220), (230, 230, 225)])
        w = rng.randint(64, 84)
        for i in range(rng.randint(2, 4)):
            if x + w > W - 4: break
            top = H - rng.randint(200, 236)
            d.rounded_rectangle([x, top + 30, x + w, H - 4], radius=10, fill=c + (255,))
            hgrad_cyl(d, (x + 4, top + 34, x + w - 4, H - 8), c)
            d.rounded_rectangle([x + w * 0.55, top + 6, x + w - 4, top + 40], radius=8, outline=c + (255,), width=8)
            d.rectangle([x + w * 0.2, top + 10, x + w * 0.5, top + 32], fill=shade(c, 0.6) + (255,))
            d.rectangle([x + 6, top + 80, x + w - 6, top + 140], fill=(255, 255, 255, 235))
            label(d, x + 6, top + 98, w - 12, rng.choice(["Чистота", "Снежок", "Блеск", "Свежесть"]), 14, shade(c, 0.6))
            x += w + 4
        x += rng.randint(6, 12)
    return img

def noise():
    rng = random.Random(3)
    img = Image.new("RGBA", (256, 256))
    px = img.load()
    for y in range(256):
        line = 18 if y % 3 == 0 else 0
        for x in range(256):
            v = rng.randint(0, 255)
            px[x, y] = (v, v, v, min(255, 40 + line + rng.randint(0, 50)))
    return img

for name, fn in (("shelf_grocery", boxes), ("shelf_drinks", lambda r: bottles(r, True)), ("shelf_snacks", bags),
                 ("shelf_cans", cans), ("fridge_dairy", dairy), ("shelf_household", household)):
    fn(random.Random(hash(name) % 1000)).save(f"{OUT}/{name}.png")
noise().save(f"{OUT}/cctv_noise.png")
print("ok")
