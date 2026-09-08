extends SceneTree
## Exercise real menu controls and preferences without touching the player's files.

var failures: Array[String] = []
var ui: GameUI


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)


func press(text: String) -> void:
	for button in ui._content.find_children("*", "Button", true, false):
		if button.text == text:
			check(not button.disabled, "Attempted a disabled menu action: " + text)
			button.pressed.emit()
			return
	check(false, "Missing menu action: " + text)


func _run() -> void:
	var preferences := GameSettings.new()
	preferences.storage_path = "user://ui_validation_%d.cfg" % OS.get_process_id()
	root.add_child(preferences)
	ui = GameUI.new()
	root.add_child(ui)
	ui.setup(preferences)
	var actions: Array[String] = []
	ui.new_game_requested.connect(func() -> void: actions.append("new"))
	ui.continue_requested.connect(func() -> void: actions.append("continue"))
	ui.choice_selected.connect(func(id: String) -> void: actions.append(id))
	ui.modal_closed.connect(func() -> void: actions.append("closed"))
	ui.settings_changed.connect(func(_values: Dictionary) -> void: actions.append("settings"))
	check(ui.view == "main" and ui.modal_open, "Initial menu did not open")
	for button in ui._content.find_children("*", "Button", true, false):
		if button.text == "CONTINUE":
			check(button.disabled, "Continue exposed without a checkpoint")
	press("NEW GAME")
	check(actions == ["new"], "New game button did not emit exactly one action")
	ui.show_main_menu(true)
	press("CONTINUE")
	press("NEW GAME")
	check(ui.view == "confirm_new" and actions == ["new", "continue"], "Existing save was not protected by new-game confirmation")
	press("BACK")
	press("SETTINGS")
	check(ui.view == "settings", "Settings button did not open usable preferences")
	var sliders := ui._content.find_children("*", "HSlider", true, false)
	check(sliders.size() == 7, "Expected all audio and controller/calibration sliders")
	sliders[0].value = 0.37
	press("APPLY")
	check(ui.view == "main" and actions.has("settings"), "Apply did not close settings and emit changes")
	check(is_equal_approx(float(preferences.values.master), 0.37), "Master control did not apply")
	preferences.values.master = 0.99
	check(preferences.load_settings() == OK and is_equal_approx(float(preferences.values.master), 0.37), "Preferences did not survive a disk round trip")
	preferences.set_value("sensitivity", INF)
	preferences.set_value("preset", 90)
	check(preferences.values.sensitivity == GameSettings.DEFAULTS.sensitivity and preferences.values.preset == 3, "Invalid preferences were not sanitized")
	ui.show_pause()
	press("SETTINGS")
	press("DEFAULTS")
	press("BACK")
	check(ui.view == "pause" and is_equal_approx(float(preferences.values.master), 0.37), "Back applied unconfirmed default changes")
	ui.show_document("SHIFT LOG", "The night shift never left.\nReturn to operations.")
	press("CLOSE  /  ESC")
	check(not ui.modal_open and ui.view == "game" and actions.has("closed"), "Document could not be closed")
	ui.show_choices("POWER PANEL", "Choose a circuit", [{"id": "a", "label": "CIRCUIT A"}, {"id": "b", "label": "CIRCUIT B", "disabled": true}])
	press("CIRCUIT A")
	check(actions.back() == "a", "Terminal selection did not preserve the option ID")
	check(ui.handle_back() and ui.view == "game", "Escape could not release terminal focus")
	ui.show_choices("SIGNAL LOST", "Connection terminated.", [{"id": "retry", "label": "RETRY"}], false)
	check(ui.handle_back() and ui.view == "choices", "Escape bypassed the failure screen")
	ui.show_subtitle("Radio / Return to the lift.")
	check(ui._subtitle_panel.visible, "Subtitle was not visible")
	ui.show_subtitle("")
	check(not ui._subtitle_panel.visible, "Empty subtitle left an overlay")
	if "--capture-ui" in OS.get_cmdline_user_args():
		ui.show_main_menu(true)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/below-level-6-menu.png")
		ui.show_settings()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/below-level-6-settings.png")
		ui._content.find_children("*", "ScrollContainer", true, false)[0].scroll_vertical = 10000
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/below-level-6-settings-display.png")
		var keypad: Array = []
		for number in range(10):
			keypad.append({"id": str(number), "label": str(number)})
		keypad.append({"id": "clear", "label": "CLEAR"})
		keypad.append({"id": "submit", "label": "VERIFY CREDENTIAL"})
		ui.show_choices("CORE / ACCESS CONTROL", "BADGE VERIFIED\nPIN: ___\n\nThree-digit authorization. Security memo: D / SURVEILLANCE.", keypad)
		await process_frame
		await RenderingServer.frame_post_draw
		check(ui._panel.get_global_rect().end.y <= root.get_visible_rect().size.y, "Keypad panel extends below the viewport")
		check(ui._panel.get_global_rect().position.y >= 0, "Keypad panel extends above the viewport")
		root.get_texture().get_image().save_png("/tmp/below-level-6-keypad.png")
		press("4")
		check(actions.back() == "4", "Grid choice captured the wrong ID")
		var patches: Array = [{"id": "fit", "label": "SEAT OFFLINE BRIDGE"}]
		for number in range(1, 7):
			patches.append({"id": str(number), "label": "PATCH PORT %d" % number})
		patches.append({"id": "commit", "label": "VERIFY AND COMMIT"})
		patches.append({"id": "clear", "label": "CLEAR PATCH"})
		ui.show_choices("NETWORK / MAINTENANCE", "OFFLINE BRIDGE / SEATED\nCHANNELS I / II / III: [0, 0, 0]\n\nSelect three distinct uplinks using the route allocation sheet beside the racks; then commit.\n\nPATCH CLEARED", patches)
		await process_frame
		await RenderingServer.frame_post_draw
		check(ui._panel.get_global_rect().end.y <= root.get_visible_rect().size.y, "Network panel extends below the viewport")
		check(ui._panel.get_global_rect().position.y >= 0, "Network panel extends above the viewport")
		root.get_texture().get_image().save_png("/tmp/below-level-6-network-ui.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(preferences.storage_path))
	ui.queue_free()
	preferences.queue_free()
	await process_frame
	print("UI_VALIDATION: " + ("PASS" if failures.is_empty() else "FAIL") + " | main, continue, save replacement, settings controls/persistence/cancel, pause, documents, terminal choices, subtitles")
	quit(0 if failures.is_empty() else 1)
