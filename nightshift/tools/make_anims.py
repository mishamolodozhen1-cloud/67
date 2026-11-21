#!/usr/bin/env python3
"""Собственные анимации персонажей NIGHT SHIFT (R15): ходьба, бег и ожидание.

Кадры считаются формулами (цикл шага), а не берутся у Roblox. Результат — файлы .rbxm
с KeyframeSequence в build/anims/, их загружают в Roblox как ассет типа Animation.

Как устроен шаг (t — доля цикла 0..1, левая нога впереди при t = 0.25):
  • бедро качается по синусу, колено сгибается, пока нога идёт вперёд (фаза переноса),
    стопа приподнимает носок в переносе и отталкивается в конце опоры;
  • руки идут навстречу ногам, локти чуть согнуты (сильнее, когда рука впереди);
  • таз два раза за цикл опускается и поднимается, слегка поворачивается и кренится,
    грудь поворачивается навстречу тазу, голова держит взгляд ровно.
  • вес и инерция (v4): руки и особенно кисти чуть запаздывают за ногами (follow-through),
    грудь поворачивается с небольшой задержкой после таза, таз переносит вес вперёд-назад,
    голова слегка кивает против подъёма корпуса.

Звуковые метки (KeyframeMarker): в ходьбе и беге метка «Step» стоит в момент касания пяткой
(значение L или R — какая нога), игра по ней проигрывает шаг под этой ступнёй. В действиях
покупателей метки отмечают момент звука: Beep — товар над сканером, Bag — товар в пакете,
Grab — взял с полки, Rustle — спрятал под куртку, Tap — карта к терминалу, Take — взял коробку.

Действия (v5, не зациклены, кроме сканирования): Scan, Reach, Conceal, Pay, Take, LookAround, HandsUp.

Запуск: python3 tools/make_anims.py  ->  build/anims/*.rbxm
"""
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import build  # noqa: E402  (бинарный писатель .rbxl/.rbxm)

Inst = build.Inst
OUT = os.path.join(ROOT, "build", "anims")

# Иерархия суставов R15: имя детали -> дочерние детали
TREE = {
    "HumanoidRootPart": ["LowerTorso"],
    "LowerTorso": ["UpperTorso", "LeftUpperLeg", "RightUpperLeg"],
    "UpperTorso": ["Head", "LeftUpperArm", "RightUpperArm"],
    "LeftUpperArm": ["LeftLowerArm"],
    "LeftLowerArm": ["LeftHand"],
    "RightUpperArm": ["RightLowerArm"],
    "RightLowerArm": ["RightHand"],
    "LeftUpperLeg": ["LeftLowerLeg"],
    "LeftLowerLeg": ["LeftFoot"],
    "RightUpperLeg": ["RightLowerLeg"],
    "RightLowerLeg": ["RightFoot"],
    "Head": [],
    "LeftHand": [],
    "RightHand": [],
    "LeftFoot": [],
    "RightFoot": [],
}


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot(rx=0.0, ry=0.0, rz=0.0):
    """Поворот как CFrame.Angles(rx, ry, rz) в Roblox (X, затем Y, затем Z)."""
    cx, sx = math.cos(rx), math.sin(rx)
    cy, sy = math.cos(ry), math.sin(ry)
    cz, sz = math.cos(rz), math.sin(rz)
    rxm = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rym = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rzm = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    return matmul(matmul(rxm, rym), rzm)


def cframe(pos=(0, 0, 0), rx=0.0, ry=0.0, rz=0.0):
    r = rot(rx, ry, rz)
    return (pos[0], pos[1], pos[2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2])


def pose_tree(name, joints):
    """joints: имя детали -> (pos, rx, ry, rz). Возвращает Pose со всеми дочерними."""
    pos, rx, ry, rz = joints.get(name, ((0, 0, 0), 0, 0, 0))
    p = Inst("Pose", name, [
        ("CFrame", "CFrame", cframe(pos, rx, ry, rz)),
        ("float", "Weight", 1.0),
        ("token", "EasingStyle", 0),  # Linear: кадры частые, между ними — прямая интерполяция
        ("token", "EasingDirection", 0),
    ])
    for child in TREE[name]:
        p.add(pose_tree(child, joints))
    return p


