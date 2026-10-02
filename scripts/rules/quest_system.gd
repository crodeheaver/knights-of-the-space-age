class_name QuestSystem
extends RefCounted
## Explicit quest state machine: inactive -> active -> completed | failed.
## Stages (within active) and objective states are changed by effects or by
## event-driven transitions declared in quests.json. Illegal transitions (for
## example completing a failed quest) are ignored and reported.

const STATES := ["inactive", "active", "completed", "failed"]
const LEGAL := {"inactive": ["active", "completed", "failed"], "active": ["completed", "failed"], "completed": [], "failed": []}


static func ensure(st: GameState, qid: String) -> Dictionary:
	if not st.quests.has(qid):
		st.quests[qid] = {"state": "inactive", "stage": "", "objectives": {}, "log": [], "outcome": ""}
	return st.quests[qid]


static func state_of(st: GameState, qid: String) -> String:
	return String(DB.dict(st.quests, qid).get("state", "inactive"))


static func set_state(st: GameState, qid: String, new_state: String, note: String = "") -> bool:
	var q := ensure(st, qid)
	var cur := String(q["state"])
	if cur == new_state:
		return false
	if not (LEGAL.get(cur, []) as Array).has(new_state):
		push_warning("Quest %s: illegal transition %s -> %s" % [qid, cur, new_state])
		return false
	q["state"] = new_state
	var qd: Dictionary = DB.quests.get(qid, {})
	if new_state == "active" and String(q["stage"]) == "" and qd.has("start"):
		set_stage(st, qid, String(qd["start"]))
	if new_state == "completed":
		for o in (q["objectives"] as Dictionary).keys():
			if q["objectives"][o] == "active" and not bool(DB.dict(DB.dict(qd, "objectives"), String(o)).get("optional", false)):
				q["objectives"][o] = "completed"
		var xp := int(qd.get("complete_xp", 0))
		if xp > 0:
			st.grant_xp(xp, "quest_complete:" + qid, "Completed " + String(qd.get("name", qid)))
	if new_state == "failed":
		for o in (q["objectives"] as Dictionary).keys():
			if q["objectives"][o] == "active":
				q["objectives"][o] = "failed"
	(q["log"] as Array).append({"t": snappedf(st.play_time, 0.1), "text": note if note != "" else "Quest %s." % new_state})
	Events.post("quest_updated", {"quest": qid, "state": new_state})
	Events.toast("%s: %s" % [String(qd.get("name", qid)), {"active": "New quest", "completed": "Completed", "failed": "Failed"}.get(new_state, new_state)], "quest")
	return true


static func set_stage(st: GameState, qid: String, stage: String) -> bool:
	var q := ensure(st, qid)
	if String(q["state"]) == "inactive":
		q["state"] = "active"
		Events.toast("New quest: %s" % DB.quests.get(qid, {}).get("name", qid), "quest")
	if String(q["state"]) != "active":
		return false
	if String(q["stage"]) == stage:
		return false
	var qd: Dictionary = DB.quests.get(qid, {})
	var sd: Dictionary = DB.dict(DB.dict(qd, "stages"), stage)
	if sd.is_empty():
		push_warning("Quest %s: unknown stage %s" % [qid, stage])
		return false
	# Required objectives of the previous stage are implicitly done.
	var prev := String(q["stage"])
	if prev != "":
		for o in DB.arr(DB.dict(DB.dict(qd, "stages"), prev), "objectives"):
			var od: Dictionary = DB.dict(DB.dict(qd, "objectives"), String(o))
			if String(q["objectives"].get(o, "")) == "active" and not bool(od.get("optional", false)):
				q["objectives"][o] = "completed"
	q["stage"] = stage
	for o in DB.arr(sd, "objectives"):
		if not (q["objectives"] as Dictionary).has(o):
			q["objectives"][o] = "active"
	(q["log"] as Array).append({"t": snappedf(st.play_time, 0.1), "text": String(sd.get("text", stage))})
	if int(sd.get("xp", 0)) > 0:
		st.grant_xp(int(sd["xp"]), "quest_stage:%s:%s" % [qid, stage], String(sd.get("title", stage)))
	Events.post("quest_updated", {"quest": qid, "stage": stage})
	return true


static func set_objective(st: GameState, qid: String, obj: String, state: String) -> bool:
	var q := ensure(st, qid)
	var cur := String(q["objectives"].get(obj, "inactive"))
	if cur == state or cur == "completed" or cur == "failed":
		return false
	if String(q["state"]) == "inactive" and state == "active":
		set_state(st, qid, "active")
	q["objectives"][obj] = state
	var od: Dictionary = DB.dict(DB.dict(DB.quests.get(qid, {}), "objectives"), obj)
	if state == "completed" and int(od.get("xp", 0)) > 0:
		st.grant_xp(int(od["xp"]), "quest_obj:%s:%s" % [qid, obj], String(od.get("text", obj)))
	Events.post("quest_updated", {"quest": qid, "objective": obj, "state": state})
	return true


## Effect entry point: {"quest": id, "stage"|"state"|"objective"+"value", "outcome"}
static func apply(st: GameState, qid: String, e: Dictionary) -> void:
	if e.has("stage"):
		set_stage(st, qid, String(e["stage"]))
	if e.has("objective"):
		set_objective(st, qid, String(e["objective"]), String(e.get("value", e.get("state", "completed"))))
	elif e.has("state"):
		set_state(st, qid, String(e["state"]), String(e.get("reason", "")))
	if e.has("resolution"):
		ensure(st, qid)["outcome"] = String(e["resolution"])


static func start_auto(st: GameState) -> void:
	for qid in DB.quests.keys():
		if bool(DB.quests[qid].get("auto_start", false)) and state_of(st, String(qid)) == "inactive":
			set_state(st, String(qid), "active")


## Event-driven transitions.
static func on_event(st: GameState, name: String, data: Dictionary) -> void:
	for qid in DB.quests.keys():
		var qd: Dictionary = DB.quests[qid]
		for tr in DB.arr(qd, "transitions"):
			if String(tr.get("event", "")) != name:
				continue
			var m: Dictionary = tr.get("match", {})
			var ok := true
			for k in m.keys():
				if not data.has(k) or str(data[k]) != str(m[k]):
					ok = false
					break
			if not ok:
				continue
			var q := ensure(st, String(qid))
			if tr.has("from"):
				var from_list: Array = tr["from"]
				if not from_list.has(q["stage"]):
					continue
			if tr.has("from_state") and String(q["state"]) != String(tr["from_state"]):
				continue
			if tr.has("if") and not Conditions.eval_all(tr["if"], st):
				continue
			apply(st, String(qid), tr)


static func active_objectives(st: GameState, qid: String) -> Array:
	var out: Array = []
	var q: Dictionary = DB.dict(st.quests, qid)
	var qd: Dictionary = DB.quests.get(qid, {})
	for o in DB.dict(q, "objectives").keys():
		var od: Dictionary = DB.dict(DB.dict(qd, "objectives"), String(o))
		out.append({"id": o, "state": q["objectives"][o], "text": Game.fmt(String(od.get("text", o))), "optional": bool(od.get("optional", false))})
	return out
