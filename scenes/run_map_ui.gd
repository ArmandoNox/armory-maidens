extends Control
## Act map: floors bottom-up, selectable nodes pulse, edges from your position
## glow gold. Also hosts the event panel and the run-over panel.

const TYPE_LABELS := {
	"fight": "Fight", "elite": "ELITE", "rest": "Rest",
	"event": "Event", "boss": "BOSS",
}
const TYPE_COLORS := {
	"fight": "#c8ccd8", "elite": "#e2543e", "rest": "#6abf6a",
	"event": "#c77dff", "boss": "#ffd24a",
}
const TYPE_TOOLTIPS := {
	"fight": "A fight scaled to this depth. Win it and the armory offers a new technique.",
	"elite": "A dangerous foe — elites ALWAYS carry a hidden mutation. Probe first.",
	"rest": "The party recovers 30% of max HP.",
	"event": "Something unusual. Choices, not combat.",
	"boss": "The Verdigris Colossus. It hides TWO mutations.",
}

var run: Run
var main: VBoxContainer
var root_margin: MarginContainer
var status_label: Label


func _ready() -> void:
	if Game.run == null:
		Game.new_run()
	run = Game.run
	_build()
	if OS.get_environment("AM_SHOT") != "":
		_dev_screenshot(OS.get_environment("AM_SHOT"))


func _dev_screenshot(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)
	print("map screenshot saved")
	get_tree().quit()


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var bg := ColorRect.new()
	bg.color = Color("#1b1d24")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if ResourceLoader.exists("res://assets/backgrounds/map.png"):
		var bg_tex := TextureRect.new()
		bg_tex.texture = load("res://assets/backgrounds/map.png")
		bg_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg_tex)
		var shade := ColorRect.new()
		shade.color = Color(0, 0, 0, 0.52)
		shade.set_anchors_preset(Control.PRESET_FULL_RECT)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
	root_margin = MarginContainer.new()
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root_margin.add_theme_constant_override(m, 16)
	add_child(root_margin)
	main = VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	root_margin.add_child(main)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	main.add_child(top)
	var title := Label.new()
	title.text = "ARMORY MAIDENS — Act 1"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.custom_minimum_size = Vector2(36, 32)
	help_btn.tooltip_text = "How to play"
	help_btn.pressed.connect(func(): HelpOverlay.popup(self))
	UITheme.style_button(help_btn, UITheme.PURPLE)
	top.add_child(help_btn)
	var to_title := Button.new()
	to_title.text = "Title"
	to_title.tooltip_text = "Back to the title screen. Progress is auto-saved at every map step."
	to_title.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	UITheme.style_button(to_title)
	top.add_child(to_title)

	var roster_row := HBoxContainer.new()
	roster_row.add_theme_constant_override("separation", 20)
	main.add_child(roster_row)
	for c in run.roster:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		roster_row.add_child(cell)
		var portrait_path := "res://assets/portraits/%s.png" % c.id
		if ResourceLoader.exists(portrait_path):
			var pt := TextureRect.new()
			pt.texture = load(portrait_path)
			pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pt.custom_minimum_size = Vector2(52, 52)
			cell.add_child(pt)
		var l := Label.new()
		l.text = "%s\n%d/%d" % [c.display_name, c.hp, c.max_hp]
		l.add_theme_color_override("font_color",
			UITheme.RED if c.hp < c.max_hp * 0.35 else Color("#c8ccd8"))
		cell.add_child(l)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#8d93a5"))
	main.add_child(status_label)

	_maybe_map_bark(roster_row)

	match run.state:
		"event":
			_build_event_panel()
		"over":
			_build_over_panel()
		_:
			_build_map()


