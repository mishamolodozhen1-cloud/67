"""Простой растеризатор для проверки манекена и поз без Roblox: z-буфер, плавное освещение, пол-шахматка.

render(items, eye, target, fov, W, H) -> PIL.Image
items: [(pos (N,3), nrm (N,3), col (N,3) 0..255, idx (M,3))] в мировых координатах (Y вверх).
"""
import math

import numpy as np
from PIL import Image

LIGHT = np.array([-0.45, 0.8, -0.4])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
FILL = np.array([0.6, 0.3, 0.7])
FILL = FILL / np.linalg.norm(FILL)


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = (np.asarray(v, float) for v in (eye, target, up))
    f = target - eye
    f /= np.linalg.norm(f)
    r = np.cross(f, up)
    r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, r, u, f


def ground(size=8.0, step=1.0, y=0.0):
    pos, idx, col = [], [], []
    n = int(size / step)
    for i in range(-n, n):
        for j in range(-n, n):
            x0, z0 = i * step, j * step
            k = len(pos)
            pos += [(x0, y, z0), (x0 + step, y, z0), (x0 + step, y, z0 + step), (x0, y, z0 + step)]
            c = (70, 72, 76) if (i + j) % 2 == 0 else (58, 60, 64)
            col += [c] * 4
            idx += [(k, k + 1, k + 2), (k, k + 2, k + 3)]
    pos = np.array(pos, float)
    return pos, np.tile([0, 1, 0], (len(pos), 1)).astype(float), np.array(col, float), np.array(idx, int)


def render(items, eye, target, fov=35.0, W=640, H=900, bg=(26, 28, 32), near=None):
    cam, r, u, f = look_at(eye, target)
    img = np.zeros((H, W, 3), float)
    img[:] = bg
    zbuf = np.full((H, W), np.inf)
    t = math.tan(math.radians(fov) / 2)
    for pos, nrm, col, idx in items:
        rel = pos - cam
        x, y, z = rel @ r, rel @ u, rel @ f
        zr = z.copy()
        z = np.maximum(z, 1e-3)
        sx = (x / (z * t)) * (H / 2) + W / 2
        sy = -(y / (z * t)) * (H / 2) + H / 2
        # свет на вершинах: основной + заполняющий + немного «неба»
        nl = np.clip(nrm @ LIGHT, 0, 1)
        nf = np.clip(nrm @ FILL, 0, 1)
        sky = 0.5 + 0.5 * nrm[:, 1]
        shade = 0.28 + 0.62 * nl + 0.18 * nf + 0.12 * sky
        vcol = np.clip(col * shade[:, None], 0, 255)
        for a, b, c in idx:
            # ближняя плоскость (как у камеры Roblox): треугольники, задевающие её, не рисуем
            if near is not None and min(zr[a], zr[b], zr[c]) < near:
                continue
            xs = np.array([sx[a], sx[b], sx[c]])
            ys = np.array([sy[a], sy[b], sy[c]])
            x0, x1 = int(max(0, math.floor(xs.min()))), int(min(W - 1, math.ceil(xs.max())))
            y0, y1 = int(max(0, math.floor(ys.min()))), int(min(H - 1, math.ceil(ys.max())))
            if x0 > x1 or y0 > y1:
                continue
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            w2 = 1 - w0 - w1
            inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not inside.any():
                continue
            zz = w0 * z[a] + w1 * z[b] + w2 * z[c]
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            m = inside & (zz < sub)
            if not m.any():
                continue
            sub[m] = zz[m]
            cc = w0[..., None] * vcol[a] + w1[..., None] * vcol[b] + w2[..., None] * vcol[c]
            img[y0:y1 + 1, x0:x1 + 1][m] = cc[m]
    return Image.fromarray(img.astype(np.uint8))


def label(img, text):
    from PIL import ImageDraw, ImageFont
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    d.text((8, 6), text, fill=(230, 230, 230), font=font)
    return img


def sheet(images, cols):
    w, h = images[0].size
    rows = (len(images) + cols - 1) // cols
    out = Image.new("RGB", (w * cols, h * rows), (0, 0, 0))
    for i, im in enumerate(images):
        out.paste(im, ((i % cols) * w, (i // cols) * h))
    return out
