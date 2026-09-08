extends SceneTree

func _initialize() -> void:
	var facility_script = load("res://environment/facility.gd")
	if facility_script == null:
		quit(1)
		return
	var facility = facility_script.new()
	root.add_child(facility)
	facility.build()
	print("FACILITY_BUILD_OK interactables=", facility.interactables.size(), " lights=", facility.lights.size(), " nodes=", facility.get_child_count())
	await physics_frame
	await physics_frame
	var failures := 0
	var door_rids: Array[RID] = []
	for door in get_nodes_in_group("facility_doors"):
		door_rids.append(door.get_rid())
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.31
	capsule.height = 1.78
	for key in facility.markers:
		var p: Vector3 = facility.markers[key]
		var query := PhysicsRayQueryParameters3D.create(p + Vector3(0, 1.0, 0), p - Vector3(0, 0.5, 0), 1)
		var hit: Dictionary = facility.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or absf(hit.position.y) > 0.08:
			push_error("INVALID SPAWN " + key + " " + str(hit))
			failures += 1
	for link in facility.traversal_links:
		var a: Vector3 = facility.traversal_nodes[link[0]] + Vector3(0, 0.7, 0)
		var b: Vector3 = facility.traversal_nodes[link[1]] + Vector3(0, 0.7, 0)
		var query := PhysicsRayQueryParameters3D.create(a, b, 1, door_rids)
		var hit: Dictionary = facility.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			print("GRAPH EDGE BLOCKED ", link, " at ", hit.position)
		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = capsule
		shape_query.transform = Transform3D(Basis.IDENTITY, a + Vector3(0, 0.2, 0))
		shape_query.motion = b - a
		shape_query.collision_mask = 1
		shape_query.exclude = door_rids
		var motion: PackedFloat32Array = facility.get_world_3d().direct_space_state.cast_motion(shape_query)
		if motion[0] < 0.999:
			push_error("CAPSULE EDGE BLOCKED " + str(link) + " " + str(motion))
			failures += 1
	for key in facility.interaction_approaches:
		var approach: Dictionary = facility.interaction_approaches[key]
		var query := PhysicsRayQueryParameters3D.create(approach.position + Vector3(0, 1.65, 0), approach.target, 3)
		var hit: Dictionary = facility.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != facility.interactables[key]:
			push_error("INTERACTION OBSTRUCTED " + key + " " + str(hit))
			failures += 1
		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = capsule
		shape_query.transform = Transform3D(Basis.IDENTITY, approach.position + Vector3(0, 0.9, 0))
		shape_query.collision_mask = 1
		var collisions: Array = facility.get_world_3d().direct_space_state.intersect_shape(shape_query)
		if not collisions.is_empty():
			push_error("INTERACTION APPROACH BLOCKED " + key)
			failures += 1
	for variant in [1, 2, 0]:
		facility.extend_corridor(variant, Vector3.ZERO)
		await physics_frame
		await physics_frame
		var approach: Dictionary = facility.interaction_approaches.module
		var query := PhysicsRayQueryParameters3D.create(approach.position + Vector3(0, 1.65, 0), approach.target, 3)
		var hit: Dictionary = facility.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.collider != facility.interactables.module:
			push_error("DYNAMIC MODULE UNREACHABLE " + str(variant))
			failures += 1
		var path: Array = facility.find_path(Vector3(-24, 0.1, 8), approach.position)
		if path.is_empty():
			failures += 1
		var prior: float = facility.anomaly_nodes.corridor_end.position.x
		if facility.extend_corridor((variant + 1) % 3, Vector3(-24, 0.1, 8)) or facility.anomaly_nodes.corridor_end.position.x != prior:
			push_error("OCCUPIED CORRIDOR MOVED")
			failures += 1
	print("FACILITY_COLLISION_AUDIT failures=", failures)
	quit(1 if failures > 0 else 0)
