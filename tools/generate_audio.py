"""Author the original BELOW LEVEL 6 sound library; never needed by a player.

Requires NumPy, SciPy and Pillow. Optional radio WAVs are generated beforehand by
generate_radio.ps1. Every non-speech sample is synthesized from scratch here.
"""
from pathlib import Path
import json
import wave
import numpy as np
from scipy import signal
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "audio"
OUT.mkdir(parents=True, exist_ok=True)
SR = 44100
RNG = np.random.default_rng(6061426)
TAU = 2 * np.pi
REPORT = {}


def axis(seconds):
    return np.arange(round(SR * seconds)) / SR


def noise(n, low=30, high=6000):
    # Circular FFT filtering makes the long beds naturally seamless.
    bins = np.fft.rfftfreq(n, 1 / SR)
    white = np.fft.rfft(RNG.standard_normal(n))
    mask = (1 - np.exp(-(bins / low) ** 4)) * np.exp(-(bins / high) ** 4)
    result = np.fft.irfft(white * mask, n)
    return result / max(np.std(result), 1e-5)


def fades(x, attack=0.006, release=0.10):
    x = x.copy()
    a, r = min(round(attack * SR), len(x)), min(round(release * SR), len(x))
    x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    x[-r:] *= np.linspace(1, 0, r)[:, None] if x.ndim == 2 else np.linspace(1, 0, r)
    return x


def echo(x, taps=((0.067, .14), (0.13, .10), (0.257, .055))):
    y = x.copy()
    for delay, gain in taps:
        count = int(SR * delay)
        if count < len(x):
            y[count:] += x[:-count] * gain
    return y


