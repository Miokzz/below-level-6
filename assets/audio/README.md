# BELOW LEVEL 6 audio

All environmental sounds, footsteps, interface signals and drones are original
procedural synthesis authored for this project. No samples from commercial games,
stock sound packs or third-party music are used. The deterministic authoring script
is `tools/generate_audio.py` (NumPy, SciPy and Pillow are authoring dependencies only).

Radio dialogue uses original text rendered offline with the English Microsoft
Windows system speech voice via `tools/generate_radio.ps1`, then band-filtered,
compressed and mixed with original radio noise. The game does not access system
speech services, a microphone, personal files or the network at runtime.

The five surfaces each have four independently synthesized variants. A shuffled
selection rule prevents immediate sample repeats; small pitch and gain variation
make repeated walking less mechanical. Ambient beds have periodic source signals
and circularly filtered noise for seamless loops.

`manifest.json` lists duration, channels, peak, RMS and looping intent for every
sample. AudioStreamPlayer3D supplies spatial panning and distance rolloff. Four
environment sources update obstruction with low-cost collision queries every
250 ms, lowering the level and low-pass cutoff through walls. SFX has a restrained
room reverb. The drone uses a separate Music bus, and radio uses light compression.
In-game sources inherit pausing; interface clicks remain available during pause.

Original game audio and the generation code are supplied under the project license.
