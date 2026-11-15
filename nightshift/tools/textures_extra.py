"""Дополнительные текстуры: хлеб, овощи/фрукты в ящиках (вид сверху), заморозка (вид сверху)."""
import random, sys, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = sys.argv[1]
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
def font(s): return ImageFont.truetype(BOLD, s)

def bread():
    rng = random.Random(7)
    W, H = 1024, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    x = 6
    while x < W - 60:
        kind = rng.random()
        if kind < 0.4:  # батон
            w, h = rng.randint(150, 190), rng.randint(70, 90)
            y = H - h - 4
            base = (rng.randint(196, 214), rng.randint(140, 156), rng.randint(70, 86))
            d.rounded_rectangle([x, y, x + w, H - 4], radius=h // 2, fill=base + (255,))
            d.rounded_rectangle([x + 6, y + 4, x + w - 6, y + h * 0.45], radius=h // 3, fill=tuple(min(255, c + 22) for c in base) + (255,))
            for k in range(4):
                cx = x + w * (0.2 + 0.2 * k)
                d.line([cx - 10, y + 10, cx + 10, y + h * 0.55], fill=(240, 214, 160, 255), width=6)
            d.rectangle([x + w * 0.35, y + h * 0.55, x + w * 0.65, H - 10], fill=(250, 250, 245, 200))
            x += w + rng.randint(4, 12)
        elif kind < 0.7:  # круглый хлеб
            r = rng.randint(48, 60)
            cy = H - r - 4
            base = (rng.randint(150, 175), rng.randint(96, 112), rng.randint(52, 64))
            d.ellipse([x, cy - r * 0.8, x + 2 * r, H - 4], fill=base + (255,))
            d.ellipse([x + 10, cy - r * 0.7, x + 2 * r - 10, cy], fill=tuple(min(255, c + 25) for c in base) + (255,))
            d.line([x + r * 0.5, cy - r * 0.3, x + r * 1.5, cy - r * 0.3], fill=(220, 190, 140, 255), width=5)
            x += 2 * r + rng.randint(4, 10)
        else:  # булочки в пакете
            w, h = rng.randint(110, 130), rng.randint(90, 110)
            y = H - h - 4
            d.rounded_rectangle([x, y, x + w, H - 4], radius=16, fill=(235, 235, 230, 170))
            for i in range(3):
                for j in range(2):
                    cx, cy = x + 22 + i * 36, y + 30 + j * 38
                    d.ellipse([cx - 18, cy - 15, cx + 18, cy + 15], fill=(214, 160, 88, 255))
                    d.ellipse([cx - 12, cy - 12, cx + 8, cy - 2], fill=(236, 190, 120, 255))
            d.rectangle([x + 10, y + h - 26, x + w - 10, y + h - 8], fill=(200, 40, 44, 255))
            x += w + rng.randint(6, 12)
    return img

def produce():
    rng = random.Random(11)
    W, H = 512, 512
    img = Image.new("RGBA", (W, H), (60, 42, 26, 255)); d = ImageDraw.Draw(img)
    kinds = [((200, 30, 40), (120, 10, 20), 30), ((240, 140, 20), (180, 90, 10), 30), ((210, 190, 120), (150, 120, 70), 28),
             ((60, 150, 40), (30, 90, 20), 32)]
    q = W // 2
    for qi in range(4):
        c1, c2, r = kinds[qi]
        ox, oy = (qi % 2) * q, (qi // 2) * q
        d.rectangle([ox + 4, oy + 4, ox + q - 4, oy + q - 4], outline=(120, 86, 50, 255), width=8)
        for _ in range(70):
            cx, cy = ox + rng.randint(r, q - r), oy + rng.randint(r, q - r)
            rr = r + rng.randint(-4, 4)
            d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=c2 + (255,))
            d.ellipse([cx - rr + 3, cy - rr + 3, cx + rr - 6, cy + rr - 6], fill=c1 + (255,))
            d.ellipse([cx - rr * 0.5, cy - rr * 0.6, cx - rr * 0.1, cy - rr * 0.2], fill=tuple(min(255, c + 60) for c in c1) + (255,))
    return img

def frozen():
    rng = random.Random(5)
    W, H = 512, 512
    img = Image.new("RGBA", (W, H), (210, 225, 235, 255)); d = ImageDraw.Draw(img)
    names = ["ПЕЛЬМЕНИ", "МОРОЖЕНОЕ", "ВАРЕНИКИ", "ПЛОМБИР", "ОВОЩИ", "БЛИНЧИКИ"]
    cols = [(40, 80, 170), (200, 40, 60), (30, 140, 90), (240, 190, 40), (120, 60, 160), (236, 120, 30)]
    y = 4
    while y < H - 40:
        h = rng.randint(70, 100); x = 4
        while x < W - 40:
            w = rng.randint(100, 160)
            i = rng.randrange(len(names)); c = cols[i]
            d.rectangle([x, y, x + w, y + h], fill=c + (255,))
            d.rectangle([x + 6, y + h * 0.3, x + w - 6, y + h * 0.7], fill=(255, 255, 255, 235))
            f = font(18)
            tw = d.textlength(names[i], font=f)
            if tw > w - 16:
                f = font(int(18 * (w - 16) / tw)); tw = d.textlength(names[i], font=f)
            d.text((x + (w - tw) / 2, y + h * 0.5 - 11), names[i], font=f, fill=c)
            x += w + 4
        y += h + 4
    return img.filter(ImageFilter.GaussianBlur(0.6))

bread().save(f"{OUT}/shelf_bread.png")
produce().save(f"{OUT}/produce_top.png")
frozen().save(f"{OUT}/frozen_top.png")
print("ok")