def save(name, data, peak=.62, loop=False):
    data = np.nan_to_num(data)
    data *= peak / max(float(np.max(np.abs(data))), 1e-6)
    if loop:
        # Start on a locally quiet derivative in both channels; circular synthesis
        # is periodic already, this keeps the WAV boundary especially unobtrusive.
        differences = np.abs(np.diff(data[:SR // 4], axis=0))
        if data.ndim == 2:
            differences = differences.max(axis=1)
        pivot = int(np.argmin(differences)) + 1
        data = np.roll(data, -pivot, axis=0)
    else:
        data = fades(data)
    values = (np.clip(data, -.98, .98) * 32767).astype('<i2')
    with wave.open(str(OUT / (name + '.wav')), 'wb') as wav:
        wav.setnchannels(data.shape[1] if data.ndim == 2 else 1)
        wav.setsampwidth(2)
        wav.setframerate(SR)
        wav.writeframes(values.tobytes())
    REPORT[name] = {'duration': round(len(data) / SR, 3), 'channels': 2 if data.ndim == 2 else 1,
                    'peak': round(float(np.max(np.abs(data))), 3),
                    'rms': round(float(np.sqrt(np.mean(data ** 2))), 4), 'loop': loop}


def loops():
    t = axis(24)
    n = len(t)
    slow = .88 + .05 * np.sin(TAU * t / 8) + .04 * np.cos(TAU * t / 24)
    left = noise(n, 70, 1100) * slow * .10 + .065 * np.sin(TAU * 50 * t)
    left += .026 * np.sin(TAU * 100 * t + .03 * np.sin(TAU * t / 12))
    right = noise(n, 90, 1200) * slow * .10 + .062 * np.sin(TAU * 50 * t + .04)
    right += .024 * np.sin(TAU * 100 * t + .2)
    save('ambience', np.column_stack([left, right]), peak=.53, loop=True)
    t = axis(16)
    n = len(t)
    fans = noise(n, 90, 2300) * (.15 + .02 * np.sin(TAU * t / 8))
    fans += .09 * np.sin(TAU * 73 * t) + .04 * np.sin(TAU * 146 * t)
    save('hvac', fans, peak=.54, loop=True)
    electrical = .16 * np.sin(TAU * 60 * t) + .065 * np.sin(TAU * 180 * t)
    electrical += noise(n, 1000, 4500) * .018 * (.7 + .3 * np.sin(TAU * t / 4) ** 8)
    save('electrical', electrical, peak=.55, loop=True)
    servers = noise(n, 400, 4600) * .10 + noise(n, 50, 400) * .055
    servers += .008 * np.sin(TAU * 2016 * t) * (1 + np.sin(TAU * t / 16))
    save('servers', servers, peak=.50, loop=True)
    t = axis(32)
    # Beating partials produce unease without a melody or jump in loudness.
    left = .16 * np.sin(TAU * 43 * t) + .11 * np.sin(TAU * 43.15625 * t + .7)
    left += .06 * np.sin(TAU * 86.28125 * t) * (.7 + .3 * np.sin(TAU * t / 32))
    left += noise(len(t), 100, 600) * .016
    right = .16 * np.sin(TAU * 43 * t + .025) + .10 * np.sin(TAU * 43.125 * t + .9)
    right += .057 * np.sin(TAU * 86.25 * t) + noise(len(t), 100, 600) * .016
    save('drone', np.column_stack([left, right]), peak=.48, loop=True)


def footsteps():
    materials = {'concrete': (85, 1400, .14), 'metal': (128, 2600, .24),
                 'grating': (156, 3800, .28), 'tile': (112, 2100, .12),
                 'wet': (88, 5000, .20)}
    for name, (pitch, cutoff, tail) in materials.items():
        for variant in range(4):
            t = axis(.54 if name in ('metal', 'grating') else .42)
            n = len(t)
            pitch *= float(RNG.uniform(.98, 1.02))
            body = np.sin(TAU * pitch * t - 7 * t * t) * np.exp(-t / .045) * .40
            grit = noise(n, 120, cutoff) * np.exp(-t / .030) * .16
            toe = noise(n, 500, cutoff) * np.exp(-((t - .071) / .029) ** 2) * .04
            if name in ('metal', 'grating'):
                for partial in (1, 2.31, 3.17):
                    body += .065 / partial * np.sin(TAU * pitch * partial * t) * np.exp(-t / tail)
            if name == 'wet':
                grit += noise(n, 900, 5000) * np.exp(-((t - .080) / .050) ** 2) * .080
            if name == 'tile':
                grit += np.sin(TAU * 950 * t) * np.exp(-t / .011) * .11
            save(f'step_{name}_{variant + 1}', echo(body + grit + toe), peak=.54)


def cues():
    t = axis(2.4)
    bell = sum(np.sin(TAU * freq * t) * amp * np.exp(-t / decay)
               for freq, amp, decay in [(587.3, .5, .6), (1174.6, .2, .32), (1762, .06, .2)])
    save('chime', echo(bell), peak=.54)
    t = axis(.22)
    save('click', noise(len(t), 1400, 6500) * np.exp(-t / .009) + .3 * np.sin(TAU * 170 * t) * np.exp(-t / .02), peak=.45)
    t = axis(3.7)
    motor = noise(len(t), 70, 1100) * .12 + .12 * np.sin(TAU * (94 * t + 3 * t * t))
    motor *= np.sin(np.pi * np.clip(t / 3.0, 0, 1)) ** .7
    latch = noise(len(t), 180, 1200) * np.exp(-np.maximum(0, t - 3.1) / .10) * (t >= 3.1) * .13
    save('door', fades(echo(motor + latch), .12, .25), peak=.52)
    t = axis(2.6)
    drag = noise(len(t), 350, 3800) * (.3 + .15 * np.sin(TAU * 13.1 * t))
    drag *= np.sin(np.pi * t / 2.6) ** 2
    drag += .16 * np.sin(TAU * (407 * t + 14 * t * t)) * np.sin(np.pi * t / 2.6) ** 3
    save('drag', echo(drag), peak=.49)
    t = axis(.65)
    connect = noise(len(t), 500, 4000) * .16 * np.exp(-t / .08)
    connect += .08 * np.sin(TAU * 1140 * t) * np.exp(-((t - .09) / .035) ** 2)
    save('radio', connect, peak=.43)
    for name, pitches in [('success', [392, 523.25]), ('error', [196, 174.61]), ('network', [784, 987.77, 1174.66])]:
        t = axis(1.8)
        x = np.zeros(len(t))
        for i, freq in enumerate(pitches):
            local = np.maximum(0, t - i * .15)
            x += np.sin(TAU * freq * local) * np.exp(-local / .17) * (t >= i * .15)
        save(name, echo(x), peak=.45)
    t = axis(5)
    rise = np.sin(np.pi * t / 5) ** 2
    save('power', echo((np.sin(TAU * (40 * t + 3.4 * t * t)) * .2 + noise(len(t), 40, 1000) * .08) * rise), peak=.52)
    save('cooling', echo((noise(len(t), 80, 3400) * .19 + np.sin(TAU * (57 * t + 2 * t * t)) * .06) * rise), peak=.51)
    t = axis(2.8)
    failure = (np.sin(TAU * (120 * t - 14 * t * t)) * .21 + noise(len(t), 80, 1400) * .06) * np.exp(-t / .9)
    save('failure', echo(failure), peak=.55)
    t = axis(1.4)
    pulse = np.sin(TAU * 54 * t) * np.exp(-t / .07)
    pulse += np.sin(TAU * 47 * t) * np.exp(-np.maximum(0, t - .22) / .09) * (t >= .22) * .55
    save('heartbeat', echo(pulse), peak=.42)
    t = axis(4.3)
    breath = noise(len(t), 250, 1700) * np.sin(np.pi * t / 4.3) ** 4
    save('breath', breath, peak=.37)
    t = axis(14)
    motor = noise(len(t), 35, 700) * .12 + .19 * np.sin(TAU * 48 * t) + .03 * np.sin(TAU * 144 * t)
    save('elevator', motor, peak=.51, loop=True)
    t = axis(4)
    down = noise(len(t), 60, 2200) * .15 + .16 * np.sin(TAU * (115 * t - 12 * t * t))
    save('shutdown', fades(down * np.exp(-t / 1.4), .03, 1), peak=.5)


def speech():
    raw = ROOT / '.tools' / 'radio_raw'
    for path in sorted(raw.glob('*.wav')):
        with wave.open(str(path), 'rb') as wav:
            rate, channels, samplewidth = wav.getframerate(), wav.getnchannels(), wav.getsampwidth()
            assert samplewidth == 2
            voice = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(float) / 32768
        if channels > 1:
            voice = voice.reshape(-1, channels).mean(axis=1)
        voice = signal.resample_poly(voice, SR, rate)
        voice = signal.sosfilt(signal.butter(4, [360, 3300], btype='bandpass', fs=SR, output='sos'), voice)
        voice /= max(np.max(np.abs(voice)), 1e-5)
        voice = np.tanh(voice * 1.7) * .7
        voice += noise(len(voice), 450, 4200) * .013
        pad = np.zeros(int(SR * .28))
        voice = np.concatenate([pad, fades(voice, .015, .12), pad])
        squelch = noise(len(voice), 650, 3800)
        t = np.arange(len(voice)) / SR
        voice += squelch * (np.exp(-t / .035) + np.exp(-np.abs(t - t[-1] + .14) / .035)) * .033
        save(path.stem, voice, peak=.64)


def icon():
    # Same original glyph as assets/icon.svg, rasterized at multiple Windows icon sizes.
    scale = 4
    canvas = Image.new('RGBA', (256 * scale, 256 * scale), (0, 0, 0, 0))
    drawing = ImageDraw.Draw(canvas)
    drawing.rounded_rectangle((0, 0, 256 * scale - 1, 256 * scale - 1), radius=36 * scale, fill='#0b1519')
    path = [(44, 48), (212, 48), (212, 70), (66, 70), (66, 186), (190, 186), (190, 138), (132, 138), (132, 166), (110, 166), (110, 116), (212, 116), (212, 208), (44, 208)]
    drawing.polygon([(x * scale, y * scale) for x, y in path], fill='#aec8c6')
    drawing.rectangle((152 * scale, 84 * scale, 212 * scale, 98 * scale), fill='#e6ae60')
    canvas.resize((256, 256), Image.Resampling.LANCZOS).save(ROOT / 'assets' / 'icon.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


if __name__ == '__main__':
    loops()
    footsteps()
    cues()
    speech()
    icon()
    (OUT / 'manifest.json').write_text(json.dumps(REPORT, indent=2) + '\n', encoding='utf-8')
    print(f'Authored {len(REPORT)} sounds; {sum(item["duration"] for item in REPORT.values()):.1f}s total.')
