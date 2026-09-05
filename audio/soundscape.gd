extends Node3D
class_name Soundscape
## Original industrial sound library with restrained, continuous dynamics.
## All authoring is offline; the released game only loads packaged WAV assets.

const AUDIO_PATH := "res://assets/audio/"
const SURFACES := ["concrete", "metal", "grating", "tile", "wet"]
const CUES := ["chime", "click", "door", "drag", "radio", "success", "error",
	"power", "cooling", "network", "failure", "heartbeat", "breath", "elevator", "shutdown",
	"radio_arrival", "radio_power", "radio_cooling", "radio_network", "radio_core", "radio_escape"]
const RADIO_TRANSCRIPTS := {
	"radio_arrival": "Sector Six lost telemetry forty minutes ago. Check the operations terminal. We will monitor your progress from upstairs.",
	"radio_power": "Power has returned. The overnight team may be in the cooling gallery. Restore circulation before reconnecting the network.",
	"radio_cooling": "We have your pressure readings. You are the only technician currently assigned to this level.",
	"radio_network": "Do not reconnect the network. That maintenance order was withdrawn. Can you hear me? Do not reconnect.",
	"radio_core": "This is a containment system. They turned it off on purpose. Your work order was issued from inside Sector Six.",
	"radio_escape": "The elevator is responding. Release the brake in electrical. Purge the lift line in cooling. Return to the lift. Keep moving."
}

var player: Node3D
var facility: Node3D
var tension := 0.05
var silence := 0.0
var _streams: Dictionary = {}
var _spatial: Array[AudioStreamPlayer3D] = []
var _spatial_base: Dictionary = {}
var _active_cues: Dictionary = {}
var _last_step: Dictionary = {}
var _ambience: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _steps: AudioStreamPlayer
var _interface: AudioStreamPlayer
var _radio: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _occlusion_clock := 0.0
var _started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_rng.randomize()
	_create_buses()
	for id in CUES:
		_cache(id, id == "elevator")
	for material in SURFACES:
		for index in range(1, 5):
			_cache("step_%s_%d" % [material, index])
	_ambience = _make_flat("ambience", "SFX", -23.0, true)
	_drone = _make_flat("drone", "Music", -46.0, true)
	_steps = AudioStreamPlayer.new()
	_steps.bus = "SFX"
	_steps.volume_db = -11.0
	_steps.max_polyphony = 3
	add_child(_steps)
	_interface = AudioStreamPlayer.new()
	_interface.bus = "SFX"
	_interface.volume_db = -18.0
	_interface.max_polyphony = 3
	_interface.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_interface)
	_radio = AudioStreamPlayer.new()
	_radio.bus = "Radio"
	_radio.volume_db = -8.0
	add_child(_radio)


func setup(player_ref: Node3D, facility_ref: Node3D) -> void:
	player = player_ref
	facility = facility_ref
	if _started:
		return
	_started = true
	_ambience.play()
	_drone.play()
	var points: Dictionary = facility.get("markers") if facility != null else {}
	_spawn_ambient("hvac", points.get("cooling", Vector3(14, 1, -8)) + Vector3(0, 1.8, 0), -16.0, 30.0)
	_spawn_ambient("electrical", points.get("power", Vector3(-14, 1, -8)) + Vector3(0, 1, 0), -20.0, 18.0)
	_spawn_ambient("servers", points.get("network", Vector3(0, 1, -15)) + Vector3(0, 1.5, 0), -18.0, 26.0)
	_spawn_ambient("servers", points.get("hub", Vector3.ZERO) + Vector3(0, 2.6, -5), -24.0, 20.0)


func _create_buses() -> void:
	for bus_name in ["SFX", "Music", "Radio"]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")
		if bus_name == "SFX":
			var reverb := AudioEffectReverb.new()
			reverb.room_size = 0.56
			reverb.damping = 0.65
			reverb.wet = 0.13
			reverb.dry = 0.94
			reverb.predelay_msec = 34.0
			AudioServer.add_bus_effect(index, reverb)
		elif bus_name == "Radio":
			var compressor := AudioEffectCompressor.new()
			compressor.threshold = -14.0
			compressor.ratio = 2.5
			compressor.attack_us = 3000.0
			compressor.release_ms = 140.0
			AudioServer.add_bus_effect(index, compressor)


func _cache(id: String, looping: bool = false) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var path := AUDIO_PATH + id + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Missing sound asset: " + path)
		return null
	var stream: AudioStream = load(path)
	if looping and stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_streams[id] = stream
	return stream


func _make_flat(id: String, bus_name: String, gain: float, looping: bool) -> AudioStreamPlayer:
	var source := AudioStreamPlayer.new()
	source.name = id.capitalize()
	source.stream = _cache(id, looping)
	source.bus = bus_name
	source.volume_db = gain
	add_child(source)
	return source


func _spawn_ambient(id: String, at: Vector3, gain: float, distance: float) -> void:
	var source := AudioStreamPlayer3D.new()
	source.stream = _cache(id, true)
	source.bus = "SFX"
	source.volume_db = gain
	source.max_db = 0.0
	source.unit_size = 7.0
	source.max_distance = distance
	source.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	source.attenuation_filter_cutoff_hz = 6500.0
	source.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	add_child(source)
	source.global_position = at
	_spatial.append(source)
	_spatial_base[source] = gain
	source.play(_rng.randf_range(0, source.stream.get_length()))


