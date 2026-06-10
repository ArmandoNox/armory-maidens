extends Control
## Classic side-view battlefield: enemies stage left, party stage right,
## floating damage numbers, intent bubbles, armory draft on victory.
## Sprites load from res://assets/sprites/ when present; element-colored
## silhouettes otherwise. Two modes: run (from the map) or standalone picker.

var db: DataDB
var battle: Battle
var run_mode := false
var selected_slot := -1
var pending: String = ""          # "" | move_id | "ally:<move_id>" | "probe"
var log_cursor := 0
var event_cursor := 0
var battle_resolved := false
var draft_pick := ""

var top_label: Label
var battlefield: Control
var field_bg: TextureRect
var log_text: RichTextLabel
var action_box: HFlowContainer
var context_box: HBoxContainer
var pack_picker: OptionButton
var widgets := {}                 # Combatant -> Control

const PARTY_ANCHORS := [Vector2(0.64, 0.10), Vector2(0.72, 0.36), Vector2(0.80, 0.62)]
const ENEMY_ANCHORS := [Vector2(0.22, 0.10), Vector2(0.13, 0.36), Vector2(0.05, 0.62)]
const SPRITE_H := { "normal": 110.0, "elite": 150.0, "boss": 200.0, "girl": 120.0 }


func _ready() -> void:
	var game := get_node_or_null("/root/Game")
	if game != null and game.run != null and game.run.state == "battle":
		db = game.db
		run_mode = true
	else:
		db = DataDB.load_default()
	_build_layout()
	if run_mode:
		battle = Game.run.pending_battle
		_reset_view()
	else:
		_start_battle("trash_pack")


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#16181f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(m, 10)
	add_child(root)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	root.add_child(main)

	var top_row := HBoxContainer.new()
	main.add_child(top_row)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(top_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	if not run_mode:
		pack_picker = OptionButton.new()
		for pack in db.encounters:
			pack_picker.add_item(pack)
		top_row.add_child(pack_picker)
		var restart := Button.new()
		restart.text = "Restart"
		restart.pressed.connect(func(): _start_battle(pack_picker.get_item_text(pack_picker.selected)))
		top_row.add_child(restart)

	battlefield = Panel.new()
	battlefield.size_flags_vertical = Control.SIZE_EXPAND_FILL
	battlefield.size_flags_stretch_ratio = 1.35
	var field_style := StyleBoxFlat.new()
	field_style.bg_color = Color("#1d2030")
	field_style.set_corner_radius_all(8)
	battlefield.add_theme_stylebox_override("panel", field_style)
	battlefield.resized.connect(_layout_field)
	battlefield.clip_contents = true
	main.add_child(battlefield)

	field_bg = TextureRect.new()
	field_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	field_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	field_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield.add_child(field_bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.22)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield.add_child(shade)

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 12)
	main.add_child(bottom)

	var log_frame := PanelContainer.new()
	log_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_frame.size_flags_stretch_ratio = 0.8
	log_frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	bottom.add_child(log_frame)
	log_text = RichTextLabel.new()
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.scroll_following = true
	log_text.bbcode_enabled = true
	log_text.add_theme_font_size_override("normal_font_size", 13)
	log_frame.add_child(log_text)

	var command_frame := PanelContainer.new()
	command_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_frame.size_flags_stretch_ratio = 1.2
	command_frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	bottom.add_child(command_frame)
	var command := VBoxContainer.new()
	command.add_theme_constant_override("separation", 6)
	command_frame.add_child(command)
	action_box = HFlowContainer.new()
	action_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_box.add_theme_constant_override("h_separation", 6)
	action_box.add_theme_constant_override("v_separation", 6)
	command.add_child(action_box)
	context_box = HBoxContainer.new()
	context_box.add_theme_constant_override("separation", 6)
	command.add_child(context_box)


func _start_battle(pack: String) -> void:
	battle = Battle.create(db, ["kaede", "riko", "tsubaki", "mizuki"], db.encounters[pack], randi())
	_reset_view()


func _reset_view() -> void:
	var bg_name := "field"
	for e in battle.enemies:
		if db.enemies[e.id].get("tier", "normal") == "boss":
			bg_name = "boss"
	var bg_path := "res://assets/backgrounds/%s.png" % bg_name
	if ResourceLoader.exists(bg_path):
		field_bg.texture = load(bg_path)
	selected_slot = -1
	pending = ""
	log_cursor = 0
	event_cursor = battle.events.size()
	battle_resolved = false
	draft_pick = ""
	log_text.clear()
	_refresh()


## ---- Rendering ----------------------------------------------------------------

