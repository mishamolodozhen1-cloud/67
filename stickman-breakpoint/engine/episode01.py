# -*- coding: utf-8 -*-
"""Сборка серии 1 «Обычный вторник»: порядок сцен и музыкальная раскладка."""
import os
from core import *
from director import Episode
import ep1_cold as A0
import ep1_a as A
import ep1_b as B
import ep1_extra as X

M = 'build/music/'

def build():
    ep = Episode()
    A0.cold_open(ep)
    t_title = ep.t
    A0.title_card(ep)
    t_op = ep.t
    A0.opening(ep)
    t_a = ep.t
    X.est_morning(ep)
    A.sc1_room(ep)
    A.sc2_kitchen(ep)
    A.sc3_street(ep)
    X.bus(ep)
    X.vertex_morning(ep)
    t_class = ep.t
    X.est_school(ep)
    A.sc4_class(ep)
    t_corr = ep.t
    X.sc45_corridor(ep)
    t_eye = ep.t
    A.eyecatch(ep)
    t_b = ep.t
    X.est_lunch(ep)
    B.sc5_roof(ep)
    t_gate = ep.t
    B.sc6_gate(ep)
    X.practice(ep)
    X.library(ep)
    t_stairs = ep.t
    X.est_evening(ep)
    B.sc7_stairs(ep)
    X.witness(ep)
    t_bridge = ep.t
    X.bridge_vo(ep)
    B.sc8_bridge(ep)
    t_dinner = ep.t
    X.est_home(ep)
    B.sc9_dinner(ep)
    t_lab = ep.t
    X.est_institute(ep)
    B.sc10_vertex(ep)
    X.sol_epilogue(ep)
    t_roof = ep.t
    B.sc11_rooftop(ep)
    t_night = ep.t
    B.sc12_night(ep)
    t_final = ep.shots[-1].start
    B.ending(ep)
    X.post_credits(ep)
    B.preview(ep)
    ep.end_scenes()

    # ── музыка (кроме опенинга/эндинга, которые ставятся в своих сценах) ──
    ep.music = [m for m in ep.music if m['file'].endswith(('op_theme.wav', 'ed_theme.wav'))]
    cue = ep.cue
    cue(M + 'bgm_mystery.wav', 0.0, t_title, gain=0.30, fade_in=3.0, fade_out=0.3)
    sc1 = next(s for s in ep.scenes if s['id'] == '1')
    r2 = sc1['shots'][1].start
    cue(M + 'bgm_daily.wav', r2 + 1.0, t_class - 0.5, gain=0.30, fade_in=2.0, fade_out=1.5)
    cue(M + 'bgm_school.wav', t_class + 1.0, t_corr + 1.0, gain=0.26, fade_in=2.0, fade_out=1.2)
    cue(M + 'bgm_mystery.wav', t_corr + 50.0, t_eye, gain=0.0, fade_in=2.0, fade_out=0.6)
    cue(M + 'bgm_lunch.wav', t_b + 0.3, t_gate, gain=0.27, fade_in=1.5, fade_out=1.5, duck_window=None)
    cue(M + 'bgm_walk.wav', t_gate, t_stairs + 6.0, gain=0.28, fade_in=1.5, fade_out=2.5)
    sc7 = next(s for s in ep.scenes if s['id'] == '7')
    g2 = sc7['shots'][1].start
    cut = getattr(ep, 'music_cut', g2 + 20)
    cue(M + 'bgm_tense.wav', g2, cut, gain=0.32, fade_in=2.0, fade_out=0.05)
    g7 = sc7['shots'][6].start
    cue(M + 'bgm_mystery.wav', g7 + 6.0, t_dinner, gain=0.26, fade_in=4.0, fade_out=2.0)
    cue(M + 'bgm_home.wav', t_dinner + 0.8, t_lab, gain=0.30, fade_in=2.5, fade_out=1.5)
    cue(M + 'bgm_mystery.wav', t_lab, t_night + 2.0, gain=0.32, fade_in=1.5, fade_out=3.0)
    cue(M + 'bgm_home.wav', t_night + 1.0, t_final + 0.5, gain=0.22, fade_in=3.0, fade_out=2.0)
    # эндинг: вступление начинается под финальный закадровый голос
    for m in ep.music:
        if m['file'].endswith('ed_theme.wav'):
            m['t0'] = t_final
            m['fade_in'] = 2.0
    ep.markers = dict(title=t_title, op=t_op, a=t_a, eyecatch=t_eye, b=t_b, final=t_final)
    return ep

def cue_patch():
    # допускаем лишние ключи в cue()
    from director import Episode as E
    orig = E.cue
    def cue(self, file, t0, t1, gain=0.5, fade_in=1.0, fade_out=1.5, loop=True, offset=0.0, duck=True, **kw):
        return orig(self, file, t0, t1, gain, fade_in, fade_out, loop, offset, duck)
    E.cue = cue
cue_patch()

if __name__ == '__main__':
    ep = build()
    print('duration %.1f s = %d:%04.1f' % (ep.duration, ep.duration // 60, ep.duration % 60))
    for s in ep.scenes:
        print('%-4s %-28s %7.1f → %7.1f  (%5.1f s, %d shots)' % (s['id'], s['title'], s['t0'], s['t1'], s['t1'] - s['t0'], len(s['shots'])))
    missing = [e for e in ep.audio if e['kind'] == 'voice' and not os.path.exists('build/voice/%s.wav' % e['lid'])]
    print('voice events', sum(1 for e in ep.audio if e['kind'] == 'voice'), 'missing', len(missing))
    names = sorted(set(e['name'] for e in ep.audio if e['kind'] == 'sfx'))
    print('sfx names', len(names), names)
