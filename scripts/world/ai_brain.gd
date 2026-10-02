class_name AIBrain
extends RefCounted
## Decision-making for enemies (by role) and companions (by behaviour).
## Only consulted when an actor's queue is empty: manual orders always win.
## Uses the seeded dice so encounters are reproducible.


static func _chance(p: float) -> bool:
	return Game.state.dice.randf() < p


# ------------------------------------------------------------ enemies
static func enemy_action(a: Actor, w: World) -> Dictionary:
	var s := a.sheet
	var targets: Array = w.hostiles_of(a)
	if targets.is_empty():
		return {}
	var role := String(s.overrides.get("role", s.behavior))
	var tgt: Actor = _pick_target(a, targets, role, w)
	# Support / controller abilities.
	if role == "support":
		var hurt: Actor = _hurt_ally(a, w, 0.55)
		if hurt != null:
			if s.powers.has("repair_beam") and hurt.sheet.kind == "machine" and not s.cooldowns.has("power:repair_beam"):
				return {"type": "power", "id": "repair_beam", "target": hurt.uid}
			if int(s.kit.get("medpac", 0)) > 0 and hurt.sheet.kind == "organic" and hurt.position.distance_to(a.position) < 12.0:
				return {"type": "item", "id": "medpac", "target": hurt.uid}
		if s.powers.has("suppression_field") and not s.cooldowns.has("power:suppression_field") and _cluster(tgt, targets, 2.5) >= 1:
			return {"type": "power", "id": "suppression_field", "target": tgt.uid}
		for g in ["stun_grenade", "adhesive_grenade"]:
			if int(s.kit.get(g, 0)) > 0 and _chance(0.45):
				return {"type": "item", "id": g, "target": tgt.uid}
	if s.powers.has("suppression_pulse") and not s.cooldowns.has("power:suppression_pulse"):
		var close := 0
		for t in targets:
			if (t as Actor).position.distance_to(a.position) <= 4.0:
				close += 1
		if close >= 1:
			return {"type": "power", "id": "suppression_pulse"}
	if int(s.kit.get("frag_grenade", 0)) > 0 and _cluster(tgt, targets, 3.0) >= 1 and tgt.position.distance_to(a.position) > 4.0 and _chance(0.5):
		return {"type": "item", "id": "frag_grenade", "target": tgt.uid}
	if int(s.kit.get("shield_cell", 0)) > 0 and s.hp < s.max_hp() * 0.5 and not s.has_status("shield_basic"):
		return {"type": "item", "id": "shield_cell"}
	if int(s.kit.get("medpac", 0)) > 0 and s.hp < s.max_hp() * 0.3 and role != "support":
		return {"type": "item", "id": "medpac", "target": a.uid}
	for f in s.action_feats():
		var fd: Dictionary = DB.feat(f)
		if ActionResolver.feat_usable(s, f, tgt.sheet) == "" and _chance(0.4):
			return {"type": "feat", "id": f, "target": tgt.uid}
	return {"type": "attack", "target": tgt.uid}


static func _pick_target(a: Actor, targets: Array, role: String, w: World) -> Actor:
	# Keep the current target if still valid (prevents jitter).
	if a.target_uid != "":
		for t in targets:
			if (t as Actor).uid == a.target_uid:
				return t
	var best: Actor = targets[0]
	var bs := INF
	for t in targets:
		var ta: Actor = t
		var d := ta.position.distance_to(a.position)
		var score := d
		if role == "ranged" and not w.grid.los(a.position, ta.position):
			score += 8.0
		score -= (1.0 - float(ta.sheet.hp) / float(maxi(1, ta.sheet.max_hp()))) * 3.0
		if score < bs:
			bs = score
			best = ta
	a.target_uid = best.uid
	return best


static func _cluster(tgt: Actor, targets: Array, r: float) -> int:
	var n := 0
	for t in targets:
		var ta: Actor = t
		if ta != tgt and ta.position.distance_to(tgt.position) <= r:
			n += 1
	return n


