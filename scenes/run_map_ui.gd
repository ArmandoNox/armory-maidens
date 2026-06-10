extends Control
## Greybox act map: floors bottom-up, selectable nodes light up. Also hosts the
## event panel and the run-over panel.

const TYPE_LABELS := {
	"fight": "⚔ Fight", "elite": "☠ ELITE", "rest": "✚ Rest",
	"event": "? Event", "boss": "♛ BOSS",
}
const TYPE_COLORS := {
	"fight": "#c8ccd8", "elite": "#e2543e", "rest": "#6abf6a",
	"event": "#c77dff", "boss": "#ffd24a",
}

var run: Run
var main: VBoxContainer
var status_label: Label


func _ready() -> void:
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
	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(m, 16)
	add_child(root)
	main = VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	root.add_child(main)

	var top := HBoxContainer.new()
	main.add_child(top)
	var title := Label.new()
	title.text = "ARMORY MAIDENS — Act 1"
	title.add_theme_font_size_override("font_size", 22)
	top.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var new_run := Button.new()
	new_run.text = "New Run"
	new_run.pressed.connect(func():
		Game.new_run()
		run = Game.run
		_build())
	top.add_child(new_run)

	var roster_row := HBoxContainer.new()
	roster_row.add_theme_constant_override("separation", 16)
	main.add_child(roster_row)
	for c in run.roster:
		var l := Label.new()
		l.text = "%s  %d/%d" % [c.display_name, c.hp, c.max_hp]
		l.add_theme_color_override("font_color",
			Color("#e2543e") if c.hp < c.max_hp * 0.35 else Color("#c8ccd8"))
		roster_row.add_child(l)

	status_label = Label.new()
	status_label.add_theme_color_override("font_color", Color("#8d93a5"))
	main.add_child(status_label)

	match run.state:
		"event":
			_build_event_panel()
		"over":
			_build_over_panel()
		_:
			_build_map()


func _build_map() -> void:
	status_label.text = "Choose your path. (%d fights won)" % run.fights_won
	var selectable := run.selectable_nodes()
	var map_box := VBoxContainer.new()
	map_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_box.add_theme_constant_override("separation", 10)
	map_box.alignment = BoxContainer.ALIGNMENT_CENTER
	main.add_child(map_box)
	for f in range(run.map.size() - 1, -1, -1):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 24)
		map_box.add_child(row)
		for i in run.map[f].size():
			var node: Dictionary = run.map[f][i]
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(150, 44)
			btn.text = TYPE_LABELS.get(node["type"], node["type"])
			var can_enter := false
			for s in selectable:
				if s["floor"] == f and s["index"] == i:
					can_enter = true
			if node["done"]:
				btn.text += " ✓"
			if f == run.cur_floor and i == run.cur_index:
				btn.text = "▶ " + btn.text
			btn.disabled = not can_enter
			if can_enter:
				btn.add_theme_color_override("font_color", Color(TYPE_COLORS.get(node["type"], "#ffffff")))
				var ff: int = f
				var ii: int = i
				btn.pressed.connect(func(): _enter(ff, ii))
			row.add_child(btn)


func _enter(f: int, i: int) -> void:
	if not run.enter_node(f, i):
		return
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
	name_l.add_theme_color_override("font_color", Color("#c77dff"))
	panel.add_child(name_l)
	var text_l := Label.new()
	text_l.text = ev["text"]
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(text_l)
	for ci in (ev["choices"] as Array).size():
		var choice: Dictionary = ev["choices"][ci]
		var btn := Button.new()
		btn.text = choice["label"]
		var idx := ci
		btn.pressed.connect(func():
			var msg := run.apply_event_choice(idx)
			_build()
			status_label.text = msg)
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
		l.add_theme_color_override("font_color", Color("#6abf6a"))
	else:
		l.text = "THE PARTY HAS FALLEN"
		l.add_theme_color_override("font_color", Color("#e2543e"))
	panel.add_child(l)
	var stats := Label.new()
	stats.text = "Fights won: %d" % run.fights_won
	panel.add_child(stats)
	var btn := Button.new()
	btn.text = "Start a new run"
	btn.pressed.connect(func():
		Game.new_run()
		run = Game.run
		_build())
	panel.add_child(btn)
