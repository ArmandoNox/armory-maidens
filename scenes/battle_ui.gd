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
var icons_label: Label
var battlefield: Control
var field_root: Control           # shake/zoom target: bg + widgets + popups live here
var field_bg: TextureRect
var rim: Panel                    # screen-edge tier flash
var forge_box: HBoxContainer      # the Icon Forge: physical action diamonds
var ticker_box: VBoxContainer     # 3-line fading combat ticker on the field
var log_overlay: Control          # full history, hidden behind the Log button
var log_text: RichTextLabel
var action_box: HFlowContainer
var context_box: HBoxContainer
var detail_box: VBoxContainer
var pack_picker: OptionButton
var widgets := {}                 # Combatant -> Control
var outcome_staged := false       # victory/defeat staging runs once
var outcome_nodes: Array = []     # stamps/tallies swept on restart
var _stop_until_ms := 0           # hit-stop guard (real time)

# x = fraction of field width; y = fraction of AVAILABLE height (field height
# minus the widget's own height), so name/HP labels can never clip under the
# bottom menu no matter how the panels resize.
const PARTY_ANCHORS := [Vector2(0.64, 0.04), Vector2(0.72, 0.50), Vector2(0.80, 0.96)]
const ENEMY_ANCHORS := [Vector2(0.22, 0.04), Vector2(0.13, 0.50), Vector2(0.05, 0.96)]
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
		if not bool(Game.setting("help_seen", false)):
			Game.set_setting("help_seen", true)
			HelpOverlay.popup(self)
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
	top_row.add_theme_constant_override("separation", 12)
	main.add_child(top_row)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(top_label)
	icons_label = Label.new()
	icons_label.add_theme_font_size_override("font_size", 20)
	icons_label.add_theme_color_override("font_color", UITheme.GOLD)
	top_row.add_child(icons_label)
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
		UITheme.style_button(restart)
		top_row.add_child(restart)
	var log_btn := Button.new()
	log_btn.text = "Log"
	log_btn.custom_minimum_size = Vector2(56, 32)
	log_btn.tooltip_text = "Full battle history"
	log_btn.pressed.connect(func(): log_overlay.visible = not log_overlay.visible)
	UITheme.style_button(log_btn)
	top_row.add_child(log_btn)
	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.custom_minimum_size = Vector2(36, 32)
	help_btn.tooltip_text = "How to play"
	help_btn.pressed.connect(func(): HelpOverlay.popup(self))
	UITheme.style_button(help_btn, UITheme.PURPLE)
	top_row.add_child(help_btn)

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

	field_root = Control.new()
	field_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	battlefield.add_child(field_root)

	field_bg = TextureRect.new()
	field_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	field_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	field_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	field_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	field_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_root.add_child(field_bg)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.22)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_root.add_child(shade)

	# CRT warmth on the field only: scanlines + vignette, UI stays crisp.
	var crt := ColorRect.new()
	crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_mat := ShaderMaterial.new()
	var crt_sh := Shader.new()
	crt_sh.code = """
shader_type canvas_item;
void fragment() {
	float scan = step(0.5, fract(UV.y * 180.0)) * 0.045;
	vec2 c = UV - vec2(0.5);
	float vig = smoothstep(0.62, 0.95, length(c)) * 0.30;
	COLOR = vec4(0.0, 0.0, 0.0, scan + vig);
}
"""
	crt_mat.shader = crt_sh
	crt.material = crt_mat
	battlefield.add_child(crt)

	# Tier rim: a border-only panel flashed gold on WEAK / violet on reveals.
	rim = Panel.new()
	rim.set_anchors_preset(Control.PRESET_FULL_RECT)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_sb := StyleBoxFlat.new()
	rim_sb.draw_center = false
	rim_sb.border_color = Color(1, 1, 1)
	rim_sb.set_border_width_all(5)
	rim_sb.set_corner_radius_all(8)
	rim.add_theme_stylebox_override("panel", rim_sb)
	rim.modulate.a = 0.0
	battlefield.add_child(rim)

	# The Icon Forge: the press-turn economy as physical diamonds in a rack.
	forge_box = HBoxContainer.new()
	forge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	forge_box.add_theme_constant_override("separation", 6)
	battlefield.add_child(forge_box)
	forge_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	forge_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	forge_box.position.y = 10

	# Two-line fading ticker replaces the old log panel; history lives in the overlay.
	ticker_box = VBoxContainer.new()
	ticker_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker_box.add_theme_constant_override("separation", 0)
	ticker_box.alignment = BoxContainer.ALIGNMENT_END
	battlefield.add_child(ticker_box)
	ticker_box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	ticker_box.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# Tapping empty battlefield cancels the pending move / deselects.
	battlefield.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and battle != null and battle.phase != "over":
			if pending != "":
				pending = ""
				_refresh()
			elif selected_slot >= 0:
				selected_slot = -1
				_refresh())

	var bottom := HBoxContainer.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.add_theme_constant_override("separation", 10)
	main.add_child(bottom)

	var command_frame := PanelContainer.new()
	command_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	command_frame.size_flags_stretch_ratio = 1.5
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

	var detail_frame := PanelContainer.new()
	detail_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_frame.size_flags_stretch_ratio = 1.0
	detail_frame.add_theme_stylebox_override("panel", UITheme.panel_box(Color("#101230")))
	bottom.add_child(detail_frame)
	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 4)
	detail_frame.add_child(detail_box)

	# Full battle history — hidden overlay, toggled by the Log button.
	log_overlay = Control.new()
	log_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_overlay.visible = false
	log_overlay.z_index = 60
	add_child(log_overlay)
	var log_dim := ColorRect.new()
	log_dim.color = Color(0, 0, 0, 0.55)
	log_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	log_overlay.add_child(log_dim)
	log_dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			log_overlay.visible = false)
	var log_frame := PanelContainer.new()
	log_frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	log_frame.set_anchors_preset(Control.PRESET_CENTER)
	log_frame.custom_minimum_size = Vector2(640, 420)
	log_overlay.add_child(log_frame)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.bbcode_enabled = true
	log_text.add_theme_font_size_override("normal_font_size", 13)
	log_frame.add_child(log_text)


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
	outcome_staged = false
	for n in outcome_nodes:
		if is_instance_valid(n):
			n.queue_free()
	outcome_nodes.clear()
	field_root.modulate = Color(1, 1, 1)
	log_text.clear()
	_refresh()


