"""Проверка озвучки распознаванием речи (Whisper small, faster-whisper) и отбор лучших дублей.

  voice_check.py OUT_DIR [порог=0.85]   (OUT_DIR — папка voices.py; модели Piper в ./voices, Whisper в ./whisper)

Каждая реплика распознаётся и сравнивается с задуманным текстом. Если похожесть ниже порога,
синтезируется до 8 новых дублей (с разной скоростью) и остаётся лучший. После этого нужно
пересобрать спрайты: voices.py VOICES_DIR OUT_DIR --reuse.
"""
import json, subprocess, sys, re, os, difflib, numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voices as V, voice_lines as VL
from piper import PiperVoice
from faster_whisper import WhisperModel
out = sys.argv[1]; thr = float(sys.argv[2]) if len(sys.argv) > 2 else 0.85
idx = json.load(open(out + '/voice_index.json'))
m = WhisperModel('small', device='cpu', compute_type='int8', download_root='whisper')
def norm(s):
    s = s.lower().replace('ё', 'е'); return ' '.join(re.sub(r'[^а-яa-z0-9 ]+', ' ', s).split())
def score(y, text):
    a = np.frombuffer(subprocess.run(['ffmpeg','-v','error','-f','f32le','-ar',str(V.SR),'-ac','1','-i','-','-ar','16000','-f','f32le','-'], input=y.astype(np.float32).tobytes(), capture_output=True).stdout, dtype=np.float32)
    segs, _ = m.transcribe(a, language='ru', beam_size=5)
    t = ' '.join(s.text for s in segs)
    return difflib.SequenceMatcher(None, norm(text), norm(t)).ratio(), t
models = {}
fixed = []
for key, it in idx.items():
    v, k = key.split('_', 1)
    wav = f'{out}/clips/{key}.wav'
    import wave
    with wave.open(wav) as r: y0 = np.frombuffer(r.readframes(r.getnframes()), dtype=np.int16).astype(np.float32) / 32768
    s0, t0 = score(y0, it['Text'])
    if s0 >= thr: continue
    cfg = VL.VOICES[v]
    nervous = v != 'P' and VL.CUSTOMER[k][2]
    if cfg['model'] not in models: models[cfg['model']] = PiperVoice.load(f"voices/{cfg['model']}.onnx")
    best = (s0, y0, t0)
    for attempt in range(8):
        length = cfg['length'] * (0.92 if nervous else 1.0) * (1.0 + 0.05 * (attempt % 3))
        data, sr = V.synth(models[cfg['model']], it['Text'], length)
        y = V.process(data, sr, cfg['semitones'] + (0.5 if nervous else 0.0))
        s, t = score(y, it['Text'])
        if s > best[0]: best = (s, y, t)
        if best[0] >= 0.95: break
    V.save_wav(wav, best[1])
    fixed.append((key, it['Text'], round(s0, 2), round(best[0], 2), best[2]))
for f in fixed: print(f)
