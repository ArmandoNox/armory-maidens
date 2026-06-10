class_name UITheme
extends RefCounted
## Classic JRPG menu framing: deep-blue panels with light borders, shared by
## the battle scene and the act map.

const PANEL_BG := Color("#12143a")
const BORDER := Color("#aeb4c8")
const BORDER_DIM := Color("#4a4f6a")


static func panel_box(bg: Color = PANEL_BG, border: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	return sb


static func style_button(btn: Button, accent: Color = Color("#c8ccd8")) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#141744")
	normal.border_color = BORDER_DIM
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(8)
	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = BORDER
	hover.bg_color = Color("#1b1f5a")
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color("#0d0f30")
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color("#101225")
	disabled.border_color = Color("#2a2d44")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", Color("#ffffff"))
	btn.add_theme_color_override("font_disabled_color", Color("#5a5e75"))
	btn.focus_mode = Control.FOCUS_NONE
