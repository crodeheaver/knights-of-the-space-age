class_name StatusRules
extends RefCounted
## Status-effect application, stacking, expiry and damage-break rules.
##
## Stacking (documented in docs/RULES.md):
##  * Same id already present: refresh. remaining = max(old, new), mods and
##    absorb pool are replaced by the new application.
##  * Different id in the same group: the new effect replaces the old one only
##    if its priority >= the old one's priority; otherwise it is rejected.
##  * Immunity: status.immune_kinds vs creature kind, status.immune_tag vs the
##    bearer's immunities (gear, feats, other statuses).
## Durations are simulation seconds and only tick while the sim runs.


static func apply(sheet: CharacterSheet, status_id: String, duration: float, source: String = "", opts: Dictionary = {}) -> Dictionary:
	var def: Dictionary = DB.status(status_id)
	if def.is_empty():
		return {"applied": false, "reason": "unknown"}
	if sheet.dead:
		return {"applied": false, "reason": "dead"}
	if status_id != "downed" and sheet.is_downed():
		return {"applied": false, "reason": "downed"}
	if DB.arr(def, "immune_kinds").has(sheet.kind):
		return {"applied": false, "reason": "immune"}
	var tag := String(def.get("immune_tag", ""))
	if tag != "" and sheet.immunities().has(tag):
		return {"applied": false, "reason": "immune"}
	var group := String(def.get("group", status_id))
	var prio := int(def.get("priority", 1))
	var inst := {"id": status_id, "remaining": duration, "source": source}
	if opts.has("mods"):
		inst["mods"] = opts["mods"]
	if def.has("absorb"):
		inst["absorb_left"] = int(DB.dict(def, "absorb").get("amount", 0))
	# same id -> refresh
	for i in sheet.statuses.size():
		var s: Dictionary = sheet.statuses[i]
		if s["id"] == status_id:
			inst["remaining"] = maxf(float(s["remaining"]), duration)
			sheet.statuses[i] = inst
			sheet.mark_dirty()
			return {"applied": true, "reason": "refreshed", "status": inst}
	# same group -> priority rule
	for i in sheet.statuses.size():
		var s: Dictionary = sheet.statuses[i]
		var sdef: Dictionary = DB.status(String(s["id"]))
		if String(sdef.get("group", s["id"])) == group:
			if prio >= int(sdef.get("priority", 1)):
				sheet.statuses[i] = inst
				sheet.mark_dirty()
				return {"applied": true, "reason": "replaced", "replaced": s["id"], "status": inst}
			return {"applied": false, "reason": "weaker"}
	sheet.statuses.append(inst)
	sheet.mark_dirty()
	return {"applied": true, "reason": "new", "status": inst}


static func remove(sheet: CharacterSheet, status_id: String) -> bool:
	for i in sheet.statuses.size():
		if sheet.statuses[i]["id"] == status_id:
			sheet.statuses.remove_at(i)
			sheet.mark_dirty()
			return true
	return false


## Removes statuses whose id or kind matches any entry in `what`.
static func cleanse(sheet: CharacterSheet, what: Array) -> Array[String]:
	var removed: Array[String] = []
	for i in range(sheet.statuses.size() - 1, -1, -1):
		var s: Dictionary = sheet.statuses[i]
		var def: Dictionary = DB.status(String(s["id"]))
		if what.has(s["id"]) or what.has(String(def.get("kind", ""))):
			removed.append(String(s["id"]))
			sheet.statuses.remove_at(i)
	if not removed.is_empty():
		sheet.mark_dirty()
	return removed


## Advances durations. Returns ids that expired.
static func tick(sheet: CharacterSheet, dt: float) -> Array[String]:
	var expired: Array[String] = []
	for i in range(sheet.statuses.size() - 1, -1, -1):
		var s: Dictionary = sheet.statuses[i]
		if s["id"] == "downed":
			continue
		s["remaining"] = float(s["remaining"]) - dt
		if float(s["remaining"]) <= 0.0001:
			expired.append(String(s["id"]))
			sheet.statuses.remove_at(i)
	for k in sheet.cooldowns.keys():
		sheet.cooldowns[k] = float(sheet.cooldowns[k]) - dt
		if float(sheet.cooldowns[k]) <= 0.0:
			sheet.cooldowns.erase(k)
	if not expired.is_empty():
		sheet.mark_dirty()
	return expired


## Called when the bearer takes damage. Removes break_on_damage effects.
static func on_damaged(sheet: CharacterSheet) -> Array[String]:
	var removed: Array[String] = []
	for i in range(sheet.statuses.size() - 1, -1, -1):
		var s: Dictionary = sheet.statuses[i]
		if bool(DB.status(String(s["id"])).get("break_on_damage", false)):
			removed.append(String(s["id"]))
			sheet.statuses.remove_at(i)
	if not removed.is_empty():
		sheet.mark_dirty()
	return removed


## Damage-over-time for one round boundary. Returns [{id, rolled, dtype}].
static func dot_rolls(sheet: CharacterSheet, dice: Dice) -> Array:
	var out: Array = []
	for s in sheet.statuses:
		var def: Dictionary = DB.status(String(s["id"]))
		if def.has("dot"):
			var dot: Dictionary = def["dot"]
			var r := dice.roll_expr(String(dot.get("dice", "1d4")))
			out.append({"id": s["id"], "rolled": int(r["total"]), "dtype": String(dot.get("type", "kinetic"))})
	return out


static func interrupts(status_id: String) -> bool:
	return bool(DB.status(status_id).get("interrupt", false))


static func clears_queue(status_id: String) -> bool:
	return bool(DB.status(status_id).get("clear_queue", false))


static func symbol(status_id: String) -> String:
	return String(DB.status(status_id).get("symbol", status_id.substr(0, 3).to_upper()))
