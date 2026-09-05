"""Validate shipped PCM files, authored headroom and seamless ambient transitions."""
from pathlib import Path
import json
import wave
import numpy as np

root = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
manifest = json.loads((root / 'manifest.json').read_text())
for name, info in manifest.items():
    with wave.open(str(root / (name + '.wav')), 'rb') as wav:
        assert wav.getsampwidth() == 2 and wav.getframerate() == 44100, name
        assert wav.getnchannels() == info['channels'], name
        pcm = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2')
        data = pcm.astype(float).reshape(-1, wav.getnchannels()) / 32768
    assert np.isfinite(data).all() and np.max(np.abs(data)) < .7, name
    assert np.sqrt(np.mean(data ** 2)) > .005, name
    if info['loop']:
        seam = float(np.max(np.abs(data[0] - data[-1])))
        ordinary = float(np.quantile(np.abs(np.diff(data, axis=0)), .99))
        assert seam <= ordinary, (name, seam, ordinary)
        print(f'LOOP {name}: seam={seam:.6f}; normal adjacent limit={ordinary:.6f}; PASS')
    else:
        assert np.max(np.abs(data[0])) < .001 and np.max(np.abs(data[-1])) < .001, name
print(f'AUDIO_ASSET_VALIDATION: PASS | {len(manifest)} PCM files, headroom, non-silence, channel format, fade edges and loop continuity')
