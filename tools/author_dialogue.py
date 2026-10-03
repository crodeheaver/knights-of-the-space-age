#!/usr/bin/env python3
"""Authoring source for data/dialogue/*.json.

Each module in tools/dialogues/ defines DIALOGUES = [dict, ...] built with the
helpers below. Run:  python3 tools/author_dialogue.py
The game reads only the generated JSON (validated at startup and in tests).
"""
import importlib.util
import json
import os
import glob

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "dialogue")


def N(speaker, text, *choices, nxt=None, effects=None, end=False, repeat_effects=False, shot=None, anim=None):
    """A line. Choices are C(...) dicts; nxt continues without choices.

    Optional staging: shot = "ots" | "close" | "two" | "keep" (camera framing
    for this line), anim = "nod" | "shake" | "shrug" | "gesture" | "point" |
    "look_away" (a gesture the speaker plays while talking)."""
    n = {"speaker": speaker, "text": text}
    if choices:
        n["choices"] = list(choices)
    if nxt:
        n["next"] = nxt
    if effects:
        n["effects"] = effects
    if end:
        n["end"] = True
    if repeat_effects:
        n["repeat_effects"] = True
    if shot:
        n["shot"] = shot
    if anim:
        n["anim"] = anim
    return n


def R(*branches):
    """Redirect node: [(conditions, node), ...] first match wins."""
    return {"redirect": [{"if": c, "node": n} for c, n in branches]}


def C(text, nxt=None, *, tag=None, cond=None, locked=None, effects=None, check=None, success=None, failure=None,
      success_effects=None, failure_effects=None, end=False, tone=None, companion=None, hide=None):
    c = {"text": text}
    if nxt:
        c["next"] = nxt
    if tag:
        c["tag"] = tag
    if cond:
        c["if"] = cond
    if locked:
        c["show_locked"] = locked
    if effects:
        c["effects"] = effects
    if check:
        c["check"] = check
        c["success"] = success
        c["failure"] = failure
    if success_effects:
        c["success_effects"] = success_effects
    if failure_effects:
        c["failure_effects"] = failure_effects
    if end:
        c["end"] = True
    if tone:
        c["tone"] = tone
    if companion:
        c["companion"] = companion
    if hide:
        c["hide_if"] = hide
    if not nxt and not check and not end:
        c["end"] = True
    return c


def chk(skill, dc, cid, who="player", **kw):
    d = {"skill": skill, "dc": dc, "id": cid}
    if who != "player":
        d["who"] = who
    d.update(kw)
    return d


def inf(comp, delta, key, reason):
    return {"influence": comp, "delta": delta, "key": key, "reason": reason}


def align(delta, key, reason):
    return {"alignment": delta, "key": key, "reason": reason}


def xp(n, key, reason=""):
    return {"xp": n, "key": key, "reason": reason}


def flag(name, value=True):
    return {"set_flag": name, "value": value}


IONA = [{"in_party": "iona"}]
TAV = [{"in_party": "tav7"}]


def main():
    os.makedirs(OUT, exist_ok=True)
    count = 0
    outputs = {}
    for path in sorted(glob.glob(os.path.join(HERE, "dialogues", "*.py"))):
        spec = importlib.util.spec_from_file_location(os.path.basename(path)[:-3], path)
        mod = importlib.util.module_from_spec(spec)
        mod.__dict__.update({k: v for k, v in globals().items() if not k.startswith("__")})
        spec.loader.exec_module(mod)
        for d in getattr(mod, "DIALOGUES", []):
            with open(os.path.join(OUT, d["id"] + ".json"), "w") as f:
                json.dump(d, f, indent=1, ensure_ascii=False)
            count += 1
        # Modules may also emit other data files: OUTPUTS = {"voices": {...}}
        # writes data/voices.json. Dict outputs from several modules merge.
        for name, data in getattr(mod, "OUTPUTS", {}).items():
            outputs.setdefault(name, {}).update(data)
    print("wrote", count, "dialogues")
    for name, data in sorted(outputs.items()):
        path = os.path.join(OUT, "..", name + ".json")
        with open(path, "w") as f:
            json.dump(data, f, indent=1, ensure_ascii=False)
        print("wrote data/%s.json" % name)


if __name__ == "__main__":
    main()
