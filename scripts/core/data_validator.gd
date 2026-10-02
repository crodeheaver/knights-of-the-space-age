class_name DataValidator
extends RefCounted
## Validates every ID, prerequisite, reference and dialogue destination in the
## data set. Run at startup (errors are printed) and by the test suite (errors
## fail the build).

var errors: Array[String] = []
var db: Node


func err(msg: String) -> void:
	errors.append(msg)


func validate_all(d: Node) -> Array[String]:
	db = d
	errors.clear()
	for e in d.load_errors:
		err(e)
	_classes()
	_feats()
	_powers()
	_items()
	_recipes()
	_enemies()
	_companions()
	_vendors()
	_quests()
	_dialogues()
	_layout()
	_encounters()
	_builds()
	_prestige()
	_presets()
	return errors


func _item_ok(id: String, where: String) -> void:
	if not db.items.has(id) and id != "credits":
		err("%s: unknown item '%s'" % [where, id])


func _feat_ok(id: String, where: String) -> void:
	if not db.feats.has(id):
		err("%s: unknown feat '%s'" % [where, id])


func _power_ok(id: String, where: String) -> void:
	if not db.powers.has(id):
		err("%s: unknown power '%s'" % [where, id])


func _status_ok(id: String, where: String) -> void:
	if not db.statuses.has(id):
		err("%s: unknown status '%s'" % [where, id])


func _skill_ok(id: String, where: String) -> void:
	if not db.skills.has(id):
		err("%s: unknown skill '%s'" % [where, id])


func _classes() -> void:
	for cid in db.classes.keys():
		var c: Dictionary = db.classes[cid]
		for s in c.get("class_skills", []):
			_skill_ok(String(s), "class " + cid)
		for f in c.get("starting_feats", []):
			_feat_ok(String(f), "class " + cid)
		for lv in DB.dict(c, "class_features").keys():
			for f in c["class_features"][lv]:
				_feat_ok(String(f), "class %s features" % cid)
		for slot in DB.dict(c, "starting_equipment").keys():
			_item_ok(String(c["starting_equipment"][slot]), "class %s equipment" % cid)
		for it in DB.dict(c, "starting_items").keys():
			_item_ok(String(it), "class %s items" % cid)
		for k in ["bab", "feat_picks", "power_picks"]:
			if (c.get(k, []) as Array).size() < 10:
				err("class %s: %s table shorter than 10 levels" % [cid, k])


func _feats() -> void:
	for fid in db.feats.keys():
		var f: Dictionary = db.feats[fid]
		var pr: Dictionary = f.get("prereq", {})
		for x in pr.get("feats", []):
			_feat_ok(String(x), "feat %s prereq" % fid)
		for x in pr.get("any_feats", []):
			_feat_ok(String(x), "feat %s prereq" % fid)
		var a: Dictionary = f.get("action", {})
		for k in ["self_status", "on_hit_status", "status_on_fail"]:
			if a.has(k):
				_status_ok(String(a[k]["id"]), "feat %s" % fid)
		if f.has("chain") and not f.has("rank"):
			err("feat %s: chain without rank" % fid)


func _powers() -> void:
	for pid in db.powers.keys():
		var p: Dictionary = db.powers[pid]
		for x in DB.dict(p, "prereq").get("powers", []):
			_power_ok(String(x), "power %s prereq" % pid)
		for k in ["status", "status_on_fail", "machine_status_on_fail"]:
			if p.has(k):
				_status_ok(String(p[k]["id"]), "power %s" % pid)
		if not ["mercy", "dominion", "universal"].has(String(p.get("school", ""))):
			err("power %s: bad school" % pid)
		if not ["self", "ally", "party", "enemy", "area_enemy", "self_area"].has(String(p.get("target", ""))):
			err("power %s: bad target" % pid)


