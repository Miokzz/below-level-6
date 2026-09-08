extends Node3D
## Integrates the original facility, technician, soundscape and Observer.

const FacilityScript = preload("res://environment/facility.gd")
const PlayerScript = preload("res://player/technician.gd")
const ObserverScript = preload("res://ai/observer.gd")
const SoundScript = preload("res://audio/soundscape.gd")
const ScareScript = preload("res://narrative/scare_director.gd")
const RepairScript = preload("res://puzzles/repair_state.gd")
const SaveScript = preload("res://systems/checkpoints.gd")
const SettingsScript = preload("res://systems/settings.gd")
const UIScript = preload("res://ui/game_ui.gd")

enum Stage { ARRIVAL, OPERATIONS, POWER_REPAIR, POWER_ONLINE, COOLING_REPAIR,
	COOLING_ONLINE, NETWORK_REPAIR, NETWORK_ONLINE, CCTV_DISCOVERY, CORE_ACCESS,
	CORE_REVEAL, FAILURE, CHASE, ELEVATOR_ESCAPE, ENDING }

const DOCUMENTS := {
	"note_power": ["DISTRIBUTION / RESET", "BUS 06 — ISOLATION PROCEDURE\n\n1. Isolate distribution before fitting the replacement carrier.\n2. Carrier stock: service workbench beside the arrival lift.\n3. Close circuits in startup order: 2 > 1 > 3.\n\nAn incorrect order trips the interlock. Reset the sequence; do not remove a seated carrier."],
	"note_cooling": ["COOLANT / CALIBRATION", "LOCAL PUMPS\nStart PRIMARY near the hub and RETURN at the rear of the cooling gallery.\n\nCommissioning setpoints:\nA / INLET: 2\nB / BYPASS: 4\nC / RETURN: 3\n\nSet all three actuators, then run the pressure test. Each selector cycles through 0–5. The bypass keeps pressure off the lift line."],
	"note_network": ["UPLINK / RESTORE", "Bridge 06 must remain in OFFLINE COLD STORAGE through Operations / Archive until rack cooling is stable.\n\nAssign three distinct uplinks:\nCHANNEL I > PORT 6\nCHANNEL II > PORT 1\nCHANNEL III > PORT 4\n\nVerify all links before COMMIT. A failed verification leaves the patch editable."],
	"note_security": ["INTERNAL / SECURITY", "CORE ACCESS: 6 1 4\nSecurity badge required. Spare credentials: desk opposite the video wall.\n\nTWO PERSON RULE — DO NOT ENTER ALONE\n\n02:14:06 / Shift amendment\nThe second operator is already inside. No second badge was issued.\n\nEmergency lift release: electrical brake, then cooling line purge. Both controls are local and remain available after a network failure."]
}

var level: Node3D
var player: CharacterBody3D
var observer: Node3D
var sound: Node3D
var hud: CanvasLayer
var scares: Node
var settings: Node
var repairs: RefCounted = RepairScript.new()
var saves: RefCounted = SaveScript.new()
var world: Node3D
var stage: int = Stage.ARRIVAL
var playing := false
var modal := false
var session_token := 0
var modal_context := ""
var _pin := ""
var _feedback := ""
var _feedback_time := 0.0
var _elapsed := 0.0
var _checkpoint_clock := 0.0
var _environment: Environment
var _fade: ColorRect
var _fade_tween: Tween
var _feed: SubViewport
var _feed_camera: Camera3D
var _double: Node3D
var _player_proxy: Node3D
var _feed_index := 0
var _feed_clock := 0.0
var _safe_snapshot: Dictionary = {}
var _ending_seen := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	settings = SettingsScript.new()
	add_child(settings)
	settings.load_settings()
	world = Node3D.new()
	world.name = "Shift"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	_setup_environment()
	level = FacilityScript.new()
	world.add_child(level)
	level.build()
	player = PlayerScript.new()
	world.add_child(player)
	player.teleport(level.markers.spawn)
	player.surface_provider = level.surface_at
	observer = ObserverScript.new()
	world.add_child(observer)
	observer.setup(player, level)
	sound = SoundScript.new()
	world.add_child(sound)
	sound.setup(player, level)
	level.mechanism_cue.connect(func(id: String, at: Vector3): sound.play_cue(id, Vector3.INF if id == "elevator" else at))
	scares = ScareScript.new()
	world.add_child(scares)
	scares.game = self
	hud = UIScript.new()
	add_child(hud)
	hud.setup(settings)
	hud.new_game_requested.connect(_new_game_requested)
	hud.continue_requested.connect(continue_game)
	hud.resume_requested.connect(_resume)
	hud.menu_requested.connect(return_to_menu)
	hud.quit_requested.connect(_quit)
	hud.choice_selected.connect(_choice)
	hud.modal_closed.connect(_close_modal)
	hud.settings_changed.connect(_settings_changed)
	hud.ui_sound.connect(func(): sound.play_cue("click"))
	player.interacted.connect(_interact)
	player.footstep.connect(sound.step)
	player.flashlight_changed.connect(func(_enabled: bool): sound.play_cue("click"))
	observer.caught.connect(_caught)
	sound.subtitle_changed.connect(hud.show_subtitle)
	_setup_cctv()
	_setup_fade()
	_settings_changed(settings.values)
	return_to_menu()

