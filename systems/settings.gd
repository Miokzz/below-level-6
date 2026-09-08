extends Node
class_name GameSettings
## Preferences live separately from narrative checkpoints.

const SETTINGS_PATH := "user://settings.cfg"
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const DEFAULTS := {
	"master": 0.8, "music": 0.7, "sfx": 0.8, "voice": 0.9,
	"fov": 82.0, "sensitivity": 0.11, "invert_y": false,
	"brightness": 1.0, "head_bob": 1, "reduced_flashes": true,
	"reduced_shake": true, "subtitles": true, "preset": 2,
	"window_mode": 0, "resolution": 0, "fps_limit": 60, "vsync": true
}
const RANGES := {
	"master": Vector2(0, 1), "music": Vector2(0, 1), "sfx": Vector2(0, 1), "voice": Vector2(0, 1),
	"fov": Vector2(65, 110), "sensitivity": Vector2(0.02, 0.4), "brightness": Vector2(0.7, 1.4),
	"head_bob": Vector2(0, 2), "preset": Vector2(0, 3), "window_mode": Vector2(0, 2),
	"resolution": Vector2(0, 3), "fps_limit": Vector2(0, 240)
}

var values: Dictionary = DEFAULTS.duplicate()
var storage_path := SETTINGS_PATH
var _last_display: Array = []


func _ready() -> void:
	load_settings()


func load_settings() -> Error:
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	var error := config.load(storage_path)
	if error == ERR_FILE_NOT_FOUND:
		return OK
	if error != OK:
		push_warning("Preferences could not be read; safe defaults restored.")
		return error
	for key in DEFAULTS:
		set_value(key, config.get_value("preferences", key, DEFAULTS[key]))
	return OK


func set_value(key: String, value: Variant) -> void:
	if not DEFAULTS.has(key):
		return
	if DEFAULTS[key] is bool:
		values[key] = value if value is bool else DEFAULTS[key]
		return
	if not (value is float or value is int) or not is_finite(float(value)):
		values[key] = DEFAULTS[key]
		return
	var limits: Vector2 = RANGES[key]
	var normalized := clampf(float(value), limits.x, limits.y)
	values[key] = int(normalized) if DEFAULTS[key] is int else normalized


func save_settings() -> Error:
	var config := ConfigFile.new()
	for key in DEFAULTS:
		config.set_value("preferences", key, values[key])
	var error := config.save(storage_path + ".tmp")
	if error != OK:
		return error
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(storage_path + ".tmp"), ProjectSettings.globalize_path(storage_path))


func apply_runtime(player: Node = null, facility: Node = null, sound: Node = null) -> void:
	if is_instance_valid(player) and player.has_method("apply_settings"):
		player.apply_settings(values)
	if is_instance_valid(facility) and facility.has_method("apply_quality"):
		facility.apply_quality(int(values.preset))
	if is_instance_valid(sound) and sound.has_method("apply_settings"):
		sound.apply_settings(values)
	if player is Node3D and player.is_inside_tree():
		var environment: Environment = player.get_world_3d().environment
		if environment != null:
			environment.adjustment_enabled = true
			environment.adjustment_brightness = float(values.brightness)
	Engine.max_fps = int(values.fps_limit)
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(values.vsync) else DisplayServer.VSYNC_DISABLED)
	var display: Array = [values.window_mode, values.resolution]
	if display == _last_display:
		return
	_last_display = display
	var mode := int(values.window_mode)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, mode == 1)
	var screen := DisplayServer.window_get_current_screen()
	if mode == 2:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif mode == 1:
		DisplayServer.window_set_size(DisplayServer.screen_get_size(screen))
		DisplayServer.window_set_position(DisplayServer.screen_get_position(screen))
	else:
		var available := DisplayServer.screen_get_usable_rect(screen)
		var target: Vector2i = RESOLUTIONS[int(values.resolution)]
		target.x = mini(target.x, maxi(640, available.size.x - 40))
		target.y = mini(target.y, maxi(360, available.size.y - 80))
		DisplayServer.window_set_size(target)
		DisplayServer.window_set_position(available.position + (available.size - target) / 2)