def sequence(name, length, frames, sample, priority, loop=True, markers=None):
    """markers: список (доля цикла 0..1, имя, значение) — метка ставится на ближайший кадр."""
    kfs = Inst("KeyframeSequence", name, [("bool", "Loop", loop), ("token", "Priority", priority)])
    marks = {}
    for (u, mname, value) in (markers or []):
        marks.setdefault(int(round(u * frames)), []).append((mname, value))
    for i in range(frames + 1):
        t = i / frames
        kf = Inst("Keyframe", "Keyframe", [("float", "Time", round(t * length, 4))])
        kf.add(pose_tree("HumanoidRootPart", sample(t)))
        for (mname, value) in marks.get(i, []):
            kf.add(Inst("KeyframeMarker", mname, [("string", "Value", value)]))
        kfs.add(kf)
    return kfs


def smooth(x):
    x = max(0.0, min(1.0, x))
    return x * x * (3 - 2 * x)


def keyed(keys):
    """keys: [(t, value)] по возрастанию t -> функция плавной интерполяции значения во времени."""
    def f(t):
        if t <= keys[0][0]:
            return keys[0][1]
        for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
            if t <= t1:
                k = smooth((t - t0) / (t1 - t0)) if t1 > t0 else 1
                return v0 + (v1 - v0) * k
        return keys[-1][1]
    return f


def action(channels):
    """channels: {(сустав, ось): [(t, значение)]} поверх стойки ожидания (ноги и дыхание из idle)."""
    curves = {k: keyed(v) for k, v in channels.items()}

    def sample(t):
        base = idle_sample(t * 0.5)
        j = {}
        for name, (pos, rx, ry, rz) in base.items():
            vals = {"x": rx, "y": ry, "z": rz}
            for axis in ("x", "y", "z"):
                c = curves.get((name, axis))
                if c is not None:
                    vals[axis] = c(t)
            j[name] = (pos, vals["x"], vals["y"], vals["z"])
        return j
    return sample


# Покупатель на кассе самообслуживания: взял товар из корзины слева, провёл над сканером, положил в пакет справа
SCAN = action({
    ("RightUpperArm", "x"): [(0, 0.15), (0.2, 0.55), (0.42, 1.0), (0.62, 0.85), (0.82, 0.25), (1, 0.15)],
    ("RightUpperArm", "z"): [(0, -0.05), (0.2, 0.35), (0.42, 0.05), (0.62, -0.45), (0.82, -0.1), (1, -0.05)],
    ("RightLowerArm", "x"): [(0, 0.2), (0.2, 0.7), (0.42, 0.95), (0.62, 0.55), (0.82, 0.3), (1, 0.2)],
    ("RightHand", "x"): [(0, 0.05), (0.42, -0.25), (0.62, 0.1), (1, 0.05)],
    ("UpperTorso", "y"): [(0, 0), (0.2, 0.22), (0.42, 0.0), (0.62, -0.22), (0.82, -0.05), (1, 0)],
    ("UpperTorso", "x"): [(0, -0.03), (0.2, -0.12), (0.42, -0.06), (0.62, -0.1), (1, -0.03)],
    ("Head", "x"): [(0, 0.05), (0.42, 0.25), (0.62, 0.18), (1, 0.05)],
    ("LeftUpperArm", "x"): [(0, 0.1), (0.42, 0.35), (1, 0.1)],
    ("LeftLowerArm", "x"): [(0, 0.2), (0.42, 0.6), (1, 0.2)],
})

# Взять товар с полки на уровне груди
REACH = action({
    ("RightUpperArm", "x"): [(0, 0.05), (0.35, 1.35), (0.5, 1.35), (0.75, 0.7), (1, 0.05)],
    ("RightUpperArm", "z"): [(0, -0.06), (0.35, 0.05), (0.75, 0.15), (1, -0.06)],
    ("RightLowerArm", "x"): [(0, 0.15), (0.35, 0.15), (0.5, 0.35), (0.75, 1.3), (1, 0.15)],
    ("RightHand", "x"): [(0, 0.05), (0.4, -0.3), (0.55, 0.3), (1, 0.05)],
    ("UpperTorso", "x"): [(0, -0.02), (0.35, -0.12), (0.75, -0.04), (1, -0.02)],
    ("Head", "x"): [(0, 0.03), (0.3, -0.15), (0.7, 0.1), (1, 0.03)],
})

