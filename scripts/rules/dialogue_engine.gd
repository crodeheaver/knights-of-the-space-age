class_name DialogueEngine
extends RefCounted
## Runs one authored conversation from data/dialogue/*.json.
## * Entry points are chosen by condition (repeat-conversation handling).
## * Node effects apply once per node (ledger by node id) unless repeatable.
## * Skill checks resolve once per check id and are stored in GameState.checks;
##   re-entering a conversation never re-rolls a resolved check.
## * Every line and choice is appended to the conversation history.

signal line_changed(node: Dictionary)
signal ended(dialogue_id: String)

var st: GameState
var dlg: Dictionary = {}
var dialogue_id: String = ""
var node_id: String = ""
var node: Dictionary = {}
var last_check: Dictionary = {}
var active := false
var ctx: Dictionary = {}
var pending_log: Array[String] = []


func _init(state: GameState) -> void:
	st = state


func start(id: String, context: Dictionary = {}) -> bool:
	dlg = DB.dialogue(id)
	if dlg.is_empty():
		push_error("Unknown dialogue " + id)
		return false
	dialogue_id = id
	ctx = context
	active = true
	var entry := ""
	for e in DB.arr(dlg, "entry"):
		if Conditions.eval_all(e.get("if", []), st, ctx):
			entry = String(e["node"])
			break
	if entry == "":
		entry = String(dlg.get("start", "start"))
	Events.post("dialogue_started", {"dialogue": id})
	_enter(entry)
	return true


func _enter(id: String) -> void:
	if id == "" or id == "end":
		finish()
		return
	node_id = id
	node = DB.dict(DB.dict(dlg, "nodes"), id)
	if node.is_empty():
		push_error("Dialogue %s: missing node %s" % [dialogue_id, id])
		finish()
		return
	# Redirect nodes: {"redirect": [{"if":..., "node":...}, ...]}
	if node.has("redirect"):
		for r in node["redirect"]:
			if Conditions.eval_all(r.get("if", []), st, ctx):
				_enter(String(r["node"]))
				return
	var seen_key := "%s:%s" % [dialogue_id, id]
	var first := not st.seen_nodes.has(seen_key)
	st.seen_nodes[seen_key] = true
	if first or bool(node.get("repeat_effects", false)):
		pending_log.append_array(Effects.apply_all(node.get("effects", []), st, ctx))
	if node.has("text"):
		st.add_history(speaker_name(String(node.get("speaker", "narrator"))), text(), dialogue_id)
	line_changed.emit(current())
	if not active:
		return


func finish() -> void:
	if not active:
		return
	active = false
	Events.post("dialogue_ended", {"dialogue": dialogue_id, "node": node_id})
	ended.emit(dialogue_id)


func text() -> String:
	return Game.fmt(String(node.get("text", "")))


func speaker_id() -> String:
	return String(node.get("speaker", "narrator"))


func speaker_name(sid: String) -> String:
	var names: Dictionary = dlg.get("names", {})
	if names.has(sid):
		return String(names[sid])
	if sid == "player":
		var p := st.player()
		return p.display_name if p != null else "You"
	if DB.companions.has(sid):
		return String(DB.companions[sid]["name"])
	var npcs: Dictionary = DB.dict(DB.layout, "npcs")
	if npcs.has(sid):
		return String(npcs[sid].get("name", sid))
	return {"narrator": "", "warden": "WARDEN", "intercom": "Ship Intercom", "system": ""}.get(sid, sid.capitalize())


func current() -> Dictionary:
	return {"dialogue": dialogue_id, "node": node_id, "speaker": speaker_id(), "speaker_name": speaker_name(speaker_id()),
		"text": text(), "choices": choices(), "can_continue": has_continue(), "check": last_check, "log": pending_log.duplicate()}


func take_log() -> Array[String]:
	var l := pending_log.duplicate()
	pending_log.clear()
	return l


func has_continue() -> bool:
	return choices().is_empty()


func _check_id(c: Dictionary, index: int) -> String:
	var ck: Dictionary = c.get("check", {})
	return String(ck.get("id", "%s:%s:%d" % [dialogue_id, node_id, index]))


func check_actor(ck: Dictionary) -> CharacterSheet:
	var who := String(ck.get("who", "player"))
	return st.get_char(who)