func _setup_environment() -> void:
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color("080f12")
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color("7a9999")
	_environment.ambient_light_energy = 0.31
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.fog_enabled = true
	_environment.fog_light_color = Color("263939")
	_environment.fog_light_energy = 0.35
	_environment.fog_density = 0.008
	environment_node.environment = _environment
	world.add_child(environment_node)

func _setup_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_fade)
	_fade.modulate.a = 0.0

func _setup_cctv() -> void:
	_feed = SubViewport.new()
	_feed.size = Vector2i(768, 432)
	_feed.world_3d = get_world_3d()
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_feed.audio_listener_enable_3d = false
	add_child(_feed)
	_feed_camera = Camera3D.new()
	_feed_camera.fov = 70
	_feed_camera.cull_mask = 1 | (1 << 19)
	_feed.add_child(_feed_camera)
	_feed_camera.current = true
	_feed_camera.global_position = level.camera_points[0].position
	_feed_camera.look_at(level.camera_points[0].target)
	level.bind_cctv_texture(_feed.get_texture())
	_double = observer.create_body()
	world.add_child(_double)
	_set_visual_layer(_double, 1 << 19)
	_double.hide()
	_player_proxy = observer.create_body()
	world.add_child(_player_proxy)
	_player_proxy.scale = Vector3(0.82, 0.77, 0.82)
	_set_visual_layer(_player_proxy, 1 << 19)
	player.camera.cull_mask = 1 | (1 << 18)

func _set_visual_layer(node: Node, mask_value: int) -> void:
	if node is GeometryInstance3D: node.layers = mask_value
	for child in node.get_children(): _set_visual_layer(child, mask_value)

func _settings_changed(_values: Dictionary) -> void:
	settings.apply_runtime(player, level, sound)
	_environment.ambient_light_energy = 0.31 * float(settings.values.get("brightness", 1.0))
	if not bool(settings.values.get("subtitles", true)): hud.show_subtitle("")

func _new_game_requested() -> void:
	start_new_game()

func _reset_session() -> void:
	get_tree().paused = false
	session_token += 1
	playing = false
	modal = false
	modal_context = ""
	_checkpoint_clock = 0.0
	_feedback = ""
	_feedback_time = 0.0
	_pin = ""
	if _fade_tween != null: _fade_tween.kill()
	_fade.modulate.a = 0.0
	observer.stop()
	sound.clear_cues()
	sound.restore_radio_state({})
	level.reset_elevator(false)
	level.reset_anomalies()
	scares.restore({})
	level.set_door("core", false)
	level.reset_interactions()
	_double.hide()
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ending_seen = false

func start_new_game() -> void:
	_reset_session()
	repairs = RepairScript.new()
	_elapsed = 0.0
	_safe_snapshot = {}
	observer.restore_event_flags({})
	playing = true
	sound.set_active(true)
	stage = Stage.ARRIVAL
	level.set_stage(stage)
	level.reset_elevator(true)
	player.teleport(level.markers.spawn + Vector3.UP * 30.0)
	player.locked = false
	player.look_only = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_game()
	hud.set_objective("NIGHT SHIFT 03 / Descend to Sector 06")
	_fade.modulate.a = 1.0
	_fade_to(0.0, 2.5)
	_intro(session_token)

func _intro(token: int) -> void:
	sound.play_radio("radio_arrival")
	var arrived: bool = await level.travel_elevator(false, player, 17.0)
	if token != session_token or not playing: return
	sound.stop_cue("elevator")
	if not arrived:
		level.reset_elevator(false)
		player.teleport(level.markers.spawn)
	level.set_door("elevator", true)
	player.look_only = false
	_set_stage(Stage.OPERATIONS)
	_checkpoint()
	_feedback_message("WASD / Move    SHIFT / Run    E / Use    F / Light    ESC / Pause", 12.0)