# Вор прячет товар: оглядывается, рука под куртку, плечи сжимаются
CONCEAL = action({
    ("Head", "y"): [(0, 0), (0.12, 0.55), (0.28, -0.5), (0.42, 0.0), (0.85, 0.3), (1, 0)],
    ("UpperTorso", "y"): [(0, 0), (0.12, 0.15), (0.28, -0.15), (0.42, 0), (1, 0)],
    ("UpperTorso", "x"): [(0, -0.02), (0.45, -0.16), (0.8, -0.14), (1, -0.02)],
    ("RightUpperArm", "x"): [(0, 0.05), (0.45, 0.35), (0.55, 0.55), (0.8, 0.55), (1, 0.05)],
    ("RightUpperArm", "z"): [(0, -0.06), (0.45, 0.45), (0.55, 0.7), (0.8, 0.65), (1, -0.06)],
    ("RightLowerArm", "x"): [(0, 0.15), (0.45, 1.3), (0.55, 1.75), (0.8, 1.7), (1, 0.15)],
    ("LeftUpperArm", "x"): [(0, 0.05), (0.5, 0.25), (0.8, 0.25), (1, 0.05)],
    ("LeftLowerArm", "x"): [(0, 0.15), (0.5, 0.9), (0.8, 0.9), (1, 0.15)],
})

# Приложить карту к терминалу
PAY = action({
    ("RightUpperArm", "x"): [(0, 0.1), (0.35, 0.95), (0.6, 0.95), (1, 0.1)],
    ("RightUpperArm", "z"): [(0, -0.05), (0.35, 0.12), (1, -0.05)],
    ("RightLowerArm", "x"): [(0, 0.2), (0.35, 0.45), (0.6, 0.55), (1, 0.2)],
    ("RightHand", "x"): [(0, 0.05), (0.35, -0.35), (0.6, -0.35), (1, 0.05)],
    ("Head", "x"): [(0, 0.04), (0.35, 0.22), (0.7, 0.2), (1, 0.04)],
})

# Взять коробку (заказ) двумя руками
TAKE = action({
    ("RightUpperArm", "x"): [(0, 0.1), (0.4, 1.05), (0.6, 1.0), (1, 0.75)],
    ("LeftUpperArm", "x"): [(0, 0.1), (0.4, 1.05), (0.6, 1.0), (1, 0.75)],
    ("RightUpperArm", "z"): [(0, -0.05), (0.4, 0.2), (1, 0.25)],
    ("LeftUpperArm", "z"): [(0, 0.05), (0.4, -0.2), (1, -0.25)],
    ("RightLowerArm", "x"): [(0, 0.2), (0.4, 0.35), (0.6, 0.6), (1, 0.9)],
    ("LeftLowerArm", "x"): [(0, 0.2), (0.4, 0.35), (0.6, 0.6), (1, 0.9)],
    ("UpperTorso", "x"): [(0, -0.02), (0.4, -0.1), (1, -0.04)],
})

# Оглядеться по сторонам
LOOK = action({
    ("Head", "y"): [(0, 0), (0.25, 0.7), (0.45, 0.65), (0.7, -0.7), (0.85, -0.6), (1, 0)],
    ("UpperTorso", "y"): [(0, 0), (0.25, 0.2), (0.7, -0.2), (1, 0)],
    ("Head", "x"): [(0, 0.03), (0.25, -0.05), (0.7, 0.08), (1, 0.03)],
})

