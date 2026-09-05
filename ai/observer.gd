extends Node3D
class_name Observer
## A quiet, one-shot presence until the narrative explicitly begins pursuit.
## Pursuit uses a clearance-tested A* graph and a real sliding physics body.

signal caught

const CELL_SIZE := 1.25
const BODY_RADIUS := 0.30
const CHASE_SPEED := 2.18
const REPATH_SECONDS := 0.48

var state_name: String = "ABSENT"
var tension: float = 0.05
var visible_to_player: bool = false
var navigation_ready: bool = false
var navigation_point_count: int = 0

var _player: CharacterBody3D
var _facility: Node3D
var _actor: CharacterBody3D
var _visual: Node3D
var _head: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _phase: int = 0
var _seen_events: Dictionary = {}
var _queued_events: Array[String] = []
var _current_event: String = ""
var _observed_seconds: float = 0.0
var _unseen_seconds: float = 0.0
var _present_seconds: float = 0.0
var _chase_seconds: float = 0.0
var _catch_seconds: float = 0.0
var _repath_clock: float = 0.0
var _gait: float = 0.0
var _pending_hide: bool = false
var _astar := AStar3D.new()
var _grid: Dictionary = {}
var _sample_cells: Array[Vector2i] = []
var _sample_index: int = 0
var _edge_cells: Array[Vector2i] = []
var _edge_index: int = 0
var _clearance: CapsuleShape3D
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0
var _last_goal: Vector3 = Vector3.INF
var _breadcrumbs: Array[Vector3] = []

func _ready() -> void:
	_actor = CharacterBody3D.new()
	_actor.name = "Presence"
	_actor.collision_layer = 8
	_actor.collision_mask = 1
	_actor.floor_snap_length = 0.25
	_actor.max_slides = 6
	add_child(_actor)
	_actor.top_level = true
	var capsule := CapsuleShape3D.new()
	capsule.radius = BODY_RADIUS
	capsule.height = 2.20
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = 1.12
	_actor.add_child(collider)
	_visual = create_body()
	_actor.add_child(_visual)
	_head = _visual.get_node("HeadPivot")
	_left_leg = _visual.get_node("LeftLeg")
	_right_leg = _visual.get_node("RightLeg")
	_left_arm = _visual.get_node("LeftArm")
	_right_arm = _visual.get_node("RightArm")
	_actor.hide()
	_clearance = CapsuleShape3D.new()
	_clearance.radius = BODY_RADIUS + 0.035
	_clearance.height = 2.18

func setup(player_ref: CharacterBody3D, facility_ref: Node3D) -> void:
	_player = player_ref
	_facility = facility_ref
	_prepare_navigation()

func set_phase(phase: int) -> void:
	_phase = phase
	var levels: Array[float] = [0.05, 0.2, 0.4, 0.65, 0.80, 1.0]
	tension = levels[clampi(phase, 0, levels.size() - 1)]
	if phase == 2 and not _seen_events.has("cooling") and not _queued_events.has("cooling"):
		_queued_events.append("cooling")
	if phase == 3 and not _seen_events.has("network") and not _queued_events.has("network"):
		_queued_events.append("network")
	if phase >= 4 and state_name == "WATCHING":
		_pending_hide = true
	if phase >= 4:
		_queued_events.clear()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_facility):
		return
	if not navigation_ready:
		_build_navigation_slice()
	_record_breadcrumb()
	visible_to_player = _actor.visible and _is_visible()
	if state_name == "PURSUIT":
		_update_pursuit(delta)
	elif state_name == "WATCHING":
		_update_watching(delta)
	elif state_name == "ABSENT":
		_try_sighting()
	if state_name == "WATCHING" or state_name == "PURSUIT":
		_update_pose(delta)
	global_position = _actor.global_position

func _try_sighting() -> void:
	if _queued_events.is_empty() or bool(_player.get("locked")):
		return
	var event_id := _queued_events[0]
	var marker_id := "observer_" + event_id
	var fallback_id := "cooling" if event_id == "cooling" else "network"
	var location := _marker(marker_id, _marker(fallback_id, Vector3.INF))
	if not location.is_finite():
		_queued_events.pop_front()
		return
	var distance := _player.global_position.distance_to(location)
	if distance < 8.0 or distance > 36.0:
		return
	# Never create an actor in a part of the room the player is already seeing.
	if _player.call("is_observing", location + Vector3.UP * 1.35, 1.35):
		return
	_actor.global_position = location
	_actor.velocity = Vector3.ZERO
	_actor.show()
	_face_player(1.0)
	_current_event = _queued_events.pop_front()
	_seen_events[_current_event] = true
	_observed_seconds = 0.0
	_unseen_seconds = 0.0
	_present_seconds = 0.0
	_pending_hide = false
	state_name = "WATCHING"

