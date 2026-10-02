class_name PlaythroughBot
extends RefCounted
## Automated playthrough driver. It plays the real World through the same
## command API the input layer uses (move, open, interact, talk, choose
## dialogue options, queue attacks and items), fast-forwarding the
## simulation. It is an automated integration test, not a human playtest.

const DT := 1.0 / 30.0

var tree: SceneTree
var host: Node
var world: World
var log: PackedStringArray = []
var prefs: Dictionary = {}
var default_prefs: Array = []
var failures: PackedStringArray = []
var steps_run := 0
var choice_trace: Array = []
var max_sim := 0.0


var combat_lines: PackedStringArray = []
## Called by Routes at the threshold of each major area (before its door
## opens); tools/godot/gen_dev_stages.gd captures preset stages here.
var stage_hook: Callable = Callable()


func stage(name: String) -> void:
	if stage_hook.is_valid():
		stage_hook.call(name)


func _init(t: SceneTree, h: Node) -> void:
	tree = t
	host = h
	Events.combat_log.connect(func(e: Dictionary) -> void:
		combat_lines.append("[%6.1fs] %s | %s" % [Game.state.sim_time if Game.state else 0.0, String(e.get("text", "")), String(e.get("detail", ""))]))


func note(s: String) -> void:
	log.append("[%6.1fs] %s" % [Game.state.sim_time if Game.state else 0.0, s])
	print("BOT: ", s)


func fail(s: String) -> void:
	failures.append(s)
	note("FAIL: " + s)


# ------------------------------------------------------------ setup
func new_game(build: Dictionary, difficulty: String = "standard", seed_v: int = 7) -> void:
	Game.new_game(build, difficulty)
	Game.state.dice.set_seed(seed_v)
	start_world()


func start_world() -> void:
	if world != null:
		world.queue_free()
		world = null
		await tree.process_frame
	world = World.new()
	world.manual_step = true
	host.add_child(world)
	await tree.process_frame


func free_world() -> void:
	if world != null:
		world.queue_free()
		world = null
	await tree.process_frame


# ------------------------------------------------------------ time
func step(seconds: float) -> void:
	var n := int(ceil(seconds / DT))
	for i in n:
		if world.sim_running():
			world.sim_step(DT)
			steps_run += 1
		if i % 20 == 19:
			await tree.process_frame
		if world.modal.has("dialogue") or world.game_over:
			break
	await tree.process_frame


func lead() -> Actor:
	return world.controlled()


## Walk the controlled character to p, handling dialogues and fights that
## interrupt. Returns true when within `tol` metres.
func walk(p: Vector3, tol: float = 1.2, timeout: float = 90.0) -> bool:
	var t := 0.0
	var attempts := 0
	level_ups()
	while t < timeout:
		await pump()
		if world.game_over:
			return false
		if world.combat.active:
			await fight()
			continue
		var a := lead()
		if a.position.distance_to(p) <= tol:
			return true
		if not a.is_moving():
			attempts += 1
			if attempts > 6:
				fail("walk: cannot reach %s from %s" % [str(p), str(a.position)])
				return false
			world.cmd_move(a, p)
		await step(0.5)
		t += 0.5
	fail("walk: timeout reaching %s" % str(p))
	return false


func goto_obj(oid: String) -> WorldObject:
	var wo: WorldObject = world.objects.get(oid, null)
	if wo == null:
		fail("no object " + oid)
		return null
	var a := lead()
	await walk(wo.approach_point(a), 0.6)
	return wo


func open_door(did: String) -> bool:
	var wo := await goto_obj(did)
	if wo == null:
		return false
	if wo.is_open():
		return true
	if wo.is_locked():
		fail("door %s is locked" % did)
		return false
	world.perform_option(lead(), wo, "_open")
	await step(0.3)
	return wo.is_open()


func use(oid: String, option: String) -> Dictionary:
	var wo := await goto_obj(oid)
	if wo == null:
		return {}
	if wo.distance_to_actor(lead()) > wo.reach:
		fail("not in reach of %s" % oid)
	var r := world.perform_option(lead(), wo, option)
	note("use %s/%s -> %s %s (acting: %s)" % [oid, option, str(r.get("success", r.get("ok", ""))), String(r.get("reason", "")), lead().sheet.display_name])
	await step(0.2)
	await pump()
	return r


func loot(oid: String) -> void:
	var wo := await goto_obj(oid)
	if wo == null:
		return
	var got := world.loot_take(wo, "", true)
	note("looted %s: %s" % [oid, ", ".join(got)])
	equip_best()
	await pump()


func read(oid: String) -> void:
	var wo := await goto_obj(oid)
	if wo == null:
		return
	world.read_object(wo, lead())
	await pump()


