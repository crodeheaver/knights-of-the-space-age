#!/usr/bin/env python3
"""Procedural audio for Ashes of the Concord.

Synthesises every sound effect, the ship ambience bed and the five music loops
as 16-bit mono WAV files in assets/audio/, then writes the manifest in
docs/ASSETS_AUDIO.md. Everything is original and generated from first
principles (oscillators, filtered noise, envelopes, FM, a small reverb and
echo) with the Python 3 standard library only: no samples, no third-party
code, no network access.

Output is deterministic: every sound draws from its own RNG seeded by its id,
so re-running the script reproduces byte-identical files.

Sound effects are rendered at 44.1 kHz; the ambience and music loops at
22.05 kHz to keep the repository small. Loops are built on a circular buffer
(note tails and effect tails wrap around to the start), so the last sample
flows straight into the first. Each loop file carries one extra "guard"
sample equal to sample 0, so a resampler that interpolates past the loop end
reads the correct value; GameAudio loops over frames [0, frames - 1).

Usage:
    python3 tools/gen_audio.py              # render everything + manifest
    python3 tools/gen_audio.py hit crit     # render only these ids
    python3 tools/gen_audio.py --list       # list ids
    python3 tools/gen_audio.py --manifest   # rewrite docs/ASSETS_AUDIO.md only
"""

import math
import os
import random
import struct
import sys
import wave

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
DOC_PATH = os.path.join(ROOT, "docs", "ASSETS_AUDIO.md")

SFX_RATE = 44100
LOOP_RATE = 22050
PEAK_DB = -3.0

TAU = 2.0 * math.pi
SR = SFX_RATE  # current render rate; set per sound by render()


# =============================================================== basic helpers
def ns(sec):
    """Seconds -> sample count at the current rate."""
    return max(1, int(round(sec * SR)))


def fnv1a(text):
    """Stable 32-bit string hash (Python's hash() is randomised per run)."""
    h = 0x811C9DC5
    for ch in text.encode("utf-8"):
        h = ((h ^ ch) * 0x01000193) & 0xFFFFFFFF
    return h


def mul(a, b):
    return [x * y for x, y in zip(a, b)]


def scale(a, g):
    return [x * g for x in a]


def add(*sigs):
    """Sum signals of any lengths (result is as long as the longest)."""
    out = [0.0] * max(len(s) for s in sigs)
    for s in sigs:
        out[: len(s)] = [a + b for a, b in zip(out, s)]
    return out


def place(dst, src, start, gain=1.0):
    """Mix src into dst at sample offset start (clipped to dst's length)."""
    if start >= len(dst):
        return
    end = min(len(dst), start + len(src))
    dst[start:end] = [a + b * gain for a, b in zip(dst[start:end], src)]


def peak(x):
    return max(max(x), -min(x)) or 1e-12


def rms(x):
    return math.sqrt(sum(v * v for v in x) / max(1, len(x)))


def active_rms(x, block=0.1):
    """RMS over the blocks that are actually sounding (ignores silent sections)."""
    b = ns(block)
    ms = []
    for i in range(0, len(x), b):
        seg = x[i:i + b]
        ms.append(sum(v * v for v in seg) / len(seg))
    top = max(ms) if ms else 0.0
    loud = [m for m in ms if m > top * 0.01]
    return math.sqrt(sum(loud) / len(loud)) if loud else 0.0


def fit(x, target):
    """Scale x so its active RMS equals target."""
    r = active_rms(x)
    return scale(x, target / r) if r > 1e-9 else x


def drive(x, k):
    """tanh saturation normalised so full scale stays full scale."""
    d = math.tanh(k)
    return [math.tanh(k * v) / d for v in x]


def fade_out(x, sec):
    m = min(len(x), ns(sec))
    for j in range(m):
        x[len(x) - m + j] *= 0.5 + 0.5 * math.cos(math.pi * (j + 1) / m)
    return x


def fade_in(x, sec):
    m = min(len(x), ns(sec))
    for j in range(m):
        x[j] *= 0.5 - 0.5 * math.cos(math.pi * j / m)
    return x


# ================================================================ oscillators
TBL_BITS = 13
TBL = 1 << TBL_BITS
MASK = TBL - 1
_SINE = [math.sin(TAU * i / TBL) for i in range(TBL)]
_TABLES = {}
_HARM_STEPS = (1, 2, 3, 4, 6, 8, 11, 16, 22, 32, 45, 64, 90, 128, 180, 256)


