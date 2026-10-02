class_name Conditions
extends RefCounted
## Structured, data-only condition evaluator used by dialogue, interactions,
## quests and encounters. There is no expression parsing or code evaluation:
## every condition is a Dictionary of known keys (see docs/ARCHITECTURE.md).

const KNOWN := ["flag", "not_flag", "eq", "gte", "lte", "attr", "skill", "who", "background", "class", "item", "count",
	"equipped", "power", "feat", "alignment_gte", "alignment_lte", "influence", "in_party", "recruited", "quest", "state",
	"stage", "objective", "seen", "credits_gte", "level_gte", "any", "all", "not", "encounter", "controlled", "difficulty",
	"kind", "check_done", "check_passed", "check_failed", "energy_gte", "party_size_gte", "dev", "cleared", "_note"]


static func eval_all(conds: Variant, st: GameState, ctx: Dictionary = {}) -> bool:
	if conds == null:
		return true
	if typeof(conds) == TYPE_DICTIONARY:
		return eval_one(conds, st, ctx)
	for c in conds:
		if not eval_one(c, st, ctx):
			return false
	return true


static func _who(c: Dictionary, st: GameState, ctx: Dictionary) -> CharacterSheet:
	var w := String(c.get("who", "player"))
	if w == "actor":
		w = String(ctx.get("actor", "player"))
	return st.get_char(w)


static func _cmp(v: Variant, c: Dictionary) -> bool:
	if c.has("eq"):
		return v == c["eq"] or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(c["eq"]) in [TYPE_INT, TYPE_FLOAT] and float(v) == float(c["eq"]))
	if c.has("gte"):
		return float(v) >= float(c["gte"])
	if c.has("lte"):
		return float(v) <= float(c["lte"])
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
		return float(v) != 0.0
	return v != null and String(v) != ""


static func eval_one(c: Dictionary, st: GameState, ctx: Dictionary = {}) -> bool:
	if c.has("any"):
		var ok := false
		for x in c["any"]:
			if eval_one(x, st, ctx):
				ok = true
				break
		if not ok:
			return false
	if c.has("all") and not eval_all(c["all"], st, ctx):
		return false
	if c.has("not") and eval_one(c["not"], st, ctx):
		return false
	if c.has("flag"):
		if not _cmp(st.flags.get(String(c["flag"]), null), c):
			return false
	if c.has("not_flag"):
		var v: Variant = st.flags.get(String(c["not_flag"]), null)
		if v != null and v != false and v != 0:
			return false
	if c.has("attr"):
		var s := _who(c, st, ctx)
		if s == null or not _cmp(s.attr(String(c["attr"])), c):
			return false
	if c.has("skill"):
		var s2 := _who(c, st, ctx)
		if s2 == null or not _cmp(s2.skill_total(String(c["skill"])), c):
			return false
	if c.has("background"):
		var p := st.get_char("player")
		if p == null or p.background != String(c["background"]):
			return false
	if c.has("class"):
		var p2 := st.get_char("player")
		if p2 == null or p2.class_id != String(c["class"]):
			return false
	if c.has("kind"):
		var s3 := _who(c, st, ctx)
		if s3 == null or s3.kind != String(c["kind"]):
			return false
	if c.has("item"):
		var need := int(c.get("count", 1))
		if st.inventory.count(String(c["item"])) < need:
			return false
	if c.has("equipped"):
		var found := false
		for uid in st.party:
			var s4 := st.get_char(uid)
			if s4 == null:
				continue
			for slot in s4.equipment.keys():
				var inst: Variant = s4.equipment[slot]
				if inst != null and inst["id"] == c["equipped"]:
					found = true
		if not found:
			return false
	if c.has("power"):
		var s5 := _who(c, st, ctx)
		if s5 == null or not s5.powers.has(String(c["power"])):
			# upgrade chains count (compel satisfies sway-chain checks only if listed)
			return false
	if c.has("feat"):
		var s6 := _who(c, st, ctx)
		if s6 == null or not s6.feats.has(String(c["feat"])):
			return false
	if c.has("energy_gte"):
		var s7 := _who(c, st, ctx)
		if s7 == null or s7.energy < int(c["energy_gte"]):
			return false
	if c.has("alignment_gte") and st.alignment < int(c["alignment_gte"]):
		return false
	if c.has("alignment_lte") and st.alignment > int(c["alignment_lte"]):
		return false
	if c.has("influence"):
		if not _cmp(st.influence.get(String(c["influence"]), 50), c):
			return false
	if c.has("in_party") and not st.party.has(String(c["in_party"])):
		return false
	if c.has("recruited") and not st.roster.has(String(c["recruited"])):
		return false
	if c.has("party_size_gte") and st.party.size() < int(c["party_size_gte"]):
		return false
	if c.has("controlled") and st.controlled != String(c["controlled"]):
		return false
	if c.has("quest"):
		var q: Dictionary = st.quests.get(String(c["quest"]), {})
		var qstate := String(q.get("state", "inactive"))
		if c.has("state"):
			var want: Variant = c["state"]
			if typeof(want) == TYPE_ARRAY:
				if not (want as Array).has(qstate):
					return false
			elif qstate != String(want):
				return false
		if c.has("stage") and String(q.get("stage", "")) != String(c["stage"]):
			return false
	if c.has("objective"):
		var parts := String(c["objective"]).split(".")
		var q2: Dictionary = st.quests.get(parts[0], {})
		var os := String(DB.dict(q2, "objectives").get(parts[1] if parts.size() > 1 else "", "inactive"))
		if String(c.get("state", "completed")) != os:
			return false
	if c.has("seen"):
		if not st.seen_nodes.has(String(c["seen"])):
			return false
	if c.has("check_done") and not st.checks.has(String(c["check_done"])):
		return false
	if c.has("check_passed"):
		if not bool(DB.dict(st.checks, String(c["check_passed"])).get("success", false)):
			return false
	if c.has("check_failed"):
		var ck: Dictionary = DB.dict(st.checks, String(c["check_failed"]))
		if ck.is_empty() or bool(ck.get("success", false)):
			return false
	if c.has("credits_gte") and st.inventory.credits < int(c["credits_gte"]):
		return false
	if c.has("level_gte"):
		var p3 := st.get_char("player")
		if p3 == null or p3.level < int(c["level_gte"]):
			return false
	if c.has("encounter"):
		var es := String(DB.dict(st.encounters, String(c["encounter"])).get("state", "pending"))
		if c.has("state") and not c.has("quest") and es != String(c["state"]):
			return false
	if c.has("cleared"):
		if String(DB.dict(st.encounters, String(c["cleared"])).get("state", "pending")) != "resolved":
			return false
	if c.has("difficulty") and st.difficulty != String(c["difficulty"]):
		return false
	if c.has("dev") and bool(c["dev"]) != st.dev_mode:
		return false
	return true


## Validation helper: returns unknown keys in a condition tree.
static func unknown_keys(c: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(c) == TYPE_ARRAY:
		for x in c:
			out.append_array(unknown_keys(x))
	elif typeof(c) == TYPE_DICTIONARY:
		for k in (c as Dictionary).keys():
			if not KNOWN.has(String(k)):
				out.append(String(k))
		for sub in ["any", "all"]:
			if c.has(sub):
				out.append_array(unknown_keys(c[sub]))
		if c.has("not"):
			out.append_array(unknown_keys(c["not"]))
	return out