func _update_watching(delta: float) -> void:
	_present_seconds += delta
	if visible_to_player:
		_observed_seconds += delta
		_unseen_seconds = 0.0
	else:
		_unseen_seconds += delta
	var has_been_noticed := _observed_seconds > 0.18
	var approached := _player.global_position.distance_to(_actor.global_position) < 5.0
	var spent := _present_seconds > 95.0
	if _unseen_seconds > 0.5 and (has_been_noticed or approached or spent or _pending_hide):
		_actor.hide()
		state_name = "ABSENT"
		_current_event = ""
	# No locomotion in early acts. Its gaze slowly finds the player.
	_face_player(minf(delta * 0.45, 1.0))

func begin_chase() -> void:
	if not is_instance_valid(_player):
		return
	_queued_events.clear()
	_pending_hide = false
	_chase_seconds = 0.0
	_catch_seconds = 0.0
	_repath_clock = 0.0
	_path = PackedVector3Array()
	_path_index = 0
	_last_goal = Vector3.INF
	tension = 1.0
	# The core event supplies darkness before pursuit; start behind the technician.
	# A spawn position must be on floor with enough capsule clearance.
	var core := _marker("core", _player.global_position)
	var candidates: Array[Vector3] = [
		_marker("observer_chase", core + Vector3(0, 0, -8.0)),
		core + Vector3(8.0, 0, -8.0),
		core + Vector3(-8.0, 0, -8.0),
		core + Vector3(-4.0, 0, -6.0),
		core + Vector3(4.0, 0, -6.0),
		core + Vector3(0, 0, -4.0)
	]
	var spawn := Vector3.INF
	for candidate in candidates:
		var safe := _floor_point(candidate)
		if safe.is_finite() and safe.distance_to(_player.global_position) > 6.0:
			spawn = safe
			break
	if not spawn.is_finite():
		spawn = _farthest_safe_near(core, _player.global_position, 17.0)
	if not spawn.is_finite():
		# A valid breadcrumb is guaranteed to have been reachable by the player.
		for index in range(_breadcrumbs.size() - 1, -1, -1):
			if _breadcrumbs[index].distance_to(_player.global_position) > 8.0:
				spawn = _breadcrumbs[index]
				break
	if not spawn.is_finite():
		spawn = core
	_actor.global_position = spawn
	_actor.velocity = Vector3.ZERO
	_actor.show()
	_face_player(1.0)
	state_name = "PURSUIT"
	# Doors change during the story; refresh clearance after the core unlocks.
	# Incremental construction fits inside the pursuit's 2.4-second lead-in.
	_prepare_navigation()
	_rebuild_path()

func _update_pursuit(delta: float) -> void:
	_chase_seconds += delta
	_repath_clock -= delta
	if _repath_clock <= 0.0:
		_repath_clock = REPATH_SECONDS
		_rebuild_path()
	# A readable lead-in gives the player time to leave the core.
	var speed := CHASE_SPEED * clampf((_chase_seconds - 2.4) / 2.0, 0.0, 1.0)
	if visible_to_player:
		speed *= 0.73
	var player_distance := _actor.global_position.distance_to(_player.global_position)
	if player_distance < 4.0:
		speed *= 0.90
	var destination := _actor.global_position
	if _segment_clear(_actor.global_position, _player.global_position):
		destination = _player.global_position
	elif _path_index < _path.size():
		while _path_index < _path.size() - 1 and _horizontal_distance(_actor.global_position, _path[_path_index]) < 0.30:
			_path_index += 1
		# Visibility smoothing follows wide corridors without cutting rack corners.
		while _path_index < _path.size() - 1 and _segment_clear(_actor.global_position, _path[_path_index + 1]):
			_path_index += 1
		destination = _path[_path_index]
	var direction := destination - _actor.global_position
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.08 else Vector3.ZERO
	_actor.velocity.x = move_toward(_actor.velocity.x, direction.x * speed, delta * 4.0)
	_actor.velocity.z = move_toward(_actor.velocity.z, direction.z * speed, delta * 4.0)
	_actor.velocity.y = -0.1 if _actor.is_on_floor() else maxf(_actor.velocity.y - 20.0 * delta, -12.0)
	_actor.move_and_slide()
	if direction.length_squared() > 0.01:
		var heading := atan2(-direction.x, -direction.z)
		_actor.rotation.y = lerp_angle(_actor.rotation.y, heading, 1.0 - exp(-3.0 * delta))
	if player_distance < 1.05 and _chase_seconds > 4.0 and _segment_clear(_actor.global_position, _player.global_position):
		_catch_seconds += delta
	else:
		_catch_seconds = 0.0
	if _catch_seconds >= 0.25:
		state_name = "CAUGHT"
		_actor.velocity = Vector3.ZERO
		caught.emit()

