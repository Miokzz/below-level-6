extends Node
class_name ScareDirector
## Observation-gated changes with checkpointable, pause-safe timing.

var tension: float = 0.05
var elapsed: float = 0.0
var cooldown: float = 0.0
var events: Dictionary = {}
var game: Node
var chair_moves: int = 0

var _light_clock: float = 0.0
var _light_active: bool = false
var _chase_lights: Array[Light3D] = []

func setup(game_ref: Node) -> void:
	game = game_ref
	_collect_chase_lights()

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not game.playing or game.modal or game.stage < 3:
		return
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	_update_light_chase(delta)
	var shutter = game.level.anomaly_nodes.get("door")
	if is_instance_valid(shutter) and not events.has("shutter_closed"):
		if game.player.global_position.distance_to(shutter.global_position) < 12.0 and not game.player.is_observing(shutter.global_position + Vector3.UP, 1.4):
			shutter.rotation.y = move_toward(shutter.rotation.y, 0.0, delta * 0.16)
			if absf(shutter.rotation.y) < 0.02:
				claim("shutter_closed", 15.0)
	if cooldown > 0.0:
		return
	var corridor = game.level.anomaly_nodes.get("corridor_end")
	if is_instance_valid(corridor) and game.level.has_method("extend_corridor"):
		var wanted: int = 2 if game.stage >= 7 else (1 if game.stage >= 5 else 0)
		if wanted > 0 and not events.has("corridor_" + str(wanted)):
			if game.player.global_position.x > -19.0 and not game.player.is_observing(corridor.global_position + Vector3.UP, 2.0):
				if game.level.extend_corridor(wanted, game.player.global_position):
					claim("corridor_" + str(wanted), 20.0)
					return
	if game.stage >= 7 and not events.has("light_chase_started") and game.player.global_position.z > 13 and game.player.global_position.z < 20:
		if claim("light_chase_started", 30.0):
			_collect_chase_lights()
			_light_active = true
			_light_clock = 0.0
			return
	var chair = game.level.anomaly_nodes.get("chair")
	if is_instance_valid(chair) and game.stage >= 5 and chair_moves < 3 and game.player.global_position.distance_to(chair.global_position) < 13.0:
		if not game.player.is_observing(chair.global_position + Vector3.UP * 0.5, 0.8):
			var id: String = "chair_" + str(chair_moves)
			if claim(id, 24.0):
				chair.position.x += 0.45 if chair_moves == 0 else 0.8
				if chair_moves == 2:
					chair.visible = false
					game.sound.play_cue("drag", game.player.global_position + Vector3(7, 0, 7))
				chair_moves += 1
				return
	if game.stage >= 7 and not events.has("sign_changed"):
		var sign_node = game.level.anomaly_nodes.get("sign")
		if sign_node is Label3D and not game.player.is_observing(sign_node.global_position, 1.0):
			if claim("sign_changed", 18.0):
				sign_node.text = "NO EXIT   /   B6"

func claim(id: String, delay: float = 12.0) -> bool:
	if events.has(id):
		return false
	events[id] = true
	cooldown = delay
	return true

func restore(saved: Dictionary) -> void:
	stop()
	events = saved.duplicate(true)
	chair_moves = int(events.has("chair_0")) + int(events.has("chair_1")) + int(events.has("chair_2"))
	cooldown = 15.0
	elapsed = 0.0
	if not is_instance_valid(game) or not is_instance_valid(game.level):
		return
	game.level.reset_anomalies()
	var nodes: Dictionary = game.level.anomaly_nodes
	var shutter = nodes.get("door")
	if is_instance_valid(shutter) and events.has("shutter_closed"):
		shutter.rotation.y = 0.0
	var chair = nodes.get("chair")
	if is_instance_valid(chair):
		chair.position.x += 0.45 + maxf(chair_moves - 1, 0) * 0.8 if chair_moves > 0 else 0.0
		chair.visible = chair_moves < 3
	var sign_node = nodes.get("sign")
	if sign_node is Label3D and events.has("sign_changed"):
		sign_node.text = "NO EXIT   /   B6"
	if game.level.has_method("extend_corridor"):
		game.level.extend_corridor(2 if events.has("corridor_2") else (1 if events.has("corridor_1") else 0))
	_collect_chase_lights()
	# Old checkpoints only have the completion flag; preserve their final state.
	if events.has("light_chase"):
		events["light_chase_started"] = true
		for index in range(_chase_lights.size()):
			events["light_chase_" + str(index)] = true
	var completed := _completed_light_count()
	for index in range(completed):
		_extinguish(_chase_lights[index], false)
	_light_active = events.has("light_chase_started") and not events.has("light_chase")

func stop() -> void:
	_light_active = false
	_light_clock = 0.0

func _collect_chase_lights() -> void:
	_chase_lights.clear()
	if not is_instance_valid(game) or not is_instance_valid(game.level):
		return
	for lamp in game.level.lights:
		if is_instance_valid(lamp) and absf(lamp.position.x) < 3 and lamp.position.z > 3 and lamp.position.z < 22:
			_chase_lights.append(lamp)
	_chase_lights.sort_custom(func(a: Light3D, b: Light3D) -> bool: return a.position.z < b.position.z)

func _update_light_chase(delta: float) -> void:
	if not _light_active:
		return
	_light_clock += delta
	if _light_clock < 1.4:
		return
	_light_clock = 0.0
	var index := _completed_light_count()
	if index < _chase_lights.size():
		_extinguish(_chase_lights[index], true)
		events["light_chase_" + str(index)] = true
	if _completed_light_count() >= _chase_lights.size():
		events["light_chase"] = true
		_light_active = false

func _completed_light_count() -> int:
	var count := 0
	while count < _chase_lights.size() and events.has("light_chase_" + str(count)):
		count += 1
	return count

func _extinguish(lamp: Light3D, audible: bool) -> void:
	if not is_instance_valid(lamp):
		return
	lamp.set_meta("scare_disabled", true)
	lamp.light_energy = 0.0
	if audible:
		game.sound.play_cue("click", lamp.global_position)