func talk(npc_id: String) -> void:
	var a: Actor = world.actors.get(npc_id, null)
	if a == null:
		fail("no npc " + npc_id)
		return
	await walk(a.position, 2.2)
	world.talk_to(a)
	await pump()


func switch_to(uid: String) -> void:
	world.switch_control(uid)
	await tree.process_frame


# ------------------------------------------------------------ dialogue
## Runs any active dialogue to completion, choosing options by preference.
func pump() -> void:
	var guard := 0
	while world.dialogue != null and world.dialogue.active and guard < 200:
		guard += 1
		var eng := world.dialogue
		var choices := eng.choices()
		if choices.is_empty():
			eng.advance()
		else:
			var pick := _pick(eng, choices)
			choice_trace.append("%s:%s → %s" % [eng.dialogue_id, eng.node_id, String(pick["text"]).substr(0, 60)])
			var r := eng.choose(int(pick["index"]))
			if r.has("check") and not (r["check"] as Dictionary).is_empty():
				var ck: Dictionary = r["check"]
				note("check %s (%s) %d vs %d: %s" % [ck["skill"], ck["actor_name"], ck["total"], ck["dc"], "success" if ck["success"] else "FAILED"])
	if guard >= 200:
		fail("dialogue loop guard tripped in " + (world.dialogue.dialogue_id if world.dialogue else "?"))
	if world.dialogue != null and not world.dialogue.active:
		world.end_dialogue()
	await tree.process_frame
	await tree.process_frame
	if world.dialogue != null and world.dialogue.active:
		await pump()


var _visited: Dictionary = {}


func _pick(eng: DialogueEngine, choices: Array) -> Dictionary:
	var enabled: Array = choices.filter(func(c: Dictionary) -> bool: return bool(c["enabled"]))
	if enabled.is_empty():
		fail("no enabled choice in %s:%s" % [eng.dialogue_id, eng.node_id])
		return choices[0]
	var plist: Array = prefs.get(eng.dialogue_id, []) + default_prefs
	for p in plist:
		for c in enabled:
			if String(c["text"]).to_lower().contains(String(p).to_lower()) or String(c.get("tag", "")).to_lower().contains(String(p).to_lower()):
				var key := "%s:%s:%d" % [eng.dialogue_id, eng.node_id, int(c["index"])]
				if _visited.get(key, 0) < 2:
					_visited[key] = _visited.get(key, 0) + 1
					return c
	# Fall back: an unvisited choice, else the last one (usually "leave").
	for c in enabled:
		var key2 := "%s:%s:%d" % [eng.dialogue_id, eng.node_id, int(c["index"])]
		if not _visited.has(key2):
			_visited[key2] = 1
			return c
	return enabled[enabled.size() - 1]


# ------------------------------------------------------------ combat
func fight(timeout: float = 240.0) -> bool:
	var t := 0.0
	var names: PackedStringArray = []
	for o in world.actors.values():
		var oa: Actor = o
		if oa.role != "party" and oa.alert and not oa.sheet.dead:
			names.append("%s(%d)@%.0f,%.0f" % [oa.sheet.display_name, oa.sheet.hp, oa.position.x, oa.position.z])
	note("combat begins vs %s; party %s; lead @%.0f,%.0f" % [", ".join(names), party_hp(), lead().position.x, lead().position.z])
	while world.combat.active and t < timeout:
		await pump()
		if world.game_over:
			fail("party wiped at %s" % str(lead().position))
			return false
		if world.paused:
			world.set_paused(false)
		var a := lead()
		if a.sheet.is_downed():
			world.cycle_control()
			a = lead()
		var low := float(a.sheet.hp) / float(maxi(1, a.sheet.max_hp())) < 0.4
		# Revive a downed ally first, as a player would.
		if a.queue.is_empty() and a.current.is_empty():
			for p in world.party_actors():
				var pa: Actor = p
				if pa != a and pa.sheet.is_downed() and not pa.sheet.dead:
					var rv := "repair_kit" if pa.sheet.kind == "machine" else "medpac"
					if Game.state.inventory.count(rv) > 0:
						world.queue_action(a, {"type": "item", "id": rv, "target": pa.uid})
						break
		if low and a.queue.is_empty() and a.current.is_empty():
			var heal := "repair_kit" if a.sheet.kind == "machine" else "medpac"
			if Game.state.inventory.count("trauma_pack") > 0 and a.sheet.kind == "organic":
				heal = "trauma_pack"
			if Game.state.inventory.count(heal) > 0:
				world.queue_action(a, {"type": "item", "id": heal, "target": a.uid})
		if not world.valid_hostile_target(a, a.target_uid):
			var h := world.nearest_hostile(a)
			if h != null:
				world.cmd_target(a, h.uid)
		if a.queue.is_empty() and a.current.is_empty() and world.valid_hostile_target(a, a.target_uid):
			# The controlled character plays like a sensible player: the same
			# tactical brain companions use (heals, revives, powers, grenades,
			# feats), falling back to a basic attack.
			var act := AIBrain.companion_action(a, world)
			if act.is_empty() or (act.has("target") and String(act["target"]) == ""):
				act = {"type": "attack", "target": a.target_uid}
			if world.queue_action(a, act) != "":
				world.queue_action(a, {"type": "attack", "target": a.target_uid})
		await step(0.5)
		t += 0.5
	if world.combat.active:
		fail("combat timeout")
		return false
	note("combat over (%.0fs); party %s; medpacs %d" % [t, party_hp(), Game.state.inventory.count("medpac")])
	await pump()
	if world.controlled() != null and world.controlled().uid != "player" and world.actors.has("player"):
		world.switch_control("player")
	await rest()
	level_ups()
	return true


