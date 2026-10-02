class_name DevTools
extends RefCounted
## Developer presets and cheats. Presets build a fresh GameState from a
## recommended build, a world-state stage captured from a real bot run
## (data/dev_stages.json) and per-preset overrides (data/dev_presets.json).
## Everything they produce is tagged dev_mode, and saves made from them are
## labelled [DEV].


static func preset_ids() -> Array[String]:
	var out: Array[String] = []
	for k in DB.dev_presets.keys():
		if not String(k).begins_with("_"):
			out.append(String(k))
	return out


## Builds the preset's state into Game.state without loading a world.
static func apply_preset(id: String) -> Dictionary:
	var pd: Dictionary = DB.dev_presets.get(id, {})
	if pd.is_empty():
		return {"ok": false, "reason": "Unknown preset %s." % id}
	var b := BuildValidator.recommended(String(pd.get("class", "vanguard")))
	if pd.has("name_override"):
		b["name"] = String(pd["name_override"])
	Game.new_game(b, String(pd.get("difficulty", "standard")))
	var st := Game.state
	st.dev_mode = true
	st.preset_id = id
	st.dice.set_seed(4242)
	# World stage.
	var stage_id := String(pd.get("stage", ""))
	if stage_id != "":
		var sg: Dictionary = DB.dev_stages.get(stage_id, {})
		if sg.is_empty():
			return {"ok": false, "reason": "Missing stage %s (run tools/godot/gen_dev_stages.tscn)." % stage_id}
		var d := st.to_dict()
		for k in sg.keys():
			if d.has(k):
				d[k] = (sg[k] as Variant)
		st = GameState.from_dict(d)
		st.dev_mode = true
		st.preset_id = id
		Game.set_state(st)
		var pos: Array = sg.get("pos", [0, 0, 0])
		st.positions = {"player": pos}
		st.area = String(sg.get("area", "cabin"))
	# Companions.
	for c in pd.get("companions", []):
		var cid := String(c)
		Game.recruit(cid)
		if not st.npcs.has(cid + "_npc"):
			st.npcs[cid + "_npc"] = {}
		st.npcs[cid + "_npc"]["removed"] = true
		st.set_flag(cid + "_recruited")
	for k in (pd.get("influence", {}) as Dictionary).keys():
		st.influence[String(k)] = int(pd["influence"][k])
	st.alignment = int(pd.get("alignment", 0))
	# Levels: Recommended choices, as the level-up screen's button would.
	var lvl := int(pd.get("level", 1))
	for uid in st.roster:
		var s := st.get_char(uid)
		s.xp = maxi(s.xp, s.xp_for_level(lvl))
		var guard := 0
		while s.level < lvl and s.levels_available() > 0 and guard < 12:
			guard += 1
			var r := Progression.apply_level_up(s, Progression.recommended_choices(s))
			if not bool(r["ok"]):
				return {"ok": false, "reason": "%s level-up failed: %s" % [uid, str(r["errors"])]}
	# Skill floors (prestige requirements) and extra powers.
	var ms: Dictionary = pd.get("min_skills", {})
	for uid in ms.keys():
		var s2 := st.get_char(String(uid))
		for sk in (ms[uid] as Dictionary).keys():
			s2.skill_ranks[String(sk)] = maxi(int(s2.skill_ranks.get(sk, 0)), int(ms[uid][sk]))
		s2.mark_dirty()
	var ep: Dictionary = pd.get("extra_powers", {})
	for uid in ep.keys():
		var s3 := st.get_char(String(uid))
		for p in ep[uid]:
			if not s3.powers.has(String(p)):
				s3.powers.append(String(p))
		s3.mark_dirty()
	for k in (pd.get("flags", {}) as Dictionary).keys():
		st.set_flag(String(k), pd["flags"][k])
	for k in (pd.get("items", {}) as Dictionary).keys():
		st.inventory.add(String(k), int(pd["items"][k]))
	if pd.has("credits"):
		st.inventory.credits = int(pd["credits"])
	for uid in st.roster:
		var s4 := st.get_char(uid)
		s4.mark_dirty()
		s4.hp = s4.max_hp()
		s4.energy = s4.max_energy()
	if pd.has("adopt"):
		var ar := Prestige.adopt(st.player(), String(pd["adopt"]), st.alignment)
		if not bool(ar["ok"]):
			return {"ok": false, "reason": "adopt: " + str(ar["errors"])}
	# Tutorials already seen elsewhere are noise in a jump.
	for t in DB.tutorials.keys():
		st.tutorials_seen[String(t)] = true
	return {"ok": true, "reason": ""}


static func load_preset(id: String) -> void:
	var r := apply_preset(id)
	if not bool(r["ok"]):
		Events.toast("Preset failed: " + String(r["reason"]), "warn")
		push_warning("Preset failed: " + String(r["reason"]))
		return
	if Game.main != null and Game.main.has_method("load_world"):
		Game.main.load_world()
		Events.toast("Developer preset: %s" % DB.dev_presets[id].get("name", id), "info")


# ------------------------------------------------------------ cheats
static func grant_levels(n: int) -> void:
	var st := Game.state
	for uid in st.roster:
		var s := st.get_char(uid)
		s.xp = maxi(s.xp, s.xp_for_level(mini(int(DB.progression.get("max_level", 10)), s.level + n)))
	Events.toast("Developer: experience granted. Level up from the party cards.", "info")


static func set_alignment(v: int) -> void:
	Game.state.alignment = clampi(v, -100, 100)
	Events.post("alignment_changed", {"delta": 0, "value": Game.state.alignment, "reason": "developer"})


static func set_influence(cid: String, v: int) -> void:
	Game.state.influence[cid] = clampi(v, 0, 100)
	Events.post("influence_changed", {"companion": cid, "delta": 0, "value": v, "reason": "developer"})
