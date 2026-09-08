extends Node3D
class_name Facility
## An authored modular underground facility. Structural geometry is batched by
## material, while collision and movable props keep deliberately simple shapes.

signal door_state_changed(id: String, opened: bool)
signal elevator_arrived(to_surface: bool)
signal mechanism_cue(id: String, position: Vector3)

const ELEVATOR_SURFACE_HEIGHT := 30.0
const DOOR_SECONDS := 1.4

var markers: Dictionary = {}
var interactables: Dictionary = {}
var interaction_approaches: Dictionary = {}
var camera_points: Array = []
var anomaly_nodes: Dictionary = {}
var route: Array[Vector3] = []
var lights: Array = []
var traversal_nodes: Array[Vector3] = []
var traversal_links: Array = []
var materials: Dictionary = {}
var _batches: Dictionary = {}
var _doors: Dictionary = {}
var _screens: Array = []
var _fans: Array = []
var _stage: int = 0
var _corridor_variant: int = 0
var _built: bool = false
var _clock: float = 0.0
var _anomaly_defaults: Dictionary = {}
var screenshot_points: Dictionary = {}
var _reflection_probes: Array[ReflectionProbe] = []
var _texture_cache: Dictionary = {}
var _terminal_labels: Dictionary = {}
var _terminal_defaults: Dictionary = {}
var _collectibles: Dictionary = {}
var _pump_handles: Dictionary = {}
var elevator_cabin: AnimatableBody3D
var _elevator_moving := false
var _elevator_busy := false
var _elevator_passenger: CharacterBody3D
var _elevator_elapsed := 0.0
var _elevator_duration := 10.0
var _elevator_from := 0.0
var _elevator_target := 0.0
var _elevator_platform_layers := 0
var _elevator_passenger_physics := true
var _elevator_display_floor := -99
var _elevator_generation := 0
var _door_guard_clock := 0.0

const COLD := Color("9cbec1")
const CYAN := Color("6ed6c5")
const AMBER := Color("e6a856")
const RED := Color("d04935")

func build() -> void:
	if _built:
		return
	_built = true
	_make_materials()
	_make_layout()
	_arrival()
	_hub()
	_operations()
	_power()
	_cooling()
	_server_hall()
	_security()
	_core()
	_service_corridor()
	_build_navigation()
	_build_approaches()
	_flush_batches()
	_make_reflections()
	for key in anomaly_nodes:
		_anomaly_defaults[key] = anomaly_nodes[key].transform
	screenshot_points = {
		"elevator": {"position": Vector3(-1.7, 1.65, 27), "target": Vector3(0.4, 1.8, 18)},
		"server_hall": {"position": Vector3(-15.6, 1.65, -0.9), "target": Vector3(-14.5, 1.9, -15)},
		"cooling": {"position": Vector3(19.4, 1.7, -1.5), "target": Vector3(10.2, 2.7, -9.5)},
		"cctv": {"position": Vector3(1.5, 1.7, -11.2), "target": Vector3(-3.6, 2.0, -17.3)},
		"core": {"position": Vector3(-3.5, 1.75, -31.5), "target": Vector3(0.6, 5.2, -43)},
		"hub": {"position": Vector3(-2.2, 1.65, 11.4), "target": Vector3(2.8, 1.9, -3)},
	}
	set_stage(0)

func _make_materials() -> void:
	_mat("concrete", Color("494e4c"), 0.91, 0.0, "concrete")
	_mat("wall", Color("89938c"), 0.76, 0.1, "paint")
	_mat("lower", Color("263a3b"), 0.7, 0.2, "paint")
	_mat("floor", Color("303d3e"), 0.39, 0.45, "floor")
	_mat("tile", Color("58625e"), 0.55, 0.25, "floor")
	_mat("wet", Color("273c3c"), 0.18, 0.6, "floor")
	_mat("steel", Color("202b2c"), 0.52, 0.8, "metal")
	_mat("steel_light", Color("747f7c"), 0.38, 0.78, "metal")
	_mat("rack", Color("111c1f"), 0.52, 0.65, "metal")
	_mat("black", Color("0b1113"), 0.66)
	_mat("orange", Color("bd7838"), 0.57, 0.1, "paint")
	_mat("paper", Color("bcb8a1"), 0.92)
	_mat("rubber", Color("151d1e"), 0.92)
	_mat("red", Color("863327"), 0.45, 0.4)
	_mat("water", Color("1b4647"), 0.13, 0.7)
	_emission("lamp", Color("c4ded8"), 2.0)
	_emission("cyan", CYAN, 1.8)
	_emission("amber", AMBER, 1.8)
	_emission("alarm", RED, 1.8)
	_emission("screen", Color("163d3b"), 0.7)
	_emission("screen_dead", Color("081c1d"), 0.12)
	_emission("white", Color("c6d4c7"), 0.25)
	var glass := _mat("glass", Color(0.1, 0.23, 0.24, 0.24), 0.15, 0.35)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED

func _mat(key: String, color: Color, roughness: float, metal: float = 0.0, texture_kind: String = "") -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metal
	if texture_kind != "":
		material.albedo_texture = _texture(texture_kind)
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_triplanar_sharpness = 8.0
		material.uv1_scale = Vector3.ONE * (0.65 if texture_kind == "concrete" else 1.0)
	materials[key] = material
	return material

func _emission(key: String, color: Color, energy: float) -> void:
	var material := _mat(key, color, 0.45)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy

func _texture(kind: String) -> ImageTexture:
	if _texture_cache.has(kind):
		return _texture_cache[kind]
	var texture_image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	for y in range(256):
		for x in range(256):
			var grain := rng.randf_range(0.88, 1.0)
			if kind == "concrete":
				grain -= 0.06 * sin(float(x) * 0.06) * sin(float(y) * 0.13)
				if rng.randf() < 0.02:
					grain -= 0.2
			elif kind == "metal":
				grain = 0.94 + rng.randf_range(-0.04, 0.04) + 0.015 * sin(float(y) * 3.0)
			elif kind == "floor":
				grain = 0.91 + rng.randf_range(-0.035, 0.035)
				if x < 2 or y < 2:
					grain = 0.38
				elif (x < 7 and y < 7) or (x > 249 and y > 249):
					grain = 0.55
			else:
				grain = 0.96 + rng.randf_range(-0.035, 0.035)
			texture_image.set_pixel(x, y, Color(grain, grain, grain))
	texture_image.generate_mipmaps()
	var texture := ImageTexture.create_from_image(texture_image)
	_texture_cache[kind] = texture
	return texture

func _box(pos: Vector3, size: Vector3, material: String, solid: bool = false, yaw: float = 0.0) -> void:
	# Compatibility supports a bounded light list per object. Spatial batches keep
	# distant rooms out of each other's lists and make frustum culling effective.
	var batch_key := material + "|" + str(floori(pos.x / 8.0)) + "|" + str(floori(pos.z / 8.0))
	if not _batches.has(batch_key):
		_batches[batch_key] = []
	var basis := Basis(Vector3.UP, yaw).scaled_local(size)
	_batches[batch_key].append(Transform3D(basis, pos))
	if solid:
		_collider(pos, size, yaw)