func stop() -> void:
	state_name = "ABSENT"
	_queued_events.clear()
	_path = PackedVector3Array()
	visible_to_player = false
	if is_instance_valid(_actor):
		_actor.velocity = Vector3.ZERO
		_actor.hide()

func world_position() -> Vector3:
	return _actor.global_position if is_instance_valid(_actor) else global_position

func get_event_flags() -> Dictionary:
	return _seen_events.duplicate()

func restore_event_flags(flags: Dictionary) -> void:
	_seen_events = flags.duplicate()
	_queued_events.clear()

func _is_visible() -> bool:
	# Sample the full height, so a visible head or legs prevent disappearance.
	return (
		bool(_player.call("is_observing", _actor.global_position + Vector3.UP * 1.60, 0.43))
		or bool(_player.call("is_observing", _actor.global_position + Vector3.UP * 2.52, 0.24))
		or bool(_player.call("is_observing", _actor.global_position + Vector3.UP * 0.55, 0.25))
	)

func _face_player(weight: float) -> void:
	var offset := _player.global_position - _actor.global_position
	if offset.length_squared() > 0.01:
		_actor.rotation.y = lerp_angle(_actor.rotation.y, atan2(-offset.x, -offset.z), weight)

func _update_pose(delta: float) -> void:
	var moving_speed := Vector2(_actor.velocity.x, _actor.velocity.z).length()
	_gait += delta * moving_speed * 2.6
	var strength := clampf(moving_speed / CHASE_SPEED, 0.0, 1.0) if state_name == "PURSUIT" else 0.0
	_left_leg.rotation.x = sin(_gait) * 0.28 * strength
	_right_leg.rotation.x = sin(_gait + PI) * 0.28 * strength
	_left_arm.rotation.x = sin(_gait + PI) * 0.095 * strength
	_right_arm.rotation.x = sin(_gait) * 0.08 * strength
	_visual.position.y = sin(_gait * 2.0) * 0.013 * strength
	_head.rotation.z = lerpf(_head.rotation.z, -0.105 if visible_to_player else 0.045, delta * 0.5)

func _marker(id: String, fallback: Vector3) -> Vector3:
	var markers: Dictionary = _facility.get("markers")
	return markers.get(id, fallback)

func _record_breadcrumb() -> void:
	var pos := _player.global_position
	if _breadcrumbs.is_empty() or _breadcrumbs.back().distance_to(pos) > 0.80:
		_breadcrumbs.append(pos)
		if _breadcrumbs.size() > 420:
			_breadcrumbs.pop_front()

func _prepare_navigation() -> void:
	_astar.clear()
	_grid.clear()
	_sample_cells.clear()
	_edge_cells.clear()
	_sample_index = 0
	_edge_index = 0
	navigation_ready = false
	var markers: Dictionary = _facility.get("markers")
	var min_pos := Vector3(-8, 0, -8)
	var max_pos := Vector3(8, 0, 8)
	for value in markers.values():
		if value is Vector3:
			min_pos.x = minf(min_pos.x, value.x - 9.0)
			min_pos.z = minf(min_pos.z, value.z - 9.0)
			max_pos.x = maxf(max_pos.x, value.x + 9.0)
			max_pos.z = maxf(max_pos.z, value.z + 9.0)
	for x in range(int(floor(min_pos.x / CELL_SIZE)), int(ceil(max_pos.x / CELL_SIZE)) + 1):
		for z in range(int(floor(min_pos.z / CELL_SIZE)), int(ceil(max_pos.z / CELL_SIZE)) + 1):
			_sample_cells.append(Vector2i(x, z))

func _build_navigation_slice() -> void:
	# Spread collision queries over frames to avoid an arrival hitch.
	var budget := 60
	while budget > 0 and _sample_index < _sample_cells.size():
		var cell := _sample_cells[_sample_index]
		_sample_index += 1
		budget -= 1
		var pos := _floor_point(Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE))
		if pos.is_finite():
			var id := _astar.get_available_point_id()
			_astar.add_point(id, pos)
			_grid[cell] = id
			_edge_cells.append(cell)
	if _sample_index < _sample_cells.size():
		return
	budget = 36
	var offsets: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]
	while budget > 0 and _edge_index < _edge_cells.size():
		var cell := _edge_cells[_edge_index]
		_edge_index += 1
		budget -= 1
		var id: int = _grid[cell]
		for offset in offsets:
			var other := cell + offset
			if not _grid.has(other):
				continue
			if offset.x != 0 and offset.y != 0:
				if not _grid.has(cell + Vector2i(offset.x, 0)) or not _grid.has(cell + Vector2i(0, offset.y)):
					continue
			var other_id: int = _grid[other]
			if _segment_clear(_astar.get_point_position(id), _astar.get_point_position(other_id)):
				_astar.connect_points(id, other_id, true)
	if _edge_index >= _edge_cells.size():
		navigation_ready = true
		navigation_point_count = _astar.get_point_count()

