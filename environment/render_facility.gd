extends SceneTree
## Reproducible offscreen-authored camera composition and renderer audit.

func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	var output_root := ProjectSettings.globalize_path("res://test-output")
	DirAccess.make_dir_recursive_absolute(output_root)
	var ignore_file := FileAccess.open(output_root.path_join(".gdignore"), FileAccess.WRITE)
	ignore_file.close()
	var output := output_root.path_join("facility")
	var measure := not ("--screenshots-only" in OS.get_cmdline_user_args())
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		output += "-compatibility"
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1920, 1080)
	root.msaa_3d = Viewport.MSAA_2X
	var world := WorldEnvironment.new()
	var atmosphere := Environment.new()
	atmosphere.background_mode = Environment.BG_COLOR
	atmosphere.background_color = Color("101c22")
	atmosphere.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	atmosphere.ambient_light_color = Color("91aab9")
	atmosphere.ambient_light_energy = 0.34
	atmosphere.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	atmosphere.tonemap_exposure = 1.2
	atmosphere.fog_enabled = true
	atmosphere.fog_light_color = Color("24343d")
	atmosphere.fog_light_energy = 0.3
	atmosphere.fog_density = 0.006
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		atmosphere.ssao_enabled = true
		atmosphere.ssao_radius = 1.5
		atmosphere.ssao_intensity = 2.0
		atmosphere.glow_enabled = true
		atmosphere.glow_intensity = 0.55
	world.environment = atmosphere
	root.add_child(world)
	var script: GDScript = load("res://environment/facility.gd")
	var facility: Node3D = script.new()
	root.add_child(facility)
	facility.build()
	facility.apply_quality(2)
	facility.set_stage(7)
	facility.set_door("core", true)
	var camera := Camera3D.new()
	camera.fov = 80.0
	root.add_child(camera)
	camera.current = true
	var report: Dictionary = {"renderer": RenderingServer.get_current_rendering_method(), "resolution": "1920x1080", "preset": "HIGH", "views": {}}
	for key in facility.screenshot_points:
		var data: Dictionary = facility.screenshot_points[key]
		camera.position = data.position
		camera.look_at(data.target)
		if key == "elevator":
			facility.set_door("elevator", false)
			await create_timer(1.6).timeout
		for frame in range(60):
			await process_frame
		var elapsed := 0.0
		if measure:
			var start: int = Time.get_ticks_usec()
			for frame in range(120):
				await process_frame
			elapsed = float(Time.get_ticks_usec() - start) / 1000000.0
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(key + ".png"))
		if measure:
			report.views[key] = {"average_fps": 120.0 / elapsed, "draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)}
		print("RENDERED ", key, " ", report.views.get(key, "screenshot only"))
		if key == "elevator":
			facility.set_door("elevator", true)
	if measure:
		var file := FileAccess.open(output.path_join("render-report.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	quit(0)
