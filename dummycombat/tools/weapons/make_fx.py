#!/usr/bin/env python3
"""Текстуры эффектов оружия (с прозрачностью) -> build/weapons/fx_*.png:
  fx_flash.png   вспышка выстрела: звезда из лучей с горячим центром (смотрит в камеру — частица)
  fx_flash_side.png  вспышка сбоку: язык пламени вдоль ствола (плоскость вдоль ствола)
  fx_hole.png    след от пули: тёмное отверстие, сколы и копоть по краю
Цвет вспышки — тёплый белый в центре, оранжевый к краям; в игре он ещё умножается на цвет частицы.
"""
import math
import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "weapons")
rng = np.random.default_rng(7)


def save(arr, name):
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))


def flash():
    n = 256
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.hypot(x, y)
    a = np.arctan2(y, x)
    rays = np.zeros_like(r)
    for k in range(5):
        ang = k * 2 * math.pi / 5 + rng.uniform(-0.25, 0.25)
        length = rng.uniform(0.6, 0.9)
        width = rng.uniform(0.28, 0.42)
        d = np.abs(np.angle(np.exp(1j * (a - ang))))
        rays = np.maximum(rays, np.clip(1 - d / width, 0, 1) ** 1.5 * np.clip(1 - r / length, 0, 1))
    core = np.clip(1 - r / 0.45, 0, 1) ** 0.9
    alpha = np.clip(core + rays * 0.85, 0, 1)
    heat = np.clip(core * 1.2 + rays * 0.4, 0, 1)
    rgb = np.stack([255 * np.ones_like(r), 150 + 100 * heat, 60 + 170 * heat ** 2], -1)
    save(np.concatenate([rgb, (alpha * 255)[..., None]], -1), "fx_flash.png")


def flash_side():
    w, h = 256, 128
    y, x = np.mgrid[0:h, 0:w]
    u = x / (w - 1)  # 0 — у дула, 1 — конец пламени
    v = (y / (h - 1)) * 2 - 1
    width = 0.75 * (1 - u) ** 0.6 * (0.6 + 0.4 * np.sin(u * 9 + rng.uniform(0, 6)))
    body = np.clip(1 - np.abs(v) / np.maximum(width, 1e-3), 0, 1) * np.clip(1 - u, 0, 1) ** 0.8
    alpha = np.clip(body * 1.3, 0, 1)
    heat = np.clip(body * (1 - u) * 1.6, 0, 1)
    rgb = np.stack([255 * np.ones_like(u), 140 + 110 * heat, 50 + 180 * heat ** 2], -1)
    save(np.concatenate([rgb, (alpha * 255)[..., None]], -1), "fx_flash_side.png")


def hole():
    n = 128
    y, x = np.mgrid[0:n, 0:n] / (n - 1) * 2 - 1
    r = np.hypot(x, y)
    a = np.arctan2(y, x)
    jag = 1 + 0.18 * np.sin(a * 7 + 1.3) + 0.1 * np.sin(a * 13 + 0.4)
    hole_a = np.clip((0.2 * jag - r) / 0.04, 0, 1)
    chips = np.clip((0.42 * jag - r) / 0.12, 0, 1) * (0.5 + 0.25 * np.sin(a * 11 + 0.7))
    soot = np.clip(1 - r / 0.95, 0, 1) ** 2 * 0.45
    alpha = np.clip(np.maximum.reduce([hole_a, chips * 0.8, soot]), 0, 1)
    shade = 18 + 40 * (1 - hole_a) * (r > 0.22)
    rgb = np.stack([shade, shade * 0.97, shade * 0.93], -1)
    save(np.concatenate([rgb, (alpha * 255)[..., None]], -1), "fx_hole.png")


def main():
    os.makedirs(OUT, exist_ok=True)
    flash()
    flash_side()
    hole()
    print("ok")


if __name__ == "__main__":
    main()
