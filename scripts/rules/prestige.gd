class_name Prestige
extends RefCounted
## Prestige specializations (later-game system, demonstrated through developer
## presets). Families and alignment variants are data in prestige.json; this
## class evaluates eligibility and exposes each variant's feature to the rules.


static func data() -> Dictionary:
	return DB.prestige


static func variant(id: String) -> Dictionary:
	return DB.dict(DB.dict(data(), "variants"), id) if id != "" else {}


static func family(id: String) -> Dictionary:
	return DB.dict(DB.dict(data(), "families"), id)


static func eligibility_errors(sheet: CharacterSheet, variant_id: String, alignment: int) -> Array[String]:
	var errs: Array[String] = []
	var v := variant(variant_id)
	if v.is_empty():
		return ["Unknown specialization."]
	if sheet.prestige != "":
		errs.append("Already specialized as %s." % variant(sheet.prestige).get("name", sheet.prestige))
	if not sheet.is_player:
		errs.append("Only the protagonist can specialize in this build.")
	var minl := int(data().get("min_level", 6))
	if sheet.level < minl:
		errs.append("Requires level %d." % minl)
	var req: Dictionary = DB.dict(family(String(v["family"])), "requires")
	if req.has("bab") and sheet.bab() < int(req["bab"]):
		errs.append("Requires base attack +%d." % int(req["bab"]))
	var anyf: Array = req.get("any_feats", [])
	if not anyf.is_empty():
		var ok := false
		for f in anyf:
			if sheet.feats.has(String(f)):
				ok = true
		if not ok:
			errs.append("Requires a martial technique feat (Power Strike, Flurry, Dueling, Two-Weapon Fighting or Critical Strike).")
	if req.has("min_powers") and sheet.powers.size() < int(req["min_powers"]):
		errs.append("Requires %d known powers." % int(req["min_powers"]))
	var attrs: Dictionary = req.get("attrs", {})
	for a in attrs.keys():
		if sheet.attr_perm(String(a)) < int(attrs[a]):
			errs.append("Requires %s %d." % [Rules.ATTR_NAMES[a], int(attrs[a])])
	var sk: Dictionary = req.get("skills", {})
	for s in sk.keys():
		if sheet.skill_rank(String(s)) < int(sk[s]):
			errs.append("Requires %d ranks of %s." % [int(sk[s]), DB.skill(String(s)).get("name", s)])
	var anys: Dictionary = req.get("any_skills", {})
	if not anys.is_empty():
		var ok2 := false
		for s in anys.keys():
			if sheet.skill_rank(String(s)) >= int(anys[s]):
				ok2 = true
		if not ok2:
			var names: PackedStringArray = []
			for s in anys.keys():
				names.append("%d %s" % [int(anys[s]), DB.skill(String(s)).get("name", s)])
			errs.append("Requires one of: %s ranks." % ", ".join(names))
	if v.has("alignment_min") and alignment < int(v["alignment_min"]):
		errs.append("Requires Mercy %d or higher (current %d)." % [int(v["alignment_min"]), alignment])
	if v.has("alignment_max") and alignment > int(v["alignment_max"]):
		errs.append("Requires Dominion %d or lower (current %d)." % [int(v["alignment_max"]), alignment])
	return errs


static func eligible_variants(sheet: CharacterSheet, alignment: int) -> Array[String]:
	var out: Array[String] = []
	for vid in DB.dict(data(), "variants").keys():
		if eligibility_errors(sheet, String(vid), alignment).is_empty():
			out.append(String(vid))
	return out


static func adopt(sheet: CharacterSheet, variant_id: String, alignment: int) -> Dictionary:
	var errs := eligibility_errors(sheet, variant_id, alignment)
	if not errs.is_empty():
		return {"ok": false, "errors": errs}
	sheet.prestige = variant_id
	sheet.mark_dirty()
	Events.post("prestige_adopted", {"uid": sheet.uid, "variant": variant_id})
	return {"ok": true, "errors": []}


# ------------------------------------------------------------ features
static func power_cost_mod(variant_id: String, school: String) -> int:
	return int(DB.dict(variant(variant_id), "power_cost").get(school, 0))


static func dc_bonus(sheet: CharacterSheet, school: String) -> int:
	return int(DB.dict(variant(sheet.prestige), "dc_bonus").get(school, 0))


static func heal_mult(sheet: CharacterSheet) -> float:
	return float(variant(sheet.prestige).get("heal_mult", 1.0))


static func sneak_bonus(sheet: CharacterSheet) -> int:
	return int(variant(sheet.prestige).get("sneak_bonus", 0))


static func detection_mult(sheet: CharacterSheet) -> float:
	return float(variant(sheet.prestige).get("detection_mult", 1.0))


static func crit_status(sheet: CharacterSheet) -> Dictionary:
	return DB.dict(variant(sheet.prestige), "crit_status")


static func chain_bonus(sheet: CharacterSheet) -> int:
	return int(variant(sheet.prestige).get("chain_bonus", 0))


static func aura(sheet: CharacterSheet) -> Dictionary:
	return DB.dict(variant(sheet.prestige), "aura")


## Applies an aura to the given allies (world supplies those within radius).
static func apply_aura(bearer: CharacterSheet, allies: Array) -> int:
	var a := aura(bearer)
	if a.is_empty():
		return 0
	var n := 0
	for s in allies:
		var sh: CharacterSheet = s
		if sh.is_downed():
			continue
		if bool(StatusRules.apply(sh, String(a["status"]), float(a.get("duration", 3.5)), bearer.uid)["applied"]):
			n += 1
	return n
