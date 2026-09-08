extends CanvasLayer
class_name GameUI
## Shared menus and diegetic terminal panels; progression remains in Game.

signal new_game_requested
signal continue_requested
signal resume_requested
signal menu_requested
signal quit_requested
signal choice_selected(id: String)
signal modal_closed
signal settings_changed(values: Dictionary)
signal ui_sound

const INK := Color("091416")
const PAPER := Color("c4d5ce")
const MUTED := Color("839e9b")
const AMBER := Color("e6ae60")

var modal_open := true
var view := "main"
var settings: GameSettings
var _root: Control
var _hud: Control
var _overlay: ColorRect
var _panel: PanelContainer
var _content: VBoxContainer
var _objective: Label
var _prompt: Label
var _subtitle_panel: PanelContainer
var _subtitle: Label
var _notice: Label
var _notice_time := 0.0
var _settings_return := "main"
var _has_save := false
var _pending: Dictionary = {}
var _theme: Theme
var _allow_close := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_theme()
	_build_canvas()
	show_main_menu(false)


func setup(settings_ref: GameSettings) -> void:
	settings = settings_ref


func _build_theme() -> void:
	_theme = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "DejaVu Sans Mono", "monospace"])
	_theme.default_font = font
	_theme.default_font_size = 26
	_theme.set_color("font_color", "Label", PAPER)
	_theme.set_color("font_color", "Button", PAPER)
	_theme.set_color("font_hover_color", "Button", Color.WHITE)
	_theme.set_color("font_focus_color", "Button", Color.WHITE)
	_theme.set_color("font_disabled_color", "Button", Color("4d6261"))
	_theme.set_color("font_color", "CheckButton", PAPER)
	_theme.set_stylebox("normal", "Button", _style(Color("112427"), Color("294749")))
	_theme.set_stylebox("hover", "Button", _style(Color("1b3538"), AMBER))
	_theme.set_stylebox("pressed", "Button", _style(Color("294747"), AMBER))
	_theme.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), AMBER))
	_theme.set_stylebox("disabled", "Button", _style(Color("0c1c1e"), Color("1a3032")))
	_theme.set_stylebox("panel", "PanelContainer", _style(Color("0d1c1f"), Color("365153"), 30))
	_theme.set_stylebox("slider", "HSlider", _style(Color("294749"), Color("294749"), 2))
	_theme.set_stylebox("grabber_area", "HSlider", _style(AMBER, AMBER, 2))
	_theme.set_stylebox("grabber_area_highlight", "HSlider", _style(PAPER, PAPER, 2))
	var handle := GradientTexture2D.new()
	handle.width = 6
	handle.height = 18
	handle.gradient = Gradient.new()
	handle.gradient.colors = PackedColorArray([AMBER, AMBER])
	_theme.set_icon("grabber", "HSlider", handle)
	_theme.set_icon("grabber_highlight", "HSlider", handle)
	_theme.set_stylebox("scroll", "VScrollBar", _style(Color("132b2e"), Color("132b2e"), 3))
	_theme.set_stylebox("grabber", "VScrollBar", _style(MUTED, MUTED, 3))
	_theme.set_stylebox("grabber_highlight", "VScrollBar", _style(AMBER, AMBER, 3))
	_theme.set_constant("separation", "VBoxContainer", 16)
	_theme.set_constant("separation", "HBoxContainer", 20)


func _style(fill: Color, border: Color, margin: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	return style


func _build_canvas() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _theme
	add_child(_root)
	_hud = Control.new()
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hud)
	_objective = _label("", 24, MUTED)
	_objective.position = Vector2(54, 40)
	_objective.size = Vector2(870, 112)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hud.add_child(_objective)
	var reticle := _label("·", 34, Color(0.75, 0.86, 0.82, 0.65))
	_hud.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position -= Vector2(10, 24)
	_prompt = _label("", 25, PAPER)
	_hud.add_child(_prompt)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -600
	_prompt.offset_right = 600
	_prompt.offset_top = 50
	_prompt.offset_bottom = 95
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice = _label("", 23, AMBER)
	_hud.add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_notice.offset_left = 54
	_notice.offset_top = -94
	_notice.offset_right = 1160
	_notice.offset_bottom = -42
	_overlay = ColorRect.new()
	_overlay.color = Color(0.015, 0.035, 0.04, 0.95)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(1040, 0)
	center.add_child(_panel)
	_content = VBoxContainer.new()
	_panel.add_child(_content)
	_subtitle_panel = PanelContainer.new()
	_root.add_child(_subtitle_panel)
	_subtitle_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_subtitle_panel.offset_left = 260
	_subtitle_panel.offset_right = -260
	_subtitle_panel.offset_top = -190
	_subtitle_panel.offset_bottom = -68
	_subtitle_panel.add_theme_stylebox_override("panel", _style(Color(0.015, 0.035, 0.04, 0.93), Color(0, 0, 0, 0), 16))
	_subtitle_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle = _label("", 27, PAPER)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_panel.add_child(_subtitle)
	_subtitle_panel.hide()


