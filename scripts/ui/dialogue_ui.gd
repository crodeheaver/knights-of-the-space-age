class_name DialogueUI
extends Control
## Conversation screen: letterbox, speaker name and portrait, line text,
## numbered choices (with skill/companion/Resonance tags, chances and locked
## reasons), inline check results, history and skip for non-interactive runs.

var main: Node
var eng: DialogueEngine
var top_bar: ColorRect
var bottom: PanelContainer
var speaker_label: Label
var portrait: TextureRect
var text_label: RichTextLabel
var choices_box: VBoxContainer
var check_label: RichTextLabel
var history_panel: PanelContainer
var history_text: RichTextLabel
var _choice_rows: Array = []


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	UIKit.full_rect(dim)
	add_child(dim)
	top_bar = ColorRect.new()
	top_bar.color = Color(0, 0, 0, 0.92)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 90)
	top_bar.size = Vector2(1920, 90)
	add_child(top_bar)
	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.03, 0.035, 0.045, 0.96), Color(0.3, 0.26, 0.2)))
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -430
	bottom.offset_bottom = 0
	add_child(bottom)
	var h := UIKit.hbox(18)
	bottom.add_child(h)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(portrait)
	var v := UIKit.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top := UIKit.hbox()
	speaker_label = UIKit.label("", 24, UIKit.ACCENT2)
	speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(speaker_label)
	top.add_child(UIKit.button("History", func() -> void: _toggle_history(), "Conversation history (also in Journal)"))
	top.add_child(UIKit.button("Skip lines", func() -> void: _skip(), "Skip to the next choice. Effects and rewards are still applied."))
	v.add_child(top)
	text_label = UIKit.rich("", 21)
	text_label.custom_minimum_size = Vector2(1200, 0)
	v.add_child(text_label)
	check_label = UIKit.rich("", 16)
	v.add_child(check_label)
	choices_box = UIKit.vbox(4)
	v.add_child(choices_box)
	history_panel = UIKit.panel(null, Color(0.03, 0.035, 0.045, 0.97))
	history_text = UIKit.rich("", 16, false)
	history_text.custom_minimum_size = Vector2(900, 520)
	history_text.scroll_following = true
	history_panel.add_child(history_text)
	history_panel.set_anchors_preset(Control.PRESET_CENTER)
	history_panel.position = Vector2(-460, -440)
	history_panel.visible = false
	add_child(history_panel)


func open(engine: DialogueEngine) -> void:
	eng = engine
	visible = true
	if not eng.line_changed.is_connected(_on_line):
		eng.line_changed.connect(_on_line)
	if not eng.ended.is_connected(_on_end):
		eng.ended.connect(_on_end)
	_on_line(eng.current())


func close() -> void:
	visible = false
	history_panel.visible = false
	if Game.world != null:
		(Game.world as World).end_dialogue()


func _on_end(_id: String) -> void:
	# Show any final rewards, then return to the game.
	var logs := eng.take_log() if eng != null else []
	for l in logs:
		Events.toast(String(l), "reward")
	close()


func _on_line(n: Dictionary) -> void:
	if eng == null:
		return
	var sid := String(n.get("speaker", ""))
	speaker_label.text = String(n.get("speaker_name", ""))
	var col := "#e9e2d4"
	if sid == "narrator" or sid == "system":
		col = "#b8b0a2"
	text_label.text = "[color=%s]%s[/color]" % [col, String(n.get("text", "")).replace("[", "(").replace("]", ")")] if sid in ["narrator", "system"] else String(n.get("text", ""))
	if sid in ["narrator", "system"]:
		text_label.text = "[i][color=#b8b0a2]%s[/color][/i]" % String(n.get("text", ""))
	_set_portrait(sid)
	var w := Game.world as World
	if w != null:
		w.dialogue_frame(sid)
	var logs := eng.take_log()
	var ck: Dictionary = n.get("check", {})
	var lines: PackedStringArray = []
	if not ck.is_empty():
		lines.append("[color=%s]%s check (%s): d20 %d %s = %d vs DC %d — %s[/color]" % ["#5fd38a" if ck["success"] else "#ff6a5a", DB.skill(String(ck["skill"])).get("name", ""), ck["actor_name"], ck["natural"], Rules.signed(int(ck["bonus"])), ck["total"], ck["dc"], "SUCCESS" if ck["success"] else "FAILURE"])
	for l in logs:
		if String(l).contains("check (") and not ck.is_empty():
			continue
		lines.append("[color=#f2c26b]%s[/color]" % l)
	check_label.text = "\n".join(lines)
	check_label.visible = not lines.is_empty()
	_build_choices(n)
	history_text.text = _history_bb()


