class_name MinigamePanel
extends PanelBase
## Shared shell for the minigame screens: the practice flag, the world's
## "minigame" modal (held while the panel exists, released on every exit
## path, including being freed by a load or a return to the main menu), Esc
## handling with an optional confirmation, a pausing overlay, and swallowing
## keys so world shortcuts and the dialogue box underneath stay quiet.
##
## Subclasses implement build(), on_escape() and handle_key(), and call
## close_now() to leave.

var game_id := ""
var practice := false
var overlay: Control = null
var _modal_held := false
var _closed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hold_modal()
	super._ready()


func _exit_tree() -> void:
	release_modal()


func hold_modal() -> void:
	if _modal_held or Game.world == null or not is_instance_valid(Game.world):
		return
	Game.world.set_modal("minigame", true)
	_modal_held = true


func release_modal() -> void:
	if not _modal_held:
		return
	_modal_held = false
	if Game.world != null and is_instance_valid(Game.world):
		Game.world.set_modal("minigame", false)


## Leaves the minigame. Safe to call more than once.
func close_now() -> void:
	if _closed:
		return
	_closed = true
	close_overlay()
	release_modal()
	if main != null and is_instance_valid(main) and main.has_method("close_panel"):
		main.close_panel(self)
	else:
		queue_free()


func is_closed() -> bool:
	return _closed


## The window's close button and main.close_top_panel() land here.
func request_close() -> void:
	on_escape()


## Esc / close. Default: leave at once. Games with something at stake confirm.
func on_escape() -> void:
	close_now()


## Keys other than Esc while no overlay is open.
func handle_key(_ev: InputEventKey) -> void:
	pass


func is_paused() -> bool:
	return overlay != null


func _unhandled_input(event: InputEvent) -> void:
	if _closed or not is_visible_in_tree():
		return
	var esc := event.is_action_pressed("menu") or (event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE and not (event as InputEventKey).echo)
	if esc:
		get_viewport().set_input_as_handled()
		if overlay != null and overlay.has_meta("esc"):
			var cb: Callable = overlay.get_meta("esc")
			if cb.is_valid():
				cb.call()
		elif overlay == null:
			on_escape()
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and overlay == null:
			handle_key(k)
		# Swallow every key so nothing underneath reacts while we are open.
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------ overlay
## A centred message box that pauses the game underneath. buttons:
## [[label, Callable], ...]; esc_index: which button Esc presses (-1: none).
func show_overlay(title: String, text: String, buttons: Array, esc_index: int = -1, width: float = 620.0) -> void:
	close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	UIKit.full_rect(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.08, 0.1, 0.98), UIKit.ACCENT))
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(width, 0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	dim.add_child(box)
	var v := UIKit.vbox(12)
	box.add_child(v)
	v.add_child(UIKit.label(title, 26, UIKit.ACCENT2))
	if text != "":
		var r := UIKit.rich(text, 18)
		r.custom_minimum_size = Vector2(width - 40.0, 0)
		v.add_child(r)
	var row := UIKit.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var first: Button = null
	for b in buttons:
		var cb: Callable = b[1]
		var btn := UIKit.button(String(b[0]), cb)
		btn.custom_minimum_size = Vector2(150, 44)
		row.add_child(btn)
		if first == null:
			first = btn
	if esc_index >= 0 and esc_index < buttons.size():
		dim.set_meta("esc", buttons[esc_index][1])
	add_child(dim)
	overlay = dim
	if first != null:
		focus_later(first)


func close_overlay() -> void:
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()
	overlay = null


# ------------------------------------------------------------ helpers
## Focuses a control on the next frame if it is still on screen by then
## (pages are rebuilt often, so the control may be gone).
static func focus_later(c: Control) -> void:
	var cb := func() -> void:
		if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
			c.grab_focus()
	cb.call_deferred()


## Rounded, bordered card style used by every game's widgets.
static func card_style(col: Color, fill: float = 0.62, border: int = 2, radius: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col.darkened(fill)
	s.border_color = col
	s.set_border_width_all(border)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 6
	s.content_margin_right = 6
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


static func fmt_time(t: float) -> String:
	if t <= 0.0:
		return "--:--.--"
	var m := int(t / 60.0)
	return "%d:%05.2f" % [m, t - m * 60.0]
