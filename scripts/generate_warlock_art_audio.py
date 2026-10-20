"""Deterministic original dark-magic sound masters; Python standard library only.

No recordings, third-party samples or network inputs. Run from any directory.
"""
from array import array
from pathlib import Path
import hashlib
import json
import math
import random
import sys
import wave

RATE = 48_000
TAU = math.tau
DEST = Path(__file__).resolve().parents[1] / "assets/audio/warlock-art-v1"


def blank(seconds):
    return [0.0] * round(seconds * RATE)


def growl(out, at, duration, start, end, gain, attack, decay, seed):
    """Inharmonic, slowly beating vocal-like body with audible mid harmonics."""
    rng = random.Random(seed)
    phases = [rng.uniform(0, TAU) for _ in range(3)]
    ratios = (1.0, 1.017, 0.498)
    low, middle = 0.0, 0.0
    count = round(duration * RATE)
    offset = round(at * RATE)
    for i in range(count):
        j = offset + i
        if j >= len(out):
            break
        t, u = i / RATE, i / max(1, count - 1)
        low += 0.019 * (rng.uniform(-1, 1) - low)
        middle += 0.15 * (low - middle)
        frequency = start * (end / start) ** u
        flutter = 1 + 0.025 * math.sin(TAU * 17.3 * t) + 0.09 * low
        envelope = min(1.0, t / attack) * math.exp(-decay * u)
        envelope *= min(1.0, (1 - u) / 0.06)
        body = 0.0
        for k, ratio in enumerate(ratios):
            phases[k] += TAU * frequency * ratio * flutter / RATE
            p = phases[k]
            # Unequal formant partials and FM roughness avoid a clean synthesizer beep.
            fm = 0.7 * math.sin(p * 0.497 + k) + 2.8 * middle
            voice = math.sin(p + fm) + 0.45 * math.sin(2.03 * p + fm)
            voice += 0.29 * math.sin(3.97 * p) + 0.19 * math.sin(6.13 * p)
            body += voice * (0.45 if k < 2 else 0.23)
        out[j] += gain * envelope * math.tanh(body * 1.45)


def grains(out, at, span, count, pitch, gain, seed, rising=False):
    """Irregular pitched fractures, with filtered turbulence inside each grain."""
    rng = random.Random(seed)
    for n in range(count):
        progress = (n + rng.random() * 0.7) / max(1, count)
        start = at + span * progress
        duration = rng.uniform(0.018, 0.075)
        frequency = pitch * rng.uniform(0.55, 2.4)
        phase, grit = rng.uniform(0, TAU), 0.0
        amp = gain * rng.uniform(0.45, 1.0)
        amp *= 0.2 + 0.8 * progress if rising else (1 - progress) ** 1.3
        for i in range(round(duration * RATE)):
            j = round(start * RATE) + i
            if j >= len(out):
                break
            u = i / max(1, round(duration * RATE) - 1)
            grit += 0.13 * (rng.uniform(-1, 1) - grit)
            phase += TAU * frequency * (1 - 0.45 * u) / RATE
            envelope = math.sin(math.pi * u) ** 1.2
            texture = math.sin(phase + 4.0 * grit) + 0.38 * math.sin(phase * 2.37)
            out[j] += amp * envelope * (texture * 0.7 + grit * 0.5)


def pressure(out, at, duration, gain, seed, reverse=False):
    """Band-limited breathing/stone pressure, never raw full-band white noise."""
    rng = random.Random(seed)
    bass = presence = 0.0
    count = round(duration * RATE)
    for i in range(count):
        j = round(at * RATE) + i
        if j >= len(out):
            break
        u = i / max(1, count - 1)
        noise = rng.uniform(-1, 1)
        bass += 0.018 * (noise - bass)
        presence += 0.18 * (noise - presence)
        envelope = u**1.8 if reverse else math.exp(-6 * u) * min(1.0, u / 0.018)
        envelope *= min(1.0, (1 - u) / 0.04)
        out[j] += gain * envelope * (1.6 * bass + 0.45 * (presence - bass))


def reflections(out, taps):
    dry = out[:]
    for seconds, gain in taps:
        offset, smoothed = round(seconds * RATE), 0.0
        for i in range(offset, len(out)):
            smoothed += 0.11 * (dry[i - offset] - smoothed)
            out[i] += gain * smoothed