## ---- Rendering ----------------------------------------------------------------

func _refresh() -> void:
	_drain_log()
	if battle.phase == "over":
		top_label.text = "Round %d  —  %s" % [battle.round_num, battle.result.to_upper()]
		icons_label.text = ""
	else:
		top_label.text = "Round %d" % battle.round_num
		icons_label.text = ""
	_build_forge()
	_build_field()
	_drain_events()
	if battle.phase == "over" and not outcome_staged:
		outcome_staged = true
		_stage_outcome()
	_render_actions()
	_render_detail_default()


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
		_ticker_line(line, Color(color))
		log_cursor += 1


## One fading ticker line on the field; keeps at most 3 visible.
func _ticker_line(line: String, color: Color) -> void:
	while ticker_box.get_child_count() >= 3:
		var oldest := ticker_box.get_child(0)
		ticker_box.remove_child(oldest)
		oldest.queue_free()
	var l := Label.new()
	l.text = line
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticker_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(3.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


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
		field_root.add_child(widgets[girl])
	for ei in battle.enemies.size():
		var e: Combatant = battle.enemies[ei]
		widgets[e] = _combatant_widget(e, "enemy", ei)
		field_root.add_child(widgets[e])
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
		field_root.add_child(bench_l)
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
	btn.custom_minimum_size = Vector2(maxf(150.0, sprite_h * 1.1), sprite_h + 84.0)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Intent chip (enemies): element + phys icons → target portrait, not a sentence.
	if side == "enemy" and c.is_alive():
		for intent in battle.intents:
			if intent["enemy"] == idx:
				var mv: Dictionary = db.moves[intent["move"]]
				var chip := HBoxContainer.new()
				chip.alignment = BoxContainer.ALIGNMENT_CENTER
				chip.add_theme_constant_override("separation", 3)
				chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chip.add_child(UITheme.icon_rect(mv["element"], 18, Color(db.element_colors.get(mv["element"], "#5d6275"))))
				chip.add_child(UITheme.icon_rect(mv["phys"], 18))
				var arrow := Label.new()
				arrow.text = "→"
				arrow.add_theme_font_size_override("font_size", 12)
				arrow.add_theme_color_override("font_color", Color("#e8a04a"))
				arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chip.add_child(arrow)
				var tgt_slot: int = intent["slot"]
				var tgt: Combatant = null
				if tgt_slot >= 0 and tgt_slot < battle.party.size():
					tgt = battle.party[tgt_slot]
				if tgt == null:
					var all_l := Label.new()
					all_l.text = "ALL"
					all_l.add_theme_font_size_override("font_size", 11)
					all_l.add_theme_color_override("font_color", Color("#e8a04a"))
					all_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
					chip.add_child(all_l)
				else:
					var pp := "res://assets/portraits/%s.png" % tgt.id
					if ResourceLoader.exists(pp):
						var mini := TextureRect.new()
						mini.texture = load(pp)
						mini.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
						mini.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
						mini.custom_minimum_size = Vector2(20, 20)
						mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
						chip.add_child(mini)
					else:
						var nm_l := Label.new()
						nm_l.text = tgt.display_name
						nm_l.add_theme_font_size_override("font_size", 11)
						nm_l.add_theme_color_override("font_color", Color("#e8a04a"))
						nm_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
						chip.add_child(nm_l)
				box.add_child(chip)
				var pulse := chip.create_tween().set_loops()
				pulse.tween_property(chip, "modulate:a", 0.5, 0.55).set_trans(Tween.TRANS_SINE)
				pulse.tween_property(chip, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)

	# Predicted tier badge while the player is aiming a move.
	if side == "enemy" and c.is_alive() and pending != "" and pending != "probe" and not pending.begins_with("ally:"):
		var pmv: Dictionary = db.moves[pending]
		var bmult := Rules.believed_mult(db, pmv["element"], pmv["phys"], c)
		var btier := Rules.tier_of(bmult)
		var badge := Label.new()
		badge.text = "%s ×%.2f%s" % [Rules.tier_name(btier), bmult, "" if c.mutation_revealed else " ?"]
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", UITheme.tier_color(btier))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(badge)

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
		btn.set_meta("sprite_tr", tr)
		btn.set_meta("idle_tex", tr.texture)
		if side == "party":
			var atk_path := "res://assets/sprites/girls/%s_attack.png" % c.id
			if ResourceLoader.exists(atk_path):
				btn.set_meta("attack_tex", load(atk_path))
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
		name_color = UITheme.GOLD
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

	# Unprobed enemies glitch — a periodic violet palette flicker you can SEE
	# and itch to resolve. Probing stops it.
	if side == "enemy" and c.is_alive() and not c.mutation_revealed:
		var flick: CanvasItem = btn.get_meta("sprite_tr") if btn.has_meta("sprite_tr") else box
		var fl := flick.create_tween().set_loops()
		fl.tween_interval(2.2 + randf() * 1.8)
		fl.tween_property(flick, "self_modulate", Color(1.45, 0.8, 1.55), 0.06)
		fl.tween_property(flick, "self_modulate", Color(1, 1, 1), 0.10)

	if side == "party":
		var s := idx
		btn.pressed.connect(func(): _on_party_clicked(s))
		btn.mouse_entered.connect(func(): _render_detail_girl(c))
	else:
		var e := idx
		btn.pressed.connect(func(): _on_enemy_clicked(e))
		btn.mouse_entered.connect(func(): _render_detail_enemy(c))
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
		w.reset_size()
		var wh: float = maxf(w.size.y, w.custom_minimum_size.y)
		var ww: float = maxf(w.size.x, w.custom_minimum_size.x)
		var x: float = clampf(a.x * fs.x, 4.0, maxf(4.0, fs.x - ww - 4.0))
		var y: float = 6.0 + a.y * maxf(0.0, fs.y - wh - 12.0)
		w.position = Vector2(x, y)
		if c.is_alive():
			var base_y: float = w.position.y
			var half := 0.85 + randf() * 0.5
			var bob := w.create_tween().set_loops()
			bob.tween_property(w, "position:y", base_y - 3.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			bob.tween_property(w, "position:y", base_y + 3.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			w.set_meta("bob", bob)


## ---- The Icon Forge ---------------------------------------------------------------

func _build_forge() -> void:
	for ch in forge_box.get_children():
		ch.queue_free()
		forge_box.remove_child(ch)
	if battle.phase == "over":
		return
	for i in battle.icons:
		forge_box.add_child(_forge_diamond())
	forge_box.reset_size()


## A forged-metal action diamond (rotated square, gold face, dark edge).
func _forge_diamond(face := Color("#ffd24a")) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(22, 22)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := ColorRect.new()
	edge.color = Color("#6a5012")
	edge.size = Vector2(16, 16)
	edge.position = Vector2(11, -1)
	edge.rotation_degrees = 45
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(edge)
	var d := ColorRect.new()
	d.color = face
	d.size = Vector2(12, 12)
	d.position = Vector2(11, 2)
	d.rotation_degrees = 45
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(d)
	return slot


## ---- FX ------------------------------------------------------------------------

func _drain_events() -> void:
	while event_cursor < battle.events.size():
		var ev: Dictionary = battle.events[event_cursor]
		event_cursor += 1
		match ev["kind"]:
			"hit":
				_fx_hit(ev)
			"heal":
				_fx_heal(ev)
			"icon":
				_fx_icon(ev)
			"switch":
				_fx_switch(ev)


func _fx_hit(ev: Dictionary) -> void:
	var target: Combatant = ev["target"]
	if not widgets.has(target):
		return
	var w: Control = widgets[target]
	# Attacker lunge toward the target, swapping to her attack pose if we have one.
	var actor: Combatant = ev.get("actor")
	if actor != null and widgets.has(actor) and actor != target:
		var aw: Control = widgets[actor]
		var ax: float = aw.position.x
		var dx := -38.0 if actor.side == "party" else 38.0
		if aw.has_meta("attack_tex") and aw.has_meta("sprite_tr"):
			var tr: TextureRect = aw.get_meta("sprite_tr")
			tr.texture = aw.get_meta("attack_tex")
			var restore := aw.create_tween()
			restore.tween_interval(0.42)
			restore.tween_callback(func():
				if is_instance_valid(tr) and aw.has_meta("idle_tex"):
					tr.texture = aw.get_meta("idle_tex"))
		var lunge := create_tween()
		lunge.tween_property(aw, "position:x", ax + dx, 0.10).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lunge.tween_property(aw, "position:x", ax, 0.16)
	# Target flash + shake.
	var orig_mod: Color = w.modulate
	var flash := create_tween()
	flash.tween_property(w, "modulate", Color(1.7, 0.55, 0.55), 0.07)
	flash.tween_property(w, "modulate", orig_mod, 0.25)
	if ev["amount"] > 0:
		var wx: float = w.position.x
		var shake := create_tween()
		shake.tween_property(w, "position:x", wx + 7.0, 0.05)
		shake.tween_property(w, "position:x", wx - 6.0, 0.06)
		shake.tween_property(w, "position:x", wx, 0.05)
	# Tier is FELT before the number is read: hit-stop + punch-zoom on WEAK,
	# a flat desaturated dip on RESIST, shake on anything heavy.
	if ev["tier"] == Rules.Tier.WEAK:
		_hit_stop(0.14)
		_punch_zoom(w)
		_rim_flash(UITheme.GOLD)
		_screen_shake(6.0)
	elif ev["tier"] == Rules.Tier.RESIST:
		var dip := create_tween()
		dip.tween_property(field_root, "modulate", Color(0.72, 0.72, 0.80), 0.06)
		dip.tween_property(field_root, "modulate", Color(1, 1, 1), 0.22)
	else:
		if ev["amount"] > 0:
			_hit_stop(0.06)
		if ev["amount"] >= 30:
			_screen_shake(4.0)
	# KO: the fallen one drops out of frame.
	if not target.is_alive():
		var fall := create_tween()
		fall.set_parallel(true)
		fall.tween_property(w, "position:y", w.position.y + 26.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		fall.tween_property(w, "modulate:a", 0.25, 0.5)
		fall.tween_property(w, "rotation_degrees", -10.0 if target.side == "enemy" else 10.0, 0.5)
	_damage_popup(w, ev)


## Numbers with mass: spawn oversized, overshoot-shrink, then gravity-arc off.
## Resisted numbers are small, grey, and barely lift — almost ashamed.
func _damage_popup(w: Control, ev: Dictionary) -> void:
	var popup := Label.new()
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	popup.add_theme_constant_override("outline_size", 6)
	var arc := 36.0
	match ev["tier"]:
		Rules.Tier.WEAK:
			popup.text = "-%d  WEAK!" % ev["amount"]
			popup.add_theme_font_size_override("font_size", 34)
			popup.add_theme_color_override("font_color", UITheme.GOLD)
			arc = 52.0
		Rules.Tier.RESIST:
			popup.text = "-%d" % ev["amount"]
			popup.add_theme_font_size_override("font_size", 14)
			popup.add_theme_color_override("font_color", UITheme.GREY)
			arc = 10.0
		_:
			popup.text = "-%d" % ev["amount"]
			popup.add_theme_font_size_override("font_size", 23)
			popup.add_theme_color_override("font_color", UITheme.RED)
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_root.add_child(popup)
	popup.position = w.position + Vector2(randf_range(16, 56), 4)
	popup.scale = Vector2(2.1, 2.1)
	popup.pivot_offset = Vector2(20, 12)
	var drift_x := randf_range(14.0, 30.0) * (1.0 if randf() < 0.5 else -1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(popup, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(popup, "position:y", popup.position.y - arc, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(popup, "position:x", popup.position.x + drift_x, 0.85)
	tw.chain().tween_property(popup, "position:y", popup.position.y + 26.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(popup, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(popup.queue_free)


func _fx_heal(ev: Dictionary) -> void:
	var target: Combatant = ev["target"]
	if not widgets.has(target):
		return
	var w: Control = widgets[target]
	var orig_mod: Color = w.modulate
	var flash := create_tween()
	flash.tween_property(w, "modulate", Color(0.6, 1.6, 0.7), 0.07)
	flash.tween_property(w, "modulate", orig_mod, 0.25)
	var popup := Label.new()
	popup.add_theme_font_size_override("font_size", 22)
	popup.text = "+%d" % ev["amount"]
	popup.add_theme_color_override("font_color", UITheme.GREEN)
	_float_popup(popup, w.position + Vector2(randf_range(20, 70), -6))


## The icon economy made physical: a mint flies a molten diamond from the
## striker to the forge rack; a burn cracks diamonds off the rack as shards.
func _fx_icon(ev: Dictionary) -> void:
	var actor: Combatant = ev.get("actor")
	var pos := Vector2(battlefield.size.x * 0.42, battlefield.size.y * 0.12)
	if actor != null and widgets.has(actor):
		pos = (widgets[actor] as Control).position + Vector2(0, -26)
	var rack_pos: Vector2 = forge_box.position + Vector2(forge_box.size.x * 0.5, 10.0)
	var popup := Label.new()
	popup.add_theme_font_size_override("font_size", 17)
	popup.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	popup.add_theme_constant_override("outline_size", 4)
	if int(ev["amount"]) > 0:
		popup.text = "WEAK — icon refunded"
		popup.add_theme_color_override("font_color", UITheme.GOLD)
		# Molten diamond flies from the striker's position into the rack.
		var fly := _forge_diamond(Color("#ffe9a0"))
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		field_root.add_child(fly)
		fly.position = pos + Vector2(30, 20)
		fly.scale = Vector2(1.6, 1.6)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(fly, "position", rack_pos, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(fly, "scale", Vector2.ONE, 0.45)
		tw.chain().tween_callback(func():
			if is_instance_valid(fly):
				fly.queue_free()
			if is_instance_valid(forge_box):
				var fl := create_tween()
				fl.tween_property(forge_box, "modulate", Color(1.8, 1.6, 0.9), 0.08)
				fl.tween_property(forge_box, "modulate", Color(1, 1, 1), 0.3))
	else:
		popup.text = "RESISTED — icons burned"
		popup.add_theme_color_override("font_color", UITheme.GREY)
		# Two diamonds crack off the rack and fall as shards.
		for i in 2:
			var shard := _forge_diamond(Color("#5a5e75"))
			shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
			field_root.add_child(shard)
			shard.position = rack_pos + Vector2(i * 14.0 - 7.0, 0)
			var st := create_tween()
			st.set_parallel(true)
			st.tween_property(shard, "position:y", shard.position.y + 70.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			st.tween_property(shard, "position:x", shard.position.x + randf_range(-18.0, 18.0), 0.6)
			st.tween_property(shard, "rotation_degrees", randf_range(-120.0, 120.0), 0.6)
			st.tween_property(shard, "modulate:a", 0.0, 0.6)
			st.chain().tween_callback(shard.queue_free)
		var rfl := create_tween()
		rfl.tween_property(forge_box, "modulate", Color(0.6, 0.6, 0.7), 0.08)
		rfl.tween_property(forge_box, "modulate", Color(1, 1, 1), 0.35)
	_float_popup(popup, pos, 1.0)


func _fx_switch(ev: Dictionary) -> void:
	var incoming: Combatant = ev["target"]
	if not widgets.has(incoming):
		return
	var w: Control = widgets[incoming]
	var dest_x: float = w.position.x
	w.position.x = battlefield.size.x + 40.0
	w.modulate = Color(1.4, 1.4, 1.1)
	var slide := create_tween()
	slide.tween_property(w, "position:x", dest_x, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	slide.parallel().tween_property(w, "modulate", Color(1, 1, 1), 0.45)


func _float_popup(popup: Label, pos: Vector2, dur := 0.7) -> void:
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field_root.add_child(popup)
	popup.position = pos
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(popup, "position:y", popup.position.y - 44, dur)
	tw.tween_property(popup, "modulate:a", 0.0, dur).set_delay(0.15)
	tw.chain().tween_callback(popup.queue_free)


func _screen_shake(strength: float) -> void:
	var tw := create_tween()
	tw.tween_property(field_root, "position", Vector2(strength, -strength * 0.4), 0.04)
	tw.tween_property(field_root, "position", Vector2(-strength * 0.7, strength * 0.3), 0.05)
	tw.tween_property(field_root, "position", Vector2(strength * 0.4, 0), 0.04)
	tw.tween_property(field_root, "position", Vector2.ZERO, 0.05)


## Frame-freeze standing in for impact audio. Real-time guarded so overlapping
## events extend rather than stack.
func _hit_stop(duration: float) -> void:
	var now := Time.get_ticks_msec()
	var until := now + int(duration * 1000.0)
	if until <= _stop_until_ms:
		return
	_stop_until_ms = until
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(duration, true, false, true)  # ignores time_scale
	t.timeout.connect(func():
		if Time.get_ticks_msec() >= _stop_until_ms - 5:
			Engine.time_scale = 1.0)


func _punch_zoom(target: Control) -> void:
	field_root.pivot_offset = target.position + target.size * 0.5
	var tw := create_tween()
	tw.tween_property(field_root, "scale", Vector2(1.06, 1.06), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(field_root, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _rim_flash(color: Color, peak := 0.85) -> void:
	rim.self_modulate = color
	var tw := create_tween()
	tw.tween_property(rim, "modulate:a", peak, 0.05)
	tw.tween_property(rim, "modulate:a", 0.0, 0.45)


## ---- Outcome staging --------------------------------------------------------------

## Victory: time-dilated tableau — attack poses + stamped VICTORY + stat count-up.
## Defeat: the field goes dark, embers rise, the verdict stamps in letter by letter.
func _stage_outcome() -> void:
	if battle.result == "victory":
		for c in battle.party:
			if c == null or not widgets.has(c):
				continue
			var w: Control = widgets[c]
			if w.has_meta("attack_tex") and w.has_meta("sprite_tr"):
				(w.get_meta("sprite_tr") as TextureRect).texture = w.get_meta("attack_tex")
		_rim_flash(UITheme.GOLD)
		var stamp := _stamp_label("VICTORY", UITheme.GOLD, 54)
		stamp.scale = Vector2(3.0, 3.0)
		var tw := create_tween()
		tw.tween_property(stamp, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): _screen_shake(5.0))
		# Stat tally counts up with escalating ticks.
		var tally := Label.new()
		tally.add_theme_font_size_override("font_size", 16)
		tally.add_theme_color_override("font_color", Color("#c8ccd8"))
		tally.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		tally.add_theme_constant_override("outline_size", 5)
		tally.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tally.mouse_filter = Control.MOUSE_FILTER_IGNORE
		battlefield.add_child(tally)
		tally.set_anchors_preset(Control.PRESET_CENTER)
		tally.position += Vector2(-160, 44)
		tally.custom_minimum_size = Vector2(320, 0)
		outcome_nodes.append(tally)
		var wk := int(battle.stats["weak_hits"])
		var rd := int(battle.stats["rounds"])
		var sw := int(battle.stats["switches"])
		var tick := func(t: float):
			if is_instance_valid(tally):
				tally.text = "weak hits %d   rounds %d   switches %d" % [roundi(wk * t), roundi(rd * t), roundi(sw * t)]
		var count := create_tween()
		count.tween_method(tick, 0.0, 1.0, 0.9).set_delay(0.25)
	else:
		var dip := create_tween()
		dip.tween_property(field_root, "modulate", Color(0.40, 0.38, 0.46), 1.2)
		var stamp := _stamp_label("THE PARTY HAS FALLEN", UITheme.RED, 40)
		stamp.visible_characters = 0
		var tw := create_tween()
		tw.tween_property(stamp, "visible_characters", stamp.text.length(), 1.5).set_delay(0.4)
		for i in 14:
			var ember := ColorRect.new()
			ember.color = Color("#e2543e") if i % 3 != 0 else Color("#e8a04a")
			var s := 2.0 + randf() * 3.0
			ember.size = Vector2(s, s)
			ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
			field_root.add_child(ember)
			ember.position = Vector2(randf() * battlefield.size.x, battlefield.size.y * (0.55 + randf() * 0.4))
			ember.modulate.a = 0.0
			var et := ember.create_tween()
			et.tween_interval(randf() * 1.2)
			et.tween_property(ember, "modulate:a", 0.9, 0.3)
			et.parallel().tween_property(ember, "position:y", ember.position.y - (60.0 + randf() * 120.0), 2.4 + randf() * 1.5)
			et.parallel().tween_property(ember, "position:x", ember.position.x + randf_range(-24.0, 24.0), 2.6)
			et.tween_property(ember, "modulate:a", 0.0, 0.6)
			et.tween_callback(ember.queue_free)


func _stamp_label(text: String, color: Color, size: int) -> Label:
	var stamp := Label.new()
	stamp.text = text
	stamp.add_theme_font_size_override("font_size", size)
	stamp.add_theme_color_override("font_color", color)
	stamp.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.92))
	stamp.add_theme_constant_override("outline_size", 8)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battlefield.add_child(stamp)
	stamp.set_anchors_preset(Control.PRESET_CENTER)
	stamp.reset_size()
	stamp.position -= stamp.size * 0.5
	stamp.pivot_offset = stamp.size * 0.5
	outcome_nodes.append(stamp)
	return stamp


## ---- Command deck ----------------------------------------------------------------

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
			action_box.add_child(_move_button(m, girl))
		for m in girl.moves:
			if int(girl.cooldowns.get(m, 0)) > 0:
				action_box.add_child(_cooldown_button(m, int(girl.cooldowns[m])))
		if girl.actions_this_round >= Battle.MAX_ACTIONS_PER_GIRL:
			var capped := Label.new()
			capped.text = "(acted %d/%d)" % [girl.actions_this_round, Battle.MAX_ACTIONS_PER_GIRL]
			action_box.add_child(capped)

		var probe := Button.new()
		probe.text = "Probe"
		probe.icon = UITheme.icon("probe")
		probe.add_theme_constant_override("icon_max_width", 20)
		probe.tooltip_text = "Spend 1 icon: reveal this enemy's hidden mutation."
		probe.custom_minimum_size = Vector2(110, 40)
		probe.pressed.connect(func(): _set_pending("probe"))
		UITheme.style_button(probe, UITheme.PURPLE)
		if pending == "probe":
			probe.add_theme_color_override("font_color", Color("#ffffff"))
		context_box.add_child(probe)
		for bi in battle.bench.size():
			var bg: Combatant = battle.bench[bi]
			if bg != null and bg.is_alive():
				var sw := Button.new()
				sw.text = "Switch: %s" % bg.display_name
				sw.icon = UITheme.icon("switch")
				sw.add_theme_constant_override("icon_max_width", 20)
				sw.tooltip_text = "1 icon. %s takes this slot — and the hit aimed at it. Trigger: %s" % [bg.display_name, db.girls[bg.id].get("trigger_desc", "")]
				sw.custom_minimum_size = Vector2(150, 40)
				var bench_index := bi
				sw.pressed.connect(func(): _do_action({ "type": "switch", "slot": selected_slot, "bench": bench_index }))
				UITheme.style_button(sw)
				context_box.add_child(sw)

	var pass_btn := Button.new()
	pass_btn.text = "End Turn"
	pass_btn.tooltip_text = "Yield your remaining icons; the enemies act."
	pass_btn.custom_minimum_size = Vector2(110, 40)
	pass_btn.pressed.connect(func(): _do_action({ "type": "pass" }))
	UITheme.style_button(pass_btn, Color("#e8a04a"))
	context_box.add_child(pass_btn)


## A framed JRPG command entry: element + phys icons, name, power/cd line.
func _move_button(move_id: String, girl: Combatant) -> Button:
	var mv: Dictionary = db.moves[move_id]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(172, 56)
	UITheme.style_button(btn, Color(db.element_colors.get(mv["element"], "#c8ccd8")))
	if pending == move_id or pending == "ally:" + move_id:
		btn.add_theme_color_override("font_color", UITheme.GOLD)

	# Heat-edge: a slim element-colored blade edge with a slow idle shimmer.
	var edge := ColorRect.new()
	edge.color = Color(db.element_colors.get(mv["element"], "#5d6275"))
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(edge)
	edge.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	edge.offset_left = 1
	edge.offset_right = 4
	edge.offset_top = 2
	edge.offset_bottom = -2
	var shimmer := edge.create_tween().set_loops()
	shimmer.tween_property(edge, "modulate:a", 0.45, 1.1 + randf() * 0.5).set_trans(Tween.TRANS_SINE)
	shimmer.tween_property(edge, "modulate:a", 1.0, 1.1 + randf() * 0.5).set_trans(Tween.TRANS_SINE)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 9
	row.add_theme_constant_override("separation", 6)
	btn.add_child(row)
	var icon_col := VBoxContainer.new()
	icon_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_col.alignment = BoxContainer.ALIGNMENT_CENTER
	icon_col.add_theme_constant_override("separation", 2)
	row.add_child(icon_col)
	icon_col.add_child(UITheme.icon_rect(mv["element"], 20, Color(db.element_colors.get(mv["element"], "#5d6275"))))
	icon_col.add_child(UITheme.icon_rect(mv["phys"], 20))
	var text_col := VBoxContainer.new()
	text_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.alignment = BoxContainer.ALIGNMENT_CENTER
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_col)
	var name_l := Label.new()
	name_l.text = mv["name"]
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.add_theme_color_override("font_color", Color(db.element_colors.get(mv["element"], "#c8ccd8")))
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(name_l)
	var sub := Label.new()
	var bits: Array = []
	if int(mv["power"]) > 0:
		bits.append("PWR %d" % int(mv["power"]))
	if int(mv.get("hits", 1)) > 1:
		bits.append("×%d" % int(mv["hits"]))
	if int(mv.get("cooldown", 0)) > 0:
		bits.append("CD %d" % int(mv["cooldown"]))
	if mv.has("effect"):
		bits.append("✦")
	sub.text = " · ".join(bits) if not bits.is_empty() else "support"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color("#8d93a5"))
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_col.add_child(sub)

	btn.pressed.connect(func(): _on_move_clicked(move_id))
	btn.mouse_entered.connect(func(): _render_detail_move(move_id))
	return btn


func _cooldown_button(move_id: String, rounds_left: int) -> Button:
	var mv: Dictionary = db.moves[move_id]
	var btn := Button.new()
	btn.text = "%s\nready in %d" % [mv["name"], rounds_left]
	btn.custom_minimum_size = Vector2(172, 56)
	btn.disabled = true
	UITheme.style_button(btn)
	btn.mouse_entered.connect(func(): _render_detail_move(move_id))
	return btn


## ---- Detail panel -----------------------------------------------------------------

func _render_detail_default() -> void:
	if battle.phase == "over":
		_detail_lines("", [])
		return
	if pending != "" and pending != "probe" and not pending.begins_with("ally:"):
		_render_detail_move(pending)
	elif pending == "probe":
		_detail_lines("PROBE", [
			["Click an enemy to scan it.", Color("#c8ccd8")],
			["Costs 1 icon. Reveals its hidden affinity mutation — [?] enemies may not be what the chart says.", Color("#8d93a5")],
		])
	elif selected_slot >= 0 and battle.party[selected_slot] != null:
		_render_detail_girl(battle.party[selected_slot])
	else:
		_detail_lines("TACTICS", [
			["Hover a move to preview its tier vs each enemy.", Color("#c8ccd8")],
			["WEAK hits refund the icon (free action). RESIST hits burn 2.", Color("#8d93a5")],
			["weak × resist cancel out — element AND physical type both matter.", Color("#8d93a5")],
		])


func _render_detail_move(move_id: String) -> void:
	if not db.moves.has(move_id):
		return
	var mv: Dictionary = db.moves[move_id]
	var lines: Array = []
	lines.append([mv.get("desc", ""), Color("#c8ccd8")])
	var meta_bits: Array = ["%s / %s" % [mv["element"], mv["phys"]]]
	if int(mv["power"]) > 0:
		meta_bits.append("power %d%s" % [int(mv["power"]), (" ×%d hits" % int(mv["hits"])) if int(mv.get("hits", 1)) > 1 else ""])
	if int(mv.get("cooldown", 0)) > 0:
		meta_bits.append("cooldown %d" % int(mv.get("cooldown", 0)))
	lines.append(["  ·  ".join(meta_bits), Color("#8d93a5")])
	# Tier math vs every living enemy — believed values only (the chart + what
	# probing has revealed), never the hidden truth.
	if int(mv["power"]) > 0 and mv.get("target", "enemy") in ["enemy", "all_enemies"]:
		for e in battle.enemies:
			if not e.is_alive():
				continue
			var bmult := Rules.believed_mult(db, mv["element"], mv["phys"], e)
			var btier := Rules.tier_of(bmult)
			var em := Rules.element_mult(db, mv["element"], e.element, e.elem_overrides if e.mutation_revealed else {})
			var pm := Rules.phys_mult(db, mv["phys"], e.archetype, e.phys_overrides if e.mutation_revealed else {})
			var line := "vs %s: ×%.1f elem · ×%.1f phys = ×%.2f  %s" % [e.display_name, em, pm, bmult, Rules.tier_name(btier)]
			if not e.mutation_revealed:
				line += "  (unprobed!)"
			lines.append([line, UITheme.tier_color(btier)])
	_detail_lines(mv["name"], lines)


func _render_detail_girl(c: Combatant) -> void:
	if c.side != "party":
		return
	var g: Dictionary = db.girls[c.id]
	_detail_lines(c.display_name, [
		["%s · %s · %s" % [g["weapon"], c.element, c.archetype], Color("#8d93a5")],
		["ATK %d  DEF %d  SPD %d" % [c.eff_atk(), int(c.eff_def()), c.spd], Color("#c8ccd8")],
		[g.get("trigger_desc", ""), UITheme.PURPLE],
		["Statuses: %s" % (", ".join(c.statuses.keys()) if not c.statuses.is_empty() else "none"), Color("#8d93a5")],
	])


func _render_detail_enemy(c: Combatant) -> void:
	var lines: Array = []
	lines.append(["%s body · %s element" % [c.archetype, c.element], Color("#c8ccd8")])
	var arch: Dictionary = db.archetypes.get(c.archetype, {})
	var weak_to: Array = []
	var resists: Array = []
	for ph in arch:
		if float(arch[ph]) >= Rules.WEAK_MULT:
			weak_to.append(ph)
		elif float(arch[ph]) <= Rules.RESIST_MULT:
			resists.append(ph)
	if not weak_to.is_empty():
		lines.append(["Body weak to: " + ", ".join(weak_to), UITheme.GOLD])
	if not resists.is_empty():
		lines.append(["Body resists: " + ", ".join(resists), UITheme.GREY])
	if c.mutation_revealed and not c.mutations.is_empty():
		for m in c.mutations:
			lines.append(["Mutation: %s %s" % [m["key"], "WEAK" if m["mult"] >= Rules.WEAK_MULT else "RESIST"], UITheme.PURPLE])
	elif not c.mutation_revealed:
		lines.append(["[?] Unprobed — one affinity may be flipped.", UITheme.PURPLE])
	var ei := battle.enemies.find(c)
	for intent in battle.intents:
		if intent["enemy"] == ei:
			var imv: Dictionary = db.moves[intent["move"]]
			var who := "the whole party"
			if intent["slot"] >= 0 and intent["slot"] < battle.party.size() and battle.party[intent["slot"]] != null:
				who = battle.party[intent["slot"]].display_name
			lines.append(["Intends: %s (%s/%s) → %s" % [imv["name"], imv["element"], imv["phys"], who], Color("#e8a04a")])
	_detail_lines(c.display_name, lines)


func _detail_lines(title: String, lines: Array) -> void:
	_clear(detail_box)
	if title != "":
		var t := Label.new()
		t.text = title
		t.add_theme_font_size_override("font_size", 15)
		t.add_theme_color_override("font_color", UITheme.GOLD)
		detail_box.add_child(t)
	for entry in lines:
		var l := Label.new()
		l.text = entry[0]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", entry[1])
		detail_box.add_child(l)


## ---- Run mode: victory rewards / defeat ------------------------------------------

func _render_run_outcome() -> void:
	var run: Run = Game.run
	if not battle_resolved:
		battle_resolved = true
		run.on_battle_finished()
		Game.checkpoint()
	match run.state:
		"draft":
			_render_draft(run)
		"over", "map":
			var btn := Button.new()
			btn.text = "Continue" if run.result != "defeat" else "Accept defeat"
			btn.custom_minimum_size = Vector2(220, 48)
			btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
			UITheme.style_button(btn, UITheme.GOLD)
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
		lbl.add_theme_color_override("font_color", UITheme.GOLD)
		action_box.add_child(lbl)
		for offer in run.pending_draft["offers"]:
			var mv: Dictionary = db.moves[offer]
			var btn := Button.new()
			var eff: String = mv.get("effect", "")
			btn.text = "%s\n%s/%s  p%d  cd%d%s" % [mv["name"], mv["element"], mv["phys"], int(mv["power"]), int(mv.get("cooldown", 0)), ("\n[%s]" % eff) if eff != "" else ""]
			btn.custom_minimum_size = Vector2(170, 60)
			btn.tooltip_text = mv.get("desc", "")
			var offer_id: String = offer
			btn.pressed.connect(func():
				draft_pick = offer_id
				_refresh())
			btn.mouse_entered.connect(func(): _render_detail_move(offer_id))
			UITheme.style_button(btn, Color(db.element_colors.get(mv["element"], "#c8ccd8")))
			context_box.add_child(btn)
		var skip := Button.new()
		skip.text = "Skip"
		skip.custom_minimum_size = Vector2(100, 60)
		skip.pressed.connect(func():
			run.apply_draft("", -1)
			Game.checkpoint()
			get_tree().change_scene_to_file("res://scenes/run_map.tscn"))
		UITheme.style_button(skip)
		context_box.add_child(skip)
	else:
		var lbl := Label.new()
		lbl.text = "Replace which of %s's moves with %s?" % [girl.display_name, db.moves[draft_pick]["name"]]
		lbl.add_theme_color_override("font_color", UITheme.GOLD)
		action_box.add_child(lbl)
		for mi in girl.moves.size():
			var mv: Dictionary = db.moves[girl.moves[mi]]
			var btn := Button.new()
			btn.text = "%s\n%s/%s  p%d" % [mv["name"], mv["element"], mv["phys"], int(mv["power"])]
			btn.custom_minimum_size = Vector2(170, 60)
			btn.tooltip_text = mv.get("desc", "")
			var idx := mi
			btn.pressed.connect(func():
				Game.run.apply_draft(draft_pick, idx)
				Game.checkpoint()
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
	# Re-tapping the pending move cancels the aim.
	if pending == move_id or pending == "ally:" + move_id:
		_set_pending("")
		return
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
	var revealed_before := 0
	for e in battle.enemies:
		if e.mutation_revealed:
			revealed_before += 1
	battle.player_action(action)
	var revealed_after := 0
	for e in battle.enemies:
		if e.mutation_revealed:
			revealed_after += 1
	if revealed_after > revealed_before:
		_rim_flash(UITheme.PURPLE, 0.7)
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
