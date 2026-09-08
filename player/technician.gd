extends CharacterBody3D
class_name Technician
## Weighted first-person controller. The player's origin is at the soles.
## All observation queries exclude the body and include solid level geometry.

signal interacted(target: Object)
signal footstep(surface: String)
signal flashlight_changed(enabled: bool)

const WALK_SPEED := 1.90
const RUN_SPEED := 4.25
const CROUCH_SPEED := 1.25
const STANDING_HEIGHT := 1.80
const CROUCH_HEIGHT := 1.08
const INTERACTION_DISTANCE := 3.4

var camera: Camera3D
var flashlight: SpotLight3D
var locked: bool = true
var look_only: bool = false
var settings: Dictionary = {
	"fov": 82.0, "sensitivity": 0.11, "invert_y": false,
	"head_bob": 1, "reduced_shake": true, "preset": 2
}
var interaction_target: Object = null
var surface_provider: Callable
var crouching: bool = false
var sprinting: bool = false
var distance_walked: float = 0.0
var flashlight_enabled: bool = true

var _collider: CollisionShape3D
var _capsule: CapsuleShape3D
var _standing_clearance: CapsuleShape3D
var _pitch: float = 0.0
var _crouch_toggle: bool = false
var _eye_height: float = 1.65
var _step_distance: float = 0.0
var _bob_clock: float = 0.0
var _last_ground_position: Vector3
var _gravity: float = 20.0
var _test_input_enabled: bool = false
var _test_axis: Vector2 = Vector2.ZERO
var _test_run: bool = false
var _test_crouch: bool = false

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.28
	floor_max_angle = deg_to_rad(45.0)
	max_slides = 5
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.28
	_capsule.height = STANDING_HEIGHT
	_standing_clearance = CapsuleShape3D.new()
	_standing_clearance.radius = 0.27
	_standing_clearance.height = STANDING_HEIGHT - 0.04
	_collider = CollisionShape3D.new()
	_collider.shape = _capsule
	_collider.position.y = STANDING_HEIGHT * 0.5
	add_child(_collider)
	camera = Camera3D.new()
	camera.name = "Eyes"
	camera.position.y = _eye_height
	camera.near = 0.045
	camera.far = 115.0
	camera.current = true
	add_child(camera)
	flashlight = SpotLight3D.new()
	flashlight.name = "InspectionLight"
	flashlight.position = Vector3(0.18, -0.14, -0.12)
	flashlight.light_color = Color(0.81, 0.9, 1.0)
	flashlight.light_energy = 3.0
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 29.0
	flashlight.spot_angle_attenuation = 0.8
	flashlight.spot_attenuation = 1.15
	flashlight.shadow_enabled = true
	flashlight.shadow_bias = 0.04
	camera.add_child(flashlight)
	_last_ground_position = global_position
	apply_settings(settings)

func apply_settings(values: Dictionary) -> void:
	settings.merge(values, true)
	if not is_instance_valid(camera):
		return
	camera.fov = clampf(float(settings.get("fov", 82.0)), 65.0, 110.0)
	flashlight.shadow_enabled = int(settings.get("preset", 2)) >= 1

func _unhandled_input(event: InputEvent) -> void:
	if locked or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		var sensitivity := deg_to_rad(float(settings.get("sensitivity", 0.11)))
		rotate_y(-motion.screen_relative.x * sensitivity)
		var invert := -1.0 if bool(settings.get("invert_y", false)) else 1.0
		_pitch = clampf(_pitch - motion.screen_relative.y * sensitivity * invert, -1.46, 1.46)
		camera.rotation.x = _pitch
	elif event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		match key.physical_keycode:
			KEY_E:
				_refresh_interaction_target()
				if is_instance_valid(interaction_target) and not look_only:
					interacted.emit(interaction_target)
			KEY_F:
				flashlight_enabled = not flashlight_enabled
				flashlight.visible = flashlight_enabled
				flashlight_changed.emit(flashlight_enabled)
			KEY_C:
				_crouch_toggle = not _crouch_toggle

func _physics_process(delta: float) -> void:
	var axis := Vector2.ZERO
	var run_pressed := false
	var crouch_pressed := false
	if not locked and not look_only:
		if _test_input_enabled:
			axis = _test_axis.limit_length()
			run_pressed = _test_run
			crouch_pressed = _test_crouch
		else:
			axis = Vector2(
				float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
				float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
			).limit_length()
			run_pressed = Input.is_physical_key_pressed(KEY_SHIFT)
			crouch_pressed = _crouch_toggle or Input.is_physical_key_pressed(KEY_CTRL)
	if crouch_pressed:
		_set_crouching(true)
	elif crouching and _can_stand():
		_set_crouching(false)
	sprinting = run_pressed and not crouching and axis.y < 0.15 and axis.length() > 0.1
	var speed := CROUCH_SPEED if crouching else (RUN_SPEED if sprinting else WALK_SPEED)
	var direction := global_basis * Vector3(axis.x, 0.0, axis.y)
	var desired := direction * speed
	var acceleration := 9.0 if axis.length() > 0.0 else 13.0
	velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = -0.1
	if locked or look_only:
		velocity.x = 0.0
		velocity.z = 0.0
	move_and_slide()
	_update_gait(delta)
	_refresh_interaction_target()

