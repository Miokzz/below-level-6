# Implementation contracts — 0.2.0

Godot 4.5.2 Standard, Compatibility renderer, native Windows/Linux x64.
The original facility is authored procedurally; `scenes/main.tscn` is the entry
scene. No autoloads or external game services are required.

## Session ownership

`systems/game.gd` owns a pausable `Shift` subtree containing `Facility`,
`Technician`, `Observer`, `Soundscape` and `ScareDirector`. The root and `GameUI`
continue processing pause/menu input. The session token cancels prior narrative
continuations on new game/menu/load. The elevator also owns a transport generation
counter so a canceled ride restores the passenger's physics settings.

Stages follow arrival (0), operations (1), power (2–3), cooling (4–5), network
(6–7), CCTV (8), access (9), core (10), failure (11), pursuit (12), lift (13),
ending (14). RepairState is the source of puzzle truth; the root advances stages
only after valid operations. Checkpoint validation checks both agree.

## Environment and interactions

`Facility.build()` retains the authored interconnected rooms, batched geometry,
runtime materials, interaction targets and navigation graph. `markers` and
`interaction_approaches` are clear standing locations. Floors are at y=0.
Layer 1 is physical geometry, 2 interaction targets, 3 player, 4 visible Observer
(Godot bitmask values 1, 2, 4, 8). The player's center ray tests geometry and
interactables, so walls block use.

Targets carry `interaction_id` and `label` metadata. The root routes every exposed
ID to inventory, documents, repairs, CCTV, access, core or lift behavior.
`set_collected`, `set_terminal_status`, `set_pump_state` and `set_stage` synchronize
visible world feedback. `reset_interactions()` resets the authored state.

`travel_elevator(to_surface, passenger, seconds)` moves a closed cabin through a
30 m shaft, carrying the passenger. The root allows looking but no translation
during travel. Door bodies remain collidable while moving; obstruction reverses
closure. Call/open/close/surface controls are separate interaction targets.
`mechanism_cue` supplies timed door, motor and chime feedback.

## Puzzles and persistence

`RepairState.operate(action, value)` validates the distribution carrier and
sequenced circuits, local pumps and calibrated valves, then distinct network
uplinks and commit. Incorrect attempts retain recoverable state. Items are
idempotent. Every operation used by the UI is available to the regression tests;
there are no player-facing debug shortcuts.

`Checkpoints` stores versioned JSON with SHA256 integrity, type and consistency
validation, temporary-file replacement and a previous validated backup. Numeric
sequences are normalized when JSON converts integers to floats. Stages 1–10 and
14 may be saved; pursuit reloads the pre-failure core airlock checkpoint. Arbitrary
player coordinates, in-progress lift motion and capture states are never saved.
Inventory, partial puzzles, world events and radio/Observer history are retained.

Settings use a separate `ConfigFile` managed by `GameSettings`. Apply handles
display mode/resolution, quality budget, frame limit, VSync, audio, FOV, sensitivity,
brightness, invert Y, head bob, reduced movement and subtitles. No strobe effects
or microphone option are exposed.

## Observation, video and sound

`Technician.is_observing()` checks view bounds and multiple occlusion samples.
The Observer uses incremental clearance-tested A* and a physical sliding body.
Hidden/stopped actors have no collision. `resume_chase()` preserves the existing
position when a lift departure is rejected. Captures emit once.

`ScareDirector` stores exact world changes and partial light sequences as boolean
event flags. Restore reapplies chair, shutter, signs and corridor geometry.
Temporal changes respect pause and session cancellation.

One shared-world `SubViewport` renders the selected surveillance camera. Layer
19 holds the physical screen (excluded from the feed camera to avoid recursive
feedback); layer 20 holds video-only figures (excluded from the player camera).
The screen refreshes at 2 Hz near security, and continuously while actively
viewing a feed. Distant video rendering is disabled. Offline monitors explicitly
show diagnostic status.

`Soundscape` owns Master/SFX/Music/Radio buses, spatial occlusion, nonrepeating
surface footsteps and unique mechanism cues. Radio completion drives a single
subtitle lifecycle and queue; stop, load and menu clear queued dialogue safely.
Menu activity and permanent audio shutdown are explicit. Real-time audio tests
run against the mixer clock, separately from accelerated physics tests.

## Verification and exports

`tools/verify.py` runs component, persistence and session regressions and checks
engine logs, not just exit codes. `--native` drives the complete original map
through the controller, E input and UI buttons. It neither teleports the player
nor edits progression. `tests/test_session_recovery.gd` separately sets up
checkpoint fixtures to test loading and capture recovery.

`tools/package.py` exports pinned release templates, includes engine/dependency
notices, creates ZIPs and writes SHA256 checksums. `.godot`, `.tools`, `dist` and
`test-output` are local generated artifacts and are excluded from version control.