func continue_game() -> void:
	var data: Dictionary = saves.load_checkpoint()
	if data.is_empty() or int(data.stage) == Stage.ENDING:
		hud.show_document("SHIFT RECORD", saves.last_error if not saves.last_error.is_empty() else "This shift has ended. Begin a new shift from the menu.")
		modal_context = "menu_document"
		return
	_reset_session()
	repairs = RepairScript.new()
	repairs.restore(data.repairs)
	stage = int(data.stage)
	_elapsed = float(data.get("elapsed", 0.0))
	player.teleport(level.markers.get(data.get("checkpoint", "hub"), level.markers.hub))
	player.locked = false
	player.look_only = false
	observer.restore_event_flags(data.get("observer_events", {}))
	sound.restore_radio_state({"heard": data.get("radio_events", {}).keys()})
	scares.restore(data.get("events", {}))
	_set_stage(stage)
	level.set_door("elevator", true)
	for item in repairs.inventory: level.set_collected(item, true)
	for pump in repairs.pumps: level.set_pump_state(pump, repairs.pumps[pump])
	_safe_snapshot = data.duplicate(true)
	playing = true
	sound.set_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_game()
	_feedback_message("SHIFT RECORD RESTORED / " + _objective(), 7.0)

func return_to_menu() -> void:
	if playing and stage > Stage.ARRIVAL and stage < Stage.FAILURE: _checkpoint()
	session_token += 1
	playing = false
	modal = false
	modal_context = ""
	observer.stop()
	sound.clear_cues()
	sound.set_active(false)
	_double.hide()
	_feed.render_target_update_mode = SubViewport.UPDATE_DISABLED
	player.locked = true
	player.look_only = false
	if _fade_tween != null: _fade_tween.kill()
	_fade.modulate.a = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_main_menu(saves.can_continue())
	get_tree().paused = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if hud.handle_back():
			get_viewport().set_input_as_handled()
			return
		if playing:
			if get_tree().paused: _resume()
			else: _pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	modal = true
	modal_context = "pause"
	get_tree().paused = true
	player.locked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_pause()

func _resume() -> void:
	if not playing: return
	modal = false
	modal_context = ""
	player.locked = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_game()

func _process(delta: float) -> void:
	if not is_instance_valid(hud) or not playing: return
	if get_tree().paused: return
	_elapsed += delta
	_feedback_time = maxf(0.0, _feedback_time - delta)
	var target: Object = player.interaction_target
	var prompt := ""
	if is_instance_valid(target): prompt = "E / " + str(target.get_meta("label", "USE"))
	if _feedback_time > 0.0: prompt = _feedback
	hud.set_prompt(prompt)
	hud.set_objective(_objective())
	_player_proxy.position = player.position
	_player_proxy.rotation.y = player.rotation.y
	_feed_clock += delta
	if stage >= Stage.NETWORK_ONLINE and stage < Stage.FAILURE and _feed_clock >= 0.5:
		_feed_clock = 0.0
		if player.position.distance_to(level.markers.cctv) < 14.0:
			_feed.render_target_update_mode = SubViewport.UPDATE_ONCE
	_checkpoint_clock += delta
	if _checkpoint_clock >= 20.0 and stage >= Stage.OPERATIONS and stage <= Stage.CORE_REVEAL:
		_checkpoint()
	# The sole fall recovery uses an authored clear marker, never an arbitrary saved transform.
	if player.position.y < -3.0:
		if stage == Stage.CHASE: _caught()
		elif stage > Stage.ARRIVAL and stage < Stage.ELEVATOR_ESCAPE:
			player.teleport(level.markers.core_access if stage >= Stage.CORE_REVEAL else level.markers.hub)
			_feedback_message("Safety tether recovered / checkpoint landing", 4.0)

