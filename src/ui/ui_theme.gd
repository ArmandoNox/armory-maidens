class_name UITheme
extends RefCounted
## Classic JRPG menu framing: deep-blue panels with light borders, shared by
## the battle scene and the act map.

const PANEL_BG := Color("#12143a")
const BORDER := Color("#aeb4c8")
const BORDER_DIM := Color("#4a4f6a")
const GOLD := Color("#ffd24a")
const RED := Color("#e2543e")
const GREEN := Color("#6abf6a")
const GREY := Color("#7f8597")
const PURPLE := Color("#c77dff")

static var _icon_cache := {}


## Pixel icon from assets/icons/icon_<name>.png, or null if not generated yet.
static func icon(icon_name: String) -> Texture2D:
	if _icon_cache.has(icon_name):
		return _icon_cache[icon_name]
	var path := "res://assets/icons/icon_%s.png" % icon_name
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_icon_cache[icon_name] = tex
	return tex


## Small TextureRect for a pixel icon; falls back to a colored swatch so the
## layout never breaks before art lands.
static func icon_rect(icon_name: String, px: int = 20, fallback := Color("#5d6275")) -> Control:
	var tex := icon(icon_name)
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(px, px)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var cr := ColorRect.new()
	cr.color = fallback
	cr.custom_minimum_size = Vector2(px, px)
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cr


static func tier_color(tier: int) -> Color:
	match tier:
		Rules.Tier.WEAK: return GOLD
		Rules.Tier.RESIST: return GREY
		_: return Color("#c8ccd8")


static func tier_verdict(tier: int) -> String:
	match tier:
		Rules.Tier.WEAK: return "WEAK — bonus icon"
		Rules.Tier.RESIST: return "RESIST — burns 2 icons"
		_: return "NORMAL"


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
