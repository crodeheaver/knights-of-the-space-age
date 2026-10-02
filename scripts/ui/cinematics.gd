class_name Cinematics
extends Control
## Short in-engine cinematics: letterbox bars, captions and a scripted camera
## path on the World's cinematic camera, while the world is modal
## ("cinematic") so nothing simulates and saving is blocked. Any key or click
## skips. When it ends, the follow-up dialogue (if any) starts.

const SHOTS := {
	"petrel_escape": [
		{"from": [156.0, 5.5, 20.0], "to": [158.0, 4.0, 17.0], "look": [166.0, 1.6, 8.0], "dur": 3.0,
			"caption": "The docking clamps let go with a sound like a held breath released."},
		{"from": [170.0, 3.0, 18.0], "to": [176.0, 3.5, 16.0], "look": [178.0, 2.0, 8.0], "dur": 3.5, "fly": true,
			"caption": "The Petrel slides out through Bay 2's shimmering field, into the dark above Haldis Reach."},
	],
}

var main: Node
var id := ""
var then_dialogue := ""
var _shots: Array = []
var _i := -1
var _t := 0.0
var _caption: Label
var _bars: Array[ColorRect] = []
var _craft: Node3D
var _craft_start := Vector3.ZERO
var _done := false
var _hidden: Array[Node3D] = []


static func play(m: Node, cid: String, then: String = "") -> void:
	var w: World = Game.world
	if w == null or not SHOTS.has(cid):
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
	for i in 2:
		var b := ColorRect.new()
		b.color = Color.BLACK
		if i == 0:
			UIKit.anchor(b, Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 120))
		else:
			UIKit.anchor(b, Vector4(0, 1, 1, 1), Vector4(0, -150, 0, 0))
		add_child(b)
		_bars.append(b)
	_caption = UIKit.label("", 26, UIKit.TEXT, true)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.anchor(_caption, Vector4(0.1, 1, 0.9, 1), Vector4(0, -130, 0, -40))
	add_child(_caption)
	var skip := UIKit.label("Press any key to skip", 14, UIKit.DIM)
	UIKit.anchor(skip, Vector4(1, 0, 1, 0), Vector4(-260, 40, -20, 80))
	add_child(skip)
	_shots = SHOTS[id]
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
	var k := clampf(_t / float(sh["dur"]), 0.0, 1.0)
	var e := smoothstep(0.0, 1.0, k)
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
	w.cam.cine_cam.current = true
	_craft = w.find_child("Petrel", true, false) as Node3D
	if _craft != null:
		_craft_start = _craft.position
	# The party is aboard.
	for p in w.party_actors():
		var a: Actor = p
		if a.visible:
			a.visible = false
			_hidden.append(a)
	GameAudio.play("door", -4.0)
	_i = -1
	_next(w)


func _next(w: World) -> void:
	_i += 1
	_t = 0.0
	if _i >= _shots.size():
		_finish(w)
		return
	_caption.text = String(_shots[_i].get("caption", ""))


func _finish(w: World) -> void:
	if _done:
		return
	_done = true
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