func _interact(target: Object) -> void:
	if not playing or modal or player.look_only or not is_instance_valid(target): return
	if target != player.interaction_target: return
	var id: String = target.get_meta("interaction_id", "")
	if DOCUMENTS.has(id):
		_open_document(id, DOCUMENTS[id][0], DOCUMENTS[id][1])
		return
	if id in ["fuse", "module", "badge"]:
		if repairs.collect(id):
			level.set_collected(id, true)
			sound.play_cue("success")
			_feedback_message("COLLECTED / " + str(target.get_meta("label")), 5.0)
			_checkpoint()
		return
	if id in ["pump_a", "pump_b"]:
		_feedback_message(repairs.operate(id), 5.0)
		level.set_pump_state(id, repairs.pumps[id])
		sound.play_cue("relay" if repairs.pumps[id] else "error", target.global_position)
		_checkpoint()
		return
	match id:
		"operations":
			if stage == Stage.OPERATIONS: _set_stage(Stage.POWER_REPAIR)
			_open_document(id, "SECTOR 06 / NIGHT OPERATIONS", "WORK ORDER 0214-06\nSource: REMOTE MAINTENANCE\n\nRestore in order: ELECTRICAL > COOLING > NETWORK.\n\nC / ELECTRICAL: fit a carrier from service stock by the lift. Reset procedure is posted beside the terminal.\nB / COOLING: two local pumps; calibrate valves at the main controller.\nA / NETWORK: fetch the offline bridge through Operations / Archive, then patch uplinks.\nD / SECURITY: inspect live surveillance after the network returns.\n\n" + _system_status())
			_checkpoint()
		"power", "cooling", "network":
			if stage == Stage.CHASE:
				_escape_control(id)
				return
			if id == "power" and stage < Stage.POWER_REPAIR:
				_feedback_message("Check the operations work order before servicing distribution.")
				return
			if id == "cooling" and not repairs.power_solved:
				_feedback_message("No power. Restore electrical distribution in C / ELECTRICAL.")
				return
			if id == "network" and not repairs.cooling_solved:
				_feedback_message("Rack temperature unsafe. Restore B / COOLING first.")
				return
			if id == "cooling" and stage == Stage.POWER_ONLINE: _set_stage(Stage.COOLING_REPAIR)
			if id == "network" and stage == Stage.COOLING_ONLINE: _set_stage(Stage.NETWORK_REPAIR)
			_open_puzzle(id)
		"cctv":
			if not repairs.network_solved:
				_feedback_message("SIGNAL LOST / Restore the network in A / SERVER HALL.")
			else: _open_feed(0)
		"core_access":
			if stage < Stage.CCTV_DISCOVERY:
				_feedback_message("Security hold. Review the incident on CAM 06-14 in D / SECURITY.")
			elif not repairs.inventory.has("badge"):
				_feedback_message("Security credential required. Check the desk opposite the CCTV wall.")
			elif stage >= Stage.CORE_REVEAL:
				level.set_door("core", true)
				_feedback_message("ISOLATION SEAL OPEN")
			else:
				_set_stage(Stage.CORE_ACCESS)
				_pin = ""
				_show_access()
		"core":
			if stage == Stage.CORE_REVEAL:
				_open_choices("core", "CENTRAL PROCESS / OPERATOR RECORD", "02:14:06 / Work order issued from this terminal.\nOperator count: 1\nExpected operator count: 2\n\nThe system was isolated deliberately. Reconnecting the network restored its access to cameras, doors and occupancy records.\n\nYour badge has been present since before your arrival.", [_option("isolate_core", "TERMINATE REMOTE PROCESS")])
			elif stage == Stage.CHASE: _feedback_message("Isolation failed. Return to the lift.")
		"exit":
			if stage == Stage.CHASE and repairs.brake_released and repairs.line_purged:
				_escape(session_token)
			elif stage == Stage.CHASE: _feedback_message(_objective(), 6.0)
			else: _feedback_message("SURFACE CALL DENIED / Complete the active maintenance order.", 5.0)
		"elevator_call", "elevator_open":
			if not level.is_elevator_moving():
				level.set_door("elevator", true)
				_feedback_message("LIFT B6 / Doors opening")
		"elevator_close":
			if not level.is_elevator_moving():
				level.set_door("elevator", false)

func _open_document(id: String, title: String, body: String) -> void:
	_begin_modal(id)
	hud.show_document(title, body)

func _begin_modal(id: String) -> void:
	modal = true
	modal_context = id
	player.locked = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _open_choices(id: String, title: String, body: String, choices: Array) -> void:
	_begin_modal(id)
	hud.show_choices(title, body, choices)

func _close_modal() -> void:
	_double.hide()
	_feed.render_target_update_mode = SubViewport.UPDATE_ONCE if stage >= Stage.NETWORK_ONLINE else SubViewport.UPDATE_DISABLED
	if not playing:
		return_to_menu()
		return
	_resume()