# Пойманный вор: руки вверх
HANDS_UP = action({
    ("RightUpperArm", "x"): [(0, 0.1), (0.3, 2.6), (1, 2.5)],
    ("LeftUpperArm", "x"): [(0, 0.1), (0.3, 2.6), (1, 2.5)],
    ("RightUpperArm", "z"): [(0, -0.05), (0.3, -0.35), (1, -0.35)],
    ("LeftUpperArm", "z"): [(0, 0.05), (0.3, 0.35), (1, 0.35)],
    ("RightLowerArm", "x"): [(0, 0.2), (0.3, 1.3), (1, 1.2)],
    ("LeftLowerArm", "x"): [(0, 0.2), (0.3, 1.3), (1, 1.2)],
    ("Head", "x"): [(0, 0.03), (0.3, 0.2), (1, 0.15)],
})


def pos_part(x):
    return max(0.0, x)


def gait(hip, knee, knee_stance, ankle_up, ankle_push, arm, elbow, elbow_swing, lean, bob, twist, sway, head_hold):
    """Возвращает функцию t -> позы суставов для шага с заданными амплитудами (радианы, studs)."""

    def sample(t):
        w = 2 * math.pi * t
        j = {}
        for side, ph in (("Left", 0.0), ("Right", math.pi)):
            s = math.sin(w + ph)          # >0 — нога впереди
            c = math.cos(w + ph)          # >0 — нога идёт вперёд (перенос)
            swing = pos_part(c)
            stance = pos_part(-c)
            # бедро: вперёд-назад; колено: сгиб в переносе и немного при постановке на пятку
            j[side + "UpperLeg"] = ((0, 0, 0), hip * s, 0, 0)
            j[side + "LowerLeg"] = ((0, 0, 0), -(knee * swing ** 1.3 + knee_stance * pos_part(s) * stance), 0, 0)
            # стопа: носок вверх в переносе, толчок носком в конце опоры
            j[side + "Foot"] = ((0, 0, 0), ankle_up * swing - ankle_push * pos_part(-s) * stance, 0, 0)
            # рука навстречу ноге той же стороны, с небольшим запаздыванием; кисть запаздывает сильнее
            sa = math.sin(w + ph - 0.22)
            a = -arm * sa
            j[side + "UpperArm"] = ((0, 0, 0), a, 0, (0.06 if side == "Left" else -0.06))
            j[side + "LowerArm"] = ((0, 0, 0), elbow + elbow_swing * pos_part(-math.sin(w + ph - 0.4)), 0, 0)
            j[side + "Hand"] = ((0, 0, 0), 0.05 + 0.08 * arm * math.sin(w + ph - 0.9), 0, 0)
        # таз: два подъёма за цикл (выше всего, когда ноги проходят друг мимо друга), поворот и крен
        y = bob * math.cos(2 * w)
        shift = bob * 0.25 * math.sin(2 * w)  # перенос веса вперёд-назад
        j["LowerTorso"] = ((0, y, shift), 0, -twist * math.sin(w), sway * math.sin(w))
        # грудь: наклон вперёд, поворот навстречу тазу (чуть позже таза — инерция корпуса)
        lag = math.sin(w - 0.3)
        j["UpperTorso"] = ((0, 0, 0), -lean - bob * 0.25 * math.cos(2 * w - 0.5), twist * 1.6 * lag, -sway * 0.6 * lag)
        # голова гасит повороты и наклон, слегка кивает против подъёма корпуса
        j["Head"] = ((0, 0, 0), lean * head_hold + bob * 0.35 * math.cos(2 * w - 0.9), -twist * 0.6 * lag, 0)
        return j

    return sample