func _floor_point(pos: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.60, pos + Vector3.DOWN * 1.25, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or Vector3(hit.normal).y < 0.85:
		return Vector3.INF
	var foot: Vector3 = hit.position + Vector3.UP * 0.035
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = _clearance
	shape_query.transform = Transform3D(Basis.IDENTITY, foot + Vector3.UP * 1.12)
	shape_query.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(shape_query, 1).is_empty():
		return Vector3.INF
	return foot

func _segment_clear(from: Vector3, to: Vector3) -> bool:
	var direction := to - from
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return true
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _clearance
	query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * 1.12)
	query.motion = direction
	query.collision_mask = 1
	var fractions := get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.999

func _nearest_reachable(point: Vector3) -> int:
	var nearest: int = -1
	var nearest_distance := INF
	for id in _astar.get_point_ids():
		var candidate := _astar.get_point_position(id)
		var distance := candidate.distance_squared_to(point)
		if distance < nearest_distance and distance < 36.0 and _segment_clear(point, candidate):
			nearest_distance = distance
			nearest = id
	return nearest

func _rebuild_path() -> void:
	if not navigation_ready:
		return
	var goal := _player.global_position
	if _segment_clear(_actor.global_position, goal):
		_path = PackedVector3Array([goal])
		_path_index = 0
		return
	var start_id := _nearest_reachable(_actor.global_position)
	var goal_id := _nearest_reachable(goal)
	if start_id < 0 or goal_id < 0:
		return
	var proposed := _astar.get_point_path(start_id, goal_id)
	# Revalidate changed doors/props. A stale shortest edge must not trap pursuit.
	for attempt in range(6):
		var changed := false
		for index in range(proposed.size() - 1):
			if not _segment_clear(proposed[index], proposed[index + 1]):
				var first_id := _astar.get_closest_point(proposed[index])
				var second_id := _astar.get_closest_point(proposed[index + 1])
				_astar.disconnect_points(first_id, second_id)
				changed = true
		if not changed:
			break
		proposed = _astar.get_point_path(start_id, goal_id)
	if not proposed.is_empty():
		_path = proposed
		_path_index = 0
		_last_goal = goal

func _farthest_safe_near(center: Vector3, away_from: Vector3, max_distance: float) -> Vector3:
	var best := Vector3.INF
	var score := 6.0
	for id in _astar.get_point_ids():
		var point := _astar.get_point_position(id)
		if point.distance_to(center) < max_distance and _segment_clear(center, point):
			var distance := point.distance_to(away_from)
			if distance > score:
				score = distance
				best = point
	return best

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