## A rotating girl gets a word in on the map — wounded girls complain first.
func _maybe_map_bark(roster_row: HBoxContainer) -> void:
	if run.state != "map" or randf() > 0.65:
		return
	var wounded: Array = []
	var living: Array = []
	for i in run.roster.size():
		var c: Combatant = run.roster[i]
		if not c.is_alive():
			continue
		living.append(i)
		if float(c.hp) / c.max_hp < 0.35:
			wounded.append(i)
	if living.is_empty():
		return
	var idx: int
	var category: String
	if not wounded.is_empty() and randf() < 0.7:
		idx = wounded[randi() % wounded.size()]
		category = "map_low"
	else:
		idx = living[randi() % living.size()]
		category = "map"
	var girl: Combatant = run.roster[idx]
	var lines: Array = (Game.db.barks.get(girl.id, {}) as Dictionary).get(category, [])
	if lines.is_empty() or idx >= roster_row.get_child_count():
		return
	var cell: HBoxContainer = roster_row.get_child(idx)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UITheme.panel_box())
	cell.add_child(bubble)
	var bl := Label.new()
	bl.text = "\"%s\"" % lines[randi() % lines.size()]
	bl.add_theme_font_size_override("font_size", 12)
	bl.add_theme_color_override("font_color", Color(Game.db.element_colors.get(girl.element, "#c8ccd8")).lightened(0.25))
	bubble.add_child(bl)
	var tw := bubble.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(bubble, "modulate:a", 0.0, 1.0)
	tw.tween_callback(bubble.queue_free)


func _build_map() -> void:
	status_label.text = "Choose your path. (%d fights won)" % run.fights_won
	var selectable := run.selectable_nodes()
	var edges_overlay := Control.new()
	edges_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	edges_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edges_overlay)
	move_child(edges_overlay, root_margin.get_index())  # above bg layers, below the UI tree
	var map_box := VBoxContainer.new()
	map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_box.add_theme_constant_override("separation", 14)
	map_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(map_box)
	var node_buttons: Array = []
	for f in run.map.size():
		node_buttons.append([])
	for f in range(run.map.size() - 1, -1, -1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 28)
		map_box.add_child(row)
		for i in run.map[f].size():
			var node: Dictionary = run.map[f][i]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(160, 46)
			btn.text = TYPE_LABELS.get(node["type"], node["type"])
			btn.icon = UITheme.icon(node["type"])
			btn.add_theme_constant_override("icon_max_width", 24)
			btn.add_theme_constant_override("h_separation", 8)
			btn.tooltip_text = TYPE_TOOLTIPS.get(node["type"], "")
			var can_enter := false
			for s in selectable:
				if s["floor"] == f and s["index"] == i:
					can_enter = true
			if node["done"]:
				btn.text += " ✓"
			if f == run.cur_floor and i == run.cur_index:
				btn.text = "▶ " + btn.text
			btn.disabled = not can_enter
			UITheme.style_button(btn, Color(TYPE_COLORS.get(node["type"], "#ffffff")))
			if can_enter:
				var ff: int = f
				var ii: int = i
				btn.pressed.connect(func(): _enter(ff, ii))
				var pulse := btn.create_tween().set_loops()
				pulse.tween_property(btn, "modulate", Color(1.25, 1.25, 1.1), 0.6).set_trans(Tween.TRANS_SINE)
				pulse.tween_property(btn, "modulate", Color(1, 1, 1), 0.6).set_trans(Tween.TRANS_SINE)
			elif not node["done"] and f > run.cur_floor:
				btn.modulate = Color(0.7, 0.7, 0.75)
			row.add_child(btn)
			node_buttons[f].append(btn)
	_draw_edges(edges_overlay, node_buttons)


