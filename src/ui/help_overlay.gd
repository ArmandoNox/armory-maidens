class_name HelpOverlay
extends Control
## Full-screen "How to play" overlay shared by the title, map, and battle
## scenes. Built in code; closes on the button or Esc.


static func popup(parent: Node) -> void:
	var overlay := HelpOverlay.new()
	overlay._build()
	parent.add_child(overlay)


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			queue_free())

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_box())
	frame.custom_minimum_size = Vector2(720, 0)
	center.add_child(frame)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	frame.add_child(col)

	var title := Label.new()
	title.text = "HOW TO PLAY"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.custom_minimum_size = Vector2(690, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.text = """[color=#ffd24a][b]ICONS — your turn economy[/b][/color]
Each round you get one [color=#ffd24a]◆ icon[/color] per living active girl. Every action (attack, probe, switch) spends one.
• Strike a [color=#ffd24a]WEAK[/color]ness → the action is FREE (a bonus icon is minted, up to 3/round).
• Hit a [color=#7f8597]RESIST[/color] → it burns [color=#e2543e]2 icons[/color]. Don't guess into resists.
[color=#e8a04a]Enemies play by the same rules[/color] — they mint icons off YOUR weaknesses.

[color=#ffd24a][b]ELEMENT × PHYSICAL — the composition rule[/b][/color]
Every attack has an element (ember→gale→terra→volt→tide cycle) AND a physical type (slash / pierce / blunt vs the body it hits). The two multipliers [b]multiply[/b]:
[color=#ffd24a]weak ×1.5[/color] × [color=#7f8597]resist ×0.5[/color] = ×0.75 → [b]NORMAL[/b]. One axis cancels the other.
A swap dodges the crit — it doesn't blank the hit.

[color=#ffd24a][b]SWITCHING — costs an icon, binds to the slot[/b][/color]
Enemy attacks telegraph their target slot. Switch a girl in and SHE eats that hit — but she also fires her signature switch-in trigger (guard, counter, snap shot, party heal).

[color=#c77dff][b]PROBE — buy the truth[/b][/color]
Every enemy can carry a hidden affinity [color=#c77dff]mutation[/color] (elites always; bosses two). [b][?][/b] means unprobed. Probe costs one icon and reveals it — before you swing into a surprise resist.

[color=#ffd24a][b]THE RUN[/b][/color]
Climb the map: fights, elites, rests (+30% HP), events, then the boss. HP carries between fights; the fallen revive at 25% after victory. After each fight the armory offers one girl a new technique — learning it overwrites one of her four equipped moves."""
	col.add_child(body)

	var close := Button.new()
	close.text = "Got it"
	close.custom_minimum_size = Vector2(160, 42)
	UITheme.style_button(close, UITheme.GOLD)
	close.pressed.connect(queue_free)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_child(close)
	col.add_child(brow)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		accept_event()