## Rests once the area is clear, as a player would between fights.
func rest() -> void:
	for i in 6:
		if world.combat.active or world.game_over:
			return
		var r := world.rest()
		if bool(r["ok"]):
			note("rested; party %s" % party_hp())
			return
		await step(1.0)
		await pump()
	note("could not rest: " + String(world.rest_block_reason()))


func party_hp() -> String:
	var out: PackedStringArray = []
	for uid in Game.state.party:
		var s := Game.state.get_char(uid)
		out.append("%s %d/%d L%d" % [s.display_name.split(" ")[0], s.hp, s.max_hp(), s.level])
	return ", ".join(out)


## Puts on the best body armour each party member can wear, as a player
## would after looting (through the same atomic equip path the UI uses).
func equip_best() -> void:
	for uid in Game.state.roster:
		var s := Game.state.get_char(uid)
		if s == null:
			continue
		for inst in Game.state.inventory.instances.duplicate():
			var id := String(inst["id"])
			var it: Dictionary = DB.item(id)
			if String(it.get("slot", "")) != "body":
				continue
			if EquipmentRules.can_equip(s, id, "body") != "":
				continue
			var cmp := EquipmentRules.compare(s, id, "body")
			var cur: Variant = s.equipment.get("body", null)
			var before := s.defense()
			var after := before + int(DB.dict(cmp, "delta").get("Defense", 0)) if cmp.has("delta") else before
			if cur == null or after > before:
				var r := EquipmentRules.equip(s, Game.state.inventory, String(inst["uid"]), "body")
				if bool(r["ok"]):
					note("%s equips %s (Defense %d -> %d)" % [s.display_name, it.get("name", id), before, s.defense()])


## Spends pending level-ups with the Recommended choices, as a player would.
func level_ups() -> void:
	for uid in Game.state.roster:
		var s := Game.state.get_char(uid)
		while s != null and s.levels_available() > 0:
			var r := Progression.apply_level_up(s, Progression.recommended_choices(s))
			if not bool(r["ok"]):
				fail("level up %s: %s" % [uid, str(r["errors"])])
				break
			note("%s reached level %d" % [s.display_name, s.level])


# ------------------------------------------------------------ assertions
func expect(cond: bool, what: String) -> void:
	if cond:
		note("ok: " + what)
	else:
		fail(what)


## True (and recorded once) when the party has wiped: the route stops.
func halted() -> bool:
	if world != null and world.game_over:
		if not _halt_noted:
			_halt_noted = true
			fail("route halted: the party was defeated")
		return true
	return false


var _halt_noted := false


func flag(name: String) -> Variant:
	return Game.state.flags.get(name, null)


## Snapshot of state that a reload must preserve.
func snapshot() -> Dictionary:
	var st := Game.state
	var inv := {}
	for k in st.inventory.stacks.keys():
		inv[k] = st.inventory.stacks[k]
	var q := {}
	for k in st.quests.keys():
		q[k] = [st.quests[k]["state"], st.quests[k]["stage"]]
	return {"survivors": st.survivors(), "credits": st.inventory.credits, "inv": inv, "inst": st.inventory.instances.size(), "quests": q,
		"influence": st.influence.duplicate(), "alignment": st.alignment, "party": st.party.duplicate(), "xp": st.player().xp,
		"dead_enemies": st.enemies.keys().filter(func(k: String) -> bool: return String(st.enemies[k].get("state", "")) == "dead").size(),
		"flags": {"ward_choice": st.flags.get("ward_choice"), "med": st.flags.get("med_supplies_choice"), "senna": st.flags.get("senna_fate")}}