func _set_crouching(value: bool) -> void:
	if crouching == value:
		return
	crouching = value
	var height := CROUCH_HEIGHT if value else STANDING_HEIGHT
	_capsule.height = height
	_collider.position.y = height * 0.5

func _can_stand() -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _standing_clearance
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * (STANDING_HEIGHT * 0.5 + 0.015))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _update_gait(delta: float) -> void:
	var horizontal := global_position - _last_ground_position
	horizontal.y = 0.0
	_last_ground_position = global_position
	var travelled := horizontal.length()
	var moving := is_on_floor() and travelled > 0.001 and travelled < 0.4 and not locked
	if moving:
		distance_walked += travelled
		_step_distance += travelled
		_bob_clock += travelled * 7.1
		var step_length := 0.91 if sprinting else (0.75 if crouching else 0.86)
		if _step_distance >= step_length:
			_step_distance = fmod(_step_distance, step_length)
			var surface := "concrete"
			if surface_provider.is_valid():
				surface = str(surface_provider.call(global_position))
			footstep.emit(surface)
	else:
		_step_distance = minf(_step_distance, 0.35)
	var bob_setting := int(settings.get("head_bob", 1))
	var amplitude := 0.0 if bob_setting == 0 else (0.009 if bob_setting == 1 else 0.021)
	if bool(settings.get("reduced_shake", true)):
		amplitude *= 0.45
	if crouching:
		amplitude *= 0.5
	var target_height := 0.94 if crouching else 1.65
	_eye_height = lerpf(_eye_height, target_height, 1.0 - exp(-12.0 * delta))
	var bob := sin(_bob_clock) * amplitude if moving else 0.0
	camera.position.y = lerpf(camera.position.y, _eye_height + bob, 1.0 - exp(-16.0 * delta))
	if crouching:
		# The capsule lowers immediately; keep the easing camera below low geometry.
		var origin := global_position + Vector3.UP * 0.9
		var query := PhysicsRayQueryParameters3D.create(origin, camera.global_position + Vector3.UP * 0.09, 1, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			camera.position.y = minf(camera.position.y, hit.position.y - global_position.y - 0.09)
	var base_fov := clampf(float(settings.get("fov", 82.0)), 65.0, 110.0)
	var run_fov := 2.0 if sprinting and not bool(settings.get("reduced_shake", true)) else 0.0
	camera.fov = lerpf(camera.fov, base_fov + run_fov, 1.0 - exp(-5.0 * delta))

func _refresh_interaction_target() -> void:
	interaction_target = null
	if locked or look_only or not is_instance_valid(camera):
		return
	var start := camera.global_position
	var end := start - camera.global_basis.z * INTERACTION_DISTANCE
	# Solid geometry blocks interaction with terminals on the other side of a wall.
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 2, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var target: Object = hit.get("collider")
		if is_instance_valid(target) and target.has_meta("interaction_id"):
			interaction_target = target

func is_observing(point: Vector3, radius: float = 0.5) -> bool:
	if not is_instance_valid(camera) or not is_inside_tree():
		return false
	var origin := camera.global_position
	var distance := origin.distance_to(point)
	if distance > camera.far or distance < 0.001:
		return distance < 0.001
	var local_point := camera.global_transform.affine_inverse() * point
	if local_point.z > radius:
		return false
	var screen_size := camera.get_viewport().get_visible_rect().size
	var aspect := screen_size.x / maxf(screen_size.y, 1.0)
	var tangent := tan(deg_to_rad(camera.fov * 0.5))
	var half_vertical := tangent
	var half_horizontal := tangent * aspect
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		half_horizontal = tangent
		half_vertical = tangent / aspect
	var depth := maxf(-local_point.z, 0.001)
	if absf(local_point.x) > depth * half_horizontal + radius:
		return false
	if absf(local_point.y) > depth * half_vertical + radius:
		return false
	# Multiple samples stop a partially exposed silhouette or door from vanishing.
	var spread := maxf(0.0, radius * 0.70)
	var samples: Array[Vector3] = [
		point,
		point + camera.global_basis.x * spread,
		point - camera.global_basis.x * spread,
		point + camera.global_basis.y * spread,
		point - camera.global_basis.y * spread
	]
	for sample in samples:
		var direction := sample - origin
		var endpoint := sample - direction.normalized() * minf(radius, direction.length() * 0.25)
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1 | 2, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return true
	return false

func teleport(pos: Vector3, yaw: float = 0.0) -> void:
	global_position = pos
	rotation.y = yaw
	_pitch = 0.0
	velocity = Vector3.ZERO
	_step_distance = 0.0
	_bob_clock = 0.0
	_crouch_toggle = false
	_last_ground_position = pos
	if is_instance_valid(camera):
		camera.rotation.x = 0.0
		_set_crouching(false)
		_eye_height = 1.65
		camera.position.y = _eye_height
	reset_physics_interpolation()

## Deterministic verification uses the same acceleration, collision and gait path.
## This is callable only; it has no player-facing shortcut or alternate controls.
func set_test_input(axis: Vector2, run: bool = false, crouch: bool = false) -> void:
	_test_input_enabled = true
	_test_axis = axis
	_test_run = run
	_test_crouch = crouch

func clear_test_input() -> void:
	_test_input_enabled = false
	_test_axis = Vector2.ZERO
	_test_run = false
	_test_crouch = false
