extends SceneTree
## Run with Godot --headless --path . --script ai/verify_controller_ai.gd
## Exercises real physics, ray occlusion, crouching, sightings and a routed catch.

const PlayerScript = preload("res://player/technician.gd")
const ObserverScript = preload("res://ai/observer.gd")

class TestFacility extends Node3D:
	var markers: Dictionary = {
		"spawn": Vector3(0, 0.05, 8), "core": Vector3(0, 0.05, -5),
		"observer_chase": Vector3(0, 0.05, -10),
		"observer_cooling": Vector3(0, 0.05, -8),
		"observer_network": Vector3(-7, 0.05, -7),
		"exit": Vector3(0, 0.05, 12)
	}

var failures: Array[String] = []
var step_count: int = 0
var caught_count: int = 0
var player: CharacterBody3D
var observer: Node3D
var facility: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _box(parent: Node3D, pos: Vector3, size: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.position = pos
	body.add_child(collider)
	parent.add_child(body)
	return body

func _frames(count: int) -> void:
	for tick in range(count):
		await physics_frame

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	facility = TestFacility.new()
	world.add_child(facility)
	_box(facility, Vector3(0, -0.15, 0), Vector3(30, 0.3, 32))
	_box(facility, Vector3(0, 1.5, 0), Vector3(12, 3, 0.45))
	player = PlayerScript.new()
	world.add_child(player)
	player.teleport(Vector3(0, 0.05, 8))
	player.locked = false
	player.footstep.connect(func(_surface: String) -> void: step_count += 1)
	observer = ObserverScript.new()
	world.add_child(observer)
	observer.setup(player, facility)
	observer.caught.connect(func() -> void: caught_count += 1)
	await _frames(4)
	_check(player.is_observing(Vector3(0, 1.6, 4), 0.2), "Visible point does not self-hit player collider")
	_check(not player.is_observing(Vector3(0, 1.6, -4), 0.2), "Wall occludes observation")
	_check(not player.is_observing(Vector3(0, 1.6, 12), 0.2), "Point behind camera is unobserved")
	_check(not player.is_observing(Vector3(10, 1.6, 7), 0.2), "Point outside horizontal FOV is unobserved")
	var terminal := _box(facility, Vector3(0, 1.55, 5.5), Vector3(0.5, 0.5, 0.12), 2)
	terminal.set_meta("interaction_id", "test")
	await _frames(3)
	_check(player.interaction_target == terminal, "Center ray finds layer-two interactable")
	terminal.position = Vector3(0, 1.55, -0.8)
	player.teleport(Vector3(0, 0.05, 1.5))
	await _frames(3)
	_check(player.interaction_target == null, "Solid wall blocks interaction through it")
	terminal.queue_free()
	player.teleport(Vector3(0, 0.05, 8))
	player.set_test_input(Vector2(0, -1), true)
	await _frames(150)
	_check(player.global_position.z > 0.49 and player.global_position.z < 0.7, "Sprint stops at wall using capsule collision")
	_check(step_count >= 5, "Distance-based footstep cadence emits during movement")
	player.set_test_input(Vector2.ZERO, false, true)
	await _frames(30)
	_check(player.crouching and player.camera.position.y < 1.04, "Crouch lowers collider and eyes")
	player.set_test_input(Vector2.ZERO)
	await _frames(30)
	_check(not player.crouching and player.camera.position.y > 1.55, "Unobstructed standing restores camera height")
	player.clear_test_input()
	player.teleport(Vector3(0, 0.05, 8))
	observer.set_phase(2)
	await _frames(3)
	_check(observer.state_name == "WATCHING", "Early presence spawns beyond an occluding wall")
	player.teleport(Vector3(7, 0.05, -8), PI * 0.5)
	await _frames(40)
	_check(observer.visible_to_player and observer.state_name == "WATCHING", "Directly observed silhouette remains present")
	player.rotation.y = -PI * 0.5
	await _frames(40)
	_check(observer.state_name == "ABSENT", "Seen silhouette disappears only after player turns away")
	observer.set_phase(2)
	await _frames(3)
	_check(observer.state_name == "ABSENT", "One-shot sighting does not repeat at same phase")
	player.teleport(Vector3(0, 0.05, 8))
	await _frames(100)
	_check(observer.navigation_ready and observer.navigation_point_count > 100, "Clearance-tested A* graph is built")
	observer.begin_chase()
	var crossed_wall := false
	var went_around_wall := false
	for tick in range(1900):
		await physics_frame
		var pos: Vector3 = observer.world_position()
		if absf(pos.x) < 6.2 and absf(pos.z) < 0.45:
			crossed_wall = true
		if absf(pos.x) > 6.25:
			went_around_wall = true
		if caught_count > 0:
			break
	_check(not crossed_wall, "Pursuit never crosses the wall collider")
	_check(went_around_wall, "Pursuit routes around the obstacle")
	_check(caught_count == 1, "Pursuit catches stationary player exactly once")
	await _frames(30)
	_check(caught_count == 1, "Catch signal is not emitted repeatedly")
	observer.stop()
	_check(observer.state_name == "ABSENT" and not observer.visible_to_player, "Stop clears pursuit")
	print("CONTROLLER_AI_VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
