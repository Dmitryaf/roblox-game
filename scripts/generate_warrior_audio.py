"""Original deterministic sword/stone Foley synthesis. No samples, services or uploads."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

RATE = 48000
DEST = Path(__file__).resolve().parents[1] / 'assets/audio/warrior-v1'


def make(kind, duration):
    rng = random.Random({'brace': 531, 'slash': 719, 'impact': 913, 'rupture': 1031}[kind])
    low = middle = phase = 0.0
    out = []
    for index in range(round(duration * RATE)):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low += 0.025 * (white - low)
        middle += 0.23 * (white - middle)
        grit = white - middle
        if kind == 'brace':
            # Dry leather tension and two small armour catches before release.
            env = math.sin(math.pi * min(1, t / duration)) ** 1.7
            value = 0.20 * middle * env + 0.26 * low * env
            for start in (0.025, 0.12):
                age = t - start
                if age >= 0:
                    value += 0.07 * (math.sin(math.tau * 1720 * age) + grit) * math.exp(-age * 100)
        else:
            hit = math.exp(-t * (19 if kind == 'slash' else 12)) * min(1, t / 0.002)
            frequency = (95 if kind == 'impact' else 72) * math.exp(-t * 3.5)
            phase += math.tau * frequency / RATE
            weight = 0.23 if kind == 'slash' else 0.6
            value = weight * math.sin(phase) * hit
            if kind == 'slash':
                whoosh = math.exp(-((t - 0.075) / 0.065) ** 2)
                value += (middle * 1.5 + low * 1.2) * whoosh
                value += grit * 0.09 * math.exp(-t * 25)
            else:
                # A dry front edge, then low stone pressure and discrete falling chips.
                value += grit * 0.45 * math.exp(-t * 120)
                value += low * (3 if kind == 'rupture' else 1.8) * math.exp(-t * 7)
                for start in (0.02, 0.055, 0.09, 0.14, 0.21, 0.30):
                    age = t - start
                    if age >= 0:
                        value += (grit + 0.4 * math.sin(math.tau * (750 + start * 3200) * age)) * 0.09 * math.exp(-age * 95)
        fade = min(1, t / 0.002, (duration - t - 1 / RATE) / 0.025)
        out.append(math.tanh(value * 1.2) * max(0, fade))
    peak = max(map(abs, out))
    return array('h', (round(value / peak * 0.83 * 32767) for value in out))


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    for name, seconds in (('brace', 0.27), ('slash', 0.43), ('impact', 0.60), ('rupture', 0.66)):
        samples = make(name, seconds)
        if sys.byteorder != 'little':
            samples.byteswap()
        path = DEST / f'{name}.wav'
        with wave.open(str(path), 'wb') as output:
            output.setparams((1, 2, RATE, len(samples), 'NONE', 'not compressed'))
            output.writeframes(samples.tobytes())
        with wave.open(str(path), 'rb') as check:
            decoded = array('h', check.readframes(check.getnframes()))
            assert check.getnchannels() == 1 and check.getframerate() == RATE
            assert decoded[0] == decoded[-1] == 0 and max(map(abs, decoded)) < 28000
        print(f'{name}: {len(samples) / RATE:.2f}s, mono PCM 48kHz, peak below -1.6dBFS')
