extends Control
## Greybox battle UI — rectangles and labels only, built entirely in code.
## Pixel-art combat presentation replaces this after the fun gate passes.

var db: DataDB
var battle: Battle
var selected_slot := -1
var pending: String = ""          # "" | move_id | "probe" | "switch"
var log_cursor := 0

var top_label: Label
var party_box: VBoxContainer
var bench_box: VBoxContainer
var enemy_box: VBoxContainer
var action_box: HBoxContainer
var context_box: HBoxContainer
var log_text: RichTextLabel
var pack_picker: OptionButton

const PANEL_W := 320


func _ready() -> void:
	db = DataDB.load_default()
	_build_layout()
	_start_battle("trash_pack")


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#1b1d24")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root.add_theme_constant_override(m, 12)
	add_child(root)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 8)
	root.add_child(main)

	var top_row := HBoxContainer.new()
	main.add_child(top_row)
	top_label = Label.new()
	top_label.add_theme_font_size_override("font_size", 20)
	top_row.add_child(top_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(spacer)
	pack_picker = OptionButton.new()
	for pack in db.encounters:
		pack_picker.add_item(pack)
	top_row.add_child(pack_picker)
	var restart := Button.new()
	restart.text = "Restart"
	restart.pressed.connect(func(): _start_battle(pack_picker.get_item_text(pack_picker.selected)))
	top_row.add_child(restart)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	main.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(PANEL_W, 0)
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	left.add_child(_header("PARTY"))
	party_box = VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 6)
	left.add_child(party_box)
	left.add_child(_header("BENCH"))
	bench_box = VBoxContainer.new()
	left.add_child(bench_box)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(mid)
	mid.add_child(_header("LOG"))
	log_text = RichTextLabel.new()
	log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_text.scroll_following = true
	log_text.bbcode_enabled = true
	mid.add_child(log_text)

	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(PANEL_W + 40, 0)
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(_header("ENEMIES"))
	enemy_box = VBoxContainer.new()
	enemy_box.add_theme_constant_override("separation", 6)
	right.add_child(enemy_box)

	main.add_child(_header("ACTIONS"))
	action_box = HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 6)
	main.add_child(action_box)
	context_box = HBoxContainer.new()
	context_box.add_theme_constant_override("separation", 6)
	main.add_child(context_box)


func _header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color("#8d93a5"))
	l.add_theme_font_size_override("font_size", 13)
	return l


func _start_battle(pack: String) -> void:
	var foes: Array = db.encounters[pack]
	battle = Battle.create(db, ["kaede", "riko", "tsubaki", "mizuki"], foes, randi())
	selected_slot = -1
	pending = ""
	log_cursor = 0
	log_text.clear()
	_refresh()


## ---- Rendering ----------------------------------------------------------------

func _refresh() -> void:
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

	var icons_str := ""
	for i in battle.icons:
		icons_str += "◆ "
	if battle.phase == "over":
		top_label.text = "Round %d   —   %s" % [battle.round_num, battle.result.to_upper()]
	else:
		top_label.text = "Round %d   icons: %s" % [battle.round_num, icons_str]

	_clear(party_box)
	for slot in battle.party.size():
		party_box.add_child(_party_panel(slot))
	_clear(bench_box)
	for bi in battle.bench.size():
		bench_box.add_child(_bench_panel(bi))
	_clear(enemy_box)
	for ei in battle.enemies.size():
		enemy_box.add_child(_enemy_panel(ei))
	_render_actions()


func _party_panel(slot: int) -> Button:
	var girl: Combatant = battle.party[slot]
	var b := Button.new()
	b.custom_minimum_size = Vector2(PANEL_W, 64)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if girl == null or not girl.is_alive():
		b.text = "  (down)"
		b.disabled = true
		return b
	var mark := "▶ " if slot == selected_slot else "  "
	b.text = "%s%s  [%s/%s]  HP %d/%d%s" % [
		mark, girl.display_name, girl.element, girl.archetype, girl.hp, girl.max_hp,
		_status_str(girl),
	]
	b.add_theme_color_override("font_color", Color(db.element_colors.get(girl.element, "#ffffff")))
	b.pressed.connect(func(): _on_party_clicked(slot))
	return b


func _bench_panel(bi: int) -> Label:
	var girl: Combatant = battle.bench[bi]
	var l := Label.new()
	if girl == null:
		l.text = "  (empty)"
	elif not girl.is_alive():
		l.text = "  %s (down)" % girl.display_name
	else:
		l.text = "  %s  HP %d/%d" % [girl.display_name, girl.hp, girl.max_hp]
	return l