func _collider(pos: Vector3, size: Vector3, yaw: float = 0.0, parent_node: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	parent_node.add_child(body)
	body.position = pos
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body

func _dynamic_box(parent_node: Node3D, pos: Vector3, size: Vector3, material: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = materials[material]
	parent_node.add_child(mesh_instance)
	mesh_instance.position = pos
	return mesh_instance

func _flush_batches() -> void:
	for key in _batches:
		var material_key: String = key.get_slice("|", 0)
		var transforms: Array = _batches[key]
		var multi_mesh := MultiMesh.new()
		multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
		multi_mesh.instance_count = transforms.size()
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE
		multi_mesh.mesh = cube
		for i in range(transforms.size()):
			multi_mesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "Architecture_" + key
		instance.multimesh = multi_mesh
		instance.material_override = materials[material_key]
		if material_key in ["cyan", "amber", "alarm", "lamp", "white", "screen"]:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	_batches.clear()

func _cylinder(pos: Vector3, radius: float, height: float, material: String, rotation_value: Vector3 = Vector3.ZERO, top_radius: float = -1.0, parent_node: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.rings = 1
	instance.mesh = mesh
	instance.material_override = materials[material]
	parent_node.add_child(instance)
	instance.position = pos
	instance.rotation = rotation_value
	return instance

func _pipe(a: Vector3, b: Vector3, radius: float, material: String = "steel_light") -> void:
	var pipe := _cylinder((a + b) * 0.5, radius, a.distance_to(b), material)
	pipe.quaternion = Quaternion(Vector3.UP, (b - a).normalized())

func _ring(pos: Vector3, inner_radius: float, outer_radius: float, material: String, rotation_value: Vector3 = Vector3.ZERO, parent_node: Node3D = self) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner_radius
	mesh.outer_radius = outer_radius
	mesh.rings = 32
	mesh.ring_segments = 8
	instance.mesh = mesh
	instance.material_override = materials[material]
	parent_node.add_child(instance)
	instance.position = pos
	instance.rotation = rotation_value
	return instance

func _label(value: String, pos: Vector3, font_size: int = 48, color: Color = COLD, yaw: float = 0.0, pixel: float = 0.005, parent_node: Node3D = self) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.shaded = false
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parent_node.add_child(label)
	label.position = pos
	label.rotation.y = yaw
	return label

func _light(pos: Vector3, color: Color = COLD, energy: float = 2.0, radius: float = 10.0, category: String = "normal") -> OmniLight3D:
	var light := OmniLight3D.new()
	add_child(light)
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 1.8
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 24.0
	light.distance_fade_length = 12.0
	light.distance_fade_shadow = 18.0
	light.set_meta("base_energy", energy)
	light.set_meta("category", category)
	lights.append(light)
	return light

func _fixture(pos: Vector3, length: float = 2.2, yaw: float = 0.0, color: Color = COLD, category: String = "normal", energy: float = 1.9) -> void:
	_box(pos, Vector3(length + 0.22, 0.15, 0.5), "steel", false, yaw)
	_box(pos - Vector3(0, 0.09, 0), Vector3(length, 0.025, 0.26), "lamp", false, yaw)
	_light(pos - Vector3(0, 0.35, 0), color, energy, 10.0, category)

func _wall_x(x: float, from_z: float, to_z: float, height: float = 4.2) -> void:
	var center := (from_z + to_z) * 0.5
	var length := to_z - from_z
	if length <= 0.01:
		return
	_box(Vector3(x, height * 0.5, center), Vector3(0.3, height, length), "wall", true)
	_box(Vector3(x, 0.6, center), Vector3(0.34, 1.15, length), "lower")
	_box(Vector3(x, 1.22, center), Vector3(0.38, 0.08, length), "steel_light")
	_box(Vector3(x, 0.12, center), Vector3(0.42, 0.24, length), "steel")
	for z in range(int(ceil(from_z / 3.0)), int(floor(to_z / 3.0)) + 1):
		_box(Vector3(x, height * 0.5, float(z) * 3.0), Vector3(0.35, height, 0.038), "steel")

func _wall_z(z: float, from_x: float, to_x: float, height: float = 4.2) -> void:
	var center := (from_x + to_x) * 0.5
	var length := to_x - from_x
	if length <= 0.01:
		return
	_box(Vector3(center, height * 0.5, z), Vector3(length, height, 0.3), "wall", true)
	_box(Vector3(center, 0.6, z), Vector3(length, 1.15, 0.34), "lower")
	_box(Vector3(center, 1.22, z), Vector3(length, 0.08, 0.38), "steel_light")
	_box(Vector3(center, 0.12, z), Vector3(length, 0.24, 0.42), "steel")
	for x in range(int(ceil(from_x / 3.0)), int(floor(to_x / 3.0)) + 1):
		_box(Vector3(float(x) * 3.0, height * 0.5, z), Vector3(0.038, height, 0.35), "steel")

func _opening_x(x: float, z: float, width: float = 3.2, height: float = 4.2) -> void:
	_box(Vector3(x, (height + 3.0) * 0.5, z), Vector3(0.55, maxf(height - 3.0, 0.3), width), "steel", true)
	for side in [-1.0, 1.0]:
		_box(Vector3(x, 1.5, z + side * (width * 0.5)), Vector3(0.52, 3.0, 0.18), "steel_light", true)
		_box(Vector3(x + 0.29, 1.5, z + side * (width * 0.5)), Vector3(0.03, 2.2, 0.045), "amber")

func _opening_z(z: float, x: float, width: float = 3.4, height: float = 4.2) -> void:
	_box(Vector3(x, (height + 3.0) * 0.5, z), Vector3(width, height - 3.0, 0.55), "steel", true)
	for side in [-1.0, 1.0]:
		_box(Vector3(x + side * (width * 0.5), 1.5, z), Vector3(0.18, 3.0, 0.52), "steel_light", true)
		_box(Vector3(x + side * (width * 0.5), 1.5, z + 0.29), Vector3(0.045, 2.2, 0.03), "amber")

func _floor(x: float, z: float, width: float, depth: float, material: String = "floor", ceiling: float = 4.2) -> void:
	_box(Vector3(x, -0.16, z), Vector3(width, 0.32, depth), material, true)
	_box(Vector3(x, ceiling + 0.12, z), Vector3(width, 0.24, depth), "concrete", true)

func _make_layout() -> void:
	# Elevator, arrival, hub, east maintenance alcove.
	_floor(0, 17, 6, 10)
	_floor(0, 4, 16, 16)
	_floor(7, 17, 8, 6, "concrete")
	_wall_x(-3, 12, 22)
	_wall_x(3, 20, 22)
	_wall_x(3, 12, 15.4)
	_wall_x(11, 14, 20)
	_wall_z(14, 3, 11)
	_wall_z(20, 3, 11)
	_opening_x(3, 17, 3.2)
	_wall_z(12, -8, -3)
	_wall_z(12, 3, 8)
	_wall_z(-4, -8, -3)
	_wall_z(-4, 3, 8)
	# Hub west has operations and server passages. East has electrical/HVAC.
	for side in [-8.0, 8.0]:
		_wall_x(side, -4, -3.6)
		_wall_x(side, -0.4, 6.4)
		_wall_x(side, 9.6, 12)
		_opening_x(side, -2, 3.2)
		_opening_x(side, 8, 3.2)
	# Operations / electrical.
	_floor(-14, 9, 12, 10, "tile")
	_floor(14, 9, 12, 10, "concrete")
	_wall_x(-20, 4, 6.4)
	_wall_x(-20, 9.6, 14)
	_opening_x(-20, 8, 3.2)
	_wall_z(4, -20, -8)
	_wall_z(14, -20, -8)
	_wall_x(-8, 12, 14)
	_wall_x(20, 4, 14)
	_wall_z(4, 8, 16.3)
	_wall_z(4, 19.7, 20)
	_opening_z(4, 18, 3.4)
	_wall_z(14, 8, 20)
	_wall_x(8, 12, 14)
	_floor(18, 2, 3.4, 4, "steel")
	_wall_x(16.3, 0, 4)
	_wall_x(19.7, 0, 4)
	# Server hall: wide clear longitudinal central aisle at x=-15.
	_floor(-15, -9, 14, 18)
	_wall_x(-22, -18, 0)
	_wall_x(-8, -18, -4)
	_wall_z(0, -22, -8)
	_wall_z(-18, -22, -16.8)
	_wall_z(-18, -13.2, -8)
	_opening_z(-18, -15, 3.6)
	# HVAC opens onto east return corridor.
	_floor(15, -7, 14, 14, "wet", 5.6)
	_floor(19, -16, 6, 4, "steel", 5.6)
	_wall_x(8, -14, -4, 5.6)
	_wall_x(22, -18, 0, 5.6)
	_wall_z(0, 8, 16.3, 5.6)
	_wall_z(0, 19.7, 22, 5.6)
	_opening_z(0, 18, 3.4, 5.6)
	_wall_z(-14, 8, 16, 5.6)
	_wall_x(16, -18, -14, 5.6)
	# Security spine joins the hub to the return passage.
	_floor(0, -6, 6, 4)
	_wall_x(-3, -8, -4)
	_wall_x(3, -8, -4)
	_floor(-2, -13, 12, 10, "tile")
	_wall_z(-8, -8, -1.8)
	_wall_z(-8, 1.8, 4)
	_opening_z(-8, 0, 3.6)
	_wall_x(4, -18, -8)
	_wall_z(-18, -8, -1.8)
	_wall_z(-18, 1.8, 4)
	_opening_z(-18, 0, 3.6)
	# A complete loop along the rear of the facility.
	_floor(0, -20, 44, 4, "steel")
	_wall_x(-22, -22, -18)
	_wall_x(22, -22, -18)
	_wall_z(-22, -22, -3)
	_wall_z(-22, 3, 22)
	_wall_z(-18, 4, 16)
	# Core airlock and the monumental chamber.
	_floor(0, -26, 6, 8, "steel", 4.8)
	_wall_x(-3, -30, -22, 4.8)
	_wall_x(3, -30, -22, 4.8)
	_floor(0, -40, 24, 20, "steel", 14.5)
	_wall_z(-30, -12, -2.1, 14.5)
	_wall_z(-30, 2.1, 12, 14.5)
	_wall_z(-50, -12, 12, 14.5)
	_wall_x(-12, -50, -30, 14.5)
	_wall_x(12, -50, -30, 14.5)
	_opening_z(-30, 0, 4.2, 14.5)
	_door("elevator", Vector3(0, 0, 22), 5.4, 2.5)
	_box(Vector3(0, 2.8, 22), Vector3(6.0, 0.6, 0.34), "steel", true)
	for x in [-2.84, 2.84]:
		_box(Vector3(x, 1.25, 22), Vector3(0.35, 2.5, 0.4), "steel", true)
	_door("core", Vector3(0, 0, -29.4), 4.0, 3.6)
	markers = {
		"spawn": Vector3(0, 0.1, 25.5), "exit": Vector3(0, 0.1, 25.0),
		"hub": Vector3(0, 0.1, 5), "maintenance": Vector3(7.0, 0.1, 17.6),
		"operations": Vector3(-16, 0.1, 7.0), "power": Vector3(15, 0.1, 7.0),
		"cooling": Vector3(17, 0.1, -11.0), "network": Vector3(-11.6, 0.1, -15.0),
		"cctv": Vector3(-2, 0.1, -14.0), "core_access": Vector3(0, 0.1, -26.2),
		"core": Vector3(0, 0.1, -34.5), "observer_cooling": Vector3(19, 0.1, -16),
		"observer_network": Vector3(-15, 0.1, -17), "service": Vector3(-25, 0.1, 8)
	}
	camera_points = [
		{"name": "CAM 06-01 / ARRIVAL", "position": Vector3(2.7, 2.8, 21.4), "target": Vector3(0, 1.2, 12)},
		{"name": "CAM 06-14 / SERVICE HALL", "position": Vector3(-10, 3.5, -2), "target": Vector3(-15, 1.1, -16)},
		{"name": "CAM 06-08 / HVAC", "position": Vector3(21, 4.5, -1), "target": Vector3(17, 1.2, -13)},
		{"name": "CAM 06-04 / SECURITY", "position": Vector3(3.4, 3.6, -9), "target": Vector3(-2, 1.2, -15)},
		{"name": "CAM 06-00 / CORE", "position": Vector3(8, 8, -32), "target": Vector3(0, 4, -43)}
	]
	for point in camera_points:
		_camera_prop(point.position, point.target)

func _door(id: String, pos: Vector3, width: float, height: float) -> void:
	var anchor := Node3D.new()
	anchor.name = id.capitalize() + "Door"
	add_child(anchor)
	anchor.position = pos
	var panels: Array = []
	for side in [-1.0, 1.0]:
		var panel := Node3D.new()
		anchor.add_child(panel)
		panel.position = Vector3(side * width * 0.25, height * 0.5, 0)
		_dynamic_box(panel, Vector3.ZERO, Vector3(width * 0.5 - 0.025, height, 0.18), "steel_light")
		_dynamic_box(panel, Vector3(0, 0.15, 0.11), Vector3(width * 0.5 - 0.15, height * 0.54, 0.06), "steel")
		_dynamic_box(panel, Vector3(0, -height * 0.37, 0.15), Vector3(width * 0.5 - 0.12, 0.14, 0.035), "orange")
		var door_body := _collider(Vector3.ZERO, Vector3(width * 0.5 + 0.015, height, 0.24), 0.0, panel)
		door_body.add_to_group("facility_doors")
		panel.set_meta("side", side)
		panels.append(panel)
	_doors[id] = {"anchor": anchor, "panels": panels, "width": width, "height": height, "open": false, "moving": false, "settled": true, "tween": null}

func set_door(id: String, opened: bool) -> void:
	if not _doors.has(id):
		return
	if id == "elevator" and _elevator_moving:
		return
	var data: Dictionary = _doors[id]
	if data.open == opened and (data.moving or data.settled):
		return
	if not opened and _door_obstructed(id):
		if not data.open:
			set_door(id, true)
		return
	data.open = opened
	data.moving = true
	data.settled = false
	if data.tween != null and is_instance_valid(data.tween):
		data.tween.kill()
	var tween := create_tween().set_parallel(true).set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	data.tween = tween
	mechanism_cue.emit("door", data.anchor.global_position + Vector3.UP)
	for panel in data.panels:
		var side: float = panel.get_meta("side")
		var x: float = side * data.width * (0.76 if opened else 0.25)
		tween.tween_property(panel, "position:x", x, DOOR_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		data.moving = false
		data.settled = true
		door_state_changed.emit(id, opened)
	)

func _door_obstructed(id: String) -> bool:
	if not is_inside_tree():
		return false
	var data: Dictionary = _doors[id]
	var shape := BoxShape3D.new()
	shape.size = Vector3(data.width + 0.35, data.height, 0.95)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, data.anchor.global_position + Vector3.UP * data.height * 0.5)
	query.collision_mask = 4 | 8
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func is_door_open(id: String) -> bool:
	return _doors.has(id) and _doors[id].open and _doors[id].settled

func elevator_contains(point: Vector3) -> bool:
	if not is_instance_valid(elevator_cabin):
		return false
	var local := elevator_cabin.to_local(point)
	return absf(local.x) < 2.5 and local.z > 22.65 and local.z < 27.5 and local.y > -0.3 and local.y < 2.3

func is_elevator_moving() -> bool:
	return _elevator_busy

func set_elevator_status(value: String) -> void:
	if anomaly_nodes.has("elevator_display"):
		anomaly_nodes.elevator_display.text = value

func reset_elevator(at_surface: bool = false) -> void:
	_elevator_generation += 1
	_elevator_moving = false
	_elevator_busy = false
	_release_passenger()
	elevator_cabin.position.y = ELEVATOR_SURFACE_HEIGHT if at_surface else 0.0
	_elevator_display_floor = -99
	set_elevator_status("G" if at_surface else "B6")
	_snap_door("elevator", false)

func _snap_door(id: String, opened: bool) -> void:
	var door: Dictionary = _doors[id]
	if door.tween != null and is_instance_valid(door.tween):
		door.tween.kill()
	for panel in door.panels:
		panel.position.x = panel.get_meta("side") * door.width * (0.76 if opened else 0.25)
	door.open = opened
	door.moving = false
	door.settled = true

func travel_elevator(to_surface: bool, passenger: CharacterBody3D, duration: float = 10.0) -> bool:
	if _elevator_busy or not is_instance_valid(passenger) or not elevator_contains(passenger.global_position):
		return false
	_elevator_busy = true
	var generation := _elevator_generation
	set_door("elevator", false)
	while _doors.elevator.moving:
		await get_tree().physics_frame
		if generation != _elevator_generation:
			return false
	if _doors.elevator.open or not elevator_contains(passenger.global_position):
		_elevator_busy = false
		return false
	_elevator_passenger = passenger
	_elevator_platform_layers = passenger.platform_floor_layers
	_elevator_passenger_physics = passenger.is_physics_processing()
	# While controls allow looking only, transport the passenger with the cabin.
	# Suspending gravity avoids recovery against the previous physics-frame floor.
	passenger.set_physics_process(false)
	passenger.platform_floor_layers = 0
	passenger.velocity = Vector3.ZERO
	_elevator_from = elevator_cabin.position.y
	_elevator_target = ELEVATOR_SURFACE_HEIGHT if to_surface else 0.0
	_elevator_elapsed = 0.0
	_elevator_duration = maxf(duration, 0.1)
	_elevator_moving = true
	mechanism_cue.emit("elevator", elevator_cabin.global_position + Vector3(0, 1, 25))
	while _elevator_moving:
		await get_tree().physics_frame
		if generation != _elevator_generation:
			return false
	return true

func _release_passenger() -> void:
	if is_instance_valid(_elevator_passenger):
		_elevator_passenger.platform_floor_layers = _elevator_platform_layers
		_elevator_passenger.set_physics_process(_elevator_passenger_physics)
		_elevator_passenger.velocity = Vector3.ZERO
	_elevator_passenger = null

func _interaction(id: String, label_text: String, pos: Vector3, size: Vector3 = Vector3(1.4, 1.3, 0.22), yaw: float = 0.0, parent_node: Node3D = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Interact_" + id
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("interaction_id", id)
	body.set_meta("label", label_text)
	parent_node.add_child(body)
	body.position = pos
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	interactables[id] = body
	return body

func _terminal(id: String, heading: String, lines: String, pos: Vector3, width: float = 1.8) -> void:
	_box(pos + Vector3(0, -0.65, -0.1), Vector3(width + 0.22, 0.5, 0.65), "steel", true)
	_box(pos + Vector3(0, -1.0, -0.1), Vector3(width * 0.8, 0.5, 0.52), "lower", true)
	_box(pos, Vector3(width, 1.1, 0.22), "rack", true)
	var screen := _dynamic_box(self, pos + Vector3(0, 0, 0.13), Vector3(width - 0.15, 0.9, 0.025), "screen")
	_screens.append(screen)
	_label(heading, pos + Vector3(0, 0.27, 0.151), 38, CYAN, 0.0, 0.0032)
	_terminal_labels[id] = _label(lines, pos + Vector3(0, -0.10, 0.151), 25, COLD, 0.0, 0.0034)
	_terminal_defaults[id] = lines
	_box(pos + Vector3(0, -0.63, 0.29), Vector3(width * 0.65, 0.06, 0.27), "black")
	for x in range(12):
		for z in range(3):
			_box(pos + Vector3(-width * 0.28 + x * width * 0.046, -0.59, 0.2 + z * 0.072), Vector3(0.045, 0.02, 0.043), "steel_light")
	_interaction(id, heading, pos + Vector3(0, 0, 0.2), Vector3(width, 1.55, 0.32))

func set_terminal_status(id: String, value: String) -> void:
	if _terminal_labels.has(id):
		_terminal_labels[id].text = value

func set_collected(id: String, collected: bool) -> void:
	if _collectibles.has(id):
		_collectibles[id].visible = not collected
	if interactables.has(id):
		interactables[id].collision_layer = 0 if collected else 2
		interactables[id].set_meta("collected", collected)

func set_pump_state(id: String, enabled: bool) -> void:
	if not _pump_handles.has(id):
		return
	var data: Dictionary = _pump_handles[id]
	data.handle.rotation.x = -0.7 if enabled else 0.0
	data.status.text = "RUNNING / LOCAL READY" if enabled else "LOCAL / MANUAL START"
	data.status.modulate = CYAN if enabled else COLD
	for lamp in data.lamps:
		lamp.material_override = materials["cyan" if enabled else "amber"]

func reset_interactions() -> void:
	_snap_door("core", false)
	for id in _collectibles:
		set_collected(id, false)
	for id in _pump_handles:
		set_pump_state(id, false)
	for id in _terminal_defaults:
		set_terminal_status(id, _terminal_defaults[id])
	for screen in _screens:
		_update_monitor_status(screen, 0)

func _note(id: String, heading: String, text_value: String, pos: Vector3, yaw: float = 0.0) -> void:
	_box(pos, Vector3(0.74, 0.96, 0.025), "paper", false, yaw)
	_label(heading, pos + Vector3(sin(yaw) * 0.025, 0.32, cos(yaw) * 0.025), 29, Color("253636"), yaw, 0.0023)
	_label(text_value, pos + Vector3(sin(yaw) * 0.026, -0.04, cos(yaw) * 0.026), 24, Color("253636"), yaw, 0.0022)
	_interaction(id, heading, pos + Vector3(sin(yaw) * 0.06, 0, cos(yaw) * 0.06), Vector3(0.8, 1.05, 0.08), yaw)

func _sign(value: String, pos: Vector3, width: float = 2.7, yaw: float = 0.0, color: Color = COLD) -> Label3D:
	_box(pos, Vector3(width, 0.66, 0.07), "steel", false, yaw)
	return _label(value, pos + Vector3(sin(yaw) * 0.045, 0, cos(yaw) * 0.045), 48, color, yaw, 0.0038)

func _cable_tray(a: Vector3, b: Vector3, width: float = 0.9) -> void:
	var length := a.distance_to(b)
	var center := (a + b) * 0.5
	var along_z: bool = absf(b.z - a.z) > absf(b.x - a.x)
	var yaw: float = 0.0 if along_z else PI * 0.5
	_box(center, Vector3(width, 0.08, length), "black", false, yaw)
	for side in [-1.0, 1.0]:
		var offset := Vector3(side * width * 0.5, 0.12, 0).rotated(Vector3.UP, yaw)
		_box(center + offset, Vector3(0.04, 0.25, length), "steel_light", false, yaw)
	for n in range(int(length / 0.65)):
		var point := a.lerp(b, float(n) * 0.65 / length)
		_box(point + Vector3(0, -0.05, 0), Vector3(width, 0.035, 0.045), "steel_light", false, yaw)
	for n in range(5):
		var offset := Vector3(-width * 0.32 + n * width * 0.16, 0.065, 0).rotated(Vector3.UP, yaw)
		_box(center + offset, Vector3(0.075, 0.065, length), "rubber", false, yaw)

func _hazard_line(pos: Vector3, width: float, along_z: bool = false) -> void:
	var yaw: float = PI * 0.5 if along_z else 0.0
	_box(pos, Vector3(width, 0.012, 0.3), "orange", false, yaw)
	for n in range(int(width / 0.42)):
		var offset := Vector3(-width * 0.5 + n * 0.42 + 0.12, 0.008, 0).rotated(Vector3.UP, yaw)
		_box(pos + offset, Vector3(0.19, 0.012, 0.32), "black", false, yaw + 0.35)

func _arrival() -> void:
	_build_elevator()
	_hazard_line(Vector3(0, 0.018, 22.1), 5.5)
	for z in [14, 18]:
		_fixture(Vector3(0, 3.95, z), 2.0)
		_box(Vector3(0, 3.8, z), Vector3(5.7, 0.12, 0.16), "steel")
	_cable_tray(Vector3(-1.8, 3.65, 12), Vector3(-1.8, 3.65, 22), 0.65)
	_pipe(Vector3(2.55, 3.2, 12), Vector3(2.55, 3.2, 22), 0.10)
	_sign("SECTOR 06  /  OPERATIONS", Vector3(0, 3.05, 12.1), 4.7)
	_sign("F  /  SURFACE LIFT", Vector3(0, 2.8, 21.76), 3.6, PI)
	_sign("MAINTENANCE", Vector3(3.22, 2.65, 17), 2.6, -PI * 0.5, AMBER)
	# Service workbench, stocked shelves, fuse carrier and handwritten job ticket.
	_box(Vector3(8.2, 0.87, 14.8), Vector3(4.4, 0.16, 1.1), "steel_light", true)
	for x in [6.3, 10.1]:
		_box(Vector3(x, 0.43, 14.8), Vector3(0.12, 0.86, 0.8), "steel", true)
	var fuse := Node3D.new()
	fuse.name = "FuseCarrier"
	add_child(fuse)
	_dynamic_box(fuse, Vector3(8.25, 1.04, 15.0), Vector3(0.64, 0.21, 0.42), "orange")
	for x in [8.05, 8.22, 8.39]:
		_cylinder(Vector3(x, 1.18, 15.0), 0.053, 0.28, "steel_light", Vector3(PI * 0.5, 0, 0), -1.0, fuse)
	_interaction("fuse", "PICK UP / FUSE CARRIER", Vector3(8.25, 1.15, 15.1), Vector3(0.9, 0.5, 0.7))
	_collectibles["fuse"] = fuse
	_sign("SERVICE STOCK / 06", Vector3(8, 2.8, 14.23), 3.5, 0, AMBER)
	_label("REPLACEMENT FUSE CARRIER\nISOLATE DISTRIBUTION BEFORE FITTING", Vector3(8, 2.2, 14.25), 32, COLD, 0, 0.003)
	for y in [0.5, 1.35, 2.2]:
		_box(Vector3(10.5, y, 17.2), Vector3(0.65, 0.09, 3.1), "steel")
		for z in [16.3, 17.15, 18.0]:
			_box(Vector3(10.5, y + 0.22, z), Vector3(0.51, 0.37, 0.62), "lower")
	_fixture(Vector3(7.5, 3.9, 17), 1.7, PI * 0.5, AMBER, "normal", 1.5)

func _cabin_box(pos: Vector3, size: Vector3, material: String, solid: bool = false) -> MeshInstance3D:
	var visual := _dynamic_box(elevator_cabin, pos, size, material)
	if solid:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		collision.position = pos
		elevator_cabin.add_child(collision)
	return visual

func _build_elevator() -> void:
	elevator_cabin = AnimatableBody3D.new()
	elevator_cabin.name = "SurfaceLiftCabin"
	elevator_cabin.collision_layer = 1
	elevator_cabin.collision_mask = 0
	elevator_cabin.sync_to_physics = false
	add_child(elevator_cabin)
	_doors.elevator.anchor.reparent(elevator_cabin, false)
	_cabin_box(Vector3(0, -0.16, 25), Vector3(6, 0.32, 6), "steel_light", true)
	_cabin_box(Vector3(0, 3.22, 25), Vector3(6, 0.24, 6), "steel", true)
	_cabin_box(Vector3(0, 2.8, 22.1), Vector3(6, 0.6, 0.18), "steel", true)
	for x in [-2.83, 2.83]:
		_cabin_box(Vector3(x, 1.25, 22.1), Vector3(0.22, 2.5, 0.2), "steel", true)
	_cabin_box(Vector3(-2.92, 1.55, 25), Vector3(0.16, 3.1, 6), "steel_light", true)
	_cabin_box(Vector3(0, 1.55, 27.92), Vector3(6, 3.1, 0.16), "steel_light", true)
	# Inspection glazing reveals fixed rails and landing marks during real travel.
	for z in [23.0, 27.25]:
		_cabin_box(Vector3(2.92, 1.55, z), Vector3(0.16, 3.1, 2.0 if z < 24 else 1.5), "steel_light", true)
	_cabin_box(Vector3(2.92, 0.56, 25.25), Vector3(0.16, 1.12, 2.5), "steel", true)
	_cabin_box(Vector3(2.92, 2.75, 25.25), Vector3(0.16, 0.7, 2.5), "steel_light", true)
	_cabin_box(Vector3(2.94, 1.76, 25.25), Vector3(0.06, 1.28, 2.5), "glass", true)
	for z in [24.0, 25.25, 26.5]:
		_cabin_box(Vector3(2.85, 1.76, z), Vector3(0.12, 1.4, 0.07), "steel")
	for x in [-2.72, 2.72]:
		_cabin_box(Vector3(x, 1.0, 25), Vector3(0.07, 0.07, 4.4), "steel_light")
		_cabin_box(Vector3(x, 0.43, 25), Vector3(0.12, 0.75, 5.6), "steel")
	_cabin_box(Vector3(0, 2.93, 25), Vector3(3.3, 0.13, 0.5), "steel")
	_cabin_box(Vector3(0, 2.85, 25), Vector3(3.1, 0.03, 0.26), "lamp")
	var cabin_light := _light(Vector3(0, 2.58, 25), Color("d5dfc7"), 2.5, 7, "arrival")
	cabin_light.reparent(elevator_cabin, false)
	_cabin_box(Vector3(0, 2.8, 22.21), Vector3(1.8, 0.52, 0.05), "black")
	anomaly_nodes["elevator_display"] = _label("B6", Vector3(0, 2.8, 22.25), 66, AMBER, 0, 0.005, elevator_cabin)
	_label("MERIDIAN / SUBSURFACE SYSTEMS", Vector3(0, 2.2, 27.73), 44, COLD, PI, 0.0035, elevator_cabin)
	_label("CAPACITY  1800 KG\nAUTHORIZED PERSONNEL ONLY", Vector3(-2.81, 1.95, 25), 25, Color("293839"), PI * 0.5, 0.003, elevator_cabin)
	_cabin_box(Vector3(2.75, 1.35, 23.35), Vector3(0.17, 1.8, 1.0), "steel")
	for data in [["exit", "SURFACE", 1.92], ["elevator_open", "OPEN", 1.36], ["elevator_close", "CLOSE", 0.8]]:
		_cabin_box(Vector3(2.64, data[2], 23.35), Vector3(0.055, 0.21, 0.25), "amber")
		_label(data[1], Vector3(2.60, data[2] + 0.19, 23.35), 25, COLD, -PI * 0.5, 0.0028, elevator_cabin)
		_interaction(data[0], "LIFT / " + data[1], Vector3(2.57, data[2], 23.35), Vector3(0.25, 0.3, 0.6), 0, elevator_cabin)
	_box(Vector3(2.80, 1.55, 21.66), Vector3(0.25, 0.65, 0.15), "steel")
	_box(Vector3(2.80, 1.55, 21.55), Vector3(0.12, 0.15, 0.04), "amber")
	_label("CALL", Vector3(2.80, 1.85, 21.54), 25, AMBER, PI, 0.0028)
	_interaction("elevator_call", "LIFT / CALL CAR", Vector3(2.80, 1.55, 21.47), Vector3(0.38, 0.65, 0.2))
	# The shaft remains at world height while the cabin and passenger move 30 m.
	for x in [-3.6, 3.6]:
		_box(Vector3(x, 17, 25), Vector3(0.3, 35, 6.6), "concrete", true)
		for z in [23.4, 26.9]:
			_box(Vector3(x * 0.93, 17, z), Vector3(0.13, 35, 0.16), "steel_light")
	_box(Vector3(0, 17, 28.45), Vector3(7.4, 35, 0.3), "concrete", true)
	_box(Vector3(0, 18.8, 21.65), Vector3(7.4, 30.2, 0.3), "concrete", true)
	for floor_number in range(7):
		var height := float(floor_number) * 5.0
		_box(Vector3(3.38, height + 1.5, 25), Vector3(0.12, 0.22, 6.2), "orange")
		_label("B" + str(6 - floor_number) if floor_number < 6 else "SURFACE", Vector3(3.39, height + 2.05, 25.0), 60, AMBER, -PI * 0.5, 0.005)
		_light(Vector3(3.23, height + 2.8, 25.5), AMBER, 0.65, 4.0, "shaft")

func _hub() -> void:
	# Architectural rhythm: cold suspended lights, structural ribs, dark lower walls.
	for z in [-1.0, 5.0, 10.0]:
		_fixture(Vector3(0, 3.8, z), 3.0, 0, COLD, "hub", 2.0)
		_box(Vector3(0, 3.99, z), Vector3(15.6, 0.25, 0.32), "steel")
	for x in [-6.0, 6.0]:
		_cable_tray(Vector3(x, 3.5, -3), Vector3(x, 3.5, 11), 0.9)
	_box(Vector3(0, 0.006, 4), Vector3(0.08, 0.013, 15.2), "orange")
	for x in [-4.0, 4.0]:
		_box(Vector3(x, 0.005, 4), Vector3(0.035, 0.012, 15.2), "steel_light")
	_label("06", Vector3(-5.0, 2.45, 11.8), 220, COLD, PI, 0.006)
	_label("MERIDIAN\nSUBSURFACE SYSTEMS", Vector3(5, 2.5, 11.8), 52, COLD, PI, 0.004)
	_sign("A  /  OPERATIONS", Vector3(-7.73, 2.7, 8), 3.0, PI * 0.5)
	_sign("C  /  ELECTRICAL", Vector3(7.73, 2.7, 8), 3.0, -PI * 0.5, AMBER)
	_sign("B  /  COOLING", Vector3(7.73, 2.7, -2), 3.0, -PI * 0.5)
	_sign("A  /  SERVER HALL", Vector3(-7.73, 2.7, -2), 3.0, PI * 0.5)
	_sign("D  /  SECURITY     E  /  CORE", Vector3(0, 3.02, -3.8), 5.8)
	anomaly_nodes["sign"] = _sign("EXIT  /  SURFACE", Vector3(0, 2.8, 11.82), 3.6, PI, CYAN)
	# Lit directory sits on the east wall, facing through the entrance.
	_box(Vector3(7.68, 1.9, 3.2), Vector3(0.12, 1.8, 2.9), "rack")
	_label("SECTOR 06", Vector3(7.58, 2.43, 3.2), 61, CYAN, -PI * 0.5, 0.004)
	_label("OPERATIONS     A\nELECTRICAL     C\nCOOLING        B\nSERVER HALL    A\nSECURITY       D\nCORE           E", Vector3(7.57, 1.75, 3.2), 29, COLD, -PI * 0.5, 0.004)
	_extinguisher(Vector3(-7.57, 1.1, 3.2))
	var chair := _chair(Vector3(-6.7, 0, 5.0), 0.3)
	anomaly_nodes["chair"] = chair
	# An unneeded office shutter provides the observation door event.
	_box(Vector3(-7.69, 1.45, 1.2), Vector3(0.14, 2.9, 1.6), "black")
	var false_door := Node3D.new()
	add_child(false_door)
	false_door.position = Vector3(-7.55, 0, 1.2)
	false_door.rotation.y = -PI / 3.0
	_dynamic_box(false_door, Vector3(0, 1.35, 0), Vector3(0.1, 2.7, 1.45), "lower")
	_dynamic_box(false_door, Vector3(0.09, 1.4, 0.48), Vector3(0.04, 0.21, 0.13), "steel_light")
	anomaly_nodes["door"] = false_door
	_sign("05 / ARCHIVE", Vector3(-7.43, 2.96, 1.2), 1.8, PI * 0.5)
	for z in [-6, -20]:
		_fixture(Vector3(0, 3.94, z), 1.6, 0, COLD, "rear", 1.7)
	for x in [-18.0, -10.0, 9.0, 18.0]:
		_fixture(Vector3(x, 3.92, -20), 1.8, 0, COLD, "rear", 1.4)
	_cable_tray(Vector3(-21, 3.6, -20.9), Vector3(21, 3.6, -20.9), 0.8)
	_pipe(Vector3(-21, 3.4, -18.4), Vector3(21, 3.4, -18.4), 0.085)
	_sign("E / LEVEL 6 CORE", Vector3(0, 3.0, -21.82), 4.0, 0, AMBER)
	_sign("SERVER HALL  <     SECURITY  >", Vector3(-10, 2.5, -21.78), 4.6)
	_sign("COOLING  >", Vector3(13, 2.5, -21.78), 2.9)

func _operations() -> void:
	_fixture(Vector3(-14, 3.9, 7), 3.0, 0, COLD, "operations", 2.4)
	_fixture(Vector3(-14, 3.9, 12), 2.2, 0, COLD, "operations", 1.3)
	_terminal("operations", "SECTOR 06 / OPERATIONS", "TELEMETRY LOST\nPOWER  --   COOLING  --   NETWORK  --", Vector3(-16, 1.6, 4.7), 2.3)
	_sign("NIGHT OPERATIONS", Vector3(-14, 3.0, 4.24), 4.4)
	_sign("ARCHIVE / OFFLINE MODULE", Vector3(-19.73, 2.8, 8), 3.3, PI * 0.5, AMBER)
	for x in [-11.5, -9.4]:
		_desk(Vector3(x, 0, 5.2), 0)
		_monitor(Vector3(x, 1.38, 4.9), "NO SIGNAL", 0.95)
		_chair(Vector3(x, 0, 6.7), 0)
	# Observation glazing overlooking an inaccessible server plenum.
	_box(Vector3(-13.3, 2.0, 13.76), Vector3(8.0, 2.2, 0.035), "glass")
	for x in [-17.2, -15.2, -13.2, -11.2, -9.2]:
		_box(Vector3(x, 2, 13.72), Vector3(0.07, 2.3, 0.1), "steel_light")
	for y in [0.9, 3.1]:
		_box(Vector3(-13.2, y, 13.71), Vector3(8.1, 0.08, 0.12), "steel_light")
	_box(Vector3(-18.8, 0.8, 11.8), Vector3(1.7, 1.6, 1.0), "lower", true)
	for y in [0.25, 0.65, 1.05, 1.45]:
		_box(Vector3(-18.8, y, 12.32), Vector3(1.48, 0.03, 0.035), "steel_light")
		_box(Vector3(-18.8, y + 0.16, 12.35), Vector3(0.24, 0.035, 0.065), "steel_light")
	_label("SHIFT 03 / 02:14\n\nALL PERSONNEL: CHECK OUT IN PAIRS\n\nDO NOT RESET THE ISOLATION BUS", Vector3(-19.76, 2.0, 5.2), 32, COLD, PI * 0.5, 0.0033)
	_cylinder(Vector3(-11.1, 0.98, 5.35), 0.085, 0.15, "paper")
	_ring(Vector3(-10.99, 0.98, 5.35), 0.04, 0.065, "paper", Vector3(PI * 0.5, 0, 0))

func _power() -> void:
	_fixture(Vector3(14, 3.9, 8), 2.9, 0, AMBER, "power", 2.0)
	_fixture(Vector3(16, 3.9, 12), 2.0, 0, COLD, "power", 1.2)
	_terminal("power", "POWER DISTRIBUTION", "BUS 06 / ISOLATED\nINSERT CARRIER / SEQUENCE REQUIRED", Vector3(15, 1.6, 4.7), 2.05)
	_note("note_power", "DISTRIBUTION / RESET", "STARTUP ORDER\n\n2  >  1  >  3\n\nFIT CARRIER FIRST\nSERVICE STOCK: ARRIVAL", Vector3(12.0, 1.75, 4.25))
	_sign("C / ELECTRICAL DISTRIBUTION", Vector3(12.3, 3.15, 4.25), 5.6, 0, AMBER)
	_sign("COOLING / PRESSURE RELEASE", Vector3(18, 3.15, 4.32), 3.3, 0, CYAN)
	_sign("ELECTRICAL / SERVICE LINK", Vector3(18, 3.15, -0.32), 3.3, PI, AMBER)
	_fixture(Vector3(18, 3.92, 2), 1.55, 0, COLD, "normal", 1.6)
	_box(Vector3(18, 0.015, 2), Vector3(0.08, 0.02, 3.8), "orange")
	for z in [7, 9.2, 11.4]:
		_box(Vector3(19.12, 1.46, z), Vector3(1.35, 2.92, 1.95), "steel", true)
		_box(Vector3(18.42, 1.5, z), Vector3(0.06, 2.65, 1.75), "lower")
		_label("600 V\nISOLATION", Vector3(18.35, 2.1, z), 33, AMBER, -PI * 0.5, 0.0035)
		for level in [0.5, 0.72, 0.94]:
			for segment in range(6):
				_box(Vector3(18.37, level, z - 0.63 + segment * 0.25), Vector3(0.04, 0.08, 0.13), "black")
		_box(Vector3(18.32, 1.4, z - 0.45), Vector3(0.11, 0.19, 0.08), "steel_light")
		_box(Vector3(18.34, 2.45, z + 0.55), Vector3(0.04, 0.08, 0.08), "amber")
	for x in [10.0, 11.5]:
		_box(Vector3(x, 1.15, 12.95), Vector3(1.3, 2.3, 1.2), "steel", true)
		for y in range(8):
			_box(Vector3(x, 0.4 + y * 0.19, 12.32), Vector3(1.08, 0.035, 0.04), "black")
		_pipe(Vector3(x, 2.3, 13), Vector3(x, 3.4, 13), 0.12)
	_hazard_line(Vector3(17.65, 0.018, 9.5), 7.5, true)
	_cable_tray(Vector3(17.8, 3.55, 4.5), Vector3(17.8, 3.55, 13.5), 1.1)
	_box(Vector3(14.0, 0.012, 8.1), Vector3(4.0, 0.025, 1.4), "rubber")
	_extinguisher(Vector3(8.42, 1.1, 11))

func _cooling() -> void:
	_fixture(Vector3(13, 5.25, -3.5), 3.0, 0, Color("8fbfc2"), "cooling", 2.8)
	_fixture(Vector3(18.5, 5.25, -10.5), 2.8, 0, COLD, "cooling", 2.7)
	_light(Vector3(10, 1.5, -10), CYAN, 1.4, 8.0, "cooling")
	_terminal("cooling", "COOLANT FLOW CONTROL", "INLET / BYPASS / RETURN\nMANUAL PRESSURE BALANCE REQUIRED", Vector3(17, 1.6, -13.45), 2.2)
	_note("note_cooling", "HVAC / FLOW ENVELOPE", "NORMAL PRESSURE\n\nINLET       2\nBYPASS      4\nRETURN      3\n\nKEEP THIS MANIFOLD OPEN", Vector3(14.8, 1.75, -13.75))
	_sign("B / COOLING PLANT", Vector3(14.5, 4.05, -13.74), 5.0)
	# Two enormous axial fan plenums on the west wall, framed and grilled.
	for z in [-5.5, -10.7]:
		_box(Vector3(9.15, 2.6, z), Vector3(1.75, 4.9, 4.5), "steel", true)
		_box(Vector3(10.08, 2.7, z), Vector3(0.14, 4.3, 4.05), "black")
		_ring(Vector3(10.2, 2.7, z), 1.6, 1.87, "steel_light", Vector3(0, 0, PI * 0.5))
		var rotor := Node3D.new()
		add_child(rotor)
		rotor.position = Vector3(10.26, 2.7, z)
		rotor.rotation.z = PI * 0.5
		_cylinder(Vector3.ZERO, 0.37, 0.18, "steel_light", Vector3.ZERO, -1.0, rotor)
		for i in range(8):
			var angle := float(i) * TAU / 8.0
			var blade := _dynamic_box(rotor, Vector3(cos(angle) * 0.85, 0, sin(angle) * 0.85), Vector3(1.25, 0.08, 0.36), "lower")
			blade.rotation.y = -angle + 0.3
		_fans.append(rotor)
		for n in range(-7, 8):
			_box(Vector3(10.38, 2.7 + float(n) * 0.23, z), Vector3(0.045, 0.025, 3.7), "steel_light")
			_box(Vector3(10.4, 2.7, z + float(n) * 0.23), Vector3(0.045, 3.7, 0.025), "steel_light")
		_label("AIR HANDLER / 0" + str(1 if z > -8 else 2), Vector3(10.51, 4.87, z), 38, COLD, PI * 0.5, 0.003)
	# Chilled water pipes flank the player route, insulated trunk overhead.
	for z in [-3.0, -7.0, -11.0]:
		_pipe(Vector3(21.15, 0.4, z), Vector3(21.15, 4.7, z), 0.16, "steel_light")
		_pipe(Vector3(21.15, 4.7, z), Vector3(11.2, 4.7, z), 0.16, "steel_light")
		for y in [0.7, 2.8, 4.4]:
			_cylinder(Vector3(21.15, y, z), 0.21, 0.11, "orange")
		_ring(Vector3(20.94, 1.45, z), 0.23, 0.31, "red", Vector3(0, 0, PI * 0.5))
		_pipe(Vector3(20.8, 1.45, z - 0.23), Vector3(20.8, 1.45, z + 0.23), 0.025, "red")
	_pipe(Vector3(20.6, 4.95, 0), Vector3(20.6, 4.95, -17.5), 0.30, "lower")
	for z in [-2.0, -6.0, -10.0, -16.0]:
		_cylinder(Vector3(20.6, 4.95, z), 0.35, 0.2, "steel_light", Vector3(PI * 0.5, 0, 0))
	# Recessed drains suggest condensate without costly transparent planes.
	for z in [-4.0, -8.0, -12.0]:
		_box(Vector3(16.4, 0.008, z), Vector3(3.4, 0.015, 0.34), "black")
		for x in range(17):
			_box(Vector3(14.82 + x * 0.2, 0.02, z), Vector3(0.025, 0.02, 0.34), "steel_light")
	_box(Vector3(12.6, 0.007, -8), Vector3(1.6, 0.01, 3.2), "water")
	_hazard_line(Vector3(11.2, 0.025, -7.9), 10.7, true)
	_fixture(Vector3(19, 5.2, -16), 1.8, 0, AMBER, "rear", 1.3)
	_sign("SERVER HALL / REAR ROUTE", Vector3(19, 3.0, -14.1), 4.5, 0, CYAN)
	for x in [17.4, 20.6]:
		_box(Vector3(x, 4.38, -14.1), Vector3(0.055, 2.1, 0.055), "steel_light")
	_label("TURN LEFT AT THE REAR JUNCTION", Vector3(19, 2.52, -14.05), 31, COLD, 0, 0.0031)
	_sign("<  A / SERVER HALL", Vector3(18.9, 2.7, -21.78), 4.2, 0, CYAN)
	_pump_switch("pump_a", "PUMP A / PRIMARY", Vector3(13, 1.45, -0.32), PI)
	_pump_switch("pump_b", "PUMP B / RETURN", Vector3(21.72, 1.45, -15.5), -PI * 0.5)

func _pump_switch(id: String, caption: String, pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_box(pos, Vector3(0.92, 1.18, 0.28), "steel", true, yaw)
	_box(pos + basis * Vector3(0, 0.02, 0.16), Vector3(0.78, 0.96, 0.08), "lower", false, yaw)
	_box(pos + basis * Vector3(0, 0.14, 0.23), Vector3(0.36, 0.36, 0.06), "black", false, yaw)
	var handle := _dynamic_box(self, pos + basis * Vector3(0, 0.14, 0.30), Vector3(0.09, 0.24, 0.12), "orange")
	handle.rotation.y = yaw
	var lamps: Array[MeshInstance3D] = []
	for x in [-0.23, 0.23]:
		var lamp := _dynamic_box(self, pos + basis * Vector3(x, -0.3, 0.22), Vector3(0.07, 0.07, 0.025), "amber")
		lamp.rotation.y = yaw
		lamps.append(lamp)
	_label(caption, pos + basis * Vector3(0, 0.78, 0.20), 38, AMBER, yaw, 0.0033)
	var status := _label("LOCAL / MANUAL START", pos + basis * Vector3(0, -0.48, 0.225), 24, COLD, yaw, 0.0027)
	_pump_handles[id] = {"handle": handle, "status": status, "lamps": lamps}
	_interaction(id, caption + " / RESTART", pos + basis * Vector3(0, 0, 0.35), Vector3(1.0, 1.3, 0.35), yaw)

func _server_hall() -> void:
	_sign("A / COMPUTE HALL", Vector3(-15, 3.2, -17.76), 5.3)
	_sign("F / LIFT VIA SERVER HALL", Vector3(-15, 2.8, -18.25), 4.6, PI, CYAN)
	_sign("HUB / SURFACE LIFT", Vector3(-8.28, 2.65, -2), 3.0, -PI * 0.5, CYAN)
	for z in [-2.0, -7.0, -12.0, -16.5]:
		_fixture(Vector3(-15, 3.82, z), 2.0, 0, Color("93b7c1"), "server", 1.9)
		_box(Vector3(-15, 3.99, z), Vector3(13.6, 0.15, 0.22), "steel")
	for x in [-19.7, -10.3]:
		_cable_tray(Vector3(x, 3.54, -0.8), Vector3(x, 3.54, -17.2), 1.3)
		for n in range(6):
			var z := -3.8 - n * 1.85
			_rack(Vector3(x, 0, z), PI * 0.5 if x < -15 else -PI * 0.5, n + (1 if x < -15 else 7))
	for x in [-17.3, -12.7]:
		_box(Vector3(x, 0.01, -8.5), Vector3(0.08, 0.015, 16.4), "orange")
	# Raised floor center ventilation band.
	_box(Vector3(-15, 0.007, -8.6), Vector3(1.4, 0.015, 16.4), "black")
	for z in range(80):
		_box(Vector3(-15, 0.02, -0.6 - z * 0.2), Vector3(1.4, 0.025, 0.036), "steel_light")
	_terminal("network", "NETWORK / FIBRE ROUTING", "NODE 06 / SYNCHRONIZATION LOST\nPATCH UPLINKS IN ASSIGNED ORDER", Vector3(-11.6, 1.6, -17.35), 2.0)
	_note("note_network", "UPLINK / RESTORE", "ROUTE ALLOCATION\n\n6  >  1  >  4\n\nVERIFY ALL THREE LINKS\nBEFORE COMMIT", Vector3(-18.9, 1.7, -17.76))
	# Wall conduits and numbered aisle markings frame long sightlines.
	for y in [0.9, 1.05, 1.2]:
		_pipe(Vector3(-21.7, y, -1), Vector3(-21.7, y, -17), 0.045)
	_light(Vector3(-16.3, 0.8, -16), CYAN, 0.7, 5.0, "server")

func _rack(pos: Vector3, yaw: float, number: int) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_box(pos + Vector3(0, 1.48, 0), Vector3(1.1, 2.96, 1.4), "rack", true, yaw)
	for side in [-1.0, 1.0]:
		_box(pos + basis * Vector3(side * 0.51, 1.5, 0.735), Vector3(0.07, 2.85, 0.06), "steel_light", false, yaw)
	for unit in range(12):
		var y := 0.3 + unit * 0.205
		_box(pos + basis * Vector3(0, y, 0.73), Vector3(0.91, 0.176, 0.07), "lower", false, yaw)
		_box(pos + basis * Vector3(-0.11, y, 0.775), Vector3(0.46, 0.11, 0.027), "black", false, yaw)
		for vent in range(5):
			_box(pos + basis * Vector3(-0.3 + vent * 0.083, y, 0.797), Vector3(0.023, 0.074, 0.01), "steel", false, yaw)
		for led in range(3):
			var led_key := "cyan" if (unit + number + led) % 7 != 0 else "amber"
			_box(pos + basis * Vector3(0.25 + led * 0.058, y, 0.795), Vector3(0.023, 0.025, 0.025), led_key, false, yaw)
		_box(pos + basis * Vector3(-0.4, y, 0.785), Vector3(0.035, 0.09, 0.035), "steel_light", false, yaw)
	_label("MS / " + str(number).pad_zeros(2), pos + basis * Vector3(0, 2.84, 0.8), 30, COLD, yaw, 0.003)
	_box(pos + Vector3(0, 3.0, 0), Vector3(1.12, 0.08, 1.45), "steel_light", false, yaw)
	for x in [-0.34, 0.28]:
		_box(pos + basis * Vector3(x, 3.23, -0.2), Vector3(0.075, 0.4, 0.075), "rubber", false, yaw)

func _security() -> void:
	_fixture(Vector3(-3.4, 3.88, -12.5), 2.2, 0, Color("8eb0af"), "security", 1.3)
	_light(Vector3(-3.4, 2.2, -16.4), CYAN, 1.5, 6.0, "security")
	_sign("D / SURVEILLANCE", Vector3(-3.6, 3.03, -17.77), 5.0)
	# Video wall has individually framed CRT-like monitor housings.
	for row in range(2):
		for col in range(3):
			var p := Vector3(-5.4 + col * 1.72, 2.02 + row * 0.97, -17.35)
			var screen := _monitor(p, "CAM 06-" + str(1 + row * 3 + col).pad_zeros(2) + "\nSIGNAL LOST", 1.57)
			if row == 1 and col == 1:
				anomaly_nodes["cctv_screen"] = screen
	_terminal("cctv", "CCTV / SECTOR 06", "SELECT LIVE FEED\nARCHIVE BUFFER / 02:14:06", Vector3(-2, 1.22, -16.3), 1.75)
	for x in [-5.6, -3.8]:
		_desk(Vector3(x, 0, -16), 0)
		_chair(Vector3(x, 0, -14.8), 0.15)
	_note("note_security", "INTERNAL / SECURITY", "CORE ACCESS\n\n6  1  4\n\nTWO PERSON RULE\nDO NOT ENTER ALONE", Vector3(-7.74, 1.8, -12.3), PI * 0.5)
	_box(Vector3(2.6, 0.88, -15.7), Vector3(1.6, 0.18, 1.5), "steel_light", true)
	for x in [2.0, 3.2]:
		_box(Vector3(x, 0.42, -15.7), Vector3(0.1, 0.85, 1.2), "steel")
	var badge := Node3D.new()
	badge.name = "SecurityBadge"
	add_child(badge)
	_dynamic_box(badge, Vector3(2.5, 1.0, -15.4), Vector3(0.23, 0.035, 0.35), "paper")
	_dynamic_box(badge, Vector3(2.5, 1.023, -15.4), Vector3(0.17, 0.013, 0.14), "cyan")
	_collectibles["badge"] = badge
	_interaction("badge", "SECURITY ACCESS BADGE", Vector3(2.5, 1.14, -15.4), Vector3(0.85, 0.5, 0.8))
	_label("ACCESS CREDENTIALS", Vector3(3.74, 2.0, -15.5), 36, COLD, -PI * 0.5, 0.003)
	for z in [-10, -11.2]:
		_box(Vector3(-7.3, 1.35, z), Vector3(0.9, 2.7, 1.0), "lower", true)
		_label("PERSONAL\nEFFECTS", Vector3(-6.79, 2.0, z), 23, COLD, PI * 0.5, 0.003)
		_box(Vector3(-6.8, 1.2, z + 0.28), Vector3(0.05, 0.15, 0.06), "steel_light")

func _core() -> void:
	# The approach compresses the player before an unexpectedly tall machine hall.
	_fixture(Vector3(0, 4.48, -24), 2.0, 0, AMBER, "airlock", 1.8)
	_fixture(Vector3(0, 4.48, -28), 2.0, 0, COLD, "airlock", 1.6)
	_terminal("core_access", "CORE / ACCESS CONTROL", "SECURITY CREDENTIAL REQUIRED\nISOLATION SEAL / LOCKED", Vector3(1.6, 1.6, -28.8), 1.65)
	_sign("E / LEVEL 6", Vector3(0, 4.0, -29.03), 4.4, 0, AMBER)
	_label("NO OCCUPANCY SENSORS BEYOND THIS POINT", Vector3(0, 3.31, -29.02), 29, COLD, 0, 0.003)
	_hazard_line(Vector3(0, 0.02, -29.6), 5.6)
	# Heavy vertical ribs and service balconies, all beyond the walkable foreground.
	for z in [-32.0, -38.0, -44.0, -49.0]:
		for x in [-11.55, 11.55]:
			_box(Vector3(x, 7.0, z), Vector3(0.75, 14, 0.65), "steel", true)
			_box(Vector3(x * 0.972, 7.0, z + 0.36), Vector3(0.11, 13.5, 0.04), "steel_light")
		_box(Vector3(0, 13.6, z), Vector3(23, 0.6, 0.75), "steel")
	for x in [-9.7, 9.7]:
		_box(Vector3(x, 6.1, -40), Vector3(3.0, 0.22, 19), "steel", true)
		for z in range(-49, -30, 2):
			_box(Vector3(x * 0.84, 6.7, z), Vector3(0.07, 1.2, 0.07), "steel_light")
		_box(Vector3(x * 0.84, 7.3, -40), Vector3(0.08, 0.07, 19), "steel_light")
		_box(Vector3(x * 0.84, 6.75, -40), Vector3(0.055, 0.04, 19), "steel_light")
		for z in [-34, -41, -48]:
			_fixture(Vector3(x, 11.7, z), 2.6, PI * 0.5, COLD, "core", 3.2)
			_light(Vector3(x * 0.75, 2.4, z), Color("4f918b"), 2.2, 11.0, "core")
	# Central encapsulated apparatus: dense finned stacked turbine, luminous seam.
	_cylinder(Vector3(0, 0.23, -43), 4.6, 0.46, "steel", Vector3.ZERO, 4.4)
	_collider(Vector3(0, 3.0, -43), Vector3(6.6, 6, 6.6))
	_cylinder(Vector3(0, 6.7, -43), 2.45, 12.5, "black")
	for y in [0.6, 1.2, 3.0, 4.8, 6.6, 8.4, 10.2, 12.0]:
		_cylinder(Vector3(0, y, -43), 3.1, 0.27, "steel_light")
		_ring(Vector3(0, y + 0.19, -43), 2.49, 2.57, "cyan")
	for i in range(16):
		var angle := float(i) * TAU / 16.0
		var p := Vector3(sin(angle) * 2.83, 6.65, -43 + cos(angle) * 2.83)
		_box(p, Vector3(0.28, 11.8, 0.38), "lower", false, angle)
		_box(p + Vector3(sin(angle) * 0.23, 0, cos(angle) * 0.23), Vector3(0.035, 10.9, 0.08), "cyan", false, angle)
	for x in [-5.5, 5.5]:
		for z in [-39.5, -46.5]:
			_cylinder(Vector3(x, 4.2, z), 0.54, 8.4, "steel_light")
			_cylinder(Vector3(x, 1.1, z), 0.72, 0.28, "steel")
			_cylinder(Vector3(x, 7.2, z), 0.72, 0.28, "steel")
			_pipe(Vector3(x, 8.2, z), Vector3(x * 0.35, 10.5, -43), 0.25, "lower")
			_collider(Vector3(x, 4, z), Vector3(1.1, 8, 1.1))
	_light(Vector3(0, 8.5, -37.5), CYAN, 3.7, 15.0, "core")
	_light(Vector3(0, 3.5, -47), CYAN, 3.0, 13.0, "core")
	_terminal("core", "ISOLATION / CENTRAL PROCESS", "THREE SUBSYSTEMS SYNCHRONIZED\nAWAITING OPERATOR AUTHORIZATION", Vector3(0, 1.45, -37), 2.4)
	_label("BELOW LEVEL 6", Vector3(0, 11.8, -49.73), 160, COLD, 0, 0.013)
	_label("MERIDIAN / EXPERIMENTAL COMPUTE DIVISION", Vector3(0, 10.4, -49.72), 43, COLD, 0, 0.007)
	for x in [-4.2, 4.2]:
		_box(Vector3(x, 0.016, -36), Vector3(0.1, 0.018, 10), "orange")
		for z in [-31.5, -34, -36.5]:
			_box(Vector3(x, 0.025, z), Vector3(0.33, 0.025, 0.6), "cyan")
	# Alarm hardware is silent and dim until final failure.
	for x in [-10.7, 10.7]:
		_light(Vector3(x, 2.9, -32), RED, 3.0, 15.0, "alarm")
		_box(Vector3(x, 3.3, -30.3), Vector3(0.45, 0.3, 0.3), "alarm")

func _service_corridor() -> void:
	# A noncritical survey spur can gain physical length only while unobserved.
	_floor(-32, 8, 24, 3.2, "concrete", 3.3)
	_wall_z(6.4, -44, -20, 3.3)
	_wall_z(9.6, -44, -20, 3.3)
	_wall_x(-44, 6.4, 9.6, 3.3)
	for x in [-24, -28, -32, -36, -40, -43]:
		_fixture(Vector3(x, 3.07, 8), 1.8, PI * 0.5, COLD, "survey", 1.0)
		_box(Vector3(x, 1.65, 6.6), Vector3(0.18, 3.3, 0.18), "steel")
		_box(Vector3(x, 1.65, 9.4), Vector3(0.18, 3.3, 0.18), "steel")
		_box(Vector3(x, 3.05, 8), Vector3(0.18, 0.28, 3.0), "steel")
	_pipe(Vector3(-43, 2.55, 6.72), Vector3(-20.5, 2.55, 6.72), 0.075)
	var end := Node3D.new()
	add_child(end)
	end.position = Vector3(-28, 0, 8)
	_dynamic_box(end, Vector3(0, 1.6, 0), Vector3(0.22, 3.2, 3.15), "steel")
	_dynamic_box(end, Vector3(0.13, 1.45, 0), Vector3(0.05, 2.5, 1.7), "lower")
	_collider(Vector3(0, 1.6, 0), Vector3(0.26, 3.2, 3.2), 0, end)
	_label("SURVEY 06\nEND OF ACCESS", Vector3(0.17, 2.0, 0), 40, COLD, PI * 0.5, 0.004, end)
	_dynamic_box(end, Vector3(0.62, 0.82, 0), Vector3(0.9, 0.15, 1.35), "steel_light")
	_dynamic_box(end, Vector3(0.42, 0.42, 0), Vector3(0.42, 0.84, 1.1), "lower")
	_collider(Vector3(0.56, 0.46, 0), Vector3(1.0, 0.92, 1.4), 0, end)
	var module := Node3D.new()
	module.name = "OfflineModule"
	end.add_child(module)
	_dynamic_box(module, Vector3(0.65, 1.01, 0), Vector3(0.4, 0.23, 0.68), "orange")
	_dynamic_box(module, Vector3(0.87, 1.01, 0), Vector3(0.035, 0.12, 0.46), "black")
	for z in [-0.14, 0.0, 0.14]:
		_dynamic_box(module, Vector3(0.90, 1.02, z), Vector3(0.022, 0.05, 0.045), "cyan")
	_collectibles["module"] = module
	_label("BRIDGE 06\nOFFLINE COLD STORAGE", Vector3(0.20, 1.44, 0), 26, AMBER, PI * 0.5, 0.003, end)
	_interaction("module", "BRIDGE 06 / OFFLINE MODULE", Vector3(0.76, 1.08, 0), Vector3(0.65, 0.55, 0.85), 0, end)
	anomaly_nodes["corridor_end"] = end
	_sign("SURVEY / 8 METERS", Vector3(-20.25, 2.8, 8), 2.5, PI * 0.5)

func extend_corridor(variant: int, player_position: Vector3 = Vector3.INF) -> bool:
	if player_position != Vector3.INF and player_position.x < -20.0 and player_position.z > 5.5 and player_position.z < 10.5:
		return false
	_corridor_variant = clampi(variant, 0, 2)
	anomaly_nodes.corridor_end.position.x = -28.0 - float(_corridor_variant) * 7.7
	_update_module_approach()
	return true

func _update_module_approach() -> void:
	var end_x: float = anomaly_nodes.corridor_end.position.x
	var approach := Vector3(end_x + 2.45, 0.1, 8)
	markers["module"] = approach
	interaction_approaches["module"] = {"position": approach, "target": Vector3(end_x + 0.76, 1.08, 8)}
	if traversal_nodes.size() > 36:
		traversal_nodes[36] = approach

func _desk(pos: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	_box(pos + Vector3(0, 0.8, 0), Vector3(1.6, 0.13, 0.88), "steel_light", true, yaw)
	for x in [-0.65, 0.65]:
		_box(pos + basis * Vector3(x, 0.38, 0), Vector3(0.075, 0.76, 0.7), "steel", true, yaw)
	_box(pos + basis * Vector3(0.4, 0.4, -0.1), Vector3(0.45, 0.6, 0.6), "lower", true, yaw)
	_box(pos + basis * Vector3(-0.2, 0.89, 0.13), Vector3(0.65, 0.05, 0.25), "black", false, yaw)

func _monitor(pos: Vector3, caption: String, width: float = 1.25) -> MeshInstance3D:
	_box(pos, Vector3(width, width * 0.58, 0.2), "rack")
	var screen := _dynamic_box(self, pos + Vector3(0, 0.02, 0.115), Vector3(width - 0.12, width * 0.48, 0.02), "screen_dead")
	_screens.append(screen)
	var caption_node := _label(caption, pos + Vector3(0, 0, 0.14), 22, CYAN, 0, 0.0026)
	screen.set_meta("caption_node", caption_node)
	screen.set_meta("default_caption", caption)
	_box(pos + Vector3(0, -width * 0.37, -0.015), Vector3(0.10, width * 0.23, 0.12), "steel_light")
	_box(pos + Vector3(0, -width * 0.48, 0), Vector3(width * 0.4, 0.045, 0.3), "steel")
	_box(pos + Vector3(width * 0.38, -width * 0.22, 0.13), Vector3(0.025, 0.025, 0.02), "cyan")
	return screen

func _chair(pos: Vector3, yaw: float) -> Node3D:
	var chair := Node3D.new()
	add_child(chair)
	chair.position = pos
	chair.rotation.y = yaw
	_dynamic_box(chair, Vector3(0, 0.47, 0), Vector3(0.57, 0.13, 0.55), "rubber")
	_dynamic_box(chair, Vector3(0, 0.92, 0.24), Vector3(0.57, 0.66, 0.13), "lower")
	_cylinder(Vector3(0, 0.25, 0), 0.055, 0.38, "steel_light", Vector3.ZERO, -1.0, chair)
	for i in range(5):
		var angle := float(i) * TAU / 5.0
		var leg := _dynamic_box(chair, Vector3(cos(angle) * 0.18, 0.1, sin(angle) * 0.18), Vector3(0.4, 0.045, 0.06), "steel_light")
		leg.rotation.y = -angle
		_cylinder(Vector3(cos(angle) * 0.35, 0.065, sin(angle) * 0.35), 0.065, 0.065, "rubber", Vector3(0, 0, PI * 0.5), -1.0, chair)
	for side in [-1.0, 1.0]:
		_dynamic_box(chair, Vector3(side * 0.34, 0.64, 0.03), Vector3(0.055, 0.27, 0.06), "steel_light")
		_dynamic_box(chair, Vector3(side * 0.34, 0.78, 0.02), Vector3(0.1, 0.065, 0.37), "rubber")
	return chair

func _extinguisher(pos: Vector3) -> void:
	_cylinder(pos, 0.14, 0.62, "red")
	_cylinder(pos + Vector3(0, 0.36, 0), 0.06, 0.12, "steel_light")
	_box(pos + Vector3(0, 0.45, 0), Vector3(0.28, 0.04, 0.10), "black")
	_box(pos + Vector3(0, 0, 0.15), Vector3(0.17, 0.23, 0.015), "paper")
	_pipe(pos + Vector3(0.1, 0.35, 0), pos + Vector3(0.2, -0.1, 0), 0.025, "rubber")

func _camera_prop(pos: Vector3, target: Vector3) -> void:
	var camera_model := Node3D.new()
	add_child(camera_model)
	camera_model.position = pos
	camera_model.basis = Basis.looking_at(target - pos, Vector3.UP)
	_dynamic_box(camera_model, Vector3.ZERO, Vector3(0.32, 0.26, 0.6), "paper")
	_dynamic_box(camera_model, Vector3(0, 0, -0.32), Vector3(0.28, 0.20, 0.04), "black")
	_dynamic_box(camera_model, Vector3(0.09, -0.07, -0.35), Vector3(0.025, 0.025, 0.02), "alarm")
	_dynamic_box(camera_model, Vector3(0, 0.25, 0.1), Vector3(0.07, 0.4, 0.07), "steel_light")

func set_stage(stage: int) -> void:
	var previous := _stage
	_stage = stage
	for light in lights:
		var category: String = light.get_meta("category", "normal")
		var base: float = light.get_meta("base_energy", 1.0)
		var factor := 1.0
		if category == "alarm":
			factor = 1.0 if stage >= 11 else 0.0
		elif stage >= 11:
			factor = 0.25 if category not in ["arrival", "power", "cooling"] else 0.75
			if category == "core":
				factor = 0.12
		elif stage < 3 and category in ["server", "rear", "core"]:
			factor = 0.25
		elif stage >= 7 and category in ["hub", "survey"]:
			factor = 0.57
		light.light_energy = 0.0 if light.get_meta("scare_disabled", false) else base * factor
	for screen in _screens:
		_update_monitor_status(screen, stage)
		if screen.get_meta("live_feed", false):
			continue
		screen.material_override = materials["screen"] if stage >= 7 and stage < 11 else materials["screen_dead"]
	if stage >= 10:
		set_door("core", true)
	if previous == 0 and stage >= 1 and not _elevator_busy:
		set_door("elevator", true)

func _update_monitor_status(screen: MeshInstance3D, stage: int) -> void:
	if not screen.has_meta("caption_node"):
		return
	var caption: Label3D = screen.get_meta("caption_node")
	var original: String = screen.get_meta("default_caption")
	var heading := original.get_slice("\n", 0) if original.begins_with("CAM") else "OPERATIONS BUS"
	if stage >= 11:
		caption.text = heading + "\nREMOTE LINK LOST\nLOCAL DISPLAY ONLY"
		caption.modulate = AMBER
	elif stage >= 7:
		caption.text = heading + ("\nCHANNEL AVAILABLE\nSELECT AT CONSOLE" if original.begins_with("CAM") else "\nTELEMETRY ONLINE\nWORK ORDER 0214-06")
		caption.modulate = CYAN
	elif stage >= 3:
		caption.text = heading + "\nPOWER ONLINE\nNETWORK OFFLINE"
		caption.modulate = COLD
	else:
		caption.text = original
		caption.modulate = CYAN
	caption.visible = not screen.get_meta("live_feed", false) or stage < 7 or stage >= 11

func bind_cctv_texture(texture: Texture2D) -> void:
	var screen: MeshInstance3D = anomaly_nodes["cctv_screen"]
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	screen.material_override = material
	# The live camera excludes this layer, avoiding render-texture feedback when
	# its security-room feed looks back at the physical video wall.
	screen.layers = 1 << 18
	screen.set_meta("live_feed", true)
	_update_monitor_status(screen, _stage)

func apply_quality(preset: int) -> void:
	var shadow_count := 0
	var limit: int = [0, 3, 8, 12][clampi(preset, 0, 3)]
	var used_categories: Dictionary = {}
	for light in lights:
		var category: String = light.get_meta("category", "normal")
		var eligible: bool = category in ["hub", "power", "cooling", "server", "core", "operations", "security", "arrival"]
		var category_count: int = used_categories.get(category, 0)
		light.shadow_enabled = eligible and category_count < (2 if preset == 3 else 1) and shadow_count < limit
		if light.shadow_enabled:
			shadow_count += 1
			used_categories[category] = category_count + 1
		light.distance_fade_begin = [16.0, 20.0, 24.0, 32.0][clampi(preset, 0, 3)]
		light.distance_fade_shadow = [0.0, 10.0, 16.0, 22.0][clampi(preset, 0, 3)]
	for probe in _reflection_probes:
		probe.visible = preset >= 2

func _make_reflections() -> void:
	for data in [
		[Vector3(0, 2, 4), Vector3(16, 4, 16)],
		[Vector3(-15, 2, -9), Vector3(14, 4, 18)],
		[Vector3(15, 2.8, -7), Vector3(14, 5.6, 14)],
		[Vector3(0, 6.8, -40), Vector3(24, 14, 20)],
	]:
		var probe := ReflectionProbe.new()
		probe.position = data[0]
		probe.size = data[1]
		probe.box_projection = true
		probe.interior = true
		probe.intensity = 0.45
		probe.max_distance = 30.0
		probe.update_mode = ReflectionProbe.UPDATE_ONCE
		add_child(probe)
		_reflection_probes.append(probe)

func reset_anomalies() -> void:
	for key in _anomaly_defaults:
		anomaly_nodes[key].transform = _anomaly_defaults[key]
		anomaly_nodes[key].visible = true
	anomaly_nodes.sign.text = "EXIT  /  SURFACE"
	anomaly_nodes.elevator_display.text = "B6"
	for light in lights:
		light.set_meta("scare_disabled", false)
	set_stage(_stage)
	extend_corridor(0)

func surface_at(pos: Vector3) -> String:
	if pos.z > 22.0 or pos.z < -18.0:
		return "metal"
	if pos.x > 8.0 and pos.z < 0.0:
		return "wet"
	if pos.x < -8.0 and pos.z < 0.0:
		return "grating"
	if (pos.x < -8.0 and pos.z > 4.0 and pos.x > -20.0) or (pos.z < -8.0 and pos.x > -8.0 and pos.x < 4.0):
		return "tile"
	return "concrete"

func _build_navigation() -> void:
	traversal_nodes = [
		Vector3(0, 0.1, 25), Vector3(0, 0.1, 17), Vector3(0, 0.1, 8),
		Vector3(0, 0.1, -2), Vector3(-15, 0.1, 8), Vector3(-16, 0.1, 7),
		Vector3(15, 0.1, 8), Vector3(15, 0.1, 7), Vector3(7, 0.1, 17),
		Vector3(-15, 0.1, -2), Vector3(-15, 0.1, -10), Vector3(-15, 0.1, -15),
		Vector3(-15, 0.1, -20), Vector3(0, 0.1, -20), Vector3(19, 0.1, -20),
		Vector3(19, 0.1, -16), Vector3(19, 0.1, -10), Vector3(19, 0.1, -2),
		Vector3(17, 0.1, -11), Vector3(0, 0.1, -6), Vector3(0, 0.1, -11),
		Vector3(0, 0.1, -14), Vector3(0, 0.1, -17), Vector3(-2, 0.1, -14),
		Vector3(0, 0.1, -26), Vector3(0, 0.1, -32), Vector3(0, 0.1, -34.5),
		Vector3(7, 0.1, -37), Vector3(-7, 0.1, -37), Vector3(8, 0.1, -43),
		Vector3(-8, 0.1, -43), Vector3(0, 0.1, -48), Vector3(-24, 0.1, 8),
		Vector3(8, 0.1, -48), Vector3(-8, 0.1, -48), Vector3(-11.6, 0.1, -15),
		Vector3(-25.55, 0.1, 8), Vector3(13, 0.1, -2.2), Vector3(19.4, 0.1, -15.5),
		Vector3(18, 0.1, 7), Vector3(18, 0.1, 2), Vector3(18, 0.1, -2),
	]
	traversal_links = [
		[0, 1], [1, 2], [1, 8], [2, 3], [2, 4], [4, 5], [2, 6], [6, 7],
		[3, 9], [9, 10], [10, 11], [11, 12], [12, 13], [13, 14], [14, 15],
		[15, 16], [16, 17], [17, 3], [16, 18], [3, 19], [19, 20], [20, 21],
		[21, 22], [22, 13], [21, 23], [20, 23], [13, 24], [24, 25], [25, 26],
		[26, 27], [26, 28], [27, 29], [28, 30], [29, 33], [30, 34], [33, 31], [34, 31], [4, 32], [11, 35],
		[32, 36], [3, 37], [17, 37], [15, 38], [16, 38],
		[7, 39], [39, 40], [40, 41], [41, 17],
	]
	route = [Vector3(0, 0.1, -34.5), Vector3(0, 0.1, -26), Vector3(0, 0.1, -20), Vector3(-15, 0.1, -20), Vector3(-15, 0.1, -2), Vector3(0, 0.1, -2), Vector3(0, 0.1, 8), Vector3(0, 0.1, 17), Vector3(0, 0.1, 25)]

func _build_approaches() -> void:
	for key in ["operations", "power", "cooling", "network", "cctv", "core", "exit", "core_access"]:
		interaction_approaches[key] = {"position": markers[key], "target": interactables[key].position}
	for key in ["elevator_open", "elevator_close"]:
		interaction_approaches[key] = {"position": markers.exit, "target": interactables[key].position}
	interaction_approaches["elevator_call"] = {"position": Vector3(2.1, 0.1, 19.5), "target": interactables.elevator_call.position}
	interaction_approaches["fuse"] = {"position": Vector3(8.2, 0.1, 17.0), "target": interactables.fuse.position}
	interaction_approaches["badge"] = {"position": Vector3(2.5, 0.1, -13.5), "target": interactables.badge.position}
	interaction_approaches["note_power"] = {"position": Vector3(12.0, 0.1, 6.1), "target": interactables.note_power.position}
	interaction_approaches["note_cooling"] = {"position": Vector3(14.5, 0.1, -11.4), "target": interactables.note_cooling.position}
	interaction_approaches["note_network"] = {"position": Vector3(-18.9, 0.1, -15.2), "target": interactables.note_network.position}
	interaction_approaches["note_security"] = {"position": Vector3(-5.5, 0.1, -12.3), "target": interactables.note_security.position}
	markers["pump_a"] = Vector3(13, 0.1, -2.2)
	markers["pump_b"] = Vector3(19.4, 0.1, -15.5)
	interaction_approaches["pump_a"] = {"position": markers.pump_a, "target": interactables.pump_a.position}
	interaction_approaches["pump_b"] = {"position": markers.pump_b, "target": interactables.pump_b.position}
	_update_module_approach()

func find_path(from: Vector3, to: Vector3) -> Array[Vector3]:
	var graph := AStar3D.new()
	for i in range(traversal_nodes.size()):
		graph.add_point(i, traversal_nodes[i])
	for link in traversal_links:
		graph.connect_points(link[0], link[1])
	var start := _nearest_visible_node(from)
	var finish := _nearest_visible_node(to)
	var points: Array[Vector3] = []
	if start < 0 or finish < 0:
		points.append(to)
		return points
	for point in graph.get_point_path(start, finish):
		points.append(point)
	points.append(Vector3(to.x, 0.1, to.z))
	return points

func _nearest_visible_node(point: Vector3) -> int:
	var best := -1
	var best_distance := INF
	var space := get_world_3d().direct_space_state
	for i in range(traversal_nodes.size()):
		var distance := point.distance_to(traversal_nodes[i])
		if distance >= best_distance:
			continue
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 0.9, point.z), traversal_nodes[i] + Vector3(0, 0.8, 0), 1)
		if space.intersect_ray(query).is_empty():
			best = i
			best_distance = distance
	return best

func _physics_process(delta: float) -> void:
	_door_guard_clock -= delta
	if _door_guard_clock <= 0.0:
		_door_guard_clock = 0.08
		for id in _doors:
			if _doors[id].moving and not _doors[id].open and _door_obstructed(id):
				set_door(id, true)
	if not _elevator_moving:
		return
	_elevator_elapsed = minf(_elevator_elapsed + delta, _elevator_duration)
	var progress := _elevator_elapsed / _elevator_duration
	var eased := progress * progress * (3.0 - 2.0 * progress)
	var next_height := lerpf(_elevator_from, _elevator_target, eased)
	var displacement := next_height - elevator_cabin.position.y
	elevator_cabin.position.y = next_height
	if is_instance_valid(_elevator_passenger):
		_elevator_passenger.global_position.y += displacement
		_elevator_passenger.velocity = Vector3.ZERO
	var floor_number := clampi(6 - roundi(next_height / 5.0), 0, 6)
	if floor_number != _elevator_display_floor:
		_elevator_display_floor = floor_number
		var direction := "^ " if _elevator_target > _elevator_from else "v "
		set_elevator_status(direction + ("G" if floor_number == 0 else "B" + str(floor_number)))
	if progress >= 1.0:
		_elevator_moving = false
		_elevator_busy = false
		var surface := _elevator_target > 0.0
		set_elevator_status("G" if surface else "B6")
		_release_passenger()
		mechanism_cue.emit("chime", elevator_cabin.global_position + Vector3(0, 1, 25))
		elevator_arrived.emit(surface)

func _process(delta: float) -> void:
	_clock += delta
	if _stage >= 5:
		for fan in _fans:
			fan.rotate_object_local(Vector3.UP, delta * 1.6)
