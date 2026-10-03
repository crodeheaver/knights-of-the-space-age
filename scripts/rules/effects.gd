class_name Effects
extends RefCounted
## Structured effect runner for dialogue, interactions and encounters.
## State effects mutate GameState directly; world/UI effects are posted as
## "world_effect" events for the World and UI to execute. One-time rewards use
## ledger keys, so replaying a conversation or reloading never doubles them.

const KNOWN := ["set_flag", "value", "inc_flag", "by", "alignment", "key", "reason", "influence", "delta", "xp",
	"give_item", "count", "take_item", "credits", "quest", "stage", "state", "objective", "join_party", "leave_party",
	"start_encounter", "resolve_encounter", "resolution", "end_dialogue", "heal_party", "damage_party", "dtype", "world", "set", "event", "data",
	"codex", "tutorial", "notify", "grant_feat", "grant_power", "who", "spend_energy", "survivors", "open", "minigame",
	"cinematic", "then", "status", "duration", "teleport", "npc", "npc_state", "remove_npc", "autosave", "combat_hostile", "faction", "_note", "sound",
	"start_dialogue", "enemy", "area_damage", "radius", "dice", "reveal_area", "evac", "bark"]


static func apply_all(effects: Variant, st: GameState, ctx: Dictionary = {}) -> Array[String]:
	var log: Array[String] = []
	if effects == null:
		return log
	var list: Array = effects if typeof(effects) == TYPE_ARRAY else [effects]
	for e in list:
		log.append_array(apply_one(e, st, ctx))
	return log