func _items() -> void:
	for iid in db.items.keys():
		var it: Dictionary = db.items[iid]
		for y in DB.dict(it, "dismantle").keys():
			_item_ok(String(y), "item %s dismantle" % iid)
		var u: Dictionary = it.get("use", {})
		if u.has("status"):
			_status_ok(String(u["status"]["id"]), "item " + iid)
		for k in ["throw", "mine"]:
			var t: Dictionary = it.get(k, {})
			for k2 in ["status_on_fail", "machine_status_on_fail"]:
				if t.has(k2):
					_status_ok(String(t[k2]["id"]), "item %s" % iid)
		if it.get("type", "") == "weapon" and not it.has("weapon"):
			err("item %s: weapon without stats" % iid)
		if it.get("type", "") == "armor" and not it.has("armor"):
			err("item %s: armor without stats" % iid)
		if it.get("type", "") in ["armor", "gear"] and not ["head", "body", "hands", "belt", "implant", "wrist"].has(String(it.get("slot", ""))):
			err("item %s: bad slot" % iid)
		if int(it.get("value", 0)) < 0:
			err("item %s: negative value" % iid)


func _recipes() -> void:
	for rid in db.recipes.keys():
		var r: Dictionary = db.recipes[rid]
		for x in DB.dict(r, "inputs").keys():
			_item_ok(String(x), "recipe " + rid)
		for x in DB.dict(r, "output").keys():
			_item_ok(String(x), "recipe " + rid)
		_skill_ok(String(r.get("skill", "")), "recipe " + rid)
		if not ["workbench", "medstation"].has(String(r.get("station", ""))):
			err("recipe %s: bad station" % rid)
		# Economic loop check: dismantling the output can never return more
		# value than the inputs cost.
		var in_value := 0
		for x in DB.dict(r, "inputs").keys():
			in_value += int(db.items.get(String(x), {}).get("value", 0)) * int(r["inputs"][x])
		for x in DB.dict(r, "output").keys():
			var dy: Dictionary = DB.dict(db.items.get(String(x), {}), "dismantle")
			var out_value := 0
			for y in dy.keys():
				out_value += int(db.items.get(String(y), {}).get("value", 0)) * int(dy[y])
			if out_value * int(r["output"][x]) > in_value:
				err("recipe %s: dismantle loop generates value" % rid)


func _enemies() -> void:
	for eid in db.enemies.keys():
		var e: Dictionary = db.enemies[eid]
		for slot in DB.dict(e, "weapons").keys():
			_item_ok(String(e["weapons"][slot]), "enemy " + eid)
		if e.has("armor"):
			_item_ok(String(e["armor"]), "enemy " + eid)
		for x in DB.dict(e, "kit").keys():
			_item_ok(String(x), "enemy %s kit" % eid)
		for x in DB.dict(e, "loot").keys():
			_item_ok(String(x), "enemy %s loot" % eid)
		for x in e.get("powers", []):
			_power_ok(String(x), "enemy " + eid)
		for x in e.get("feats", []):
			_feat_ok(String(x), "enemy " + eid)
		if not ["melee", "ranged", "support", "machine"].has(String(e.get("role", ""))):
			err("enemy %s: bad role" % eid)


func _companions() -> void:
	for cid in db.companions.keys():
		var c: Dictionary = db.companions[cid]
		for f in c.get("feats", []):
			_feat_ok(String(f), "companion " + cid)
		for slot in DB.dict(c, "equipment").keys():
			_item_ok(String(c["equipment"][slot]), "companion " + cid)
		for s in DB.dict(c, "skills").keys():
			_skill_ok(String(s), "companion " + cid)
		if not db.classes.has(String(c.get("class", ""))):
			err("companion %s: unknown class" % cid)


func _vendors() -> void:
	for vid in db.vendors.keys():
		for x in DB.dict(db.vendors[vid], "stock").keys():
			_item_ok(String(x), "vendor " + vid)
		if float(db.vendors[vid].get("sell_mult", 0.4)) >= float(db.vendors[vid].get("buy_mult", 1.0)):
			err("vendor %s: sell price >= buy price allows credit loops" % vid)


