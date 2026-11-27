#!/usr/bin/env python3
"""Раскадровка анимаций манекена: build/anims/preview_move.png (походки) и preview_poses.png (стойки, прыжок,
лазание). Пол — y = 0: видно, касаются ли стопы пола и не проваливаются ли.

Запуск: python3 tools/dummy/preview_anims.py
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_anims as A  # noqa: E402
import make_dummy as D  # noqa: E402
import render  # noqa: E402
import rig  # noqa: E402

OUT = os.path.join(A.ROOT, "build", "anims")

MOVE = [("WalkF", "сбоку"), ("WalkR", "спереди"), ("RunF", "сбоку"), ("CrouchF", "сбоку"), ("CrouchR", "спереди")]
POSES = [("Idle", "три четверти"), ("CrouchIdle", "сбоку"), ("Jump", "сбоку"), ("Fall", "три четверти"), ("Land", "сбоку"), ("Climb", "сбоку")]
EYES = {"сбоку": (10.5, 3.0, 0.0), "спереди": (0.0, 3.0, -10.5), "три четверти": (-6.5, 4.0, -8.0)}


def strip(parts, info, name, view, frames):
    fn = A.ANIMS[name][0]
    loop = A.ANIMS[name][2]
    root = (0, -A.CROUCH_DROP, 0) if name in A.CROUCHED else (0, 0, 0)
    floor = render.ground(3, 0.5)
    imgs = []
    for i in range(frames):
        t = i / frames if loop else i / (frames - 1)
        items = D.posed_items(parts, info, fn(t), root) + [floor]
        im = render.render(items, EYES[view], (0, 2.5, 0), fov=34, W=230, H=330)
        imgs.append(render.label(im, f"{name} {t:.2f}" if i else f"{name} ({view})"))
    return imgs


def main():
    parts = rig.build_parts()
    info, _ = rig.spec(parts)
    for fname, group, frames in (("preview_move.png", MOVE, 6), ("preview_poses.png", POSES, 5)):
        imgs = []
        for name, view in group:
            imgs += strip(parts, info, name, view, frames)
        render.sheet(imgs, frames).save(os.path.join(OUT, fname))
        print(os.path.join(OUT, fname))


if __name__ == "__main__":
    main()
