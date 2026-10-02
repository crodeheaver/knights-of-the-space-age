class_name Crafting
extends RefCounted
## Workbench / medical station crafting, dismantling and weapon/armor upgrades.
## Every operation is an atomic Inventory.Tx. Recipe outputs are never worth
## dismantling for more than their inputs (validated in tests).


static func recipes_for(station: String) -> Array[String]:
	var out: Array[String] = []
	for r in DB.recipes.keys():
		if String(DB.recipes[r].get("station", "")) == station:
			out.append(String(r))
	out.sort()
	return out


static func preview(recipe_id: String, crafter: CharacterSheet, st: GameState) -> Dictionary:
	var r: Dictionary = DB.recipes.get(recipe_id, {})
	var res := {"ok": true, "reasons": [], "inputs": [], "output": r.get("output", {})}
	if r.is_empty():
		return {"ok": false, "reasons": ["Unknown recipe."], "inputs": [], "output": {}}
	if r.has("requires_flag") and not st.has_flag(String(r["requires_flag"])):
		res["ok"] = false
		res["reasons"].append("Recipe not known yet.")
	var sk := String(r.get("skill", ""))
	var need := int(r.get("min", 0))
	var have := crafter.skill_total(sk) if sk != "" else 0
	res["skill"] = sk
	res["skill_need"] = need
	res["skill_have"] = have
	if have < need:
		res["ok"] = false
		res["reasons"].append("%s needs %s %d (has %d)." % [crafter.display_name, DB.skill(sk).get("name", sk), need, have])
	var inputs: Dictionary = r.get("inputs", {})
	for id in inputs.keys():
		var n := int(inputs[id])
		var h := st.inventory.count(String(id))
		res["inputs"].append({"id": id, "need": n, "have": h})
		if h < n:
			res["ok"] = false
			res["reasons"].append("Need %d %s (have %d)." % [n, DB.item_name(String(id)), h])
	return res


static func craft(recipe_id: String, crafter: CharacterSheet, st: GameState) -> Dictionary:
	var pv := preview(recipe_id, crafter, st)
	if not bool(pv["ok"]):
		return {"ok": false, "reason": " ".join(PackedStringArray(pv["reasons"]))}
	var r: Dictionary = DB.recipes[recipe_id]
	var tx := st.inventory.tx()
	var inputs: Dictionary = r.get("inputs", {})
	for id in inputs.keys():
		tx.remove_items(String(id), int(inputs[id]))
	var outp: Dictionary = r.get("output", {})
	for id in outp.keys():
		tx.add_items(String(id), int(outp[id]))
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	Events.post("crafted", {"recipe": recipe_id, "by": crafter.uid})
	return {"ok": true, "reason": ""}


static func can_dismantle(st: GameState, item_id: String, inst_uid: String = "") -> String:
	var it: Dictionary = DB.item(item_id)
	if bool(it.get("quest", false)):
		return "Quest items cannot be dismantled."
	if bool(it.get("bound", false)):
		return "%s is bound to you." % it.get("name", item_id)
	if not it.has("dismantle"):
		return "%s cannot be broken down." % it.get("name", item_id)
	if inst_uid != "":
		if st.inventory.find_instance(inst_uid).is_empty():
			return "Unequip it first."
	elif st.inventory.stack_count(item_id) <= 0:
		return "None left."
	return ""


static func dismantle(st: GameState, item_id: String, inst_uid: String = "") -> Dictionary:
	var reason := can_dismantle(st, item_id, inst_uid)
	if reason != "":
		return {"ok": false, "reason": reason}
	var it: Dictionary = DB.item(item_id)
	var tx := st.inventory.tx()
	if inst_uid != "":
		tx.remove_instance(inst_uid)
		var inst := st.inventory.find_instance(inst_uid)
		for up in inst.get("upgrades", []):
			tx.add_items(String(up), 1)
	else:
		tx.remove_items(item_id, 1)
	var y: Dictionary = it["dismantle"]
	for id in y.keys():
		tx.add_items(String(id), int(y[id]))
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	Events.post("dismantled", {"item": item_id})
	return {"ok": true, "reason": "", "yield": y}


# ------------------------------------------------------------ upgrades
static func upgrade_applies(upgrade_id: String, target_item_id: String) -> bool:
	var ud: Dictionary = DB.dict(DB.item(upgrade_id), "upgrade")
	var applies: Array = ud.get("applies_to", [])
	var tgt: Dictionary = DB.item(target_item_id)
	var t := String(tgt.get("type", ""))
	if t == "armor":
		return applies.has("armor")
	if t == "weapon":
		var w: Dictionary = tgt.get("weapon", {})
		if bool(w.get("energy_blade", false)) and applies.has("energy_blade"):
			return true
		return applies.has(String(w.get("category", "")))
	return false


## Finds an instance by uid in the inventory or any party member's equipment.
static func locate(st: GameState, uid: String) -> Dictionary:
	var inst := st.inventory.find_instance(uid)
	if not inst.is_empty():
		return {"inst": inst, "owner": null, "slot": ""}
	for cid in st.characters.keys():
		var s: CharacterSheet = st.characters[cid]
		for slot in s.equipment.keys():
			var e: Variant = s.equipment[slot]
			if e != null and e["uid"] == uid:
				return {"inst": e, "owner": s, "slot": slot}
	return {}


static func install(st: GameState, upgrade_id: String, target_uid: String) -> Dictionary:
	var loc := locate(st, target_uid)
	if loc.is_empty():
		return {"ok": false, "reason": "Item not found."}
	var inst: Dictionary = loc["inst"]
	if not upgrade_applies(upgrade_id, String(inst["id"])):
		return {"ok": false, "reason": "%s does not fit %s." % [DB.item_name(upgrade_id), DB.item_name(String(inst["id"]))]}
	var ups: Array = inst.get("upgrades", [])
	if ups.size() >= ItemInst.upgrade_slots(inst):
		return {"ok": false, "reason": "No free upgrade slots."}
	var tx := st.inventory.tx()
	tx.remove_items(upgrade_id, 1)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	ups.append(upgrade_id)
	inst["upgrades"] = ups
	if loc["owner"] != null:
		(loc["owner"] as CharacterSheet).mark_dirty()
	Events.post("upgrade_installed", {"item": inst["uid"], "upgrade": upgrade_id})
	return {"ok": true, "reason": ""}


static func remove_upgrade(st: GameState, target_uid: String, upgrade_id: String) -> Dictionary:
	var loc := locate(st, target_uid)
	if loc.is_empty():
		return {"ok": false, "reason": "Item not found."}
	var inst: Dictionary = loc["inst"]
	var ups: Array = inst.get("upgrades", [])
	if not ups.has(upgrade_id):
		return {"ok": false, "reason": "Upgrade not installed."}
	var tx := st.inventory.tx()
	tx.add_items(upgrade_id, 1)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	ups.erase(upgrade_id)
	inst["upgrades"] = ups
	if loc["owner"] != null:
		(loc["owner"] as CharacterSheet).mark_dirty()
	Events.post("upgrade_removed", {"item": inst["uid"], "upgrade": upgrade_id})
	return {"ok": true, "reason": ""}
