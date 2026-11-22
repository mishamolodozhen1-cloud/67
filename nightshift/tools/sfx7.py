"""Спрайт Sfx7 (v10): существо, скример, отключение света, испуг покупателей — звуки Soundza.

  запускать из папки, где лежит sfx_raw/ со скачанными из Soundza файлами; пишет Sfx7.wav, Sfx7.ogg, sfx7_index.json
"""
import subprocess, json, numpy as np
SR = 44100
def load(name, start=0.0, dur=None):
    cmd = ['ffmpeg','-v','error','-ss',str(start),'-i',f'sfx_raw/{name}']
    if dur: cmd += ['-t', str(dur)]
    cmd += ['-ac','1','-ar',str(SR),'-f','f32le','-']
    return np.frombuffer(subprocess.run(cmd, capture_output=True, check=True).stdout, dtype=np.float32).copy()
def rms_norm(x, db):
    r = float(np.sqrt(np.mean(x.astype(np.float64)**2))) or 1e-9
    y = x * (10**(db/20)/r); p = np.max(np.abs(y))
    return y/p*0.95 if p > 0.95 else y
def fade(x, a=0.005, b=0.08):
    x = x.copy(); n=int(a*SR); m=int(b*SR)
    if n: x[:n] *= np.linspace(0,1,n)
    if m: x[-m:] *= np.linspace(1,0,m)
    return x
def loudest(name, win):
    x = load(name); n=int(win*SR)
    e = np.convolve(x**2, np.ones(n), 'valid'); i = int(np.argmax(e))
    return x[i:i+n]
items = [
    ('BeastRoar', fade(rms_norm(load('BeastRoar.wav', 0.45, 2.9), -15), 0.01, 0.4)),
    ('BeastGrowl', fade(rms_norm(load('BeastGrowl.wav', 0, 2.2), -16), 0.01, 0.3)),
    ('BeastGrowlLow', fade(rms_norm(load('BeastGrowlLong.wav', 0, 3.2), -18), 0.3, 0.8)),
    ('BeastShriek', fade(rms_norm(load('BeastShriek.wav', 0.02, 1.1), -14), 0.003, 0.2)),
    ('BeastStep', fade(rms_norm(load('BeastStep.wav', 0, 1.9), -16), 0.002, 0.5)),
    ('BeastStomp', fade(rms_norm(load('BeastStomp.wav', 0, 0.39), -15), 0.002, 0.08)),
    ('ScareSting', fade(rms_norm(load('ScareSting.wav', 0, 2.6), -13), 0.002, 0.6)),
    ('BoneCrack', fade(rms_norm(load('BoneCrack.wav', 0, 0.4), -18), 0.002, 0.1)),
    ('CrowdGasp', fade(rms_norm(load('CrowdGasp.wav', 0, 1.15), -17), 0.005, 0.2)),
    ('WomanScream', fade(rms_norm(loudest('WomanScream.wav', 2.6), -17), 0.02, 0.5)),
    ('Blackout', fade(rms_norm(load('Blackout.wav', 0, 3.85), -17), 0.003, 0.5)),
    ('Breaker', fade(rms_norm(load('Breaker.wav', 0.2, 0.7), -16), 0.002, 0.15)),
]
parts=[np.zeros(int(0.02*SR),np.float32)]; t=0.02; idx={}
for name, x in items:
    idx[name] = (round(t,3), round(t+len(x)/SR,3)); parts.append(x.astype(np.float32)); t += len(x)/SR
    parts.append(np.zeros(int(0.6*SR),np.float32)); t += 0.6
a = np.concatenate(parts)
import wave
with wave.open('Sfx7.wav','wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((np.clip(a,-1,1)*32767).astype(np.int16).tobytes())
subprocess.run(['ffmpeg','-v','error','-y','-i','Sfx7.wav','-c:a','libvorbis','-q:a','5','Sfx7.ogg'], check=True)
json.dump(idx, open('sfx7_index.json','w'), indent=1)
print('Sfx7 %.1f s' % (len(a)/SR)); print(idx)
