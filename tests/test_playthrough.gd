extends SceneTree
## Full production flow: menu buttons, actual capsule walks, center-ray E use,
## terminal buttons, failed puzzle attempts, pursuit interlocks and the ending.
## Godot --fixed-fps 60 --path . --script tests/test_playthrough.gd
## Requires a native display: headless mode cannot capture the gameplay mouse.

const GameScript = preload("res://systems/game.gd")
var game: Node3D
var failures: Array[String] = []
var directory: String
var total_distance := 0.0
var _finishing := false

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> bool:
	if _finishing: return condition
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)
	return condition

func _frames(count: int) -> void:
	for tick in range(count):
		await physics_frame

func _click(text: String) -> void:
	for node in game.hud.find_children("*", "Button", true, false):
		if node.text == text and node.is_visible_in_tree() and not node.disabled:
			node.pressed.emit()
			await process_frame
			return
	_check(false, "Usable UI button exists: " + text + " (context " + game.modal_context + ")")
	_finish()
	await process_frame

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame

func _await_stage(expected: int, frame_limit: int) -> void:
	for tick in range(frame_limit):
		if game.stage == expected:
			_check(true, "Story reaches stage %d through production events" % expected)
			return
		await physics_frame
	_check(false, "Story reaches stage %d (actual %d)" % [expected, game.stage])
	_finish()
	await process_frame

func _walk_to(destination: Vector3) -> void:
	if _finishing: return
	var path: Array[Vector3] = game.level.find_path(game.player.global_position, destination)
	for waypoint in path:
		if _finishing: return
		var reached := false
		for tick in range(1800):
			var delta: Vector3 = waypoint - game.player.global_position
			delta.y = 0.0
			if delta.length() < 0.16:
				reached = true
				break
			if not game.playing or game.modal:
				_check(false, "Walking remained playable (context " + game.modal_context + ")")
				_finish()
				await process_frame
				return
			game.player.rotation.y = atan2(-delta.x, -delta.z)
			game.player.camera.rotation = Vector3.ZERO
			game.player.set_test_input(Vector2(0, -1), delta.length() > 1.0)
			await physics_frame
		game.player.set_test_input(Vector2.ZERO)
		await _frames(16)
		if not reached:
			_check(false, "Walk reaches %s from actual position %s" % [waypoint, game.player.global_position])
			_finish()
			await process_frame
			return

func _use(id: String) -> void:
	if _finishing: return
	print("VISIT ", id, " / stage ", game.stage)
	for attempt in range(3):
		var approach: Dictionary = game.level.interaction_approaches[id]
		await _walk_to(approach.position)
		var target: Node3D = game.level.interactables[id]
		if game.player.camera.global_position.distance_to(target.global_position) <= 3.25:
			break
	var target: Node3D = game.level.interactables[id]
	var delta: Vector3 = target.global_position - game.player.camera.global_position
	game.player.rotation.y = atan2(-delta.x, -delta.z)
	game.player.camera.look_at(target.global_position)
	await _frames(3)
	if not _check(game.player.interaction_target == target, "Center ray reaches " + id + " after a real walk"):
		_finish()
		await process_frame
		return
	await _key(KEY_E)