def idle_sample(t):
    w = 2 * math.pi * t
    breath = math.sin(w)            # один вдох за цикл
    shift = math.sin(w + 0.7)       # переступает с ноги на ногу
    j = {
        "LowerTorso": ((0.03 * shift, -0.02 + 0.015 * breath, 0), 0, 0.02 * shift, 0.015 * shift),
        "UpperTorso": ((0, 0, 0), -0.02 + 0.012 * breath, -0.02 * shift, -0.01 * shift),
        "Head": ((0, 0, 0), 0.03 - 0.01 * breath, 0.04 * math.sin(w * 0.5 + 1.0), 0),
        "LeftUpperArm": ((0, 0, 0), 0.03 + 0.015 * breath, 0, 0.07),
        "RightUpperArm": ((0, 0, 0), 0.03 + 0.015 * breath, 0, -0.07),
        "LeftLowerArm": ((0, 0, 0), 0.16, 0, 0),
        "RightLowerArm": ((0, 0, 0), 0.18, 0, 0),
        "LeftHand": ((0, 0, 0), 0.08, 0, 0),
        "RightHand": ((0, 0, 0), 0.08, 0, 0),
        "LeftUpperLeg": ((0, 0, 0), 0.02, 0, -0.015 * shift),
        "RightUpperLeg": ((0, 0, 0), 0.02, 0, -0.015 * shift),
        "LeftLowerLeg": ((0, 0, 0), -0.04 - 0.03 * max(0, -shift), 0, 0),
        "RightLowerLeg": ((0, 0, 0), -0.04 - 0.03 * max(0, shift), 0, 0),
        "LeftFoot": ((0, 0, 0), 0.02, 0, 0),
        "RightFoot": ((0, 0, 0), 0.02, 0, 0),
    }
    return j


# Длина цикла и «родная» скорость (studs/с при росте 1): скрипт анимации подстраивает темп под скорость
ANIMS = {
    # спокойный шаг: длинные медленные шаги, взгляд ровно
    "walk": dict(length=0.84, natural=9.0, priority=1, sample=gait(
        hip=0.52, knee=0.95, knee_stance=0.18, ankle_up=0.3, ankle_push=0.42,
        arm=0.34, elbow=0.22, elbow_swing=0.3, lean=0.05, bob=0.07, twist=0.07, sway=0.035, head_hold=0.8)),
    # бег: корпус вперёд, высокие колени, руки согнуты
    "run": dict(length=0.6, natural=17.0, priority=1, sample=gait(
        hip=0.85, knee=1.55, knee_stance=0.35, ankle_up=0.35, ankle_push=0.6,
        arm=0.75, elbow=1.25, elbow_swing=0.25, lean=0.2, bob=0.16, twist=0.1, sway=0.03, head_hold=0.9)),
    # ожидание: дыхание и лёгкое переступание
    "idle": dict(length=4.0, natural=0, priority=0, sample=idle_sample),
    # действия покупателей (приоритет Action = 2)
    "scan": dict(length=1.7, natural=0, priority=2, sample=SCAN, loop=True,
                 markers=[(0.5, "Beep", ""), (0.74, "Bag", "")]),
    "reach": dict(length=1.8, natural=0, priority=2, sample=REACH, loop=False, markers=[(0.45, "Grab", "")]),
    "conceal": dict(length=2.4, natural=0, priority=2, sample=CONCEAL, loop=False, markers=[(0.55, "Rustle", "")]),
    "pay": dict(length=1.3, natural=0, priority=2, sample=PAY, loop=False, markers=[(0.45, "Tap", "")]),
    "take": dict(length=1.4, natural=0, priority=2, sample=TAKE, loop=False, markers=[(0.45, "Take", "")]),
    "look": dict(length=3.2, natural=0, priority=2, sample=LOOK, loop=False),
    "handsup": dict(length=1.2, natural=0, priority=2, sample=HANDS_UP, loop=False),
}

# Метки шагов: левая пятка касается пола при t = 0.25, правая при 0.75
STEP_MARKERS = [(0.25, "Step", "L"), (0.75, "Step", "R")]
ANIMS["walk"]["markers"] = STEP_MARKERS
ANIMS["run"]["markers"] = STEP_MARKERS


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, a in ANIMS.items():
        frames = 24 if name in ("walk", "run") else (16 if name == "idle" else 30)
        seq = sequence("NS_" + name.capitalize(), a["length"], frames, a["sample"], a["priority"],
                       a.get("loop", True), a.get("markers"))
        data = build.write_binary([seq])
        path = os.path.join(OUT, name + ".rbxm")
        with open(path, "wb") as f:
            f.write(data)
        print(f"{path}: {len(data)} байт, цикл {a['length']} с, скорость {a['natural']}")


if __name__ == "__main__":
    main()
