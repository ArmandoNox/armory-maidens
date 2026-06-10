extends Control
## Title screen: key art, New Run / Continue / How to Play / Settings.
## Dev hook: AM_SHOT env → jump straight to the map for the screenshot tool;
## AM_TITLE_SHOT env → screenshot this screen and quit.


func _ready() -> void:
	if OS.get_environment("AM_SHOT") != "":
		if Game.run == null:
			Game.new_run()
		get_tree().change_scene_to_file.call_deferred("res://scenes/run_map.tscn")
		return
	_build()
	if OS.get_environment("AM_TITLE_SHOT") != "":
		_dev_screenshot(OS.get_environment("AM_TITLE_SHOT"))


func _dev_screenshot(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("title screenshot saved")
	get_tree().quit()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#101218")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists("res://assets/backgrounds/title.png"):
		var art := TextureRect.new()
		art.texture = load("res://assets/backgrounds/title.png")
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		# Bottom gradient so the menu reads against the art.
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.42)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	var title := Label.new()
	title.text = "ARMORY MAIDENS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.add_theme_color_override("font_outline_color", Color("#12143a"))
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "press-turn tactics · element × steel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color("#c8ccd8"))
	sub.add_theme_color_override("font_outline_color", Color("#101218"))
	sub.add_theme_constant_override("outline_size", 6)
	col.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 26)
	col.add_child(gap)

	var btn_col := VBoxContainer.new()
	btn_col.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_col.add_theme_constant_override("separation", 8)
	col.add_child(btn_col)

	if Game.has_save():
		_menu_button(btn_col, "Continue", UITheme.GOLD, func():
			if Game.load_run():
				get_tree().change_scene_to_file("res://scenes/run_map.tscn")
			else:
				# Stale/corrupt save was discarded — rebuild the menu with notice.
				for ch in get_children():
					ch.queue_free()
				_build())
	_menu_button(btn_col, "New Run", UITheme.GOLD if not Game.has_save() else Color("#c8ccd8"), func():
		Game.new_run()
		get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
	_menu_button(btn_col, "How to Play", UITheme.PURPLE, func(): HelpOverlay.popup(self))
	_menu_button(btn_col, "Settings", Color("#8d93a5"), _settings_popup)

	if Game.stale_save_notice:
		Game.stale_save_notice = false
		var notice := Label.new()
		notice.text = "Your save was from an older build and has been retired. Fresh run awaits."
		notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		notice.add_theme_font_size_override("font_size", 13)
		notice.add_theme_color_override("font_color", Color("#e8a04a"))
		col.add_child(notice)

	var foot := Label.new()
	foot.text = "act 1 preview build"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 12)
	foot.add_theme_color_override("font_color", Color("#5d6275"))
	col.add_child(foot)


func _menu_button(parent: Node, text: String, accent: Color, fn) -> void:
	var wrap := CenterContainer.new()
	parent.add_child(wrap)
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(280, 52)
	btn.add_theme_font_size_override("font_size", 18)
	UITheme.style_button(btn, accent)
	btn.pressed.connect(fn)
	wrap.add_child(btn)


func _settings_popup() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 100
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			overlay.queue_free())
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	frame.custom_minimum_size = Vector2(360, 0)
	center.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	frame.add_child(box)
	var t := Label.new()
	t.text = "SETTINGS"
	t.add_theme_color_override("font_color", UITheme.GOLD)
	t.add_theme_font_size_override("font_size", 18)
	box.add_child(t)
	var vol_l := Label.new()
	vol_l.text = "Volume — arrives with the audio pass"
	vol_l.add_theme_color_override("font_color", Color("#8d93a5"))
	box.add_child(vol_l)
	var vol := HSlider.new()
	vol.editable = false
	vol.value = 80
	box.add_child(vol)
	var close := Button.new()
	close.text = "Close"
	UITheme.style_button(close)
	close.pressed.connect(overlay.queue_free)
	box.add_child(close)