def make_charge():
    out = blank(0.45)
    growl(out, 0, 0.44, 62, 124, 0.76, 0.26, -0.25, 101)
    grains(out, 0.025, 0.285, 19, 230, 0.10, 102, rising=True)
    pressure(out, 0.01, 0.32, 0.5, 103, reverse=True)
    reflections(out, ((0.031, 0.14), (0.067, 0.08)))
    return out


def make_launch():
    out = blank(0.65)
    growl(out, 0, 0.60, 195, 43, 0.78, 0.003, 5.0, 201)
    grains(out, 0, 0.19, 24, 430, 0.22, 202)
    pressure(out, 0, 0.33, 1.15, 203)
    # Several unequal cracks make a torn, directional release rather than a click.
    for n, (at, pitch) in enumerate(((0.004, 670), (0.021, 390), (0.047, 245))):
        growl(out, at, 0.085, pitch, pitch * 0.36, 0.16, 0.0015, 4.5, 210 + n)
    reflections(out, ((0.043, 0.17), (0.091, 0.11), (0.163, 0.06)))
    return out


def make_impact():
    out = blank(1.6)
    growl(out, 0, 1.35, 105, 39, 1.05, 0.003, 6.2, 301)
    growl(out, 0.008, 0.32, 310, 76, 0.44, 0.002, 4.4, 302)
    pressure(out, 0, 0.58, 1.4, 303)
    grains(out, 0, 0.29, 37, 510, 0.20, 304)
    grains(out, 0.105, 0.98, 26, 215, 0.095, 305)
    # Low dissonant residues and small falling pieces continue after the attack.
    for n, at in enumerate((0.057, 0.112, 0.19, 0.31, 0.47, 0.69, 0.91)):
        growl(out, at, 0.19 + at * 0.19, 160 + n * 29, 66 + n * 11,
              0.13 * math.exp(-at * 2.7), 0.002, 4.1, 320 + n)
    reflections(out, ((0.047, 0.19), (0.093, 0.14), (0.173, 0.12),
                      (0.289, 0.085), (0.411, 0.055)))
    return out


def make_teleport():
    out = blank(0.9)
    growl(out, 0, 0.245, 57, 190, 0.42, 0.17, -0.5, 401)
    pressure(out, 0, 0.24, 0.85, 402, reverse=True)
    grains(out, 0.01, 0.20, 17, 260, 0.10, 403, rising=True)
    growl(out, 0.23, 0.63, 230, 47, 0.88, 0.002, 5.2, 404)
    grains(out, 0.226, 0.20, 23, 380, 0.18, 405)
    pressure(out, 0.23, 0.50, 0.95, 406)
    reflections(out, ((0.031, 0.16), (0.079, 0.10), (0.151, 0.07)))
    return out


def write_master(name, samples):
    # Gentle saturation controls isolated peaks; no sample is hard clipped.
    dc = sum(samples) / len(samples)
    samples = [math.tanh((sample - dc) * 0.95) for sample in samples]
    for i in range(len(samples)):
        fade = min(1.0, i / (RATE * 0.002), (len(samples) - 1 - i) / (RATE * 0.025))
        samples[i] *= 0.5 - 0.5 * math.cos(math.pi * fade)
    scale = 0.86 / max(map(abs, samples))
    pcm = array("h", (round(sample * scale * 32767) for sample in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = DEST / f"{name}.wav"
    with wave.open(str(path), "wb") as output:
        output.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
        output.writeframes(pcm.tobytes())
    # Verify the written PCM, not just the source floats.
    with wave.open(str(path), "rb") as check:
        assert (check.getnchannels(), check.getsampwidth(), check.getframerate()) == (1, 2, RATE)
        decoded = array("h", check.readframes(check.getnframes()))
        if sys.byteorder != "little":
            decoded.byteswap()
        peak = max(map(abs, decoded)) / 32768
        rms = math.sqrt(sum((v / 32768) ** 2 for v in decoded) / len(decoded))
        assert decoded[0] == decoded[-1] == 0 and peak < 0.861
        assert all(-32768 < value < 32767 for value in decoded)
        return {"file": str(path.relative_to(DEST)), "seconds": len(decoded) / RATE,
                "sample_rate": RATE, "channels": 1, "pcm_bits": 16,
                "peak_dbfs": round(20 * math.log10(peak), 2),
                "rms_dbfs": round(20 * math.log10(rms), 2),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    for name, make in (("charge", make_charge), ("launch", make_launch),
                       ("impact", make_impact), ("teleport", make_teleport)):
        print(json.dumps(write_master(name, make()), ensure_ascii=False))