func _finish() -> void:
	if _finishing: return
	_finishing = true
	paused = false
	if is_instance_valid(game):
		game.playing = false
		total_distance = game.player.distance_walked
		game.player.clear_test_input()
		game.sound.clear_cues()
	for suffix in ["", ".backup", ".tmp"]:
		var path: String = directory + "/checkpoint.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
	print("FULL_PLAYTHROUGH: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size(), " / walked=", snappedf(total_distance, 0.1), "m")
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Full input verification requires a display; run without --headless (a virtual X11 display is also supported).")
		quit(2)
		return
	directory = "user://verification_playthrough_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	game = GameScript.new()
	game.saves.path = directory + "/checkpoint.json"
	root.add_child(game)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await process_frame
	_check(game.hud.view == "main" and not game.saves.can_continue(), "Boot opens the real main menu with Continue disabled on a fresh profile")
	await _click("NEW GAME")
	await _await_stage(1, 1500)
	_check(absf(game.player.global_position.y) < 0.3 and not game.player.look_only, "Arrival elevator carries the technician to B6 and releases movement")
	await _key(KEY_ESCAPE)
	_check(paused and game.hud.view == "pause", "Escape pauses the world and opens the pause menu")
	await _click("RESUME")
	_check(not paused and not game.player.locked, "Resume restores captured gameplay")
	await _use("operations")
	_check(game.stage == 2 and game.modal, "Operations work order begins electrical repair")
	await _click("CLOSE  /  ESC")
	await _use("fuse")
	_check(game.repairs.inventory.has("fuse"), "Service carrier pickup reaches inventory")
	await _use("note_power")
	await _click("CLOSE  /  ESC")
	await _use("power")
	await _click("FIT REPLACEMENT CARRIER")
	_check(not game.repairs.carrier_fitted, "Terminal rejects fitting carrier before isolating bus")
	await _click("ISOLATE DISTRIBUTION BUS")
	await _click("FIT REPLACEMENT CARRIER")
	await _click("CLOSE CIRCUIT 2")
	await _click("CLOSE CIRCUIT 3")
	_check(game.repairs.power_steps.is_empty() and game.stage == 2, "Wrong startup order resets electrical puzzle without advancing story")
	for circuit in [2, 1, 3]: await _click("CLOSE CIRCUIT %d" % circuit)
	_check(game.stage == 3 and game.repairs.power_solved, "Electrical puzzle updates actual facility progression")
	await _click("CLOSE  /  ESC")
	await _use("pump_a")
	await _use("pump_b")
	await _use("note_cooling")
	await _click("CLOSE  /  ESC")
	await _use("cooling")
	await _click("RUN PRESSURE TEST")
	_check(not game.repairs.cooling_solved, "Uncalibrated pressure test fails through actual UI")
	for valve in range(3):
		for turn in [2, 4, 3][valve]:
			await _click("%s / %d > %d" % [["A / INLET", "B / BYPASS", "C / RETURN"][valve], turn, turn + 1])
	await _click("RUN PRESSURE TEST")
	_check(game.stage == 5 and game.repairs.cooling_solved, "Calibrated pumps restore cooling")
	await _click("CLOSE  /  ESC")
	await _use("module")
	_check(game.repairs.inventory.has("module"), "Archive corridor module is reachable and collected after anomaly changes")
	await _use("note_network")
	await _click("CLOSE  /  ESC")
	await _use("network")
	await _click("SEAT OFFLINE BRIDGE")
	for port in [1, 2, 3]: await _click("PATCH PORT %d" % port)
	await _click("VERIFY AND COMMIT")
	_check(not game.repairs.network_solved, "Wrong uplink order cannot bypass network puzzle")
	await _click("CLEAR PATCH")
	for port in [6, 1, 4]: await _click("PATCH PORT %d" % port)
	await _click("VERIFY AND COMMIT")
	_check(game.stage == 7 and game.repairs.network_solved, "Correct uplinks restore network and surveillance")
	await _click("CLOSE  /  ESC")
	await _use("cctv")
	await _click("CAM 06-14 / SERVICE HALL")
	_check(game.stage == 8 and game.scares.events.has("cctv_double"), "Selecting live incident camera reveals the duplicate and unlocks access progression")
	await _click("CLOSE  /  ESC")
	await _use("badge")
	await _use("note_security")
	await _click("CLOSE  /  ESC")
	await _use("core_access")
	for digit in [1, 1, 1]: await _click(str(digit))
	await _click("VERIFY CREDENTIAL")
	_check(game.stage == 9 and game.modal, "Wrong PIN keeps the core sealed with a retryable prompt")
	for digit in [6, 1, 4]: await _click(str(digit))
	await _click("VERIFY CREDENTIAL")
	_check(game.stage == 10 and not game.modal, "Badge and correct PIN open the physical core airlock")
	await _use("core")
	await _click("TERMINATE REMOTE PROCESS")
	await _await_stage(12, 600)
	_check(game.observer.state_name == "PURSUIT", "Isolation failure begins physical pursuit")
	await _use("power")
	_check(game.repairs.brake_released, "Electrical control releases emergency lift brake during pursuit")
	await _use("cooling")
	_check(game.repairs.line_purged, "Cooling control purges emergency lift line during pursuit")
	# The rear service loop avoids retracing the route the presence followed.
	await _walk_to(Vector3(19.4, 0.1, -20))
	await _walk_to(Vector3(-15, 0.1, -20))
	await _walk_to(Vector3(-15, 0.1, -2))
	await _use("exit")
	await _await_stage(14, 1800)
	_check(game.modal_context == "ending" and not game.saves.can_continue(), "Escaping elevator reaches the ending and records the completed shift")
	await _click("MAIN MENU")
	_check(game.hud.view == "main" and not game.playing, "Ending returns to the functional main menu")
	_finish()
