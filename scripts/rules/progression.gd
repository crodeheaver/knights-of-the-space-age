class_name Progression
extends RefCounted
## Level-up rules driven entirely by progression.json and classes.json.
## Both the manual level-up screen and the "Recommended" button go through
## apply_level_up(), which validates every choice with BuildValidator.


static func preview(sheet: CharacterSheet) -> Dictionary:
	var nl := sheet.level + 1
	var tmp := CharacterSheet.from_dict(sheet.to_dict())
	tmp.level = nl
	tmp.mark_dirty()
	var sp := BuildValidator.skill_points_for_level(sheet.class_id, sheet.attr_perm("int"), nl) + sheet.skill_bank
	return {
		"level": nl,
		"hp_gain": tmp.max_hp() - sheet.max_hp(),
		"energy_gain": tmp.max_energy() - sheet.max_energy(),
		"skill_points": sp,
		"feat_picks": BuildValidator.feat_picks(sheet.class_id, nl),
		"power_picks": BuildValidator.power_picks(sheet.class_id, nl) if sheet.has_resonance() else 0,
		"attr_increase": DB.int_arr(DB.progression.get("attribute_increase_levels", [])).has(nl),
		"class_features": BuildValidator.class_features(sheet.class_id, nl),
		"bab": tmp.bab() - sheet.bab(),
	}


## A sheet already at the new level, used to evaluate prerequisites.
static func staged_sheet(sheet: CharacterSheet, choices: Dictionary) -> CharacterSheet:
	var tmp := CharacterSheet.from_dict(sheet.to_dict())
	tmp.level = sheet.level + 1
	var a := String(choices.get("attr", ""))
	if a != "":
		tmp.attr_increases[a] = int(tmp.attr_increases.get(a, 0)) + 1
	for f in BuildValidator.class_features(sheet.class_id, tmp.level):
		if not tmp.feats.has(f):
			tmp.feats.append(f)
	tmp.mark_dirty()
	return tmp


