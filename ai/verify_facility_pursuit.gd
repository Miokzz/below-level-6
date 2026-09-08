extends SceneTree
## Real facility geometry, opened story doors, and the production pursuit body.
## Godot --headless --fixed-fps 60 --path . --script ai/verify_facility_pursuit.gd

const FacilityScript = preload("res://environment/facility.gd")
const PlayerScript = preload("res://player/technician.gd")
const ObserverScript = preload("res://ai/observer.gd")

var failures: Array[String] = []
var caught_count := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _frames(count: int) -> void:
	for tick in range(count):
		await physics_frame

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var facility := FacilityScript.new()
	world.add_child(facility)
	facility.build()
	facility.set_stage(12)
	var player := PlayerScript.new()
	world.add_child(player)
	player.locked = false
	player.teleport(facility.markers.hub)
	var observer := ObserverScript.new()
	world.add_child(observer)
	observer.setup(player, facility)
	observer.caught.connect(func() -> void: caught_count += 1)
	await _frames(420)
	_check(observer.navigation_ready and observer.navigation_point_count > 500, "Production facility generates a traversable pursuit graph")
	for destination in ["hub", "exit"]:
		observer.stop()
		player.teleport(facility.markers[destination])
		await _frames(5)
		var previous_count := caught_count
		observer.begin_chase()
		_check(observer.world_position().distance_to(player.global_position) > 6.0, "Pursuit begins with safe distance for " + destination)
		var fell := false
		for tick in range(6600):
			await physics_frame
			fell = fell or observer.world_position().y < -0.2
			if caught_count > previous_count:
				break
		_check(not fell, "Pursuing body remains on facility floor toward " + destination)
		_check(caught_count == previous_count + 1, "Pursuit reaches a stationary player at " + destination + " through actual rooms and doors")
	observer.stop()
	print("FACILITY_PURSUIT_VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
