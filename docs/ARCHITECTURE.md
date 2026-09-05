# Implementation contracts

Godot 4.5.2, native Windows x64. Runtime geometry is authored procedurally; no web layer.

## Root integration
`scenes/main.tscn` loads `systems/game.gd`. Game owns `level`, `player`, `hud`, `observer`, `sound`, and a single narrative state enum. Root implements interaction UI, progression, checkpoint persistence, and test hooks.

## Environment contract
`environment/facility.gd` extends Node3D, class_name Facility. `build()` creates facility. `markers: Dictionary` maps names to Vector3 positions: spawn, operations, power, cooling, network, cctv, core_access, core, exit, hub, maintenance. `interactables: Dictionary` maps IDs to StaticBody3D with metadata `interaction_id`, `label`. Root raycast reads metadata. IDs: operations, power, cooling, network, cctv, core_access, core, exit, note_power, note_cooling, note_network, note_security, badge. Build labels and terminals near markers. Methods `set_stage(stage: int)`, `set_door(id: String, opened: bool)`, `surface_at(pos: Vector3) -> String`. Door IDs elevator, core. `camera_points: Array` of dictionaries {name:String, position:Vector3, target:Vector3}. `anomaly_nodes: Dictionary` at least chair, sign, door. `route: Array[Vector3]` optional traversable chase path core to exit. Large compact interconnected hub and industrial detailed rooms. Coordinate Y up, floors at y=0, player markers y=0.1. Main doors and passages >=2.5m width, camera height 1.65. Room entry should allow terminal facing straightforwardly. Geometry colliders layer 1, interactable layer 2 (collision_layer=2). `lights: Array` optional. Labels readable in 3D. No dependence on other scripts except assets.

## Player / AI contract
`player/technician.gd` extends CharacterBody3D, class_name Technician. Sets its own collider and `camera: Camera3D`, flashlight. `locked: bool` prevents movement and mouse, `look_only: bool` permits looking with no translation, `settings: Dictionary`. Root creates, adds child, then positions. Signal `interacted(target: Object)` from center raycast <=3.4m; signal `footstep(surface: String)`; `interaction_target: Object` exposed; `surface_provider: Callable` optional. Methods `apply_settings(values: Dictionary)`, `is_observing(point: Vector3, radius: float=0.5) -> bool` with FOV, distance and occlusion, `teleport(pos: Vector3, yaw: float=0.0)`. No global/autoload dependencies. Controls WASD, shift sprint, C/ctrl crouch, F flashlight, E interact via physical keys. Do not handle ESC.
`ai/observer.gd` extends Node3D, class_name Observer. `setup(player_ref: CharacterBody3D, facility_ref: Node3D)`, `set_phase(phase: int)`, `begin_chase()`, `stop()`, signal `caught`. Expose state_name, tension, visible_to_player. Early sightings at phase 2 and 3; chase only begin_chase. Reliable graph pathfinding or player breadcrumb route around level geometry; no teleport during pursuit. Early silhouette no pop while observed. CCTV humanoid factory may be public `create_body() -> Node3D`. `process_mode` inherits to respect pause.

## Audio contract
`audio/soundscape.gd` extends Node3D class_name Soundscape. `setup(player_ref, facility_ref)`, `set_tension(value: float)`, `play_cue(id: String, position: Vector3=Vector3.INF)`, `step(surface: String)`, `apply_settings(values: Dictionary)`. Generates/loads original wav in assets/audio. Ambient ventilation, electrical and HVAC spatial sources, subtle drone (Music bus), footsteps variants surface concrete/metal/grating/tile/wet, chime, click, door, drag, radio messages or abstract signal. Native audio only. No microphone.

## Shared settings keys
master/music/sfx normalized 0..1; fov (82), sensitivity (0.11 degrees/pixel), invert_y false, brightness 1.0, head_bob 1 (0 off /1 low /2 normal), reduced_flashes true, reduced_shake true, subtitles true, preset 2 (0 low/1 medium/2 high/3 ultra), window_mode 0 (window/1 borderless/2 fullscreen), resolution 1 (1280x720/1920x1080/2560x1440/3840x2160), fps_limit 60, vsync true. Microphone not implemented.

## Narrative
Stages ordered arrival(0), operations(1), power repair(2), power restored(3), cooling repair(4), cooling restored(5), network repair(6), network restored(7), CCTV discovery(8), core access(9), core reveal(10), failure(11), chase(12), elevator escape(13), ending(14). Restoration status derived from stage, not scattered booleans.
