extends Node
class_name ScareDirector

var tension: float = 0.05
var elapsed: float = 0.0
var cooldown: float = 0.0
var events: Dictionary = {}
var game: Node
var chair_moves: int = 0

func _process(delta: float) -> void:
	if game == null or not game.playing or game.modal or game.stage < 3:
		return
	elapsed += delta
	cooldown = maxf(0.0, cooldown - delta)
	var shutter = game.level.anomaly_nodes.get("door")
	if is_instance_valid(shutter) and game.stage >= 3 and not events.has("shutter_closed"):
		if game.player.global_position.distance_to(shutter.global_position) < 12.0 and not game.player.is_observing(shutter.global_position + Vector3.UP, 1.4):
			shutter.rotation.y = move_toward(shutter.rotation.y, 0.0, delta * 0.16)
			if absf(shutter.rotation.y) < 0.02:
				claim("shutter_closed", 15.0)
	if cooldown > 0.0:
		return
	var corridor = game.level.anomaly_nodes.get("corridor_end")
	if is_instance_valid(corridor) and game.level.has_method("extend_corridor"):
		var wanted = 2 if game.stage >= 7 else (1 if game.stage >= 5 else 0)
		if wanted > 0 and not events.has("corridor_" + str(wanted)):
			# Require the player outside the complete survey-wing sightline and behind its mouth.
			if game.player.global_position.x > -19.0 and not game.player.is_observing(corridor.global_position + Vector3.UP, 2.0):
				game.level.extend_corridor(wanted, game.player.global_position)
				claim("corridor_" + str(wanted), 20.0)
	if game.stage >= 7 and not events.has("light_chase") and game.player.global_position.z > 13 and game.player.global_position.z < 20:
		if claim("light_chase", 30):
			_light_chase()
	var chair = game.level.anomaly_nodes.get("chair")
	if is_instance_valid(chair) and game.stage >= 5 and chair_moves < 3 and game.player.global_position.distance_to(chair.global_position) < 13.0:
		if not game.player.is_observing(chair.global_position + Vector3.UP * 0.5, 0.8):
			var id = "chair_" + str(chair_moves)
			if claim(id, 24.0):
				chair.position.x += 0.45 if chair_moves == 0 else 0.8
				if chair_moves == 2:
					chair.visible = false
					game.sound.play_cue("drag", game.player.global_position + Vector3(7, 0, 7))
				chair_moves += 1
	if game.stage >= 7 and not events.has("sign_changed"):
		var sign_node = game.level.anomaly_nodes.get("sign")
		if is_instance_valid(sign_node) and not game.player.is_observing(sign_node.global_position, 1.0):
			if claim("sign_changed", 18.0) and sign_node is Label3D:
				sign_node.text = "NO EXIT   /   B6"

func claim(id: String, delay: float = 12.0) -> bool:
	if events.has(id):
		return false
	events[id] = true
	cooldown = delay
	return true

func restore(saved: Dictionary) -> void:
	events = saved.duplicate(true)
	chair_moves = int(events.has("chair_0")) + int(events.has("chair_1")) + int(events.has("chair_2"))
	cooldown = 15.0

func _light_chase() -> void:
	var chase_lights: Array = []
	for lamp in game.level.lights:
		if absf(lamp.position.x) < 3 and lamp.position.z > 3 and lamp.position.z < 22:
			chase_lights.append(lamp)
	chase_lights.sort_custom(func(a, b): return a.position.z < b.position.z)
	var token = game.session_token
	for lamp in chase_lights:
		await get_tree().create_timer(1.4, false).timeout
		if not is_instance_valid(game) or token != game.session_token or not game.playing: return
		lamp.light_energy = 0.0
		game.sound.play_cue("click", lamp.global_position)
	# No strobe or loud follow-up; the next fixture remains a safe visual destination.
