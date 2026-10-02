class_name UIKit
extends RefCounted
## Shared theme and widget constructors so every screen looks coherent.

const BG := Color(0.05, 0.06, 0.08, 0.92)
const PANEL := Color(0.09, 0.1, 0.13, 0.94)
const PANEL_LIGHT := Color(0.14, 0.15, 0.19, 0.96)
const BORDER := Color(0.32, 0.29, 0.25, 1.0)
const ACCENT := Color("#e8823a")
const ACCENT2 := Color("#f2c26b")
const TEAL := Color("#3fb6b0")
const TEXT := Color("#e9e2d4")
const DIM := Color("#9c958a")
const GOOD := Color("#5fd38a")
const BAD := Color("#ff6a5a")
const WARN := Color("#f2c26b")
const MERCY := Color("#7fd0ff")
const DOMINION := Color("#d06aff")

static var _theme: Theme


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 19
	var p := _sb(PANEL, BORDER, 1, 6)
	t.set_stylebox("panel", "Panel", p)
	t.set_stylebox("panel", "PanelContainer", p)
	var bn := _sb(Color(0.15, 0.15, 0.18, 0.95), Color(0.36, 0.33, 0.28), 1, 4)
	var bh := _sb(Color(0.24, 0.2, 0.15, 0.98), ACCENT, 1, 4)
	var bp := _sb(Color(0.32, 0.22, 0.12, 1.0), ACCENT2, 1, 4)
	var bd := _sb(Color(0.1, 0.1, 0.12, 0.8), Color(0.22, 0.22, 0.24), 1, 4)
	var bf := _sb(Color(0.2, 0.17, 0.13, 0.98), ACCENT2, 2, 4)
	for s in [bn, bh, bp, bd, bf]:
		s.content_margin_left = 12
		s.content_margin_right = 12
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", bf)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.48, 0.45))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("normal", "LineEdit", _sb(Color(0.06, 0.07, 0.09), BORDER, 1, 4))
	t.set_stylebox("focus", "LineEdit", _sb(Color(0.08, 0.09, 0.11), ACCENT, 1, 4))
	var tab_sel := _sb(Color(0.24, 0.2, 0.15), ACCENT, 1, 4)
	var tab_un := _sb(Color(0.12, 0.12, 0.15), BORDER, 1, 4)
	for s in [tab_sel, tab_un]:
		s.content_margin_left = 14
		s.content_margin_right = 14
		s.content_margin_top = 6
		s.content_margin_bottom = 6
	t.set_stylebox("tab_selected", "TabBar", tab_sel)
	t.set_stylebox("tab_unselected", "TabBar", tab_un)
	t.set_stylebox("tab_hovered", "TabBar", tab_sel)
	t.set_stylebox("panel", "TabContainer", p)
	t.set_stylebox("tab_selected", "TabContainer", tab_sel)
	t.set_stylebox("tab_unselected", "TabContainer", tab_un)
	t.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	var bg := _sb(Color(0.12, 0.12, 0.14), Color(0.25, 0.25, 0.28), 1, 3)
	var fill := _sb(ACCENT, ACCENT, 0, 3)
	t.set_stylebox("background", "ProgressBar", bg)
	t.set_stylebox("fill", "ProgressBar", fill)
	t.set_stylebox("panel", "PopupMenu", p)
	t.set_stylebox("panel", "TooltipPanel", _sb(Color(0.05, 0.05, 0.07, 0.97), ACCENT2, 1, 4))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("normal", "OptionButton", bn)
	t.set_stylebox("hover", "OptionButton", bh)
	t.set_stylebox("pressed", "OptionButton", bp)
	t.set_stylebox("focus", "OptionButton", bf)
	t.set_stylebox("slider", "HSlider", _sb(Color(0.15, 0.15, 0.18), BORDER, 1, 3))
	t.set_stylebox("grabber_area", "HSlider", _sb(ACCENT.darkened(0.3), ACCENT, 0, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _sb(ACCENT, ACCENT, 0, 3))
	_theme = t
	return t


static func _sb(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func panel_style(bg: Color = PANEL, border: Color = BORDER) -> StyleBoxFlat:
	return _sb(bg, border, 1, 6)


static func label(text: String, size: int = 0, col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func rich(bbcode: String, size: int = 0, fit: bool = true) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = bbcode
	r.fit_content = fit
	r.scroll_active = not fit
	r.selection_enabled = false
	if size > 0:
		r.add_theme_font_size_override("normal_font_size", size)
		r.add_theme_font_size_override("bold_font_size", size)
	return r


static func button(text: String, cb: Callable = Callable(), tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func() -> void: GameAudio.play("ui_click", -10.0))
	return b


static func vbox(sep: int = 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func panel(child: Control = null, bg: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg))
	if child != null:
		p.add_child(child)
	return p


static func bar(value: float, max_v: float, col: Color, h: float = 14.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.max_value = maxf(1.0, max_v)
	b.value = value
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, h)
	var f := _sb(col, col, 0, 3)
	b.add_theme_stylebox_override("fill", f)
	return b


static func spacer(w: float = 0, h: float = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	return c


static func expand(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func scroll(child: Control, min_h: float = 0) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = Vector2(0, min_h)
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func sep() -> HSeparator:
	return HSeparator.new()


static func header(text: String) -> Label:
	var l := label(text.to_upper(), 16, ACCENT2)
	return l


## Anchors (0..1) plus pixel offsets, independent of the parent's current size.
static func anchor(c: Control, a: Vector4, o: Vector4) -> void:
	c.anchor_left = a.x
	c.anchor_top = a.y
	c.anchor_right = a.z
	c.anchor_bottom = a.w
	c.offset_left = o.x
	c.offset_top = o.y
	c.offset_right = o.z
	c.offset_bottom = o.w


static func full_rect(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


static func center_box(c: Control, size: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.custom_minimum_size = size
	c.offset_left = -size.x / 2
	c.offset_top = -size.y / 2
	c.offset_right = size.x / 2
	c.offset_bottom = size.y / 2


## Modal backdrop + centered window with a title bar and close button.
static func window(title: String, size: Vector2, on_close: Callable) -> Dictionary:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var win := PanelContainer.new()
	win.add_theme_stylebox_override("panel", panel_style(Color(0.07, 0.08, 0.1, 0.97), Color(0.45, 0.38, 0.28)))
	center_box(win, size)
	dim.add_child(win)
	var v := vbox(8)
	win.add_child(v)
	var top := hbox()
	var t := label(title, 24, ACCENT2)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	if on_close.is_valid():
		var x := button("Close (Esc)", on_close)
		top.add_child(x)
	v.add_child(top)
	v.add_child(sep())
	var body := vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	return {"root": dim, "win": win, "body": body, "title": t}


static func status_chip(status_id: String, remaining: float) -> Label:
	var d: Dictionary = DB.status(status_id)
	var kind := String(d.get("kind", "debuff"))
	var col := GOOD if kind in ["buff", "shield"] else (BAD if kind in ["control", "dot", "debuff"] else WARN)
	var l := label("%s %ds" % [String(d.get("symbol", status_id)), ceili(remaining)] if remaining < 900 else String(d.get("symbol", status_id)), 13, col)
	l.tooltip_text = "%s: %s" % [d.get("name", status_id), d.get("desc", "")]
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	var sb := _sb(Color(0.05, 0.05, 0.06, 0.85), col.darkened(0.3), 1, 3)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	return l
