extends SceneTree
## Exercises the actual technician collider, cabin travel and doorway interlock.

var failures := 0
var checks := 0
var facility: Node3D
var player: CharacterBody3D

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func _settle(frames: int = 4) -> void:
	for frame in range(frames):
		await physics_frame

func _start_ride(to_surface: bool, duration: float, result: Dictionary) -> void:
	result.success = await facility.travel_elevator(to_surface, player, duration)
	result.done = true

func _run() -> void:
	facility = load("res://environment/facility.gd").new()
	root.add_child(facility)
	facility.build()
	player = load("res://player/technician.gd").new()
	root.add_child(player)
	player.locked = false
	player.look_only = true
	facility.reset_elevator(true)
	player.teleport(facility.markers.spawn + Vector3.UP * 30.0)
	await _settle()
	_expect(facility.elevator_contains(player.global_position), "Surface cabin must contain the arriving passenger")
	_expect(absf(player.global_position.y - 30.0) < 0.12, "Passenger must stand on the surface cabin floor")
	for surface in [false, true, false]:
		var result := {"done": false, "success": false}
		_start_ride(surface, 2.0, result)
		var maximum_error := 0.0
		var crossed_midpoint := false
		var frames := 0
		while not result.done and frames < 600:
			await physics_frame
			frames += 1
			maximum_error = maxf(maximum_error, absf(player.global_position.y - facility.elevator_cabin.position.y))
			if facility.elevator_cabin.position.y > 10.0 and facility.elevator_cabin.position.y < 20.0:
				crossed_midpoint = true
				facility.set_door("elevator", true)
				_expect(not facility._doors.elevator.open, "Door must reject an open request inside the shaft")
		_expect(result.done and result.success, "Elevator must finish its requested journey")
		_expect(crossed_midpoint, "The cabin must physically traverse the shaft")
		_expect(maximum_error < 0.13, "Passenger must remain attached to the actual cabin floor: " + str(maximum_error))
		_expect(absf(facility.elevator_cabin.position.y - (30.0 if surface else 0.0)) < 0.001, "Cabin must align exactly with its landing")
		_expect(not facility.is_elevator_moving(), "Arrival must clear the movement interlock")
		_expect(facility.anomaly_nodes.elevator_display.text == ("G" if surface else "B6"), "Arrival display must identify the physical floor")
		await _settle()

	facility.set_door("elevator", true)
	await create_timer(1.6, false).timeout
	_expect(facility.is_door_open("elevator"), "Opening animation must finish before reporting the door open")
	player.teleport(Vector3(0, 0.1, 22))
	await _settle()
	facility.set_door("elevator", false)
	await _settle()
	_expect(facility._doors.elevator.open, "A passenger across the threshold must inhibit door closing")
	player.teleport(Vector3(0, 0.1, 20))
	await _settle()
	_expect(not await facility.travel_elevator(true, player, 0.1), "A passenger outside the cabin must never start a journey")
	facility.set_door("elevator", false)
	await create_timer(1.6, false).timeout
	var ray := PhysicsRayQueryParameters3D.create(Vector3(0, 1, 21), Vector3(0, 1, 23), 1)
	var hit := facility.get_world_3d().direct_space_state.intersect_ray(ray)
	_expect(not hit.is_empty() and hit.collider.is_in_group("facility_doors"), "Closed doors must have physical collision")
	facility.set_door("elevator", true)
	await create_timer(1.6, false).timeout
	player.teleport(facility.markers.spawn)
	await _settle()
	var cancelled := {"done": false, "success": true}
	_start_ride(true, 2.0, cancelled)
	await create_timer(1.9, false).timeout
	facility.reset_elevator(false)
	player.teleport(facility.markers.spawn)
	await _settle()
	_expect(cancelled.done and not cancelled.success, "Reset must cancel an old journey without a late arrival")
	_expect(not facility.is_elevator_moving(), "Reset must release all movement state")
	_expect(player.platform_floor_layers != 0, "Passenger platform settings must be restored after cancellation")
	print("ELEVATOR_PHYSICS_AUDIT checks=", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)