func _set_portrait(sid: String) -> void:
	portrait.texture = null
	var w := Game.world as World
	if w == null or (main as Node) == null:
		return
	var s: CharacterSheet = null
	if sid == "player":
		s = Game.state.player()
	elif w.actors.has(sid):
		s = (w.actors[sid] as Actor).sheet
	elif w.dialogue_npc != null and sid != "narrator" and sid != "system" and sid != "warden" and sid != "intercom":
		s = w.dialogue_npc.sheet
	if s != null and main.hud != null:
		portrait.texture = main.hud.portraits.texture_for(s, 160)


func _build_choices(n: Dictionary) -> void:
	UIKit.clear(choices_box)
	_choice_rows.clear()
	var chs: Array = n.get("choices", [])
	if chs.is_empty():
		var b := UIKit.button("Continue  [Space]", func() -> void: eng.advance())
		choices_box.add_child(b)
		b.call_deferred("grab_focus")
		return
	var i := 0
	for c in chs:
		i += 1
		var cd: Dictionary = c
		var tag := String(cd.get("tag", ""))
		var txt := "%d. %s%s" % [i, ("[%s] " % tag) if tag != "" else "", String(cd["text"])]
		var ck: Dictionary = cd.get("check", {})
		if not ck.is_empty():
			txt += "   (%d%%)" % int(ck.get("chance", 0))
		var b2 := UIKit.button(txt, func() -> void: eng.choose(int(cd["index"])))
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.add_theme_font_size_override("font_size", 18)
		if tag.begins_with("Resonance"):
			b2.add_theme_color_override("font_color", UIKit.MERCY)
		elif tag != "":
			b2.add_theme_color_override("font_color", UIKit.ACCENT2)
		if not bool(cd.get("enabled", true)):
			b2.disabled = true
			b2.text = txt + "   — " + String(cd.get("reason", "unavailable"))
		choices_box.add_child(b2)
		_choice_rows.append(cd)
		if i == 1:
			b2.call_deferred("grab_focus")


func _skip() -> void:
	if eng != null:
		eng.skip_lines()


func _toggle_history() -> void:
	history_panel.visible = not history_panel.visible
	history_text.text = _history_bb()


func _history_bb() -> String:
	var out: PackedStringArray = []
	var h := Game.state.dialogue_history
	for i in range(maxi(0, h.size() - 80), h.size()):
		var e: Dictionary = h[i]
		var sp := String(e.get("speaker", ""))
		var tx := String(e.get("text", "")).replace("[", "(").replace("]", ")")
		out.append(("[color=#f2c26b]%s:[/color] %s" % [sp, tx]) if sp != "" else "[color=#9c958a][i]%s[/i][/color]" % tx)
	return "\n".join(out)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or eng == null:
		return
	if event is InputEventKey and event.is_pressed() and not (event as InputEventKey).echo:
		var k := (event as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_9:
			var idx := k - KEY_1
			if idx < _choice_rows.size() and bool(_choice_rows[idx].get("enabled", true)):
				eng.choose(int(_choice_rows[idx]["index"]))
			get_viewport().set_input_as_handled()
		elif (k == KEY_SPACE or k == KEY_ENTER) and _choice_rows.is_empty():
			eng.advance()
			get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			if history_panel.visible:
				history_panel.visible = false
			get_viewport().set_input_as_handled()
