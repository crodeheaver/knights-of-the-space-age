class_name World
extends Node3D
## The playable ship. Builds the level from data, owns actors and world
## objects, runs the deterministic simulation step (only while not paused and
## not in a modal screen), routes player commands, executes interactions and
## world effects, and synchronises live state back into GameState for saving.

signal ui_request(kind: String, data: Dictionary)
signal hud_changed

const FIXED_DT := 1.0 / 60.0

var grid := ShipGrid.new()
var actors: Dictionary = {}
var objects: Dictionary = {}
var combat: CombatManager
var fx: FX
var cam: CameraRig
var paused := false
var pause_reason := ""
var modal: Dictionary = {}
var game_over := false
var transition_lock := ""
var hover_node: Node = null
var projectiles: Array = []
var current_area := ""
var time_scale := 1.0
var manual_step := false
var _acc := 0.0
var _stealth_clock := 0.0
var _reveal_clock := 0.0
var _follow_clock := 0.0
var _trigger_clock := 0.0
var _hazard_clock := 0.0
var _aware_clock := 0.0
var _regen: Dictionary = {}
var _auto_solo := false
var _pending_interact: Dictionary = {}
var dialogue: DialogueEngine = null
var dialogue_npc: Actor = null
var bash_jobs: Array = []
var _pending_corpses: Array = []


func _ready() -> void:
	Game.world = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	grid.setup(DB.layout)
	LevelBuilder.build(self, DB.layout, grid)
	fx = FX.new()
	add_child(fx)
	_restore_explored()
	_spawn_objects()
	refresh_hazard_avoidance()
	_spawn_party()
	_spawn_npcs()
	_spawn_enemies()
	combat = CombatManager.new(self)
	cam = CameraRig.new()
	add_child(cam)
	cam.target = controlled()
	cam.snap()
	if Game.state.positions.has("_cam"):
		var cp: Array = Game.state.positions["_cam"]
		cam.yaw = float(cp[0])
		cam.pitch = float(cp[1])
		cam.distance = float(cp[2])
		cam._apply()
	Events.event.connect(_on_event)
	_restore_combat_state()
	_area_check(true)
	refresh_markers()
	GameAudio.ambient("amb_ship")
	GameAudio.music(area_music())


func _exit_tree() -> void:
	if Game.world == self:
		Game.world = null
	if Events.event.is_connected(_on_event):
		Events.event.disconnect(_on_event)


# ================================================================ spawning
func _restore_explored() -> void:
	var ex := Game.state.explored
	if ex.size() == grid.explored.size():
		grid.explored = ex.duplicate()


func _spawn_objects() -> void:
	for d in DB.layout.get("doors", []):
		var dd: Dictionary = (d as Dictionary).duplicate(true)
		dd["type"] = "door"
		if not dd.has("model"):
			dd["model"] = String(dd.get("kind", "door"))
		_add_object(dd)
	for o in DB.layout.get("objects", []):
		_add_object(o)
	# Corpses / wrecks of enemies that died earlier.
	for uid in Game.state.enemies.keys():
		var e: Dictionary = Game.state.enemies[uid]
		if String(e.get("state", "")) == "dead":
			_make_corpse(String(uid), e)
	for mid in Game.state.world.keys():
		var ws: Dictionary = Game.state.world[mid]
		if ws.has("placed_mine") and not objects.has(mid):
			_add_object(ws["placed_mine"])


func _add_object(d: Dictionary) -> WorldObject:
	var o := WorldObject.new()
	add_child(o)
	o.setup(d, self)
	objects[o.id] = o
	return o


func _spawn_party() -> void:
	var st := Game.state
	var start: Dictionary = DB.layout.get("player_start", {"pos": [6, 6], "rot": 90})
	var i := 0
	for uid in st.party:
		var s := st.get_char(uid)
		if s == null:
			continue
		var a := _make_actor(s, "party")
		if st.positions.has(uid):
			var p: Array = st.positions[uid]
			a.set_pos(Vector3(float(p[0]), 0, float(p[1])))
			a.set_facing_deg(float(p[2]) if p.size() > 2 else 0.0)
		else:
			# No saved spot: fall in beside the player (or the ship's start).
			var sp: Array = st.positions.get("player", start["pos"]) if uid != "player" else start["pos"]
			a.set_pos(grid.nearest_passable(Vector3(float(sp[0]) - i * 0.9, 0, float(sp[1]) + i * 0.6)))
			a.set_facing_deg(float(start.get("rot", 90)))
		if st.queues.has(uid):
			a.queue.from_array(st.queues[uid])
		i += 1


func _make_actor(s: CharacterSheet, role: String) -> Actor:
	var a := Actor.new()
	add_child(a)
	a.setup(s, role, self)
	actors[a.uid] = a
	return a


func _spawn_npcs() -> void:
	var npcs: Dictionary = DB.dict(DB.layout, "npcs")
	for nid in npcs.keys():
		var n: Dictionary = npcs[nid]
		var ns: Dictionary = Game.state.npcs.get(nid, {})
		if bool(ns.get("removed", false)):
			continue
		if n.has("if") and not Conditions.eval_all(n["if"], Game.state) and not bool(ns.get("spawned", false)):
			continue
		if String(ns.get("state", "")) == "enemy":
			continue  # converted to an enemy record; spawned with enemies
		spawn_npc(String(nid))


func spawn_npc(nid: String, force: bool = false) -> Actor:
	if actors.has(nid):
		return actors[nid]
	var n: Dictionary = DB.dict(DB.layout, "npcs").get(nid, {})
	if n.is_empty():
		return null
	var ns: Dictionary = Game.state.npcs.get(nid, {})
	var s: CharacterSheet
	if n.has("template"):
		s = CharacterSheet.from_template(String(n["template"]), nid)
		s.faction = String(n.get("faction", s.faction))
		if ns.has("sheet"):
			s = CharacterSheet.from_dict(ns["sheet"])
	else:
		s = CharacterSheet.new()
		s.uid = nid
		s.display_name = String(n.get("name", nid))
		s.faction = String(n.get("faction", "civilian"))
		s.kind = String(n.get("kind", "organic"))
		s.class_id = "enemy"
		s.overrides = {"hp_max": 12, "bab": 0, "saves": {}, "speed": 3.2}
		s.hp = 12
	s.display_name = String(n.get("name", s.display_name))
	var app: Dictionary = (n.get("appearance", {}) as Dictionary).duplicate()
	if not app.has("model"):
		app["model"] = String(n.get("model", "humanoid"))
	s.appearance = app
	if n.has("armor_look"):
		s.equipment["body"] = ItemInst.make(String(n["armor_look"]))
	var a := _make_actor(s, "npc")
	a.npc_id = nid
	var p: Array = ns.get("pos", n.get("pos", [0, 0]))
	a.set_pos(Vector3(float(p[0]), 0, float(p[1])))
	a.set_facing_deg(float(ns.get("rot", n.get("rot", 0))))
	a.home = a.position
	var dn: bool = bool(ns.get("downed", n.get("downed", false))) or bool(n.get("downed_pose", false))
	if dn:
		StatusRules.apply(s, "downed", 1.0)
		if not n.has("template"):
			s.hp = 0
	return a


func _spawn_enemies() -> void:
	var st := Game.state
	# Restore saved enemies exactly (positions, health, statuses, alertness).
	for uid in st.enemies.keys():
		var e: Dictionary = st.enemies[uid]
		var est := String(e.get("state", "alive"))
		if est == "dead" or est == "gone":
			continue
		var s := CharacterSheet.from_dict(e["sheet"]) if e.has("sheet") else CharacterSheet.from_template(String(e["template"]), String(uid))
		var a := _make_actor(s, "enemy")
		a.encounter_id = String(e.get("encounter", ""))
		var p: Array = e.get("pos", [0, 0, 0])
		a.set_pos(Vector3(float(p[0]), 0, float(p[1])))
		a.set_facing_deg(float(p[2]) if p.size() > 2 else 0.0)
		var h: Array = e.get("home", p)
		a.home = Vector3(float(h[0]), 0, float(h[1]))
		a.alert = bool(e.get("alert", false))
		a.hostile_override = String(e.get("hostile_override", ""))
		a.target_uid = String(e.get("target", ""))
		a.recovery = float(e.get("recovery", 0.0))
		a.round_clock = float(e.get("round_clock", 0.0))
		if e.has("queue"):
			a.queue.from_array(e["queue"])
		if e.has("npc_id"):
			a.npc_id = String(e["npc_id"])
	# Encounters that spawn at load and have not been spawned yet.
	for eid in DB.encounters.keys():
		var ed: Dictionary = DB.encounters[eid]
		if String(ed.get("spawn_on", "load")) == "load":
			spawn_encounter(String(eid))


func encounter_state(eid: String) -> Dictionary:
	if not Game.state.encounters.has(eid):
		Game.state.encounters[eid] = {"state": "pending", "spawned": false}
	return Game.state.encounters[eid]


func spawn_encounter(eid: String) -> void:
	var es := encounter_state(eid)
	if bool(es.get("spawned", false)):
		return
	var ed: Dictionary = DB.encounters.get(eid, {})
	if ed.is_empty():
		return
	if ed.has("if") and not Conditions.eval_all(ed["if"], Game.state):
		return
	es["spawned"] = true
	for sp in ed.get("spawns", []):
		var spd: Dictionary = sp
		if spd.has("if") and not Conditions.eval_all(spd["if"], Game.state):
			continue
		var uid := String(spd["uid"])
		if Game.state.enemies.has(uid):
			continue
		var s := CharacterSheet.from_template(String(spd["enemy"]), uid)
		if spd.has("faction"):
			s.faction = String(spd["faction"])
		if spd.has("hp_frac"):
			s.hp = maxi(1, int(s.max_hp() * float(spd["hp_frac"])))
		for mod in DB.arr(ed, "mods"):
			if Conditions.eval_all(mod.get("if", []), Game.state):
				if mod.has("attack_bonus"):
					s.overrides["attack_bonus"] = int(s.overrides.get("attack_bonus", 0)) + int(mod["attack_bonus"])
				if mod.has("hp_mult"):
					s.overrides["hp_max"] = int(int(s.overrides["hp_max"]) * float(mod["hp_mult"]))
					s.hp = s.max_hp()
		var a := _make_actor(s, "enemy")
		a.encounter_id = eid
		var p: Array = spd.get("pos", [0, 0])
		a.set_pos(grid.nearest_passable(Vector3(float(p[0]), 0, float(p[1]))))
		a.set_facing_deg(float(spd.get("rot", 0)))
		a.home = a.position
		if String(spd.get("state", "")) == "offline":
			a.hostile_override = "offline"
		Game.state.enemies[uid] = {"template": String(spd["enemy"]), "encounter": eid, "state": "alive"}
	Events.post("encounter_spawned", {"id": eid})


func _restore_combat_state() -> void:
	var c: Dictionary = Game.state.combat
	if bool(c.get("active", false)):
		combat.active = true
		combat.combat_time = float(c.get("time", 0.0))
		for uid in c.get("party_clocks", {}).keys():
			if actors.has(uid):
				var pc: Array = c["party_clocks"][uid]
				var a: Actor = actors[uid]
				a.recovery = float(pc[0])
				a.round_clock = float(pc[1])
				a.in_combat = true
				a.target_uid = String(pc[2]) if pc.size() > 2 else ""
		for a in actors.values():
			if (a as Actor).role == "enemy" and (a as Actor).alert:
				(a as Actor).in_combat = true
		set_paused(true, "Loaded during combat")
		GameAudio.music("music_combat")


# ================================================================ queries
func sorted_actors() -> Array:
	var keys := actors.keys()
	keys.sort()
	var out: Array = []
	for k in keys:
		out.append(actors[k])
	return out


func party_actors() -> Array:
	var out: Array = []
	for uid in Game.state.party:
		if actors.has(uid):
			out.append(actors[uid])
	return out


func controlled() -> Actor:
	return actors.get(Game.state.controlled, null)


func actor_of(sheet: CharacterSheet) -> Actor:
	return actors.get(sheet.uid, null)


func faction_of(a: Actor) -> String:
	if a.role == "party":
		return "party"
	return a.sheet.faction


func hostile(a: Actor, b: Actor) -> bool:
	if a == b or a.sheet.dead or b.sheet.dead:
		return false
	if a.hostile_override in ["neutral", "offline", "fled"] or b.hostile_override in ["neutral", "offline", "fled"]:
		return false
	var fa := faction_of(a)
	var fb := faction_of(b)
	if fa == fb:
		return false
	if fa == "civilian" or fb == "civilian":
		return false
	var pair := [fa, fb]
	pair.sort()
	var key := "%s|%s" % pair
	match key:
		"party|warden":
			return true
		"lantern|party":
			if Game.state.has_flag("lantern_truce"):
				return false
			return true
		"crew|party":
			return a.hostile_override == "hostile" or b.hostile_override == "hostile"
		"lantern|warden", "crew|warden":
			return true
		"crew|lantern":
			return true
	return false


func is_engaged(a: Actor) -> bool:
	## Whether this actor is an active combatant (enemies must be alert).
	if a.sheet.dead or a.sheet.is_downed():
		return false
	if a.role == "enemy" or a.role == "npc":
		return a.alert and a.hostile_override != "offline"
	return true