## Visible choices with availability and check annotations.
func choices() -> Array:
	var out: Array = []
	var raw: Array = DB.arr(node, "choices")
	for i in raw.size():
		var c: Dictionary = raw[i]
		var cond_ok := Conditions.eval_all(c.get("if", []), st, ctx)
		if not cond_ok and not c.has("show_locked"):
			continue
		var enabled := cond_ok
		var reason := "" if cond_ok else Game.fmt(String(c.get("show_locked", "Requirement not met")))
		var label := Game.fmt(String(c.get("text", "...")))
		var tag := String(c.get("tag", ""))
		var check_info := {}
		if c.has("check"):
			var ck: Dictionary = c["check"]
			var cid := _check_id(c, i)
			if st.checks.has(cid) and not bool(ck.get("retry", false)):
				continue
			var actor := check_actor(ck)
			var who := String(ck.get("who", "player"))
			if actor == null or (who != "player" and not st.party.has(who)):
				if who != "player":
					continue
				enabled = false
				reason = "Unavailable"
			else:
				var bonus := int(ck.get("bonus", 0)) + _situational_bonus(ck)
				var sk := String(ck.get("skill", "persuasion"))
				var total := actor.skill_total(sk) + bonus
				var dc := int(ck.get("dc", 10))
				var chance := clampi((21 - (dc - total)) * 5, 0, 100)
				check_info = {"skill": sk, "dc": dc, "who": who, "who_name": actor.display_name, "bonus": total, "chance": chance}
				var skill_name := String(DB.skill(sk).get("name", sk))
				if who == "player":
					tag = "%s%s %d" % ["" if tag == "" else tag + " · ", skill_name, dc]
				else:
					tag = "%s%s – %s %d" % ["" if tag == "" else tag + " · ", actor.display_name, skill_name, dc]
				if ck.has("power"):
					var pid := String(ck["power"])
					var cost := int(ck.get("energy", DB.power(pid).get("cost", 3)))
					tag = "Resonance: %s · %s" % [DB.power(pid).get("name", pid), tag]
					if not actor.powers.has(pid):
						enabled = false
						reason = "Requires the %s power" % DB.power(pid).get("name", pid)
					elif actor.energy < cost:
						enabled = false
						reason = "Needs %d energy" % cost
					check_info["energy"] = cost
		out.append({"index": i, "text": label, "tag": tag, "enabled": enabled, "reason": reason, "check": check_info,
			"tone": String(c.get("tone", "")), "companion": String(c.get("companion", ""))})
	return out


func _situational_bonus(ck: Dictionary) -> int:
	var b := 0
	for sb in DB.arr(ck, "bonus_if"):
		if Conditions.eval_all(sb.get("if", []), st, ctx):
			b += int(sb.get("bonus", 0))
	if ck.has("power"):
		b += int(ck.get("power_bonus", 5))
	return b


func choose(index: int) -> Dictionary:
	var raw: Array = DB.arr(node, "choices")
	if index < 0 or index >= raw.size():
		return {"ok": false}
	var vis := choices()
	var found := false
	for v in vis:
		if int(v["index"]) == index and bool(v["enabled"]):
			found = true
	if not found:
		return {"ok": false, "reason": "Choice unavailable."}
	var c: Dictionary = raw[index]
	st.add_history(speaker_name("player"), Game.fmt(String(c.get("text", ""))), dialogue_id)
	last_check = {}
	pending_log.append_array(Effects.apply_all(c.get("effects", []), st, ctx))
	var nxt := String(c.get("next", ""))
	if c.has("check"):
		var ck: Dictionary = c["check"]
		var cid := _check_id(c, index)
		var actor := check_actor(ck)
		if ck.has("power"):
			var cost := int(ck.get("energy", DB.power(String(ck["power"])).get("cost", 3)))
			actor.energy = maxi(0, actor.energy - cost)
			pending_log.append("%s spends %d energy" % [actor.display_name, cost])
		var res := CombatRules.skill_check(actor, String(ck.get("skill", "persuasion")), int(ck.get("dc", 10)), st.dice, int(ck.get("bonus", 0)) + _situational_bonus(ck))
		res["id"] = cid
		st.checks[cid] = res
		last_check = res
		st.stats["checks_passed" if res["success"] else "checks_failed"] = int(st.stats.get("checks_passed" if res["success"] else "checks_failed", 0)) + 1
		var line := "%s check (%s): d20 %d %s = %d vs DC %d — %s" % [DB.skill(String(res["skill"])).get("name", res["skill"]), res["actor_name"], res["natural"], Rules.signed(int(res["bonus"])), res["total"], res["dc"], "SUCCESS" if res["success"] else "FAILURE"]
		st.add_history("", line, dialogue_id)
		pending_log.append(line)
		Events.post("skill_check", res)
		if res["success"]:
			pending_log.append_array(Effects.apply_all(c.get("success_effects", []), st, ctx))
			nxt = String(c.get("success", nxt))
		else:
			pending_log.append_array(Effects.apply_all(c.get("failure_effects", []), st, ctx))
			nxt = String(c.get("failure", nxt))
	if bool(c.get("end", false)) or nxt == "" or nxt == "end":
		finish()
		return {"ok": true, "ended": true, "check": last_check}
	_enter(nxt)
	return {"ok": true, "ended": not active, "check": last_check}


func advance() -> void:
	if not active:
		return
	var nxt := String(node.get("next", ""))
	if nxt == "" or bool(node.get("end", false)):
		finish()
		return
	_enter(nxt)


## Skips to the end of a non-interactive run of nodes, applying their effects.
func skip_lines() -> void:
	var guard := 0
	while active and choices().is_empty() and guard < 64:
		guard += 1
		advance()
