class_name ShipLife
extends Node
## The ship and party talking outside conversations (data/ship_life.json):
## companions bark in combat, banter while exploring and react to choices;
## WARDEN and the purser make shipwide announcements; a companion with
## something on their mind asks to talk. Lines show as speech bubbles over the
## speaker (and as captions when Settings → captions are on), go to the log,
## and are babbled in the speaker's voice.
##
## Presentation only: Main adds it to the World, so tests and bots run without
## it unless a test adds one. It never touches the simulation; the only state
## it writes are one-time "chatter:<id>" ledger keys and the hook flags that
## open a companion's new topic. Randomness is cosmetic (global randf).

const SHIP_VOICES := ["warden", "intercom"]
const BUBBLES := 3

var world: World
var cfg: Dictionary = {}
var now := 0.0  # seconds of running simulation seen by this node
var _queue: Array = []  # [{at, speaker, text, id, actor?}]
var _cool: Dictionary = {}  # line id -> time it may play again
var _speaker_free: Dictionary = {}  # speaker -> time
var _next_bark := 0.0
var _banter_t := 0.0
var _announce_t := 0.0
var _hook_t := 25.0  # no one asks to talk the moment the game loads
var _dlg_infl: Dictionary = {}
var _bubbles: Array = []  # [{label, actor, left}]
var _talker: Actor = null


func setup(w: World) -> void:
	world = w
	cfg = DB.dict(DB.ship_life, "config")
	_banter_t = _gap("banter_gap", 80.0) * _banter_mult()
	_announce_t = _gap("announce_gap", 150.0)
	for i in BUBBLES:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = false
		l.pixel_size = 0.0045
		l.font_size = 30
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.width = 520.0
		l.modulate = Color("#f2e6c8")
		l.visible = false
		l.top_level = true
		add_child(l)
		_bubbles.append({"label": l, "actor": null, "left": 0.0})
	Events.event.connect(_on_event)
	GameAudio.voice_syllable.connect(_on_syllable)
	w.presented.connect(_on_presented)


func _exit_tree() -> void:
	if Events.event.is_connected(_on_event):
		Events.event.disconnect(_on_event)
	if GameAudio.voice_syllable.is_connected(_on_syllable):
		GameAudio.voice_syllable.disconnect(_on_syllable)


## Combat beats from the World's presentation layer.
func _on_presented(kind: String, data: Dictionary) -> void:
	if kind == "crit" and bool(data.get("party", false)):
		fire("crit", data)


var _low_t := 0.0


## Companions badly hurt in a fight say so (polled once a second).
func _check_low_health(delta: float) -> void:
	_low_t -= delta
	if _low_t > 0.0:
		return
	_low_t = 1.0
	for uid in Game.state.party:
		var a: Actor = world.actors.get(uid, null)
		if a == null or a.sheet.is_downed() or a.sheet.dead:
			continue
		if float(a.sheet.hp) / float(maxi(1, a.sheet.max_hp())) < 0.3:
			fire("low_health", {"uid": String(uid)})


func _on_syllable(channel: String, amp: float) -> void:
	if channel == "world" and _talker != null and is_instance_valid(_talker):
		_talker.visual.pulse_glow(amp)


func _gap(key: String, def: float) -> float:
	var g: Variant = cfg.get(key, [def, def])
	if typeof(g) == TYPE_ARRAY and (g as Array).size() == 2:
		return randf_range(float(g[0]), float(g[1]))
	return float(g)


## Settings → Party chatter: off / rare / normal / often.
static func _banter_mult() -> float:
	match String(Settings.get_v("banter")):
		"off":
			return -1.0
		"rare":
			return 2.0
		"often":
			return 0.5
	return 1.0


