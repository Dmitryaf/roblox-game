"""Original procedural audio sketches; deterministic PCM masters, no sampled third-party media."""
from pathlib import Path
import math
import random
import struct
import wave

DEST = Path(__file__).resolve().parents[1] / "assets/audio"
RATE = 48000


def render(name, length, start, end, noise_level, seed):
    rng = random.Random(seed)
    phase, low = 0.0, 0.0
    samples = []
    for i in range(round(length * RATE)):
        t = i / RATE
        progress = t / length
        # Soft onset, layered harmonics and a filtered noise tail rather than a click/beep.
        attack = min(1.0, t / 0.018)
        decay = (1 - progress) ** (1.3 if name == "charge" else 2.5)
        frequency = start * (end / start) ** progress
        phase += math.tau * frequency / RATE
        low += 0.08 * (rng.uniform(-1, 1) - low)
        tone = 0.5 * math.sin(phase) + 0.18 * math.sin(phase * 0.501) + 0.12 * math.sin(phase * 2.01)
        samples.append(attack * decay * (tone + noise_level * low))
    # Short quiet reflections; source stays mono for positional Roblox playback.
    dry = samples[:]
    for delay, gain in ((0.041, 0.17), (0.087, 0.09)):
        offset = round(delay * RATE)
        for i in range(offset, len(samples)):
            samples[i] += dry[i - offset] * gain
    peak = max(map(abs, samples)) or 1
    payload = b"".join(struct.pack("<h", round(s / peak * 23000)) for s in samples)
    DEST.mkdir(parents=True, exist_ok=True)
    with wave.open(str(DEST / f"{name}.wav"), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(payload)
    print(f"{name}.wav: {length}s, 48kHz mono, peak -3.1 dBFS")


if __name__ == "__main__":
    render("charge", 0.32, 140, 400, 0.7, 1)
    render("launch", 0.48, 260, 65, 2.0, 2)
    render("impact", 0.45, 95, 38, 2.7, 3)
    render("teleport", 0.60, 430, 85, 1.4, 4)