func hostiles_of(a: Actor) -> Array:
	var out: Array = []
	for o in actors.values():
		var oa: Actor = o
		if oa.sheet.is_downed() or oa.sheet.dead:
			continue
		if hostile(a, oa) and (oa.role == "party" or is_engaged(oa) or a.role != "party"):
			if a.role != "party" or is_engaged(oa) or oa.alert:
				out.append(oa)
	return out


func allies_of(a: Actor) -> Array:
	var out: Array = []
	var fa := faction_of(a)
	for o in actors.values():
		var oa: Actor = o
		if oa != a and faction_of(oa) == fa and not oa.sheet.dead:
			out.append(oa)
	return out


func alert_hostile_count() -> int:
	var n := 0
	for o in actors.values():
		var oa: Actor = o
		if oa.role != "party" and oa.alert and not oa.sheet.dead and not oa.sheet.is_downed() and oa.hostile_override not in ["neutral", "offline", "fled"]:
			# Only counts if hostile to the party.
			for p in party_actors():
				if hostile(p, oa):
					n += 1
					break
	return n


func nearest_hostile(a: Actor) -> Actor:
	var best: Actor = null
	var bd := INF
	for o in hostiles_of(a):
		var d := (o as Actor).position.distance_to(a.position)
		if d < bd:
			bd = d
			best = o
	return best


func valid_hostile_target(a: Actor, uid: String) -> bool:
	if uid == "" or not actors.has(uid):
		return false
	var t: Actor = actors[uid]
	return hostile(a, t) and not t.sheet.is_downed() and not t.sheet.dead


func sheets_in_radius(center: Vector3, r: float, need_los: bool = true) -> Array:
	var out: Array = []
	for o in actors.values():
		var oa: Actor = o
		if oa.sheet.dead:
			continue
		if oa.position.distance_to(center) <= r and (not need_los or grid.los(center, oa.position)):
			out.append(oa)
	return out


func area_music() -> String:
	return String(DB.dict(DB.dict(DB.layout, "areas"), current_area).get("music", "music_explore"))


# ================================================================ pause & modal
func set_paused(on: bool, reason: String = "") -> void:
	if game_over:
		on = true
	paused = on
	pause_reason = reason if on else ""
	Events.post("pause_changed", {"paused": on, "reason": reason})
	hud_changed.emit()


func toggle_pause() -> void:
	set_paused(not paused, "Paused")


func set_modal(key: String, on: bool) -> void:
	if on:
		modal[key] = true
	else:
		modal.erase(key)
	Game.block_ui(key, on)
	hud_changed.emit()


func sim_running() -> bool:
	return not paused and modal.is_empty() and not game_over


func save_block_reason() -> String:
	if game_over:
		return "The party has fallen. Load a save instead."
	if transition_lock != "":
		return transition_lock
	if modal.has("dialogue"):
		return "Finish the conversation first."
	if modal.has("cinematic"):
		return "Saving is unavailable during a cinematic."
	if modal.has("minigame"):
		return "Exit the activity first."
	if combat != null and combat.active and not paused:
		return "Pause combat (Space) to save at a stable moment."
	if not projectiles.is_empty():
		return "Wait for the grenade to land."
	if not bash_jobs.is_empty():
		return "Finish forcing the door first."
	return ""


# ================================================================ main loop
func _physics_process(delta: float) -> void:
	if manual_step:
		return
	if not Game.ui_blocked() and not game_over:
		_direct_input()
	elif controlled() != null:
		controlled().input_dir = Vector3.ZERO
	if _pending_autosave != "" and sim_running() and not combat.active:
		_checkpoint(_pending_autosave)
	if sim_running():
		Game.state.play_time += delta
		_acc += delta * time_scale
		var steps := 0
		while _acc >= FIXED_DT and steps < 8:
			sim_step(FIXED_DT)
			_acc -= FIXED_DT
			steps += 1
	_update_hover()


## Samples the movement keys into the controlled actor's input_dir; the
## movement itself happens in Actor.sim_step at the fixed simulation rate.
func _direct_input() -> void:
	var a := controlled()
	if a == null:
		return
	if not sim_running():
		a.input_dir = Vector3.ZERO
		return
	var v := Vector3.ZERO
	var b := cam.basis_flat()
	if Input.is_action_pressed("move_forward"):
		v += b[0]
	if Input.is_action_pressed("move_back"):
		v -= b[0]
	if Input.is_action_pressed("move_right"):
		v += b[1]
	if Input.is_action_pressed("move_left"):
		v -= b[1]
	if v.length_squared() > 0.0:
		a.current = {} if String(a.current.get("type", "")) == "interact" or bool(a.current.get("auto", false)) else a.current
		_pending_interact = {}
		a.queue.remove_auto()
		a.input_dir = v.normalized()
	else:
		a.input_dir = Vector3.ZERO


## One deterministic simulation step. Tests call this directly.
func sim_step(dt: float) -> void:
	var st := Game.state
	st.sim_time += dt
	_party_follow(dt)
	combat.step(dt)
	for a in sorted_actors():
		var aa: Actor = a
		var exp := StatusRules.tick(aa.sheet, dt)
		for e in exp:
			if e != "downed":
				Events.post("status_expired", {"uid": aa.uid, "id": e})
		aa.sim_step(dt)
		if aa.role == "npc" and aa.is_moving() == false and aa.sheet.has_status("feared"):
			pass
	_step_interaction(dt)
	_step_projectiles(dt)
	_step_bash(dt)
	fx.step(dt)
	_regen_step(dt)
	_stealth_clock += dt
	if _stealth_clock >= 0.25:
		_stealth_step(_stealth_clock)
		_stealth_clock = 0.0
	_reveal_clock += dt
	if _reveal_clock >= 0.25:
		_reveal_clock = 0.0
		for p in party_actors():
			grid.reveal((p as Actor).position, 7.0)
		_area_check(false)
	_trigger_clock += dt
	if _trigger_clock >= 0.2:
		_trigger_clock = 0.0
		_check_triggers()
		_check_mines()
		_auto_doors()
	_hazard_clock += dt
	if _hazard_clock >= 1.5:
		_hazard_clock = 0.0
		_hazard_step()
	_aware_clock += dt
	if _aware_clock >= 1.0:
		_aware_clock = 0.0
		_awareness_step()
	_enemy_idle_step(dt)
	for i in range(_pending_corpses.size() - 1, -1, -1):
		var pc: Dictionary = _pending_corpses[i]
		if float(pc["at"]) <= st.sim_time:
			_pending_corpses.remove_at(i)
			var uid := String(pc["uid"])
			_make_corpse(uid, pc["rec"])
			if actors.has(uid):
				var da: Actor = actors[uid]
				actors.erase(uid)
				da.queue_free()


# ================================================================ party
func _party_follow(dt: float) -> void:
	_follow_clock += dt
	if _follow_clock < 0.4:
		return
	_follow_clock = 0.0
	var lead := controlled()
	if lead == null:
		return
	if combat.active:
		return
	var st := Game.state
	if st.solo or st.party_order == "hold":
		return
	var i := 0
	for p in party_actors():
		var a: Actor = p
		if a == lead or a.sheet.is_downed():
			continue
		if a.manual_move and a.is_moving():
			continue
		var side := -1.0 if i == 0 else 1.0
		i += 1
		var back := Vector3(lead.facing.x, 0, lead.facing.y) * -1.6
		var right := Vector3(lead.facing.y, 0, -lead.facing.x) * side * 1.1
		var goal := lead.position + back + right
		# Formation spots on the far side of a wall or door would send
		# followers the long way round (or open doors): stay by the lead.
		var gp := grid.nearest_passable(goal, 3)
		if grid.area_at(gp) != grid.area_at(lead.position) or not grid.los(lead.position, gp):
			goal = lead.position
		var d := a.position.distance_to(lead.position)
		if d > 3.2:
			if not a.is_moving() or a.destination().distance_to(goal) > 2.5:
				if not a.move_to(grid.nearest_passable(goal, 3)):
					a.move_to(lead.position)
		elif d < 1.8 and a.is_moving() and not a.manual_move:
			a.stop()


func _regen_step(dt: float) -> void:
	if combat.active:
		return
	var rg: Dictionary = DB.dict(DB.progression, "regen")
	for p in party_actors():
		var a: Actor = p
		var s := a.sheet
		if s.is_downed():
			continue
		var acc: Vector2 = _regen.get(a.uid, Vector2.ZERO)
		acc.x += float(rg.get("hp_per_sec_out_of_combat", 0.5)) * dt
		acc.y += float(rg.get("energy_per_sec_out_of_combat", 1.0)) * dt
		if acc.x >= 1.0:
			s.hp = mini(s.max_hp(), s.hp + int(acc.x))
			acc.x -= int(acc.x)
		if acc.y >= 1.0:
			s.energy = mini(s.max_energy(), s.energy + int(acc.y))
			acc.y -= int(acc.y)
		_regen[a.uid] = acc


func on_combat_ended() -> void:
	# Downed allies recover; the fight is over.
	var frac := float(DB.dict(DB.progression, "regen").get("downed_recover_hp_fraction", 0.25))
	for p in party_actors():
		var a: Actor = p
		if a.sheet.is_downed() and not a.sheet.dead:
			StatusRules.remove(a.sheet, "downed")
			a.sheet.hp = maxi(1, int(a.sheet.max_hp() * frac))
			Events.toast("%s recovers (%d health)." % [a.sheet.display_name, a.sheet.hp], "info")
			Events.post("ally_recovered", {"uid": a.uid})
		StatusRules.remove(a.sheet, "exposed")
	for o in actors.values():
		(o as Actor).current = {}
	hud_changed.emit()


## Resting (out of combat, nobody hostile awake nearby) restores the party:
## downed allies stand, health and energy refill, harmful statuses and
## cooldowns clear. Buffs from consumables are kept.
const REST_CLEAR_RADIUS := 18.0


func rest_block_reason(from_menu: bool = false) -> String:
	if combat.active:
		return "You can't rest during combat."
	if game_over:
		return "The party has fallen."
	var busy := modal.keys().filter(func(k: Variant) -> bool: return not (from_menu and String(k) == "menu"))
	if not busy.is_empty():
		return "Finish what you're doing first."
	for o in actors.values():
		var e: Actor = o
		if e.role == "party" or e.sheet.dead or e.sheet.is_downed():
			continue
		var hostile_to_party := false
		for p in party_actors():
			var pa: Actor = p
			if not hostile(e, pa):
				continue
			var dist := e.position.distance_to(pa.position)
			# Alert hostiles nearby block rest; unaware ones only when they are
			# in the same space (same area or a clear line of sight).
			if e.alert and dist < REST_CLEAR_RADIUS * 1.5:
				hostile_to_party = true
			elif dist < REST_CLEAR_RADIUS and (grid.area_at(e.position) == grid.area_at(pa.position) or grid.los(e.position, pa.position)):
				hostile_to_party = true
			if hostile_to_party:
				break
		if hostile_to_party:
			return "Hostiles are too close to rest."
	for p in party_actors():
		var pa2: Actor = p
		if hazard_at(pa2.position) != "":
			return "You can't rest in a hazard."
	return ""


func rest(from_menu: bool = false) -> Dictionary:
	var why := rest_block_reason(from_menu)
	if why != "":
		Events.toast(why, "warn")
		return {"ok": false, "reason": why}
	for p in party_actors():
		var a: Actor = p
		var s := a.sheet
		if s.is_downed() and not s.dead:
			StatusRules.remove(s, "downed")
			a.visual.set_downed(false)
		StatusRules.cleanse(s, ["control", "dot", "debuff"])
		s.cooldowns.clear()
		s.hp = s.max_hp()
		s.energy = s.max_energy()
		a.queue.clear()
		a.current = {}
	Game.state.stats["rests"] = int(Game.state.stats.get("rests", 0)) + 1
	Events.post("rested", {"area": Game.state.area})
	Events.toast("The party catches its breath. Health and energy restored.", "info")
	GameAudio.play("heal", -6.0)
	hud_changed.emit()
	return {"ok": true}


func switch_control(uid: String) -> void:
	if not Game.state.party.has(uid) or not actors.has(uid):
		return
	var a: Actor = actors[uid]
	if a.sheet.is_downed():
		Events.toast("%s is down." % a.sheet.display_name, "warn")
		return
	var prev := controlled()
	if prev != null:
		prev.input_dir = Vector3.ZERO
	Game.state.controlled = uid
	cam.target = a
	if combat.active:
		auto_queue_attack(a)
	refresh_markers()
	Events.post("control_changed", {"uid": uid})
	hud_changed.emit()


func cycle_control() -> void:
	var p := Game.state.party
	if p.is_empty():
		return
	var i := p.find(Game.state.controlled)
	for k in range(1, p.size() + 1):
		var nxt: String = p[(i + k) % p.size()]
		if actors.has(nxt) and not (actors[nxt] as Actor).sheet.is_downed():
			switch_control(nxt)
			return


func set_party_order(mode: String) -> void:
	Game.state.party_order = mode
	if mode == "hold":
		for p in party_actors():
			if p != controlled():
				(p as Actor).stop()
	Events.toast("Party: %s" % ("holding position" if mode == "hold" else "following"), "info")
	hud_changed.emit()