func _option(id: String, label: String, disabled := false) -> Dictionary:
	return {"id": id, "label": label, "disabled": disabled}

func _open_puzzle(id: String, feedback := "") -> void:
	var options: Array = []
	var body := ""
	match id:
		"power":
			body = "BUS 06 / %s\nCARRIER / %s\nCIRCUITS / %s\n\nUse the distribution procedure posted beside this terminal." % ["ISOLATED" if repairs.isolated else "ISOLATION REQUIRED", "SEATED" if repairs.carrier_fitted else "MISSING", str(repairs.power_steps)]
			if not repairs.power_solved:
				options = [_option("isolate", "ISOLATE DISTRIBUTION BUS"), _option("fit_fuse", "FIT REPLACEMENT CARRIER")]
				for number in [1, 2, 3]: options.append(_option("circuit:%d" % number, "CLOSE CIRCUIT %d" % number))
				options.append(_option("reset_power", "RESET STARTUP SEQUENCE"))
			else: body = "POWER ONLINE / Distribution stable.\nProceed to B / COOLING."
		"cooling":
			body = "PRIMARY PUMP / %s\nRETURN PUMP / %s\nACTUATORS A / B / C: %s\n\nSet the three actuators to the values on the calibration plate. Run the pressure test when both local pumps are online." % ["RUNNING" if repairs.pumps.pump_a else "LOCAL START REQUIRED", "RUNNING" if repairs.pumps.pump_b else "LOCAL START REQUIRED", str(repairs.valves)]
			if not repairs.cooling_solved:
				for number in range(3): options.append(_option("valve:%d" % number, "%s / %d > %d" % [["A / INLET", "B / BYPASS", "C / RETURN"][number], repairs.valves[number], (int(repairs.valves[number]) + 1) % 6]))
				options.append(_option("test_pressure", "RUN PRESSURE TEST"))
				options.append(_option("reset_cooling", "RESET ACTUATORS"))
			else: body = "COOLING ONLINE / Circulation stable.\nProceed to A / SERVER HALL. Fetch the bridge from Operations / Archive."
		"network":
			body = "OFFLINE BRIDGE / %s\nCHANNELS I / II / III: %s\n\nSelect three distinct uplinks using the route allocation sheet beside the racks; then commit." % ["SEATED" if repairs.module_fitted else "REQUIRED FROM OPERATIONS / ARCHIVE", str(repairs.links)]
			if not repairs.network_solved:
				options = [_option("fit_module", "SEAT OFFLINE BRIDGE")]
				for number in range(1, 7): options.append(_option("link:%d" % number, "PATCH PORT %d" % number, repairs.links.has(number)))
				options.append(_option("commit_network", "VERIFY AND COMMIT"))
				options.append(_option("reset_network", "CLEAR PATCH"))
			else: body = "NETWORK ONLINE\nRemote command source: SECTOR 06\nSurveillance restored. Review CAM 06-14 in D / SECURITY."
	if not feedback.is_empty(): body += "\n\n" + feedback
	_open_choices(id, id.to_upper() + " / MAINTENANCE", body, options)

