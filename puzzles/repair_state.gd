extends RefCounted
class_name RepairState
## The same state machine serves terminal UI, persistence and regression tests.

const POWER_ORDER := [2, 1, 3]
const COOLING_TARGET := [2, 4, 3]
const NETWORK_ORDER := [6, 1, 4]

var inventory: Dictionary = {}
var isolated := false
var carrier_fitted := false
var power_steps: Array = []
var power_solved := false
var pumps := {"pump_a": false, "pump_b": false}
var valves: Array = [0, 0, 0]
var cooling_solved := false
var module_fitted := false
var links: Array = []
var network_solved := false
var brake_released := false
var line_purged := false

func collect(id: String) -> bool:
	if id not in ["fuse", "module", "badge"] or inventory.has(id):
		return false
	inventory[id] = true
	return true

func operate(action: String, value: int = 0) -> String:
	match action:
		"isolate":
			if power_solved: return "Distribution is already stable."
			isolated = true
			power_steps.clear()
			return "Bus isolated. It is safe to fit the carrier."
		"fit_fuse":
			if not isolated: return "Isolate the distribution bus before fitting the carrier."
			if not inventory.has("fuse"): return "Replacement carrier required. Service stock is beside the lift."
			carrier_fitted = true
			return "Carrier seated. Follow the startup order on the wall procedure."
		"circuit":
			if power_solved: return "Power distribution stable."
			if not isolated or not carrier_fitted: return "Isolate the bus and fit the replacement carrier first."
			if power_steps.size() >= POWER_ORDER.size():
				power_steps.clear()
				return "Interlock reset. Follow the startup sequence again."
			if value != POWER_ORDER[power_steps.size()]:
				power_steps.clear()
				return "Interlock tripped. Sequence cleared; carrier remains safe. Check the wall procedure."
			power_steps.append(value)
			if power_steps.size() == POWER_ORDER.size():
				power_solved = true
				return "POWER ONLINE / Distribution stable."
			return "Circuit %d latched. Continue the startup sequence." % value
		"reset_power":
			if not power_solved: power_steps.clear()
			return "Startup sequence cleared."
		"pump_a", "pump_b":
			if not power_solved: return "Local motor starter has no power. Restore electrical distribution."
			pumps[action] = true
			return "%s RUNNING / Local pressure available." % action.replace("_", " ").to_upper()
		"valve":
			if cooling_solved: return "Cooling circulation stable."
			if not power_solved: return "Actuators offline. Restore electrical distribution."
			if value < 0 or value > 2: return "Unknown actuator."
			valves[value] = (int(valves[value]) + 1) % 6
			return "Valve %s set to %d. Verify the calibration plate before pressure test." % ["ABC"[value], valves[value]]
		"test_pressure":
			if not pumps.pump_a or not pumps.pump_b: return "Pressure test blocked. Start both local pumps in the cooling gallery."
			if valves != COOLING_TARGET: return "Pressure outside calibration. Inlet / bypass / return must match the wall plate."
			cooling_solved = true
			return "COOLING ONLINE / Supply 2 bar; bypass 4; return 3. Flow stable."
		"reset_cooling":
			if not cooling_solved: valves = [0, 0, 0]
			return "Valves returned to zero. Pump power retained."
		"fit_module":
			if not cooling_solved: return "Rack temperature unsafe. Restore cooling first."
			if not inventory.has("module"): return "Bridge module required. Cold storage is through Operations / Archive."
			module_fitted = true
			return "Bridge seated. Assign uplinks in the order on the routing sheet."
		"link":
			if network_solved: return "Network synchronized."
			if not cooling_solved or not module_fitted: return "Cool the rack and seat the offline bridge first."
			if value < 1 or value > 6: return "Unknown uplink."
			if links.size() >= 3: return "Three uplinks assigned. Commit or clear the patch."
			if links.has(value): return "That uplink is already assigned. Each channel needs a distinct port."
			links.append(value)
			return "Uplink %d assigned to channel %d." % [value, links.size()]
		"commit_network":
			if not cooling_solved or not module_fitted or links != NETWORK_ORDER:
				return "Routing verification failed. Clear the patch and check the route allocation sheet."
			network_solved = true
			return "NETWORK ONLINE / Remote command source: SECTOR 06."
		"reset_network":
			if not network_solved: links.clear()
			return "Patch cleared. Bridge retained."
	return "Control unavailable."

func snapshot() -> Dictionary:
	return {
		"inventory": inventory.duplicate(), "isolated": isolated, "carrier_fitted": carrier_fitted,
		"power_steps": power_steps.duplicate(), "power_solved": power_solved,
		"pumps": pumps.duplicate(), "valves": valves.duplicate(), "cooling_solved": cooling_solved,
		"module_fitted": module_fitted, "links": links.duplicate(), "network_solved": network_solved,
		"brake_released": brake_released, "line_purged": line_purged
	}

func restore(data: Dictionary) -> void:
	inventory = data.get("inventory", {}).duplicate()
	isolated = data.get("isolated", false)
	carrier_fitted = data.get("carrier_fitted", false)
	power_steps = _integer_array(data.get("power_steps", []))
	power_solved = data.get("power_solved", false)
	pumps = data.get("pumps", {"pump_a": false, "pump_b": false}).duplicate()
	valves = _integer_array(data.get("valves", [0, 0, 0]))
	cooling_solved = data.get("cooling_solved", false)
	module_fitted = data.get("module_fitted", false)
	links = _integer_array(data.get("links", []))
	network_solved = data.get("network_solved", false)
	brake_released = data.get("brake_released", false)
	line_purged = data.get("line_purged", false)

func _integer_array(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(int(value))
	return result