func _cond_check(c: Variant, where: String) -> void:
	for k in Conditions.unknown_keys(c):
		err("%s: unknown condition key '%s'" % [where, k])
	_cond_refs(c, where)


func _cond_refs(c: Variant, where: String) -> void:
	if typeof(c) == TYPE_ARRAY:
		for x in c:
			_cond_refs(x, where)
		return
	if typeof(c) != TYPE_DICTIONARY:
		return
	if c.has("item"):
		_item_ok(String(c["item"]), where)
	if c.has("quest") and not db.quests.has(String(c["quest"])):
		err("%s: unknown quest '%s'" % [where, c["quest"]])
	if c.has("skill"):
		_skill_ok(String(c["skill"]), where)
	if c.has("power"):
		_power_ok(String(c["power"]), where)
	for sub in ["any", "all"]:
		if c.has(sub):
			_cond_refs(c[sub], where)
	if c.has("not"):
		_cond_refs(c["not"], where)


func _eff_check(e: Variant, where: String) -> void:
	for k in Effects.unknown_keys(e):
		err("%s: unknown effect key '%s'" % [where, k])
	var list: Array = e if typeof(e) == TYPE_ARRAY else ([e] if typeof(e) == TYPE_DICTIONARY else [])
	for x in list:
		if x.has("give_item"):
			_item_ok(String(x["give_item"]), where)
		if x.has("take_item"):
			_item_ok(String(x["take_item"]), where)
		if x.has("quest"):
			var qid := String(x["quest"])
			if not db.quests.has(qid):
				err("%s: unknown quest '%s'" % [where, qid])
			else:
				if x.has("stage") and not DB.dict(db.quests[qid], "stages").has(String(x["stage"])):
					err("%s: quest %s has no stage '%s'" % [where, qid, x["stage"]])
				if x.has("objective") and not DB.dict(db.quests[qid], "objectives").has(String(x["objective"])):
					err("%s: quest %s has no objective '%s'" % [where, qid, x["objective"]])
		if x.has("start_encounter") and not db.encounters.has(String(x["start_encounter"])):
			err("%s: unknown encounter '%s'" % [where, x["start_encounter"]])
		if x.has("resolve_encounter") and not db.encounters.has(String(x["resolve_encounter"])):
			err("%s: unknown encounter '%s'" % [where, x["resolve_encounter"]])
		if x.has("codex") and not db.codex.has(String(x["codex"])):
			err("%s: unknown codex entry '%s'" % [where, x["codex"]])
		if x.has("tutorial") and not db.tutorials.has(String(x["tutorial"])):
			err("%s: unknown tutorial '%s'" % [where, x["tutorial"]])
		if x.has("grant_feat"):
			_feat_ok(String(x["grant_feat"]), where)
		if x.has("grant_power"):
			_power_ok(String(x["grant_power"]), where)
		if x.has("influence") and not db.companions.has(String(x["influence"])):
			err("%s: unknown companion '%s'" % [where, x["influence"]])
		if (x.has("xp") or x.has("alignment") or x.has("influence")) and not x.has("key"):
			err("%s: reward/alignment/influence effect without a one-time key" % where)


func _quests() -> void:
	for qid in db.quests.keys():
		var q: Dictionary = db.quests[qid]
		var stages: Dictionary = q.get("stages", {})
		var objs: Dictionary = q.get("objectives", {})
		if q.has("start") and not stages.has(String(q["start"])):
			err("quest %s: start stage missing" % qid)
		for s in stages.keys():
			for o in stages[s].get("objectives", []):
				if not objs.has(String(o)):
					err("quest %s stage %s: unknown objective %s" % [qid, s, o])
		for tr in q.get("transitions", []):
			if tr.has("stage") and not stages.has(String(tr["stage"])):
				err("quest %s: transition to unknown stage %s" % [qid, tr["stage"]])
			if tr.has("objective") and not objs.has(String(tr["objective"])):
				err("quest %s: transition to unknown objective %s" % [qid, tr["objective"]])
			for f in tr.get("from", []):
				if not stages.has(String(f)):
					err("quest %s: transition from unknown stage %s" % [qid, f])
			if tr.has("if"):
				_cond_check(tr["if"], "quest %s transition" % qid)


