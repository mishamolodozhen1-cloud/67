# -*- coding: utf-8 -*-
"""Общие помощники постановки."""
from core import *
from film import Shot
from director import Beat, sfx, note, voice_info
from stickman import Actor, SPECS
from sets import Layer
import fx as FX

def HY(who, scale=1.0):
    """Высота центра головы персонажа над землёй (мировые единицы, со знаком «вверх»)."""
    return -0.965 * SPECS.get(who, SPECS['EXTRA']).get('scale', 1.0) * scale

def mk(tod, layers, **kw):
    return Shot(0.0, tod, list(layers), **kw)

def C(keys, ease='io'):
    return cam_track(keys, ease)

def done(ep, sh, b, tail=0.4, cam=None, min_dur=0.0):
    sh.dur = max(b.t + tail, min_dur) if b is not None else max(tail, min_dur)
    if cam is not None:
        sh.cam = cam(sh.dur) if getattr(cam, 'is_factory', False) else cam
    ep.append(sh)
    return sh

def drift(x0, y0, z0, x1, y1, z1, roll0=0.0, roll1=0.0, ap=0.0, focus=0.0, ease='io'):
    """Камера, плавно дрейфующая за длительность шота (функция от dur)."""
    def make(dur):
        return cam_track([(0.0, dict(x=x0, y=y0, zoom=z0, roll=roll0, aperture=ap, focus=focus)),
                          (dur, dict(x=x1, y=y1, zoom=z1, roll=roll1, aperture=ap, focus=focus, ))], ease)
    make.is_factory = True
    return make

def screen(sh, fn):
    sh.screen_fx.append(fn)

def world(sh, z, fn, name='fx'):
    sh.world_fx.append(Layer(z, fn, name=name))

def card(sh, t0, name, line2, color, dur=3.0, side='right'):
    screen(sh, lambda cv, t: FX.name_card(cv, t - t0, name, line2, color, dur, side))

def sfxt(sh, t0, txt, x, y, size=120, color=None, rot=-8, dur=1.0, **kw):
    screen(sh, lambda cv, t: FX.sfx_text(cv, txt, x, y, size, t - t0, color=color, rot=rot, dur=dur, **kw))

def freeze(sh, t0, t1):
    """Стоп-кадр мира между t0 и t1 (экранные эффекты продолжают жить)."""
    sh.freeze = (t0, t1)

def mblur(sh, t0, t1, n=5):
    """Включить motion blur (n подкадров) в окне локального времени шота."""
    sh.mblur_ranges.append((t0, t1, n))

def follow(actors, y, z0, z1, ap=0.5, tau=0.9, dx=0.0, roll=0.8, focus=0.0):
    """Камера-«оператор»: плавно ведёт к говорящему (зум z1) и к группе в паузах (зум z0).
    Возвращает фабрику камеры (вызывается с длительностью шота)."""
    import numpy as np
    def make(dur):
        n = int(dur * 30) + 3
        xs = np.zeros(n); zs = np.zeros(n)
        for i in range(n):
            t = i / 30.0
            spk = [a for a in actors if any(t0 - 0.2 <= t <= t0 + d for (t0, env, d) in a.talks)]
            grp = spk if spk else actors
            xs[i] = sum(a.x_at(t) for a in grp) / len(grp) + dx
            zs[i] = z1 if spk else z0
        # двусторонний экспоненциальный фильтр (без запаздывания)
        k = 1.0 - math.exp(-1.0 / (30.0 * tau))
        def smooth2(v):
            f = v.copy()
            for i in range(1, n):
                f[i] = f[i - 1] + k * (f[i] - f[i - 1])
            for i in range(n - 2, -1, -1):
                f[i] = f[i + 1] + k * (f[i] - f[i + 1])
            return f
        xs2, zs2 = smooth2(xs), smooth2(smooth2(zs))
        def cam(t):
            i = t * 30.0
            j = int(min(max(i, 0), n - 2)); u = min(max(i - j, 0), 1)
            x = xs2[j] * (1 - u) + xs2[j + 1] * u
            z = zs2[j] * (1 - u) + zs2[j + 1] * u
            return Cam(x=x + math.sin(t * 0.21) * 0.04, y=y + math.sin(t * 0.17 + 1) * 0.015, zoom=z * (1 + 0.02 * math.sin(t * 0.13)),
                       roll=roll * math.sin(t * 0.11), aperture=ap, focus=focus)
        return cam
    make.is_factory = True
    return make

def mix_cam(a, b, u):
    c = Cam()
    for k in ('x', 'y', 'zoom', 'roll', 'D', 'focus', 'aperture', 'shake'):
        setattr(c, k, getattr(a, k) + (getattr(b, k) - getattr(a, k)) * u)
    return c
