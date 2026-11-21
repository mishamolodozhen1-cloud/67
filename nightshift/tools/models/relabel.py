"""Заменить этикетки с упоминанием алкоголя на свои (атлас хранится перевёрнутым на 180°)."""
import sys
from PIL import Image, ImageDraw, ImageFont
P = sys.argv[1]
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
REG = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
im = Image.open(P + '/clean/Asset_baseColor.png').convert('RGB')

def label(w, h, bg, fg, title, sub, small):
    lab = Image.new('RGB', (w, h), bg)
    d = ImageDraw.Draw(lab)
    d.rectangle([0, 0, w - 1, int(h * 0.12)], fill=fg)
    d.rectangle([0, h - int(h * 0.12), w - 1, h - 1], fill=fg)
    def fit(text, font_path, max_w, max_h):
        size = max_h
        while size > 6:
            f = ImageFont.truetype(font_path, size)
            bb = d.textbbox((0, 0), text, font=f)
            if bb[2] - bb[0] <= max_w and bb[3] - bb[1] <= max_h:
                return f, bb
            size -= 1
        return ImageFont.truetype(font_path, 6), d.textbbox((0, 0), text, font=ImageFont.truetype(font_path, 6))
    f, bb = fit(title, BOLD, int(w * 0.5), int(h * 0.32))
    d.text(((w - (bb[2] - bb[0])) / 2 - bb[0], h * 0.22 - bb[1]), title, font=f, fill=fg)
    f2, bb2 = fit(sub, REG, int(w * 0.5), int(h * 0.16))
    d.text(((w - (bb2[2] - bb2[0])) / 2 - bb2[0], h * 0.6 - bb2[1]), sub, font=f2, fill=fg)
    f3, bb3 = fit(small, REG, int(w * 0.22), int(h * 0.1))
    d.text((w * 0.03, h * 0.75), small, font=f3, fill=fg)
    d.text((w * 0.75, h * 0.75), small, font=f3, fill=fg)
    return lab

def paste(lab, box):
    x0, y0, x1, y1 = box
    im.paste(lab.resize((x1 - x0, y1 - y0), Image.LANCZOS).rotate(180), (x0, y0))

def lid(cx, cy, r):
    d = ImageDraw.Draw(im)
    for k in range(r, 0, -1):
        v = int(150 + 50 * (1 - k / r))
        d.ellipse([cx - k, cy - k, cx + k, cy + k], fill=(v, v, v + 4))
    d.ellipse([cx - r * 0.75, cy - r * 0.75, cx + r * 0.75, cy + r * 0.75], outline=(120, 120, 124), width=2)

# банка «ALCOHOL-SOAKED …» -> фасоль
paste(label(520, 106, (46, 120, 60), (245, 240, 220), 'ФАСОЛЬ «ДАЧНАЯ»', 'в томатном соусе', '400 г'), (215, 262, 480, 315))
lid(65, 408, 56)
# банка «FRESH CIRRHOSIS / STEWED LIVER» -> тушёнка
paste(label(740, 170, (170, 30, 34), (250, 244, 230), 'ТУШЁНКА «ВОЛГА»', 'говядина тушёная · высший сорт', '325 г'), (490, 180, 860, 265))
lid(65, 665, 56)
im.save(P + '/clean/Asset_baseColor.png')
im.crop((0, 160, 880, 720)).rotate(180).save(P + '/clean/zoomA2.png')
