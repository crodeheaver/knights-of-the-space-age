class_name DialogueStage
extends RefCounted
## Conversation staging: who looks at whom, who talks and gestures, and how
## the cinematic camera frames each line (KOTOR-style over-the-shoulder,
## close-up and two-shot cuts that keep to one side of the line).
## Visual-only: it turns ActorVisual nodes and moves the cinematic camera,
## never Actor positions, facing or any other simulation state.

const VOICELESS := ["narrator", "system"]
const SHIP_VOICES := ["warden", "intercom", "terminal"]

var world: World
var npc: Actor
var lead: Actor
var object_pos := Vector3.ZERO
var has_object := false
var participants: Array[Actor] = []
var side := 1.0
var lines := 0
## Whoever is speaking the current line (for the voice glow).
var speaking: Actor = null
var _last_speaker := ""
var _last_shot := ""


func _init(w: World, n: Actor, ctx: Dictionary) -> void:
	world = w
	npc = n
	lead = w.controlled()
	var oid := String(ctx.get("object", ""))
	if oid != "" and w.objects.has(oid):
		object_pos = (w.objects[oid] as WorldObject).center
		has_object = true
	_add(lead)
	_add(npc)
	if lead != null:
		for p in w.party_actors():
			var a: Actor = p
			if a.position.distance_to(lead.position) < 10.0:
				_add(a)
	side = _pick_side()


func _add(a: Actor) -> void:
	if a == null or not is_instance_valid(a) or a.visual == null or participants.has(a):
		return
	participants.append(a)
	a.visual.pres_on = true


## The actor who speaks a line, joining the scene if they are nearby.
func resolve(sid: String) -> Actor:
	if lead == null:
		return null
	if sid == "player":
		return world.actors.get("player", lead)
	if world.actors.has(sid):
		var a: Actor = world.actors[sid]
		if a.position.distance_to(lead.position) < 16.0 and not a.sheet.dead:
			_add(a)
			return a
		return null
	if npc != null and not VOICELESS.has(sid) and not SHIP_VOICES.has(sid):
		# Speakers named only in the conversation (a squad leader, a voice
		# on the other side of a door) are the person we are talking to.
		return npc
	return null


static func head_height(a: Actor) -> float:
	if a == null or a.visual == null:
		return 1.55
	match a.visual.model:
		"spider":
			return 0.55
		"turret":
			return 1.05
		"drone", "drone_support":
			return 1.5
		"sentinel":
			return 2.05
	if a.visual.down_amt > 0.5:
		return 0.35
	return 1.55 * a.visual.body.scale.y if a.visual.body != null else 1.55


static func head_pos(a: Actor) -> Vector3:
	return a.position + Vector3(0, head_height(a), 0)


## Stages one line: gaze, talking, a gesture, and the camera shot.
## `shot` comes from the dialogue data ("" picks one automatically).
func present(sid: String, dur: float, anim: String, shot: String) -> void:
	if lead == null:
		return
	lines += 1
	var first := lines == 1
	var sp := resolve(sid)
	speaking = sp
	if sp == null:
		_present_offstage(sid, shot, first)
		_last_speaker = sid
		return
	var listener: Actor = null
	var listen_pos := Vector3.ZERO
	var listen_h := 1.55
	var lead_like: bool = sp == lead or sp == world.actors.get("player", null)
	if lead_like:
		if npc != null and npc != sp:
			listener = npc
		elif has_object:
			listen_pos = object_pos
			listen_h = 1.3
		else:
			for p in participants:
				if p != sp:
					listener = p
					break
	else:
		listener = lead if lead != sp else npc
	if listener != null:
		listen_pos = listener.position
		listen_h = head_height(listener)
	elif listen_pos == Vector3.ZERO:
		listen_pos = sp.position + Vector3(sin(sp.rotation.y), 0, cos(sp.rotation.y)) * 2.0
	for p in participants:
		if not is_instance_valid(p):
			continue
		if p == sp:
			p.visual.look_at_point(listen_pos + Vector3(0, listen_h, 0))
		else:
			p.visual.look_at_point(head_pos(sp))
	sp.visual.talk(dur + 0.2)
	if anim != "":
		sp.visual.gesture(anim)
	var s := shot
	if s == "keep":
		_last_speaker = sid
		return
	if s == "":
		# A two-shot only when they stand close; across a room, start over
		# the shoulder.
		if first and npc != null and sp.position.distance_to(listen_pos) < 4.5:
			s = "two"
		elif sid == _last_speaker:
			# A run of lines from one speaker alternates close-up and
			# over-the-shoulder, like coverage cut together.
			s = "ots" if _last_shot == "close" else "close"
		else:
			s = "ots"
	world.cam.frame_shot(sp.position, listen_pos, s, side, first, head_height(sp), listen_h)
	_last_speaker = sid
	_last_shot = s


## Lines from nobody standing here: the narrator, system text, or a ship
## voice (WARDEN, the intercom, a terminal).
func _present_offstage(sid: String, shot: String, first: bool) -> void:
	if SHIP_VOICES.has(sid):
		var at := object_pos if has_object else Vector3.ZERO
		for p in participants:
			if is_instance_valid(p) and has_object:
				p.visual.look_at_point(object_pos + Vector3(0, 1.3, 0))
		if shot == "keep":
			return
		if has_object:
			world.cam.frame_shot(at, lead.position, "ots" if shot == "" else shot, side, first, 1.3, head_height(lead))
		else:
			# A voice from the speakers: hold on the listener's face.
			var front := lead.position + Vector3(sin(lead.rotation.y), 0, cos(lead.rotation.y)) * 2.0
			world.cam.frame_shot(lead.position, front, "close", side, first, head_height(lead), 1.55)
		return
	# Narration and system text keep the current shot; the first line of a
	# conversation that opens with narration still gets an establishing view.
	if first and shot != "keep":
		if npc != null:
			var near := npc.position.distance_to(lead.position) < 4.5
			world.cam.frame_shot(npc.position, lead.position, "two" if near else "ots", side, true, head_height(npc), head_height(lead))
		elif has_object:
			world.cam.frame_shot(object_pos, lead.position, "ots", side, true, 1.3, head_height(lead))


## A companion's visible reaction to an influence change.
func react(uid: String, delta: int) -> void:
	var a: Actor = world.actors.get(uid, null)
	if a == null or not participants.has(a):
		return
	a.visual.gesture("nod" if delta > 0 else "shake")


func tick(dt: float) -> void:
	for p in participants:
		if is_instance_valid(p) and p.visual != null:
			p.visual.present(dt, true)


func clear() -> void:
	for p in participants:
		if is_instance_valid(p) and p.visual != null:
			p.visual.clear_presentation()
	participants.clear()


## Keeps the camera on the side of the line with more room (walls).
func _pick_side() -> float:
	if lead == null or world.cam == null:
		return 1.0
	var focus := npc.position if npc != null else (object_pos if has_object else Vector3.ZERO)
	if focus == Vector3.ZERO or focus.distance_to(lead.position) < 0.2:
		return 1.0
	var dir := focus - lead.position
	dir.y = 0
	dir = dir.normalized()
	var look := focus + Vector3(0, 1.55, 0)
	var best := 1.0
	var best_d := -1.0
	for sgn: float in [1.0, -1.0]:
		var sidev := Vector3(-dir.z, 0, dir.x) * sgn
		var eye := lead.position - dir * 1.9 + sidev * 1.15 + Vector3(0, 1.75, 0)
		var d := world.cam.safe_eye(look, eye).distance_to(look)
		if d > best_d + 0.05:
			best_d = d
			best = sgn
	return best