func _choice(id: String) -> void:
	if id == "new_confirm" and modal_context == "confirm_new": start_new_game(); return
	if id == "new_cancel" and modal_context == "confirm_new": return_to_menu(); return
	if id == "retry" and modal_context == "death": continue_game(); return
	if id == "menu" and modal_context in ["death", "ending"]: return_to_menu(); return
	if id == "credits" and modal_context == "ending":
		hud.show_document("BELOW LEVEL 6 / CREDITS", "MERIDIAN SUBSURFACE SYSTEMS\nTHANK YOU FOR YOUR SERVICE.\n\nOriginal facility, sound synthesis, narrative and code: BELOW LEVEL 6 project.\nDevelopment with Codex assistance.\nRadio: original dialogue rendered with Microsoft David Desktop.\n\nMade with Godot Engine 4.5.2.\nGodot Engine © Juan Linietsky, Ariel Manzur and contributors (MIT).\nFull engine and library license notices are included in docs/licenses.\n\nNo microphone recording is used.\n\nEND OF SHIFT")
		return
	if not playing or not modal: return
	if modal_context in ["power", "cooling", "network"]:
		var allowed := {"power": ["isolate", "fit_fuse", "circuit", "reset_power"], "cooling": ["valve", "test_pressure", "reset_cooling"], "network": ["fit_module", "link", "commit_network", "reset_network"]}
		var action := id.get_slice(":", 0)
		if action not in allowed[modal_context]: return
		var context := modal_context
		var feedback: String = repairs.operate(action, int(id.get_slice(":", 1)))
		var completed: bool = (repairs.power_solved and stage < Stage.POWER_ONLINE) or (repairs.cooling_solved and stage < Stage.COOLING_ONLINE) or (repairs.network_solved and stage < Stage.NETWORK_ONLINE)
		if completed: _close_modal()
		_sync_repair_progress()
		sound.play_cue("error" if "failed" in feedback or "tripped" in feedback or "blocked" in feedback else "click")
		if completed: _feedback_message(feedback, 7.0)
		else: _open_puzzle(context, feedback)
		_checkpoint()
	elif modal_context == "cctv" and id.begins_with("feed:"):
		_open_feed(int(id.get_slice(":", 1)))
	elif modal_context == "core_access":
		if id.begins_with("digit:") and _pin.length() < 3:
			_pin += id.get_slice(":", 1)
		elif id == "clear_pin": _pin = ""
		elif id == "submit_pin":
			if _pin == "614" and repairs.inventory.has("badge") and repairs.network_solved:
				_set_stage(Stage.CORE_REVEAL)
				sound.play_cue("success")
				sound.play_radio("radio_core")
				_close_modal()
				_checkpoint()
				return
			_pin = ""
			sound.play_cue("error")
			_show_access("Credential accepted; PIN rejected. Review the security memo in D / SECURITY.")
			return
		_show_access()
	elif modal_context == "core" and id == "isolate_core":
		_close_modal()
		_failure(session_token)

func _sync_repair_progress() -> void:
	if repairs.network_solved and stage < Stage.NETWORK_ONLINE:
		_set_stage(Stage.NETWORK_ONLINE)
		sound.play_cue("network", level.markers.network)
		sound.play_radio("radio_network")
	elif repairs.cooling_solved and stage < Stage.COOLING_ONLINE:
		_set_stage(Stage.COOLING_ONLINE)
		sound.play_cue("cooling", level.markers.cooling)
		sound.play_radio("radio_cooling")
	elif repairs.power_solved and stage < Stage.POWER_ONLINE:
		_set_stage(Stage.POWER_ONLINE)
		sound.play_cue("power", level.markers.power)
		sound.play_radio("radio_power")

func _show_access(feedback := "") -> void:
	var choices: Array = []
	for digit in range(10): choices.append(_option("digit:%d" % digit, str(digit)))
	choices.append(_option("clear_pin", "CLEAR"))
	choices.append(_option("submit_pin", "VERIFY CREDENTIAL"))
	_open_choices("core_access", "CORE / ACCESS CONTROL", "BADGE VERIFIED\nPIN: " + _pin.rpad(3, "_") + "\n\nThree-digit authorization. Security memo: D / SURVEILLANCE.\n" + feedback, choices)

func _open_feed(index: int) -> void:
	_feed_index = clampi(index, 0, level.camera_points.size() - 1)
	var point: Dictionary = level.camera_points[_feed_index]
	_feed_camera.global_position = point.position
	_feed_camera.look_at(point.target)
	_double.hide()
	var description: String = point.name
	if _feed_index == 1 and not scares.events.has("cctv_double"):
		_double.position = Vector3(-15, 0.03, -12)
		_double.rotation.y = 0.0
		_double.show()
		scares.events["cctv_double"] = true
		description += " / DUPLICATE BADGE DETECTED"
		if stage < Stage.CCTV_DISCOVERY: _set_stage(Stage.CCTV_DISCOVERY)
	elif _feed_index == 3 and not scares.events.has("cctv_behind"):
		_double.position = player.position + player.global_basis.z * 2.4
		_double.rotation.y = player.rotation.y
		_double.show()
		scares.events["cctv_behind"] = true
		description += " / OCCUPANCY: 2"
	var choices: Array = []
	for number in range(level.camera_points.size()):
		choices.append(_option("feed:%d" % number, level.camera_points[number].name))
	_begin_modal("cctv")
	_feed.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	hud.show_feed(description, _feed.get_texture(), choices)
	_checkpoint()