# ---------------------------------------------------------------- events
func _on_event(ev: String, data: Dictionary) -> void:
	if world == null:
		return
	match ev:
		"world_effect":
			if String(data.get("type", "")) == "bark":
				say_line(String(data.get("id", "")), true)
		"dialogue_started":
			_dlg_infl.clear()
		"influence_changed":
			if world.modal.has("dialogue"):
				var c := String(data.get("companion", ""))
				_dlg_infl[c] = int(_dlg_infl.get(c, 0)) + int(data.get("delta", 0))
		"dialogue_ended":
			for c in _dlg_infl.keys():
				var d := int(_dlg_infl[c])
				if d >= 3:
					fire("approve", {"uid": c}, 1.5)
				elif d <= -2:
					fire("disapprove", {"uid": c}, 1.5)
			_dlg_infl.clear()
		"flag_changed":
			fire("flag", data)
		"combat_started", "combat_ended", "encounter_started", "enemy_killed", "ally_downed", "ally_recovered", "area_entered", "rested":
			fire(ev, data)


## Plays a fitting line for an event, if any is available.
func fire(on: String, data: Dictionary, delay: float = 0.0) -> void:
	var cands: Array = []
	for sec in ["barks", "announcements"]:
		for l in DB.arr(DB.ship_life, sec):
			var line: Dictionary = l
			if String(line.get("on", "")) != on:
				continue
			if not _matches(line, data):
				continue
			if (on == "approve" or on == "disapprove") and String(line["speaker"]) != String(data.get("uid", "")):
				continue
			if not _playable(line, false):
				continue
			cands.append(line)
	if cands.is_empty():
		return
	var pick: Dictionary = cands[randi() % cands.size()]
	if randf() > float(pick.get("chance", 1.0)):
		return
	_play(pick, delay + float(pick.get("delay", 0.0)))


## Plays a specific line by id (the `bark` effect). `forced` skips chance.
func say_line(id: String, forced: bool = false) -> bool:
	var line := DB.ship_line(id)
	if line.is_empty() or not _playable(line, forced):
		return false
	_play(line, float(line.get("delay", 0.0)))
	return true


func _matches(line: Dictionary, data: Dictionary) -> bool:
	var m: Dictionary = line.get("match", {})
	for k in m.keys():
		var want: Variant = m[k]
		var got: Variant = data.get(k, null)
		if typeof(want) == TYPE_ARRAY:
			if not (want as Array).has(got):
				return false
		elif got != want and not (typeof(got) in [TYPE_INT, TYPE_FLOAT] and typeof(want) in [TYPE_INT, TYPE_FLOAT] and float(got) == float(want)):
			return false
	return true


func _playable(line: Dictionary, forced: bool) -> bool:
	var id := String(line.get("id", ""))
	var sp := String(line.get("speaker", ""))
	var ship := SHIP_VOICES.has(sp)
	if not ship and _banter_mult() < 0.0:
		return false
	if bool(line.get("once", false)) and Game.state.claimed("chatter:" + id):
		return false
	if float(_cool.get(id, -1.0)) > now:
		return false
	if not Conditions.eval_all(line.get("if", []), Game.state):
		return false
	if not ship:
		if not forced and now < _next_bark:
			return false
		if float(_speaker_free.get(sp, -1.0)) > now:
			return false
		if speaker_actor(sp) == null:
			return false
	return true


func _play(line: Dictionary, delay: float) -> void:
	var id := String(line.get("id", ""))
	if bool(line.get("once", false)) and not Game.state.claim("chatter:" + id):
		return
	_cool[id] = now + float(line.get("cooldown", cfg.get("cooldown", 90.0)))
	var sp := String(line["speaker"])
	if not SHIP_VOICES.has(sp):
		_next_bark = now + float(cfg.get("bark_gap", 6.0))
		_speaker_free[sp] = now + float(cfg.get("speaker_gap", 10.0))
	_queue.append({"at": now + delay, "speaker": sp, "text": String(line["text"]), "id": id})


## The actor who would say a line: a party member near the leader, a named
## NPC, or the nearest living enemy of a kind ("reclaimer", "drone").
func speaker_actor(sp: String) -> Actor:
	var lead := world.controlled()
	if lead == null:
		return null
	var rng := float(cfg.get("range", 18.0))
	if world.actors.has(sp):
		var a: Actor = world.actors[sp]
		if a.sheet.dead or a.sheet.is_downed() or not a.visible:
			return null
		if a.role == "party" and not Game.state.party.has(sp):
			return null
		if a.position.distance_to(lead.position) > rng:
			return null
		return a
	if sp == "reclaimer" or sp == "drone":
		var best: Actor = null
		var bd := 22.0
		for o in world.actors.values():
			var e: Actor = o
			if e.role != "enemy" or e.sheet.dead or e.sheet.is_downed() or not e.alert:
				continue
			var is_drone := e.sheet.faction == "warden"
			if (sp == "drone") != is_drone:
				continue
			var d := e.position.distance_to(lead.position)
			if d < bd:
				bd = d
				best = e
		return best
	return null


