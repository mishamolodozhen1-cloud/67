# -*- coding: utf-8 -*-
"""Режиссёрский слой: реплики (озвучка + субтитры + липсинк), SFX, музыка, заметки сценария."""
import json, os, subprocess, functools
import numpy as np
from core import *
from film import Shot, Timeline
import lines as LN

VOICE_DIR = os.path.join(ROOT, 'build', 'voice')
SR = 48000

@functools.lru_cache(None)
def voice_info(lid):
    path = os.path.join(VOICE_DIR, lid + '.wav')
    if not os.path.exists(path):
        # озвучки ещё нет: оценка длительности по тексту (для черновой сборки)
        n = len(LN.clean(LN.L[lid][1]))
        return dict(path=None, dur=max(0.8, n / 13.0), env=None)
    raw = subprocess.run(['ffmpeg', '-v', 'quiet', '-i', path, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    x = np.frombuffer(raw, np.float32)
    hop = SR // 60
    n = len(x) // hop
    rms = np.sqrt((x[:n * hop].reshape(n, hop) ** 2).mean(1) + 1e-12)
    ref = np.percentile(rms, 92) + 1e-6
    env = np.clip(rms / ref, 0, 1.2)
    # сглаживание и «слоговая» модуляция
    k = np.array([0.25, 0.5, 0.25])
    env = np.convolve(env, k, 'same')
    return dict(path=path, dur=len(x) / SR, env=env)

def envelope_fn(lid):
    info = voice_info(lid)
    env = info['env']
    dur = info['dur']
    if env is None:
        def f(t):
            if t < 0 or t > dur:
                return 0.0
            return 0.55 + 0.45 * math.sin(t * 17) * math.sin(t * 5.3)
        return f
    def f(t):
        i = t * 60
        if i < 0 or i >= len(env) - 1:
            return 0.0
        k = int(i); u = i - k
        return float(env[k] * (1 - u) + env[k + 1] * u)
    return f

class Beat:
    """Курсор времени внутри шота. Все времена — локальные для шота."""
    def __init__(self, shot, t=0.0):
        self.shot = shot
        self.t = t

    def wait(self, d):
        self.t += d
        return self

    EXTRA_GAP = 0.3

    def say(self, actor, lid, gap=0.35, lead=0.0, style=None, fx=None, gain=1.0, talk=True, pan=0.0):
        """Реплика: звук + субтитр + липсинк персонажа. Возвращает (t0, t1)."""
        info = voice_info(lid)
        t0 = self.t + lead
        dur = info['dur']
        who = LN.speaker(lid)
        if style is None:
            style = 'vo' if actor is None else 'normal'
        self.shot.audio.append(dict(kind='voice', lid=lid, t=t0, gain=gain, fx=fx, pan=pan))
        self.shot.subs.append((t0, t0 + dur + 0.25, who, LN.clean(LN.L[lid][1]), style))
        if actor is not None and talk:
            actor.talk(t0, envelope_fn(lid), dur)
        self.t = t0 + dur + gap + Beat.EXTRA_GAP
        return (t0, t0 + dur)

    def sfx(self, name, dt=0.0, gain=1.0, **kw):
        self.shot.audio.append(dict(kind='sfx', name=name, t=self.t + dt, gain=gain, **kw))
        return self

def sfx(shot, name, t, gain=1.0, **kw):
    shot.audio.append(dict(kind='sfx', name=name, t=t, gain=gain, **kw))

def note(shot, t, text):
    shot.notes.append((t, text))

def patch_shot_class():
    # Расширяем Shot списками звука/субтитров/заметок
    orig_init = Shot.__init__
    def __init__(self, *a, **k):
        orig_init(self, *a, **k)
        self.audio = []
        self.subs = []
        self.notes = []
    Shot.__init__ = __init__
patch_shot_class()

class Episode(Timeline):
    def __init__(self):
        super().__init__()
        self.music = []      # dict(file, t0, t1, gain, fade_in, fade_out, loop, offset)
        self.scenes = []     # dict(id, title, place, t0, t1, desc)
        self._scene = None

    def scene(self, sid, title, place, desc=''):
        if self._scene is not None and self._scene['id'] == sid:
            # продолжение уже открытой сцены (установочный план + сама сцена)
            self._scene.update(title=title, place=place, desc=desc or self._scene['desc'])
            return self._scene
        if self._scene is not None:
            self._scene['t1'] = self.t
        self._scene = dict(id=sid, title=title, place=place, t0=self.t, t1=None, desc=desc, shots=[])
        self.scenes.append(self._scene)
        return self._scene

    def end_scenes(self):
        if self._scene is not None:
            self._scene['t1'] = self.t

    def append(self, shot):
        super().append(shot)
        for ev in shot.audio:
            e = dict(ev); e['t'] = ev['t'] + shot.start
            e['shot_end'] = shot.start + shot.dur
            self.audio.append(e)
        if getattr(shot, 'muffle', None):
            a, b_ = shot.muffle
            tm = getattr(shot, 'timemap', None)
            self.muffles = getattr(self, 'muffles', []) + [(shot.start + a, shot.start + b_)]
        for (a, b, who, txt, st) in shot.subs:
            self.subs.append((a + shot.start, b + shot.start, who, txt, st))
        for (t, txt) in shot.notes:
            self.notes.append((t + shot.start, self._scene['id'] if self._scene else '', txt))
        if self._scene is not None:
            self._scene['shots'].append(shot)
        return shot

    def cue(self, file, t0, t1, gain=0.5, fade_in=1.0, fade_out=1.5, loop=True, offset=0.0, duck=True):
        self.music.append(dict(file=file, t0=t0, t1=t1, gain=gain, fade_in=fade_in, fade_out=fade_out, loop=loop,
                               offset=offset, duck=duck))