func _set_stage(next: int) -> void:
	stage = next
	level.set_stage(stage)
	var phase := 0
	if stage >= Stage.CHASE: phase = 5
	elif stage >= Stage.CORE_REVEAL: phase = 4
	elif stage >= Stage.COOLING_ONLINE: phase = 3
	elif stage >= Stage.POWER_ONLINE: phase = 2
	observer.set_phase(phase)
	sound.set_tension([0.05, 0.12, 0.30, 0.52, 0.72, 1.0][phase])
	level.set_terminal_status("power", "BUS 06 / ONLINE" if repairs.power_solved else "BUS 06 / ISOLATED\nREPLACEMENT CARRIER REQUIRED")
	level.set_terminal_status("cooling", "FLOW / STABLE" if repairs.cooling_solved else "CIRCULATION OFFLINE\nLOCAL START / CALIBRATION")
	level.set_terminal_status("network", "NETWORK ONLINE\nCOMMAND SOURCE / SECTOR 06" if repairs.network_solved else "SYNCHRONIZATION LOST\nOFFLINE BRIDGE REQUIRED")
	level.set_terminal_status("operations", _system_status())
	if stage >= Stage.CORE_REVEAL: level.set_door("core", true)
	if stage == Stage.NETWORK_ONLINE: _feed.render_target_update_mode = SubViewport.UPDATE_ONCE
	if stage == Stage.CHASE:
		level.set_terminal_status("power", "LIFT BRAKE / LOCAL RELEASE")
		level.set_terminal_status("cooling", "LIFT LINE / EMERGENCY PURGE")
		level.set_elevator_status("INTERLOCK / BRAKE + LINE")
	hud.set_objective(_objective())

func _system_status() -> String:
	return "POWER / %s\nCOOLING / %s\nNETWORK / %s" % ["ONLINE" if repairs.power_solved else "OFFLINE", "ONLINE" if repairs.cooling_solved else "OFFLINE", "ONLINE" if repairs.network_solved else "OFFLINE"]

func _objective() -> String:
	match stage:
		Stage.ARRIVAL: return "NIGHT SHIFT 03 / Descend to Sector 06"
		Stage.OPERATIONS: return "CHECK THE OPERATIONS TERMINAL / A"
		Stage.POWER_REPAIR: return "RESTORE DISTRIBUTION / C — " + ("Use the wall reset procedure" if repairs.inventory.has("fuse") else "Carrier: service stock beside the lift")
		Stage.POWER_ONLINE, Stage.COOLING_REPAIR: return "RESTORE COOLING / B — Start both local pumps; calibrate the main controller"
		Stage.COOLING_ONLINE, Stage.NETWORK_REPAIR: return "RESTORE NETWORK / A — " + ("Patch uplinks using the route sheet" if repairs.inventory.has("module") else "Bridge: Operations / Archive cold storage")
		Stage.NETWORK_ONLINE: return "REVIEW CAM 06-14 / D — Security video wall"
		Stage.CCTV_DISCOVERY, Stage.CORE_ACCESS: return "ENTER THE CORE / E — " + ("Authorization code: security memo" if repairs.inventory.has("badge") else "Find the security badge opposite the CCTV wall")
		Stage.CORE_REVEAL: return "INVESTIGATE THE CENTRAL PROCESS / E — Core console"
		Stage.FAILURE: return "LOCAL CONNECTION LOST"
		Stage.CHASE:
			if not repairs.brake_released: return "RELEASE LIFT BRAKE / C — Electrical terminal. SHIFT / Run"
			if not repairs.line_purged: return "PURGE LIFT LINE / B — Cooling terminal. Keep moving"
			return "REACH THE LIFT / F — Rear service passage > Server hall > Hub. Use SURFACE inside"
		Stage.ELEVATOR_ESCAPE: return "SURFACE / ASCENDING"
	return "END OF SHIFT"

func _failure(token: int) -> void:
	_checkpoint()
	_set_stage(Stage.FAILURE)
	player.look_only = true
	sound.play_cue("shutdown")
	sound.set_silence(1.0)
	_fade_to(1.0, 1.2)
	await get_tree().create_timer(1.5, false).timeout
	if token != session_token or not playing: return
	hud.set_prompt("LOCAL DISPLAY LINK LOST\nRe-establishing operator session...")
	await get_tree().create_timer(3.0, false).timeout
	if token != session_token or not playing: return
	repairs.brake_released = false
	repairs.line_purged = false
	_set_stage(Stage.CHASE)
	observer.begin_chase()
	player.look_only = false
	sound.set_silence(0.0)
	sound.play_radio("radio_escape", true)
	_fade_to(0.0, 1.0)
	_feedback_message("The lift has two local interlocks. Electrical brake, then cooling purge. Keep moving.", 10.0)

