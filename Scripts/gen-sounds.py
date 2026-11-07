#!/usr/bin/env python3
"""Synthesizes Vigie's built-in alert sounds (Story 10.2) as 44.1 kHz 16-bit mono WAV.

Stdlib only. Re-run after a change and commit the WAVs:
    Scripts/gen-sounds.py [output dir]   (default: Packages/VigieCore/Sources/VigieCore/Resources/Sounds)

Register: simple, clean sci-fi tones (sine + a little 2nd/3rd harmonic), each under 1 s, with short fades.
"""
import math
import os
import struct
import sys
import wave

RATE = 44100
PEAK = 0.55  # headroom: alerts should not be louder than system sounds


def tone(freq, dur, harmonics=((1, 1.0), (2, 0.18), (3, 0.06)), glide_to=None, attack=0.006, decay=6.0):
    """A note of `dur` seconds: harmonic sine, optional linear pitch glide, fast attack, exponential decay."""
    n = int(RATE * dur)
    out = []
    phase = [0.0] * len(harmonics)
    for i in range(n):
        t = i / RATE
        f = freq if glide_to is None else freq + (glide_to - freq) * (i / n)
        s = 0.0
        for k, (mult, amp) in enumerate(harmonics):
            phase[k] += 2 * math.pi * f * mult / RATE
            s += amp * math.sin(phase[k])
        env = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(s * env)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    """Sums tracks given as (offset seconds, samples)."""
    length = max(int(off * RATE) + len(s) for off, s in tracks)
    out = [0.0] * length
    for off, samples in tracks:
        start = int(off * RATE)
        for i, v in enumerate(samples):
            out[start + i] += v
    return out


def finish(samples, fade=0.012):
    """Normalizes to PEAK and applies short linear fades so no sound starts or ends with a click."""
    peak = max(abs(v) for v in samples) or 1.0
    samples = [v / peak * PEAK for v in samples]
    f = int(RATE * fade)
    for i in range(min(f, len(samples))):
        samples[i] *= i / f
        samples[-1 - i] *= i / f
    return samples


def blocked():
    # Two-tone rising ping (A5 then E6), bright and attention-getting, ~0.6 s.
    return mix((0.0, tone(880, 0.28, decay=9)), (0.16, tone(1318.5, 0.44, decay=7)))


def failed():
    # Descending buzz: a square-ish tone (odd harmonics) gliding 330 → 165 Hz with a slight 30 Hz flutter, ~0.7 s.
    n = int(RATE * 0.7)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 330 - 165 * (i / n)
        phase += 2 * math.pi * f / RATE
        s = sum(math.sin(phase * k) / k for k in (1, 3, 5, 7))
        flutter = 0.8 + 0.2 * math.sin(2 * math.pi * 30 * t)
        env = min(1.0, t / 0.008) * math.exp(-3.2 * t)
        out.append(s * flutter * env)
    return out


def done():
    # Soft major third chime (C6 + E6, the E entering a beat later), sine-heavy, ~0.5 s.
    soft = ((1, 1.0), (2, 0.08))
    return mix((0.0, tone(1046.5, 0.5, soft, decay=7)), (0.07, tone(1318.5, 0.43, soft, decay=8)))


def warn():
    # Short double blip at D6, ~0.4 s.
    blip = tone(1174.7, 0.12, decay=14)
    return mix((0.0, blip), (0.17, blip), (0.0, silence(0.4)))


SOUNDS = {"blocked": blocked, "failed": failed, "done": done, "warn": warn}


def write(path, samples):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in samples))


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        root, "Packages/VigieCore/Sources/VigieCore/Resources/Sounds")
    os.makedirs(out_dir, exist_ok=True)
    for name, make in SOUNDS.items():
        samples = finish(make())
        assert len(samples) < RATE, f"{name} is not under 1 s"
        path = os.path.join(out_dir, f"{name}.wav")
        write(path, samples)
        print(f"{path}: {len(samples) / RATE:.2f} s")


if __name__ == "__main__":
    main()