func set_solo(on: bool) -> void:
	Game.state.solo = on
	if on:
		for p in party_actors():
			if p != controlled():
				(p as Actor).stop()
	Events.toast("Solo mode %s" % ("ON: companions stay put" if on else "OFF"), "info")
	hud_changed.emit()


func set_behavior(uid: String, beh: String) -> void:
	var s := Game.state.get_char(uid)
	if s != null:
		s.behavior = beh
		hud_changed.emit()


func toggle_stealth(a: Actor) -> void:
	if a == null:
		return
	if a.stealth:
		break_stealth(a, "")
		return
	if combat.active and _seen_by_alert(a):
		Events.toast("Cannot enter stealth while enemies are watching you.", "warn")
		return
	a.stealth = true
	a.visual.set_stealth(true)
	Events.toast("%s is sneaking (Stealth %s). Enemies need Awareness checks to notice." % [a.sheet.display_name, Rules.signed(a.sheet.skill_total("stealth"))], "info")
	Events.post("stealth_changed", {"uid": a.uid, "on": true})
	if bool(Settings.get_v("hold_on_stealth")) and not Game.state.solo and a == controlled():
		_auto_solo = true
		set_solo(true)
	hud_changed.emit()


func break_stealth(a: Actor, why: String) -> void:
	if not a.stealth:
		return
	a.stealth = false
	a.visual.set_stealth(false)
	if why != "":
		Events.toast("Stealth broken: %s" % why, "warn")
		fx.text(a.position, "SEEN", Color("#ff5a4a"), true)
	Events.post("stealth_changed", {"uid": a.uid, "on": false, "why": why})
	if _auto_solo:
		_auto_solo = false
		set_solo(false)
	hud_changed.emit()


func _seen_by_alert(a: Actor) -> bool:
	for o in actors.values():
		var e: Actor = o
		if e.role == "enemy" and e.alert and not e.sheet.is_downed() and grid.los(e.position, a.position) and e.position.distance_to(a.position) < e.sheet.sight_range():
			return true
	return false


# ================================================================ stealth & awareness
func _stealth_step(dt: float) -> void:
	var dice := Game.state.dice
	for o in sorted_actors():
		var e: Actor = o
		if e.role == "party" or e.sheet.dead or e.sheet.is_downed() or not e.sheet.can_act():
			continue
		if e.hostile_override in ["offline", "neutral", "fled"]:
			continue
		var hostile_to_party := false
		for p in party_actors():
			if hostile(p, e):
				hostile_to_party = true
				break
		if not hostile_to_party:
			continue
		if e.role == "npc" and not e.alert:
			continue
		for p in party_actors():
			var pa: Actor = p
			if pa.sheet.is_downed():
				continue
			var see := StealthRules.perceivable(e.pos2(), e.facing, e.sheet.sight_range(), pa.pos2(), grid.los(e.eye_pos(), pa.position))
			var key := pa.uid
			var sus := float(e.suspicion.get(key, 0.0))
			if not see:
				e.suspicion[key] = maxf(0.0, sus - StealthRules.DECAY_PER_SEC * dt)
				continue
			if e.alert:
				continue
			if not pa.stealth:
				_alert_enemy(e, pa, "%s spotted %s" % [e.sheet.display_name, pa.sheet.display_name], true)
				break
			e.detect_clock += dt
			if e.detect_clock < StealthRules.CHECK_INTERVAL:
				continue
			e.detect_clock = 0.0
			var shadow_bonus := 4 if grid.is_shadow(pa.position) else 0
			var r := StealthRules.check(e.sheet, pa.sheet, e.position.distance_to(pa.position), pa.still_time > 0.8, dice)
			if shadow_bonus > 0 and r["success"] and int(r["total"]) < int(r["dc"]) + shadow_bonus:
				r["success"] = false
				r["gain"] = 0.0
			sus = minf(1.0, sus + float(r["gain"]))
			e.suspicion[key] = sus
			if r["success"]:
				Events.log_combat("%s notices something: Awareness d20 %d %s - %d = %d vs Stealth DC %d (suspicion %d%%)" % [e.sheet.display_name, r["natural"], Rules.signed(int(r["awareness"])), r["distance_penalty"], r["total"], r["dc"], int(sus * 100)], "", "stealth")
			if sus >= 1.0:
				break_stealth(pa, "%s detected %s" % [e.sheet.display_name, pa.sheet.display_name])
				_alert_enemy(e, pa, "", true)
				break


func max_suspicion_on(uid: String) -> float:
	var m := 0.0
	for o in actors.values():
		var e: Actor = o
		if e.role != "party" and not e.alert:
			m = maxf(m, float(e.suspicion.get(uid, 0.0)))
	return m


## Verbose world tracing for debugging bot runs (AOTC_DEBUG=1).
static var _debug := OS.has_environment("AOTC_DEBUG")


func dbg(msg: String) -> void:
	if _debug:
		print("[world %.1f] %s" % [Game.state.sim_time if Game.state else 0.0, msg])


func _alert_enemy(e: Actor, cause: Actor, msg: String, allow_parley: bool = false) -> void:
	if e.alert:
		return
	dbg("alert %s by %s (%s) at %s" % [e.uid, cause.uid if cause != null else "-", msg, str(e.position)])
	var eid0 := e.encounter_id
	if allow_parley and eid0 != "":
		var ed0: Dictionary = DB.encounters.get(eid0, {})
		var pd := String(ed0.get("parley_dialogue", ""))
		var es0 := encounter_state(eid0)
		if pd != "" and String(es0["state"]) == "pending" and not bool(es0.get("parleyed", false)):
			es0["parleyed"] = true
			for o in actors.values():
				var oa0: Actor = o
				if oa0.encounter_id == eid0:
					oa0.face_towards(cause.position if cause != null else oa0.position)
					oa0.stop()
			var sp: Actor = null
			for o in actors.values():
				if (o as Actor).encounter_id == eid0 and not (o as Actor).sheet.dead:
					sp = o
			start_dialogue(pd, sp)
			return
	if msg != "":
		Events.toast(msg, "alert")
	GameAudio.play("alert", -4.0)
	var group := e.encounter_id
	for o in actors.values():
		var oa: Actor = o
		if oa.role == "party" or oa.alert or oa.sheet.dead:
			continue
		if oa == e or (group != "" and oa.encounter_id == group and oa.hostile_override not in ["offline", "neutral", "fled"]):
			oa.alert = true
			if cause != null:
				oa.target_uid = cause.uid
	if group != "":
		var es := encounter_state(group)
		if String(es["state"]) == "pending":
			es["state"] = "active"
			Events.post("encounter_started", {"id": group})
			Effects.apply_all(DB.encounters.get(group, {}).get("on_start", []), Game.state)
			var tut := String(DB.encounters.get(group, {}).get("tutorial", ""))
			if tut != "":
				Events.post("tutorial", {"id": tut})


func alert_encounter(eid: String) -> void:
	spawn_encounter(eid)
	for o in actors.values():
		var oa: Actor = o
		if oa.encounter_id == eid and not oa.sheet.dead:
			_alert_enemy(oa, controlled(), "")
			return


func make_noise(pos: Vector3, radius: float, what: String) -> void:
	for o in actors.values():
		var e: Actor = o
		if e.role == "enemy" and not e.alert and not e.sheet.dead and e.position.distance_to(pos) <= radius and e.hostile_override not in ["offline", "neutral", "fled"]:
			# Bulkheads and closed doors carry little sound: only listeners in
			# the same area or with a clear line to the noise react.
			if grid.area_at(e.position) != grid.area_at(pos) and not grid.los(pos, e.position):
				continue
			_alert_enemy(e, controlled(), "%s heard %s" % [e.sheet.display_name, what])


func _awareness_step() -> void:
	## Passive Awareness rolls against hidden mines, hazards and clues: one
	## roll per party member per object, when they first come within range.
	for o in objects.values():
		var wo: WorldObject = o
		var dc := int(wo.def.get("hidden_dc", 0))
		if dc <= 0 or wo.is_detected():
			continue
		if wo.def.has("if") and not Conditions.eval_all(wo.def["if"], Game.state):
			continue
		var rng := float(wo.def.get("notice_range", 6.0))
		for p in party_actors():
			var pa: Actor = p
			if pa.sheet.is_downed() or pa.position.distance_to(wo.center) > rng:
				continue
			var rolled: Dictionary = wo.st().get("aware_rolls", {})
			if rolled.has(pa.uid):
				continue
			rolled[pa.uid] = true
			wo.st()["aware_rolls"] = rolled
			var sk := "awareness"
			if wo.kind == "mine":
				# Demolitions training also helps spot explosives.
				sk = "awareness" if pa.sheet.skill_total("awareness") >= pa.sheet.skill_total("demolitions") else "demolitions"
			var r := CombatRules.skill_check(pa.sheet, sk, dc, Game.state.dice)
			Events.log_combat("%s %s check vs hidden %s: d20 %d %s = %d vs DC %d — %s" % [pa.sheet.display_name, DB.skill(sk)["name"], wo.display_name(), r["natural"], Rules.signed(int(r["bonus"])), r["total"], dc, "noticed" if r["success"] else "missed"], "", "skill")
			if r["success"]:
				reveal_object(wo, pa)
				break


func reveal_object(wo: WorldObject, by: Actor) -> void:
	wo.st()["detected"] = true
	wo.refresh()
	var who := by.sheet.display_name if by != null else "You"
	Events.toast("%s noticed: %s" % [who, wo.display_name()], "discovery")
	fx.pulse(wo.center, Color("#f2c26b"), 1.5)
	Effects.apply_all(wo.def.get("on_detect", []), Game.state, {"actor": by.uid if by != null else "player"})
	Events.post("object_detected", {"id": wo.id})


func reveal_radius(center: Vector3, r: float, by: Actor) -> void:
	for o in objects.values():
		var wo: WorldObject = o
		if int(wo.def.get("hidden_dc", 0)) > 0 and not wo.is_detected() and wo.center.distance_to(center) <= r:
			if wo.def.has("if") and not Conditions.eval_all(wo.def["if"], Game.state):
				continue
			reveal_object(wo, by)
	fx.pulse(center, Color("#3fb6b0"), r * 0.5)


# ================================================================ areas & triggers
func _area_check(initial: bool) -> void:
	var lead := controlled()
	if lead == null:
		return
	var aid := grid.area_at(lead.position)
	if aid == "" or aid == current_area:
		return
	current_area = aid
	var st := Game.state
	st.area = aid
	var ad: Dictionary = DB.dict(DB.dict(DB.layout, "areas"), aid)
	var first := not st.areas_visited.has(aid)
	if first:
		st.areas_visited.append(aid)
	Events.post("area_entered", {"area": aid, "first": first})
	ui_request.emit("area_banner", {"name": String(ad.get("name", aid)), "sub": String(ad.get("subtitle", ""))})
	if not combat.active:
		GameAudio.music(area_music())
	if first and not initial:
		if int(ad.get("discover_xp", 0)) > 0:
			st.grant_xp(int(ad["discover_xp"]), "area:" + aid, "Explored " + String(ad.get("name", aid)))
		Effects.apply_all(ad.get("on_enter", []), st)
		if bool(ad.get("checkpoint", false)):
			call_deferred("_checkpoint", String(ad.get("name", aid)))


var _pending_autosave := ""


func _checkpoint(label: String) -> void:
	if save_block_reason() == "" and not combat.active:
		Saves.autosave(label)
		_pending_autosave = ""
	else:
		_pending_autosave = label


func _check_triggers() -> void:
	var lead := controlled()
	if lead == null:
		return
	for tr in DB.layout.get("triggers", []):
		var td: Dictionary = tr
		var tid := String(td["id"])
		var key := "trigger:" + tid
		if bool(td.get("once", true)) and Game.state.claimed(key):
			continue
		var r: Array = td["rect"]
		var inside := false
		for p in party_actors():
			var pa: Actor = p
			if td.get("who", "any") == "lead" and pa != lead:
				continue
			if pa.position.x >= float(r[0]) and pa.position.x < float(r[2]) and pa.position.z >= float(r[1]) and pa.position.z < float(r[3]):
				inside = true
				break
		if not inside:
			continue
		if td.has("if") and not Conditions.eval_all(td["if"], Game.state):
			continue
		Game.state.claim(key)
		Events.post("trigger", {"id": tid})
		Effects.apply_all(td.get("effects", []), Game.state)
		if td.has("encounter"):
			if bool(td.get("alert", true)):
				alert_encounter(String(td["encounter"]))
			else:
				spawn_encounter(String(td["encounter"]))
		if td.has("dialogue"):
			var spk: Actor = null
			if td.has("speaker_uid"):
				spk = actors.get(String(td["speaker_uid"]), null)
			start_dialogue(String(td["dialogue"]), spk, String(td.get("speaker_npc", "")))