static func validate(sheet: CharacterSheet, choices: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	if sheet.levels_available() <= 0:
		errs.append("Not enough experience to level up.")
		return errs
	var pv := preview(sheet)
	var a := String(choices.get("attr", ""))
	if bool(pv["attr_increase"]):
		if not Rules.ATTRS.has(a):
			errs.append("Choose an attribute to increase.")
	elif a != "":
		errs.append("No attribute increase at this level.")
	var tmp := staged_sheet(sheet, choices)
	errs.append_array(BuildValidator.validate_skills(sheet.class_id, tmp.level, sheet.skill_ranks, choices.get("skills", {}), int(pv["skill_points"])))
	var feats := DB.str_arr(choices.get("feats", []))
	if feats.size() > int(pv["feat_picks"]):
		errs.append("Too many feats (%d of %d)." % [feats.size(), int(pv["feat_picks"])])
	var owned: Array[String] = tmp.feats.duplicate()
	for f in feats:
		var fe := BuildValidator.feat_errors(tmp, f, owned)
		if not fe.is_empty():
			errs.append("%s: %s" % [DB.feat(f).get("name", f), fe[0]])
		owned.append(f)
	tmp.feats = owned
	tmp.mark_dirty()
	var pw := DB.str_arr(choices.get("powers", []))
	if pw.size() > int(pv["power_picks"]):
		errs.append("Too many powers (%d of %d)." % [pw.size(), int(pv["power_picks"])])
	var powned: Array[String] = tmp.powers.duplicate()
	for p in pw:
		var pe := BuildValidator.power_errors(tmp, p, powned)
		if not pe.is_empty():
			errs.append("%s: %s" % [DB.power(p).get("name", p), pe[0]])
		powned.append(p)
	return errs


static func apply_level_up(sheet: CharacterSheet, choices: Dictionary) -> Dictionary:
	var errs := validate(sheet, choices)
	if not errs.is_empty():
		return {"ok": false, "errors": errs}
	var pv := preview(sheet)
	var old_max_hp := sheet.max_hp()
	var old_max_en := sheet.max_energy()
	sheet.level += 1
	var a := String(choices.get("attr", ""))
	if a != "":
		sheet.attr_increases[a] = int(sheet.attr_increases.get(a, 0)) + 1
	var added: Dictionary = choices.get("skills", {})
	var spent := BuildValidator.skill_spend(sheet.class_id, added)
	for s in added.keys():
		sheet.skill_ranks[String(s)] = int(sheet.skill_ranks.get(s, 0)) + int(added[s])
	sheet.skill_bank = maxi(0, int(pv["skill_points"]) - spent)
	for f in BuildValidator.class_features(sheet.class_id, sheet.level):
		if not sheet.feats.has(f):
			sheet.feats.append(f)
	for f in DB.str_arr(choices.get("feats", [])):
		sheet.feats.append(f)
	for p in DB.str_arr(choices.get("powers", [])):
		sheet.powers.append(p)
	sheet.mark_dirty()
	sheet.hp += sheet.max_hp() - old_max_hp
	sheet.energy += sheet.max_energy() - old_max_en
	sheet.hp = clampi(sheet.hp, 1, sheet.max_hp())
	sheet.energy = clampi(sheet.energy, 0, sheet.max_energy())
	var entry := {"level": sheet.level, "attr": a, "skills": added.duplicate(), "feats": choices.get("feats", []), "powers": choices.get("powers", [])}
	sheet.level_log.append(entry)
	Events.post("level_up", {"uid": sheet.uid, "level": sheet.level})
	return {"ok": true, "errors": [], "entry": entry}


## Automatic choices from builds.json priorities; always passes validate().
static func recommended_choices(sheet: CharacterSheet) -> Dictionary:
	var pv := preview(sheet)
	var pri: Dictionary = DB.dict(DB.builds.get(sheet.class_id, {}), "priorities")
	var choices := {"attr": "", "skills": {}, "feats": [], "powers": []}
	if bool(pv["attr_increase"]):
		choices["attr"] = String(pri.get("attr", "con"))
	var tmp := staged_sheet(sheet, choices)
	# Skills: round-robin through priorities while points and caps allow.
	var points := int(pv["skill_points"])
	var order := DB.str_arr(pri.get("skills", []))
	for s in DB.skill_ids():
		if not order.has(s) and sheet.is_class_skill(s):
			order.append(s)
	var added := {}
	var progress := true
	while progress and points > 0:
		progress = false
		for s in order:
			var cost := BuildValidator.rank_cost(sheet.class_id, s)
			var cur := int(sheet.skill_ranks.get(s, 0)) + int(added.get(s, 0))
			if cost <= points and cur < BuildValidator.max_rank(sheet.class_id, s, tmp.level):
				added[s] = int(added.get(s, 0)) + 1
				points -= cost
				progress = true
				if points <= 0:
					break
	choices["skills"] = added
	var owned: Array[String] = tmp.feats.duplicate()
	var fl: Array = []
	var fpri := DB.str_arr(pri.get("feats", []))
	for f in fpri + BuildValidator.selectable_feats(tmp, owned):
		if fl.size() >= int(pv["feat_picks"]):
			break
		if not fl.has(f) and BuildValidator.feat_errors(tmp, f, owned).is_empty():
			fl.append(f)
			owned.append(f)
	choices["feats"] = fl
	tmp.feats = owned
	tmp.mark_dirty()
	var pl: Array = []
	var powned: Array[String] = tmp.powers.duplicate()
	var ppri := DB.str_arr(pri.get("powers", []))
	for p in ppri + BuildValidator.selectable_powers(tmp, powned):
		if pl.size() >= int(pv["power_picks"]):
			break
		if not pl.has(p) and BuildValidator.power_errors(tmp, p, powned).is_empty():
			pl.append(p)
			powned.append(p)
	choices["powers"] = pl
	return choices
