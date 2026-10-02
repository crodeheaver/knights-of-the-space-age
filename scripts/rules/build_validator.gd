class_name BuildValidator
extends RefCounted
## Central validation for character builds: point-buy, skills, feats, powers.
## The character creator, level-up screen, developer presets and tests all use
## these functions, so no screen keeps its own copy of the rules.

const NAME_MAX := 24


static func pb() -> Dictionary:
	return DB.dict(DB.progression, "point_buy")


## Cost of raising a score from s to s+1.
static func step_cost(s: int) -> int:
	for t in DB.arr(pb(), "tiers"):
		if s + 1 <= int(t["up_to"]):
			return int(t["cost"])
	return 999


## Total cost to raise a score from the base (8) to `score`.
static func attr_cost(score: int) -> int:
	var base := int(pb().get("base", 8))
	var c := 0
	for s in range(base, score):
		c += step_cost(s)
	return c


static func points_spent(attrs: Dictionary) -> int:
	var t := 0
	for a in Rules.ATTRS:
		t += attr_cost(int(attrs.get(a, 8)))
	return t


static func points_remaining(attrs: Dictionary) -> int:
	return int(pb().get("budget", 30)) - points_spent(attrs)


static func can_raise(attrs: Dictionary, a: String) -> String:
	var s := int(attrs.get(a, 8))
	if s >= int(pb().get("max", 18)):
		return "Maximum score is %d." % int(pb().get("max", 18))
	if step_cost(s) > points_remaining(attrs):
		return "Needs %d points (%d left)." % [step_cost(s), points_remaining(attrs)]
	return ""


static func can_lower(attrs: Dictionary, a: String) -> String:
	if int(attrs.get(a, 8)) <= int(pb().get("min", 8)):
		return "Minimum score is %d." % int(pb().get("min", 8))
	return ""


