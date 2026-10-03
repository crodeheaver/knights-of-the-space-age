class_name SettingsUI
extends PanelBase
## Settings: gameplay (difficulty, auto-pause, tutorials), controls (key
## rebinding with conflict handling, mouse sensitivity, invert), display and
## accessibility (text/UI scale, subtitles, reduced shake and flash), audio
## volumes. Values live in the Settings autoload and save immediately.

var standalone := false
var section := "gameplay"
var _body: VBoxContainer
var _tabs: HBoxContainer
var _capture_action := ""
var _msg: Label


func build() -> void:
	var v := make_window("Settings", Vector2(1200, 860))
	_tabs = UIKit.hbox(6)
	v.add_child(_tabs)
	_body = UIKit.vbox(8)
	v.add_child(UIKit.scroll(_body))
	_msg = UIKit.label("", 16, UIKit.ACCENT2, true)
	v.add_child(_msg)
	_render()


func _render() -> void:
	UIKit.clear(_tabs)
	for t in [["gameplay", "Gameplay"], ["controls", "Controls"], ["display", "Display & Accessibility"], ["audio", "Audio"]]:
		var tid := String(t[0])
		var b := UIKit.button(String(t[1]), func() -> void:
			section = tid
			_capture_action = ""
			_render())
		b.toggle_mode = true
		b.button_pressed = section == tid
		_tabs.add_child(b)
	UIKit.clear(_body)
	match section:
		"gameplay":
			_gameplay()
		"controls":
			_controls()
		"display":
			_display()
		"audio":
			_audio()


func _check(key: String, label: String, tip: String = "") -> void:
	var c := CheckBox.new()
	c.text = label
	c.tooltip_text = tip
	c.button_pressed = bool(Settings.get_v(key))
	c.toggled.connect(func(v: bool) -> void:
		Settings.set_v(key, v)
		if key == "dev_mode" and Game.state != null:
			Game.state.dev_mode = Game.state.dev_mode or v)
	_body.add_child(c)
	if tip != "":
		_body.add_child(UIKit.label("      " + tip, 14, UIKit.DIM, true))


func _slider(key: String, label: String, lo: float, hi: float, step: float, fmt: String = "%.0f%%", scale := 100.0) -> void:
	var row := UIKit.hbox(10)
	var l := UIKit.label(label, 17)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get_v(key))
	s.custom_minimum_size = Vector2(420, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UIKit.label(fmt % (s.value * scale), 17, UIKit.ACCENT2)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt % (v * scale)
		Settings.set_v(key, v))
	row.add_child(s)
	row.add_child(val)
	_body.add_child(row)


func _gameplay() -> void:
	_body.add_child(UIKit.header("Difficulty"))
	var dr := UIKit.hbox(8)
	for d in [["story", "Story"], ["standard", "Standard"]]:
		var did := String(d[0])
		var b := UIKit.button(String(d[1]), func() -> void:
			Settings.set_v("difficulty", did)
			if Game.state != null:
				Game.state.difficulty = did
			_render())
		b.toggle_mode = true
		b.button_pressed = String(Game.state.difficulty if Game.state != null else Settings.get_v("difficulty")) == did
		dr.add_child(b)
	_body.add_child(dr)
	_body.add_child(UIKit.label("Story: enemies attack at a penalty and your party takes reduced damage. Standard: the intended balance. You can switch at any time.", 14, UIKit.DIM, true))
	_body.add_child(UIKit.header("Auto-pause"))
	_check("autopause_combat_start", "Pause when combat starts")
	_check("autopause_member_down", "Pause when a party member goes down")
	_check("autopause_queue_empty", "Pause when your character's action queue empties")
	_check("autopause_target_dead", "Pause when your target is defeated")
	_body.add_child(UIKit.header("Combat"))
	_check("auto_attack", "Auto-attack", "When combat starts and you have queued nothing, your character queues a basic attack on the selected (or nearest) enemy, and keeps attacking the nearest enemy when the target falls. Queuing anything, or moving, replaces it.")
	_body.add_child(UIKit.header("Assistance"))
	_check("tutorials", "Show tutorial tips", "Tips you have already seen stay readable in Journal → Tutorials.")
	_check("hold_on_stealth", "Companions hold position when you enter stealth")
	_check("damage_numbers", "Floating damage numbers")
	_check("edge_pan", "Rotate the camera at the screen edges")
	_body.add_child(UIKit.header("Developer"))
	_check("dev_mode", "Developer mode", "Enables the developer menu (F12) and presets on the title screen. Saves made with developer tools are tagged [DEV].")


