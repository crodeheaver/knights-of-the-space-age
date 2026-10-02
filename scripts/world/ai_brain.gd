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
	# Downed allies can be revived with a medpac by support companions.
	if beh == "support":
		for o in w.party_actors():
			var oa: Actor = o
			if oa.sheet.is_downed() and not oa.sheet.dead:
				var item2 := "repair_kit" if oa.sheet.kind == "machine" else "medpac"
				if Game.state.inventory.count(item2) > 0:
					return {"type": "item", "id": item2, "target": oa.uid}
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