static func validate_attrs(attrs: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	for a in Rules.ATTRS:
		if not attrs.has(a):
			errs.append("Missing attribute %s." % a)
			continue
		var s := int(attrs[a])
		if s < int(pb().get("min", 8)) or s > int(pb().get("max", 18)):
			errs.append("%s must be between %d and %d." % [Rules.ATTR_NAMES[a], int(pb().get("min", 8)), int(pb().get("max", 18))])
	var rem := points_remaining(attrs)
	if rem < 0:
		errs.append("Attribute budget exceeded by %d." % -rem)
	return errs


# ------------------------------------------------------------ skills
static func skill_points_for_level(class_id: String, int_score: int, level: int) -> int:
	var k: Dictionary = DB.klass(class_id)
	var per := maxi(1, int(k.get("skill_points", 2)) + Rules.mod(int_score))
	if level == 1:
		per *= int(DB.progression.get("first_level_skill_multiplier", 2))
	return per


static func rank_cost(class_id: String, skill: String) -> int:
	var k: Dictionary = DB.klass(class_id)
	var sc: Dictionary = DB.dict(DB.progression, "skill_cost")
	return int(sc.get("class", 1)) if DB.arr(k, "class_skills").has(skill) else int(sc.get("cross", 2))


static func max_rank(class_id: String, skill: String, level: int) -> int:
	var off := int(DB.dict(DB.progression, "rank_limit").get("class_offset", 3))
	var cap := level + off
	if DB.arr(DB.klass(class_id), "class_skills").has(skill):
		return cap
	return floori(cap / 2.0)


static func skill_spend(class_id: String, ranks_added: Dictionary) -> int:
	var t := 0
	for s in ranks_added.keys():
		t += int(ranks_added[s]) * rank_cost(class_id, String(s))
	return t


## Validates ranks being added at `level` on top of existing ranks.
static func validate_skills(class_id: String, level: int, existing: Dictionary, added: Dictionary, points: int) -> Array[String]:
	var errs: Array[String] = []
	for s in added.keys():
		if DB.skill(String(s)).is_empty():
			errs.append("Unknown skill %s." % s)
			continue
		if int(added[s]) < 0:
			errs.append("Cannot remove ranks.")
		var total := int(existing.get(s, 0)) + int(added[s])
		if total > max_rank(class_id, String(s), level):
			errs.append("%s exceeds rank limit %d." % [DB.skill(String(s))["name"], max_rank(class_id, String(s), level)])
	var spent := skill_spend(class_id, added)
	if spent > points:
		errs.append("Skill points exceeded (%d of %d)." % [spent, points])
	return errs


# ------------------------------------------------------------ feats & powers
static func prereq_errors(sheet: CharacterSheet, prereq: Dictionary, owned: Array[String], is_power: bool = false) -> Array[String]:
	var errs: Array[String] = []
	if prereq.has("level") and sheet.level < int(prereq["level"]):
		errs.append("Requires level %d." % int(prereq["level"]))
	var attrs: Dictionary = prereq.get("attrs", {})
	for a in attrs.keys():
		if sheet.attr_perm(String(a)) < int(attrs[a]):
			errs.append("Requires %s %d." % [Rules.ATTR_NAMES[a], int(attrs[a])])
	if prereq.has("bab") and sheet.bab() < int(prereq["bab"]):
		errs.append("Requires base attack +%d." % int(prereq["bab"]))
	var list_key := "powers" if is_power else "feats"
	for f in prereq.get(list_key, []):
		if not owned.has(String(f)):
			var nm: String = DB.power(String(f)).get("name", f) if is_power else DB.feat(String(f)).get("name", f)
			errs.append("Requires %s." % nm)
	if not is_power and prereq.has("powers"):
		for p in prereq["powers"]:
			if not sheet.powers.has(String(p)):
				errs.append("Requires power %s." % DB.power(String(p)).get("name", p))
	var anyf: Array = prereq.get("any_feats", [])
	if not anyf.is_empty():
		var ok := false
		for f in anyf:
			if owned.has(String(f)) or sheet.feats.has(String(f)):
				ok = true
		if not ok:
			var names: PackedStringArray = []
			for f in anyf:
				names.append(String(DB.feat(String(f)).get("name", f)))
			errs.append("Requires one of: %s." % ", ".join(names))
	if prereq.has("kind") and String(prereq["kind"]) != sheet.kind:
		errs.append("Only for %s characters." % ("synthetic" if prereq["kind"] == "machine" else "organic"))
	if bool(prereq.get("resonance", false)) and not sheet.has_resonance():
		errs.append("Requires Resonance.")
	return errs


static func feat_errors(sheet: CharacterSheet, feat_id: String, owned: Array[String] = []) -> Array[String]:
	var fd: Dictionary = DB.feat(feat_id)
	if fd.is_empty():
		return ["Unknown feat."]
	var have: Array[String] = owned if not owned.is_empty() else sheet.feats
	if have.has(feat_id):
		return ["Already known."]
	if bool(fd.get("earned", false)):
		return ["Earned through the story, not selectable."]
	return prereq_errors(sheet, fd.get("prereq", {}), have)


static func power_errors(sheet: CharacterSheet, power_id: String, owned: Array[String] = []) -> Array[String]:
	var pd: Dictionary = DB.power(power_id)
	if pd.is_empty():
		return ["Unknown power."]
	if bool(pd.get("innate", false)):
		return ["Not learnable."]
	var have: Array[String] = owned if not owned.is_empty() else sheet.powers
	if have.has(power_id):
		return ["Already known."]
	if not sheet.has_resonance():
		return ["Requires Resonance."]
	return prereq_errors(sheet, pd.get("prereq", {}), have, true)


static func selectable_feats(sheet: CharacterSheet, owned: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	for f in DB.feats.keys():
		if feat_errors(sheet, String(f), owned).is_empty():
			out.append(String(f))
	out.sort()
	return out


static func selectable_powers(sheet: CharacterSheet, owned: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	for p in DB.powers.keys():
		if power_errors(sheet, String(p), owned).is_empty():
			out.append(String(p))
	out.sort()
	return out


static func feat_picks(class_id: String, level: int) -> int:
	var arr: Array = DB.arr(DB.klass(class_id), "feat_picks")
	return int(arr[level - 1]) if level - 1 < arr.size() else 0


static func power_picks(class_id: String, level: int) -> int:
	var arr: Array = DB.arr(DB.klass(class_id), "power_picks")
	return int(arr[level - 1]) if level - 1 < arr.size() else 0


static func class_features(class_id: String, level: int) -> Array[String]:
	return DB.str_arr(DB.dict(DB.klass(class_id), "class_features").get(str(level), []))


# ------------------------------------------------------------ whole build
## build = {name, pronouns, class, background, attrs, skills (ranks), feats
## (chosen), powers (chosen), appearance}
static func base_sheet(build: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.uid = "player"
	s.is_player = true
	s.display_name = String(build.get("name", "Operator"))
	s.pronouns = String(build.get("pronouns", "they"))
	s.class_id = String(build.get("class", "vanguard"))
	s.background = String(build.get("background", ""))
	s.level = 1
	s.base_attrs = {}
	var a: Dictionary = build.get("attrs", {})
	for k in Rules.ATTRS:
		s.base_attrs[k] = int(a.get(k, 8))
	s.feats = DB.str_arr(DB.arr(DB.klass(s.class_id), "starting_feats"))
	for f in class_features(s.class_id, 1):
		if not s.feats.has(f):
			s.feats.append(f)
	s.appearance = (build.get("appearance", {}) as Dictionary).duplicate()
	s.behavior = "aggressive"
	s.mark_dirty()
	return s


static func validate_build(build: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var nm := String(build.get("name", "")).strip_edges()
	if nm == "":
		errs.append("Enter a name.")
	elif nm.length() > NAME_MAX:
		errs.append("Name is too long (max %d)." % NAME_MAX)
	var cid := String(build.get("class", ""))
	if DB.klass(cid).is_empty() or bool(DB.klass(cid).get("companion", false)):
		errs.append("Choose an archetype.")
		return errs
	if not DB.backgrounds.has(String(build.get("background", ""))):
		errs.append("Choose a background.")
	var ok_pron := false
	for p in DB.arr(DB.appearance, "pronouns"):
		if p["id"] == build.get("pronouns", ""):
			ok_pron = true
	if not ok_pron:
		errs.append("Choose pronouns.")
	var attrs: Dictionary = build.get("attrs", {})
	errs.append_array(validate_attrs(attrs))
	var s := base_sheet(build)
	var sp := skill_points_for_level(cid, int(attrs.get("int", 8)), 1)
	errs.append_array(validate_skills(cid, 1, {}, build.get("skills", {}), sp))
	var chosen := DB.str_arr(build.get("feats", []))
	if chosen.size() > feat_picks(cid, 1):
		errs.append("Too many feats chosen (%d of %d)." % [chosen.size(), feat_picks(cid, 1)])
	var owned: Array[String] = s.feats.duplicate()
	for f in chosen:
		var fe := feat_errors(s, f, owned)
		if not fe.is_empty():
			errs.append("%s: %s" % [DB.feat(f).get("name", f), fe[0]])
		owned.append(f)
	var pchosen := DB.str_arr(build.get("powers", []))
	if pchosen.size() > power_picks(cid, 1):
		errs.append("Too many powers chosen (%d of %d)." % [pchosen.size(), power_picks(cid, 1)])
	var powned: Array[String] = []
	s.feats = owned
	s.mark_dirty()
	for p in pchosen:
		var pe := power_errors(s, p, powned)
		if not pe.is_empty():
			errs.append("%s: %s" % [DB.power(p).get("name", p), pe[0]])
		powned.append(p)
	return errs


## Remaining unspent choices (for "complete your build" warnings).
static func unspent(build: Dictionary) -> Dictionary:
	var cid := String(build.get("class", "vanguard"))
	var attrs: Dictionary = build.get("attrs", {})
	var sp := skill_points_for_level(cid, int(attrs.get("int", 8)), 1)
	return {
		"attr_points": points_remaining(attrs),
		"skill_points": sp - skill_spend(cid, build.get("skills", {})),
		"feats": feat_picks(cid, 1) - DB.arr(build, "feats").size(),
		"powers": power_picks(cid, 1) - DB.arr(build, "powers").size(),
	}


static func make_sheet(build: Dictionary) -> CharacterSheet:
	var s := base_sheet(build)
	for k in (build.get("skills", {}) as Dictionary).keys():
		s.skill_ranks[String(k)] = int(build["skills"][k])
	for f in DB.str_arr(build.get("feats", [])):
		if not s.feats.has(f):
			s.feats.append(f)
	s.powers = DB.str_arr(build.get("powers", []))
	s.mark_dirty()
	s.hp = s.max_hp()
	s.energy = s.max_energy()
	return s


static func recommended(class_id: String) -> Dictionary:
	var b: Dictionary = DB.builds.get(class_id, {})
	return b.duplicate(true)