func set_tension(value: float) -> void:
	tension = clampf(value, 0.0, 1.0)


func set_silence(value: float) -> void:
	## Used during deliberate narrative silence. The ventilation remains barely audible.
	silence = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _started:
		return
	var ambience_target := -23.0 - 15.0 * silence
	var drone_target := lerpf(-46.0, -15.0, pow(tension, 1.5)) - 22.0 * silence
	# Slow movement between beds prevents sudden cinematic stingers.
	_ambience.volume_db = move_toward(_ambience.volume_db, ambience_target, delta * 4.0)
	_drone.volume_db = move_toward(_drone.volume_db, drone_target, delta * 2.1)
	_occlusion_clock += delta
	if _occlusion_clock < 0.25 or not is_instance_valid(player):
		return
	_occlusion_clock = 0.0
	var ear := player.global_position + Vector3(0, 1.5, 0)
	var exclusions: Array[RID] = []
	if player is CollisionObject3D:
		exclusions.append(player.get_rid())
	for source in _spatial:
		var ray := PhysicsRayQueryParameters3D.create(ear, source.global_position, 1, exclusions)
		var occluded := not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		var target: float = float(_spatial_base[source]) - 16.0 * silence - (9.0 if occluded else 0.0)
		source.volume_db = lerpf(source.volume_db, target, 0.18)
		source.attenuation_filter_cutoff_hz = lerpf(source.attenuation_filter_cutoff_hz, 1250.0 if occluded else 6500.0, 0.2)


func play_cue(id: String, at: Vector3 = Vector3.INF) -> void:
	var aliases := {"ding": "chime", "alarm": "failure", "static": "radio", "confirm": "success", "deny": "error", "valve": "cooling", "relay": "click", "light": "click", "footstep": "step_concrete_2"}
	var cue: String = aliases.get(id, id)
	if cue == "click" or cue == "error" or cue == "success":
		_interface.stream = _cache(cue)
		_interface.play()
		return
	if cue.begins_with("radio_"):
		_radio.stream = _cache(cue)
		_radio.play()
		return
	var stream: AudioStream = _cache(cue)
	if stream == null:
		return
	# A named event cannot accidentally duplicate itself while still playing.
	if _active_cues.has(cue) and is_instance_valid(_active_cues[cue]):
		return
	var source: Node
	if at.is_finite():
		var spatial := AudioStreamPlayer3D.new()
		spatial.stream = stream
		spatial.bus = "SFX"
		spatial.volume_db = -9.0 if cue == "drag" else -12.0
		spatial.unit_size = 6.0
		spatial.max_distance = 38.0
		spatial.max_db = 0.0
		spatial.attenuation_filter_cutoff_hz = 4800.0
		add_child(spatial)
		spatial.global_position = at
		spatial.play()
		source = spatial
	else:
		var flat := AudioStreamPlayer.new()
		flat.stream = stream
		flat.bus = "SFX"
		flat.volume_db = -11.0 if cue == "chime" else -15.0
		add_child(flat)
		if cue == "elevator":
			flat.volume_db = -48.0
			flat.create_tween().tween_property(flat, "volume_db", -15.0, 1.3)
		flat.play()
		source = flat
	_active_cues[cue] = source
	source.finished.connect(func() -> void:
		_active_cues.erase(cue)
		source.queue_free()
	)


func stop_cue(id: String) -> void:
	if id.begins_with("radio_"):
		_radio.stop()
	if _active_cues.has(id) and is_instance_valid(_active_cues[id]):
		_active_cues[id].queue_free()
	_active_cues.erase(id)


func clear_cues() -> void:
	## Clear old narrative audio when restarting, loading or returning to the menu.
	_radio.stop()
	_steps.stop()
	for source in _active_cues.values():
		if is_instance_valid(source):
			source.stop()
			source.queue_free()
	_active_cues.clear()
	silence = 0.0


func step(surface: String) -> void:
	var material := surface if SURFACES.has(surface) else "concrete"
	var previous: int = _last_step.get(material, 0)
	var index := _rng.randi_range(1, 4)
	if index == previous:
		index = index % 4 + 1
	_last_step[material] = index
	_steps.stream = _streams["step_%s_%d" % [material, index]]
	_steps.pitch_scale = _rng.randf_range(0.955, 1.045)
	_steps.volume_db = -12.0 + _rng.randf_range(-1.0, 0.6)
	_steps.play()


func apply_settings(values: Dictionary) -> void:
	_create_buses()
	for pair in [["Master", "master"], ["Music", "music"], ["SFX", "sfx"], ["Radio", "sfx"]]:
		var index := AudioServer.get_bus_index(pair[0])
		var gain := clampf(float(values.get(pair[1], 0.8)), 0.0, 1.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(gain, 0.0001)))
		AudioServer.set_bus_mute(index, gain <= 0.0001)