def _harmonics(shape, nh):
    if shape == "sine":
        return [(1, 1.0)]
    if shape == "saw":
        return [(k, 1.0 / k) for k in range(1, nh + 1)]
    if shape == "square":
        return [(k, 1.0 / k) for k in range(1, nh + 1, 2)]
    if shape == "tri":
        return [(k, (1.0 if (k // 2) % 2 == 0 else -1.0) / (k * k)) for k in range(1, nh + 1, 2)]
    raise ValueError(shape)


def table(shape, freq):
    """Band-limited single-cycle wavetable: only harmonics below ~0.45*SR."""
    limit = int(SR * 0.45 / max(freq, 1.0))
    nh = 1
    for h in _HARM_STEPS:
        if h <= limit:
            nh = h
    key = ("sine", 1) if shape == "sine" else (shape, nh)
    t = _TABLES.get(key)
    if t is None:
        t = [0.0] * TBL
        for k, a in _harmonics(shape, nh):
            t = [v + a * _SINE[(k * i) & MASK] for i, v in enumerate(t)]
        p = peak(t)
        t = [v / p for v in t]
        _TABLES[key] = t
    return t


def osc(shape, freq, n, phase=0.0):
    """Fixed-frequency oscillator; phase in cycles (0..1)."""
    t = table(shape, freq)
    inc = freq * TBL / SR
    p = phase * TBL
    return [t[int(p + i * inc) & MASK] for i in range(n)]


def osc_sweep(shape, freqs, phase=0.0, ref=None):
    """Oscillator following a per-sample frequency list."""
    t = table(shape, ref or max(freqs))
    k = TBL / SR
    p = phase * TBL
    out = [0.0] * len(freqs)
    for i, f in enumerate(freqs):
        out[i] = t[int(p) & MASK]
        p += f * k
    return out


def loop_osc(shape, freq, n, phase=0.0):
    """Oscillator nudged to a whole number of cycles in n samples (loop-safe)."""
    cycles = max(1, int(round(freq * n / SR)))
    return osc(shape, cycles * SR / n, n, phase)


def white(n, rng):
    r = rng.random
    return [r() * 2.0 - 1.0 for _ in range(n)]


def sparse(n, rng, density):
    """Random impulses (density = impulses per second) for crackle/debris."""
    p = density / SR
    r = rng.random
    return [(r() * 2.0 - 1.0) if r() < p else 0.0 for _ in range(n)]


def fm_bell(freq, n, ratio=3.5, index=2.0, tau=0.5, itau=None, attack=0.002):
    """Two-operator FM tone whose modulation index decays faster than its amplitude."""
    s = _SINE
    ic = freq * TBL / SR
    im = freq * ratio * TBL / SR
    da = math.exp(-1.0 / (tau * SR))
    di = math.exp(-1.0 / ((itau or tau * 0.35) * SR))
    na = max(1, int(attack * SR))
    out = [0.0] * n
    a = 1.0
    depth = index * TBL / TAU
    for i in range(n):
        out[i] = s[int(i * ic + depth * s[int(i * im) & MASK]) & MASK] * a * (i / na if i < na else 1.0)
        a *= da
        depth *= di
    return out


# ================================================================== envelopes
def env_pts(points, n):
    """Piecewise-linear envelope through (seconds, value) points."""
    out = [0.0] * n
    pts = [(int(round(t * SR)), float(v)) for t, v in points]
    first_i, first_v = pts[0]
    if first_i > 0:
        out[: min(first_i, n)] = [first_v] * min(first_i, n)
    for (i0, v0), (i1, v1) in zip(pts, pts[1:]):
        a, b = max(i0, 0), min(i1, n)
        if i1 <= i0 or a >= b:
            continue
        step = (v1 - v0) / (i1 - i0)
        out[a:b] = [v0 + step * (i - i0) for i in range(a, b)]
    last_i, last_v = pts[-1]
    if last_i < n:
        out[max(last_i, 0):] = [last_v] * (n - max(last_i, 0))
    return out


def env_exp(n, tau, attack=0.001, hold=0.0):
    """Linear attack, optional hold, then exponential decay with time constant tau."""
    na = max(1, int(attack * SR))
    nh = int(hold * SR)
    k = math.exp(-1.0 / (tau * SR))
    out = [0.0] * n
    v = 1.0
    for i in range(n):
        if i < na:
            out[i] = i / na
        elif i < na + nh:
            out[i] = 1.0
        else:
            out[i] = v
            v *= k
    return out


def sweep_exp(f0, f1, n, tau):
    """Frequency gliding exponentially from f0 towards f1 (time constant tau)."""
    return [f1 + (f0 - f1) * math.exp(-i / (tau * SR)) for i in range(n)]


def glide(f0, f1, n):
    """Geometric (musically even) glide from f0 to f1 over n samples."""
    r = f1 / f0
    return [f0 * r ** (i / max(1, n - 1)) for i in range(n)]


def lfo(n, cycles, lo, hi, phase=0.0):
    """Sine LFO with a whole number of cycles over n samples (loop-safe)."""
    mid, amp = (lo + hi) * 0.5, (hi - lo) * 0.5
    w = TAU * cycles / n
    return [mid + amp * math.sin(w * i + phase) for i in range(n)]


# ==================================================================== filters
def lp1(x, fc):
    a = 1.0 - math.exp(-TAU * fc / SR)
    y = 0.0
    out = [0.0] * len(x)
    for i, v in enumerate(x):
        y += a * (v - y)
        out[i] = y
    return out


def hp1(x, fc):
    return [v - w for v, w in zip(x, lp1(x, fc))]


def svf(x, fc, q=0.707, mode="lp"):
    """Topology-preserving state-variable filter (stable at any cutoff).

    fc is a number or a per-sample list (coefficients refresh every 16
    samples). Modes: lp, hp, bp (band-pass normalised to unity peak gain).
    """
    n = len(x)
    k = 1.0 / q
    nyq = SR * 0.49
    varying = isinstance(fc, list)

    def coefs(f):
        g = math.tan(math.pi * min(max(f, 10.0), nyq) / SR)
        a1 = 1.0 / (1.0 + g * (g + k))
        return a1, g * a1, g * g * a1

    a1, a2, a3 = coefs(fc[0] if varying else fc)
    m = {"lp": 0, "bp": 1, "hp": 2}[mode]
    out = [0.0] * n
    ic1 = ic2 = 0.0
    for i in range(n):
        if varying and (i & 15) == 0:
            a1, a2, a3 = coefs(fc[i])
        v0 = x[i]
        v3 = v0 - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if m == 0:
            out[i] = v2
        elif m == 1:
            out[i] = k * v1
        else:
            out[i] = v0 - k * v1 - v2
    return out


# ==================================================================== effects
def echo(x, t, fb=0.35, wet=0.3, damp=0.3, dry=1.0):
    """Feedback delay with a low-pass in the loop."""
    d = ns(t)
    n = len(x)
    w = [0.0] * n
    out = [0.0] * n
    s = 0.0
    g = 1.0 - damp
    for i in range(n):
        o = w[i - d] if i >= d else 0.0
        s += (o - s) * g
        w[i] = x[i] + s * fb
        out[i] = dry * x[i] + wet * o
    return out


_COMBS = (1116, 1188, 1277, 1356, 1422, 1491)
_ALLPASS = (556, 441, 341)


def reverb(x, room=0.8, damp=0.35, wet=0.3, dry=1.0):
    """Small Schroeder/Freeverb-style mono reverb (parallel combs + allpasses)."""
    sc = SR / 44100.0
    n = len(x)
    acc = [0.0] * n
    fb = 0.7 + 0.28 * room
    d1, d2 = damp, 1.0 - damp
    for length in _COMBS:
        dl = int(length * sc)
        w = [0.0] * n
        s = 0.0
        for i in range(n):
            o = w[i - dl] if i >= dl else 0.0
            s = o * d2 + s * d1
            w[i] = x[i] + s * fb
            acc[i] += o
    for length in _ALLPASS:
        dl = int(length * sc)
        w = [0.0] * n
        for i in range(n):
            bo = w[i - dl] if i >= dl else 0.0
            v = acc[i]
            w[i] = v + bo * 0.5
            acc[i] = bo - v
    g = 0.02 * wet
    return [dry * a + g * b for a, b in zip(x, acc)]


def loop_apply(buf, fn, pre_sec):
    """Run a stateful effect over a loop as if it had been playing forever:
    the effect first runs over the loop's last pre_sec seconds, so its state
    (filter memory, echo and reverb tails) carries across the seam."""
    p = min(len(buf), ns(pre_sec))
    y = fn(buf[-p:] + buf)
    return y[p:p + len(buf)]


def loop_svf(buf, fc, q, mode, pre_sec=1.0):
    """svf over a loop with a per-sample cutoff list that is itself periodic."""
    p = min(len(buf), ns(pre_sec))
    y = svf(buf[-p:] + buf, fc[-p:] + fc, q, mode)
    return y[p:]


# ================================================================== registry
SOUNDS = []


def sound(sid, kind, desc, rate=SFX_RATE, peak_db=PEAK_DB, loop=False):
    def deco(fn):
        SOUNDS.append({"id": sid, "kind": kind, "desc": desc, "rate": rate,
                       "peak_db": peak_db, "loop": loop, "fn": fn})
        return fn
    return deco


# ============================================================= notes & chords
_NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    """'C#4' / 'Bb2' / 'E5' -> MIDI note number (A4 = 69)."""
    i, acc = 1, 0
    while name[i] in "#b":
        acc += 1 if name[i] == "#" else -1
        i += 1
    return 12 * (int(name[i:]) + 1) + _NOTE[name[0]] + acc


def mhz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def hz(name):
    return mhz(midi(name))


# ======================================================================= SFX
# ---- UI ----------------------------------------------------------------------
@sound("ui_click", "UI", "Sine blip falling 2.3->1.5 kHz over a few ms plus a high-passed noise tick.")
def ui_click(rng):
    n = ns(0.055)
    tone = mul(osc_sweep("sine", sweep_exp(2300.0, 1500.0, n, 0.006)), env_exp(n, 0.009, 0.0006))
    tick = mul(svf(white(n, rng), 4500.0, 0.7, "hp"), env_exp(n, 0.0015, 0.0002))
    return add(tone, scale(tick, 0.3))


@sound("ui_open", "UI", "Triangle + fifth sweeping up an octave (440->880 Hz) over a rising band-passed air swish.")
def ui_open(rng):
    n = ns(0.3)
    f = env_pts([(0.0, 440.0), (0.14, 880.0), (0.3, 920.0)], n)
    body = add(scale(osc_sweep("tri", f), 0.7), scale(osc_sweep("sine", [v * 1.5 for v in f]), 0.3))
    body = mul(body, env_pts([(0.0, 0.0), (0.012, 1.0), (0.12, 0.65), (0.3, 0.0)], n))
    air = svf(white(n, rng), env_pts([(0.0, 700.0), (0.2, 3600.0)], n), 1.4, "bp")
    air = mul(air, env_pts([(0.0, 0.0), (0.08, 1.0), (0.3, 0.0)], n))
    return add(body, scale(air, 0.22))


@sound("ui_error", "UI", "Two descending detuned square buzzes (Bb3 then F3), low-passed.")
def ui_error(rng):
    n = ns(0.32)
    out = [0.0] * n
    for start, dur, f in ((0.0, 0.12, 233.08), (0.15, 0.16, 174.61)):
        m = ns(dur)
        sq = add(osc("square", f, m), scale(osc("square", f * 1.013, m, 0.37), 0.7))
        env = env_pts([(0.0, 0.0), (0.004, 1.0), (dur - 0.035, 0.85), (dur, 0.0)], m)
        place(out, svf(mul(sq, env), 1700.0, 0.9), ns(start))
    return out


@sound("ui_confirm", "UI", "Two quick rising FM chimes, C6 then G6.")
def ui_confirm(rng):
    n = ns(0.3)
    out = [0.0] * n
    for start, f, tau in ((0.0, 1046.5, 0.06), (0.065, 1568.0, 0.14)):
        st = ns(start)
        place(out, fm_bell(f, n - st, ratio=2.0, index=0.8, tau=tau), st)
    return out


@sound("quest", "UI", "Rising D5-A5-D6 FM bell arpeggio over a soft sine fifth, light reverb.")
def quest(rng):
    n = ns(0.95)
    out = [0.0] * n
    for start, f, tau in ((0.0, 587.33, 0.3), (0.11, 880.0, 0.35), (0.22, 1174.66, 0.5)):
        st = ns(start)
        place(out, fm_bell(f, n - st, ratio=3.0, index=1.6, tau=tau), st, 0.8)
    pad = add(osc("sine", 293.66, n), scale(osc("sine", 440.0, n), 0.6))
    pad = mul(pad, env_pts([(0, 0), (0.06, 0.35), (0.5, 0.25), (0.95, 0)], n))
    return reverb(add(out, scale(pad, 0.5)), room=0.5, damp=0.4, wet=0.25)


@sound("level_up", "UI", "Fast C-major square arpeggio into a detuned-saw chord with tremolo and a noise sparkle, reverb.")
def level_up(rng):
    n = ns(1.2)
    out = [0.0] * n
    for k, name in enumerate(("C5", "E5", "G5", "C6", "E6")):
        m = ns(0.35)
        p = mul(osc("square", hz(name), m), env_exp(m, 0.09, 0.002))
        place(out, lp1(p, 4500.0), ns(0.055 * k), 0.5)
    st = ns(0.24)
    m = n - st
    chord = [0.0] * m
    for name in ("C5", "E5", "G5", "C6"):
        f = hz(name)
        chord = add(chord, osc("saw", f * 0.997, m, rng.random()), osc("saw", f * 1.003, m, rng.random()))
    chord = svf(chord, 3200.0, 0.7)
    trem = [1.0 - 0.18 * (0.5 + 0.5 * math.sin(TAU * 9.0 * i / SR)) for i in range(m)]
    chord = mul(mul(chord, trem), env_pts([(0, 0), (0.06, 1.0), (0.45, 0.6), (0.96, 0.0)], m))
    place(out, chord, st, 0.12)
    sparkle = mul(svf(white(n, rng), 6500.0, 0.7, "hp"), env_pts([(0, 0), (0.3, 0.0), (0.6, 1.0), (1.2, 0.0)], n))
    return reverb(add(out, scale(sparkle, 0.06)), room=0.6, damp=0.35, wet=0.3)


@sound("save", "UI", "Six random high square data blips, then a soft triangle G5+D6 ding.")
def save(rng):
    n = ns(0.62)
    out = [0.0] * n
    choices = (1760.0, 1975.5, 2349.3, 2637.0, 2093.0, 2793.8)
    t = 0.0
    for _ in range(6):
        f = choices[int(rng.random() * len(choices))]
        m = ns(0.016)
        b = mul(osc("square", f, m), env_pts([(0, 0), (0.002, 1), (0.012, 0.6), (0.016, 0)], m))
        place(out, lp1(b, 5000.0), ns(t), 0.35)
        t += 0.032 + 0.012 * rng.random()
    st = ns(0.27)
    m = n - st
    ding = add(osc("tri", 783.99, m), scale(osc("tri", 1174.66, m), 0.8), scale(osc("sine", 1567.98, m), 0.25))
    place(out, mul(ding, env_exp(m, 0.16, 0.004)), st, 0.6)
    return out


# ---- world --------------------------------------------------------------------
@sound("alert", "SFX", "Urgent two-note saw/square sting (E5 then vibrato B5) with a band-passed noise hit.")
def alert(rng):
    n = ns(0.5)
    out = [0.0] * n
    m1 = ns(0.08)
    a = add(osc("saw", 659.25, m1), scale(osc("square", 659.25 * 1.005, m1), 0.5))
    place(out, mul(a, env_pts([(0, 0), (0.003, 1), (0.06, 0.8), (0.08, 0)], m1)), 0, 0.6)
    st = ns(0.09)
    m2 = n - st
    f = [987.77 * (1 + 0.012 * math.sin(TAU * 7.0 * i / SR)) for i in range(m2)]
    b = add(osc_sweep("saw", f), scale(osc_sweep("square", [v * 1.004 for v in f]), 0.5))
    place(out, mul(b, env_pts([(0, 0), (0.004, 1), (0.2, 0.7), (0.41, 0)], m2)), st, 0.6)
    out = svf(out, 3800.0, 0.8)
    hitn = mul(svf(white(n, rng), 2600.0, 1.0, "bp"), env_exp(n, 0.015, 0.0005))
    return add(out, scale(hitn, 0.35))


@sound("alarm", "SFX", "Two klaxon whoops: saw + sub-octave square rising 470->760 Hz, band-passed and saturated.")
def alarm(rng):
    n = ns(1.18)
    out = [0.0] * n
    for start in (0.0, 0.6):
        m = ns(0.56)
        f = env_pts([(0, 470.0), (0.34, 760.0), (0.56, 770.0)], m)
        w = add(osc_sweep("saw", f), scale(osc_sweep("square", [v * 0.5 for v in f]), 0.6))
        place(out, mul(w, env_pts([(0, 0), (0.02, 1), (0.5, 1), (0.56, 0)], m)), ns(start))
    return drive(svf(out, 1300.0, 1.6, "bp"), 2.2)


@sound("door", "SFX", "Pneumatic hiss (noise band sweeping 4.2->0.9 kHz), low saw motor, and a latch thunk.")
def door(rng):
    n = ns(0.9)
    hiss = svf(white(n, rng), sweep_exp(4200.0, 900.0, n, 0.18), 0.9, "bp")
    out = scale(mul(hiss, env_pts([(0, 0), (0.012, 1.0), (0.18, 0.55), (0.55, 0.12), (0.7, 0)], n)), 0.55)
    m = ns(0.68)
    mf = env_pts([(0, 70.0), (0.25, 105.0), (0.6, 96.0)], m)
    motor = svf(add(osc_sweep("saw", mf), scale(osc_sweep("square", [v * 2.01 for v in mf]), 0.3)), 420.0, 0.9)
    place(out, mul(motor, env_pts([(0, 0), (0.06, 1.0), (0.55, 0.8), (0.68, 0)], m)), ns(0.03), 0.45)
    st = ns(0.62)
    m2 = n - st
    thunk = mul(osc_sweep("sine", sweep_exp(110.0, 42.0, m2, 0.04)), env_exp(m2, 0.09, 0.001))
    clack = mul(svf(white(m2, rng), 1600.0, 0.8), env_exp(m2, 0.012, 0.0005))
    place(out, add(thunk, scale(clack, 0.6)), st, 0.9)
    return out


@sound("loot", "SFX", "Bright two-note FM pickup chime (B5, E6) with a crinkly band-passed noise rustle.")
def loot(rng):
    n = ns(0.42)
    out = [0.0] * n
    for start, f in ((0.0, 987.77), (0.07, 1318.51)):
        st = ns(start)
        place(out, fm_bell(f, n - st, ratio=2.0, index=1.2, tau=0.12), st, 0.7)
    for start in (0.0, 0.028, 0.05, 0.085):
        m = ns(0.02)
        r = mul(svf(white(m, rng), 3000.0, 0.8, "bp"), env_pts([(0, 0), (0.002, 1), (0.02, 0)], m))
        place(out, r, ns(start), 0.3)
    return out


@sound("bash", "SFX", "Forced-entry impact: sine thump 130->38 Hz, six inharmonic metal partials, noise crunch, saturated.")
def bash(rng):
    n = ns(0.55)
    body = mul(osc_sweep("sine", sweep_exp(130.0, 38.0, n, 0.035)), env_exp(n, 0.16, 0.0008))
    clang = [0.0] * n
    for f, a, tau in ((287.0, 1.0, 0.32), (431.5, 0.7, 0.22), (689.0, 0.6, 0.18),
                      (1013.0, 0.45, 0.14), (1517.0, 0.3, 0.1), (2221.0, 0.2, 0.07)):
        part = osc("sine", f * (1 + 0.004 * (rng.random() - 0.5)), n, rng.random())
        clang = add(clang, scale(mul(part, env_exp(n, tau, 0.0008)), a))
    crunch = mul(svf(white(n, rng), 3000.0, 0.7), env_exp(n, 0.035, 0.0005))
    return drive(add(body, scale(clang, 0.35), scale(crunch, 0.7)), 1.8)


# ---- ranged weapons -------------------------------------------------------------
@sound("blaster", "SFX", "Classic 'pew': sine + square falling exponentially 2.1 kHz->240 Hz with a noise crack.")
def blaster(rng):
    n = ns(0.32)
    f = sweep_exp(2100.0, 240.0, n, 0.05)
    body = mul(add(osc_sweep("sine", f), scale(osc_sweep("square", f), 0.45)), env_exp(n, 0.075, 0.0008))
    crack = mul(svf(white(n, rng), 3000.0, 0.7, "hp"), env_exp(n, 0.004, 0.0002))
    return lp1(add(body, scale(crack, 0.45)), 7500.0)


@sound("rifle", "SFX", "Sharp crack + saw/square bolt diving 1.35 kHz->95 Hz through a closing filter, low thump, slap echo.")
def rifle(rng):
    n = ns(0.48)
    f = sweep_exp(1350.0, 95.0, n, 0.04)
    body = add(osc_sweep("saw", f), scale(osc_sweep("square", [v * 1.01 for v in f]), 0.5))
    body = mul(svf(body, sweep_exp(6500.0, 450.0, n, 0.06), 0.9), env_exp(n, 0.1, 0.0006))
    crack = add(scale(mul(svf(white(n, rng), 4000.0, 0.7, "hp"), env_exp(n, 0.005, 0.0002)), 0.9),
                scale(mul(svf(white(n, rng), 2200.0, 0.9, "bp"), env_exp(n, 0.03, 0.0004)), 0.5))
    thump = mul(osc_sweep("sine", sweep_exp(150.0, 45.0, n, 0.03)), env_exp(n, 0.07, 0.0008))
    out = drive(add(scale(body, 0.6), crack, scale(thump, 0.8)), 1.6)
    return echo(out, 0.085, fb=0.25, wet=0.22, damp=0.5)


@sound("ion", "SFX", "Ring-modulated saw buzz (carrier sweeping 2.3->0.7 kHz), band-passed spark crackle and a rising zap.")
def ion(rng):
    n = ns(0.62)
    ring = osc_sweep("sine", env_pts([(0, 2300.0), (0.15, 1400.0), (0.62, 700.0)], n))
    buzz = mul(add(osc("saw", 110.0, n), scale(osc("square", 165.3, n, 0.2), 0.5)), ring)
    sparks = svf(sparse(n, rng, 900.0), 3800.0, 1.5, "bp")
    out = mul(add(scale(buzz, 0.55), fit(sparks, 0.25)), env_pts([(0, 0), (0.005, 1.0), (0.18, 0.75), (0.62, 0.0)], n))
    m = ns(0.12)
    zap = osc_sweep("sine", env_pts([(0, 300.0), (0.1, 1900.0), (0.12, 2000.0)], m))
    place(out, mul(zap, env_pts([(0, 0), (0.004, 1), (0.08, 0.7), (0.12, 0)], m)), 0, 0.5)
    return drive(out, 1.5)


@sound("drone", "SFX", "Combat-drone shot: fast-vibrato square motor whirr with two quick square zaps (2.8->0.85 kHz).")
def drone(rng):
    n = ns(0.6)
    vib = [190.0 * (1 + 0.07 * math.sin(TAU * 28.0 * i / SR)) for i in range(n)]
    whirr = svf(osc_sweep("square", vib), 1300.0, 0.9)
    out = scale(mul(whirr, env_pts([(0, 0.0), (0.05, 0.6), (0.4, 0.5), (0.6, 0.0)], n)), 0.35)
    for start in (0.06, 0.2):
        m = ns(0.09)
        z = mul(osc_sweep("square", sweep_exp(2800.0, 850.0, m, 0.025)), env_exp(m, 0.03, 0.0006))
        place(out, lp1(z, 6000.0), ns(start), 0.7)
    return out


@sound("heavy_blaster", "SFX", "Big bolt: two detuned saws diving 780->52 Hz under a closing resonant filter, sub boom, noise blast.")
def heavy_blaster(rng):
    n = ns(0.75)
    f = sweep_exp(780.0, 52.0, n, 0.085)
    body = add(osc_sweep("saw", f), osc_sweep("saw", [v * 1.012 for v in f], 0.3))
    body = mul(svf(body, sweep_exp(5200.0, 380.0, n, 0.12), 1.1), env_exp(n, 0.22, 0.0008))
    sub = mul(osc_sweep("sine", sweep_exp(90.0, 30.0, n, 0.12)), env_exp(n, 0.25, 0.001))
    boom = mul(svf(white(n, rng), 900.0, 0.7), env_exp(n, 0.13, 0.001))
    crack = mul(svf(white(n, rng), 3500.0, 0.7, "hp"), env_exp(n, 0.006, 0.0002))
    return drive(add(scale(body, 0.5), scale(sub, 0.9), scale(boom, 0.7), scale(crack, 0.4)), 2.2)


# ---- melee ------------------------------------------------------------------------
@sound("blade", "SFX", "Vibro-blade swing: noise band sweeping 0.5->3.2->0.9 kHz, faint 60 Hz-gated buzz, metallic ring.")
def blade(rng):
    n = ns(0.36)
    sw = svf(white(n, rng), env_pts([(0, 500.0), (0.12, 3200.0), (0.36, 900.0)], n), 1.6, "bp")
    sw = mul(sw, env_pts([(0, 0), (0.1, 1.0), (0.2, 0.5), (0.34, 0)], n))
    hum = mul(osc("saw", 220.0, n), [0.5 + 0.5 * math.sin(TAU * 60.0 * i / SR) for i in range(n)])
    hum = mul(svf(hum, 1500.0, 0.8), env_pts([(0, 0), (0.08, 0.3), (0.25, 0.0)], n))
    out = add(sw, scale(hum, 0.25))
    st = ns(0.13)
    m = n - st
    ring = mul(add(osc("sine", 3150.0, m), scale(osc("sine", 4720.0, m), 0.6)), env_exp(m, 0.06, 0.002))
    place(out, ring, st, 0.12)
    return out


@sound("lumen", "SFX", "Energy-blade swing: detuned saw hum ~92 Hz with Doppler pitch bend and opening filter, sizzle and swoosh.")
def lumen(rng):
    n = ns(0.75)
    bend = env_pts([(0, 0.92), (0.16, 1.35), (0.4, 1.0), (0.75, 0.97)], n)
    f1 = [92.0 * b for b in bend]
    hum = add(osc_sweep("saw", f1), osc_sweep("saw", [v * 1.016 for v in f1], 0.4),
              scale(osc_sweep("square", [v * 2.0 for v in f1], 0.1), 0.5))
    hum = svf(hum, env_pts([(0, 700.0), (0.16, 2400.0), (0.75, 800.0)], n), 1.3)
    amp = env_pts([(0, 0), (0.03, 0.55), (0.16, 1.0), (0.4, 0.6), (0.75, 0.0)], n)
    hum = mul(hum, amp)
    sizzle = mul(svf(white(n, rng), 2500.0, 2.0, "bp"), amp)
    swoosh = svf(white(n, rng), env_pts([(0, 600.0), (0.16, 2800.0), (0.4, 900.0)], n), 1.2, "bp")
    swoosh = mul(swoosh, env_pts([(0, 0), (0.16, 1.0), (0.4, 0.0)], n))
    return drive(add(scale(hum, 0.8), scale(sizzle, 0.15), scale(swoosh, 0.4)), 1.3)


@sound("punch", "SFX", "Body blow: sine thud 165->52 Hz, low-passed noise smack and a tiny click.")
def punch(rng):
    n = ns(0.24)
    body = mul(osc_sweep("sine", sweep_exp(165.0, 52.0, n, 0.018)), env_exp(n, 0.065, 0.0008))
    smack = mul(svf(white(n, rng), 1300.0, 0.7), env_exp(n, 0.022, 0.0004))
    click = mul(svf(white(n, rng), 3000.0, 0.7, "hp"), env_exp(n, 0.0015, 0.0001))
    return drive(add(body, scale(smack, 0.8), scale(click, 0.3)), 1.5)


@sound("baton", "SFX", "Stun baton: light sine thud plus a randomly gated high-passed noise zap over a 120 Hz square buzz.")
def baton(rng):
    n = ns(0.38)
    thud = mul(osc_sweep("sine", sweep_exp(210.0, 80.0, n, 0.02)), env_exp(n, 0.05, 0.0008))
    gate = []
    while len(gate) < n:
        seg = int((0.004 + 0.012 * rng.random()) * SR)
        gate.extend([1.0 if rng.random() < 0.6 else 0.15] * seg)
    gate = lp1(gate[:n], 900.0)
    zap = add(mul(svf(white(n, rng), 2500.0, 0.7, "hp"), gate), scale(svf(osc("square", 120.0, n), 2000.0, 0.7), 0.3))
    zap = mul(zap, env_exp(n, 0.14, 0.001))
    return drive(add(scale(thud, 0.8), scale(zap, 0.6)), 1.4)


@sound("heavy", "SFX", "Big melee swing: slow low noise whoosh (0.22->1.1 kHz) then a deep 115->32 Hz impact with crunch.")
def heavy(rng):
    n = ns(0.7)
    wh = svf(white(n, rng), env_pts([(0, 220.0), (0.24, 1100.0), (0.42, 300.0)], n), 1.3, "bp")
    out = scale(mul(wh, env_pts([(0, 0), (0.22, 1.0), (0.34, 0.6), (0.45, 0.0)], n)), 0.7)
    st = ns(0.34)
    m = n - st
    impact = mul(osc_sweep("sine", sweep_exp(115.0, 32.0, m, 0.04)), env_exp(m, 0.2, 0.0008))
    crunch = mul(svf(white(m, rng), 2200.0, 0.7), env_exp(m, 0.05, 0.0005))
    place(out, drive(add(impact, scale(crunch, 0.8)), 2.0), st)
    return out


@sound("spider", "SFX", "Skittering cutter: random pitched leg clicks every 22-44 ms, a wobbling 1.45 kHz saw cutting whine, servo.")
def spider(rng):
    n = ns(0.65)
    out = [0.0] * n
    t = 0.0
    while t < 0.55:
        m = ns(0.012)
        f = 1800.0 + 2400.0 * rng.random()
        c = add(mul(osc("sine", f, m, rng.random()), env_exp(m, 0.0035, 0.0002)),
                scale(mul(svf(white(m, rng), 3500.0, 0.7, "hp"), env_exp(m, 0.0012, 0.0001)), 0.6))
        place(out, c, ns(t), 0.5 + 0.5 * rng.random())
        t += 0.022 + 0.022 * rng.random()
    wf = [1450.0 * (1 + 0.03 * math.sin(TAU * 13.0 * i / SR)) for i in range(n)]
    whine = svf(osc_sweep("saw", wf), 2600.0, 2.0, "bp")
    whine = mul(whine, env_pts([(0, 0), (0.1, 0.0), (0.2, 1.0), (0.5, 0.8), (0.62, 0.0)], n))
    servo = svf(osc_sweep("square", env_pts([(0, 300.0), (0.3, 420.0), (0.65, 360.0)], n)), 900.0, 0.8)
    servo = mul(servo, env_pts([(0, 0), (0.05, 1), (0.55, 0.7), (0.65, 0)], n))
    return add(out, scale(whine, 0.3), scale(servo, 0.12))


# ---- combat feedback --------------------------------------------------------------
@sound("hit", "SFX", "Neutral hit: short sine thump 240->90 Hz, band-passed noise snap, click; mildly saturated.")
def hit(rng):
    n = ns(0.26)
    body = mul(osc_sweep("sine", sweep_exp(240.0, 90.0, n, 0.018)), env_exp(n, 0.055, 0.0006))
    snap = mul(svf(white(n, rng), 1600.0, 0.8, "bp"), env_exp(n, 0.03, 0.0004))
    click = mul(svf(white(n, rng), 4000.0, 0.7, "hp"), env_exp(n, 0.0018, 0.0001))
    return drive(add(body, scale(snap, 0.9), scale(click, 0.35)), 1.8)


@sound("crit", "SFX", "Critical: deeper, harder thump 200->48 Hz with bright noise, a ringing inharmonic 'shing' and a rising zing.")
def crit(rng):
    n = ns(0.55)
    body = mul(osc_sweep("sine", sweep_exp(200.0, 48.0, n, 0.03)), env_exp(n, 0.12, 0.0006))
    snap = mul(svf(white(n, rng), 3800.0, 0.7), env_exp(n, 0.05, 0.0004))
    shing = [0.0] * n
    for f, a, tau in ((2350.0, 1.0, 0.3), (3180.0, 0.8, 0.24), (4410.0, 0.6, 0.18), (5930.0, 0.4, 0.12)):
        shing = add(shing, scale(mul(osc("sine", f, n, rng.random()), env_exp(n, tau, 0.001)), a))
    zing = osc_sweep("sine", env_pts([(0, 1200.0), (0.2, 2600.0), (0.55, 2700.0)], n))
    zing = mul(zing, env_pts([(0, 0), (0.01, 0.0), (0.04, 1.0), (0.25, 0.3), (0.5, 0)], n))
    return add(drive(add(body, scale(snap, 0.9)), 2.4), scale(shing, 0.12), scale(zing, 0.18))


@sound("miss", "SFX", "Airy whiff: noise band falling 3->0.65 kHz with a faint sine 'fwip'; no impact.")
def miss(rng):
    n = ns(0.3)
    w = svf(white(n, rng), sweep_exp(3000.0, 650.0, n, 0.09), 1.3, "bp")
    w = mul(w, env_pts([(0, 0), (0.05, 1.0), (0.14, 0.5), (0.27, 0)], n))
    fw = mul(osc_sweep("sine", sweep_exp(950.0, 380.0, n, 0.06)), env_pts([(0, 0), (0.03, 1), (0.12, 0)], n))
    return add(w, scale(fw, 0.12))


@sound("deflect", "SFX", "Ricochet: metallic clank, sine whine diving 3.5->1.45 kHz with flutter, high inharmonic ping.")
def deflect(rng):
    n = ns(0.5)
    clank = add(mul(svf(white(n, rng), 3200.0, 0.7, "hp"), env_exp(n, 0.006, 0.0002)),
                scale(mul(osc("sine", 1900.0, n), env_exp(n, 0.03, 0.0005)), 0.6))
    pf = [v * (1 + 0.01 * math.sin(TAU * 38.0 * i / SR)) for i, v in enumerate(sweep_exp(3500.0, 1450.0, n, 0.16))]
    whine = mul(osc_sweep("sine", pf), env_pts([(0, 0), (0.015, 0.0), (0.03, 1.0), (0.25, 0.4), (0.48, 0)], n))
    ping = [0.0] * n
    for f, a, tau in ((2620.0, 1.0, 0.22), (3955.0, 0.6, 0.16), (5410.0, 0.35, 0.1)):
        ping = add(ping, scale(mul(osc("sine", f, n, rng.random()), env_exp(n, tau, 0.0008)), a))
    return add(scale(clank, 0.8), scale(whine, 0.35), scale(ping, 0.25))


@sound("explosion", "SFX", "Noise blast under a low-pass closing 5 kHz->160 Hz, sine sub boom 80->28 Hz, debris crackle, heavy saturation.")
def explosion(rng):
    n = ns(1.2)
    blast = mul(svf(white(n, rng), sweep_exp(5000.0, 160.0, n, 0.22), 0.8), env_exp(n, 0.35, 0.003))
    sub = mul(osc_sweep("sine", sweep_exp(80.0, 28.0, n, 0.15)), env_exp(n, 0.45, 0.002))
    rumble = mul(lp1(lp1(white(n, rng), 160.0), 160.0), env_pts([(0, 0), (0.05, 1.0), (0.6, 0.5), (1.2, 0)], n))
    st = ns(0.08)
    deb = sparse(n - st, rng, 350.0)
    deb = mul(svf(deb, 2400.0, 1.2, "bp"), env_pts([(0, 1.0), (0.9, 0.0)], n - st))
    out = add(blast, scale(sub, 0.9), fit(rumble, 0.12))
    place(out, fit(deb, 0.06), st)
    return drive(out, 2.6)


# ---- powers & states ----------------------------------------------------------------
@sound("cast", "SFX", "Resonance power: stacked sine partials in fifths (330 Hz base) rising a whole tone with vibrato, resonant noise swirl, reverb.")
def cast(rng):
    n = ns(0.85)
    rise = env_pts([(0, 1.0), (0.6, 1.12), (0.85, 1.12)], n)
    out = [0.0] * n
    for mult, a, vr in ((1.0, 1.0, 5.1), (1.5, 0.7, 6.3), (2.0, 0.5, 4.7), (3.0, 0.3, 7.2), (4.5, 0.18, 5.9)):
        f = [330.0 * mult * r * (1 + 0.006 * math.sin(TAU * vr * i / SR)) for i, r in enumerate(rise)]
        out = add(out, scale(osc_sweep("sine", f, rng.random()), a))
    out = mul(out, env_pts([(0, 0), (0.14, 1.0), (0.55, 0.8), (0.85, 0)], n))
    swirl = svf(white(n, rng), env_pts([(0, 400.0), (0.5, 3200.0), (0.85, 1800.0)], n), 4.0, "bp")
    swirl = mul(swirl, env_pts([(0, 0), (0.3, 1), (0.85, 0)], n))
    return reverb(add(scale(out, 0.35), scale(swirl, 0.5)), room=0.7, damp=0.3, wet=0.35)


@sound("heal", "SFX", "Warm F-major FM arpeggio (F5-A5-C6-F6) over a soft sine pad with high twinkles, reverb.")
def heal(rng):
    n = ns(0.85)
    out = [0.0] * n
    for k, name in enumerate(("F5", "A5", "C6", "F6")):
        st = ns(0.075 * k)
        place(out, fm_bell(hz(name), n - st, ratio=1.0, index=0.6, tau=0.35, attack=0.006), st, 0.45)
    pad = add(osc("sine", hz("F4"), n), scale(osc("sine", hz("C5"), n), 0.7), scale(osc("tri", hz("A4"), n), 0.4))
    out = add(out, scale(mul(pad, env_pts([(0, 0), (0.15, 0.6), (0.5, 0.45), (0.85, 0)], n)), 0.35))
    for _ in range(5):
        m = ns(0.04)
        tw = mul(osc("sine", 2500.0 + 2500.0 * rng.random(), m), env_exp(m, 0.012, 0.002))
        place(out, tw, ns(0.15 + 0.45 * rng.random()), 0.08)
    return reverb(out, room=0.65, damp=0.4, wet=0.3)


@sound("downed", "SFX", "Falling triangle/saw tone G4->G2 with wobble and closing filter, then a body-fall thud.")
def downed(rng):
    n = ns(1.0)
    m = ns(0.75)
    f = [v * (1 + 0.012 * math.sin(TAU * 6.0 * i / SR)) for i, v in enumerate(glide(392.0, 98.0, m))]
    tone = add(osc_sweep("tri", f), scale(osc_sweep("saw", f), 0.25))
    tone = svf(tone, env_pts([(0, 2400.0), (0.75, 300.0)], m), 0.9)
    tone = mul(tone, env_pts([(0, 0), (0.02, 1.0), (0.45, 0.8), (0.75, 0)], m))
    out = [0.0] * n
    place(out, tone, 0, 0.7)
    st = ns(0.58)
    m2 = n - st
    thud = add(mul(osc_sweep("sine", sweep_exp(95.0, 40.0, m2, 0.04)), env_exp(m2, 0.14, 0.001)),
               scale(mul(svf(white(m2, rng), 600.0, 0.7), env_exp(m2, 0.05, 0.001)), 0.7))
    place(out, thud, st, 0.9)
    return out


@sound("step", "SFX", "Soft deck footstep: 100->60 Hz sine thump, low-passed scuff, faint metallic tick.", peak_db=-6.0)
def step(rng):
    n = ns(0.14)
    thump = mul(osc_sweep("sine", sweep_exp(100.0, 60.0, n, 0.015)), env_exp(n, 0.03, 0.001))
    scuff = mul(svf(white(n, rng), 900.0, 0.7), env_exp(n, 0.02, 0.0015))
    tick = mul(svf(white(n, rng), 4200.0, 2.0, "bp"), env_exp(n, 0.006, 0.0003))
    return add(thump, scale(scuff, 0.6), scale(tick, 0.25))


# ---- conversation reactions ------------------------------------------------------
@sound("infl_up", "UI", "Companion approves: two warm rising FM chimes (E5, B5) over a soft sine fifth.")
def infl_up(rng):
    n = ns(0.6)
    out = [0.0] * n
    for start, f, tau in ((0.0, 659.25, 0.18), (0.09, 987.77, 0.3)):
        st = ns(start)
        place(out, fm_bell(f, n - st, ratio=2.0, index=0.9, tau=tau), st, 0.8)
    pad = mul(add(osc("sine", 329.63, n), scale(osc("sine", 493.88, n), 0.5)), env_pts([(0, 0), (0.05, 0.3), (0.6, 0)], n))
    return reverb(add(out, scale(pad, 0.4)), room=0.4, damp=0.45, wet=0.2)


@sound("infl_down", "UI", "Companion disapproves: two muted falling triangle notes (D5, A4), low-passed.")
def infl_down(rng):
    n = ns(0.55)
    out = [0.0] * n
    for start, f in ((0.0, 587.33), (0.13, 440.0)):
        m = ns(0.32)
        t = mul(add(osc("tri", f, m), scale(osc("tri", f * 1.006, m, 0.3), 0.6)), env_exp(m, 0.09, 0.004))
        place(out, lp1(t, 1800.0), ns(start), 0.8)
    return reverb(out, room=0.35, damp=0.5, wet=0.15)


@sound("align_mercy", "UI", "Mercy shift: bright major FM bell chord (G5 B5 D6) blooming upward, airy reverb.")
def align_mercy(rng):
    n = ns(0.95)
    out = [0.0] * n
    for k, name in enumerate(("G5", "B5", "D6")):
        st = ns(0.04 * k)
        place(out, fm_bell(hz(name), n - st, ratio=3.0, index=1.1, tau=0.45), st, 0.6)
    shimmer = mul(svf(white(n, rng), 7000.0, 0.8, "hp"), env_pts([(0, 0), (0.15, 1.0), (0.9, 0)], n))
    return reverb(add(out, scale(shimmer, 0.04)), room=0.7, damp=0.3, wet=0.35)


@sound("align_dominion", "UI", "Dominion shift: low minor saw sting (C3 Eb3 G3) under a closing filter with a sub thud.")
def align_dominion(rng):
    n = ns(0.9)
    chord = [0.0] * n
    for name in ("C3", "Eb3", "G3"):
        f = hz(name)
        chord = add(chord, osc("saw", f * 0.996, n, rng.random()), osc("saw", f * 1.004, n, rng.random()))
    chord = svf(chord, sweep_exp(2400.0, 380.0, n, 0.25), 1.2)
    chord = mul(chord, env_pts([(0, 0), (0.01, 1.0), (0.3, 0.6), (0.9, 0)], n))
    sub = mul(osc_sweep("sine", sweep_exp(90.0, 45.0, n, 0.1)), env_exp(n, 0.18, 0.002))
    return reverb(add(scale(chord, 0.5), scale(sub, 0.7)), room=0.5, damp=0.5, wet=0.2)


@sound("pa_chime", "SFX", "Ship PA chime before an announcement: three soft FM bells G5-E5-C5 with a hall reverb.")
def pa_chime(rng):
    n = ns(1.15)
    out = [0.0] * n
    for start, name in ((0.0, "G5"), (0.2, "E5"), (0.4, "C5")):
        st = ns(start)
        place(out, fm_bell(hz(name), n - st, ratio=2.0, index=0.6, tau=0.35), st, 0.7)
    return reverb(lp1(out, 5000.0), room=0.75, damp=0.4, wet=0.35)


# ---- alien-language voices -----------------------------------------------------
# Conversations are "voiced" like the old d20 space RPGs: lines are babbled in a
# made-up language from banks of short synthesised syllables. Each syllable is
# a consonant onset (noise burst, plosive, nasal, liquid glide or nothing) into
# a vowel or diphthong, made by running a glottal source (band-limited saw or
# pulse with a pitch contour, jitter and breath noise) through three band-pass
# formant filters. GameAudio strings syllables together at the line's pace and
# varies their pitch, so no two lines repeat a pattern.
#   hlo  human, low voice         hhi  human, high voice
#   syn  Tav-7 (stepped pitch, sample-and-hold, bit-crush, servo chirps)
#   wrd  WARDEN (monotone, sub-octave, ring-modulated, metallic comb + room)
VOWELS = {"a": (730, 1220, 2600), "e": (420, 2000, 2560), "i": (300, 2280, 3000),
          "o": (480, 820, 2700), "u": (330, 760, 2450), "y": (360, 1650, 2400)}
VOICE_BANKS = {
    # count, f0 range, syllable length range, formant scale, vowel pool, onset pool
    "hlo": (14, (105.0, 125.0), (0.13, 0.22), 1.0, "aaoouei", ["k", "g", "r", "m", "d", "h", "", "", "sh", "t", "n", "b"]),
    "hhi": (14, (190.0, 230.0), (0.11, 0.19), 1.15, "aeeiiyo", ["s", "t", "l", "n", "", "", "k", "m", "r", "sh", "f", "d"]),
    "syn": (12, (140.0, 140.0), (0.09, 0.16), 1.08, "eeiiay", ["t", "k", "p", "d", "", "s", "t", "k", "b", "n"]),
    "wrd": (12, (82.0, 82.0), (0.18, 0.28), 0.92, "ooaauu", ["m", "n", "d", "g", "", "k", "r", "", "h", "b"]),
}


def _formants(src, f1, f2, f3, q=(8.0, 10.0, 9.0), gains=(1.0, 0.5, 0.25)):
    out = add(scale(svf(src, f1, q[0], "bp"), gains[0]), scale(svf(src, f2, q[1], "bp"), gains[1]),
              scale(svf(src, f3, q[2], "bp"), gains[2]))
    return add(out, scale(lp1(src, 300.0), 0.12))


def voice_syllable(rng, bank, i):
    count, f0r, dur_r, fscale, vpool, opool = VOICE_BANKS[bank]
    dur = dur_r[0] + (dur_r[1] - dur_r[0]) * rng.random()
    tail = 0.05 if bank == "wrd" else 0.02
    n = ns(dur + tail)
    nv = ns(dur)
    onset = opool[i % len(opool)] if i < len(opool) else opool[int(rng.random() * len(opool))]
    v0 = vpool[int(rng.random() * len(vpool))]
    v1 = vpool[int(rng.random() * len(vpool))] if rng.random() < 0.35 else v0
    # --- pitch: a gentle fall, sometimes a rise; jitter and a slow wobble
    f0 = f0r[0] + (f0r[1] - f0r[0]) * rng.random()
    rise = rng.random() < 0.25
    c0, c1 = (0.97, 1.04) if rise else (1.03, 0.95)
    if bank == "wrd":
        c0, c1 = 1.0, 0.99
    if bank == "syn":
        # three stepped pitch levels per syllable, like a vocoder slip
        steps = [f0 * s for s in (1.0, 1.12 if rise else 0.9, 1.06)]
        f = [steps[min(2, j * 3 // nv)] for j in range(nv)]
    else:
        f = [f0 * (c0 + (c1 - c0) * j / nv) * (1.0 + 0.008 * math.sin(TAU * 5.3 * j / SR)) for j in range(nv)]
    src = osc_sweep("square" if bank == "syn" else "saw", f, rng.random())
    if bank == "wrd":
        src = add(src, scale(osc_sweep("square", [v * 0.5 for v in f], rng.random()), 0.6))
    src = add(src, scale(white(nv, rng), 0.06))
    # --- formant glide (diphthong), with liquid onsets bending the start
    a, b = VOWELS[v0], VOWELS[v1]
    fa = [v * fscale for v in a]
    fb = [v * fscale for v in b]
    if onset == "l":
        fa = [320 * fscale, 1050 * fscale, fa[2]]
    elif onset == "r":
        fa = [fa[0], fa[1] * 0.85, 1650 * fscale]
    gl = min(nv - 1, ns(0.06 if onset in ("l", "r") else 0.03))
    def track(k):
        # onset formant -> vowel target over gl samples, then glide to the
        # second vowel (a diphthong) over the rest
        mid = a[k] * fscale
        lst = [0.0] * nv
        for j in range(nv):
            if j < gl:
                lst[j] = fa[k] + (mid - fa[k]) * (j / max(1, gl))
            else:
                lst[j] = mid + (fb[k] - mid) * ((j - gl) / max(1, nv - gl))
        return lst
    vowel = _formants(src, track(0), track(1), track(2))
    att = 0.012 if onset in ("", "h", "l", "r", "m", "n") else 0.006
    vowel = mul(vowel, env_pts([(0.0, 0.0), (att, 1.0), (dur * 0.6, 0.85), (dur, 0.0)], nv))
    out = [0.0] * n
    # --- consonant onset
    con_len = 0.0
    if onset in ("s", "sh", "f", "h"):
        con_len = {"s": 0.055, "sh": 0.06, "f": 0.045, "h": 0.04}[onset]
        m = ns(con_len)
        if onset == "h":
            c = _formants(white(m, rng), fa[0], fa[1], fa[2], q=(3.0, 4.0, 4.0))
            g = 0.35
        else:
            fc = {"s": 5200.0, "sh": 2900.0, "f": 3800.0}[onset]
            c = svf(white(m, rng), fc * fscale, 2.2 if onset != "f" else 0.9, "bp")
            g = {"s": 0.32, "sh": 0.38, "f": 0.15}[onset]
        c = mul(c, env_pts([(0, 0), (con_len * 0.3, 1.0), (con_len, 0.2)], m))
        place(out, c, 0, g)
    elif onset in ("t", "k", "p"):
        con_len = 0.025
        m = ns(0.018)
        fc = {"t": 4000.0, "k": 1900.0, "p": 900.0}[onset]
        c = mul(svf(white(m, rng), fc, 1.6, "bp"), env_exp(m, 0.006, 0.0005))
        place(out, c, 0, 0.55)
    elif onset in ("b", "d", "g"):
        con_len = 0.015
        m = ns(0.03)
        thump = mul(osc_sweep("sine", sweep_exp(180.0, 110.0, m, 0.01)), env_exp(m, 0.01, 0.001))
        burst = mul(svf(white(m, rng), {"b": 700.0, "d": 3000.0, "g": 1600.0}[onset], 1.4, "bp"), env_exp(m, 0.004, 0.0005))
        place(out, add(thump, scale(burst, 0.5)), 0, 0.5)
    elif onset in ("m", "n"):
        con_len = 0.045
        m = ns(con_len)
        hum = lp1(osc_sweep("saw", [f[0]] * m, 0.0), 380.0 if onset == "m" else 520.0)
        place(out, mul(hum, env_pts([(0, 0), (0.01, 1.0), (con_len, 0.6)], m)), 0, 0.9)
    place(out, vowel, ns(max(0.0, con_len - 0.008)))
    out = out[:n]
    # --- character processing
    if bank == "syn":
        held = out[:]
        for j in range(len(held)):
            held[j] = out[j - (j % 3)]
        out = [round(v * 16.0) / 16.0 for v in scale(held, 1.0 / peak(held))]
        if rng.random() < 0.4:
            m = ns(0.03)
            chirp = mul(osc_sweep("sine", glide(2400.0, 3200.0, m)), env_pts([(0, 0), (0.005, 1), (0.03, 0)], m))
            place(out, chirp, len(out) - m - ns(0.01), 0.12)
    elif bank == "wrd":
        out = [v * (0.4 + 0.6 * math.sin(TAU * 47.0 * j / SR)) for j, v in enumerate(out)]
        out = echo(out, 1.0 / 82.0, fb=0.55, wet=0.5, damp=0.25)
        out = reverb(out, room=0.45, damp=0.3, wet=0.2)
    return out


def _voice_entry(bank, i):
    sid = "vox_%s_%02d" % (bank, i + 1)
    names = {"hlo": "low human voice", "hhi": "high human voice", "syn": "synthetic voice (Tav-7)", "wrd": "WARDEN voice"}
    desc = "Babble syllable %d, %s: glottal source through three gliding formant filters with a consonant onset." % (i + 1, names[bank])
    sound(sid, "Voice", desc, rate=LOOP_RATE, peak_db=-4.0)(lambda rng: voice_syllable(rng, bank, i))


for _bank, _spec in VOICE_BANKS.items():
    for _i in range(_spec[0]):
        _voice_entry(_bank, _i)


# ================================================================= loop engine
class Loop:
    """Circular multi-bus buffer measured in bars and beats (4/4)."""

    def __init__(self, bpm, bars, rng, beats=4):
        self.bpm = bpm
        self.bars = bars
        self.beats = beats
        self.spb = 60.0 / bpm
        self.n = int(round(bars * beats * self.spb * SR))
        self.rng = rng
        self.bus = {}

    def at(self, bar, beat=0.0):
        """Sample index of a 1-based bar and 0-based beat."""
        return int(round(((bar - 1) * self.beats + beat) * self.spb * SR))

    def secs(self, beats):
        return beats * self.spb

    def get(self, name):
        if name not in self.bus:
            self.bus[name] = [0.0] * self.n
        return self.bus[name]

    def put(self, name, sig, start, gain=1.0):
        """Mix sig into a bus, wrapping anything past the loop end to the start."""
        b = self.get(name)
        n = self.n
        start %= n
        i = 0
        while i < len(sig):
            seg = min(len(sig) - i, n - start)
            b[start:start + seg] = [a + v * gain for a, v in zip(b[start:start + seg], sig[i:i + seg])]
            i += seg
            start = 0


def notes_from_chords(prog, beats=4):
    """[(bar, beat, len_beats, 'A2 E3 ...')] -> [(midi, start_beat, len_beats)],
    holding tones common to consecutive chords instead of re-striking them."""
    out = []
    held = {}
    for bar, beat, length, names in prog:
        start = (bar - 1) * beats + beat
        tones = {midi(t) for t in names.split()}
        for m in list(held):
            if m not in tones or held[m][0] + held[m][1] != start:
                out.append((m, held[m][0], held[m][1]))
                del held[m]
        for m in tones:
            if m in held:
                held[m] = (held[m][0], held[m][1] + length)
            else:
                held[m] = (start, length)
    for m, (s, ln) in held.items():
        out.append((m, s, ln))
    return sorted(out, key=lambda e: (e[1], e[0]))


def chord_at(prog, beat_abs, beats=4):
    cur = prog[0][3]
    for bar, beat, _length, names in prog:
        if (bar - 1) * beats + beat <= beat_abs + 1e-6:
            cur = names
    return sorted(midi(t) for t in cur.split())


# ---- instruments (each returns one rendered note) ----------------------------------
def inst_pad(f, dur, rng, attack=1.0, release=1.6, shape="saw", voices=3, detune=0.006):
    n = ns(dur + release)
    out = [0.0] * n
    for v in range(voices):
        fv = f * (1.0 + (v - (voices - 1) * 0.5) * detune)
        t = table(shape, fv)
        inc = fv * TBL / SR
        p = rng.random() * TBL
        out = [o + t[int(p + i * inc) & MASK] for i, o in enumerate(out)]
    a = min(attack, dur * 0.9)
    env = env_pts([(0, 0), (a, 1.0), (dur, 0.85), (dur + release, 0.0)], n)
    return [o * e / voices for o, e in zip(out, env)]


def inst_bass(f, dur, shape="saw", cut_hi=1200.0, cut_lo=180.0, ctau=0.12, q=1.1, sub=0.6,
              attack=0.004, release=0.05, k=0.0):
    n = ns(dur + release)
    x = add(osc(shape, f, n), scale(osc("sine", f, n), sub))
    fc = [cut_lo + (cut_hi - cut_lo) * math.exp(-i / (ctau * SR)) for i in range(n)]
    x = mul(svf(x, fc, q), env_pts([(0, 0), (attack, 1.0), (dur, 0.8), (dur + release, 0.0)], n))
    return drive(x, k) if k > 0 else x


def inst_pluck(f, dur, shape="tri", tau=0.25, cutoff=None, attack=0.003, release=0.06):
    n = ns(dur + release)
    x = mul(osc(shape, f, n), env_exp(n, tau, attack))
    x = mul(x, env_pts([(0, 1.0), (dur, 1.0), (dur + release, 0.0)], n))
    return lp1(x, cutoff) if cutoff else x


def inst_lead(f, dur, shape="tri", attack=0.06, release=0.35, vib=5.0, depth=0.006, vib_delay=0.25, cutoff=None):
    n = ns(dur + release)
    w = TAU * vib / SR
    d0 = ns(vib_delay)
    ramp = max(1, ns(0.3))
    fr = [f * (1.0 + depth * min(1.0, max(0, i - d0) / ramp) * math.sin(w * i)) for i in range(n)]
    x = mul(osc_sweep(shape, fr, ref=f * 1.02), env_pts([(0, 0), (attack, 1.0), (dur, 0.8), (dur + release, 0.0)], n))
    return lp1(x, cutoff) if cutoff else x


# ---- drums (noise bursts and pitched sines) ---------------------------------------------
def drum_kick(rng, f0=150.0, f1=45.0, ptau=0.03, tau=0.2, click=0.25, dur=0.5):
    n = ns(dur)
    body = mul(osc_sweep("sine", sweep_exp(f0, f1, n, ptau)), env_exp(n, tau, 0.001))
    ck = mul(svf(white(n, rng), 2500.0, 0.7, "bp"), env_exp(n, 0.004, 0.0002))
    return fade_out(add(body, scale(ck, click)), 0.03)


def drum_snare(rng, tone=185.0, ntau=0.11, ttau=0.05, fc=1900.0, dur=0.35, body=0.6):
    n = ns(dur)
    t = mul(osc_sweep("tri", sweep_exp(tone * 1.6, tone, n, 0.01)), env_exp(n, ttau, 0.001))
    nz = mul(svf(white(n, rng), fc, 0.6, "bp"), env_exp(n, ntau, 0.001))
    return fade_out(add(scale(t, body), nz), 0.03)


def drum_hat(rng, tau=0.03, fc=7000.0, dur=None):
    n = ns(dur or tau * 6)
    return fade_out(mul(svf(white(n, rng), fc, 0.8, "hp"), env_exp(n, tau, 0.0008)), 0.01)


def drum_shaker(rng, dur=0.12):
    n = ns(dur)
    x = mul(svf(white(n, rng), 5500.0, 1.2, "bp"), env_pts([(0, 0), (0.012, 1.0), (dur, 0.0)], n))
    return mul(x, env_exp(n, 0.05, 0.008))


def drum_rim(rng):
    n = ns(0.08)
    a = mul(svf(white(n, rng), 1500.0, 3.0, "bp"), env_exp(n, 0.012, 0.0004))
    b = mul(osc("sine", 820.0, n), env_exp(n, 0.018, 0.0004))
    return fade_out(add(a, scale(b, 0.5)), 0.01)


def drum_tom(rng, f0, tau=0.3, dur=0.6):
    n = ns(dur)
    body = mul(osc_sweep("sine", sweep_exp(f0 * 1.5, f0, n, 0.04)), env_exp(n, tau, 0.001))
    nz = mul(svf(white(n, rng), 1200.0, 0.7), env_exp(n, 0.02, 0.0005))
    return fade_out(add(body, scale(nz, 0.3)), 0.03)


def drum_crash(rng, dur=2.0, tau=0.7):
    n = ns(dur)
    x = add(svf(white(n, rng), 4500.0, 0.7, "hp"), scale(svf(white(n, rng), 6500.0, 1.5, "bp"), 0.6))
    return fade_out(mul(x, env_exp(n, tau, 0.002)), 0.2)


def riser(rng, dur, f0=500.0, f1=4000.0):
    """Reverse-swell noise that ends on the beat it is placed before."""
    n = ns(dur)
    x = svf(white(n, rng), glide(f0, f1, n), 1.5, "bp")
    x = mul(x, [(i / n) ** 2.5 for i in range(n)])
    return fade_out(x, 0.012)


def mixdown(lp, spec, room=0.85, damp=0.4, rv_level=0.6, delay=None, drive_k=1.2):
    """Balance buses by active RMS, add echo + reverb returns, master the loop.

    spec: {bus: (rms_level, reverb_send, delay_send)}. All effects run through
    loop_apply so their tails cross the seam."""
    n = lp.n
    master = [0.0] * n
    rsend = [0.0] * n
    dsend = [0.0] * n
    for name, (level, rs, ds) in spec.items():
        if name not in lp.bus:
            continue
        x = fit(lp.bus[name], level)
        master = [a + b for a, b in zip(master, x)]
        if rs:
            rsend = [a + b * rs for a, b in zip(rsend, x)]
        if ds:
            dsend = [a + b * ds for a, b in zip(dsend, x)]
    if delay and any(dsend):
        t, fb, dmp = delay
        d = loop_apply(dsend, lambda b: echo(b, t, fb=fb, wet=1.0, damp=dmp, dry=0.0), 8.0)
        master = [a + b for a, b in zip(master, d)]
        rsend = [a + b * 0.5 for a, b in zip(rsend, d)]
    if any(rsend):
        r = loop_apply(rsend, lambda b: reverb(b, room=room, damp=damp, wet=1.0, dry=0.0), 6.0)
        r = fit(r, active_rms(rsend) * rv_level)
        master = [a + b for a, b in zip(master, r)]
    master = loop_apply(master, lambda b: hp1(b, 25.0), 1.0)
    master = scale(master, 1.0 / peak(master))
    return drive(master, drive_k)


# ================================================================== ambience
@sound("amb_ship", "Ambience loop",
       "Loop-locked 55 Hz hum with harmonics and a 0.25 Hz beating twin, filtered noise rumble and air-handler hiss, "
       "pump chugs, servo whirs, relay clicks, a distant hull ping and a faint electrical whine.",
       rate=LOOP_RATE, loop=True)
def amb_ship(rng):
    lp = Loop(60.0, 6, rng)  # 6 bars of 4 beats at 60 bpm = 24 s
    n = lp.n
    hum = [0.0] * n
    for f, a in ((55.0, 1.0), (110.0, 0.45), (165.0, 0.22), (220.0, 0.1), (330.0, 0.04), (55.25, 0.55), (110.5, 0.2)):
        hum = add(hum, scale(loop_osc("sine", f, n, rng.random()), a))
    hum = mul(hum, lfo(n, 2, 0.75, 1.0))
    lp.put("hum", hum, 0)
    rumble = loop_apply(white(n, rng), lambda b: svf(svf(b, 140.0, 0.7), 140.0, 0.7), 2.0)
    lp.put("rumble", mul(rumble, lfo(n, 3, 0.6, 1.0, 1.0)), 0)
    air = loop_svf(white(n, rng), lfo(n, 1, 650.0, 1400.0), 0.8, "bp", 1.0)
    lp.put("air", mul(air, lfo(n, 2, 0.4, 1.0, -0.5)), 0)
    whine = mul(loop_osc("sine", 1200.0, n), lfo(n, 3, 0.0, 1.0))
    lp.put("whine", whine, 0)
    # machinery events (positions in beats = seconds at 60 bpm)
    for t0, g in ((1.0, 1.0), (7.0, 0.8), (13.0, 1.0), (19.0, 0.7)):
        for dt, g2 in ((0.0, 1.0), (0.55, 0.7)):
            m = ns(0.5)
            chug = add(mul(svf(white(m, rng), 500.0, 0.8), env_pts([(0, 0), (0.03, 1.0), (0.5, 0.0)], m)),
                       scale(mul(osc_sweep("sine", sweep_exp(72.0, 50.0, m, 0.08)), env_exp(m, 0.12, 0.01)), 0.8))
            lp.put("events", chug, lp.at(1, t0 + dt), g * g2)
    for t0 in (4.6, 15.8):
        m = ns(1.4)
        wh = svf(osc_sweep("square", env_pts([(0, 300.0), (0.9, 440.0), (1.4, 420.0)], m)), 700.0, 1.5, "bp")
        lp.put("events", mul(wh, env_pts([(0, 0), (0.2, 1.0), (1.1, 0.8), (1.4, 0.0)], m)), lp.at(1, t0), 0.18)
    for _ in range(7):
        m = ns(0.02)
        click = mul(svf(white(m, rng), 3500.0, 1.5, "bp"), env_exp(m, 0.003, 0.0003))
        lp.put("events", click, lp.at(1, rng.random() * 24.0), 0.25 + 0.2 * rng.random())
    m = ns(2.5)
    ping = [0.0] * m
    for f, a, tau in ((523.0, 1.0, 0.9), (789.0, 0.6, 0.7), (1190.0, 0.4, 0.5), (1655.0, 0.2, 0.35)):
        ping = add(ping, scale(mul(osc("sine", f, m, rng.random()), env_exp(m, tau, 0.004)), a))
    lp.put("events", fade_out(ping, 0.2), lp.at(1, 10.3), 0.12)
    spec = {"hum": (0.25, 0.0, 0), "rumble": (0.07, 0.3, 0), "air": (0.025, 0.3, 0),
            "whine": (0.004, 0.0, 0), "events": (0.05, 0.6, 0)}
    return mixdown(lp, spec, room=0.75, damp=0.5, rv_level=0.5, drive_k=1.0)


# ===================================================================== music
@sound("music_menu", "Music loop",
       "66 bpm D minor, 16 bars: slow detuned-saw pad with breathing filter, soft triangle bass, gapped FM-bell "
       "arpeggio through dotted-eighth echo, lonely sine lead, sparse bells, soft shaker/kick, big reverb.",
       rate=LOOP_RATE, loop=True)
def music_menu(rng):
    lp = Loop(66.0, 16, rng)
    prog = [
        (1, 0, 4, "D3 A3 E4 F4"), (2, 0, 4, "Bb2 F3 A3 D4"), (3, 0, 4, "G2 D3 F3 Bb3"),
        (4, 0, 2, "A2 E3 A3 D4"), (4, 2, 2, "A2 E3 A3 C#4"),
        (5, 0, 4, "D3 A3 D4 F4"), (6, 0, 4, "C3 F3 A3 C4"), (7, 0, 4, "Bb2 F3 A3 E4"),
        (8, 0, 2, "A2 E3 G3 D4"), (8, 2, 2, "A2 E3 G3 C#4"),
        (9, 0, 4, "G2 D3 F3 A3 Bb3"), (10, 0, 4, "F2 D3 F3 A3"), (11, 0, 4, "Eb3 G3 Bb3 D4"),
        (12, 0, 2, "A2 E3 A3 D4"), (12, 2, 2, "A2 E3 G3 C#4"),
        (13, 0, 4, "Bb2 F3 A3 D4"), (14, 0, 4, "G2 D3 E3 Bb3"), (15, 0, 4, "A2 D3 F3 A3"),
        (16, 0, 4, "A2 E3 G3 C#4"),
    ]
    for m, st, ln in notes_from_chords(prog):
        lp.put("pad", inst_pad(mhz(m), lp.secs(ln), rng, attack=1.4, release=2.2), int(round(st * lp.spb * SR)))
    for bar in range(1, 17):
        root = chord_at(prog, (bar - 1) * 4)[0] - 12
        lp.put("bass", inst_bass(mhz(root), lp.secs(3.6), shape="tri", cut_hi=700.0, cut_lo=320.0, ctau=0.4,
                                 sub=0.8, attack=0.08, release=0.5), lp.at(bar))
    pattern = (0, 1, 2, 3, 2, 1, 2, 3)
    for bar in range(5, 17):
        for step8 in range(8):
            if rng.random() < 0.25:
                continue
            tones = [t + 12 for t in chord_at(prog, (bar - 1) * 4 + step8 * 0.5)[1:]]
            m = tones[pattern[step8] % len(tones)]
            note = fm_bell(mhz(m), ns(2.2), ratio=2.0, index=1.0, tau=0.55)
            lp.put("arp", fade_out(note, 0.1), lp.at(bar, step8 * 0.5), 0.7 + 0.3 * rng.random())
    melody = [
        (9, 0, 1.5, "A4"), (9, 1.5, 0.5, "Bb4"), (9, 2, 1, "A4"), (9, 3, 1, "G4"),
        (10, 0, 2, "F4"), (10, 2, 1, "E4"), (10, 3, 1, "D4"),
        (11, 0, 2, "G4"), (11, 2, 1, "Bb4"), (11, 3, 1, "D5"),
        (12, 0, 3, "C#5"), (12, 3, 1, "A4"),
        (13, 0, 1.5, "D5"), (13, 1.5, 0.5, "F5"), (13, 2, 1, "E5"), (13, 3, 1, "D5"),
        (14, 0, 2, "Bb4"), (14, 2, 1, "A4"), (14, 3, 1, "G4"),
        (15, 0, 3, "A4"), (15, 3, 1, "F4"),
        (16, 0, 2, "E4"), (16, 2, 1, "C#4"), (16, 3, 1, "E4"),
        (1, 0, 3, "D4"),
    ]
    for bar, beat, ln, name in melody:
        x = inst_lead(hz(name), lp.secs(ln) * 0.95, shape="sine", attack=0.12, release=0.9, vib=4.5, depth=0.005)
        lp.put("lead", add(x, scale(inst_lead(hz(name) * 2.0, lp.secs(ln) * 0.95, shape="sine", attack=0.12,
                                              release=0.9, vib=4.5, depth=0.005), 0.12)), lp.at(bar, beat))
    for bar, beat, name in ((1, 0, "A5"), (2, 2, "E5"), (3, 0, "F5"), (4, 2, "E5"),
                            (13, 2, "D6"), (14, 2, "A5"), (15, 2, "F5"), (16, 2, "E5")):
        lp.put("bell", fade_out(fm_bell(hz(name), ns(3.5), ratio=3.5, index=1.4, tau=1.0), 0.2), lp.at(bar, beat))
    kick = drum_kick(rng, f0=95.0, f1=44.0, tau=0.25, click=0.05)
    shakers = [drum_shaker(rng) for _ in range(4)]
    for bar in range(5, 17):
        lp.put("drums", kick, lp.at(bar), 1.0)
        if bar % 2 == 0:
            lp.put("drums", kick, lp.at(bar, 2.5), 0.6)
        for k in range(4):
            lp.put("drums", shakers[k], lp.at(bar, k + 0.5), 0.12 + 0.05 * (k % 2))
    for bar in (8, 16):
        lp.put("drums", riser(rng, lp.secs(2), 400.0, 3000.0), lp.at(bar, 2), 0.25)
    lp.bus["pad"] = loop_svf(lp.bus["pad"], lfo(lp.n, 2, 700.0, 1700.0, -1.5), 0.8, "lp", 2.0)
    spec = {"pad": (0.1, 0.5, 0), "bass": (0.07, 0.1, 0), "arp": (0.045, 0.5, 0.6),
            "lead": (0.075, 0.6, 0.35), "bell": (0.03, 0.8, 0.3), "drums": (0.045, 0.25, 0)}
    return mixdown(lp, spec, room=0.9, damp=0.4, rv_level=0.75, delay=(lp.secs(0.75), 0.45, 0.4), drive_k=1.0)


@sound("music_explore", "Music loop",
       "100 bpm E minor, 24 bars: dark saw pad, muted saw bass pulsing in eighths, 16th triangle arpeggio under a "
       "slowly opening filter, soft kick/rim/hats, sonar-ping bells and a sparse triangle lead.",
       rate=LOOP_RATE, loop=True)
def music_explore(rng):
    lp = Loop(100.0, 24, rng)
    prog = [
        (1, 0, 8, "E3 B3 F#4 G4"), (3, 0, 8, "C3 G3 B3 E4"), (5, 0, 8, "A2 E3 G3 C4"),
        (7, 0, 4, "B2 F#3 A3 E4"), (8, 0, 4, "B2 F#3 A3 D#4"),
        (9, 0, 8, "E3 B3 E4 G4"), (11, 0, 8, "C3 G3 B3 F#4"), (13, 0, 8, "A2 E3 G3 B3 C4"),
        (15, 0, 4, "F2 C3 E3 B3"), (16, 0, 4, "B2 F#3 A3 D#4"),
        (17, 0, 8, "E3 G3 B3 F#4"), (19, 0, 8, "D3 G3 B3 D4"), (21, 0, 8, "C3 G3 B3 E4"),
        (23, 0, 4, "B2 E3 F#3 A3"), (24, 0, 4, "B2 D#3 F#3 A3"),
    ]
    for m, st, ln in notes_from_chords(prog):
        lp.put("pad", inst_pad(mhz(m), lp.secs(ln), rng, attack=1.2, release=1.5), int(round(st * lp.spb * SR)))
    accents = (1.0, 0.55, 0.8, 0.55, 0.95, 0.55, 0.8, 0.65)
    for bar in range(1, 25):
        for s8 in range(8):
            root = chord_at(prog, (bar - 1) * 4 + s8 * 0.5)[0]
            while root > midi("G2"):
                root -= 12
            if s8 == 6 and bar % 2 == 0:
                root += 12
            note = inst_bass(mhz(root), lp.secs(0.42), cut_hi=950.0, cut_lo=160.0, ctau=0.07, sub=0.7)
            lp.put("bass", note, lp.at(bar, s8 * 0.5), accents[s8])
    pattern = (0, 2, 1, 3, 2, 1, 3, 2, 0, 3, 1, 2, 3, 1, 2, 0)
    for bar in range(9, 25):
        for s16 in range(16):
            tones = [t + 12 for t in chord_at(prog, (bar - 1) * 4 + s16 * 0.25)[1:]]
            m = tones[pattern[s16] % len(tones)] + (12 if s16 in (4, 12) else 0)
            note = inst_pluck(mhz(m), lp.secs(0.22), shape="tri", tau=0.11)
            lp.put("arp", note, lp.at(bar, s16 * 0.25), 1.0 if s16 % 4 == 0 else 0.7)
    lp.bus["arp"] = loop_svf(lp.bus["arp"], lfo(lp.n, 1, 900.0, 3400.0, -math.pi / 2), 1.2, "lp", 2.0)
    kick = drum_kick(rng, f0=110.0, f1=42.0, tau=0.18, click=0.12)
    rim = drum_rim(rng)
    hats = [drum_hat(rng, tau=0.025) for _ in range(4)]
    for bar in range(1, 25):
        lp.put("drums", kick, lp.at(bar, 0), 1.0)
        lp.put("drums", kick, lp.at(bar, 2), 0.8)
        lp.put("drums", rim, lp.at(bar, 3), 0.45)
        if bar % 4 == 0:
            lp.put("drums", rim, lp.at(bar, 3.75), 0.25)
        for s8 in range(8):
            lp.put("drums", hats[s8 % 4], lp.at(bar, s8 * 0.5), 0.14 if s8 % 2 else 0.08)
        if bar > 16:
            for s16 in (1, 5, 9, 13):
                lp.put("drums", hats[s16 % 4], lp.at(bar, s16 * 0.25), 0.05)
    for bar in range(1, 25, 4):
        lp.put("bell", fade_out(fm_bell(hz("E6"), ns(3.0), ratio=1.41, index=1.2, tau=0.8), 0.2), lp.at(bar, 0.5))
    melody = [
        (17, 0, 3, "B4"), (18, 0, 1.5, "G4"), (18, 1.5, 0.5, "A4"), (18, 2, 2, "F#4"),
        (19, 0, 3, "D5"), (20, 0, 2, "B4"), (20, 2, 2, "A4"),
        (21, 0, 3, "G4"), (21, 3, 1, "E4"), (22, 0, 4, "B4"),
        (23, 0, 2, "A4"), (23, 2, 2, "F#4"), (24, 0, 3, "D#4"),
    ]
    for bar, beat, ln, name in melody:
        lp.put("lead", inst_lead(hz(name), lp.secs(ln) * 0.92, shape="tri", attack=0.05, release=0.5,
                                 vib=5.0, depth=0.006, cutoff=2500.0), lp.at(bar, beat))
    lp.bus["pad"] = loop_svf(lp.bus["pad"], lfo(lp.n, 3, 600.0, 1100.0), 0.8, "lp", 2.0)
    spec = {"pad": (0.09, 0.45, 0), "bass": (0.085, 0.05, 0), "arp": (0.035, 0.35, 0.5),
            "lead": (0.065, 0.5, 0.4), "bell": (0.025, 0.8, 0.6), "drums": (0.06, 0.15, 0)}
    return mixdown(lp, spec, room=0.82, damp=0.45, rv_level=0.6, delay=(lp.secs(0.75), 0.4, 0.45), drive_k=1.3)


@sound("music_tension", "Music loop",
       "72 bpm C minor, 16 bars: loop-locked C/G saw drone with breathing filter, dissonant clustered pads, sub bass, "
       "heartbeat kicks, pitched ticks, low toms, noise risers, a tritone glass arpeggio and minor-second bells.",
       rate=LOOP_RATE, loop=True)
def music_tension(rng):
    lp = Loop(72.0, 16, rng)
    n = lp.n
    drone = add(loop_osc("saw", hz("C2"), n, rng.random()), scale(loop_osc("square", hz("G2"), n, rng.random()), 0.4),
                scale(loop_osc("sine", hz("C1"), n), 0.8))
    lp.put("drone", loop_svf(drone, lfo(n, 2, 180.0, 650.0), 1.4, "lp", 2.0), 0)
    prog = [
        (1, 0, 8, "C3 G3 Db4 Eb4"), (3, 0, 8, "Ab2 Eb3 G3 C4"), (5, 0, 8, "F2 C3 Ab3 G4"),
        (7, 0, 4, "G2 D3 F3 Ab3"), (8, 0, 4, "G2 B2 F3 Ab3"),
        (9, 0, 8, "C3 Eb3 G3 D4"), (11, 0, 8, "Db3 F3 Ab3 C4"), (13, 0, 8, "B2 D3 F3 Ab3"),
        (15, 0, 8, "G2 B2 F3 Ab3"),
    ]
    for m, st, ln in notes_from_chords(prog):
        lp.put("pad", inst_pad(mhz(m), lp.secs(ln), rng, attack=2.2, release=3.0, detune=0.009),
               int(round(st * lp.spb * SR)))
    for bar in range(1, 17, 2):
        root = chord_at(prog, (bar - 1) * 4)[0]
        while root > midi("C2"):
            root -= 12
        lp.put("bass", inst_bass(mhz(root), lp.secs(7.0), shape="tri", cut_hi=400.0, cut_lo=220.0, ctau=0.5,
                                 sub=1.0, attack=0.3, release=1.0), lp.at(bar))
    kick = drum_kick(rng, f0=80.0, f1=38.0, tau=0.22, click=0.02, dur=0.6)
    for bar in range(5, 17):
        lp.put("drums", kick, lp.at(bar, 0), 1.0)
        lp.put("drums", kick, lp.at(bar, 0.4), 0.55)
    tick = [fade_out(mul(svf(white(ns(0.05), rng), 4200.0, 6.0, "bp"), env_exp(ns(0.05), 0.008, 0.0005)), 0.01)
            for _ in range(3)]
    for bar in range(1, 17):
        for s8 in range(8):
            if rng.random() < 0.5:
                continue
            lp.put("drums", tick[s8 % 3], lp.at(bar, s8 * 0.5), 0.12 + 0.1 * rng.random())
    tom = drum_tom(rng, 70.0, tau=0.5, dur=1.2)
    for bar in (1, 5, 9, 13):
        lp.put("drums", tom, lp.at(bar), 0.9)
        prev = bar - 1 if bar > 1 else 16
        lp.put("drums", riser(rng, lp.secs(2), 300.0, 2500.0), lp.at(prev, 2), 0.3)
    glass = ("C5", "Gb5", "B5", "F5")
    for bar in range(9, 17):
        for beat in range(4):
            if bar % 2 == 0 and beat == 3:
                continue
            note = fm_bell(hz(glass[(bar * 4 + beat) % 4]), ns(2.0), ratio=3.01, index=0.8, tau=0.5)
            lp.put("arp", fade_out(note, 0.1), lp.at(bar, beat), 0.8 if beat == 0 else 0.55)
    for bar in (3, 7, 11, 15):
        lp.put("bell", fade_out(fm_bell(hz("Eb6"), ns(4.0), ratio=3.5, index=1.5, tau=1.2), 0.2), lp.at(bar))
        lp.put("bell", fade_out(fm_bell(hz("D6"), ns(4.0), ratio=3.5, index=1.5, tau=1.2), 0.2), lp.at(bar, 1.5), 0.8)
    lp.bus["pad"] = loop_svf(lp.bus["pad"], lfo(n, 1, 450.0, 1100.0, 1.0), 0.9, "lp", 3.0)
    spec = {"drone": (0.07, 0.25, 0), "pad": (0.08, 0.6, 0), "bass": (0.07, 0.1, 0), "drums": (0.06, 0.35, 0),
            "arp": (0.03, 0.5, 0.7), "bell": (0.025, 0.9, 0.4)}
    return mixdown(lp, spec, room=0.92, damp=0.5, rv_level=0.8, delay=(lp.secs(1.5), 0.5, 0.5), drive_k=1.2)


@sound("music_combat", "Music loop",
       "140 bpm A minor, 32 bars: driving 16th saw bass with filter envelope, kick/snare/hat/tom/crash kit from noise "
       "and sine bursts, side-chain-ducked saw power-chord pad, square 16th arpeggio and a vibrato square lead.",
       rate=LOOP_RATE, loop=True)
def music_combat(rng):
    lp = Loop(140.0, 32, rng)
    n = lp.n
    cycle = ("A2 E3 A3 C4", "A2 E3 A3 C4", "F2 C3 F3 A3", "G2 D3 G3 B3",
             "A2 E3 A3 C4", "A2 E3 A3 C4", "D3 A3 D4 F4", "E2 B2 E3 G#3")
    prog = [(bar, 0, 4, cycle[(bar - 1) % 8]) for bar in range(1, 33)]
    for m, st, ln in notes_from_chords(prog):
        lp.put("pad", inst_pad(mhz(m), lp.secs(ln), rng, attack=0.08, release=0.4, detune=0.008),
               int(round(st * lp.spb * SR)))
    bass_pat = "x.xxx.xxx.xxo.xo"
    for bar in range(1, 33):
        root = chord_at(prog, (bar - 1) * 4)[0]
        while root > midi("A2"):
            root -= 12
        for s16, c in enumerate(bass_pat):
            if c == ".":
                continue
            m = root + (12 if c == "o" else 0)
            note = inst_bass(mhz(m), lp.secs(0.22), cut_hi=2400.0, cut_lo=220.0, ctau=0.05, q=1.4, sub=0.5, k=1.8)
            lp.put("bass", note, lp.at(bar, s16 * 0.25), 1.0 if s16 % 4 == 0 else 0.8)
    kick = drum_kick(rng, f0=160.0, f1=48.0, tau=0.16, click=0.35, dur=0.4)
    snare = drum_snare(rng, tone=190.0, ntau=0.12, fc=2200.0)
    hats = [drum_hat(rng, tau=0.022) for _ in range(4)]
    ohat = drum_hat(rng, tau=0.12, fc=6500.0, dur=0.4)
    crash = drum_crash(rng)
    toms = [drum_tom(rng, f, tau=0.18, dur=0.4) for f in (190.0, 160.0, 130.0, 105.0)]
    duck = [1.0] * n
    ramp, dtau, depth = ns(0.004), 0.11 * SR, 0.5
    for bar in range(1, 33):
        fill = bar % 8 == 0
        for s16 in (0, 6, 8, 11):
            p = lp.at(bar, s16 * 0.25)
            lp.put("drums", kick, p, 1.0)
            for j in range(ns(0.4)):
                g = 1.0 - depth * min(1.0, j / ramp) * math.exp(-max(0, j - ramp) / dtau)
                duck[(p + j) % n] = min(duck[(p + j) % n], g)
        lp.put("drums", snare, lp.at(bar, 1), 0.8)
        if not fill:
            lp.put("drums", snare, lp.at(bar, 3), 0.8)
        for s16 in range(0, 16, 2):
            if fill and s16 >= 12:
                continue
            lp.put("drums", hats[s16 // 2 % 4], lp.at(bar, s16 * 0.25), 0.3 if s16 % 4 else 0.18)
        if bar > 8:
            for s16 in range(1, 16, 2):
                if not (fill and s16 >= 12):
                    lp.put("drums", hats[s16 % 4], lp.at(bar, s16 * 0.25), 0.08)
        if bar % 2 == 0 and not fill:
            lp.put("drums", ohat, lp.at(bar, 3.5), 0.22)
        if fill:
            for k, tom in enumerate(toms):
                lp.put("drums", tom, lp.at(bar, 3 + k * 0.25), 0.85)
        if bar % 8 == 1:
            lp.put("drums", crash, lp.at(bar), 0.35)
    lp.bus["pad"] = mul(loop_apply(lp.bus["pad"], lambda b: svf(b, 1800.0, 0.9), 1.0), duck)
    arp_pat = (0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1, 2)
    for bar in list(range(9, 17)) + list(range(25, 33)):
        tones = [t + 12 for t in chord_at(prog, (bar - 1) * 4)[1:]]
        for s16 in range(16):
            m = tones[arp_pat[s16] % len(tones)] + (12 if arp_pat[s16] >= len(tones) else 0)
            note = inst_pluck(mhz(m), lp.secs(0.2), shape="square", tau=0.07, cutoff=3800.0)
            lp.put("arp", note, lp.at(bar, s16 * 0.25), 1.0 if s16 % 4 == 0 else 0.65)
    melody = [
        (0, 0, 1, "E5"), (0, 1, 1, "A5"), (0, 2, 0.5, "G5"), (0, 2.5, 0.5, "E5"), (0, 3, 1, "D5"),
        (1, 0, 1.5, "C5"), (1, 1.5, 0.5, "D5"), (1, 2, 2, "E5"),
        (2, 0, 1, "F5"), (2, 1, 1, "E5"), (2, 2, 1, "D5"), (2, 3, 1, "C5"),
        (3, 0, 1, "B4"), (3, 1, 1, "D5"), (3, 2, 2, "G5"),
        (4, 0, 1.5, "A5"), (4, 1.5, 0.5, "G5"), (4, 2, 1, "E5"), (4, 3, 1, "C5"),
        (5, 0, 2, "D5"), (5, 2, 1, "E5"), (5, 3, 1, "A4"),
        (6, 0, 1, "F5"), (6, 1, 1, "E5"), (6, 2, 1, "D5"), (6, 3, 1, "F5"),
        (7, 0, 3, "E5"), (7, 3, 1, "G#5"),
    ]
    for first, shape, g in ((17, "square", 1.0), (25, "saw", 0.8)):
        for off, beat, ln, name in melody:
            x = inst_lead(hz(name), lp.secs(ln) * 0.9, shape=shape, attack=0.01, release=0.12, vib=6.0,
                          depth=0.007, vib_delay=0.15, cutoff=3200.0)
            lp.put("lead", x, lp.at(first + off, beat), g)
    spec = {"drums": (0.12, 0.12, 0), "bass": (0.1, 0.0, 0), "pad": (0.07, 0.3, 0),
            "arp": (0.04, 0.25, 0.5), "lead": (0.075, 0.35, 0.3)}
    return mixdown(lp, spec, room=0.7, damp=0.5, rv_level=0.45, delay=(lp.secs(0.75), 0.3, 0.5), drive_k=1.8)


@sound("music_ending", "Music loop",
       "76 bpm D major, 16 bars: warm detuned pad, round bass with passing fifths, rising FM-bell arpeggio, "
       "major-key reprise of the menu theme on a sine/triangle lead, shaker, soft kick and brush snare, swells.",
       rate=LOOP_RATE, loop=True)
def music_ending(rng):
    lp = Loop(76.0, 16, rng)
    prog = [
        (1, 0, 4, "D3 A3 D4 F#4"), (2, 0, 4, "C#3 A3 C#4 E4"), (3, 0, 4, "B2 F#3 A3 D4"),
        (4, 0, 4, "G2 D3 A3 B3"), (5, 0, 4, "F#2 D3 A3 D4"), (6, 0, 4, "E3 G3 B3 D4"),
        (7, 0, 4, "G2 D3 F#3 B3"), (8, 0, 2, "A2 E3 A3 D4"), (8, 2, 2, "A2 E3 A3 C#4"),
        (9, 0, 4, "B2 F#3 A3 D4"), (10, 0, 4, "F#2 C#3 E3 A3"), (11, 0, 4, "G2 D3 F#3 B3"),
        (12, 0, 4, "F#2 A3 D4 F#4"), (13, 0, 4, "E2 B2 F#3 G3 D4"), (14, 0, 4, "G2 B2 D3 G3"),
        (15, 0, 4, "A2 E3 G3 D4"), (16, 0, 4, "A2 E3 G3 C#4"),
    ]
    for m, st, ln in notes_from_chords(prog):
        lp.put("pad", inst_pad(mhz(m), lp.secs(ln), rng, attack=0.9, release=1.8, detune=0.005),
               int(round(st * lp.spb * SR)))
    for bar in range(1, 17):
        root = chord_at(prog, (bar - 1) * 4)[0]
        while root > midi("D3"):
            root -= 12
        lp.put("bass", inst_bass(mhz(root), lp.secs(2.0), shape="tri", cut_hi=900.0, cut_lo=380.0, ctau=0.3,
                                 sub=0.9, attack=0.02, release=0.3), lp.at(bar))
        lp.put("bass", inst_bass(mhz(root + (7 if bar > 8 else 0)), lp.secs(1.4), shape="tri", cut_hi=800.0,
                                 cut_lo=380.0, ctau=0.3, sub=0.9, attack=0.02, release=0.3), lp.at(bar, 2), 0.8)
    for bar in range(1, 17):
        tones = chord_at(prog, (bar - 1) * 4)[1:]
        up = [t + 12 for t in tones] + [tones[0] + 24]
        seq = (0, 1, 2, 3, 4, 3, 2, 1)
        for s8 in range(8):
            m = up[seq[s8] % len(up)]
            note = fade_out(fm_bell(mhz(m), ns(1.6), ratio=1.0, index=0.9, tau=0.4), 0.1)
            lp.put("arp", note, lp.at(bar, s8 * 0.5), (0.5 if bar < 5 else 1.0) * (1.0 if s8 % 2 == 0 else 0.7))
    melody = [
        (5, 0, 1.5, "A4"), (5, 1.5, 0.5, "B4"), (5, 2, 1, "A4"), (5, 3, 1, "F#4"),
        (6, 0, 2, "G4"), (6, 2, 1, "F#4"), (6, 3, 1, "E4"),
        (7, 0, 1, "G4"), (7, 1, 1, "B4"), (7, 2, 2, "D5"),
        (8, 0, 3, "E5"), (8, 3, 1, "C#5"),
        (9, 0, 1.5, "D5"), (9, 1.5, 0.5, "F#5"), (9, 2, 1, "E5"), (9, 3, 1, "D5"),
        (10, 0, 2, "C#5"), (10, 2, 1, "A4"), (10, 3, 1, "C#5"),
        (11, 0, 1.5, "B4"), (11, 1.5, 0.5, "D5"), (11, 2, 1, "F#5"), (11, 3, 1, "E5"),
        (12, 0, 2, "D5"), (12, 2, 1, "A4"), (12, 3, 1, "F#4"),
        (13, 0, 1, "G4"), (13, 1, 1, "B4"), (13, 2, 1, "D5"), (13, 3, 1, "F#5"),
        (14, 0, 3, "G5"), (14, 3, 1, "F#5"),
        (15, 0, 2, "E5"), (15, 2, 1, "D5"), (15, 3, 1, "E5"),
        (16, 0, 3, "C#5"),
        (1, 0, 3, "D5"),
    ]
    for bar, beat, ln, name in melody:
        x = add(inst_lead(hz(name), lp.secs(ln) * 0.95, shape="sine", attack=0.08, release=0.7, vib=4.8, depth=0.005),
                scale(inst_lead(hz(name), lp.secs(ln) * 0.95, shape="tri", attack=0.08, release=0.7, vib=4.8,
                                depth=0.005, cutoff=2200.0), 0.5))
        lp.put("lead", x, lp.at(bar, beat))
    for bar, beat, name in ((1, 2, "F#5"), (2, 2, "E5"), (3, 2, "D5"), (4, 2, "A5")):
        lp.put("bell", fade_out(fm_bell(hz(name), ns(3.0), ratio=3.5, index=1.2, tau=0.9), 0.2), lp.at(bar, beat))
    kick = drum_kick(rng, f0=100.0, f1=46.0, tau=0.2, click=0.06)
    brush = drum_snare(rng, tone=210.0, ntau=0.16, ttau=0.03, fc=3200.0, body=0.25)
    shakers = [drum_shaker(rng) for _ in range(4)]
    for bar in range(1, 17):
        for s8 in range(8):
            lp.put("drums", shakers[s8 % 4], lp.at(bar, s8 * 0.5), 0.16 if s8 % 2 else 0.09)
        if bar >= 5:
            lp.put("drums", kick, lp.at(bar, 0), 1.0)
            lp.put("drums", kick, lp.at(bar, 2.5), 0.55)
        if bar >= 9:
            lp.put("drums", brush, lp.at(bar, 1), 0.35)
            lp.put("drums", brush, lp.at(bar, 3), 0.4)
    for bar in (8, 16):
        lp.put("drums", riser(rng, lp.secs(2), 1500.0, 7000.0), lp.at(bar, 2), 0.3)
    lp.bus["pad"] = loop_svf(lp.bus["pad"], lfo(lp.n, 2, 1100.0, 2200.0, -1.0), 0.75, "lp", 2.0)
    spec = {"pad": (0.09, 0.45, 0), "bass": (0.075, 0.05, 0), "arp": (0.045, 0.4, 0.45),
            "lead": (0.075, 0.5, 0.35), "bell": (0.025, 0.8, 0.3), "drums": (0.045, 0.2, 0)}
    return mixdown(lp, spec, room=0.86, damp=0.4, rv_level=0.65, delay=(lp.secs(0.75), 0.4, 0.4), drive_k=1.1)


# ================================================================ render/write
def finish_sfx(x, peak_db):
    x = hp1(x, 18.0)
    p = peak(x)
    thresh = p * 10 ** (-60.0 / 20.0)
    end = len(x)
    while end > 1 and abs(x[end - 1]) < thresh:
        end -= 1
    x = x[:max(end, ns(0.05))]
    fade_in(x, 0.001)
    fade_out(x, min(0.03, 0.1 * len(x) / SR))
    x[-1] = 0.0
    g = 10 ** (peak_db / 20.0) / peak(x)
    return [v * g for v in x]


def finish_loop(x, peak_db):
    mean = sum(x) / len(x)
    x = [v - mean for v in x]  # a constant offset keeps the seam intact
    g = 10 ** (peak_db / 20.0) / peak(x)
    x = [v * g for v in x]
    return x + [x[0]]  # guard sample: lets interpolation at the loop end read sample 0


def write_wav(path, x, rate):
    data = struct.pack("<%dh" % len(x), *[max(-32767, min(32767, int(round(v * 32767.0)))) for v in x])
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data)


def render(entry):
    global SR
    SR = entry["rate"]
    rng = random.Random(fnv1a(entry["id"]))
    x = entry["fn"](rng)
    if entry["loop"]:
        x = finish_loop(x, entry["peak_db"])
        jumps = [abs(x[i + 1] - x[i]) for i in range(len(x) - 1)]
        seam = abs(x[0] - x[-2])
        print("  %-14s loop %6.2f s  seam step %.4f (mean step %.4f, max %.4f)"
              % (entry["id"], (len(x) - 1) / SR, seam, sum(jumps) / len(jumps), max(jumps)))
    else:
        x = finish_sfx(x, entry["peak_db"])
        print("  %-14s sfx  %6.3f s  rms %5.1f dBFS" % (entry["id"], len(x) / SR, 20 * math.log10(rms(x) + 1e-12)))
    write_wav(os.path.join(OUT_DIR, entry["id"] + ".wav"), x, SR)


def wav_info(sid, loop):
    path = os.path.join(OUT_DIR, sid + ".wav")
    if not os.path.exists(path):
        return None
    with wave.open(path, "rb") as w:
        frames, rate = w.getnframes(), w.getframerate()
    return (frames - (1 if loop else 0)) / rate, rate, os.path.getsize(path)


def write_manifest():
    lines = [
        "# Audio assets",
        "",
        "Every sound in `assets/audio/` is original, synthesised from scratch by",
        "`tools/gen_audio.py` (Python 3 standard library only: oscillators, filtered",
        "noise, envelopes, FM, a small reverb and echo; no samples or third-party",
        "material). Re-running `python3 tools/gen_audio.py` reproduces the files",
        "byte for byte (each sound uses an RNG seeded from its id). This page is",
        "regenerated by the same script.",
        "",
        "Format: 16-bit mono PCM WAV, peaks normalised to about -3 dBFS (the soft",
        "footstep to -6 dBFS). Sound effects are 44.1 kHz with click-free",
        "attack/release fades; ambience and music are 22.05 kHz seamless loops.",
        "",
        "Looping: Godot imports WAVs without loop points, so `GameAudio.music()` and",
        "`GameAudio.ambient()` switch the stream to forward looping when they start it.",
        "Loop files carry one guard sample equal to sample 0 after the loop body;",
        "the loop runs over frames `[0, frames - 1)`, so interpolation at the seam",
        "reads the real next sample. Godot's default WAV import settings are kept",
        "(QOA compression in the imported cache); the `.import` files are committed.",
        "`tests/test_audio_assets.gd` checks every id loads, lengths stay in budget,",
        "one-shots do not loop and the loops wrap without a seam glitch in the mixer.",
        "",
        "Licence for all files below: original work generated by `tools/gen_audio.py`,",
        "owned by the project and released as CC0-equivalent (no attribution required).",
        "",
        "| id | kind | duration | synthesis | licence |",
        "|---|---|---|---|---|",
    ]
    total = 0
    for e in SOUNDS:
        info = wav_info(e["id"], e["loop"])
        if info is None:
            dur = "missing"
        else:
            secs, rate, size = info
            total += size
            dur = ("%.1f s loop" % secs) if e["loop"] else ("%.2f s" % secs)
        lines.append("| `%s` | %s | %s | %s | original, tools/gen_audio.py, CC0-equivalent / project-owned |"
                     % (e["id"], e["kind"], dur, e["desc"]))
    lines += ["", "Total size: %.1f MB in %d files." % (total / 1048576.0, len(SOUNDS)), ""]
    os.makedirs(os.path.dirname(DOC_PATH), exist_ok=True)
    with open(DOC_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main(argv):
    if "--list" in argv:
        for e in SOUNDS:
            print("%-14s %s" % (e["id"], e["kind"]))
        return 0
    if "--manifest" in argv:
        write_manifest()
        print("Manifest written to %s" % DOC_PATH)
        return 0
    wanted = [a for a in argv if not a.startswith("-")]
    unknown = sorted(set(wanted) - {e["id"] for e in SOUNDS})
    if unknown:
        print("unknown ids: " + ", ".join(unknown))
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Rendering into %s" % OUT_DIR)
    for e in SOUNDS:
        if not wanted or e["id"] in wanted:
            render(e)
    write_manifest()
    print("Manifest written to %s" % DOC_PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
