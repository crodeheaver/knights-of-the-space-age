class_name EquipmentRules
extends RefCounted
## Equip/unequip validation and atomic moves between the shared inventory and a
## character's slots, plus stat comparison previews.

const WEAPON_SLOTS: Array[String] = ["main", "off", "main2", "off2"]


static func main_of(slot: String) -> String:
	return "main" if slot in ["main", "off"] else "main2"


static func off_of(slot: String) -> String:
	return "off" if slot in ["main", "off"] else "off2"


static func can_equip(sheet: CharacterSheet, item_id: String, slot: String) -> String:
	var it: Dictionary = DB.item(item_id)
	if it.is_empty():
		return "Unknown item."
	if bool(it.get("natural", false)) or bool(it.get("implicit", false)):
		return "That cannot be equipped."
	var t := String(it.get("type", ""))
	if t == "weapon":
		if not WEAPON_SLOTS.has(slot):
			return "Weapons go in a weapon slot."
	elif t == "armor" or t == "gear":
		if String(it.get("slot", "")) != slot:
			return "%s goes in the %s slot." % [it["name"], sheet.slot_name(String(it.get("slot", "")))]
	else:
		return "%s is not equipment." % it.get("name", item_id)
	var req: Dictionary = it.get("req", {})
	if req.has("kind") and String(req["kind"]) != sheet.kind:
		return "%s only fits %s characters." % [it["name"], "synthetic" if req["kind"] == "machine" else "organic"]
	var attrs: Dictionary = req.get("attrs", {})
	for a in attrs.keys():
		if sheet.attr_perm(String(a)) < int(attrs[a]):
			return "Requires %s %d (have %d)." % [Rules.ATTR_NAMES[a], int(attrs[a]), sheet.attr_perm(String(a))]
	if req.has("armor_prof"):
		if not (sheet.passive().get("armor_prof", []) as Array).has(String(req["armor_prof"])):
			return "Requires %s Armor Proficiency." % String(req["armor_prof"]).capitalize()
	if req.has("implant_tier"):
		if int(sheet.passive().get("implant_tier", 0)) < int(req["implant_tier"]):
			return "Requires %s." % ("Implant Tolerance" if int(req["implant_tier"]) == 1 else "Advanced Implant Tolerance")
	for f in req.get("feats", []):
		if not sheet.feats.has(String(f)):
			return "Requires the %s feat." % DB.feat(String(f)).get("name", f)
	if t == "weapon":
		var w: Dictionary = it["weapon"]
		if slot in ["off", "off2"]:
			if int(w.get("hands", 1)) == 2:
				return "Two-handed weapons go in the main hand."
			var main: Variant = sheet.equipment.get(main_of(slot), null)
			if main == null:
				return "Equip a main-hand weapon first."
			var mw: Dictionary = DB.dict(DB.item(String(main["id"])), "weapon")
			if int(mw.get("hands", 1)) == 2:
				return "The main-hand weapon needs both hands."
			var fam_main := "melee" if String(mw.get("category", "")) == "melee" else String(mw.get("category", ""))
			var fam_off := String(w.get("category", ""))
			if fam_main != fam_off or fam_off == "rifle":
				return "Off-hand weapon must match the main hand (two melee weapons or two pistols)."
	return ""