## Unlocked doors slide open when a character walks up to them.
func _auto_doors() -> void:
	for o in objects.values():
		var wo: WorldObject = o
		if wo.kind != "door" or wo.is_open() or wo.is_locked():
			continue
		for a in actors.values():
			var aa: Actor = a
			# Only the party opens doors; closing a door between you and a
			# pursuer breaks the chase.
			if aa.role != "party" or aa.sheet.dead or aa.sheet.is_downed():
				continue
			# In a fight only the character you control opens doors, so an AI
			# companion can't let a second group in by accident.
			if combat.active and aa.uid != Game.state.controlled:
				continue
			# Opens only for someone walking into it, not for a companion
			# brushing past in a fight.
			if wo.distance_to_actor(aa) > 1.5:
				continue
			if not _heading_through(aa, wo.cells):
				continue
			if true:
				wo.st()["open"] = true
				dbg("door %s opened by %s at %s" % [wo.id, aa.uid, str(aa.position)])
				wo.refresh()
				GameAudio.play_at("door", wo.center, self)
				Events.post("door_opened", {"id": wo.id})
				Effects.apply_all(wo.def.get("on_open", []), Game.state, {"actor": aa.uid})
				break


## True when the actor's next ~2 m of travel (its path, or a recent WASD
## push) passes through one of the given door cells.
func _heading_through(aa: Actor, cells: Array) -> bool:
	var door_cells := {}
	for c in cells:
		door_cells[grid.world_cell(int(c[0]), int(c[1]))] = true
	var pts: Array[Vector3] = []
	if aa.is_moving():
		var cur := aa.position
		var left := 2.0
		for i in range(aa.path_i, aa.path.size()):
			var q: Vector3 = aa.path[i]
			var seg := Vector3(q.x - cur.x, 0, q.z - cur.z)
			var l := seg.length()
			var n := int(ceil(minf(l, left) / 0.25))
			for k in range(1, n + 1):
				pts.append(cur + seg.normalized() * minf(l, k * 0.25))
			left -= l
			cur = q
			if left <= 0.0:
				break
	elif Game.state.sim_time - aa.push_time < 0.25:
		for k in range(1, 5):
			pts.append(aa.position + aa.push_dir * (k * 0.3))
	for p in pts:
		if door_cells.has(grid.cell_of(p)):
			return true
	return false


func _hazard_step() -> void:
	for o in objects.values():
		var wo: WorldObject = o
		if wo.kind != "hazard" or not wo.is_active():
			continue
		if wo.def.has("if") and not Conditions.eval_all(wo.def["if"], Game.state):
			continue
		var sz: Array = wo.def.get("size", [2, 2])
		for p in party_actors():
			var pa: Actor = p
			if pa.sheet.is_downed():
				continue
			if absf(pa.position.x - wo.center.x) <= float(sz[0]) * 0.5 and absf(pa.position.z - wo.center.z) <= float(sz[1]) * 0.5:
				_hazard_hit(wo, pa)


## Re-marks the cells of detected, active hazards as "avoid" for pathing.
func refresh_hazard_avoidance() -> void:
	for o in objects.values():
		var wo: WorldObject = o
		if wo.kind != "hazard":
			continue
		var on := wo.is_detected() and wo.is_active() and (not wo.def.has("if") or Conditions.eval_all(wo.def["if"], Game.state))
		var sz: Array = wo.def.get("size", [2, 2])
		var cells: Array = []
		for x in range(floori(wo.center.x - float(sz[0]) * 0.5), ceili(wo.center.x + float(sz[0]) * 0.5)):
			for z in range(floori(wo.center.z - float(sz[1]) * 0.5), ceili(wo.center.z + float(sz[1]) * 0.5)):
				cells.append(grid.world_cell(x, z))
		grid.set_avoid(cells, on)


## Nearest standable point within a few metres that is not inside a hazard.
func safe_spot_near(p: Vector3) -> Vector3:
	var c := grid.cell_of(p)
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var cc := c + Vector2i(dx, dz)
				if grid.passable(cc) and not grid.is_avoided(cc) and hazard_at(grid.center_of(cc)) == "":
					return grid.center_of(cc)
	return p


## Id of an active hazard covering p, or "".
func hazard_at(p: Vector3) -> String:
	for o in objects.values():
		var wo: WorldObject = o
		if wo.kind != "hazard" or not wo.is_active():
			continue
		if wo.def.has("if") and not Conditions.eval_all(wo.def["if"], Game.state):
			continue
		var sz: Array = wo.def.get("size", [2, 2])
		if absf(p.x - wo.center.x) <= float(sz[0]) * 0.5 + 0.5 and absf(p.z - wo.center.z) <= float(sz[1]) * 0.5 + 0.5:
			return wo.id
	return ""


func _hazard_hit(wo: WorldObject, pa: Actor) -> void:
	var s := pa.sheet
	var hk := String(wo.def.get("hazard", "shock"))
	var dice := Game.state.dice
	if not wo.is_detected():
		reveal_object(wo, pa)
	match hk:
		"shock":
			if s.immunities().has("shock"):
				fx.text(pa.position, "insulated", Color("#7fd0ff"))
				return
			var r := dice.roll_expr("1d6")
			var res := CombatRules.apply_damage(s, [{"amount": int(r["total"]), "dtype": "energy", "shock": true}], {"difficulty": Game.state.difficulty})
			StatusRules.apply(s, "shocked", 3.0, wo.id)
			fx.text(pa.position, str(int(res["dealt"])), Color("#7fd0ff"))
			Events.log_combat("%s steps on a live plate: %d energy damage." % [s.display_name, int(res["dealt"])], "", "damage")
			if bool(res["downed"]):
				on_downed(pa, "")
		"toxin":
			var sr := StatusRules.apply(s, "toxin", 6.0, wo.id)
			if bool(sr["applied"]) and sr["reason"] == "new":
				Events.toast("%s is breathing vented coolant (Coolant Exposure)." % s.display_name, "warn")
			elif not bool(sr["applied"]) and sr["reason"] == "immune":
				fx.text(pa.position, "filtered", Color("#5fd38a"))
		"steam":
			var r2 := dice.roll_expr("1d4")
			var res2 := CombatRules.apply_damage(s, [{"amount": int(r2["total"]), "dtype": "thermal"}], {"difficulty": Game.state.difficulty})
			fx.text(pa.position, str(int(res2["dealt"])), Color("#ff9a5a"))
			if bool(res2["downed"]):
				on_downed(pa, "")


func _check_mines() -> void:
	for o in objects.values():
		var wo: WorldObject = o
		if wo.kind != "mine" or bool(wo.st().get("disarmed", false)) or bool(wo.st().get("exploded", false)):
			continue
		if float(wo.st().get("arm_at", 0.0)) > Game.state.sim_time:
			continue
		var owner := String(wo.def.get("owner", "warden"))
		var trig := float(DB.dict(DB.item(String(wo.def.get("mine_item", "frag_mine"))), "mine").get("trigger", 1.5))
		for a in actors.values():
			var aa: Actor = a
			if aa.sheet.dead or aa.sheet.is_downed():
				continue
			var victim_is_party := aa.role == "party"
			var hostile_to_owner := (owner == "party" and not victim_is_party and aa.role == "enemy") or (owner != "party" and victim_is_party)
			if not hostile_to_owner:
				continue
			if aa.position.distance_to(wo.center) <= trig:
				detonate_mine(wo)
				break


func detonate_mine(wo: WorldObject) -> void:
	if bool(wo.st().get("exploded", false)):
		return
	wo.st()["exploded"] = true
	wo.st()["disarmed"] = true
	var item := String(wo.def.get("mine_item", "frag_mine"))
	var spec: Dictionary = DB.dict(DB.item(item), "mine")
	var r := float(spec.get("radius", 2.5))
	var targets: Array = []
	for a in sheets_in_radius(wo.center, r, true):
		targets.append((a as Actor).sheet)
	var res := ActionResolver.resolve_explosion(item, String(wo.def.get("owner", "warden")), targets, {"difficulty": Game.state.difficulty}, Game.state.dice)
	fx.burst(wo.center, Color("#ffb04a"), r)
	cam.add_shake(0.8)
	GameAudio.play_at("explosion", wo.center, self)
	_apply_events(null, res)
	wo.refresh()
	make_noise(wo.center, 14.0, "an explosion")
	Events.post("mine_exploded", {"id": wo.id})


# ================================================================ enemies idle
func _enemy_idle_step(dt: float) -> void:
	for o in actors.values():
		var e: Actor = o
		if e.role != "enemy" or e.alert or e.sheet.dead or e.sheet.is_downed():
			continue
		# Return home after a fight or noise.
		if not e.is_moving() and e.position.distance_to(e.home) > 2.0 and e.sheet.can_move():
			e.move_to(e.home)


# ================================================================ commands
func cmd_move(a: Actor, p: Vector3) -> bool:
	if a == null or a.sheet.is_downed():
		return false
	if not a.sheet.can_move():
		Events.toast("%s cannot move right now." % a.sheet.display_name, "warn")
		return false
	_pending_interact = {}
	if String(a.current.get("type", "")) != "":
		a.current = {}
	a.queue.remove_auto()
	var ok := a.move_to(grid.nearest_passable(p, 3), true)
	dbg("move %s %s -> %s: %s" % [a.uid, str(a.position), str(p), str(a.path) if ok else "no path"])
	if not ok:
		Events.toast("No path there.", "warn")
	return ok


func cmd_target(a: Actor, uid: String) -> void:
	if a == null:
		return
	a.target_uid = uid
	# A pending automatic attack follows the player's new selection.
	if valid_hostile_target(a, uid):
		a.queue.retarget_auto(uid)
	refresh_markers()
	hud_changed.emit()


## The enemy an idle character would go for: the nearest engaged hostile,
## preferring ones in line of sight.
func auto_target(a: Actor) -> Actor:
	var best: Actor = null
	var bd := INF
	for o in hostiles_of(a):
		var h: Actor = o
		if not valid_hostile_target(a, h.uid):
			continue
		var d := h.position.distance_to(a.position)
		if not grid.los(a.position, h.position):
			d += 1000.0
		if d < bd:
			bd = d
			best = h
	return best


## True while the player is steering this character themselves (a click-move
## path or the movement keys): automatic attacks must not override that.
func player_moving(a: Actor) -> bool:
	return (a.manual_move and a.is_moving()) or a.input_dir.length_squared() > 0.0001


## Auto-attack: when combat starts (or control passes to someone idle mid-
## fight) and the player has queued nothing, queue a basic attack on the
## selected enemy, or the nearest one. Skipped while sneaking, moving, busy
## with an interaction, or when turned off in Settings → Gameplay.
func auto_queue_attack(a: Actor) -> bool:
	if a == null or a.role != "party" or a.uid != Game.state.controlled or not bool(Settings.get_v("auto_attack")):
		return false
	if a.sheet.is_downed() or a.sheet.dead or not a.sheet.can_act() or a.stealth:
		return false
	if not a.queue.is_empty() or not a.current.is_empty() or a.interaction.size() > 0 or player_moving(a):
		return false
	var t: Actor = actors[a.target_uid] if valid_hostile_target(a, a.target_uid) else auto_target(a)
	if t == null:
		return false
	var act := {"type": "attack", "target": t.uid, "auto": true, "auto_queued": true}
	if validate_action(a, act, true) != "":
		return false
	a.target_uid = t.uid
	a.queue.push(act)
	refresh_markers()
	hud_changed.emit()
	return true


func cmd_attack(a: Actor, uid: String) -> void:
	if a == null or not actors.has(uid):
		return
	var t: Actor = actors[uid]
	if t.role == "npc" and not hostile(a, t):
		Events.toast("%s is not hostile." % t.sheet.display_name, "warn")
		return
	a.target_uid = uid
	if not t.alert and t.role != "party":
		_alert_enemy(t, a, "")
	if a.queue.is_empty() and a.current.is_empty():
		queue_action(a, {"type": "attack", "target": uid})
	refresh_markers()


func queue_action(a: Actor, action: Dictionary) -> String:
	if a == null:
		return "No character."
	if a.sheet.is_downed():
		return "%s is down." % a.sheet.display_name
	if a.queue.is_full():
		Events.toast("%s's queue is full (4 actions)." % a.sheet.display_name, "warn")
		return "Queue full."
	var reason := validate_action(a, action, true)
	if reason != "":
		Events.toast(reason, "warn")
		return reason
	var act := action.duplicate()
	act["manual"] = true
	# The player's own choice replaces any automatic basic attack.
	a.queue.remove_auto()
	a.queue.push(act)
	if a.stealth and String(act["type"]) in ["attack", "feat", "power", "item"]:
		pass  # stealth breaks when the action executes
	hud_changed.emit()
	return ""


func action_label(act: Dictionary) -> String:
	match String(act.get("type", "")):
		"attack":
			return "Attack"
		"feat":
			return String(DB.feat(String(act["id"])).get("name", act["id"]))
		"power":
			return String(DB.power(String(act["id"])).get("name", act["id"]))
		"item":
			return "Use " + DB.item_name(String(act["id"]))
		"swap":
			return "Swap weapons"
	return String(act.get("type", "?"))