func _refresh() -> void:
	_drain_log()
	var icons_str := ""
	for i in battle.icons:
		icons_str += "◆ "
	if battle.phase == "over":
		top_label.text = "Round %d  —  %s" % [battle.round_num, battle.result.to_upper()]
	else:
		top_label.text = "Round %d   %s" % [battle.round_num, icons_str]
	_build_field()
	_drain_events()
	_render_actions()


func _drain_log() -> void:
	while log_cursor < battle.log.size():
		var line: String = battle.log[log_cursor]
		var color := "#c8ccd8"
		if "WEAK" in line or "bonus icon" in line:
			color = "#ffd24a"
		elif "RESIST" in line or "burns away" in line:
			color = "#7f8597"
		elif "Mutation" in line or "Probe" in line:
			color = "#c77dff"
		elif "VICTORY" in line:
			color = "#6abf6a"
		elif "fallen" in line or "falls" in line or "defeated" in line:
			color = "#e2543e"
		log_text.append_text("[color=%s]%s[/color]\n" % [color, line])
		log_cursor += 1


func _build_field() -> void:
	for c in widgets:
		if widgets[c].has_meta("bob"):
			(widgets[c].get_meta("bob") as Tween).kill()
		widgets[c].queue_free()
	widgets.clear()
	for slot in battle.party.size():
		var girl: Combatant = battle.party[slot]
		if girl == null:
			continue
		widgets[girl] = _combatant_widget(girl, "party", slot)
		battlefield.add_child(widgets[girl])
	for ei in battle.enemies.size():
		var e: Combatant = battle.enemies[ei]
		widgets[e] = _combatant_widget(e, "enemy", ei)
		battlefield.add_child(widgets[e])
	# Bench note, bottom-right corner of the field.
	var bench_names: Array = []
	for b in battle.bench:
		if b != null and b.is_alive():
			bench_names.append("%s %d/%d" % [b.display_name, b.hp, b.max_hp])
	if not bench_names.is_empty():
		var bench_l := Label.new()
		bench_l.name = "_bench"
		bench_l.text = "bench: " + ", ".join(bench_names)
		bench_l.add_theme_color_override("font_color", Color("#5d6275"))
		bench_l.add_theme_font_size_override("font_size", 12)
		bench_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battlefield.add_child(bench_l)
		bench_l.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 8)
	_layout_field()


func _combatant_widget(c: Combatant, side: String, idx: int) -> Control:
	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_END
	btn.add_child(box)

	var sprite_h: float = SPRITE_H["girl"]
	if side == "enemy":
		sprite_h = SPRITE_H.get(db.enemies[c.id].get("tier", "normal"), SPRITE_H["normal"])
	# A Button does not size itself to children — without this the clickable
	# rect is near-zero and nothing in the battlefield can be selected.
	btn.custom_minimum_size = Vector2(maxf(150.0, sprite_h * 1.1), sprite_h + 72.0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Intent bubble (enemies).
	if side == "enemy" and c.is_alive():
		for intent in battle.intents:
			if intent["enemy"] == idx:
				var mv: Dictionary = db.moves[intent["move"]]
				var who := "everyone"
				if intent["slot"] >= 0 and intent["slot"] < battle.party.size() and battle.party[intent["slot"]] != null:
					who = battle.party[intent["slot"]].display_name
				var il := Label.new()
				il.text = "%s → %s" % [mv["name"], who]
				il.add_theme_font_size_override("font_size", 11)
				il.add_theme_color_override("font_color", Color("#e8a04a"))
				il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				il.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(il)

	# Sprite (or element-colored silhouette).
	var sprite_path := "res://assets/sprites/%s/%s.png" % ["girls" if side == "party" else "enemies", c.id]
	if ResourceLoader.exists(sprite_path):
		var tr := TextureRect.new()
		tr.texture = load(sprite_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(sprite_h * 1.1, sprite_h)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Color(db.element_colors.get(c.element, "#9a9a9a"))
		cr.custom_minimum_size = Vector2(sprite_h * 0.55, sprite_h)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrap := CenterContainer.new()
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.custom_minimum_size = Vector2(sprite_h * 1.1, sprite_h)
		wrap.add_child(cr)
		box.add_child(wrap)

	# Name + statuses.
	var nm := Label.new()
	var status := ""
	if not c.statuses.is_empty():
		status = "  {%s}" % ", ".join(c.statuses.keys())
	var mut := ""
	if side == "enemy":
		if not c.mutations.is_empty() and c.mutation_revealed:
			var parts: Array = []
			for m in c.mutations:
				parts.append("%s:%s" % [m["key"], "W" if m["mult"] >= 1.5 else "R"])
			mut = " [%s]" % ",".join(parts)
		elif not c.mutation_revealed:
			mut = " [?]"
	nm.text = c.display_name + mut + status
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", 13)
	var name_color := Color(db.element_colors.get(c.element, "#ffffff"))
	if side == "party" and idx == selected_slot:
		name_color = Color("#ffd24a")
		nm.text = "▶ " + nm.text
	nm.add_theme_color_override("font_color", name_color)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nm)

	# HP bar.
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = c.max_hp
	bar.value = c.hp
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(sprite_h * 1.0, 10)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#101218")
	bar_bg.set_corner_radius_all(3)
	var bar_fill := StyleBoxFlat.new()
	var frac := float(c.hp) / c.max_hp
	bar_fill.bg_color = Color("#6abf6a") if frac > 0.5 else (Color("#e8c84a") if frac > 0.25 else Color("#e2543e"))
	bar_fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fill)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_wrap := CenterContainer.new()
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(bar)
	box.add_child(bar_wrap)
	var hp_l := Label.new()
	hp_l.text = "%d/%d" % [c.hp, c.max_hp]
	hp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_l.add_theme_font_size_override("font_size", 11)
	hp_l.add_theme_color_override("font_color", Color("#8d93a5"))
	hp_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_l)

	if not c.is_alive():
		btn.modulate = Color(0.55, 0.5, 0.5, 0.35)
		btn.disabled = side == "enemy"
	# Targeting glow.
	if side == "enemy" and pending != "" and not pending.begins_with("ally:") and c.is_alive():
		btn.modulate = Color(1.0, 0.75, 0.7)
	if side == "party" and pending.begins_with("ally:") and c.is_alive():
		btn.modulate = Color(0.75, 1.0, 0.8)

	if side == "party":
		var s := idx
		btn.pressed.connect(func(): _on_party_clicked(s))
	else:
		var e := idx
		btn.pressed.connect(func(): _on_enemy_clicked(e))
	return btn


