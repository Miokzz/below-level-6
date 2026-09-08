extends RefCounted
class_name Checkpoints
## Validated, atomic checkpoint records; settings have a separate ConfigFile.

const VERSION := 1
var path := "user://checkpoint.json"
var last_error := ""

func save_checkpoint(data: Dictionary) -> bool:
	last_error = ""
	if not _valid(data):
		last_error = "Checkpoint data is inconsistent."
		return false
	var payload := JSON.stringify(data)
	var envelope := JSON.stringify({"version": VERSION, "payload": payload, "checksum": payload.sha256_text()})
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		last_error = "Cannot write checkpoint (%s)." % error_string(FileAccess.get_open_error())
		return false
	file.store_string(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		last_error = "Checkpoint write failed."
		return false
	# Keep the previous validated record even when the current file is damaged.
	if not _read(path).is_empty():
		DirAccess.copy_absolute(path, path + ".backup")
	var result := DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		last_error = "Cannot replace checkpoint (%s)." % error_string(result)
	return result == OK

func load_checkpoint() -> Dictionary:
	last_error = ""
	var data := _read(path)
	if not data.is_empty(): return data
	data = _read(path + ".backup")
	if not data.is_empty():
		last_error = "Recovered the previous checkpoint."
	elif FileAccess.file_exists(path):
		last_error = "Checkpoint is damaged or incompatible. Start a new shift."
	return data

func can_continue() -> bool:
	var data := load_checkpoint()
	return not data.is_empty() and int(data.stage) < 14

func _read(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path): return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null or file.get_length() > 262144: return {}
	var decoder := JSON.new()
	if decoder.parse(file.get_as_text()) != OK: return {}
	var envelope: Variant = decoder.data
	if not envelope is Dictionary or envelope.get("version") != VERSION: return {}
	var payload: Variant = envelope.get("payload")
	if not payload is String or payload.sha256_text() != envelope.get("checksum"): return {}
	if decoder.parse(payload) != OK: return {}
	var parsed: Variant = decoder.data
	return parsed if parsed is Dictionary and _valid(parsed) else {}

func _valid(data: Dictionary) -> bool:
	var stage_value: Variant = data.get("stage")
	if not (stage_value is int or stage_value is float): return false
	var stage := int(stage_value)
	if stage_value != stage or stage < 1 or (stage > 10 and stage != 14): return false
	var repairs: Variant = data.get("repairs")
	if not repairs is Dictionary: return false
	for key in ["isolated", "carrier_fitted", "power_solved", "cooling_solved", "module_fitted", "network_solved", "brake_released", "line_purged"]:
		if not repairs.get(key) is bool: return false
	var items: Variant = repairs.get("inventory")
	if not items is Dictionary: return false
	for key in items:
		if key not in ["fuse", "module", "badge"] or items[key] != true: return false
	if not _numbers(repairs.get("valves"), 3, 0, 5, false): return false
	if repairs.valves.size() != 3: return false
	if not _numbers(repairs.get("power_steps"), 3, 1, 3, true): return false
	if not _sequence(repairs.power_steps, [2, 1, 3], repairs.power_solved): return false
	if not repairs.power_solved and repairs.power_steps.size() >= 3: return false
	if not _numbers(repairs.get("links"), 3, 1, 6, true): return false
	var pumps: Variant = repairs.get("pumps")
	if not pumps is Dictionary or not pumps.get("pump_a") is bool or not pumps.get("pump_b") is bool: return false
	if repairs.carrier_fitted and (not items.has("fuse") or not repairs.isolated): return false
	if repairs.power_solved and not repairs.carrier_fitted: return false
	if repairs.cooling_solved and (not repairs.power_solved or not pumps.pump_a or not pumps.pump_b or not _sequence(repairs.valves, [2, 4, 3], true)): return false
	if repairs.module_fitted and (not items.has("module") or not repairs.cooling_solved): return false
	if repairs.network_solved and (not repairs.module_fitted or not _sequence(repairs.links, [6, 1, 4], true)): return false
	if (stage >= 3) != repairs.power_solved: return false
	if (stage >= 5) != repairs.cooling_solved: return false
	if (stage >= 7) != repairs.network_solved: return false
	if stage >= 10 and not items.has("badge"): return false
	for key in ["events", "observer_events", "radio_events"]:
		var flags: Variant = data.get(key, {})
		if not flags is Dictionary: return false
		for flag in flags:
			if not flag is String or not flags[flag] is bool: return false
	return data.get("checkpoint", "hub") in ["hub", "core_access"]

func _sequence(values: Array, expected: Array, complete: bool) -> bool:
	if complete and values.size() != expected.size(): return false
	if values.size() > expected.size(): return false
	for index in range(values.size()):
		# JSON stores numbers as floats; numeric sequence identity must survive disk.
		if int(values[index]) != int(expected[index]): return false
	return true

func _numbers(value: Variant, length_limit: int, minimum: int, maximum: int, unique: bool) -> bool:
	if not value is Array or value.size() > length_limit: return false
	var found: Array = []
	for number in value:
		if not (number is int or number is float): return false
		if number != int(number) or number < minimum or number > maximum: return false
		if unique and found.has(number): return false
		found.append(number)
	return true