# ---------------------------------------------------------------- timers
func _process(delta: float) -> void:
	if world == null:
		return
	var staged := world.modal.has("dialogue") or world.modal.has("cinematic")
	for b in _bubbles:
		(b["label"] as Label3D).visible = not staged and float(b["left"]) > 0.0 and is_instance_valid(b["actor"])
	if not world.sim_running():
		return
	now += delta
	_update_bubbles(delta)
	# Queued lines whose time has come (a speaker who has fallen stays quiet).
	var i := 0
	while i < _queue.size():
		var q: Dictionary = _queue[i]
		# The party waits for a shipwide announcement to finish.
		if float(q["at"]) <= now and not SHIP_VOICES.has(String(q["speaker"])) and GameAudio.voice_active("ship"):
			q["at"] = now + 0.4
		if float(q["at"]) <= now:
			_queue.remove_at(i)
			_speak(String(q["speaker"]), String(q["text"]), String(q["id"]))
		else:
			i += 1
	var calm := not world.combat.active
	if not calm:
		_check_low_health(delta)
	if calm:
		_hook_t -= delta
		if _hook_t <= 0.0:
			_hook_t = 150.0 if _check_hooks() else 2.0
		var bm := _banter_mult()
		if bm > 0.0:
			_banter_t -= delta
			if _banter_t <= 0.0:
				_banter_t = (_gap("banter_gap", 80.0) if try_banter() else 20.0) * bm
		_announce_t -= delta
		if _announce_t <= 0.0:
			fire("timer", {})
			_announce_t = _gap("announce_gap", 150.0)


## Starts the best available banter exchange here; true if one started.
func try_banter() -> bool:
	var area := world.current_area
	var best: Dictionary = {}
	var best_p := -1
	for b in DB.arr(DB.ship_life, "banter"):
		var bt: Dictionary = b
		var id := String(bt.get("id", ""))
		var ba := String(bt.get("area", "any"))
		if ba != "any" and ba != area:
			continue
		if bool(bt.get("once", true)) and Game.state.claimed("chatter:" + id):
			continue
		if float(_cool.get(id, -1.0)) > now:
			continue
		if not Conditions.eval_all(bt.get("if", []), Game.state):
			continue
		var ok := true
		for l in bt.get("lines", []):
			if speaker_actor(String(l["speaker"])) == null:
				ok = false
				break
		if not ok:
			continue
		var p := int(bt.get("priority", 1)) + (1 if ba == area else 0)
		if p > best_p or (p == best_p and randf() < 0.5):
			best = bt
			best_p = p
	if best.is_empty():
		return false
	var bid := String(best["id"])
	if bool(best.get("once", true)):
		Game.state.claim("chatter:" + bid)
	_cool[bid] = now + float(best.get("cooldown", 600.0))
	var t := now + 0.5
	for l in best.get("lines", []):
		t += float(l.get("delay", 0.0))
		_queue.append({"at": t, "speaker": String(l["speaker"]), "text": String(l["text"]), "id": bid})
		t += clampf(String(l["text"]).length() * 0.05, 1.6, 5.0)
	_next_bark = t + 2.0
	return true


# ---------------------------------------------------------------- hooks
## A companion who wants to talk: raises their hook flag (opening the topic
## in their conversation) and says so once. One at a time; true if raised.
func _check_hooks() -> bool:
	if not _queue.is_empty():
		return false
	for h in DB.arr(DB.ship_life, "hooks"):
		var hk: Dictionary = h
		var fl := String(hk["flag"])
		if Game.state.has_flag(fl):
			continue
		if not Conditions.eval_all(hk.get("if", []), Game.state):
			continue
		var comp := String(hk["companion"])
		if speaker_actor(comp) == null:
			continue
		Game.state.set_flag(fl)
		_queue.append({"at": now + 0.5, "speaker": comp, "text": String(hk.get("bark", "")), "id": String(hk["id"])})
		var nm := String(DB.companions.get(comp, {}).get("name", comp))
		Events.toast("%s wants to talk. (Party → Talk, or press %s beside them.)" % [nm, Settings.key_label("interact")], "approve")
		world.hud_changed.emit()
		return true
	return false