## Validates an action for an actor. Returns "" or a player-facing reason.
func validate_action(a: Actor, act: Dictionary, queueing: bool = false) -> String:
	var t := String(act.get("type", ""))
	var tgt: CharacterSheet = null
	var tuid := String(act.get("target", ""))
	if tuid != "":
		if not actors.has(tuid):
			return "Target is gone."
		tgt = (actors[tuid] as Actor).sheet
	match t:
		"attack":
			if tgt == null:
				return "No target selected."
			if tgt.dead or tgt.is_downed():
				return "%s is already down." % tgt.display_name
			if not hostile(a, actors[tuid]):
				return "%s is not hostile." % tgt.display_name
			if not a.sheet.can_attack() and not queueing:
				return "%s cannot attack right now." % a.sheet.display_name
		"feat":
			var r := ActionResolver.feat_usable(a.sheet, String(act["id"]), tgt)
			if r != "":
				return r
			if tgt != null and (tgt.dead or tgt.is_downed()):
				return "%s is already down." % tgt.display_name
		"power":
			var pd: Dictionary = DB.power(String(act["id"]))
			var pt := String(pd.get("target", "enemy"))
			if pt in ["enemy", "area_enemy"] and tgt != null and not hostile(a, actors[tuid]):
				return "%s is not a valid target for %s." % [tgt.display_name, pd.get("name", "")]
			if pt == "ally" and tgt != null and hostile(a, actors[tuid]):
				return "%s targets allies." % pd.get("name", "")
			var r2 := ActionResolver.power_usable(a.sheet, String(act["id"]), tgt, Game.state.alignment)
			if r2 != "" and not (queueing and r2.begins_with("Not enough energy")):
				return r2
			if r2 != "" and not queueing:
				return r2
			if tgt != null and tgt.dead:
				return "Target is gone."
		"item":
			var it: Dictionary = DB.item(String(act["id"]))
			if String(it.get("type", "")) == "grenade" and tgt == null and not act.has("point"):
				return "Select a target to throw at."
			var r3 := ActionResolver.item_usable(a.sheet, String(act["id"]), tgt, Game.state.inventory)
			if r3 != "":
				return r3
			if String(it.get("type", "")) == "consumable" and tgt != null and tgt != a.sheet and hostile(a, actors[tuid]):
				return "Cannot use that on an enemy."
		"swap":
			pass
		_:
			return "Unknown action."
	return ""


func action_range(a: Actor, act: Dictionary) -> float:
	match String(act.get("type", "")):
		"attack", "feat":
			if act.has("target"):
				var fd: Dictionary = DB.feat(String(act.get("id", "")))
				var k := String(DB.dict(fd, "action").get("kind", "melee"))
				if k == "self" or k == "self_area_machine":
					return -1.0
				return float(CombatRules.weapon_profile(a.sheet, "main")["range"])
			return -1.0
		"power":
			var pd: Dictionary = DB.power(String(act["id"]))
			if String(pd.get("target", "")) in ["self", "party", "self_area"]:
				return -1.0
			if not act.has("target") or String(act["target"]) == a.uid:
				return -1.0
			return float(pd.get("range", 10.0))
		"item":
			var it: Dictionary = DB.item(String(act["id"]))
			if String(it.get("type", "")) == "grenade":
				return float(DB.dict(it, "throw").get("range", 12.0))
			if String(it.get("type", "")) == "mine":
				return -1.0
			if act.has("target") and String(act["target"]) != a.uid:
				return 2.2
			return -1.0
	return -1.0


func action_target_pos(a: Actor, act: Dictionary) -> Vector3:
	var tuid := String(act.get("target", ""))
	if tuid != "" and actors.has(tuid):
		return (actors[tuid] as Actor).position
	if act.has("point"):
		var p: Array = act["point"]
		return Vector3(float(p[0]), 0, float(p[1]))
	return a.position


# ================================================================ execution
func execute_action(a: Actor, act: Dictionary) -> void:
	var st := Game.state
	var tuid := String(act.get("target", ""))
	var tgt: Actor = actors.get(tuid, null)
	var ctx := {"target": tgt.sheet if tgt != null else null, "alignment": st.alignment, "difficulty": st.difficulty,
		"inventory": st.inventory if a.role == "party" else null, "sneak": a.stealth and tgt != null and not tgt.alert}
	var t := String(act.get("type", ""))
	if t == "power":
		var pd: Dictionary = DB.power(String(act["id"]))
		match String(pd.get("target", "")):
			"party":
				var pl: Array = []
				for p in allies_of(a) + [a]:
					if (p as Actor).position.distance_to(a.position) <= 15.0:
						pl.append((p as Actor).sheet)
				ctx["area_targets"] = pl
			"area_enemy":
				var c := tgt.position if tgt != null else a.position
				ctx["area_targets"] = _hostile_sheets_near(a, c, float(pd.get("radius", 3.0)))
			"self_area":
				ctx["area_targets"] = _hostile_sheets_near(a, a.position, float(pd.get("radius", 4.0)))
		if pd.has("chain_targets") and tgt != null:
			var n := int(pd["chain_targets"]) + Prestige.chain_bonus(a.sheet)
			var chain: Array = [tgt.sheet]
			var last := tgt
			for i in n - 1:
				var nxt: Actor = null
				var bd := float(pd.get("chain_radius", 5.0))
				for h in hostiles_of(a):
					var ha: Actor = h
					if chain.has(ha.sheet):
						continue
					var d := ha.position.distance_to(last.position)
					if d <= bd:
						bd = d
						nxt = ha
				if nxt == null:
					break
				chain.append(nxt.sheet)
				last = nxt
			ctx["chain_targets"] = chain
	if t == "feat":
		var fa: Dictionary = DB.dict(DB.feat(String(act["id"])), "action")
		if String(fa.get("kind", "")) == "self_area_machine":
			ctx["area_targets"] = _hostile_sheets_near(a, a.position, float(fa.get("radius", 8.0)))
	if t == "item" and tgt == null and String(DB.item(String(act["id"])).get("use", {}).get("target", "self")) == "self":
		ctx["target"] = a.sheet
	var res := ActionResolver.resolve(act, a.sheet, ctx, st.dice)
	if not bool(res["ok"]):
		if a.role == "party":
			Events.toast("%s: %s" % [a.sheet.display_name, res["reason"]], "warn")
		return
	# Stealth breaks on any hostile action.
	if a.stealth and t in ["attack", "feat", "power", "item"]:
		var pd2: Dictionary = DB.power(String(act.get("id", ""))) if t == "power" else {}
		if t != "power" or String(pd2.get("target", "")) in ["enemy", "area_enemy", "self_area"]:
			break_stealth(a, "%s attacked" % a.sheet.display_name if t != "power" else "%s used %s" % [a.sheet.display_name, pd2.get("name", "")])
	if tgt != null and tgt.role != "party" and not tgt.alert and t in ["attack", "feat", "power", "item"] and hostile(a, tgt):
		_alert_enemy(tgt, a, "")
	_apply_events(a, res)
	hud_changed.emit()


func _hostile_sheets_near(a: Actor, c: Vector3, r: float) -> Array:
	var out: Array = []
	for h in hostiles_of(a):
		var ha: Actor = h
		if ha.position.distance_to(c) <= r and grid.los(c, ha.position):
			out.append(ha.sheet)
	return out


## Presents resolved results: animation, FX, sounds, logs, deaths. Never
## re-rolls or re-applies anything.
func _apply_events(a: Actor, res: Dictionary) -> void:
	# Attack lines are logged with their breakdown from the event below; the
	# plain copy in res.log is skipped so the log shows each roll once.
	var event_texts := {}
	for ev0 in res.get("events", []):
		if String((ev0 as Dictionary).get("type", "")) == "attack":
			event_texts[String((ev0 as Dictionary).get("text", ""))] = true
	for line in res.get("log", []):
		if not event_texts.has(String(line)):
			Events.log_combat(String(line), "", "info")
	for ev in res.get("events", []):
		var e: Dictionary = ev
		var tgt: Actor = actors.get(String(e.get("target", "")), null)
		match String(e.get("type", "")):
			"attack":
				var r: Dictionary = e["result"]
				if a != null:
					a.visual.play("ranged" if e["ranged"] else "melee", 0.35)
					GameAudio.play_at(String(e.get("sound", "blade")), a.position, self, -2.0)
				if bool(e["ranged"]) and a != null and tgt != null:
					var col := Color("#ff6a3a") if String(e.get("dtype", "")) == "energy" else Color("#7fd0ff")
					fx.bolt(a.eye_pos() - Vector3(0, 0.2, 0), tgt.eye_pos() - Vector3(0, 0.3, 0) + (Vector3(randf_range(-0.6, 0.6), 0.3, 0) if not r["hit"] else Vector3.ZERO), col)
				elif tgt != null and a != null:
					fx.slash(tgt.position, Color("#ffd27a") if String(e.get("dtype", "")) == "energy" else Color("#e8eefc"))
				if tgt != null:
					if bool(r.get("deflected", false)):
						fx.text(tgt.position, "DEFLECT", Color("#ffd27a"))
						GameAudio.play_at("deflect", tgt.position, self)
						tgt.visual.play("melee", 0.2)
					elif bool(r["hit"]):
						var dmg: Dictionary = e.get("damage", {})
						fx.text(tgt.position, ("CRIT " if r["crit"] else "") + str(int(dmg.get("dealt", 0))), Color("#ffdf6a") if r["crit"] else Color("#ff6a5a"), bool(r["crit"]))
						if int(dmg.get("absorbed", 0)) > 0:
							fx.text(tgt.position + Vector3(0, 0.3, 0), "-%d shield" % int(dmg["absorbed"]), Color("#7fd0ff"))
						tgt.visual.play("hit", 0.25)
						tgt.visual.flash(Color(1, 0.4, 0.3))
						GameAudio.play_at("crit" if r["crit"] else "hit", tgt.position, self, -4.0)
						if r["crit"]:
							cam.add_shake(0.3)
					else:
						fx.text(tgt.position, "miss", Color("#9aa3ad"))
				var text_line := String(e.get("text", ""))
				Events.log_combat(text_line, String(e.get("detail", "")), "attack")
			"damage":
				var dm: Dictionary = e["result"]
				if tgt != null and int(dm.get("dealt", 0)) > 0:
					fx.text(tgt.position, str(int(dm["dealt"])), Color("#ff6a5a"))
					tgt.visual.play("hit", 0.25)
					tgt.visual.flash(Color(1, 0.4, 0.3))
			"heal":
				if tgt != null:
					fx.text(tgt.position, "+%d" % int(e["amount"]), Color("#5fd38a"))
					fx.pulse(tgt.position, Color("#5fd38a"), 1.0)
					GameAudio.play_at("heal", tgt.position, self, -6.0)
			"status":
				var sr: Dictionary = e["result"]
				if tgt != null:
					var sname := String(DB.status(String(e["id"])).get("name", e["id"]))
					if bool(sr["applied"]):
						fx.text(tgt.position + Vector3(0, 0.4, 0), sname, Color("#f2c26b"))
						if StatusRules.interrupts(String(e["id"])) and tgt != a:
							tgt.current = {}
							if StatusRules.clears_queue(String(e["id"])):
								tgt.queue.clear()
					elif String(sr["reason"]) == "immune":
						fx.text(tgt.position + Vector3(0, 0.4, 0), "immune", Color("#9aa3ad"))
			"cast":
				if a != null:
					a.visual.play("cast", 0.5)
					fx.pulse(a.position, Color("#3fb6b0"), 1.4)
					GameAudio.play_at("cast", a.position, self, -4.0)
			"push":
				if tgt != null and actors.has(String(e.get("from", ""))):
					var src: Actor = actors[String(e["from"])]
					var dir := (tgt.position - src.position)
					dir.y = 0
					if dir.length() > 0.01:
						var dest := tgt.position
						var stepv := dir.normalized() * 0.25
						for i in int(float(e["distance"]) / 0.25):
							var np := dest + stepv
							if grid.can_stand(np, Actor.RADIUS):
								dest = np
							else:
								break
						tgt.set_pos(dest)
						tgt.stop()
			"throw":
				_spawn_grenade(a, String(e["item"]), String(e.get("target", "")))
			"place_mine":
				_place_mine(a, String(e["item"]))
			"reveal":
				if a != null:
					reveal_radius(a.position, float(e["radius"]), a)
			"swap":
				if a != null:
					a.visual.refresh_weapons(a.sheet)
			"energy":
				if tgt != null:
					fx.text(tgt.position, "+%d EN" % int(e["amount"]), Color("#3fb6b0"))
	for uid in res.get("downed", []):
		if actors.has(uid):
			on_downed(actors[uid], a.uid if a != null else "")