static func _hurt_ally(a: Actor, w: World, frac: float) -> Actor:
	var best: Actor = null
	var lowest := frac
	for o in w.allies_of(a):
		var oa: Actor = o
		if oa.sheet.is_downed():
			continue
		var f := float(oa.sheet.hp) / float(maxi(1, oa.sheet.max_hp()))
		if f < lowest:
			lowest = f
			best = oa
	return best


# ------------------------------------------------------------ companions
static func companion_action(a: Actor, w: World) -> Dictionary:
	var s := a.sheet
	var beh := s.behavior
	if beh == "passive":
		return {}
	var targets: Array = w.hostiles_of(a)
	var align := Game.state.alignment
	# Support: keep the party standing.
	if beh == "support" or beh == "ranged" or beh == "aggressive":
		var thresh := 0.5 if beh == "support" else 0.3
		var hurt := _hurt_ally(a, w, thresh)
		if hurt == null and s.hp < s.max_hp() * thresh:
			hurt = a
		if hurt != null:
			for pid in ["restore", "mend"]:
				if s.powers.has(pid) and ActionResolver.power_usable(s, pid, hurt.sheet, align) == "":
					return {"type": "power", "id": pid, "target": hurt.uid}
			if beh == "support" or hurt.sheet.hp < hurt.sheet.max_hp() * 0.25:
				var item := "repair_kit" if hurt.sheet.kind == "machine" else "medpac"
				if Game.state.inventory.count(item) > 0 and hurt.position.distance_to(a.position) < 10.0:
					return {"type": "item", "id": item, "target": hurt.uid}
	# Downed allies are revived with a medpac (or a repair kit for synthetics)
	# by any companion not set to passive; support companions also use
	# Restore/Mend first when it can revive.
	for o in w.party_actors():
		var oa: Actor = o
		if oa.sheet.is_downed() and not oa.sheet.dead and oa != a:
			var item2 := "repair_kit" if oa.sheet.kind == "machine" else "medpac"
			if Game.state.inventory.count(item2) > 0:
				return {"type": "item", "id": item2, "target": oa.uid}
	# Self-preservation: a badly hurt companion patches themself up.
	if s.hp < s.max_hp() * 0.3:
		var own := "repair_kit" if s.kind == "machine" else "medpac"
		if Game.state.inventory.count(own) > 0:
			return {"type": "item", "id": own, "target": a.uid}
	if targets.is_empty():
		return {}
	# Prefer the controlled character's target.
	var lead: Actor = w.controlled()
	var tgt: Actor = null
	if lead != null and w.valid_hostile_target(a, lead.target_uid):
		tgt = w.actors[lead.target_uid]
	if tgt == null:
		tgt = _pick_target(a, targets, "ranged" if beh == "ranged" else "melee", w)
	a.target_uid = tgt.uid
	# Weapon set preference.
	var prof := CombatRules.weapon_profile(s, "main")
	if beh == "ranged" and not bool(prof["ranged"]):
		var other: Variant = s.equipment.get("main2" if s.active_set == 0 else "main", null)
		if other != null and DB.dict(DB.item(String(other["id"])), "weapon").get("category", "") in ["pistol", "rifle"]:
			return {"type": "swap"}
	if beh == "aggressive" and bool(prof["ranged"]) and tgt.position.distance_to(a.position) < 5.0:
		var other2: Variant = s.equipment.get("main2" if s.active_set == 0 else "main", null)
		if other2 != null and DB.dict(DB.item(String(other2["id"])), "weapon").get("category", "") == "melee":
			return {"type": "swap"}
	# Tav-7 favours ion against machines when available.
	if tgt.sheet.kind == "machine" and s.powers.has("disrupt") and ActionResolver.power_usable(s, "disrupt", tgt.sheet, align) == "" and _chance(0.5):
		return {"type": "power", "id": "disrupt", "target": tgt.uid}
	var tactical := _tactical_choice(a, w, tgt, targets, align)
	if not tactical.is_empty():
		return tactical
	for f in s.action_feats():
		if ActionResolver.feat_usable(s, f, tgt.sheet) == "" and _chance(0.5):
			var fd: Dictionary = DB.feat(f)
			var k := String(DB.dict(fd, "action").get("kind", "melee"))
			if k == "self_area_machine":
				var near := 0
				for t in targets:
					if (t as Actor).sheet.kind == "machine" and (t as Actor).position.distance_to(a.position) <= 8.0:
						near += 1
				if near >= 2:
					return {"type": "feat", "id": f}
				continue
			if k == "self":
				return {"type": "feat", "id": f}
			return {"type": "feat", "id": f, "target": tgt.uid}
	return {"type": "attack", "target": tgt.uid}