func _layout_field() -> void:
	if battlefield == null:
		return
	var fs := battlefield.size
	for c in widgets:
		var w: Control = widgets[c]
		var anchors: Array
		var idx: int
		if c.side == "party":
			idx = battle.party.find(c)
			anchors = PARTY_ANCHORS
		else:
			idx = battle.enemies.find(c)
			anchors = ENEMY_ANCHORS
		if idx < 0:
			continue
		var a: Vector2 = anchors[idx % anchors.size()]
		if w.has_meta("bob"):
			(w.get_meta("bob") as Tween).kill()
		w.position = Vector2(a.x * fs.x, a.y * fs.y)
		w.reset_size()
		if c.is_alive():
			var base_y: float = w.position.y
			var half := 0.85 + randf() * 0.5
			var bob := create_tween().set_loops()
			bob.tween_property(w, "position:y", base_y - 3.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			bob.tween_property(w, "position:y", base_y + 3.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			w.set_meta("bob", bob)


func _drain_events() -> void:
	while event_cursor < battle.events.size():
		var ev: Dictionary = battle.events[event_cursor]
		event_cursor += 1
		var target: Combatant = ev["target"]
		if not widgets.has(target):
			continue
		var w: Control = widgets[target]
		# Attacker lunge toward the target.
		var actor: Combatant = ev.get("actor")
		if ev["kind"] == "hit" and actor != null and widgets.has(actor) and actor != target:
			var aw: Control = widgets[actor]
			var ax: float = aw.position.x
			var dx := -38.0 if actor.side == "party" else 38.0
			var lunge := create_tween()
			lunge.tween_property(aw, "position:x", ax + dx, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			lunge.tween_property(aw, "position:x", ax, 0.16)
		# Target flash + shake.
		var orig_mod: Color = w.modulate
		var flash := create_tween()
		flash.tween_property(w, "modulate", Color(1.7, 0.55, 0.55) if ev["kind"] == "hit" else Color(0.6, 1.6, 0.7), 0.07)
		flash.tween_property(w, "modulate", orig_mod, 0.25)
		if ev["kind"] == "hit" and ev["amount"] > 0:
			var wx: float = w.position.x
			var shake := create_tween()
			shake.tween_property(w, "position:x", wx + 7.0, 0.05)
			shake.tween_property(w, "position:x", wx - 6.0, 0.06)
			shake.tween_property(w, "position:x", wx, 0.05)
		var popup := Label.new()
		popup.add_theme_font_size_override("font_size", 22)
		if ev["kind"] == "heal":
			popup.text = "+%d" % ev["amount"]
			popup.add_theme_color_override("font_color", Color("#6abf6a"))
		else:
			match ev["tier"]:
				Rules.Tier.WEAK:
					popup.text = "-%d!" % ev["amount"]
					popup.add_theme_color_override("font_color", Color("#ffd24a"))
				Rules.Tier.RESIST:
					popup.text = "-%d" % ev["amount"]
					popup.add_theme_color_override("font_color", Color("#7f8597"))
				_:
					popup.text = "-%d" % ev["amount"]
					popup.add_theme_color_override("font_color", Color("#e2543e"))
		popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battlefield.add_child(popup)
		popup.position = w.position + Vector2(randf_range(20, 70), -6)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(popup, "position:y", popup.position.y - 44, 0.7)
		tw.tween_property(popup, "modulate:a", 0.0, 0.7).set_delay(0.15)
		tw.chain().tween_callback(popup.queue_free)


func _render_actions() -> void:
	_clear(action_box)
	_clear(context_box)
	if battle.phase == "over":
		if run_mode:
			_render_run_outcome()
		else:
			var done := Label.new()
			done.text = "Battle over — Restart or pick another pack."
			action_box.add_child(done)
		return
	if selected_slot < 0 or battle.party[selected_slot] == null or not battle.party[selected_slot].is_alive():
		var hint := Label.new()
		hint.text = "Select a girl (right side) to act — %d icons left." % battle.icons
		action_box.add_child(hint)
	else:
		var girl: Combatant = battle.party[selected_slot]
		for m in girl.all_usable_moves():
			var mv: Dictionary = db.moves[m]
			var btn := Button.new()
			var cd := int(mv.get("cooldown", 0))
			btn.text = "%s\n%s/%s  p%d%s" % [mv["name"], mv["element"], mv["phys"], int(mv["power"]), ("  cd%d" % cd) if cd > 0 else ""]
			btn.custom_minimum_size = Vector2(158, 54)
			btn.pressed.connect(func(): _on_move_clicked(m))
			UITheme.style_button(btn, Color(db.element_colors.get(mv["element"], "#c8ccd8")))
			if pending == m or pending == "ally:" + m:
				btn.add_theme_color_override("font_color", Color("#ffd24a"))
			action_box.add_child(btn)
		for m in girl.moves:
			if int(girl.cooldowns.get(m, 0)) > 0:
				var off := Button.new()
				off.text = "%s\n(cd %d)" % [db.moves[m]["name"], int(girl.cooldowns[m])]
				off.custom_minimum_size = Vector2(158, 54)
				off.disabled = true
				UITheme.style_button(off)
				action_box.add_child(off)
		if girl.actions_this_round >= Battle.MAX_ACTIONS_PER_GIRL:
			var capped := Label.new()
			capped.text = "(acted %d/%d)" % [girl.actions_this_round, Battle.MAX_ACTIONS_PER_GIRL]
			action_box.add_child(capped)

		var probe := Button.new()
		probe.text = "Probe"
		probe.custom_minimum_size = Vector2(110, 40)
		probe.pressed.connect(func(): _set_pending("probe"))
		UITheme.style_button(probe, Color("#c77dff"))
		if pending == "probe":
			probe.add_theme_color_override("font_color", Color("#ffffff"))
		context_box.add_child(probe)
		for bi in battle.bench.size():
			var bg: Combatant = battle.bench[bi]
			if bg != null and bg.is_alive():
				var sw := Button.new()
				sw.text = "Switch: %s" % bg.display_name
				sw.custom_minimum_size = Vector2(140, 40)
				var bench_index := bi
				sw.pressed.connect(func(): _do_action({ "type": "switch", "slot": selected_slot, "bench": bench_index }))
				UITheme.style_button(sw)
				context_box.add_child(sw)

	var pass_btn := Button.new()
	pass_btn.text = "End Turn"
	pass_btn.custom_minimum_size = Vector2(110, 40)
	pass_btn.pressed.connect(func(): _do_action({ "type": "pass" }))
	UITheme.style_button(pass_btn, Color("#e8a04a"))
	context_box.add_child(pass_btn)


## ---- Run mode: victory rewards / defeat ------------------------------------------

func _render_run_outcome() -> void:
	var run: Run = Game.run
	if not battle_resolved:
		battle_resolved = true
		run.on_battle_finished()
	match run.state:
		"draft":
			_render_draft(run)
		"over", "map":
			var btn := Button.new()
			btn.text = "Continue" if run.result != "defeat" else "Accept defeat"
			btn.custom_minimum_size = Vector2(220, 48)
			btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
			UITheme.style_button(btn, Color("#ffd24a"))
			action_box.add_child(btn)


func _render_draft(run: Run) -> void:
	var girl: Combatant = run.roster[run.pending_draft["girl_index"]]
	var portrait_path := "res://assets/portraits/%s.png" % girl.id
	if ResourceLoader.exists(portrait_path):
		var pt := TextureRect.new()
		pt.texture = load(portrait_path)
		pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pt.custom_minimum_size = Vector2(72, 72)
		action_box.add_child(pt)
	if draft_pick == "":
		var lbl := Label.new()
		lbl.text = "The armory offers %s a new technique:" % girl.display_name
		lbl.add_theme_color_override("font_color", Color("#ffd24a"))
		action_box.add_child(lbl)
		for offer in run.pending_draft["offers"]:
			var mv: Dictionary = db.moves[offer]
			var btn := Button.new()
			var eff: String = mv.get("effect", "")
			btn.text = "%s\n%s/%s  p%d  cd%d%s" % [mv["name"], mv["element"], mv["phys"], int(mv["power"]), int(mv.get("cooldown", 0)), ("\n[%s]" % eff) if eff != "" else ""]
			btn.custom_minimum_size = Vector2(170, 60)
			var offer_id: String = offer
			btn.pressed.connect(func():
				draft_pick = offer_id
				_refresh())
			UITheme.style_button(btn, Color(db.element_colors.get(mv["element"], "#c8ccd8")))
			context_box.add_child(btn)
		var skip := Button.new()
		skip.text = "Skip"
		skip.custom_minimum_size = Vector2(100, 60)
		skip.pressed.connect(func():
			run.apply_draft("", -1)
			get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
		UITheme.style_button(skip)
		context_box.add_child(skip)
	else:
		var lbl := Label.new()
		lbl.text = "Replace which of %s's moves with %s?" % [girl.display_name, db.moves[draft_pick]["name"]]
		lbl.add_theme_color_override("font_color", Color("#ffd24a"))
		action_box.add_child(lbl)
		for mi in girl.moves.size():
			var mv: Dictionary = db.moves[girl.moves[mi]]
			var btn := Button.new()
			btn.text = "%s\n%s/%s  p%d" % [mv["name"], mv["element"], mv["phys"], int(mv["power"])]
			btn.custom_minimum_size = Vector2(170, 60)
			var idx := mi
			btn.pressed.connect(func():
				Game.run.apply_draft(draft_pick, idx)
				get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
			UITheme.style_button(btn, Color(db.element_colors.get(mv["element"], "#c8ccd8")))
			context_box.add_child(btn)
		var back := Button.new()
		back.text = "Back"
		back.custom_minimum_size = Vector2(100, 60)
		back.pressed.connect(func():
			draft_pick = ""
			_refresh())
		UITheme.style_button(back)
		context_box.add_child(back)


## ---- Input flow -----------------------------------------------------------------

func _on_party_clicked(slot: int) -> void:
	if pending.begins_with("ally:") and selected_slot >= 0:
		var move_id := pending.substr(5)
		_do_action({ "type": "attack", "actor": selected_slot, "move": move_id, "target": slot })
		return
	selected_slot = slot
	pending = ""
	_refresh()


func _set_pending(p: String) -> void:
	pending = p
	_refresh()


func _on_move_clicked(move_id: String) -> void:
	var mv: Dictionary = db.moves[move_id]
	match mv.get("target", "enemy"):
		"enemy":
			_set_pending(move_id)
		"all_enemies":
			_do_action({ "type": "attack", "actor": selected_slot, "move": move_id, "target": -1 })
		"self", "party":
			_do_action({ "type": "attack", "actor": selected_slot, "move": move_id, "target": selected_slot })
		"ally":
			_set_pending("ally:" + move_id)


func _on_enemy_clicked(ei: int) -> void:
	if selected_slot < 0:
		return
	if pending == "probe":
		_do_action({ "type": "probe", "actor": selected_slot, "target": ei })
	elif pending != "" and not pending.begins_with("ally:"):
		_do_action({ "type": "attack", "actor": selected_slot, "move": pending, "target": ei })


func _do_action(action: Dictionary) -> void:
	pending = ""
	battle.player_action(action)
	if battle.phase != "over":
		if selected_slot >= 0:
			var g: Combatant = battle.party[selected_slot]
			if g == null or not g.is_alive() or g.actions_this_round >= Battle.MAX_ACTIONS_PER_GIRL:
				selected_slot = -1
	_refresh()


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
		node.remove_child(child)