func on_downed(t: Actor, killer: String) -> void:
	var s := t.sheet
	if t.role == "party":
		if s.has_status("downed"):
			return
		s.hp = 0
		StatusRules.apply(s, "downed", 9999.0)
		t.queue.clear()
		t.current = {}
		t.stop()
		Events.toast("%s is down!" % s.display_name, "danger")
		Events.post("ally_downed", {"uid": t.uid})
		GameAudio.play("downed", -2.0)
		if bool(Settings.get_v("autopause_member_down")) and combat.active:
			set_paused(true, "%s is down" % s.display_name)
		var standing := 0
		for p in party_actors():
			if not (p as Actor).sheet.is_downed():
				standing += 1
		if standing == 0:
			_game_over()
		elif t.uid == Game.state.controlled:
			cycle_control()
		return
	# Enemies and hostile NPCs die (machines are wrecked).
	if s.dead:
		return
	s.dead = true
	s.hp = 0
	t.stop()
	t.queue.clear()
	t.current = {}
	t.visual.set_downed(true)
	t.visual.set_selection("")
	var lead_target := controlled() != null and controlled().target_uid == t.uid
	for o in actors.values():
		(o as Actor).queue.purge_target(t.uid)
		if (o as Actor).target_uid == t.uid:
			(o as Actor).target_uid = ""
		if String((o as Actor).current.get("target", "")) == t.uid:
			(o as Actor).current = {}
	if lead_target and combat.active and bool(Settings.get_v("autopause_target_dead")) and alert_hostile_count() > 0:
		set_paused(true, "%s defeated" % s.display_name)
	Game.state.stats["kills"] = int(Game.state.stats.get("kills", 0)) + 1
	var xp := int(DB.enemy(s.template).get("xp", 0))
	var got := Game.state.grant_xp(xp, "enemy:" + t.uid, "Defeated " + s.display_name)
	if got > 0:
		fx.text(t.position + Vector3(0, 0.5, 0), "+%d XP" % got, Color("#b9a7ff"))
	Events.post("enemy_killed", {"uid": t.uid, "template": s.template, "encounter": t.encounter_id, "npc": t.npc_id})
	var rec: Dictionary = Game.state.enemies.get(t.uid, {"template": s.template})
	rec["state"] = "dead"
	rec["pos"] = [t.position.x, t.position.z, t.rotation_degrees.y]
	rec["encounter"] = t.encounter_id
	rec["npc_id"] = t.npc_id
	rec.erase("sheet")
	Game.state.enemies[t.uid] = rec
	if t.npc_id != "":
		if not Game.state.npcs.has(t.npc_id):
			Game.state.npcs[t.npc_id] = {}
		Game.state.npcs[t.npc_id]["removed"] = true
		Game.state.npcs[t.npc_id]["dead"] = true
		Game.state.set_flag(t.npc_id + "_dead", true)
	_pending_corpses.append({"uid": t.uid, "at": Game.state.sim_time + 1.4, "rec": rec})
	_check_encounter(t.encounter_id)
	refresh_markers()


func _make_corpse(uid: String, rec: Dictionary) -> void:
	var cid := "corpse_" + uid
	if objects.has(cid):
		return
	var tdef: Dictionary = DB.enemy(String(rec.get("template", "")))
	var p: Array = rec.get("pos", [0, 0, 0])
	var machine := String(tdef.get("kind", "organic")) == "machine"
	var loot: Dictionary = (tdef.get("loot", {}) as Dictionary).duplicate()
	var d := {"id": cid, "type": "wreck" if machine else "corpse", "model": "wreck" if machine else "corpse", "name": ("Wreck of " if machine else "Body of ") + String(tdef.get("name", uid)),
		"pos": [float(p[0]), float(p[1])], "rot": float(p[2]) if p.size() > 2 else 0.0, "loot": loot, "cloth": String(tdef.get("color", "#3d4552")), "reach": 2.0}
	_add_object(d)


func _check_encounter(eid: String) -> void:
	if eid == "":
		return
	var es := encounter_state(eid)
	if String(es["state"]) == "resolved":
		return
	for o in actors.values():
		var oa: Actor = o
		if oa.encounter_id == eid and not oa.sheet.dead and oa.hostile_override not in ["neutral", "fled"]:
			return
	resolve_encounter(eid, "combat")


## Resolves an encounter. Remaining participants' XP is granted once (by the
## same per-enemy keys), so killing them afterwards awards nothing more.
func resolve_encounter(eid: String, resolution: String) -> void:
	var es := encounter_state(eid)
	if String(es["state"]) == "resolved":
		return
	es["state"] = "resolved"
	es["resolution"] = resolution
	var total := 0
	for uid in Game.state.enemies.keys():
		var e: Dictionary = Game.state.enemies[uid]
		if String(e.get("encounter", "")) != eid:
			continue
		var xp := int(DB.enemy(String(e.get("template", ""))).get("xp", 0))
		total += Game.state.grant_xp(xp, "enemy:" + String(uid), "Resolved " + String(DB.encounters.get(eid, {}).get("name", eid)))
	for o in actors.values():
		var oa: Actor = o
		if oa.encounter_id == eid and not oa.sheet.dead and resolution not in ["combat", "bypassed"]:
			oa.alert = false
			oa.hostile_override = "neutral"
			oa.current = {}
			oa.queue.clear()
	var ed: Dictionary = DB.encounters.get(eid, {})
	if int(ed.get("bonus_xp", 0)) > 0:
		Game.state.grant_xp(int(ed["bonus_xp"]), "enc_bonus:" + eid, String(ed.get("name", eid)))
	Effects.apply_all(ed.get("on_resolve", []), Game.state)
	if resolution != "combat":
		Effects.apply_all(ed.get("on_peaceful", []), Game.state)
	Events.post("encounter_resolved", {"id": eid, "resolution": resolution})
	if total > 0 and resolution != "combat":
		Events.toast("Encounter resolved without a fight: +%d XP" % total, "quest")


func _game_over() -> void:
	game_over = true
	paused = true
	Events.post("game_over", {})
	ui_request.emit("game_over", {})


# ================================================================ grenades & mines
func _spawn_grenade(a: Actor, item: String, target_uid: String) -> void:
	var to := a.position
	if actors.has(target_uid):
		to = (actors[target_uid] as Actor).position
	var mi := MeshKit.sphere(0.09, MeshKit.unshaded(Color("#f2c26b")), 8)
	add_child(mi)
	mi.position = a.eye_pos()
	projectiles.append({"item": item, "from": a.eye_pos(), "to": to, "t": 0.0, "dur": 0.7, "node": mi, "src": a.uid, "src_faction": faction_of(a)})


func _step_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Dictionary = projectiles[i]
		p["t"] = float(p["t"]) + dt
		var k := clampf(float(p["t"]) / float(p["dur"]), 0.0, 1.0)
		var pos := (p["from"] as Vector3).lerp(p["to"], k) + Vector3(0, sin(k * PI) * 1.4, 0)
		if is_instance_valid(p["node"]):
			(p["node"] as Node3D).position = pos
		if k >= 1.0:
			projectiles.remove_at(i)
			if is_instance_valid(p["node"]):
				(p["node"] as Node).queue_free()
			_explode(String(p["item"]), p["to"], String(p["src"]))


func _explode(item: String, at: Vector3, src: String) -> void:
	var spec: Dictionary = DB.dict(DB.item(item), "throw")
	var r := float(spec.get("radius", 3.0))
	var targets: Array = []
	for a in sheets_in_radius(at, r, true):
		targets.append((a as Actor).sheet)
	var res := ActionResolver.resolve_explosion(item, src, targets, {"difficulty": Game.state.difficulty}, Game.state.dice)
	var col := Color("#ffb04a")
	if String(spec.get("dtype", "")) == "ion":
		col = Color("#7fd0ff")
	elif not spec.has("dice"):
		col = Color("#e8eefc")
	fx.burst(at, col, r)
	cam.add_shake(0.6)
	GameAudio.play_at("explosion", at, self)
	var src_actor: Actor = actors.get(src, null)
	_apply_events(src_actor, res)
	for t in targets:
		var ta: Actor = actor_of(t)
		if ta != null and ta.role == "enemy" and not ta.alert and src_actor != null:
			_alert_enemy(ta, src_actor, "")
	make_noise(at, 12.0, "an explosion")


func _place_mine(a: Actor, item: String) -> void:
	var mid := "pmine_%s_%d" % [a.uid, int(Game.state.sim_time * 100)]
	var d := {"id": mid, "type": "mine", "model": "mine", "name": "Placed " + DB.item_name(item), "pos": [a.position.x, a.position.z], "mine_item": item, "owner": "party", "reach": 2.0}
	var o := _add_object(d)
	o.st()["detected"] = true
	o.st()["arm_at"] = Game.state.sim_time + 2.0
	o.st()["placed_mine"] = d
	o.refresh()


# ================================================================ interaction
func cmd_interact(a: Actor, wo: WorldObject, option_id: String = "") -> void:
	if a == null or wo == null:
		return
	if a.sheet.is_downed():
		return
	_pending_interact = {"actor": a.uid, "obj": wo.id, "opt": option_id}
	if wo.distance_to_actor(a) <= wo.reach:
		_do_interact(a, wo, option_id)
		_pending_interact = {}
	else:
		a.move_to(wo.approach_point(a), true)


func cmd_talk(a: Actor, npc: Actor) -> void:
	if a == null or npc == null:
		return
	_pending_interact = {"actor": a.uid, "npc": npc.uid}
	if a.position.distance_to(npc.position) <= 2.6:
		_pending_interact = {}
		talk_to(npc)
	else:
		a.move_to(grid.nearest_passable(npc.position + (a.position - npc.position).normalized() * 1.4, 3), true)


func _step_interaction(_dt: float) -> void:
	if _pending_interact.is_empty():
		return
	var a: Actor = actors.get(String(_pending_interact.get("actor", "")), null)
	if a == null or a.sheet.is_downed():
		_pending_interact = {}
		return
	if _pending_interact.has("npc"):
		var npc: Actor = actors.get(String(_pending_interact["npc"]), null)
		if npc == null:
			_pending_interact = {}
			return
		if a.position.distance_to(npc.position) <= 2.6:
			a.stop()
			_pending_interact = {}
			talk_to(npc)
		elif not a.is_moving():
			_pending_interact = {}
			Events.toast("Cannot reach %s." % npc.sheet.display_name, "warn")
		return
	var wo: WorldObject = objects.get(String(_pending_interact.get("obj", "")), null)
	if wo == null:
		_pending_interact = {}
		return
	if wo.distance_to_actor(a) <= wo.reach:
		a.stop()
		var opt := String(_pending_interact.get("opt", ""))
		_pending_interact = {}
		_do_interact(a, wo, opt)
	elif not a.is_moving():
		_pending_interact = {}
		Events.toast("Cannot reach %s." % wo.display_name(), "warn")


## Performs an option, or asks the UI to show the option menu.
func _do_interact(a: Actor, wo: WorldObject, option_id: String) -> void:
	a.face_towards(wo.center)
	var opts := wo.options(a)
	if option_id == "":
		var enabled: Array = opts.filter(func(o: Dictionary) -> bool: return bool(o.get("enabled", false)))
		var simple := enabled.size() == 1 and not (enabled[0] as Dictionary).has("skill") and not (enabled[0] as Dictionary).has("bash") and not (enabled[0] as Dictionary).has("data")
		if simple:
			option_id = String(enabled[0]["id"])
		else:
			ui_request.emit("interact_menu", {"object": wo.id, "actor": a.uid, "options": opts, "title": wo.display_name()})
			return
	perform_option(a, wo, option_id)


func perform_option(a: Actor, wo: WorldObject, option_id: String) -> Dictionary:
	var st := Game.state
	var opts := wo.options(a)
	var row: Dictionary = {}
	for o in opts:
		if String(o["id"]) == option_id:
			row = o
	if row.is_empty():
		return {"ok": false, "reason": "Unavailable."}
	if not bool(row.get("enabled", true)):
		Events.toast(String(row.get("reason", "Unavailable.")), "warn")
		return {"ok": false, "reason": String(row.get("reason", ""))}
	a.visual.play("use", 0.4)
	match option_id:
		"_open":
			wo.st()["open"] = true
			wo.refresh()
			GameAudio.play_at("door", wo.center, self)
			Events.post("door_opened", {"id": wo.id})
			Effects.apply_all(wo.def.get("on_open", []), st, {"actor": a.uid})
			return {"ok": true}
		"_loot":
			if wo.is_locked():
				return {"ok": false}
			ui_request.emit("loot", {"object": wo.id, "actor": a.uid})
			return {"ok": true}
		"_read":
			read_object(wo, a)
			return {"ok": true}
		"_dialogue":
			start_dialogue(String(wo.def["dialogue"]), null, "", {"actor": a.uid, "object": wo.id})
			return {"ok": true}
		"_open_station":
			ui_request.emit("station", {"what": String(row.get("what", "")), "actor": a.uid, "object": wo.id})
			return {"ok": true}
		"_disarm", "_recover":
			return _mine_action(a, wo, option_id, row)
	var od: Dictionary = row.get("data", {})
	if od.has("bash"):
		_start_bash(a, wo, od)
		return {"ok": true}
	if od.has("energy"):
		a.sheet.energy = maxi(0, a.sheet.energy - int(od["energy"]))
	if od.has("dialogue"):
		start_dialogue(String(od["dialogue"]), null, "", {"actor": a.uid, "object": wo.id})
		return {"ok": true}
	var success := true
	var check: Dictionary = {}
	if od.has("skill"):
		check = CombatRules.skill_check(a.sheet, String(od["skill"]), int(od.get("dc", 10)), st.dice)
		success = bool(check["success"])
		wo.record_attempt(option_id, a.uid if String(od.get("attempt_scope", "character")) == "character" else "_all")
		st.stats["checks_passed" if success else "checks_failed"] = int(st.stats.get("checks_passed" if success else "checks_failed", 0)) + 1
		var line := "%s %s check: d20 %d %s = %d vs DC %d — %s" % [a.sheet.display_name, DB.skill(String(od["skill"]))["name"], check["natural"], Rules.signed(int(check["bonus"])), check["total"], check["dc"], "SUCCESS" if success else "FAILURE"]
		Events.log_combat(line, "", "skill")
		Events.post("skill_check", check)
		fx.text(a.position, "SUCCESS" if success else "FAILED", Color("#5fd38a") if success else Color("#ff6a5a"))
	if od.has("requires_item") and bool(od.get("consume_item", false)):
		st.inventory.remove(String(od["requires_item"]), 1)
	var ctx := {"actor": a.uid, "object": wo.id}
	var logs: Array[String] = []
	logs.append_array(Effects.apply_all(od.get("effects", []), st, ctx))
	if success:
		logs.append_array(Effects.apply_all(od.get("success", []), st, ctx))
		if int(od.get("xp", 0)) > 0:
			var g := st.grant_xp(int(od["xp"]), String(od.get("key", wo.id + ":" + option_id)), String(od.get("label", "")))
			if g > 0:
				logs.append("+%d XP" % g)
		if bool(od.get("once", false)):
			wo.mark_done(option_id)
		var stext := String(od.get("success_text", ""))
		if stext != "":
			Events.toast(Game.fmt(stext), "success")
	else:
		logs.append_array(Effects.apply_all(od.get("failure", []), st, ctx))
		var ftext := String(od.get("failure_text", "The attempt fails."))
		Events.toast(Game.fmt(ftext), "warn")
	if od.has("noise"):
		make_noise(wo.center, float(od["noise"]), String(od.get("noise_text", "a noise")))
	for l in logs:
		Events.toast(l, "reward")
	wo.refresh()
	for o in objects.values():
		(o as WorldObject).refresh()
	hud_changed.emit()
	return {"ok": true, "success": success, "check": check}