## The hook a companion is waiting to talk about, if any.
static func pending_hook(uid: String) -> Dictionary:
	for h in DB.arr(DB.ship_life, "hooks"):
		var hk: Dictionary = h
		if String(hk["companion"]) == uid and Game.state.has_flag(String(hk["flag"])) and not Game.state.has_flag(String(hk.get("done_flag", ""))):
			return hk
	return {}


# ---------------------------------------------------------------- speech
func _speak(sp: String, text: String, id: String) -> void:
	var nm := _speaker_name(sp)
	if SHIP_VOICES.has(sp):
		_announce(sp, nm, text, id)
		return
	var a := speaker_actor(sp)
	if a == null:
		return
	# Party and crew lines show over the speaker (and in the log); only the
	# ship's voices, which have no one to stand over, become captions.
	_show_bubble(a, text)
	Events.log_combat("%s: “%s”" % [nm, text], "", "bark")
	var lead := world.controlled()
	var dist := a.position.distance_to(lead.position) if lead != null else 0.0
	GameAudio.voice_line("world", text, DB.voice_for(sp), hash(id + text), 0.0, -3.0 - dist * 0.35)
	a.visual.talk(clampf(text.length() * 0.05, 1.2, 4.0))
	world.present_visual(a.visual)
	_talker = a


func _announce(sp: String, nm: String, text: String, id: String) -> void:
	GameAudio.play("pa_chime", -8.0)
	Events.toast("%s: “%s”" % [nm, text], "warden" if sp == "warden" else "intercom")
	Events.log_combat("%s: “%s”" % [nm, text], "", "bark")
	if sp == "warden":
		world.pulse_trims(Color("#ff4a3a"), 1.6)
	get_tree().create_timer(0.7, false).timeout.connect(func() -> void:
		if is_instance_valid(self):
			GameAudio.voice_line("ship", text, DB.voice_for(sp), hash(id), 0.0, -2.0))


func _speaker_name(sp: String) -> String:
	if DB.companions.has(sp):
		return String(DB.companions[sp]["name"])
	match sp:
		"warden":
			return "WARDEN"
		"intercom":
			return "Intercom (Purser Dray)"
		"reclaimer":
			return "Reclaimer"
		"drone":
			return "WARDEN unit"
	var npcs: Dictionary = DB.dict(DB.layout, "npcs")
	return String(npcs.get(sp, {}).get("name", sp.capitalize()))


func _show_bubble(a: Actor, text: String) -> void:
	var slot: Dictionary = _bubbles[0]
	for b in _bubbles:
		if b["actor"] == a or float(b["left"]) <= 0.0:
			slot = b
			break
	var l: Label3D = slot["label"]
	l.text = text
	slot["actor"] = a
	slot["left"] = clampf(text.length() * 0.055, 2.2, 6.0)
	_place(l, a)
	l.visible = true


func _place(l: Label3D, a: Actor) -> void:
	l.global_position = a.global_position + Vector3(0, DialogueStage.head_height(a) + 0.95, 0)


func _update_bubbles(delta: float) -> void:
	for b in _bubbles:
		var l: Label3D = b["label"]
		if float(b["left"]) <= 0.0:
			l.visible = false
			continue
		b["left"] = float(b["left"]) - delta
		if not is_instance_valid(b["actor"]):
			b["left"] = 0.0
			l.visible = false
			continue
		_place(l, b["actor"])
		l.modulate.a = clampf(float(b["left"]) / 0.4, 0.0, 1.0)


## Line currently shown over an actor (tests and the HUD).
func bubble_text(a: Actor) -> String:
	for b in _bubbles:
		if b["actor"] == a and float(b["left"]) > 0.0:
			return (b["label"] as Label3D).text
	return ""