func _label(text: String, font_size: int = 26, color: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable, disabled: bool = false, parent: Node = null) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 62
	button.disabled = disabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(func() -> void:
		ui_sound.emit()
		if action.is_valid():
			action.call()
	)
	(parent if parent != null else _content).add_child(button)
	return button


func _clear() -> void:
	for child in _content.get_children():
		_content.remove_child(child)
		child.queue_free()


func _present(next_view: String, title: String, body: String = "") -> void:
	_clear()
	view = next_view
	_allow_close = true
	modal_open = true
	_hud.hide()
	_overlay.show()
	_overlay.color.a = 0.96 if next_view == "main" else 0.9
	_content.add_child(_label("MERIDIAN  /  SUBSURFACE SYSTEMS", 20, AMBER))
	var heading := _label(title, 54 if next_view == "main" else 36)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(heading)
	if not body.is_empty():
		var description := _label(body, 24, MUTED)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(description)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _focus_first() -> void:
	for button in _content.find_children("*", "Button", true, false):
		if not button.disabled:
			button.grab_focus()
			return


func show_main_menu(has_save: bool) -> void:
	_has_save = has_save
	show_subtitle("")
	_present("main", "BELOW LEVEL 6", "The night shift has not checked out.\nSector Six is waiting for a technician.")
	_button("CONTINUE", func() -> void: continue_requested.emit(), not has_save)
	_button("NEW GAME", _request_new_game)
	_button("SETTINGS", show_settings)
	_button("QUIT", func() -> void: quit_requested.emit())
	_content.add_child(_label("WASD move   E interact   F flashlight\nSHIFT sprint   CTRL / C crouch   ESC pause", 20, MUTED))
	_focus_first()


func _request_new_game() -> void:
	if not _has_save:
		new_game_requested.emit()
		return
	_present("confirm_new", "BEGIN A NEW SHIFT?", "Your existing checkpoint will be replaced when the new shift starts.")
	_button("BEGIN NEW GAME", func() -> void: new_game_requested.emit())
	_button("BACK", func() -> void: show_main_menu(_has_save))
	_focus_first()


func show_pause() -> void:
	_present("pause", "SHIFT SUSPENDED", "Your progress is recorded at safe checkpoints.")
	_button("RESUME", func() -> void: resume_requested.emit())
	_button("SETTINGS", show_settings)
	_button("MAIN MENU", func() -> void: menu_requested.emit())
	_button("QUIT", func() -> void: quit_requested.emit())
	_focus_first()