static func apply_one(e: Dictionary, st: GameState, ctx: Dictionary) -> Array[String]:
	var log: Array[String] = []
	var key := String(e.get("key", ""))
	if e.has("set_flag"):
		st.set_flag(String(e["set_flag"]), e.get("value", true))
	if e.has("inc_flag"):
		var fk := String(e["inc_flag"])
		if key == "" or st.claim("flag:" + key):
			st.set_flag(fk, int(st.flags.get(fk, 0)) + int(e.get("by", 1)))
	if e.has("survivors"):
		if key == "" or st.claim("surv:" + key):
			st.set_flag("survivors", int(st.flags.get("survivors", 0)) + int(e["survivors"]))
			log.append("Survivors %s%d" % ["+" if int(e["survivors"]) >= 0 else "", int(e["survivors"])])
	if e.has("alignment"):
		var d := st.add_alignment(int(e["alignment"]), key, String(e.get("reason", "")))
		if d != 0:
			log.append("%s %s%d" % ["Mercy" if d > 0 else "Dominion", "+" if d > 0 else "", absi(d)])
	if e.has("influence"):
		var comp := String(e["influence"])
		var d2 := st.add_influence(comp, int(e.get("delta", 0)), key, String(e.get("reason", "")))
		if d2 != 0:
			var nm := String(DB.companions.get(comp, {}).get("name", comp))
			log.append("%s influence %s%d" % [nm, "+" if d2 > 0 else "", d2])
	if e.has("xp"):
		var g := st.grant_xp(int(e["xp"]), key, String(e.get("reason", "")))
		if g > 0:
			log.append("+%d XP" % g)
	if e.has("give_item"):
		if key == "" or st.claim("item:" + key):
			var n := int(e.get("count", 1))
			st.inventory.add(String(e["give_item"]), n)
			log.append("Received %s%s" % [DB.item_name(String(e["give_item"])), " x%d" % n if n > 1 else ""])
			Events.post("item_acquired", {"id": String(e["give_item"]), "count": n})
	if e.has("take_item"):
		var n2 := int(e.get("count", 1))
		if st.inventory.remove(String(e["take_item"]), n2):
			log.append("Lost %s%s" % [DB.item_name(String(e["take_item"])), " x%d" % n2 if n2 > 1 else ""])
	if e.has("credits"):
		if key == "" or st.claim("cr:" + key):
			var c := int(e["credits"])
			st.inventory.credits = maxi(0, st.inventory.credits + c)
			log.append("%s%d credits" % ["+" if c >= 0 else "", c])
	if e.has("quest"):
		QuestSystem.apply(st, String(e["quest"]), e)
	if e.has("join_party"):
		Events.post("world_effect", {"type": "join_party", "who": String(e["join_party"])})
	if e.has("leave_party"):
		Events.post("world_effect", {"type": "leave_party", "who": String(e["leave_party"])})
	if e.has("start_encounter"):
		Events.post("world_effect", {"type": "start_encounter", "id": String(e["start_encounter"]), "faction": String(e.get("faction", ""))})
	if e.has("resolve_encounter"):
		Events.post("world_effect", {"type": "resolve_encounter", "id": String(e["resolve_encounter"]), "resolution": String(e.get("resolution", "peaceful"))})
	if e.has("heal_party"):
		Events.post("world_effect", {"type": "heal_party"})
	if e.has("damage_party"):
		Events.post("world_effect", {"type": "damage_party", "amount": int(e["damage_party"]), "dtype": String(e.get("dtype", "energy")), "who": String(e.get("who", "actor")), "actor": String(ctx.get("actor", "player"))})
		log.append("Took damage")
	if e.has("status"):
		Events.post("world_effect", {"type": "status", "id": String(e["status"]), "duration": float(e.get("duration", 9.0)), "who": String(e.get("who", "actor")), "actor": String(ctx.get("actor", "player"))})
	if e.has("world"):
		var obj := String(e["world"])
		var o := st.world_obj(obj)
		var setd: Dictionary = e.get("set", {})
		for k in setd.keys():
			o[k] = setd[k]
		Events.post("world_effect", {"type": "world_object", "id": obj, "set": setd})
	if e.has("npc"):
		var nid := String(e["npc"])
		if not st.npcs.has(nid):
			st.npcs[nid] = {}
		var ns: Dictionary = st.npcs[nid]
		var nset: Dictionary = e.get("set", {})
		for k in nset.keys():
			ns[k] = nset[k]
		Events.post("world_effect", {"type": "npc", "id": nid, "set": nset})
	if e.has("event"):
		Events.post(String(e["event"]), e.get("data", {}))
	if e.has("codex"):
		if st.discover(String(e["codex"])):
			log.append("Discovery: %s" % DB.codex.get(String(e["codex"]), {}).get("title", e["codex"]))
	if e.has("tutorial"):
		Events.post("tutorial", {"id": String(e["tutorial"])})
	if e.has("notify"):
		Events.toast(Game.fmt(String(e["notify"])), "story")
	if e.has("grant_feat"):
		var who := st.get_char(String(e.get("who", "player")))
		if who != null and not who.feats.has(String(e["grant_feat"])):
			who.feats.append(String(e["grant_feat"]))
			who.mark_dirty()
			who.energy = mini(who.max_energy(), who.energy + who.max_energy())
			log.append("%s learned %s" % [who.display_name, DB.feat(String(e["grant_feat"])).get("name", e["grant_feat"])])
			Events.post("feat_granted", {"uid": who.uid, "feat": String(e["grant_feat"])})
	if e.has("grant_power"):
		var who2 := st.get_char(String(e.get("who", "player")))
		if who2 != null and not who2.powers.has(String(e["grant_power"])):
			who2.powers.append(String(e["grant_power"]))
			log.append("%s learned %s" % [who2.display_name, DB.power(String(e["grant_power"])).get("name", e["grant_power"])])
	if e.has("spend_energy"):
		var p := st.get_char(String(e.get("who", "player")))
		if p != null:
			p.energy = maxi(0, p.energy - int(e["spend_energy"]))
			log.append("-%d energy" % int(e["spend_energy"]))
	if e.has("open"):
		Events.post("world_effect", {"type": "open", "what": String(e["open"]), "actor": String(ctx.get("actor", "player"))})
	if e.has("minigame"):
		Events.post("world_effect", {"type": "minigame", "id": String(e["minigame"])})
	if e.has("cinematic"):
		Events.post("world_effect", {"type": "cinematic", "id": String(e["cinematic"]), "then": String(e.get("then", ""))})
	if e.has("teleport"):
		Events.post("world_effect", {"type": "teleport", "to": e["teleport"]})
	if e.has("combat_hostile"):
		Events.post("world_effect", {"type": "combat_hostile", "faction": String(e["combat_hostile"])})
	if e.has("autosave"):
		Events.post("world_effect", {"type": "autosave", "label": String(e["autosave"])})
	if e.has("sound"):
		Events.post("world_effect", {"type": "sound", "id": String(e["sound"])})
	if e.has("start_dialogue"):
		Events.post("world_effect", {"type": "dialogue", "id": String(e["start_dialogue"])})
	if e.has("enemy"):
		Events.post("world_effect", {"type": "enemy", "id": String(e["enemy"]), "set": e.get("set", {})})
	if e.has("area_damage"):
		Events.post("world_effect", {"type": "area_damage", "at": e["area_damage"], "radius": float(e.get("radius", 3.0)), "dice": String(e.get("dice", "2d6")),
			"dtype": String(e.get("dtype", "kinetic")), "status": String(e.get("status", "")), "duration": float(e.get("duration", 3.0)), "faction": String(e.get("faction", ""))})
	if e.has("reveal_area"):
		Events.post("world_effect", {"type": "reveal_area", "areas": e["reveal_area"]})
	if e.has("evac"):
		evac(st, String(e["evac"]))
		log.append("Load-out: %s" % String(e["evac"]))
	if e.has("bark"):
		# An ambient line (data/ship_life.json): presentation only.
		Events.post("world_effect", {"type": "bark", "id": String(e["bark"])})
	if e.has("end_dialogue"):
		Events.post("world_effect", {"type": "end_dialogue"})
	return log


## Computes who fits aboard the Petrel for an evacuation choice. Seats: 15;
## the archive cradle displaces 5; the protagonist and companions take theirs.
static func evac(st: GameState, choice: String) -> void:
	var seats := 15 - st.roster.size()
	if choice == "archive":
		seats -= 5
	var surv := st.survivors()
	var aboard := mini(surv, seats)
	st.set_flag("evac_choice", choice)
	st.set_flag("evac_aboard", aboard)
	st.set_flag("evac_left", surv - aboard)


static func unknown_keys(e: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(e) == TYPE_ARRAY:
		for x in e:
			out.append_array(unknown_keys(x))
	elif typeof(e) == TYPE_DICTIONARY:
		for k in (e as Dictionary).keys():
			if not KNOWN.has(String(k)):
				out.append(String(k))
	return out
