"""prep.py <tex8 dir> — подготовить PBR-карты для MaterialVariant:
  • плитка пола: светлее и нейтральнее (белёсо-серая плитка супермаркета)
  • потолок: рисуем сами подвесные плиты 60×60 (Армстронг) с мелкими проколами и профилем — цвет, нормали, шероховатость
  • остальные карты — как есть, 1024×1024 PNG/JPG"""
import sys, os, numpy as np
from PIL import Image, ImageFilter, ImageEnhance, ImageOps
D = sys.argv[1]
R, O = os.path.join(D, "raw"), os.path.join(D, "out")
def save(im, name, q=92):
    im.convert("RGB").save(os.path.join(O, name), "JPEG", quality=q)
# плитка пола
c = Image.open(os.path.join(R, "grey_tiles_color.jpg")).convert("RGB")
g = ImageOps.grayscale(c)
a = np.asarray(g).astype(np.float32)
a = 168 + (a - a.mean()) * 1.25  # светлее, середина ~168, швы контрастнее (цвет детали добавит оттенок)
# швы между плитками: где карта нормалей сильно отклоняется, — затемняем (затирка видна)
nm = np.asarray(Image.open(os.path.join(R, "grey_tiles_normal.jpg")).convert("RGB")).astype(np.float32) / 255 - 0.5
dev = np.sqrt(nm[..., 0] ** 2 + nm[..., 1] ** 2)
dev = np.asarray(Image.fromarray((dev * 255 * 3).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0))).astype(np.float32) / 255
a = a * (1 - 0.45 * np.clip((dev - 0.25) * 2.5, 0, 1))
rgb = np.stack([a * 1.0, a * 1.01, a * 1.02], -1).clip(0, 255).astype(np.uint8)
save(Image.fromarray(rgb), "floor_color.jpg")
for k in ("normal", "rough"):
    save(Image.open(os.path.join(R, f"grey_tiles_{k}.jpg")), f"floor_{k}.jpg")
# шероховатость плитки чуть ниже (полированная плитка блестит под лампами)
r = np.asarray(Image.open(os.path.join(R, "grey_tiles_rough.jpg")).convert("L")).astype(np.float32)
save(Image.fromarray((r * 0.75).clip(0, 255).astype(np.uint8)), "floor_rough.jpg")
# остальные: яркость и насыщенность подгоняем, чтобы цвет детали задавал оттенок (карта умножается на цвет)
def norm(img, mean, sat):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    grey = a.mean(-1, keepdims=True)
    a = grey + (a - grey) * sat
    a = a * (mean / max(1, a.mean()))
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))
LOOK = {"plaster": (200, 0.6), "block": (178, 0.25), "concrete": (150, 0.5), "asphalt": (95, 0.6), "brick": (150, 1.0), "pavers": (135, 0.55)}
for src, dst in (("painted_plaster_wall", "plaster"), ("concrete_block_wall", "block"), ("concrete_floor_worn_001", "concrete"),
                 ("asphalt_02", "asphalt"), ("brick_wall_02", "brick"), ("concrete_pavers", "pavers")):
    save(norm(Image.open(os.path.join(R, f"{src}_color.jpg")), *LOOK[dst]), f"{dst}_color.jpg")
    for k in ("normal", "rough"):
        save(Image.open(os.path.join(R, f"{src}_{k}.jpg")), f"{dst}_{k}.jpg")
# потолок: 2×2 плиты на текстуру, профиль T-bar по краям, мелкие отверстия и «трещинки»
N = 1024
rng = np.random.default_rng(7)
h = np.zeros((N, N), np.float32)
noise = rng.normal(0, 1, (N, N)).astype(np.float32)
noise = np.asarray(Image.fromarray(((noise * 20) + 128).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32) / 255 - 0.5
h += noise * 0.6
# проколы (точки) и короткие «червячки» — как у минераловатных плит
for _ in range(9000):
    x, y = rng.integers(0, N, 2)
    h[max(0, y - 1):y + 2, max(0, x - 1):x + 2] -= 0.9
for _ in range(1400):
    x, y = rng.integers(0, N, 2)
    ang = rng.uniform(0, np.pi); L = rng.integers(4, 11)
    for t in range(L):
        xx = int(x + np.cos(ang) * t) % N; yy = int(y + np.sin(ang) * t) % N
        h[yy, xx] -= 0.7
# профиль между плитами: полоса 14 px, слегка выступает, плита у края утоплена
bar = 14
mask = np.zeros((N, N), bool)
for k in (0, N // 2):
    mask[:, max(0, k - bar // 2):k + bar // 2] = True
    mask[max(0, k - bar // 2):k + bar // 2, :] = True
mask[:, N - bar // 2:] = True; mask[N - bar // 2:, :] = True
h[mask] = 1.2
edge = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9))).astype(bool) & ~mask
h[edge] -= 0.4
hs = np.asarray(Image.fromarray(((h + 2) * 50).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8))).astype(np.float32) / 50 - 2
gy, gx = np.gradient(hs)
nx, ny, nz = -gx * 2.2, gy * 2.2, np.ones_like(hs)
ln = np.sqrt(nx * nx + ny * ny + nz * nz)
nrm = np.stack([(nx / ln + 1) * 127.5, (ny / ln + 1) * 127.5, (nz / ln + 1) * 127.5], -1).clip(0, 255).astype(np.uint8)
save(Image.fromarray(nrm), "ceiling_normal.jpg")
col = np.full((N, N, 3), 232, np.float32) + noise[..., None] * 14
col[mask] = [214, 216, 218]
col[h < -0.5] -= 40
save(Image.fromarray(col.clip(0, 255).astype(np.uint8)), "ceiling_color.jpg")
rough = np.full((N, N), 235, np.float32); rough[mask] = 120
save(Image.fromarray(rough.astype(np.uint8)), "ceiling_rough.jpg")
print(sorted(os.listdir(O)))