func _mine_action(a: Actor, wo: WorldObject, option_id: String, row: Dictionary) -> Dictionary:
	var st := Game.state
	var dc := int(row.get("dc", 14))
	var r := CombatRules.skill_check(a.sheet, "demolitions", dc, st.dice)
	Events.log_combat("%s Demolitions check (%s): d20 %d %s = %d vs DC %d — %s" % [a.sheet.display_name, "recover" if option_id == "_recover" else "disarm", r["natural"], Rules.signed(int(r["bonus"])), r["total"], dc, "SUCCESS" if r["success"] else "FAILURE"], "", "skill")
	Events.post("skill_check", r)
	st.stats["checks_passed" if r["success"] else "checks_failed"] = int(st.stats.get("checks_passed" if r["success"] else "checks_failed", 0)) + 1
	if r["success"]:
		wo.st()["disarmed"] = true
		var item := String(wo.def.get("mine_item", "frag_mine"))
		if option_id == "_recover":
			st.inventory.add(item, 1)
			Events.toast("%s recovers a %s." % [a.sheet.display_name, DB.item_name(item)], "reward")
		else:
			Events.toast("%s disarms the mine." % a.sheet.display_name, "success")
		var g := st.grant_xp(int(wo.def.get("xp", 40)), "mine:" + wo.id, "Disarmed a mine")
		if g > 0:
			Events.toast("+%d XP" % g, "reward")
		Events.post("mine_disarmed", {"id": wo.id, "recovered": option_id == "_recover"})
		wo.refresh()
		return {"ok": true, "success": true}
	if int(r["margin"]) <= -5:
		Events.toast("%s fumbles the trigger — the mine detonates!" % a.sheet.display_name, "danger")
		detonate_mine(wo)
	else:
		Events.toast("%s cannot find a safe way in. Try again carefully." % a.sheet.display_name, "warn")
	return {"ok": true, "success": false}


func _start_bash(a: Actor, wo: WorldObject, od: Dictionary) -> void:
	var b: Dictionary = od["bash"]
	if not wo.st().has("bash_hp"):
		wo.st()["bash_hp"] = int(b.get("hp", 20))
	bash_jobs.append({"actor": a.uid, "obj": wo.id, "t": 0.0, "hardness": int(b.get("hardness", 2)), "od": od})
	Events.toast("%s starts forcing %s (noisy)." % [a.sheet.display_name, wo.display_name()], "info")


func _step_bash(dt: float) -> void:
	for i in range(bash_jobs.size() - 1, -1, -1):
		var j: Dictionary = bash_jobs[i]
		var a: Actor = actors.get(String(j["actor"]), null)
		var wo: WorldObject = objects.get(String(j["obj"]), null)
		if a == null or wo == null or a.sheet.is_downed() or wo.distance_to_actor(a) > wo.reach + 0.5 or a.is_moving():
			bash_jobs.remove_at(i)
			if a != null:
				Events.toast("%s stops forcing the door." % a.sheet.display_name, "info")
			continue
		j["t"] = float(j["t"]) + dt
		if float(j["t"]) < 1.5:
			continue
		j["t"] = 0.0
		var prof := CombatRules.weapon_profile(a.sheet, "main")
		var r := Game.state.dice.roll_expr(String(prof["dice"]))
		var dmg := maxi(0, int(r["total"]) + maxi(0, a.sheet.amod("str")) + int(prof["damage"]) - int(j["hardness"]))
		wo.st()["bash_hp"] = int(wo.st()["bash_hp"]) - dmg
		a.visual.play("melee", 0.4)
		GameAudio.play_at("bash", wo.center, self)
		fx.text(wo.center, str(dmg), Color("#e8eefc"))
		cam.add_shake(0.15)
		make_noise(wo.center, float(j["od"].get("noise", 16.0)), "metal being battered")
		if int(wo.st()["bash_hp"]) <= 0:
			bash_jobs.remove_at(i)
			var od: Dictionary = j["od"]
			wo.st()["broken"] = true
			Effects.apply_all(od.get("success", []), Game.state, {"actor": a.uid})
			Events.toast(Game.fmt(String(od.get("success_text", "It gives way."))), "success")
			if int(od.get("xp", 0)) > 0:
				Game.state.grant_xp(int(od["xp"]), String(od.get("key", wo.id + ":bash")), "Forced " + wo.display_name())
			wo.refresh()


func read_object(wo: WorldObject, a: Actor) -> void:
	var cid := String(wo.def.get("codex", ""))
	var entry: Dictionary = DB.codex.get(cid, {})
	var first := Game.state.discover(cid) if cid != "" else false
	if first:
		var xp := int(entry.get("xp", wo.def.get("xp", 15)))
		Game.state.grant_xp(xp, "read:" + cid, "Discovery: " + String(entry.get("title", cid)))
	Effects.apply_all(wo.def.get("on_read", []), Game.state, {"actor": a.uid})
	ui_request.emit("reader", {"title": Game.fmt(String(entry.get("title", wo.display_name()))), "text": Game.fmt(String(entry.get("text", wo.def.get("text", "")))), "first": first})


func loot_take(wo: WorldObject, item_id: String, all: bool = false) -> Array[String]:
	var got: Array[String] = []
	var loot := wo.remaining_loot()
	var keys: Array = loot.keys() if all else [item_id]
	for k in keys:
		if not loot.has(k):
			continue
		var n := int(loot[k])
		if String(k) == "credits":
			Game.state.inventory.credits += n
			got.append("%d credits" % n)
		else:
			Game.state.inventory.add(String(k), n)
			got.append("%s%s" % [DB.item_name(String(k)), " x%d" % n if n > 1 else ""])
			Events.post("item_acquired", {"id": String(k), "count": n})
		loot.erase(k)
	if loot.is_empty():
		wo.st()["looted"] = true
		Effects.apply_all(wo.def.get("on_looted", []), Game.state)
	wo.refresh()
	GameAudio.play("loot", -6.0)
	hud_changed.emit()
	return got


# ================================================================ dialogue
func talk_to(npc: Actor) -> void:
	var n: Dictionary = DB.dict(DB.layout, "npcs").get(npc.npc_id, {})
	var did := String(Game.state.npcs.get(npc.npc_id, {}).get("dialogue", n.get("dialogue", "")))
	if did == "":
		Events.toast("%s has nothing to say." % npc.sheet.display_name, "info")
		return
	if npc.alert and hostile(controlled(), npc):
		Events.toast("%s is in no mood to talk." % npc.sheet.display_name, "warn")
		return
	start_dialogue(did, npc)


func talk_companion(uid: String) -> void:
	var did := String(DB.companions.get(uid, {}).get("dialogue", uid + "_talk"))
	if DB.dialogue(did).is_empty():
		return
	if combat.active:
		Events.toast("Not during combat.", "warn")
		return
	start_dialogue(did, actors.get(uid, null))


func start_dialogue(did: String, npc: Actor = null, npc_id: String = "", ctx: Dictionary = {}) -> bool:
	if dialogue != null and dialogue.active:
		return false
	if npc == null and npc_id != "" and actors.has(npc_id):
		npc = actors[npc_id]
	var c := ctx.duplicate()
	if not c.has("actor"):
		c["actor"] = Game.state.controlled
	dialogue = DialogueEngine.new(Game.state)
	dialogue_npc = npc
	dialogue.ended.connect(func(_id: String) -> void: call_deferred("_after_dialogue_engine_end"))
	set_modal("dialogue", true)
	if not dialogue.start(did, c):
		set_modal("dialogue", false)
		return false
	if dialogue.active:
		ui_request.emit("dialogue", {"id": did})
	return true


func dialogue_frame(speaker: String) -> void:
	var lead := controlled()
	if lead == null:
		return
	var sp: Actor = null
	if speaker == "player":
		sp = actors.get("player", lead)
	elif actors.has(speaker):
		sp = actors[speaker]
	elif dialogue_npc != null:
		sp = dialogue_npc
	if sp == null:
		return
	var listener := dialogue_npc if speaker == "player" and dialogue_npc != null else lead
	if listener == sp:
		listener = lead if sp != lead else (dialogue_npc if dialogue_npc != null else lead)
	if listener == sp:
		return
	cam.frame(sp.position, listener.position)


func _after_dialogue_engine_end() -> void:
	# Safety net when no DialogueUI is attached (tests, bots): close the modal.
	if dialogue != null and not dialogue.active:
		end_dialogue()


func end_dialogue() -> void:
	if dialogue != null and dialogue.active:
		dialogue.finish()
	cam.end_cinematic()
	set_modal("dialogue", false)
	dialogue = null
	dialogue_npc = null
	for o in objects.values():
		(o as WorldObject).refresh()
	hud_changed.emit()


# ================================================================ world effects
func _eval_rules() -> void:
	for r in DB.layout.get("rules", []):
		var rid := "rule:" + String(r.get("id", ""))
		if Game.state.claimed(rid):
			continue
		if Conditions.eval_all(r.get("if", []), Game.state):
			Game.state.claim(rid)
			Effects.apply_all(r.get("effects", []), Game.state)


func _on_event(name: String, data: Dictionary) -> void:
	if name == "world_effect":
		_world_effect(data)
	elif name == "flag_changed":
		for o in objects.values():
			(o as WorldObject).refresh()
		_eval_rules()
		refresh_hazard_avoidance()
	elif name == "object_detected":
		refresh_hazard_avoidance()
	elif name == "dialogue_ended":
		if not _dialogue_queue.is_empty():
			var nxt: String = _dialogue_queue.pop_front()
			call_deferred("_queued_dialogue", nxt)
	elif name == "tutorial":
		ui_request.emit("tutorial", data)


func _world_effect(e: Dictionary) -> void:
	match String(e.get("type", "")):
		"join_party":
			var who := String(e["who"])
			Game.recruit(who)
			var start_pos := (controlled().position if controlled() else Vector3.ZERO) + Vector3(1.2, 0, 0.8)
			var placeholder := who + "_npc"
			if actors.has(placeholder):
				var ph: Actor = actors[placeholder]
				start_pos = ph.position
				actors.erase(placeholder)
				ph.queue_free()
				if not Game.state.npcs.has(placeholder):
					Game.state.npcs[placeholder] = {}
				Game.state.npcs[placeholder]["removed"] = true
			if not actors.has(who) and Game.state.party.has(who):
				var s := Game.state.get_char(who)
				var a := _make_actor(s, "party")
				a.set_pos(grid.nearest_passable(start_pos, 3))
			refresh_markers()
			hud_changed.emit()
		"leave_party":
			Game.set_active(String(e["who"]), false)
			hud_changed.emit()
		"start_encounter":
			alert_encounter(String(e["id"]))
		"resolve_encounter":
			spawn_encounter(String(e["id"]))
			resolve_encounter(String(e["id"]), String(e.get("resolution", "peaceful")))
		"heal_party":
			for p in party_actors():
				var pa: Actor = p
				StatusRules.remove(pa.sheet, "downed")
				pa.sheet.hp = pa.sheet.max_hp()
				pa.sheet.energy = pa.sheet.max_energy()
			hud_changed.emit()
		"damage_party":
			var who2 := String(e.get("who", "actor"))
			var targets: Array = []
			if who2 == "party":
				targets = party_actors()
			else:
				var uid := String(e.get("actor", "player")) if who2 == "actor" else who2
				if actors.has(uid):
					targets = [actors[uid]]
			for t in targets:
				var ta: Actor = t
				var res := CombatRules.apply_damage(ta.sheet, [{"amount": int(e["amount"]), "dtype": String(e.get("dtype", "energy"))}], {"difficulty": Game.state.difficulty})
				fx.text(ta.position, str(int(res["dealt"])), Color("#ff6a5a"))
				if bool(res["downed"]):
					on_downed(ta, "")
		"status":
			var who3 := String(e.get("who", "actor"))
			var uid3 := String(e.get("actor", "player")) if who3 == "actor" else who3
			if actors.has(uid3):
				StatusRules.apply((actors[uid3] as Actor).sheet, String(e["id"]), float(e.get("duration", 9.0)), "effect")
		"world_object":
			if objects.has(String(e["id"])):
				(objects[String(e["id"])] as WorldObject).refresh()
		"npc":
			_npc_effect(String(e["id"]), e.get("set", {}))
		"open", "minigame":
			ui_request.emit(String(e["type"]), e)
		"cinematic":
			# Headless runs (tests, bots) have no presentation layer: skip
			# straight to whatever the cinematic leads into.
			if ui_request.get_connections().is_empty():
				if String(e.get("then", "")) != "":
					call_deferred("_queued_dialogue", String(e["then"]))
			else:
				ui_request.emit("cinematic", e)
		"teleport":
			var to: Array = e["to"]
			var i := 0
			for p in party_actors():
				(p as Actor).set_pos(grid.nearest_passable(Vector3(float(to[0]) - i * 0.8, 0, float(to[1]) + i * 0.6), 4))
				(p as Actor).stop()
				i += 1
			cam.snap()
		"combat_hostile":
			var fac := String(e["faction"])
			for o in actors.values():
				var oa: Actor = o
				if oa.sheet.faction == fac and not oa.sheet.dead:
					oa.hostile_override = ""
					if oa.role == "npc":
						oa.role = "enemy"
					_alert_enemy(oa, controlled(), "")
		"autosave":
			call_deferred("_checkpoint", String(e.get("label", "Checkpoint")))
		"end_dialogue":
			ui_request.emit("end_dialogue", {})
		"sound":
			GameAudio.play(String(e["id"]))
		"dialogue":
			call_deferred("_queued_dialogue", String(e["id"]))
		"enemy":
			_enemy_effect(String(e["id"]), e.get("set", {}))
		"area_damage":
			_area_damage(e)
		"reveal_area":
			for aid in e.get("areas", []):
				_reveal_area(String(aid))


