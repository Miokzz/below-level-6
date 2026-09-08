extends SceneTree
## Godot --headless --path . --script narrative/verify_scares.gd

const DirectorScript = preload("res://narrative/scare_director.gd")

class TestPlayer extends Node3D:
	var observing := false
	func is_observing(_point: Vector3, _radius: float = 0.5) -> bool:
		return observing

class TestSound extends Node:
	var cue_count := 0
	func play_cue(_id: String, _position: Vector3) -> void:
		cue_count += 1

class TestFacility extends Node3D:
	var anomaly_nodes: Dictionary = {}
	var lights: Array[Light3D] = []
	var allow_extension := true
	var corridor_variant := 0
	func build() -> void:
		for id in ["door", "chair", "corridor_end"]:
			var node := Node3D.new()
			add_child(node)
			anomaly_nodes[id] = node
		var sign_node := Label3D.new()
		add_child(sign_node)
		anomaly_nodes["sign"] = sign_node
		for z in [6.0, 12.0, 18.0]:
			var lamp := OmniLight3D.new()
			lamp.position = Vector3(0, 3, z)
			add_child(lamp)
			lights.append(lamp)
		reset_anomalies()
	func reset_anomalies() -> void:
		anomaly_nodes.door.position = Vector3(30, 0, 0)
		anomaly_nodes.door.rotation.y = -PI / 3.0
		anomaly_nodes.chair.position = Vector3(50, 0, 0)
		anomaly_nodes.chair.visible = true
		anomaly_nodes.sign.text = "EXIT  /  SURFACE"
		anomaly_nodes.corridor_end.position = Vector3(-28, 0, 8)
		corridor_variant = 0
		for lamp in lights:
			lamp.set_meta("scare_disabled", false)
			lamp.light_energy = 1.0
	func extend_corridor(variant: int, _player_position: Vector3 = Vector3.INF) -> bool:
		if not allow_extension:
			return false
		corridor_variant = variant
		anomaly_nodes.corridor_end.position.x = -28 - 7.7 * variant
		return true

class TestGame extends Node:
	var playing := true
	var modal := false
	var stage := 7
	var session_token := 1
	var player: TestPlayer
	var level: TestFacility
	var sound: TestSound

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _run() -> void:
	var game := TestGame.new()
	root.add_child(game)
	game.level = TestFacility.new()
	game.add_child(game.level)
	game.level.build()
	game.player = TestPlayer.new()
	game.add_child(game.player)
	game.sound = TestSound.new()
	game.add_child(game.sound)
	var director := DirectorScript.new()
	game.add_child(director)
	director.set_process(false)
	director.setup(game)
	director.restore({"chair_0": true, "chair_1": true, "shutter_closed": true, "sign_changed": true, "corridor_2": true, "light_chase_started": true, "light_chase_0": true})
	_check(is_equal_approx(game.level.anomaly_nodes.chair.position.x, 51.25), "Checkpoint reapplies exact chair displacement")
	_check(is_zero_approx(game.level.anomaly_nodes.door.rotation.y) and game.level.anomaly_nodes.sign.text == "NO EXIT   /   B6", "Checkpoint restores shutter and changed exit sign")
	_check(game.level.corridor_variant == 2, "Checkpoint restores stretched corridor")
	_check(is_zero_approx(game.level.lights[0].light_energy) and game.level.lights[1].light_energy > 0.0, "Partial light sequence restores only completed fixtures")
	game.modal = true
	director._process(5.0)
	_check(game.level.lights[1].light_energy > 0.0 and game.sound.cue_count == 0, "Modal reading freezes pending scare sequence without sound")
	game.modal = false
	director._process(1.4)
	_check(is_zero_approx(game.level.lights[1].light_energy) and game.sound.cue_count == 1, "Resumed checkpoint continues from the next fixture exactly once")
	director._process(1.4)
	_check(director.events.has("light_chase") and game.sound.cue_count == 2, "Light sequence reaches completion without duplicate cue")
	director.restore({})
	director._process(1.4)
	_check(game.level.anomaly_nodes.chair.position.x == 50.0 and game.level.anomaly_nodes.chair.visible, "New session resets previous chair mutation")
	_check(game.level.lights[0].light_energy > 0.0 and game.sound.cue_count == 2, "Restoring a new session cancels old pending light sequence")
	director.restore({"chair_0": true, "chair_1": true, "chair_2": true, "light_chase": true})
	_check(not game.level.anomaly_nodes.chair.visible and is_zero_approx(game.level.lights[2].light_energy), "Completed legacy checkpoint restores hidden chair and full blackout")
	director.restore({})
	game.stage = 5
	game.level.allow_extension = false
	director._process(16.0)
	_check(not director.events.has("corridor_1"), "Rejected corridor movement never consumes its one-shot event")
	game.level.allow_extension = true
	director._process(0.1)
	_check(director.events.has("corridor_1") and game.level.corridor_variant == 1, "Previously blocked anomaly can trigger after its path is safe")
	_check(not director.claim("corridor_1"), "Claimed event cannot be replayed")
	print("SCARE_VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
