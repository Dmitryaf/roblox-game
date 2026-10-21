"""Original deterministic local interaction Foley; no samples, downloads or uploads."""
from array import array
from pathlib import Path
import math
import random
import sys
import wave

RATE = 48000
DEST = Path(__file__).resolve().parents[1] / 'assets/audio/living-magic-v1'


def make(kind, duration):
    rng = random.Random({'redirect': 2287, 'gather': 2593, 'raise': 2797, 'shatter': 3109}[kind])
    low = middle = phase = 0.0
    output = []
    for index in range(round(duration * RATE)):
        t = index / RATE
        white = rng.uniform(-1, 1)
        low += 0.018 * (white - low)
        middle += 0.16 * (white - middle)
        high = white - middle
        if kind == 'redirect':
            # Dry blade catch, a brief bright metal overtone and departing rush.
            value = high * 0.45 * math.exp(-t * 155)
            for frequency, amount, decay in ((1680, .20, 24), (2370, .12, 35), (3521, .06, 45)):
                value += math.sin(math.tau * frequency * t) * amount * math.exp(-t * decay)
            value += middle * 1.8 * math.exp(-((t - .095) / .065) ** 2)
        elif kind == 'gather':
            # A restrained inward draw distinct from a completed stone movement.
            envelope = math.sin(math.pi * min(1, t / duration)) ** 1.2
            phase += math.tau * (78 + t * 65) / RATE
            value = (math.sin(phase) * .16 + middle * .48 + low * .8) * envelope
        else:
            # Stone pressure has a low front; shattering adds discrete brittle tails.
            phase += math.tau * (64 if kind == 'raise' else 90) * math.exp(-t * 3) / RATE
            value = .5 * math.sin(phase) * math.exp(-t * 9)
            value += low * (2.8 if kind == 'raise' else 1.8) * math.exp(-t * 5)
            value += high * (.2 if kind == 'raise' else .6) * math.exp(-t * 120)
            starts = (.03, .12, .20, .32) if kind == 'raise' else (.015, .04, .075, .11, .17, .23, .31, .40)
            for start in starts:
                age = t - start
                if age >= 0:
                    value += (middle + high * .35 + math.sin(math.tau * (730 + start * 2700) * age) * .15) * .32 * math.exp(-age * 76)
        fade = max(0, min(1, t / .002, (duration - t - 1 / RATE) / .03))
        output.append(math.tanh(value * 1.25) * fade)
    peak = max(map(abs, output))
    return array('h', (round(value / peak * .8 * 32767) for value in output))


if __name__ == '__main__':
    DEST.mkdir(parents=True, exist_ok=True)
    for name, duration in (('redirect', .40), ('gather', .70), ('raise', .54), ('shatter', .68)):
        samples = make(name, duration)
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
        print(f'{name}: {duration:.2f}s, mono PCM 48kHz, peak below -1.9 dBFS')
