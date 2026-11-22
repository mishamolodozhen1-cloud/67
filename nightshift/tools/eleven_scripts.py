#!/usr/bin/env python3
"""Сценарии для озвучки в ElevenLabs (v11): все реплики одного голоса подряд, через пустую строку,
с тегами подачи. Печатает plans.json (порядок, тексты, сценарии) — его же читает tools/voice_split.py.

  eleven_scripts.py > plans.json
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import voice_lines as VL  # noqa: E402


def script(lines):
    out, prev = [], None
    for _, text, tag in lines:
        t = tag or "[calm]"
        out.append(f"{t} {text}" if (t != prev or tag) else text)
        prev = t
    return "\n\n".join(out)


def main():
    plans = {}
    for v in ("M1", "M2", "F1"):
        lines = [(k, (tf if (v == "F1" and tf) else t), VL.TAGS.get(k)) for k, (t, tf, _) in VL.CUSTOMER.items()]
        plans[v] = {"order": [k for k, _, _ in lines], "texts": {k: t for k, t, _ in lines}, "script": script(lines)}
    lines = [(k, t, VL.PLAYER_TAGS.get(k)) for k, t in VL.PLAYER.items()]
    plans["P"] = {"order": [k for k, _, _ in lines], "texts": {k: t for k, t, _ in lines}, "script": script(lines)}
    # v12: герой кат-сцены (тот же голос, что у охранника, — Dzmitry)
    lines = [(k, t, tag) for k, (t, tag) in VL.HERO.items()]
    plans["H"] = {"order": [k for k, _, _ in lines], "texts": {k: t for k, t, _ in lines}, "script": script(lines)}
    voices = dict(VL.ELEVEN_VOICES)
    voices["H"] = VL.ELEVEN_VOICES["P"]
    json.dump({"plans": plans, "voices": voices}, sys.stdout, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