func _controls() -> void:
	_body.add_child(UIKit.header("Mouse"))
	_slider("mouse_sensitivity", "Camera sensitivity", 0.2, 3.0, 0.05, "%.2f×", 1.0)
	_check("invert_y", "Invert camera pitch")
	_body.add_child(UIKit.header("Keys"))
	_body.add_child(UIKit.label("Click a binding, then press the new key (Esc cancels). A key already in use moves to the new action and the old action is left unbound — check for a dash.", 14, UIKit.DIM, true))
	for a in Settings.ACTION_LABELS.keys():
		var aid := String(a)
		var row := UIKit.hbox(8)
		var l := UIKit.label(String(Settings.ACTION_LABELS[a]), 16)
		l.custom_minimum_size = Vector2(320, 0)
		row.add_child(l)
		var listening := _capture_action == aid
		var kb := UIKit.button("Press a key…" if listening else Settings.key_label(aid), func() -> void:
			_capture_action = aid
			_msg.text = "Press a key for %s." % Settings.ACTION_LABELS[aid]
			_render())
		kb.custom_minimum_size = Vector2(200, 34)
		if Settings.key_label(aid) == "—":
			kb.add_theme_color_override("font_color", UIKit.BAD)
		row.add_child(kb)
		_body.add_child(row)
	_body.add_child(UIKit.button("Reset all keys to defaults", func() -> void:
		Settings.reset_bindings()
		_msg.text = "Key bindings reset."
		_render()))


func _input(event: InputEvent) -> void:
	if _capture_action == "" or not (event is InputEventKey) or not event.is_pressed():
		return
	var k := event as InputEventKey
	get_viewport().set_input_as_handled()
	if k.keycode == KEY_ESCAPE and _capture_action != "menu":
		_capture_action = ""
		_msg.text = "Rebinding cancelled."
		_render()
		return
	var code := int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
	var stolen := Settings.rebind(_capture_action, code)
	_msg.text = "%s → %s" % [Settings.ACTION_LABELS[_capture_action], Settings.key_label(_capture_action)]
	if stolen != "":
		_msg.text += "  (removed from %s — it is now unbound)" % Settings.ACTION_LABELS.get(stolen, stolen)
	_capture_action = ""
	_render()


func _display() -> void:
	_body.add_child(UIKit.header("Text and interface"))
	_slider("ui_scale", "Interface & text scale", 0.75, 1.6, 0.05)
	_check("subtitles", "Captions for ambient speech", "Lines spoken outside conversations (radio calls, companions) are shown larger and stay on screen longer, scaled to their length.")
	_body.add_child(UIKit.header("Conversations"))
	_text_speed()
	_check("fullscreen", "Fullscreen")
	_body.add_child(UIKit.header("Comfort"))
	_check("reduce_shake", "Reduce camera shake", "Removes shake from explosions and critical hits.")
	_check("reduce_flash", "Reduce flashes", "Softens hit flashes, explosion bursts and alarm lights.")


## Conversation text speed: characters per second, with 0 meaning instant.
func _text_speed() -> void:
	var row := UIKit.hbox(10)
	var l := UIKit.label("Text speed", 17)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 120
	s.step = 5
	s.value = float(Settings.get_v("text_speed"))
	s.custom_minimum_size = Vector2(420, 28)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fmt := func(v: float) -> String: return "Instant" if v <= 0.0 else "%d characters/s" % int(v)
	var val := UIKit.label(fmt.call(s.value), 17, UIKit.ACCENT2)
	s.value_changed.connect(func(v: float) -> void:
		val.text = fmt.call(v)
		Settings.set_v("text_speed", v))
	row.add_child(s)
	row.add_child(val)
	_body.add_child(row)
	_body.add_child(UIKit.label("Lines appear at this speed; Space or a click shows the whole line at once.", 14, UIKit.DIM, true))


func _audio() -> void:
	_body.add_child(UIKit.header("Volume"))
	_slider("master_volume", "Master", 0.0, 1.0, 0.05)
	_slider("music_volume", "Music", 0.0, 1.0, 0.05)
	_slider("sfx_volume", "Effects", 0.0, 1.0, 0.05)
	_slider("ambience_volume", "Ambience", 0.0, 1.0, 0.05)
	_slider("ui_volume", "Interface", 0.0, 1.0, 0.05)
	_slider("voice_volume", "Voices", 0.0, 1.0, 0.05)
	_body.add_child(UIKit.label("Characters speak in their own languages, as voiced babble under the subtitles.", 14, UIKit.DIM, true))
	_body.add_child(UIKit.button("Play a test sound", func() -> void: GameAudio.play("ui_confirm", 0.0)))