## Powers, grenades and buffs worth spending a round on. Kept conservative so
## companions do not drain the party's consumables: grenades only into a
## cluster, control powers only on healthy targets, buffs once per fight.
static func _tactical_choice(a: Actor, w: World, tgt: Actor, targets: Array, align: int) -> Dictionary:
	var s := a.sheet
	var reserve := 4 if (s.powers.has("mend") or s.powers.has("restore")) else 0
	# Self buffs at the start of a fight.
	for buff in ["aegis", "aegis_greater"]:
		if s.powers.has(buff) and not s.has_status(buff) and not s.has_status("aegis") and not s.has_status("aegis_greater") \
				and ActionResolver.power_usable(s, buff, null, align) == "" and _chance(0.6):
			return {"type": "power", "id": buff}
	# Area grenades into clusters, never close enough to catch ourselves.
	var cl := _cluster(tgt, targets, 3.0)
	var dist := tgt.position.distance_to(a.position)
	if cl >= 1 and dist > 4.5:
		var nade := ""
		var machines := 0
		for t in targets:
			if (t as Actor).sheet.kind == "machine" and (t as Actor).position.distance_to(tgt.position) <= 3.0:
				machines += 1
		if not _friendly_clear(a, w, tgt.position, 3.5):
			nade = ""
		elif machines >= 2 and Game.state.inventory.count("ion_grenade") > 0:
			nade = "ion_grenade"
		elif Game.state.inventory.count("frag_grenade") > 0:
			nade = "frag_grenade"
		if nade != "" and _chance(0.5) and ActionResolver.item_usable(s, nade, tgt.sheet, Game.state.inventory) == "":
			return {"type": "item", "id": nade, "target": tgt.uid}
	# Offensive and control powers.
	var tf := float(tgt.sheet.hp) / float(maxi(1, tgt.sheet.max_hp()))
	var options: Array = []
	for pid in ["stasis_field", "hold", "arc_storm", "arc_lance", "siphon", "shockwave", "shove", "dread", "sway"]:
		if not s.powers.has(pid):
			continue
		var pd: Dictionary = DB.power(pid)
		var cost := int(s.power_cost(pid, align)["cost"])
		if s.energy - cost < reserve:
			continue
		if pid == "shockwave":
			var near := 0
			for t in targets:
				if (t as Actor).position.distance_to(a.position) <= 4.0:
					near += 1
			if near >= 2 and ActionResolver.power_usable(s, pid, null, align) == "":
				options.append({"type": "power", "id": pid})
			continue
		if ActionResolver.power_usable(s, pid, tgt.sheet, align) != "":
			continue
		if pd.has("status_on_fail") and not pd.has("damage"):
			# Control: worth it on a healthy, dangerous target not already controlled.
			if tf < 0.5 or tgt.sheet.has_status(String(pd["status_on_fail"]["id"])):
				continue
			if pid == "stasis_field" and cl < 1:
				continue
		options.append({"type": "power", "id": pid, "target": tgt.uid})
	if not options.is_empty() and _chance(0.55):
		return options[0]
	return {}


## True when no party member stands within r of p (grenade safety).
static func _friendly_clear(a: Actor, w: World, p: Vector3, r: float) -> bool:
	for o in w.party_actors():
		if (o as Actor).position.distance_to(p) <= r:
			return false
	return true