func _escape_control(id: String) -> void:
	if id == "power":
		repairs.brake_released = true
		level.set_terminal_status("power", "LIFT BRAKE / RELEASED\nCOOLING LINE PURGE REQUIRED")
		_feedback_message("BRAKE RELEASED / Purge the lift line at B / COOLING", 5.0)
		sound.play_cue("success")
	elif id == "cooling":
		if not repairs.brake_released:
			_feedback_message("Pressure interlock: release the brake in C / ELECTRICAL first.")
			return
		repairs.line_purged = true
		level.set_terminal_status("cooling", "LIFT LINE / PURGED\nSURFACE LIFT READY")
		level.set_elevator_status("SURFACE / READY")
		level.set_door("elevator", true)
		sound.play_cue("cooling", level.markers.cooling)
		_feedback_message("LIFT READY / Use the rear service passage, then A / SERVER HALL to reach the hub and lift.", 9.0)
	else:
		_feedback_message("Remote access lost. Use local lift interlocks.")

func _escape(token: int) -> void:
	if not level.elevator_contains(player.global_position):
		_feedback_message("Step fully inside the cabin before requesting SURFACE.")
		return
	_set_stage(Stage.ELEVATOR_ESCAPE)
	observer.stop()
	player.look_only = true
	level.set_door("elevator", false)
	var arrived: bool = await level.travel_elevator(true, player, 15.0)
	if token != session_token or not playing: return
	if not arrived:
		# Safe retry of boarding; no narrative advancement after a rejected journey.
		_set_stage(Stage.CHASE)
		level.set_door("elevator", true)
		player.look_only = false
		sound.stop_cue("elevator")
		observer.resume_chase()
		return
	sound.stop_cue("elevator")
	sound.set_silence(1.0)
	level.set_elevator_status("GROUND")
	await get_tree().create_timer(2.0, false).timeout
	if token != session_token or not playing: return
	level.set_elevator_status("B6")
	sound.play_cue("click")
	_feedback_message("YOU RESTORED EVERYTHING.", 6.0)
	_fade_to(1.0, 3.0)
	await get_tree().create_timer(4.0, false).timeout
	if token != session_token or not playing: return
	_finish()

func _finish() -> void:
	stage = Stage.ENDING
	_ending_seen = true
	_checkpoint()
	playing = false
	modal = true
	modal_context = "ending"
	player.locked = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fade.modulate.a = 0.0
	hud.show_choices("BELOW LEVEL 6", "THANK YOU FOR YOUR SERVICE.\n\nOperator checkout: 02:14:06\nOperator count: 2\n\nEND OF SHIFT", [_option("credits", "CREDITS"), _option("menu", "MAIN MENU")], false)

func _caught() -> void:
	if not playing or stage != Stage.CHASE: return
	observer.stop()
	playing = false
	modal = true
	modal_context = "death"
	player.locked = true
	sound.clear_cues()
	sound.play_cue("error")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	hud.show_choices("SIGNAL LOST", "Operator connection terminated.\n\nYour repairs and credentials are retained at the core airlock checkpoint.\nSHIFT / Run. The presence moves more slowly while observed.", [_option("retry", "RETRY FROM CHECKPOINT"), _option("menu", "MAIN MENU")], false)

func _feedback_message(message: String, duration := 4.0) -> void:
	_feedback = message
	_feedback_time = duration

func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween != null: _fade_tween.kill()
	_fade_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_fade_tween.tween_property(_fade, "modulate:a", alpha, duration)

func _checkpoint() -> void:
	_checkpoint_clock = 0.0
	if stage < Stage.OPERATIONS or (stage >= Stage.FAILURE and stage != Stage.ENDING): return
	var radio_events: Dictionary = {}
	for id in sound.get_radio_state().get("heard", []): radio_events[id] = true
	var data := {
		"stage": stage, "checkpoint": "core_access" if stage >= Stage.CORE_REVEAL else "hub",
		"repairs": repairs.snapshot(), "events": scares.events.duplicate(),
		"observer_events": observer.get_event_flags(), "radio_events": radio_events,
		"elapsed": _elapsed
	}
	if saves.save_checkpoint(data): _safe_snapshot = data
	else: _feedback_message("CHECKPOINT NOT SAVED / " + saves.last_error, 8.0)

func _quit() -> void:
	if playing: _checkpoint()
	get_tree().paused = false
	get_tree().quit()