## Returns a reusable authored silhouette for actual CCTV render cameras.
func create_body() -> Node3D:
	var body := Node3D.new()
	body.name = "Silhouette"
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.027, 0.033, 0.035)
	cloth.roughness = 0.94
	var seams := StandardMaterial3D.new()
	seams.albedo_color = Color(0.054, 0.06, 0.061)
	seams.roughness = 0.82
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.082, 0.079, 0.073)
	skin.roughness = 0.92
	var void_material := StandardMaterial3D.new()
	void_material.albedo_color = Color(0.005, 0.007, 0.007)
	void_material.roughness = 1.0
	# Ring-built coat: an uneven hem, narrow waist and shoulders held too high.
	var coat := MeshInstance3D.new()
	coat.name = "LongCoat"
	coat.mesh = _coat_mesh()
	coat.material_override = cloth
	body.add_child(coat)
	_add_limb(body, "Collar", Vector3(0, 2.26, 0.035), Vector3(0, 2.40, -0.015), 0.12, 0.11, seams)
	var head := Node3D.new()
	head.name = "HeadPivot"
	head.position = Vector3(0.025, 2.42, -0.025)
	body.add_child(head)
	var skull := MeshInstance3D.new()
	var skull_mesh := SphereMesh.new()
	skull_mesh.radius = 0.15
	skull_mesh.height = 0.40
	skull_mesh.radial_segments = 20
	skull_mesh.rings = 12
	skull.mesh = skull_mesh
	skull.material_override = skin
	skull.position.y = 0.10
	skull.scale = Vector3(0.92, 1.0, 0.88)
	head.add_child(skull)
	# The face is a matte recess, readable only as the absence of a face.
	var face := MeshInstance3D.new()
	var face_mesh := SphereMesh.new()
	face_mesh.radius = 0.117
	face_mesh.height = 0.275
	face_mesh.radial_segments = 16
	face_mesh.rings = 10
	face.mesh = face_mesh
	face.material_override = void_material
	face.position = Vector3(0, 0.095, -0.099)
	face.scale.z = 0.43
	head.add_child(face)
	for side in [-1.0, 1.0]:
		var prefix := "Left" if side < 0 else "Right"
		var leg := Node3D.new()
		leg.name = prefix + "Leg"
		leg.position = Vector3(side * 0.125, 1.24, 0.025)
		body.add_child(leg)
		_add_limb(leg, "Thigh", Vector3.ZERO, Vector3(side * 0.017, -0.56, 0.018), 0.098, 0.071, cloth)
		_add_limb(leg, "Shin", Vector3(side * 0.017, -0.55, 0.018), Vector3(side * 0.012, -1.10, -0.02), 0.068, 0.048, cloth)
		var foot := MeshInstance3D.new()
		var shoe := SphereMesh.new()
		shoe.radius = 0.1
		shoe.height = 0.2
		shoe.radial_segments = 12
		shoe.rings = 6
		foot.mesh = shoe
		foot.position = Vector3(side * 0.012, -1.15, -0.074)
		foot.scale = Vector3(0.85, 0.75, 1.65)
		foot.material_override = void_material
		leg.add_child(foot)
		var arm := Node3D.new()
		arm.name = prefix + "Arm"
		arm.position = Vector3(side * 0.31, 2.14 + side * 0.025, 0.015)
		body.add_child(arm)
		_add_limb(arm, "UpperSleeve", Vector3.ZERO, Vector3(side * 0.09, -0.56, 0.025), 0.106, 0.066, cloth)
		_add_limb(arm, "LowerSleeve", Vector3(side * 0.09, -0.55, 0.025), Vector3(side * 0.095, -1.06, -0.055), 0.067, 0.046, cloth)
		_add_limb(arm, "Palm", Vector3(side * 0.095, -1.06, -0.055), Vector3(side * 0.102, -1.23, -0.06), 0.045, 0.032, skin)
		for finger in range(3):
			var x: float = side * 0.102 + float(finger - 1) * 0.021
			_add_limb(arm, "Finger%d" % finger, Vector3(x, -1.20, -0.06), Vector3(x + side * 0.013, -1.36 + absf(finger - 1) * 0.025, -0.08), 0.012, 0.007, skin)
	return body

func _add_limb(parent: Node3D, limb_name: String, start: Vector3, end: Vector3, top: float, bottom: float, material: Material) -> void:
	var limb := MeshInstance3D.new()
	limb.name = limb_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = start.distance_to(end)
	mesh.radial_segments = 12
	mesh.rings = 2
	limb.mesh = mesh
	limb.material_override = material
	limb.position = (start + end) * 0.5
	var y_axis := (start - end).normalized()
	var x_axis := Vector3.FORWARD.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	limb.basis = Basis(x_axis, y_axis, z_axis)
	parent.add_child(limb)

func _coat_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var levels: Array[Vector3] = [
		Vector3(0.78, 0.30, 0.17), Vector3(1.10, 0.255, 0.18),
		Vector3(1.45, 0.22, 0.17), Vector3(1.79, 0.245, 0.175),
		Vector3(2.12, 0.34, 0.18), Vector3(2.24, 0.245, 0.145)
	]
	var count := 20
	for row in range(levels.size() - 1):
		for segment in range(count):
			var next := (segment + 1) % count
			var a := _coat_vertex(levels[row], segment, count, row == 0)
			var b := _coat_vertex(levels[row], next, count, row == 0)
			var c := _coat_vertex(levels[row + 1], next, count, false)
			var d := _coat_vertex(levels[row + 1], segment, count, false)
			for vertex in [a, c, b, a, d, c]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

func _coat_vertex(level: Vector3, segment: int, count: int, hem: bool) -> Vector3:
	var angle := TAU * float(segment) / float(count)
	var pleat := 1.0 + sin(angle * 7.0) * 0.035
	var y := level.x + (sin(angle * 3.0) * 0.035 if hem else 0.0)
	return Vector3(cos(angle) * level.y * pleat, y, sin(angle) * level.z * pleat + 0.03)