func show_game() -> void:
	view = "game"
	modal_open = false
	_overlay.hide()
	_hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func show_document(title: String, text: String) -> void:
	_present("document", title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var document := _label(text, 27, PAPER)
	document.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(document)
	_button("CLOSE  /  ESC", dismiss_modal)
	_focus_first()


func show_choices(title: String, text: String, choices: Array, allow_close: bool = true) -> void:
	_present("choices", title, text)
	_allow_close = allow_close
	_add_choices(choices)
	if allow_close:
		_button("CLOSE  /  ESC", dismiss_modal)
	_focus_first()


func show_feed(title: String, texture: Texture2D, choices: Array, allow_close: bool = true) -> void:
	_present("feed", title, "SECURITY / LOCAL VIDEO BUFFER")
	_allow_close = allow_close
	var feed := TextureRect.new()
	feed.texture = texture
	feed.custom_minimum_size = Vector2(900, 420)
	feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_content.add_child(feed)
	_add_choices(choices)
	if allow_close:
		_button("CLOSE  /  ESC", dismiss_modal)
	_focus_first()


func _add_choices(choices: Array) -> void:
	var parent: Node = _content
	if choices.size() > 4:
		var columns := 3 if choices.size() > 10 else 2
		var rows := ceili(float(choices.size()) / columns)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size.y = mini(rows * 62 + (rows - 1) * 12, 370)
		_content.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = columns
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		scroll.add_child(grid)
		parent = grid
	for item in choices:
		if not item is Dictionary or not item.has("id") or not item.has("label"):
			continue
		var id := str(item.id)
		var button := _button(str(item.label), func() -> void: choice_selected.emit(id), bool(item.get("disabled", false)), parent)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if parent is GridContainer:
			button.add_theme_font_size_override("font_size", 22)


func dismiss_modal() -> void:
	show_game()
	modal_closed.emit()


func handle_back() -> bool:
	match view:
		"settings":
			_leave_settings()
		"confirm_new":
			show_main_menu(_has_save)
		"document", "choices", "feed":
			if _allow_close:
				dismiss_modal()
		"pause":
			resume_requested.emit()
		_:
			return false
	return true


func set_objective(text: String) -> void:
	_objective.text = "WORK ORDER / " + text if not text.is_empty() else ""


func set_prompt(text: String) -> void:
	_prompt.text = text


func show_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle_panel.visible = not text.is_empty()


func show_notice(text: String, seconds: float = 4.0) -> void:
	_notice.text = text
	_notice_time = seconds


func _process(delta: float) -> void:
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_notice.text = ""


func show_settings() -> void:
	if settings == null:
		return
	if view != "settings":
		_settings_return = "pause" if view == "pause" else "main"
	_pending = settings.values.duplicate()
	_render_settings()


func _render_settings() -> void:
	_present("settings", "SETTINGS", "Apply saves your preferences. Escape returns without applying changes.")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 540
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var fields := VBoxContainer.new()
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 18)
	scroll.add_child(fields)
	fields.add_child(_label("AUDIO", 22, AMBER))
	for pair in [["Master", "master"], ["Atmosphere / music", "music"], ["Effects", "sfx"], ["Radio dialogue", "voice"]]:
		_slider(fields, pair[0], pair[1], 0, 1, 0.01, true)
	_toggle(fields, "Subtitles", "subtitles")
	fields.add_child(_label("CONTROLS / COMFORT", 22, AMBER))
	_slider(fields, "Mouse sensitivity", "sensitivity", 0.02, 0.4, 0.01)
	_slider(fields, "Field of view", "fov", 65, 110, 1)
	_toggle(fields, "Invert vertical look", "invert_y")
	_select(fields, "Head movement", "head_bob", ["Off", "Subtle", "Normal"], [0, 1, 2])
	_toggle(fields, "Reduce camera shake", "reduced_shake")
	_toggle(fields, "Reduce light flashes", "reduced_flashes")
	fields.add_child(_label("DISPLAY", 22, AMBER))
	_select(fields, "Graphics quality", "preset", ["Low", "Medium", "High", "Ultra"], [0, 1, 2, 3])
	_select(fields, "Window mode", "window_mode", ["Windowed", "Borderless", "Fullscreen"], [0, 1, 2])
	_select(fields, "Window resolution", "resolution", ["1280 × 720", "1920 × 1080", "2560 × 1440", "3840 × 2160"], [0, 1, 2, 3])
	_select(fields, "Frame limit", "fps_limit", ["30", "60", "90", "120", "144", "240", "Unlimited"], [30, 60, 90, 120, 144, 240, 0])
	_toggle(fields, "Vertical synchronization", "vsync")
	_slider(fields, "Brightness", "brightness", 0.7, 1.4, 0.05)
	fields.add_child(_label("Brightness 1.0 preserves the intended lighting.\nBorderless and fullscreen use your desktop resolution.", 19, MUTED))
	var actions := HBoxContainer.new()
	_content.add_child(actions)
	for pair in [["APPLY", _apply_settings], ["DEFAULTS", _default_settings], ["BACK", _leave_settings]]:
		var button := _button(pair[0], pair[1], false, actions)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_focus_first()


func _field(parent: Node, title: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	parent.add_child(row)
	var label := _label(title, 23)
	label.custom_minimum_size.x = 360
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _slider(parent: Node, title: String, key: String, minimum: float, maximum: float, step: float, percent: bool = false) -> void:
	var row := _field(parent, title)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(_pending[key])
	slider.custom_minimum_size.x = 330
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value := _label(_format_value(slider.value, percent), 22, AMBER)
	value.custom_minimum_size.x = 85
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(number: float) -> void:
		_pending[key] = number
		value.text = _format_value(number, percent)
	)


func _format_value(number: float, percent: bool) -> String:
	return "%d%%" % roundi(number * 100) if percent else ("%d" % roundi(number) if number >= 10 else "%.2f" % number)


func _toggle(parent: Node, title: String, key: String) -> void:
	var row := _field(parent, title)
	var button := _button("ON" if bool(_pending[key]) else "OFF", Callable(), false, row)
	button.custom_minimum_size = Vector2(440, 48)
	button.pressed.connect(func() -> void:
		_pending[key] = not bool(_pending[key])
		button.text = "ON" if bool(_pending[key]) else "OFF"
	)


func _select(parent: Node, title: String, key: String, labels: Array, options: Array) -> void:
	var row := _field(parent, title)
	var selected := options.find(int(_pending[key]))
	if selected < 0:
		selected = 0
	var button := _button(str(labels[selected]) + "  ›", Callable(), false, row)
	button.custom_minimum_size = Vector2(440, 48)
	button.pressed.connect(func() -> void:
		var next := (options.find(int(_pending[key])) + 1) % options.size()
		_pending[key] = options[next]
		button.text = str(labels[next]) + "  ›"
	)


func _apply_settings() -> void:
	for key in _pending:
		settings.set_value(key, _pending[key])
	var error := settings.save_settings()
	settings_changed.emit(settings.values.duplicate())
	if error != OK:
		var notice := _label("Preferences applied, but could not be saved to disk.", 20, AMBER)
		_content.add_child(notice)
		return
	_leave_settings()


func _default_settings() -> void:
	_pending = GameSettings.DEFAULTS.duplicate()
	_render_settings()


func _leave_settings() -> void:
	if _settings_return == "pause":
		show_pause()
	else:
		show_main_menu(_has_save)