func _enemy_panel(ei: int) -> Button:
	var e: Combatant = battle.enemies[ei]
	var b := Button.new()
	b.custom_minimum_size = Vector2(PANEL_W + 40, 72)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if not e.is_alive():
		b.text = "  %s — defeated" % e.display_name
		b.disabled = true
		return b
	var intent_str := ""
	for intent in battle.intents:
		if intent["enemy"] == ei:
			var mv: Dictionary = db.moves[intent["move"]]
			var who := "slot %d" % intent["slot"]
			if intent["slot"] < battle.party.size() and battle.party[intent["slot"]] != null:
				who = battle.party[intent["slot"]].display_name
			intent_str = "\n  intent: %s → %s" % [mv["name"], who]
	var mut := ""
	if not e.mutation.is_empty():
		mut = "  [mutation: %s]" % (("%s %s" % [e.mutation["key"], "WEAK" if e.mutation["mult"] >= 1.5 else "RESIST"]) if e.mutation_revealed else "?")
	elif not e.mutation_revealed:
		mut = "  [mutation: ?]"
	b.text = "  %s  [%s/%s]%s  HP %d/%d%s%s" % [e.display_name, e.element, e.archetype, mut, e.hp, e.max_hp, _status_str(e), intent_str]
	b.add_theme_color_override("font_color", Color(db.element_colors.get(e.element, "#ffffff")))
	b.pressed.connect(func(): _on_enemy_clicked(ei))
	return b


func _status_str(c: Combatant) -> String:
	if c.statuses.is_empty():
		return ""
	return "  {%s}" % ", ".join(c.statuses.keys())


func _render_actions() -> void:
	_clear(action_box)
	_clear(context_box)
	if battle.phase == "over":
		var done := Label.new()
		done.text = "Battle over — Restart or pick another pack."
		action_box.add_child(done)
		return
	if selected_slot < 0 or battle.party[selected_slot] == null or not battle.party[selected_slot].is_alive():
		var hint := Label.new()
		hint.text = "Select a girl to act (%d icons left)." % battle.icons
		action_box.add_child(hint)
	else:
		var girl: Combatant = battle.party[selected_slot]
		for m in girl.all_usable_moves():
			var mv: Dictionary = db.moves[m]
			var btn := Button.new()
			var cd := int(mv.get("cooldown", 0))
			btn.text = "%s\n%s/%s  p%d%s" % [mv["name"], mv["element"], mv["phys"], int(mv["power"]), ("  cd%d" % cd) if cd > 0 else ""]
			btn.pressed.connect(func(): _on_move_clicked(m))
			if pending == m:
				btn.add_theme_color_override("font_color", Color("#ffd24a"))
			action_box.add_child(btn)
		for m in girl.moves:
			if int(girl.cooldowns.get(m, 0)) > 0:
				var off := Button.new()
				off.text = "%s\n(cd %d)" % [db.moves[m]["name"], int(girl.cooldowns[m])]
				off.disabled = true
				action_box.add_child(off)
		if girl.actions_this_round >= Battle.MAX_ACTIONS_PER_GIRL:
			var capped := Label.new()
			capped.text = "(acted %d/%d this round)" % [girl.actions_this_round, Battle.MAX_ACTIONS_PER_GIRL]
			action_box.add_child(capped)

		var probe := Button.new()
		probe.text = "Probe\n(reveal mutation)"
		probe.pressed.connect(func(): _set_pending("probe"))
		if pending == "probe":
			probe.add_theme_color_override("font_color", Color("#c77dff"))
		context_box.add_child(probe)
		for bi in battle.bench.size():
			var bg: Combatant = battle.bench[bi]
			if bg != null and bg.is_alive():
				var sw := Button.new()
				sw.text = "Switch in %s" % bg.display_name
				var bench_index := bi
				sw.pressed.connect(func(): _do_action({ "type": "switch", "slot": selected_slot, "bench": bench_index }))
				context_box.add_child(sw)

	var pass_btn := Button.new()
	pass_btn.text = "End Turn"
	pass_btn.pressed.connect(func(): _do_action({ "type": "pass" }))
	context_box.add_child(pass_btn)


## ---- Input flow -----------------------------------------------------------------

func _on_party_clicked(slot: int) -> void:
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