var _dialogue_queue: Array[String] = []


func _queued_dialogue(did: String) -> void:
	if dialogue != null and dialogue.active:
		if not _dialogue_queue.has(did):
			_dialogue_queue.append(did)
		return
	start_dialogue(did)


func _enemy_effect(uid: String, setd: Dictionary) -> void:
	if not actors.has(uid):
		return
	var a: Actor = actors[uid]
	if setd.has("hostile_override"):
		a.hostile_override = String(setd["hostile_override"])
		if a.hostile_override in ["offline", "neutral"]:
			a.alert = false
			a.current = {}
			a.queue.clear()
	if setd.has("faction"):
		a.sheet.faction = String(setd["faction"])
	if setd.has("alert"):
		a.alert = bool(setd["alert"])
		if a.alert:
			a.in_combat = combat.active
	if setd.has("faction") and String(setd["faction"]) == "party":
		a.visual.accent = Color("#5fd38a")
	_check_encounter(a.encounter_id)
	refresh_markers()


func _area_damage(e: Dictionary) -> void:
	var at: Array = e["at"]
	var c := Vector3(float(at[0]), 0, float(at[1]))
	var r := float(e.get("radius", 3.0))
	var fac := String(e.get("faction", ""))
	var res := {"events": [], "log": [], "downed": []}
	for o in sorted_actors():
		var a: Actor = o
		if a.sheet.dead or a.sheet.is_downed() or a.position.distance_to(c) > r:
			continue
		if fac != "" and faction_of(a) != fac:
			continue
		var roll := Game.state.dice.roll_expr(String(e.get("dice", "2d6")))
		var dmg := CombatRules.apply_damage(a.sheet, [{"amount": int(roll["total"]), "dtype": String(e.get("dtype", "kinetic"))}], {"difficulty": Game.state.difficulty})
		res["events"].append({"type": "damage", "target": a.uid, "result": dmg})
		res["log"].append("%s takes %d %s damage." % [a.sheet.display_name, int(dmg["dealt"]), e.get("dtype", "kinetic")])
		if bool(dmg["downed"]):
			res["downed"].append(a.uid)
		elif String(e.get("status", "")) != "":
			var sr := StatusRules.apply(a.sheet, String(e["status"]), float(e.get("duration", 3.0)), "environment")
			res["events"].append({"type": "status", "target": a.uid, "id": e["status"], "result": sr})
	fx.burst(c, Color("#e8eefc"), r)
	cam.add_shake(0.6)
	GameAudio.play_at("explosion", c, self)
	_apply_events(null, res)


func _reveal_area(aid: String) -> void:
	var ai := grid.area_names.find(aid)
	if ai < 0:
		return
	for i in grid.area_of.size():
		if grid.area_of[i] == ai and grid.walk[i] == 1:
			grid.explored[i] = 1
	Events.toast("Map updated: %s" % DB.dict(DB.dict(DB.layout, "areas"), aid).get("name", aid), "discovery")


func _npc_effect(nid: String, setd: Dictionary) -> void:
	var st := Game.state
	if not st.npcs.has(nid):
		st.npcs[nid] = {}
	for k in setd.keys():
		if k in ["removed", "downed", "dead", "dialogue", "state"]:
			st.npcs[nid][k] = setd[k]
	if bool(setd.get("kill", false)):
		if actors.has(nid):
			var ka: Actor = actors[nid]
			ka.role = "enemy"
			StatusRules.remove(ka.sheet, "downed")
			ka.sheet.hp = 0
			st.enemies[nid] = {"template": ka.sheet.template, "encounter": "", "state": "alive", "npc_id": nid}
			on_downed(ka, "player")
		return
	if bool(setd.get("removed", false)):
		if actors.has(nid):
			var a: Actor = actors[nid]
			actors.erase(nid)
			a.queue_free()
		return
	if not actors.has(nid):
		if bool(setd.get("spawn", false)) or setd.has("pos"):
			st.npcs[nid].erase("removed")
			spawn_npc(nid, true)
		else:
			return
	var na: Actor = actors.get(nid, null)
	if na == null:
		return
	if setd.has("move_to"):
		var m: Array = setd["move_to"]
		na.move_to(Vector3(float(m[0]), 0, float(m[1])))
		st.npcs[nid]["pos"] = m
	if setd.has("pos"):
		var p: Array = setd["pos"]
		na.set_pos(Vector3(float(p[0]), 0, float(p[1])))
	if setd.has("hostile") and bool(setd["hostile"]):
		na.role = "enemy"
		na.hostile_override = "hostile"
		st.npcs[nid]["state"] = "enemy"
		Game.state.enemies[nid] = {"template": na.sheet.template, "encounter": String(setd.get("encounter", "")), "state": "alive", "npc_id": nid}
		na.encounter_id = String(setd.get("encounter", ""))
		if na.encounter_id != "":
			spawn_encounter(na.encounter_id)
		_alert_enemy(na, controlled(), "")
	if setd.has("downed"):
		if bool(setd["downed"]):
			StatusRules.apply(na.sheet, "downed", 1.0)
			na.sheet.hp = 0
		else:
			StatusRules.remove(na.sheet, "downed")
			na.sheet.hp = maxi(1, na.sheet.max_hp() / 2)
	if setd.has("follow"):
		pass
	refresh_markers()


# ================================================================ markers & picking
func refresh_markers() -> void:
	var lead := controlled()
	for o in actors.values():
		var a: Actor = o
		var k := ""
		if a.role == "party":
			k = "controlled" if a == lead else "ally"
		elif lead != null and a.uid == lead.target_uid:
			k = "hostile" if hostile(lead, a) else "neutral"
		a.visual.set_selection(k)


func pick(mouse: Vector2) -> Dictionary:
	## Returns {"actor": Actor} / {"object": WorldObject} / {"ground": Vector3}.
	var ray := cam.screen_ray(mouse)
	var o: Vector3 = ray[0]
	var d: Vector3 = ray[1]
	var best_t := INF
	var best: Dictionary = {}
	for a in actors.values():
		var aa: Actor = a
		if not aa.visible or (aa.sheet.dead and aa.role != "party"):
			continue
		var t := _ray_capsule(o, d, aa.position, 1.8, 0.55)
		if t < best_t:
			best_t = t
			best = {"actor": aa}
	for wobj in objects.values():
		var wo: WorldObject = wobj
		if not wo.visible or not wo.is_visible_obj() and wo.kind != "door":
			continue
		if wo.kind == "hazard":
			continue
		var t2 := _ray_capsule(o, d, wo.center, 1.6 if wo.kind != "door" else 3.0, 0.7 if wo.kind != "door" else 1.2)
		if t2 < best_t:
			best_t = t2
			best = {"object": wo}
	if best.is_empty() and absf(d.y) > 0.001:
		var tg := -o.y / d.y
		if tg > 0:
			best = {"ground": o + d * tg}
	return best


static func _ray_capsule(o: Vector3, d: Vector3, base: Vector3, h: float, r: float) -> float:
	# Approximate vertical capsule as samples along its axis.
	var best := INF
	for i in 5:
		var c := base + Vector3(0, h * (i + 0.5) / 5.0, 0)
		var oc := c - o
		var t := oc.dot(d)
		if t < 0:
			continue
		var dist := (o + d * t).distance_to(c)
		if dist <= r and t < best:
			best = t
	return best


func _update_hover() -> void:
	if Game.ui_blocked() or cam == null:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var mp := vp.get_mouse_position()
	var p := pick(mp)
	var n: Node = p.get("actor", p.get("object", null))
	if n != hover_node:
		if hover_node != null and is_instance_valid(hover_node):
			if hover_node is WorldObject:
				(hover_node as WorldObject).label.visible = false
			elif hover_node is Actor and (hover_node as Actor).role != "party":
				(hover_node as Actor).show_label("", Color.WHITE)
		hover_node = n
		if n is WorldObject:
			var wo := n as WorldObject
			wo.label.text = wo.display_name() + (" [LOCKED]" if wo.kind == "door" and wo.is_locked() else "")
			wo.label.visible = true
		elif n is Actor:
			var a := n as Actor
			if a.role != "party":
				var lead := controlled()
				var hos := lead != null and hostile(lead, a)
				a.show_label(a.sheet.display_name + (" (hostile)" if hos else ""), Color("#ff8a7a") if hos else Color("#f2e6c8"))
		ui_request.emit("hover", {"node": n})


func handle_click(mouse: Vector2, button: int, double: bool) -> void:
	var lead := controlled()
	if lead == null:
		return
	var p := pick(mouse)
	if p.has("actor"):
		var a: Actor = p["actor"]
		if a.role == "party":
			switch_control(a.uid)
			return
		cmd_target(lead, a.uid)
		if hostile(lead, a):
			if double or button == MOUSE_BUTTON_LEFT and lead.target_uid == a.uid and Input.is_key_pressed(KEY_SHIFT):
				cmd_attack(lead, a.uid)
		else:
			if double:
				cmd_talk(lead, a)
	elif p.has("object"):
		var wo: WorldObject = p["object"]
		cmd_interact(lead, wo, "")
	elif p.has("ground"):
		lead.target_uid = lead.target_uid
		cmd_move(lead, p["ground"])


# ================================================================ save sync
func sync_to_state() -> void:
	var st := Game.state
	st.positions.clear()
	for p in party_actors():
		var a: Actor = p
		st.positions[a.uid] = [snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01), snappedf(a.rotation_degrees.y, 0.1)]
		st.queues[a.uid] = a.queue.to_array()
	st.positions["_cam"] = [cam.yaw, cam.pitch, cam.distance]
	for o in actors.values():
		var a: Actor = o
		if a.role == "enemy" or (a.role == "npc" and Game.state.enemies.has(a.uid)):
			var rec: Dictionary = st.enemies.get(a.uid, {"template": a.sheet.template})
			if a.sheet.dead:
				continue
			rec["sheet"] = a.sheet.to_dict()
			rec["pos"] = [snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01), snappedf(a.rotation_degrees.y, 0.1)]
			rec["home"] = [a.home.x, a.home.z]
			rec["alert"] = a.alert
			rec["hostile_override"] = a.hostile_override
			rec["target"] = a.target_uid
			rec["recovery"] = a.recovery
			rec["round_clock"] = a.round_clock
			rec["queue"] = a.queue.to_array()
			rec["encounter"] = a.encounter_id
			rec["npc_id"] = a.npc_id
			rec["state"] = "alive"
			st.enemies[a.uid] = rec
		elif a.role == "npc":
			if not st.npcs.has(a.npc_id):
				st.npcs[a.npc_id] = {}
			st.npcs[a.npc_id]["pos"] = [snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01)]
			st.npcs[a.npc_id]["rot"] = snappedf(a.rotation_degrees.y, 0.1)
			if a.sheet.template != "":
				st.npcs[a.npc_id]["sheet"] = a.sheet.to_dict()
	var clocks := {}
	for p in party_actors():
		var a2: Actor = p
		clocks[a2.uid] = [a2.recovery, a2.round_clock, a2.target_uid]
	st.combat = {"active": combat.active, "time": combat.combat_time, "party_clocks": clocks}
	st.explored = grid.explored.duplicate()
	st.area = current_area
