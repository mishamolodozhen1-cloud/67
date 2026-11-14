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
