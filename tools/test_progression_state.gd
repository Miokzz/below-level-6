extends SceneTree
## Production puzzle operations and checkpoint files, isolated from player saves.
## Godot --headless --path . --script tools/test_progression_state.gd

const RepairsScript = preload("res://puzzles/repair_state.gd")
const CheckpointScript = preload("res://systems/checkpoints.gd")

var failures: Array[String] = []
var checkpoints: RefCounted
var repairs: RefCounted

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		failures.append(description)
		push_error("FAIL " + description)

func _record(stage: int) -> Dictionary:
	return {"stage": stage, "repairs": repairs.snapshot(), "events": {"light_chase_0": true}, "observer_events": {}, "radio_events": {}, "checkpoint": "core_access" if stage >= 10 else "hub"}

func _run() -> void:
	repairs = RepairsScript.new()
	checkpoints = CheckpointScript.new()
	var directory := "user://verification_state_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	checkpoints.path = directory + "/checkpoint.json"
	_check(checkpoints.load_checkpoint().is_empty() and not checkpoints.can_continue(), "A fresh profile offers no nonexistent Continue checkpoint")
	_check(checkpoints.save_checkpoint(_record(1)), "Arrival checkpoint can be written independently of settings")
	repairs.operate("fit_fuse")
	_check(not repairs.carrier_fitted, "Live electrical bus rejects unsafe carrier installation")
	_check(repairs.collect("fuse") and not repairs.collect("fuse"), "Physical item pickup adds exactly one inventory entry")
	repairs.operate("isolate")
	repairs.operate("fit_fuse")
	repairs.operate("circuit", 2)
	repairs.operate("circuit", 3)
	_check(not repairs.power_solved and repairs.power_steps.is_empty(), "Wrong electrical order trips and clears sequence without losing the carrier")
	for circuit in [2, 1, 3]: repairs.operate("circuit", circuit)
	_check(repairs.power_solved and repairs.carrier_fitted, "Correct electrical startup powers the facility after a failed attempt")
	_check(checkpoints.save_checkpoint(_record(3)), "Power-restored checkpoint persists solved electrical state")
	var loaded: Dictionary = checkpoints.load_checkpoint()
	var restored := RepairsScript.new()
	restored.restore(loaded.repairs)
	_check(restored.power_solved and restored.inventory.has("fuse") and restored.power_steps == [2, 1, 3], "JSON checkpoint roundtrip restores progress and inventory")
	repairs = restored
	repairs.operate("test_pressure")
	_check(not repairs.cooling_solved, "Cooling cannot complete with local pumps stopped")
	repairs.operate("pump_a")
	repairs.operate("pump_b")
	repairs.operate("test_pressure")
	_check(not repairs.cooling_solved, "Running pumps do not bypass valve calibration")
	for valve in range(3):
		for turn in [2, 4, 3][valve]: repairs.operate("valve", valve)
	repairs.operate("test_pressure")
	_check(repairs.cooling_solved, "Calibrated pressure test restores cooling")
	_check(checkpoints.save_checkpoint(_record(5)), "Cooling checkpoint can be saved after continuing a restored session")
	repairs = RepairsScript.new()
	repairs.restore(checkpoints.load_checkpoint().repairs)
	_check(repairs.valves == [2, 4, 3] and repairs.cooling_solved, "Restored calibration retains integral actuator values for later puzzle operations")
	repairs.operate("fit_module")
	_check(not repairs.module_fitted, "Network cannot accept a module absent from inventory")
	repairs.collect("module")
	repairs.operate("fit_module")
	for port in [1, 2, 3]: repairs.operate("link", port)
	repairs.operate("commit_network")
	_check(not repairs.network_solved, "Wrong but distinct uplinks fail network verification")
	repairs.operate("reset_network")
	repairs.operate("link", 6)
	repairs.operate("link", 6)
	_check(repairs.links == [6], "Duplicate uplink assignment cannot consume another channel")
	for port in [1, 4]: repairs.operate("link", port)
	repairs.operate("commit_network")
	_check(repairs.network_solved, "Routing sheet order synchronizes network after a failed attempt")
	_check(checkpoints.save_checkpoint(_record(7)), "Combined puzzle and boolean environmental-event state saves successfully")
	var bad_stage := _record(3)
	_check(not checkpoints.save_checkpoint(bad_stage) and checkpoints.load_checkpoint().stage == 7, "Inconsistent stage is rejected without overwriting the playable save")
	repairs.collect("badge")
	_check(checkpoints.save_checkpoint(_record(10)), "Core checkpoint requires and preserves recovered access badge")
	_check(not checkpoints.save_checkpoint(_record(12)), "Dangerous pursuit state cannot replace a safe checkpoint")
	var corrupt := FileAccess.open(checkpoints.path, FileAccess.WRITE)
	corrupt.store_string("incomplete write")
	corrupt.close()
	_check(checkpoints.load_checkpoint().stage == 7 and checkpoints.can_continue(), "Damaged current file recovers the previous validated checkpoint")
	_check(checkpoints.save_checkpoint(_record(10)), "Recovery can be followed by another valid atomic save")
	_check(checkpoints.save_checkpoint(_record(14)) and not checkpoints.can_continue(), "Completed ending is persisted and does not offer a broken Continue")
	var invalid := RepairsScript.new()
	invalid.collect("fuse")
	invalid.operate("isolate")
	invalid.operate("fit_fuse")
	invalid.power_steps = [2, 1, 3]
	var impossible := _record(2)
	impossible.repairs = invalid.snapshot()
	_check(not checkpoints.save_checkpoint(impossible), "Completed-but-unsolved electrical record is rejected before it can cause an out-of-range retry")
	for suffix in ["", ".backup", ".tmp"]:
		if FileAccess.file_exists(checkpoints.path + suffix):
			DirAccess.remove_absolute(checkpoints.path + suffix)
	DirAccess.remove_absolute(directory)
	print("PROGRESSION_STATE_VERIFICATION: ", "PASS" if failures.is_empty() else "FAIL", " / failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
