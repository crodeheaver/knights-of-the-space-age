class_name DialogueUI
extends Control
## Conversation screen: letterbox, speaker name and portrait, the line revealed
## at the player's text speed and babbled in the speaker's voice, numbered
## choices (with tone, skill/companion/Resonance tags, chances and locked
## reasons), inline check results and reactions (approval, Mercy/Dominion,
## experience, discoveries), history and skip for non-interactive runs.

const TONE_COLORS := {
	"compassionate": Color("#7fd0ff"), "pragmatic": Color("#9c958a"), "self-interested": Color("#f2c26b"),
	"skeptical": Color("#e8a33a"), "hard": Color("#ff6a5a"),
}
const SILENT := ["player", "narrator", "system"]

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
var _reveal_t := 0.0
var _reveal_len := 0
var _revealing := false
var _reactions: Array = []
var _glyphs: Dictionary = {}
var _focus_btn: Button = null


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	top_bar = ColorRect.new()
	top_bar.color = Color(0, 0, 0, 0.92)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.custom_minimum_size = Vector2(0, 90)
	top_bar.size = Vector2(1920, 90)
	add_child(top_bar)
	# The bottom panel hugs its content and grows upwards from the screen edge.
	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.02, 0.025, 0.035, 0.95), Color(0.3, 0.26, 0.2)))
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_top = 0
	bottom.offset_bottom = 0
	bottom.custom_minimum_size = Vector2(0, 230)
	bottom.gui_input.connect(_on_panel_input)
	add_child(bottom)
	var h := UIKit.hbox(18)
	bottom.add_child(h)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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
	text_label.mouse_filter = Control.MOUSE_FILTER_PASS
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
	Events.event.connect(_on_game_event)


func _exit_tree() -> void:
	if Events.event.is_connected(_on_game_event):
		Events.event.disconnect(_on_game_event)


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
	_revealing = false
	GameAudio.voice_stop("dialogue")
	if Game.world != null:
		(Game.world as World).end_dialogue()


func _on_end(_id: String) -> void:
	# Show any final rewards, then return to the game. (The HUD holds toasts
	# raised while it is hidden and shows them once the conversation closes.)
	var logs := eng.take_log() if eng != null else []
	for l in _filter_logs(logs):
		Events.toast(String(l), "reward")
	for r in _reactions:
		Events.toast(String(r["plain"]), String(r["kind"]))
	_reactions.clear()
	close()


## Text speed in characters per second (0 = instant).
static func text_speed() -> float:
	return maxf(0.0, float(Settings.get_v("text_speed")))


## Shows square brackets literally in a BBCode label.
static func bb_escape(t: String) -> String:
	return t.replace("[", "\u0001").replace("]", "[rb]").replace("\u0001", "[lb]")


func _on_line(n: Dictionary) -> void:
	if eng == null:
		return
	var sid := String(n.get("speaker", ""))
	var sname := String(n.get("speaker_name", ""))
	speaker_label.text = sname
	var raw := String(n.get("text", ""))
	var esc := _escape(raw)
	if sid == "narrator" or sid == "system":
		text_label.text = "[i][color=#b8b0a2]%s[/color][/i]" % esc
	else:
		text_label.text = esc
	_set_portrait(sid)
	# Reveal and voice.
	var cps := text_speed()
	_reveal_len = raw.length()
	_reveal_t = 0.0
	_revealing = cps > 0.0 and _reveal_len > 0 and visible
	text_label.visible_characters = 0 if _revealing else -1
	GameAudio.voice_stop("dialogue")
	var dur := 0.0
	if not SILENT.has(sid):
		var voice := DB.voice_for(sid)
		if sname.to_lower().contains("intercom"):
			voice["bus"] = "radio"
		dur = GameAudio.voice_line("dialogue", raw, voice, hash(String(n.get("dialogue", "")) + ":" + String(n.get("node", ""))), cps)
	var read_time := float(_reveal_len) / cps if cps > 0.0 else float(_reveal_len) / 45.0
	var w := Game.world as World
	if w != null:
		w.dialogue_present(sid, maxf(dur, minf(read_time, 8.0)) if not SILENT.has(sid) else 0.0, String(n.get("anim", "")), String(n.get("shot", "")))
	# Check result, reactions and remaining effect lines.
	var logs := eng.take_log()
	var ck: Dictionary = n.get("check", {})
	var lines: PackedStringArray = []
	if not ck.is_empty():
		lines.append("[color=%s]%s check (%s): d20 %d %s = %d vs DC %d — %s[/color]" % ["#5fd38a" if ck["success"] else "#ff6a5a", DB.skill(String(ck["skill"])).get("name", ""), ck["actor_name"], ck["natural"], Rules.signed(int(ck["bonus"])), ck["total"], ck["dc"], "SUCCESS" if ck["success"] else "FAILURE"])
	var sting := ""
	for r in _reactions:
		lines.append("[color=%s]%s[/color]" % [String(r["color"]), _escape(String(r["plain"]))])
		if sting == "" or String(r["sound"]).begins_with("align"):
			sting = String(r["sound"])
		if r.has("uid") and w != null:
			w.dialogue_react(String(r["uid"]), int(r["delta"]))
	_reactions.clear()
	if sting != "":
		GameAudio.play(sting, -6.0)
	for l in _filter_logs(logs):
		if String(l).contains("check (") and not ck.is_empty():
			continue
		lines.append("[color=#f2c26b]%s[/color]" % _escape(String(l)))
	check_label.text = "\n".join(lines)
	check_label.visible = not lines.is_empty()
	_build_choices(n)
	history_text.text = _history_bb()


