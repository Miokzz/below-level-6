extends SceneTree
## Runtime load/retry/cancellation cases use a solved checkpoint fixture.
## The successful walk is independently covered by test_playthrough.gd.
## Godot --headless --fixed-fps 60 --path . --script tests/test_session_recovery.gd

const GameScript = preload("res://systems/game.gd")
const RepairScript = preload("res://puzzles/repair_state.gd")
const SaveScript = preload("res://systems/checkpoints.gd")
var game: Node3D
var failures: Array[String] = []
var directory: String

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition: print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _frames(count: int) -> void:
	for tick in range(count): await physics_frame

func _click(text: String) -> void:
	for button in game.hud.find_children("*", "Button", true, false):
		if button.text == text and button.is_visible_in_tree() and not button.disabled:
			button.pressed.emit()
			await process_frame
			return
	_check(false, "Expected usable menu button: " + text)

func _escape_key() -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await process_frame

func _fixture() -> Dictionary:
	var repairs := RepairScript.new()
	repairs.collect("fuse")
	repairs.operate("isolate")
	repairs.operate("fit_fuse")
	for circuit in [2, 1, 3]: repairs.operate("circuit", circuit)
	repairs.operate("pump_a")
	repairs.operate("pump_b")
	for valve in range(3):
		for turn in [2, 4, 3][valve]: repairs.operate("valve", valve)
	repairs.operate("test_pressure")
	repairs.collect("module")
	repairs.operate("fit_module")
	for port in [6, 1, 4]: repairs.operate("link", port)
	repairs.operate("commit_network")
	repairs.collect("badge")
	return {"stage": 10, "checkpoint": "core_access", "repairs": repairs.snapshot(), "elapsed": 340.0,
		"events": {"chair_0": true, "chair_1": true, "chair_2": true, "sign_changed": true, "corridor_2": true, "light_chase_started": true, "light_chase_0": true},
		"observer_events": {"cooling": true, "network": true}, "radio_events": {"radio_arrival": true, "radio_power": true}}

func _run() -> void:
	directory = "user://verification_recovery_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var saves := SaveScript.new()
	saves.path = directory + "/checkpoint.json"
	_check(saves.save_checkpoint(_fixture()), "Safe solved checkpoint fixture passes production validation")
	game = GameScript.new()
	game.saves.path = saves.path
	root.add_child(game)
	Engine.max_fps = 0
	await process_frame
	await _click("CONTINUE")
	await _frames(110)
	_check(game.playing and game.stage == 10 and not paused and not game.player.locked, "Continue restores a playable core checkpoint with correct input and pause state")
	_check(game.player.global_position.distance_to(game.level.markers.core_access) < 0.3 and game.level.is_door_open("core"), "Loaded player occupies the safe airlock landing with its physical core door open")
	_check(game.repairs.network_solved and game.repairs.inventory.has("badge") and game.level.interactables.badge.collision_layer == 0, "Loaded repairs and inventory remove the previously collected world badge")
	_check(not game.level.anomaly_nodes.chair.visible and game.level.anomaly_nodes.sign.text == "NO EXIT   /   B6", "Runtime Continue reapplies persisted psychological world changes")
	_check(game.scares.events.has("light_chase_1"), "Partially saved light sequence resumes through normal game processing")
	_check(game.observer.state_name == "ABSENT" and game.observer.get_event_flags().size() == 2, "Seen early presences remain consumed after Continue")
	_check(game.sound.get_radio_state().heard.has("radio_arrival") and game.sound.get_radio_state().heard.has("radio_power"), "Continue restores completed radio history without replaying heard messages")
	# Invoke the production narrative event from an existing safe loaded state.
	game._failure(game.session_token)
	await _frames(45)
	await _escape_key()
	await _frames(360)
	_check(paused and game.stage == 11, "Pausing during blackout freezes the failure sequence")
	await _click("RESUME")
	for tick in range(600):
		if game.stage == 12: break
		await physics_frame
	_check(game.stage == 12 and game.observer.state_name == "PURSUIT", "Resuming blackout starts pursuit once")
	for tick in range(2400):
		if game.modal_context == "death": break
		await physics_frame
	_check(game.modal_context == "death" and paused and not game.playing, "Real pursuit capture opens the death/retry menu")
	_check(game.saves.load_checkpoint().stage == 10, "Being caught preserves the safe checkpoint preceding pursuit")
	await _click("RETRY FROM CHECKPOINT")
	await _frames(100)
	_check(game.stage == 10 and game.playing and not game.modal and not paused, "Retry loads a playable core checkpoint without repeating completed repairs")
	_check(game.observer.state_name == "ABSENT" and game.observer.get_node("Presence").collision_layer == 0, "Retry clears the pursuing body and its collision obstruction")
	await _escape_key()
	await _click("MAIN MENU")
	var corrupt := FileAccess.open(saves.path, FileAccess.WRITE)
	corrupt.store_string("interrupted checkpoint write")
	corrupt.close()
	await _click("CONTINUE")
	await _frames(5)
	_check(game.stage == 10 and game.playing and game.saves.last_error == "Recovered the previous checkpoint.", "Continue recovers a damaged main file into the last validated core checkpoint")
	_check(game.player.global_position.distance_to(game.level.markers.core_access) < 0.3, "Recovered backup uses the safe core landing")
	game._finish()
	_check(game.modal_context == "ending" and game.saves.load_checkpoint().stage == 14 and not game.saves.can_continue(), "Production ending records completion and removes stale Continue availability")
	await _click("MAIN MENU")
	var continue_disabled := false
	for button in game.hud.find_children("*", "Button", true, false):
		if button.text == "CONTINUE": continue_disabled = button.disabled
	_check(continue_disabled and game.hud.view == "main", "Completed shift returns to a main menu with Continue visibly disabled")
	paused = false
	for suffix in ["", ".backup", ".tmp"]:
		var path: String = saves.path + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	game.sound.shutdown()
	game.queue_free()
	# Let the real mixing thread release playback after the accelerated simulation.
	for tick in range(10):
		await process_frame
		OS.delay_msec(35)
	print("SESSION_RECOVERY_VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
