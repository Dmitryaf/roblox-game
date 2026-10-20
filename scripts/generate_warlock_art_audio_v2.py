"""Original second-iteration masters. Reuses synthesis primitives, never rewrites v1."""
from array import array
from pathlib import Path
import hashlib
import json
import math
import sys
import wave
from generate_warlock_art_audio import RATE, blank, growl, grains, pressure, reflections

DEST = Path(__file__).resolve().parents[1] / "assets/audio/warlock-art-v2"


def charge():
    out = blank(0.82)
    # A restrained low beginning gathers rough mid harmonics over the full windup.
    growl(out, 0, 0.82, 49, 117, 0.75, 0.68, -0.2, 8101)
    growl(out, 0.13, 0.69, 38, 68, 0.32, 0.54, -0.15, 8102)
    grains(out, 0.07, 0.63, 37, 195, 0.085, 8103, rising=True)
    pressure(out, 0.08, 0.64, 0.42, 8104, reverse=True)
    reflections(out, ((0.031, 0.11), (0.071, 0.055)))
    for i in range(len(out)):
        t = i / RATE
        # Crest at release (~0.7 s), then a deliberate 120 ms disappearance.
        tail = 1 if t <= 0.7 else max(0, (0.82 - t) / 0.12)
        out[i] *= tail * (0.38 + 0.62 * min(1, t / 0.7))
    return out


def impact():
    out = blank(1.7)
    # The long, detuned body and separate throat layer carry weight on small speakers.
    growl(out, 0, 1.57, 89, 35, 1.12, 0.0025, 4.0, 8201)
    growl(out, 0.008, 0.61, 219, 76, 0.77, 0.004, 3.0, 8202)
    growl(out, 0.018, 0.34, 385, 133, 0.28, 0.003, 3.8, 8203)
    pressure(out, 0, 0.68, 0.82, 8204)
    grains(out, 0.006, 0.39, 32, 410, 0.22, 8205)
    grains(out, 0.20, 0.98, 24, 176, 0.12, 8206)
    # A falling sub-pressure pulse sits under, rather than replaces, the midrange jaw.
    phase = 0
    for i in range(round(1.35 * RATE)):
        t = i / RATE
        frequency = 34 + 47 * math.exp(-t * 13)
        phase += math.tau * frequency / RATE
        envelope = min(1, t / 0.006) * math.exp(-t * 4.2)
        out[i] += 0.52 * envelope * (math.sin(phase) + 0.24 * math.sin(phase * 2.01))
    for n, at in enumerate((0.046, 0.113, 0.22, 0.39, 0.62, 0.89)):
        growl(out, at, 0.25 + at * 0.16, 175 + n * 37, 69 + n * 13,
              0.20 * math.exp(-at * 2.4), 0.002, 3.9, 8220 + n)
    reflections(out, ((0.037, 0.16), (0.083, 0.15), (0.149, 0.12),
                      (0.263, 0.085), (0.397, 0.05)))
    return out


def write(name, samples):
    dc = sum(samples) / len(samples)
    samples = [math.tanh((value - dc) * 0.85) for value in samples]
    for i in range(len(samples)):
        edge = min(1, i / (RATE * 0.002), (len(samples) - 1 - i) / (RATE * 0.025))
        samples[i] *= 0.5 - 0.5 * math.cos(math.pi * edge)
    scale = 0.89 * 32767 / max(map(abs, samples))
    pcm = array("h", (round(value * scale) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    path = DEST / f"{name}.wav"
    with wave.open(str(path), "wb") as audio:
        audio.setparams((1, 2, RATE, len(pcm), "NONE", "not compressed"))
        audio.writeframes(pcm.tobytes())
    with wave.open(str(path), "rb") as audio:
        assert (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) == (1, 2, RATE)
        decoded = array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder != "little":
        decoded.byteswap()
    peak = max(map(abs, decoded)) / 32768
    rms = math.sqrt(sum((value / 32768) ** 2 for value in decoded) / len(decoded))
    assert decoded[0] == decoded[-1] == 0 and peak < 0.891
    assert all(-32768 < value < 32767 for value in decoded)
    return {"file": name + ".wav", "seconds": len(decoded) / RATE,
            "sample_rate": RATE, "channels": 1, "pcm_bits": 16,
            "peak_dbfs": round(20 * math.log10(peak), 2),
            "rms_dbfs": round(20 * math.log10(rms), 2),
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


if __name__ == "__main__":
    DEST.mkdir(parents=True, exist_ok=True)
    for name, make in (("charge", charge), ("impact", impact)):
        print(json.dumps(write(name, make())))
