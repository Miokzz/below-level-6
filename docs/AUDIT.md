# Recovery audit — 2026-09-08

Baseline: `9f170c5`, Godot 4.5.2 official Linux x86_64 (SHA512 verified).
All nine GDScript files, generation/test tools, project/export settings, asset
inventory, imports and architecture were inspected before source changes.
The repository contained **no scenes, autoloads, shaders or authored .tres files**.
Geometry and materials are built by `Facility` at runtime.

| State at baseline | Evidence |
| --- | --- |
| Cannot start | `run/main_scene` names absent `scenes/main.tscn`; launch exits 1. |
| Existing facility works in isolation | 17 interactables, 53 lights, 835 nodes; collision/raycast/navigation audit passes. |
| Existing controller / Observer work in isolation | Original 20 physics/observation/navigation assertions pass. |
| Existing sound library works in isolation | All 46 WAVs and original audio runtime test pass. |
| Elevator partial | Stationary cabin; door colliders disappear before animation; no obstruction check; stages reopen lift indiscriminately. |
| Puzzles / flow absent | Environment clues and targets exist, but no input logic, inventory, objectives, game state, CCTV renderer, chase trigger or ending. |
| UI / settings / save absent | Architecture promises these systems, but corresponding files are absent. |
| Radio / subtitles partial | Six voiced lines exist; no subtitle lifecycle, queue or repeated-dialogue prevention. |
| Horror persistence broken | Saved event flags prevent replay without restoring their changed geometry. |
| Controller edge case | Crouch can lower collider before camera clears low ceilings; stretched mouse delta affects sensitivity. |
| Packaging incomplete | Missing README, required custom export templates, incorrect license paths in asset documentation. |

The recovery preserves the authored facility, sounds, controller and entity.
New orchestration fills the missing architecture. Verification results for the
completed work belong in `VALIDATION.md`; this file records the original state.
