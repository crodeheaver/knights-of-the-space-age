class_name MainMenu
extends Control
## Title screen.

var main: Node
var stars: Array = []
var t := 0.0
var menu_box: VBoxContainer
var sub_box: Control


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	for i in 220:
		stars.append(Vector3(randf(), randf(), randf_range(0.2, 1.0)))
	var v := UIKit.vbox(10)
	v.position = Vector2(140, 240)
	v.custom_minimum_size = Vector2(520, 0)
	add_child(v)
	v.add_child(UIKit.label("ASHES OF THE CONCORD", 64, UIKit.ACCENT2))
	v.add_child(UIKit.label("An evacuation, a ship that knows your mind, and the truth it carries.", 20, UIKit.DIM))
	v.add_child(UIKit.spacer(0, 30))
	menu_box = UIKit.vbox(8)
	v.add_child(menu_box)
	var latest := Saves.latest_slot()
	if latest != "":
		menu_box.add_child(_b("Continue  (%s)" % latest.replace("_", " "), func() -> void: main.load_from_slot(latest)))
	menu_box.add_child(_b("New Game", func() -> void: main.show_creator()))
	menu_box.add_child(_b("Load Game", func() -> void: _open_load()))
	menu_box.add_child(_b("Simulation Deck (practice recreation)", func() -> void: _sim_deck()))
	menu_box.add_child(_b("Settings", func() -> void: _open_settings()))
	if bool(Settings.get_v("dev_mode")):
		menu_box.add_child(_b("Developer Presets", func() -> void: _presets()))
	menu_box.add_child(_b("Credits & Licenses", func() -> void: _credits()))
	menu_box.add_child(_b("Quit", func() -> void: get_tree().quit()))
	var ver := UIKit.label("v%s · Godot %s · original content, see docs/ASSETS.md" % [ProjectSettings.get_setting("application/config/version", "0"), Engine.get_version_info()["string"]], 14, UIKit.DIM)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(20, -40)
	add_child(ver)


func _b(text: String, cb: Callable) -> Button:
	var b := UIKit.button(text, cb)
	b.custom_minimum_size = Vector2(480, 48)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	return b


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#04060a"))
	for s in stars:
		var x := fmod(s.x + t * 0.004 * s.z, 1.0) * size.x
		var y: float = s.y * size.y
		draw_rect(Rect2(x, y, 2.0 * s.z, 2.0 * s.z), Color(0.8, 0.85, 1.0, s.z * 0.8))
	var c := Vector2(size.x * 0.72, size.y * 0.58)
	draw_circle(c, 260, Color("#3a1d10"))
	draw_circle(c + Vector2(-30, -20), 240, Color("#7a3a1a"))
	draw_circle(c + Vector2(-60, -40), 200, Color("#b8622a", 0.6))
	draw_arc(c, 300, PI * 1.05, PI * 1.6, 64, Color("#e8823a", 0.5), 3.0)
	# The Cinder Wake silhouette
	var sp := Vector2(size.x * 0.55 + sin(t * 0.2) * 6.0, size.y * 0.32)
	draw_rect(Rect2(sp, Vector2(220, 26)), Color("#1a1d22"))
	draw_rect(Rect2(sp + Vector2(40, -12), Vector2(90, 12)), Color("#1a1d22"))
	draw_rect(Rect2(sp + Vector2(-30, 6), Vector2(30, 14)), Color("#e8823a"))


func _open_load() -> void:
	var s := SaveLoadUI.new()
	s.main = main
	s.mode = "load"
	s.standalone = true
	add_child(s)


func _open_settings() -> void:
	var s := SettingsUI.new()
	s.main = main
	s.standalone = true
	add_child(s)


func _sim_deck() -> void:
	var p := PanelBase.new()
	p.main = null
	add_child(p)
	var v := p.make_window("Simulation Deck", Vector2(620, 420))
	v.add_child(UIKit.label("Practice the Cinder Wake's recreation programs. No credits are wagered and nothing carries into a saved game.", 17, UIKit.TEXT, true))
	for m in [["Shards (card game)", "shards"], ["Slipstream (hover racing)", "slipstream"], ["Turret gunnery drill", "turret"]]:
		var mid := String(m[1])
		v.add_child(UIKit.button(String(m[0]), func() -> void: Minigames.open_practice(self, mid)))


func _presets() -> void:
	var p := PanelBase.new()
	add_child(p)
	var v := p.make_window("Developer Presets (testing only)", Vector2(900, 640))
	v.add_child(UIKit.label("These load the same ship with characters and story conditions prepared to demonstrate later-game systems. They are not normal saves and are never written to save slots.", 16, UIKit.WARN, true))
	var list := UIKit.vbox(4)
	for pid in DB.dev_presets.keys():
		var pd: Dictionary = DB.dev_presets[pid]
		var b := UIKit.button("%s — %s" % [pd.get("name", pid), pd.get("desc", "")], func() -> void: DevTools.load_preset(String(pid)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		list.add_child(b)
	v.add_child(UIKit.scroll(list, 460))


func _credits() -> void:
	var p := PanelBase.new()
	add_child(p)
	var v := p.make_window("Credits & Licenses", Vector2(860, 600))
	var txt := "[b]Ashes of the Concord[/b] — original vertical slice.\n\nAll characters, factions, story, dialogue, art and audio are original to this project. Geometry is procedural; sound effects and music are synthesized by tools/gen_audio.py.\n\nBuilt with the [b]Godot Engine[/b] (MIT license, © Juan Linietsky, Ariel Manzur and contributors). Godot's default UI font is used under its open license.\n\nFull manifest: docs/ASSETS.md."
	v.add_child(UIKit.rich(txt, 18))