func _escape(t: String) -> String:
	return bb_escape(t)


## Effect log lines that reactions already show (approval, alignment,
## experience, discoveries) are dropped so nothing is listed twice.
func _filter_logs(logs: Array) -> Array:
	var out: Array = []
	for l in logs:
		var s := String(l)
		if s.begins_with("Mercy ") or s.begins_with("Dominion ") or s.contains(" influence ") or (s.begins_with("+") and s.ends_with(" XP")) or s.begins_with("Discovery: "):
			continue
		out.append(s)
	return out


## Story feedback raised by effects while the conversation is open.
func _on_game_event(ev: String, data: Dictionary) -> void:
	if not visible or eng == null:
		return
	match ev:
		"influence_changed":
			var d := int(data.get("delta", 0))
			if d == 0:
				return
			var uid := String(data.get("companion", ""))
			var nm := String(DB.companions.get(uid, {}).get("name", uid))
			_reactions.append({"plain": "%s %s (%s%d)" % [nm, "approves" if d > 0 else "disapproves", "+" if d > 0 else "", d],
				"color": "#5fd38a" if d > 0 else "#ff8a7a", "sound": "infl_up" if d > 0 else "infl_down", "kind": "approve" if d > 0 else "disapprove", "uid": uid, "delta": d})
		"alignment_changed":
			var a := int(data.get("delta", 0))
			if a == 0:
				return
			_reactions.append({"plain": "%s +%d" % ["Mercy" if a > 0 else "Dominion", absi(a)],
				"color": UIKit.MERCY.to_html(false) if a > 0 else UIKit.DOMINION.to_html(false),
				"sound": "align_mercy" if a > 0 else "align_dominion", "kind": "mercy" if a > 0 else "dominion"})
		"xp_gained":
			var x := int(data.get("amount", 0))
			if x > 0:
				_reactions.append({"plain": "+%d XP" % x, "color": "#b9a7ff", "sound": "", "kind": "xp"})
		"discovery":
			var title := String(DB.codex.get(String(data.get("id", "")), {}).get("title", ""))
			if title != "":
				_reactions.append({"plain": "Codex updated: %s" % title, "color": "#f2c26b", "sound": "", "kind": "discovery"})


func _set_portrait(sid: String) -> void:
	portrait.texture = null
	if sid in ["warden", "intercom", "terminal", "system"]:
		portrait.texture = _glyph(sid)
		return
	var w := Game.world as World
	if w == null or main == null:
		return
	var hud: Variant = main.get("hud")
	if hud == null:
		return
	var s: CharacterSheet = null
	if sid == "player":
		s = Game.state.player()
	elif w.actors.has(sid):
		s = (w.actors[sid] as Actor).sheet
	elif w.dialogue_npc != null and sid != "narrator":
		s = w.dialogue_npc.sheet
	if s != null:
		portrait.texture = (hud as HUD).portraits.texture_for(s, 160)


