# -*- coding: utf-8 -*-
"""Рендер серии: параллельные процессы → сегменты H.264 → склейка → звук AAC.

python3 engine/render.py --scale 1.0 --fps 60 --out output/STICKMAN_BREAKPOINT_E01.mp4
python3 engine/render.py --scale 0.5 --fps 12 --out build/preview.mp4   (черновик)
python3 engine/render.py --frames 1200,1260 ...                           (кусок)
"""
import argparse, os, sys, time, subprocess, multiprocessing as mp, json, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
os.chdir(ROOT)

import core
from core import W, H

EP = None

def worker(args):
    idx, f0, f1, fps, scale, seg_path, crf, preset = args
    import gfx
    from film import render_frame
    core.BASE[0] = scale
    w, h = int(W * scale), int(H * scale)
    surf = gfx.Surface(w, h)
    if scale != 1.0:
        surf.ctx.scale(scale, scale)
    cv = surf.getCanvas()
    cmd = ['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'bgra', '-s', '%dx%d' % (w, h), '-r', str(fps),
           '-i', '-', '-an', '-c:v', 'libx264', '-preset', preset, '-crf', str(crf), '-pix_fmt', 'yuv420p',
           '-g', str(fps * 2), '-threads', '2', '-tune', 'animation', seg_path]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    t0 = time.time()
    import numpy as np
    for i in range(f0, f1):
        T = i / fps
        shot = EP.shot_at(T)
        tl = T - shot.start
        n = 1
        for (a, b, k) in getattr(shot, 'mblur_ranges', []):
            if a <= tl <= b:
                n = max(n, k)
        if n <= 1:
            cv.ctx.save()
            render_frame(cv, EP, T)
            cv.ctx.restore()
            surf.surf.flush()
            p.stdin.write(bytes(surf.surf.get_data()))
        else:
            # motion blur: усреднение подкадров в пределах затвора 180°
            acc = None
            for k in range(n):
                Tk = T + (k / (n - 1) - 0.5) * (0.5 / fps)
                Tk = min(max(Tk, shot.start), shot.start + shot.dur - 1e-4)
                cv.ctx.save()
                render_frame(cv, EP, Tk, subs=False)
                cv.ctx.restore()
                surf.surf.flush()
                a = np.frombuffer(surf.surf.get_data(), np.uint8).astype(np.uint16)
                acc = a if acc is None else acc + a
            out = (acc // n).astype(np.uint8)
            # субтитры поверх без размытия
            buf = surf.surf.get_data()
            np.frombuffer(buf, np.uint8)[:] = out
            surf.surf.mark_dirty()
            from film import draw_subs
            cv.ctx.save()
            draw_subs(cv, EP, T)
            cv.ctx.restore()
            surf.surf.flush()
            p.stdin.write(bytes(surf.surf.get_data()))
        if (i - f0) % 600 == 0:
            el = time.time() - t0
            print('[w%d] frame %d/%d  %.1f fps' % (idx, i - f0, f1 - f0, (i - f0 + 1) / max(el, 1e-3)), flush=True)
    p.stdin.close()
    p.wait()
    return seg_path, time.time() - t0

def main():
    global EP
    ap = argparse.ArgumentParser()
    ap.add_argument('--scale', type=float, default=1.0)
    ap.add_argument('--fps', type=int, default=60)
    ap.add_argument('--out', default='output/STICKMAN_BREAKPOINT_S01E01.mp4')
    ap.add_argument('--workers', type=int, default=4)
    ap.add_argument('--frames', default=None)
    ap.add_argument('--crf', type=int, default=21)
    ap.add_argument('--preset', default='medium')
    ap.add_argument('--noaudio', action='store_true')
    ap.add_argument('--segdir', default='build/segments')
    a = ap.parse_args()
    import episode01
    EP = episode01.build()
    dur = EP.duration
    N = int(round(dur * a.fps))
    f0, f1 = 0, N
    if a.frames:
        f0, f1 = [int(v) for v in a.frames.split(',')]
    print('duration %.2f s, frames %d..%d @ %d fps, scale %.2f' % (dur, f0, f1, a.fps, a.scale), flush=True)
    os.makedirs(a.segdir, exist_ok=True)
    # равномерные куски, но с перемешиванием (тяжёлые сцены не скапливаются у одного процесса)
    CH = max(1, int(a.fps * 20))
    chunks = []
    for k, s in enumerate(range(f0, f1, CH)):
        chunks.append((k, s, min(f1, s + CH)))
    jobs = [(k % a.workers, s, e, a.fps, a.scale, os.path.join(a.segdir, 'seg_%05d.mp4' % k), a.crf, a.preset) for (k, s, e) in chunks]
    t0 = time.time()
    ctx = mp.get_context('fork')
    with ctx.Pool(a.workers) as pool:
        res = pool.map(worker, jobs, chunksize=1)
    print('render done in %.1f s' % (time.time() - t0), flush=True)
    lst = os.path.join(a.segdir, 'list.txt')
    with open(lst, 'w') as fh:
        for (path, _) in res:
            fh.write("file '%s'\n" % os.path.abspath(path))
    video = os.path.join(a.segdir, 'video.mp4')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-c', 'copy', video], check=True)
    if a.noaudio:
        os.replace(video, a.out)
        return
    from mix import build_mix
    wav = 'build/mix.wav'
    if a.frames is None:
        stems = build_mix(EP, wav)
        print('stems dB RMS', json.dumps(stems), flush=True)
        # громкость: двухпроходный loudnorm к −16 LUFS
        r = subprocess.run(['ffmpeg', '-v', 'info', '-i', wav, '-af', 'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-'],
                           capture_output=True, text=True)
        js = r.stderr[r.stderr.rfind('{'):r.stderr.rfind('}') + 1]
        m = json.loads(js)
        af = ('loudnorm=I=-16:TP=-1.5:LRA=11:measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s:offset=%s:linear=true'
              % (m['input_i'], m['input_tp'], m['input_lra'], m['input_thresh'], m['target_offset']))
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', video, '-i', wav, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                        '-af', af, '-ar', '48000', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart', a.out], check=True)
    else:
        os.replace(video, a.out)
    print('wrote', a.out, flush=True)

if __name__ == '__main__':
    main()