func _dialogues() -> void:
	for did in db.dialogues.keys():
		var dl: Dictionary = db.dialogues[did]
		var nodes: Dictionary = dl.get("nodes", {})
		if nodes.is_empty():
			err("dialogue %s: no nodes" % did)
		var targets: Array = []
		for e in dl.get("entry", []):
			targets.append(String(e.get("node", "")))
			_cond_check(e.get("if", []), "dialogue %s entry" % did)
		for nid in nodes.keys():
			var n: Dictionary = nodes[nid]
			var where := "dialogue %s node %s" % [did, nid]
			if n.has("next"):
				targets.append(String(n["next"]))
			for r in n.get("redirect", []):
				targets.append(String(r["node"]))
				_cond_check(r.get("if", []), where)
			_eff_check(n.get("effects", []), where)
			if not n.has("text") and not n.has("redirect"):
				err("%s: node without text" % where)
			if n.has("text") and String(n["text"]).strip_edges() == "":
				err("%s: empty text" % where)
			var sp := String(n.get("speaker", "narrator"))
			if not (["player", "narrator", "warden", "intercom", "system"].has(sp) or db.companions.has(sp) or DB.dict(db.layout, "npcs").has(sp) or DB.dict(dl, "names").has(sp)):
				err("%s: unknown speaker %s" % [where, sp])
			var choices: Array = n.get("choices", [])
			for i in choices.size():
				var c: Dictionary = choices[i]
				var cw := "%s choice %d" % [where, i]
				if String(c.get("text", "")).strip_edges() == "":
					err(cw + ": empty text")
				for k in ["next", "success", "failure"]:
					if c.has(k):
						targets.append(String(c[k]))
				if c.has("check"):
					if not c.has("success") or not c.has("failure"):
						err(cw + ": check without success/failure destinations")
					_skill_ok(String(c["check"].get("skill", "")), cw)
					if c["check"].has("power"):
						_power_ok(String(c["check"]["power"]), cw)
				if not c.has("next") and not c.has("check") and not bool(c.get("end", false)):
					err(cw + ": choice leads nowhere (needs next, check or end)")
				_cond_check(c.get("if", []), cw)
				_eff_check(c.get("effects", []), cw)
				_eff_check(c.get("success_effects", []), cw)
				_eff_check(c.get("failure_effects", []), cw)
		for t in targets:
			if t != "end" and t != "" and not nodes.has(t):
				err("dialogue %s: destination '%s' does not exist" % [did, t])