## Drawn portraits for voices with no face: WARDEN's eye, the intercom
## grille, a terminal screen.
func _glyph(sid: String) -> Texture2D:
	if _glyphs.has(sid):
		return _glyphs[sid]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.03, 0.035, 0.05, 1.0))
	var c := Vector2(n * 0.5, n * 0.5)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var r := p.distance_to(c)
			var col := Color(0, 0, 0, 0)
			match sid:
				"warden":
					if r < 9.0:
						col = Color("#ffd0c0")
					elif r < 20.0:
						col = Color("#ff3a2a").lerp(Color("#5a0a08"), (r - 9.0) / 11.0)
					elif absf(r - 34.0) < 2.0 or absf(r - 50.0) < 1.2:
						col = Color("#a8261c")
				"intercom":
					if absf(r - 52.0) < 2.0:
						col = Color("#e8823a")
					elif r < 46.0 and int(y) % 9 < 4:
						col = Color("#6b5a48")
				_:
					if x > 14 and x < n - 14 and y > 22 and y < n - 22:
						col = Color("#0f2a28") if int(y) % 6 < 4 else Color("#123430")
						if y > 40 and y < 46 and x < 90 or y > 56 and y < 62 and x < 70 or y > 72 and y < 78 and x < 100:
							col = Color("#3fb6b0")
			if col.a > 0.0:
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_glyphs[sid] = tex
	return tex


func _build_choices(n: Dictionary) -> void:
	UIKit.clear(choices_box)
	_choice_rows.clear()
	var chs: Array = n.get("choices", [])
	if chs.is_empty():
		var b := UIKit.button("Continue  [Space]", func() -> void: _continue())
		choices_box.add_child(b)
		_focus_later(b)
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
		var row := UIKit.hbox(6)
		var tone := String(cd.get("tone", ""))
		var strip := ColorRect.new()
		strip.custom_minimum_size = Vector2(5, 0)
		strip.color = TONE_COLORS.get(tone, Color(0, 0, 0, 0))
		strip.tooltip_text = ("Tone: " + tone) if tone != "" else ""
		strip.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(strip)
		var b2 := UIKit.button(txt, func() -> void: eng.choose(int(cd["index"])))
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.add_theme_font_size_override("font_size", 18)
		if tone != "":
			b2.tooltip_text = "Tone: " + tone
		if tag.begins_with("Resonance"):
			b2.add_theme_color_override("font_color", UIKit.MERCY)
		elif tag != "":
			b2.add_theme_color_override("font_color", UIKit.ACCENT2)
		if not bool(cd.get("enabled", true)):
			b2.disabled = true
			b2.text = txt + "   — " + String(cd.get("reason", "unavailable"))
		row.add_child(b2)
		choices_box.add_child(row)
		_choice_rows.append(cd)
		if i == 1:
			_focus_later(b2)


func _process(delta: float) -> void:
	if not _revealing:
		return
	_reveal_t += delta
	var shown := int(_reveal_t * text_speed())
	if shown >= _reveal_len:
		_finish_reveal()
	else:
		text_label.visible_characters = shown


func _finish_reveal() -> void:
	_revealing = false
	text_label.visible_characters = -1
	call_deferred("_grab", _focus_btn)


## Keyboard focus goes to the first choice only once the line has finished,
## so Space while a line is still appearing completes it instead of choosing.
func _focus_later(b: Button) -> void:
	_focus_btn = b
	if _revealing:
		var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
		if f != null:
			f.release_focus()
	else:
		call_deferred("_grab", b)


func _grab(b: Button) -> void:
	if b != null and is_instance_valid(b) and b.is_inside_tree() and b.is_visible_in_tree():
		b.grab_focus()


func is_revealing() -> bool:
	return _revealing


## Space / Enter / a click on the panel: finish the line first, then advance.
func _continue() -> void:
	if _revealing:
		_finish_reveal()
		return
	if eng != null and _choice_rows.is_empty():
		eng.advance()


func _on_panel_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.is_pressed() and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and _revealing:
		_finish_reveal()
		accept_event()


func _skip() -> void:
	if eng != null:
		_finish_reveal()
		eng.skip_lines()


func _toggle_history() -> void:
	history_panel.visible = not history_panel.visible
	history_text.text = _history_bb()


func _history_bb() -> String:
	var out: PackedStringArray = []
	var h := Game.state.dialogue_history
	for i in range(maxi(0, h.size() - 80), h.size()):
		var e: Dictionary = h[i]
		var sp := bb_escape(String(e.get("speaker", "")))
		var tx := bb_escape(String(e.get("text", "")))
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
				_finish_reveal()
				eng.choose(int(_choice_rows[idx]["index"]))
			get_viewport().set_input_as_handled()
		elif k == KEY_SPACE or k == KEY_ENTER:
			if _revealing or _choice_rows.is_empty():
				_continue()
				get_viewport().set_input_as_handled()
		elif k == KEY_ESCAPE:
			if history_panel.visible:
				history_panel.visible = false
			get_viewport().set_input_as_handled()
