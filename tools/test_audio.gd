extends SceneTree
## Focused runtime audio checks. Run with the pinned Godot editor --headless --script.

class TestRoom extends Node3D:
	var markers := {"cooling": Vector3(10, 0, 0), "power": Vector3(-10, 0, 0), "network": Vector3(0, 0, -12), "hub": Vector3.ZERO}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var player := CharacterBody3D.new()
	world.add_child(player)
	var room := TestRoom.new()
	world.add_child(room)
	var sound := Soundscape.new()
	world.add_child(sound)
	sound.setup(player, room)
	sound.apply_settings({"master": .75, "music": .5, "sfx": .65})
	for id in Soundscape.CUES:
		check(sound._streams.has(id) and sound._streams[id] != null, "Missing cue " + id)
	check(sound._spatial.size() == 4, "Expected four spatial ambience emitters")
	for stream in sound._spatial:
		check(stream.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Ambient stream is not looping")
		check(stream.playing, "Ambient stream is not playing")
	for material in Soundscape.SURFACES:
		var previous := -1
		for sample in range(16):
			sound.step(material)
			check(sound._last_step[material] != previous, "Immediate repeated footstep " + material)
			previous = sound._last_step[material]
	sound.play_cue("drag", Vector3(4, 1, 2))
	sound.play_cue("drag", Vector3(4, 1, 2))
	check(sound._active_cues.size() == 1, "Duplicate named cue was not suppressed")
	sound.play_cue("elevator")
	check(sound._streams["elevator"].loop_mode == AudioStreamWAV.LOOP_FORWARD, "Elevator motor does not sustain the full descent")
	sound.stop_cue("elevator")
	sound.play_cue("radio_arrival")
	check(sound._radio.playing, "Radio did not play")
	await create_timer(.15).timeout
	paused = true
	await create_timer(.12, true).timeout
	check(not sound.can_process(), "World sound continues processing while paused")
	check(sound._radio.stream_paused, "Radio did not pause")
	check(sound._ambience.stream_paused, "Ambient bed did not pause")
	sound.play_cue("click")
	check(sound._interface.can_process(), "Interface click is blocked by pause")
	paused = false
	await create_timer(.15).timeout
	check(not sound._radio.stream_paused, "Radio did not resume")
	var mix_peak := AudioServer.get_bus_peak_volume_left_db(AudioServer.get_bus_index("Master"), 0)
	print("AUDIO_DRIVER: %s | device=%s | master_peak=%.2f dBFS" % [AudioServer.get_driver_name(), AudioServer.output_device, mix_peak])
	if "--hardware-audio" in OS.get_cmdline_user_args():
		check(AudioServer.get_driver_name() != "Dummy", "Hardware audio fell back to Dummy")
		check(mix_peak > -65.0, "Hardware mixer produced no meaningful output")
	sound.apply_settings({"master": 0.0, "music": 0.0, "sfx": 0.0})
	for bus in ["Master", "Music", "SFX", "Radio"]:
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index(bus)), "Bus mute failed " + bus)
	var bus_count := AudioServer.bus_count
	sound._create_buses()
	check(bus_count == AudioServer.bus_count, "Reinitialization duplicates audio buses")
	world.queue_free()
	# The audio server releases stream playback objects on its own mixing thread.
	await create_timer(.35).timeout
	print("AUDIO_VALIDATION: " + ("PASS" if failures.is_empty() else "FAIL") + " | 46 resources, surface variation, loops, duplicate suppression, pause/resume, mute, bus reuse")
	quit(0 if failures.is_empty() else 1)