func _layout() -> void:
	var lay: Dictionary = db.layout
	if lay.is_empty():
		return
	var areas: Dictionary = lay.get("areas", {})
	var ids := {}
	for ob in lay.get("objects", []):
		var oid := String(ob.get("id", ""))
		var where := "layout object " + oid
		if oid == "":
			err("layout object without id")
		elif ids.has(oid):
			err("layout: duplicate object id " + oid)
		ids[oid] = true
		if ob.has("area") and not areas.has(String(ob["area"])):
			err("%s: unknown area %s" % [where, ob["area"]])
		if ob.has("dialogue") and not db.dialogues.has(String(ob["dialogue"])):
			err("%s: unknown dialogue %s" % [where, ob["dialogue"]])
		for x in DB.dict(ob, "loot").keys():
			_item_ok(String(x), where)
		if ob.has("vendor") and not db.vendors.has(String(ob["vendor"])):
			err("%s: unknown vendor %s" % [where, ob["vendor"]])
		if ob.has("codex") and not db.codex.has(String(ob["codex"])):
			err("%s: unknown codex %s" % [where, ob["codex"]])
		if ob.has("mine_item"):
			_item_ok(String(ob["mine_item"]), where)
		if ob.has("if"):
			_cond_check(ob["if"], where)
		for opt in ob.get("options", []):
			var ow := "%s option %s" % [where, opt.get("id", "?")]
			if opt.has("skill"):
				_skill_ok(String(opt["skill"]), ow)
			_cond_check(opt.get("if", []), ow)
			_eff_check(opt.get("effects", []), ow)
			_eff_check(opt.get("success", []), ow)
			_eff_check(opt.get("failure", []), ow)
			if opt.has("dialogue") and not db.dialogues.has(String(opt["dialogue"])):
				err("%s: unknown dialogue %s" % [ow, opt["dialogue"]])
			if opt.has("item"):
				_item_ok(String(opt["item"]), ow)
		_eff_check(ob.get("on_enter", []), where)
	for nid in DB.dict(lay, "npcs").keys():
		var n: Dictionary = lay["npcs"][nid]
		if n.has("dialogue") and not db.dialogues.has(String(n["dialogue"])):
			err("npc %s: unknown dialogue %s" % [nid, n["dialogue"]])
		if n.has("area") and not areas.has(String(n["area"])):
			err("npc %s: unknown area" % nid)
	for tr in lay.get("triggers", []):
		_eff_check(tr.get("effects", []), "trigger " + String(tr.get("id", "?")))
		_cond_check(tr.get("if", []), "trigger " + String(tr.get("id", "?")))


func _encounters() -> void:
	for eid in db.encounters.keys():
		var e: Dictionary = db.encounters[eid]
		for sp in e.get("spawns", []):
			if not db.enemies.has(String(sp.get("enemy", ""))):
				err("encounter %s: unknown enemy %s" % [eid, sp.get("enemy", "")])
			if sp.has("if"):
				_cond_check(sp["if"], "encounter %s spawn" % eid)
		_eff_check(e.get("on_resolve", []), "encounter %s on_resolve" % eid)
		_eff_check(e.get("on_start", []), "encounter %s on_start" % eid)
		if e.has("area") and not DB.dict(db.layout, "areas").has(String(e["area"])):
			err("encounter %s: unknown area" % eid)


func _builds() -> void:
	for cid in ["vanguard", "operative", "adept"]:
		var b: Dictionary = db.builds.get(cid, {})
		if b.is_empty():
			err("missing recommended build for " + cid)
			continue
		var errs := BuildValidator.validate_build(b)
		for e in errs:
			err("recommended build %s: %s" % [cid, e])
		var un := BuildValidator.unspent(b)
		for k in un.keys():
			if int(un[k]) != 0:
				err("recommended build %s leaves %s unspent (%d)" % [cid, k, int(un[k])])


func _prestige() -> void:
	var p: Dictionary = db.prestige
	for vid in DB.dict(p, "variants").keys():
		var v: Dictionary = p["variants"][vid]
		if not DB.dict(p, "families").has(String(v.get("family", ""))):
			err("prestige %s: unknown family" % vid)
		if v.has("aura"):
			_status_ok(String(v["aura"]["status"]), "prestige " + vid)
		if v.has("crit_status"):
			_status_ok(String(v["crit_status"]["id"]), "prestige " + vid)
	for fid in DB.dict(p, "families").keys():
		var n := 0
		for vid in DB.dict(p, "variants").keys():
			if p["variants"][vid]["family"] == fid:
				n += 1
		if n < 2:
			err("prestige family %s needs two variants" % fid)


func _presets() -> void:
	for pid in db.dev_presets.keys():
		var pr: Dictionary = db.dev_presets[pid]
		if pr.has("build"):
			for e in BuildValidator.validate_build(pr["build"]):
				err("dev preset %s build: %s" % [pid, e])