func _draw_edges(overlay: Control, node_buttons: Array) -> void:
	await get_tree().process_frame
	if not is_instance_valid(overlay):
		return
	overlay.draw.connect(func():
		for f in range(0, node_buttons.size() - 1):
			for i in node_buttons[f].size():
				var from_btn: Button = node_buttons[f][i]
				for j in run.map[f][i]["edges"]:
					if j >= node_buttons[f + 1].size():
						continue
					var to_btn: Button = node_buttons[f + 1][j]
					var p1: Vector2 = from_btn.get_global_rect().get_center() - overlay.global_position + Vector2(0, -from_btn.size.y * 0.5)
					var p2: Vector2 = to_btn.get_global_rect().get_center() - overlay.global_position + Vector2(0, to_btn.size.y * 0.5)
					var col := Color("#2c3046")  # chalk-faint future path
					var width := 2.0
					if f == run.cur_floor and i == run.cur_index:
						col = UITheme.GOLD  # the paths you can take right now
						width = 3.0
					elif run.map[f][i]["done"] and run.map[f + 1][j]["done"]:
						col = Color("#b06a3a")  # the trail you walked
						width = 3.0
					overlay.draw_line(p1, p2, col, width))
	overlay.queue_redraw()


func _enter(f: int, i: int) -> void:
	if not run.enter_node(f, i):
		return
	Game.checkpoint()
	match run.state:
		"battle":
			get_tree().change_scene_to_file("res://scenes/battle.tscn")
		_:
			_build()


func _build_event_panel() -> void:
	var ev: Dictionary = Game.db.events[run.pending_event_id]
	status_label.text = ""
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 12)
	main.add_child(panel)
	var name_l := Label.new()
	name_l.text = ev["name"]
	name_l.add_theme_font_size_override("font_size", 20)
	name_l.add_theme_color_override("font_color", UITheme.PURPLE)
	panel.add_child(name_l)
	var text_l := Label.new()
	text_l.text = ev["text"]
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(text_l)
	for ci in (ev["choices"] as Array).size():
		var choice: Dictionary = ev["choices"][ci]
		var btn := Button.new()
		btn.text = choice["label"]
		btn.custom_minimum_size = Vector2(0, 44)
		var idx := ci
		btn.pressed.connect(func():
			var msg := run.apply_event_choice(idx)
			Game.checkpoint()
			_build()
			status_label.text = msg)
		UITheme.style_button(btn, UITheme.PURPLE)
		panel.add_child(btn)


func _build_over_panel() -> void:
	status_label.text = ""
	var panel := VBoxContainer.new()
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 12)
	main.add_child(panel)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 28)
	if run.result == "victory":
		l.text = "ACT 1 CLEAR — the Colossus crumbles."
		l.add_theme_color_override("font_color", UITheme.GREEN)
	else:
		l.text = "THE PARTY HAS FALLEN"
		l.add_theme_color_override("font_color", UITheme.RED)
	panel.add_child(l)

	var stats_frame := PanelContainer.new()
	stats_frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	var stats_center := CenterContainer.new()
	stats_center.add_child(stats_frame)
	panel.add_child(stats_center)
	var stats_col := VBoxContainer.new()
	stats_col.add_theme_constant_override("separation", 4)
	stats_frame.add_child(stats_col)
	var rows := [
		["Fights won", str(run.fights_won)],
		["Rounds fought", str(int(run.stats["rounds"]))],
		["Weaknesses struck", str(int(run.stats["weak_hits"]))],
		["Probes", str(int(run.stats["probes"]))],
		["Switches", str(int(run.stats["switches"]))],
	]
	for r in rows:
		var rl := Label.new()
		rl.text = "%s:  %s" % [r[0], r[1]]
		rl.add_theme_color_override("font_color", Color("#c8ccd8"))
		stats_col.add_child(rl)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 12)
	panel.add_child(btn_row)
	var btn := Button.new()
	btn.text = "New run"
	btn.custom_minimum_size = Vector2(180, 48)
	btn.pressed.connect(func():
		Game.new_run()
		run = Game.run
		_build())
	UITheme.style_button(btn, UITheme.GOLD)
	btn_row.add_child(btn)
	var title_btn := Button.new()
	title_btn.text = "Title screen"
	title_btn.custom_minimum_size = Vector2(180, 48)
	title_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	UITheme.style_button(title_btn)
	btn_row.add_child(title_btn)
