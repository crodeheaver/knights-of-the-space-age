class_name Cinematics
extends Control
## Short in-engine cinematics from data/cinematics.json: letterbox bars,
## captions, title cards, fades and a scripted camera path on the World's
## cinematic camera, while the world is modal ("cinematic") so nothing
## simulates and saving is blocked. A shot with a `speaker` babbles its
## caption in that voice. Any key or click skips. When it ends, the follow-up
## dialogue (the `then` argument, or the cinematic's own `then`) starts.

var main: Node
var id := ""
var then_dialogue := ""
var _def: Dictionary = {}
var _shots: Array = []
var _i := -1
var _t := 0.0
var _caption: Label
var _title: Label
var _fade: ColorRect
var _bars: Array[ColorRect] = []
var _craft: Node3D
var _craft_start := Vector3.ZERO
var _done := false
var _hidden: Array[Node3D] = []


static func play(m: Node, cid: String, then: String = "") -> void:
	var w: World = Game.world
	var def: Dictionary = DB.cinematics.get(cid, {})
	if then == "":
		then = String(def.get("then", ""))
	if w == null or def.is_empty():
		if w != null and then != "":
			w.start_dialogue(then)
		return
	var c := Cinematics.new()
	c.main = m
	c.id = cid
	c.then_dialogue = then
	(m.get("screen") as Control).add_child(c)


func _ready() -> void:
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.full_rect(_fade)
	add_child(_fade)
	for i in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		if i == 0:
			UIKit.anchor(b, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 120))
		else:
			UIKit.anchor(b, Vector4(0, 1, 1, 1), Vector4(0, -150, 0, 0))
		add_child(b)
		_bars.append(b)
	_title = UIKit.label("", 64, UIKit.ACCENT2)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.anchor(_title, Vector4(0, 0.5, 1, 0.5), Vector4(0, -90, 0, -10))
	add_child(_title)
	_caption = UIKit.label("", 26, UIKit.TEXT, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.anchor(_caption, Vector4(0.1, 1, 0.9, 1), Vector4(0, -130, 0, -40))
	add_child(_caption)
	var skip := UIKit.label("Press any key to skip", 14, UIKit.DIM)
	UIKit.anchor(skip, Vector4(1, 0, 1, 0), Vector4(-260, 40, -20, 80))
	add_child(skip)
	_def = DB.cinematics.get(id, {})
	_shots = _def.get("shots", [])
	visible = false


func _process(delta: float) -> void:
	var w: World = Game.world
	if w == null:
		queue_free()
		return
	# Wait for the conversation that triggered us to close.
	if _i < 0:
		if w.dialogue != null and w.dialogue.active:
			return
		_begin(w)
		return
	if _done:
		return
	_t += delta
	var sh: Dictionary = _shots[_i]
	var dur := float(sh["dur"])
	var k := clampf(_t / dur, 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, k)
	# Fades: in over the first second of a title card, out at a shot's end.
	var fade := 0.0
	if bool(sh.get("black", false)):
		fade = 1.0
		_title.modulate.a = clampf(_t / 1.0, 0.0, 1.0) * clampf((dur - _t) / 0.8, 0.0, 1.0)
		_caption.modulate.a = _title.modulate.a
	else:
		var fo := float(sh.get("fade_out", 0.0))
		if fo > 0.0:
			fade = clampf((_t - (dur - fo)) / fo, 0.0, 1.0)
		if _i > 0 and bool(_shots[_i - 1].get("black", false)):
			fade = maxf(fade, clampf(1.0 - _t / 1.0, 0.0, 1.0))
		_caption.modulate.a = clampf(_t / 0.5, 0.0, 1.0)
	_fade.color.a = fade
	if not bool(sh.get("black", false)):
		var from := _v3(sh["from"])
		var to := _v3(sh["to"])
		var look := _v3(sh["look"])
		var cam := w.cam.cine_cam
		cam.global_position = from.lerp(to, e)
		if bool(sh.get("fly", false)) and _craft != null:
			_craft.position = _craft_start + Vector3(e * e * 30.0, e * 2.5, 0.0)
			look = _craft.position + Vector3(0, 1.6, 0)
		cam.look_at(look, Vector3.UP)
	if k >= 1.0:
		_next(w)


func _begin(w: World) -> void:
	visible = true
	w.set_modal("cinematic", true)
	w.cam.cinematic = true
	w.cam.scripted = true
	w.cam.cine_cam.current = true
	var craft := String(_def.get("craft", ""))
	if craft != "":
		_craft = w.find_child(craft, true, false) as Node3D
		if _craft != null:
			_craft_start = _craft.position
	if bool(_def.get("hide_party", false)):
		for p in w.party_actors():
			var a: Actor = p
			if a.visible:
				a.visible = false
				_hidden.append(a)
	if bool(_def.get("hide_enemies", false)):
		for o in w.actors.values():
			var e: Actor = o
			if e.role == "enemy" and e.visible:
				e.visible = false
				_hidden.append(e)
	if String(_def.get("sound", "")) != "":
		GameAudio.play(String(_def["sound"]), -4.0)
	_i = -1
	_next(w)


func _next(w: World) -> void:
	_i += 1
	_t = 0.0
	if _i >= _shots.size():
		_finish(w)
		return
	var sh: Dictionary = _shots[_i]
	_title.text = String(sh.get("title", ""))
	_caption.text = String(sh.get("caption", ""))
	var sp := String(sh.get("speaker", ""))
	_caption.add_theme_color_override("font_color", Color("#ff8a7a") if sp == "warden" else UIKit.TEXT)
	GameAudio.voice_stop("dialogue")
	if sp != "":
		GameAudio.voice_line("dialogue", _caption.text, DB.voice_for(sp), hash(id + str(_i)))


func _finish(w: World) -> void:
	if _done:
		return
	_done = true
	GameAudio.voice_stop("dialogue")
	w.cam.scripted = false
	w.cam.end_cinematic()
	w.set_modal("cinematic", false)
	for a in _hidden:
		if is_instance_valid(a):
			a.visible = true
	if then_dialogue != "":
		w.start_dialogue(then_dialogue)
	queue_free()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.is_pressed():
		_skip()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.is_pressed() and not (ev as InputEventKey).echo:
		get_viewport().set_input_as_handled()
		_skip()


func _skip() -> void:
	var w: World = Game.world
	if w == null or _i < 0:
		return
	if _craft != null:
		_craft.position = _craft_start + Vector3(30.0, 2.5, 0.0)
	_finish(w)


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