## Moves an inventory instance into a slot. Atomic: either everything moves or
## nothing does.
static func equip(sheet: CharacterSheet, inv: Inventory, uid: String, slot: String) -> Dictionary:
	var inst := inv.find_instance(uid)
	if inst.is_empty():
		return {"ok": false, "reason": "Item not found."}
	var reason := can_equip(sheet, String(inst["id"]), slot)
	if reason != "":
		return {"ok": false, "reason": reason}
	var tx := inv.tx()
	tx.remove_instance(uid)
	var old: Variant = sheet.equipment.get(slot, null)
	if old != null:
		tx.add_instance(old)
	var clear_off := ""
	var w: Dictionary = DB.dict(DB.item(String(inst["id"])), "weapon")
	if slot in ["main", "main2"] and int(w.get("hands", 1)) == 2:
		var off: Variant = sheet.equipment.get(off_of(slot), null)
		if off != null:
			tx.add_instance(off)
			clear_off = off_of(slot)
	if slot in ["main", "main2"] and clear_off == "":
		# A one-handed main swap may invalidate the current off-hand pairing.
		var off2: Variant = sheet.equipment.get(off_of(slot), null)
		if off2 != null:
			var ow: Dictionary = DB.dict(DB.item(String(off2["id"])), "weapon")
			var famm := String(w.get("category", ""))
			if famm != String(ow.get("category", "")):
				tx.add_instance(off2)
				clear_off = off_of(slot)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	sheet.set_slot(slot, inst)
	if clear_off != "":
		sheet.set_slot(clear_off, null)
	_clamp_resources(sheet)
	Events.post("equipment_changed", {"uid": sheet.uid, "slot": slot, "item": inst["id"]})
	return {"ok": true, "reason": ""}


static func unequip(sheet: CharacterSheet, inv: Inventory, slot: String) -> Dictionary:
	var cur: Variant = sheet.equipment.get(slot, null)
	if cur == null:
		return {"ok": false, "reason": "Slot is empty."}
	var tx := inv.tx()
	tx.add_instance(cur)
	var off_clear := ""
	if slot in ["main", "main2"] and sheet.equipment.get(off_of(slot), null) != null:
		tx.add_instance(sheet.equipment[off_of(slot)])
		off_clear = off_of(slot)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	sheet.set_slot(slot, null)
	if off_clear != "":
		sheet.set_slot(off_clear, null)
	_clamp_resources(sheet)
	Events.post("equipment_changed", {"uid": sheet.uid, "slot": slot, "item": ""})
	return {"ok": true, "reason": ""}


static func _clamp_resources(sheet: CharacterSheet) -> void:
	sheet.hp = mini(sheet.hp, sheet.max_hp())
	sheet.energy = mini(sheet.energy, sheet.max_energy())


## Stat snapshot used for equipment comparisons and the character sheet.
static func snapshot(sheet: CharacterSheet) -> Dictionary:
	var prof := CombatRules.weapon_profile(sheet, "main")
	var atk := CombatRules.sum_parts(CombatRules.attack_parts(sheet, prof))
	var dmg := Rules.dice_avg(String(prof["dice"])) + int(prof["damage"])
	if not bool(prof["ranged"]):
		dmg += sheet.amod("str")
	var snap := {"Defense": sheet.defense(), "Attack": atk, "Avg damage": snappedf(dmg, 0.1), "Max health": sheet.max_hp(), "Max energy": sheet.max_energy(),
		"Fortitude": sheet.save_total("fort"), "Reflex": sheet.save_total("ref"), "Will": sheet.save_total("will")}
	for s in DB.skill_ids():
		snap[String(DB.skill(s).get("name", s))] = sheet.skill_total(s)
	for a in Rules.ATTRS:
		snap[String(a).to_upper()] = sheet.attr(a)
	return snap


## Preview of stat changes if `item_id` were equipped in `slot`. Weapon-set
## slots are compared with that set active.
static func compare(sheet: CharacterSheet, item_id: String, slot: String) -> Dictionary:
	var base := CharacterSheet.from_dict(sheet.to_dict())
	if slot in ["main2", "off2"]:
		base.active_set = 1
	elif slot in ["main", "off"]:
		base.active_set = 0
	base.mark_dirty()
	var before := snapshot(base)
	var tmp := CharacterSheet.from_dict(base.to_dict())
	if slot in ["main", "main2"]:
		var w: Dictionary = DB.dict(DB.item(item_id), "weapon")
		if int(w.get("hands", 1)) == 2:
			tmp.set_slot(off_of(slot), null)
	tmp.set_slot(slot, {"uid": "preview", "id": item_id, "upgrades": []})
	var after := snapshot(tmp)
	var delta := {}
	for k in after.keys():
		var dv: float = float(after[k]) - float(before.get(k, 0))
		if absf(dv) > 0.001:
			delta[k] = dv
	return {"before": before, "after": after, "delta": delta, "reason": can_equip(sheet, item_id, slot)}
