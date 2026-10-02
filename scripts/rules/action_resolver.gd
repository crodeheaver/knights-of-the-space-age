class_name ActionResolver
extends RefCounted
## Resolves one queued action exactly once and applies its results to the
## authoritative sheets. The world supplies validated context (targets in range,
## area targets) and then presents the returned events. Nothing outside this
## class decides hits, damage, saves or status application for actions.
##
## ctx keys: target (CharacterSheet|null), area_targets (Array), chain_targets
## (Array), alignment (int), difficulty (String), inventory (Inventory|null),
## sneak (bool: attacker unseen), party_uids (Array)


# ------------------------------------------------------------ validation
static func feat_usable(actor: CharacterSheet, feat_id: String, target: CharacterSheet) -> String:
	var fd: Dictionary = DB.feat(feat_id)
	if not actor.feats.has(feat_id) or not fd.has("action"):
		return "%s does not know %s." % [actor.display_name, fd.get("name", feat_id)]
	var act: Dictionary = fd["action"]
	if actor.cooldowns.has("feat:" + feat_id):
		return "%s is recharging (%.0fs)." % [fd["name"], float(actor.cooldowns["feat:" + feat_id])]
	var k := String(act.get("kind", "melee"))
	if k == "melee" or k == "ranged":
		var prof := CombatRules.weapon_profile(actor, "main")
		if k == "melee" and bool(prof["ranged"]):
			return "%s needs a melee weapon in the main hand." % fd["name"]
		if k == "ranged" and not bool(prof["ranged"]):
			return "%s needs a pistol or rifle." % fd["name"]
		if target == null:
			return "Select a target."
	if fd.has("prereq") and DB.dict(fd, "prereq").get("kind", "") != "" and String(fd["prereq"]["kind"]) != actor.kind:
		return "Only usable by %s characters." % fd["prereq"]["kind"]
	return ""


static func power_usable(actor: CharacterSheet, pid: String, target: CharacterSheet, alignment: int) -> String:
	var pd: Dictionary = DB.power(pid)
	if pd.is_empty() or not actor.powers.has(pid):
		return "%s does not know that power." % actor.display_name
	if actor.cooldowns.has("power:" + pid):
		return "%s is recharging (%.0fs)." % [pd["name"], float(actor.cooldowns["power:" + pid])]
	var c := actor.power_cost(pid, alignment)
	if bool(c["blocked"]):
		return String(c["reason"])
	if actor.energy < int(c["cost"]):
		return "Not enough energy (%d needed, %d available)." % [int(c["cost"]), actor.energy]
	var tgt := String(pd.get("target", "enemy"))
	if tgt in ["enemy", "area_enemy", "ally"]:
		if target == null and tgt != "ally":
			return "Select a target."
	if target != null and tgt == "enemy":
		if bool(pd.get("organic_only", false)) and target.kind == "machine":
			return "%s only works on organic targets." % pd["name"]
		if pd.has("status_on_fail") and not pd.has("damage"):
			var sid := String(pd["status_on_fail"]["id"])
			if DB.arr(DB.status(sid), "immune_kinds").has(target.kind):
				return "%s is immune to %s." % [target.display_name, DB.status(sid).get("name", sid)]
	if target != null and tgt == "ally":
		if bool(pd.get("machine_only_heal", false)) and target.kind != "machine":
			return "Only repairs machines."
		if target.is_downed() and pd.has("heal"):
			return "%s is down; heal them after the fight or with a medpac." % target.display_name
	return ""


static func item_usable(actor: CharacterSheet, item_id: String, target: CharacterSheet, inventory: Inventory) -> String:
	var it: Dictionary = DB.item(item_id)
	if it.is_empty():
		return "Unknown item."
	if not _has_item(actor, item_id, inventory):
		return "No %s left." % it.get("name", item_id)
	var t := String(it.get("type", ""))
	if t == "consumable":
		var use: Dictionary = it.get("use", {})
		var tk := String(use.get("kind", ""))
		if tk != "" and actor.kind != tk and String(use.get("target", "self")) == "self":
			return "%s cannot use %s." % [actor.display_name, it["name"]]
		var hk := String(use.get("heal_kind", ""))
		var tgt: CharacterSheet = target if target != null else actor
		if hk != "" and tgt.kind != hk:
			return "%s only works on %s patients." % [it["name"], "machine" if hk == "machine" else "organic"]
		if use.has("energy") and not actor.has_resonance():
			return "%s has no Resonance to restore." % actor.display_name
	elif t != "grenade" and t != "mine":
		return "%s cannot be used in combat." % it.get("name", item_id)
	return ""


static func _has_item(actor: CharacterSheet, item_id: String, inventory: Inventory) -> bool:
	if actor.faction == "party" and inventory != null:
		return inventory.count(item_id) > 0
	return int(actor.kit.get(item_id, 0)) > 0


static func _consume(actor: CharacterSheet, item_id: String, inventory: Inventory) -> bool:
	if actor.faction == "party" and inventory != null:
		return inventory.remove(item_id, 1)
	if int(actor.kit.get(item_id, 0)) > 0:
		actor.kit[item_id] = int(actor.kit[item_id]) - 1
		return true
	return false


# ------------------------------------------------------------ entry point
static func resolve(action: Dictionary, actor: CharacterSheet, ctx: Dictionary, dice: Dice) -> Dictionary:
	var out := {"ok": false, "reason": "", "events": [], "log": [], "downed": [], "action": action}
	if not actor.can_act():
		out["reason"] = "%s cannot act." % actor.display_name
		return out
	var target: CharacterSheet = ctx.get("target", null)
	match String(action.get("type", "attack")):
		"attack":
			if target == null or target.is_downed() or target.dead:
				out["reason"] = "No valid target."
				return out
			if not actor.can_attack():
				out["reason"] = "%s cannot attack right now." % actor.display_name
				return out
			_do_attacks(actor, target, {}, ctx, dice, out, true)
			out["ok"] = true
		"feat":
			_do_feat(actor, String(action["id"]), target, ctx, dice, out)
		"power":
			_do_power(actor, String(action["id"]), target, ctx, dice, out)
		"item":
			_do_item(actor, String(action["id"]), target, ctx, dice, out)
		"swap":
			actor.active_set = 1 - actor.active_set
			actor.mark_dirty()
			out["ok"] = true
			out["log"].append("%s swaps to weapon set %d (%s)." % [actor.display_name, actor.active_set + 1, CombatRules.weapon_profile(actor, "main")["name"]])
			out["events"].append({"type": "swap", "actor": actor.uid})
		_:
			out["reason"] = "Unknown action."
	return out


# ------------------------------------------------------------ attacks
static func _do_attacks(actor: CharacterSheet, target: CharacterSheet, act: Dictionary, ctx: Dictionary, dice: Dice, out: Dictionary, include_offhand: bool) -> void:
	var opts := {
		"attack_mod": int(act.get("attack_mod", 0)), "damage_bonus": int(act.get("damage_bonus", 0)),
		"threat_mult": int(act.get("threat_mult", 1)), "crit_mult_bonus": int(act.get("crit_mult_bonus", 0)),
		"sneak": bool(ctx.get("sneak", false)), "difficulty": String(ctx.get("difficulty", "standard")),
		"label": String(act.get("label", "Action")),
	}
	var swings: Array = [["main", opts]]
	for i in int(act.get("extra_attacks", 0)):
		swings.append(["main", opts])
	if include_offhand and actor.is_dual_wielding():
		swings.append(["off", opts])
	var first := true
	for sw in swings:
		if target.is_downed() or target.dead:
			break
		var o: Dictionary = (sw[1] as Dictionary).duplicate()
		if not first:
			o["sneak"] = false
		first = false
		var prof := CombatRules.weapon_profile(actor, String(sw[0]))
		var r := CombatRules.resolve_attack(actor, target, prof, o, dice)
		var ev := {"type": "attack", "attacker": actor.uid, "target": target.uid, "result": r, "ranged": prof["ranged"], "sound": prof["sound"], "dtype": prof["dtype"]}
		var line := "%s → %s (%s): d20 %d %s = %d vs DEF %d" % [actor.display_name, target.display_name, prof["name"], r["natural"], Rules.signed(int(r["bonus"])), r["total"], r["defense"]]
		if bool(r["deflected"]):
			line += " — DEFLECTED by %s (d20 %d → %d)" % [target.display_name, int(r["deflect_roll"]), int(r["deflect_total"])]
		elif bool(r["hit"]):
			var dmg := CombatRules.apply_damage(target, r["components"], {"difficulty": ctx.get("difficulty", "standard")})
			ev["damage"] = dmg
			line += " — %s%s for %d (%s)" % ["CRITICAL HIT" if r["crit"] else "HIT", " (threat, unconfirmed)" if (r["threat"] and not r["crit"]) else "", int(dmg["dealt"]), r["damage_text"]]
			if int(dmg["absorbed"]) > 0:
				line += ", %d absorbed" % int(dmg["absorbed"])
			if int(dmg["resisted"]) > 0:
				line += ", %d resisted" % int(dmg["resisted"])
			if bool(dmg["downed"]):
				out["downed"].append(target.uid)
				line += " — %s is DOWN" % target.display_name
			var cs := Prestige.crit_status(actor)
			if bool(r["crit"]) and not cs.is_empty() and not bool(prof["ranged"]) and not bool(dmg["downed"]):
				var csr := StatusRules.apply(target, String(cs["id"]), float(cs["duration"]), actor.uid)
				out["events"].append({"type": "status", "target": target.uid, "id": cs["id"], "result": csr})
				if bool(csr["applied"]):
					line += " [Terror Strike: %s]" % DB.status(String(cs["id"])).get("name", cs["id"])
			if act.has("on_hit_status") and not bool(dmg["downed"]):
				var hs: Dictionary = act["on_hit_status"]
				var sr := StatusRules.apply(target, String(hs["id"]), float(hs.get("duration", 3.0)), actor.uid)
				out["events"].append({"type": "status", "target": target.uid, "id": hs["id"], "result": sr})
				if bool(sr["applied"]):
					line += " [%s]" % DB.status(String(hs["id"])).get("name", hs["id"])
		else:
			line += " — MISS" + (" (natural 1)" if int(r["natural"]) == 1 else "")
		ev["text"] = line
		ev["detail"] = "Attack: " + CombatRules.parts_text(r["parts"]) + " | Defense: " + CombatRules.parts_text(r["def_parts"])
		out["events"].append(ev)
		out["log"].append(line)


static func _do_feat(actor: CharacterSheet, feat_id: String, target: CharacterSheet, ctx: Dictionary, dice: Dice, out: Dictionary) -> void:
	var reason := feat_usable(actor, feat_id, target)
	if reason != "":
		out["reason"] = reason
		return
	var fd: Dictionary = DB.feat(feat_id)
	var act: Dictionary = (fd["action"] as Dictionary).duplicate(true)
	act["label"] = String(fd["name"])
	var k := String(act.get("kind", "melee"))
	if k == "melee" or k == "ranged":
		if target == null or target.is_downed():
			out["reason"] = "No valid target."
			return
		if not actor.can_attack():
			out["reason"] = "%s cannot attack right now." % actor.display_name
			return
		out["log"].append("%s uses %s." % [actor.display_name, fd["name"]])
		_do_attacks(actor, target, act, ctx, dice, out, true)
	elif k == "self_area_machine":
		out["log"].append("%s uses %s." % [actor.display_name, fd["name"]])
		for t in ctx.get("area_targets", []):
			var ts: CharacterSheet = t
			if ts.kind != "machine" or ts.is_downed():
				continue
			var sv := CombatRules.saving_throw(ts, String(act.get("save", "will")), int(act.get("dc", 14)), dice)
			out["events"].append({"type": "save", "target": ts.uid, "result": sv})
			var line := "  %s %s save d20 %d %s = %d vs DC %d: %s" % [ts.display_name, Rules.SAVE_NAMES[sv["save"]], sv["natural"], Rules.signed(int(sv["bonus"])), sv["total"], sv["dc"], "resisted" if sv["success"] else "failed"]
			if not bool(sv["success"]):
				var so: Dictionary = act["status_on_fail"]
				var sr := StatusRules.apply(ts, String(so["id"]), float(so["duration"]), actor.uid)
				out["events"].append({"type": "status", "target": ts.uid, "id": so["id"], "result": sr})
			out["log"].append(line)
	if act.has("self_status"):
		var ss: Dictionary = act["self_status"]
		var opts := {}
		if ss.has("mods"):
			opts["mods"] = ss["mods"]
		var sr2 := StatusRules.apply(actor, String(ss["id"]), float(ss.get("duration", 3.0)), actor.uid, opts)
		out["events"].append({"type": "status", "target": actor.uid, "id": ss["id"], "result": sr2})
		if k == "self":
			out["log"].append("%s uses %s." % [actor.display_name, fd["name"]])
	if act.has("cooldown"):
		actor.cooldowns["feat:" + feat_id] = float(act["cooldown"])
	out["ok"] = true


# ------------------------------------------------------------ powers
static func _do_power(actor: CharacterSheet, pid: String, target: CharacterSheet, ctx: Dictionary, dice: Dice, out: Dictionary) -> void:
	var alignment := int(ctx.get("alignment", 0))
	var reason := power_usable(actor, pid, target, alignment)
	if reason != "":
		out["reason"] = reason
		return
	var pd: Dictionary = DB.power(pid)
	var cost := int(actor.power_cost(pid, alignment)["cost"])
	actor.energy -= cost
	out["energy_spent"] = cost
	if pd.has("cooldown"):
		actor.cooldowns["power:" + pid] = float(pd["cooldown"])
	var tmode := String(pd.get("target", "enemy"))
	var targets: Array = []
	match tmode:
		"self":
			targets = [actor]
		"ally":
			targets = [target if target != null else actor]
		"party":
			targets = ctx.get("area_targets", [actor])
		"enemy":
			if pd.has("chain_targets"):
				targets = ctx.get("chain_targets", [target])
			else:
				targets = [target]
		"area_enemy", "self_area":
			targets = ctx.get("area_targets", [])
	out["log"].append("%s channels %s (%d energy)." % [actor.display_name, pd["name"], cost])
	out["events"].append({"type": "cast", "actor": actor.uid, "power": pid, "target": target.uid if target != null else ""})
	var dc := int(pd.get("dc", actor.power_dc(String(pd.get("school", "universal")))))
	var drained := 0
	for t in targets:
		if t == null:
			continue
		var ts: CharacterSheet = t
		if ts.dead or (ts.is_downed() and not pd.has("heal")):
			continue
		var failed := true
		var line := ""
		if pd.has("save"):
			var sv := CombatRules.saving_throw(ts, String(pd["save"]), dc, dice)
			failed = not bool(sv["success"])
			out["events"].append({"type": "save", "target": ts.uid, "result": sv})
			line = "  %s %s save d20 %d %s = %d vs DC %d: %s." % [ts.display_name, Rules.SAVE_NAMES[sv["save"]], sv["natural"], Rules.signed(int(sv["bonus"])), sv["total"], dc, "failed" if failed else "resisted"]
		if pd.has("damage"):
			if bool(pd.get("organic_only", false)) and ts.kind == "machine":
				pass
			else:
				var dd: Dictionary = pd["damage"]
				var r := dice.roll_expr(String(dd["dice"]))
				var amt := int(r["total"]) + int(dd.get("per_level", 0)) * actor.level
				if not failed and bool(pd.get("save_half", false)):
					amt = floori(amt / 2.0)
				elif not failed and not bool(pd.get("save_half", false)) and pd.has("save") and not pd.has("status_on_fail") and not pd.has("machine_status_on_fail") and not pd.has("push"):
					amt = 0
				if amt > 0:
					var dmg := CombatRules.apply_damage(ts, [{"amount": amt, "dtype": String(dd.get("type", "resonance"))}], {"difficulty": ctx.get("difficulty", "standard")})
					out["events"].append({"type": "damage", "target": ts.uid, "result": dmg, "dtype": dd.get("type", "resonance"), "source": actor.uid})
					line += "  %s takes %d %s damage (%s rolled %d)." % [ts.display_name, int(dmg["dealt"]), dd.get("type", "resonance"), dd["dice"], int(r["total"])]
					drained += int(dmg["dealt"])
					if bool(dmg["downed"]):
						out["downed"].append(ts.uid)
						line += " %s is DOWN." % ts.display_name
		if pd.has("heal"):
			var hd: Dictionary = pd["heal"]
			if bool(pd.get("machine_only_heal", false)) and ts.kind != "machine":
				pass
			elif not ts.is_downed():
				var hr := dice.roll_expr(String(hd["dice"]))
				var amt2 := int(hr["total"]) + int(hd.get("per_level", 0)) * actor.level + actor.amod(String(hd.get("attr", "wis")))
				amt2 = int(floor(amt2 * Prestige.heal_mult(actor)))
				var healed := CombatRules.heal(ts, amt2)
				out["events"].append({"type": "heal", "target": ts.uid, "amount": healed})
				line += "  %s recovers %d health." % [ts.display_name, healed]
		if pd.has("cleanse"):
			var rem := StatusRules.cleanse(ts, pd["cleanse"])
			if not rem.is_empty():
				line += "  Purged: %s." % ", ".join(PackedStringArray(rem))
		if pd.has("cleanse_target"):
			StatusRules.cleanse(ts, pd["cleanse_target"])
		if pd.has("status"):
			var st: Dictionary = pd["status"]
			var sr := StatusRules.apply(ts, String(st["id"]), float(st["duration"]), actor.uid)
			out["events"].append({"type": "status", "target": ts.uid, "id": st["id"], "result": sr})
			line += "  %s: %s%s." % [ts.display_name, DB.status(String(st["id"])).get("name", st["id"]), "" if sr["applied"] else " (%s)" % sr["reason"]]
		if failed and not ts.is_downed():
			if pd.has("status_on_fail"):
				var so: Dictionary = pd["status_on_fail"]
				var sr2 := StatusRules.apply(ts, String(so["id"]), float(so["duration"]), actor.uid)
				out["events"].append({"type": "status", "target": ts.uid, "id": so["id"], "result": sr2})
				line += "  %s %s." % [ts.display_name, ("is " + String(DB.status(String(so["id"])).get("name", so["id"])).to_lower()) if sr2["applied"] else "is unaffected (%s)" % sr2["reason"]]
			if pd.has("machine_status_on_fail") and ts.kind == "machine":
				var so2: Dictionary = pd["machine_status_on_fail"]
				var sr3 := StatusRules.apply(ts, String(so2["id"]), float(so2["duration"]), actor.uid)
				out["events"].append({"type": "status", "target": ts.uid, "id": so2["id"], "result": sr3})
				if sr3["applied"]:
					line += "  %s's systems lock up." % ts.display_name
			if pd.has("push"):
				out["events"].append({"type": "push", "target": ts.uid, "from": actor.uid, "distance": float(pd["push"])})
		if line != "":
			out["log"].append(line.strip_edges(false, true))
	if bool(pd.get("drain", false)) and drained > 0:
		var h := CombatRules.heal(actor, drained)
		out["events"].append({"type": "heal", "target": actor.uid, "amount": h})
		out["log"].append("  %s drains %d health." % [actor.display_name, h])
	if pd.has("reveal_radius"):
		out["events"].append({"type": "reveal", "actor": actor.uid, "radius": float(pd["reveal_radius"])})
	out["ok"] = true


# ------------------------------------------------------------ items
static func heal_amount_for_item(user: CharacterSheet, item_id: String, dice: Dice) -> Dictionary:
	var use: Dictionary = DB.item(item_id).get("use", {})
	var r := dice.roll_expr(String(use.get("heal", "0")))
	var base := int(r["total"])
	var sk := String(use.get("skill", ""))
	var skill_bonus := 0
	if sk != "":
		skill_bonus = maxi(0, floori(user.skill_total(sk) / 2.0))
	var mult := 1.0 + float(user.passive().get("heal_item_bonus", 0)) / 100.0
	var total := int(floor((base + skill_bonus) * mult))
	return {"total": total, "rolled": base, "skill_bonus": skill_bonus, "mult": mult}


static func _do_item(actor: CharacterSheet, item_id: String, target: CharacterSheet, ctx: Dictionary, dice: Dice, out: Dictionary) -> void:
	var inv: Inventory = ctx.get("inventory", null)
	var reason := item_usable(actor, item_id, target, inv)
	if reason != "":
		out["reason"] = reason
		return
	var it: Dictionary = DB.item(item_id)
	var t := String(it.get("type", ""))
	if t == "grenade":
		# Throwing consumes the grenade now; the world detonates it after a
		# short flight and calls resolve_explosion() once.
		_consume(actor, item_id, inv)
		out["events"].append({"type": "throw", "actor": actor.uid, "item": item_id, "target": target.uid if target != null else ""})
		out["log"].append("%s throws a %s." % [actor.display_name, it["name"]])
		out["ok"] = true
		return
	if t == "mine":
		_consume(actor, item_id, inv)
		out["events"].append({"type": "place_mine", "actor": actor.uid, "item": item_id})
		out["log"].append("%s places a %s. It arms in 2 seconds." % [actor.display_name, it["name"]])
		out["ok"] = true
		return
	var use: Dictionary = it.get("use", {})
	var tgt: CharacterSheet = actor
	if String(use.get("target", "self")) == "ally" and target != null:
		tgt = target
	var revive := tgt.is_downed() and use.has("heal")
	if revive:
		# Medpacs and repair kits can revive a downed ally (costs the action).
		StatusRules.remove(tgt, "downed")
	_consume(actor, item_id, inv)
	var line := "%s uses %s%s." % [actor.display_name, it["name"], (" on " + tgt.display_name) if tgt != actor else ""]
	if use.has("heal"):
		var ha := heal_amount_for_item(actor, item_id, dice)
		var healed := CombatRules.heal(tgt, maxi(1, int(ha["total"])), revive)
		out["events"].append({"type": "heal", "target": tgt.uid, "amount": healed, "revive": revive})
		if revive:
			line += " %s is back on their feet." % tgt.display_name
		line += " +%d health (rolled %d, +%d skill%s)." % [healed, ha["rolled"], ha["skill_bonus"], ", x%.1f" % ha["mult"] if ha["mult"] > 1.0 else ""]
	if use.has("cleanse"):
		StatusRules.cleanse(tgt, use["cleanse"])
	if use.has("status"):
		var st: Dictionary = use["status"]
		var sr := StatusRules.apply(tgt, String(st["id"]), float(st["duration"]), actor.uid)
		out["events"].append({"type": "status", "target": tgt.uid, "id": st["id"], "result": sr})
		line += " %s%s." % [DB.status(String(st["id"])).get("name", st["id"]), "" if sr["applied"] else " not applied: " + String(sr["reason"])]
	if use.has("energy"):
		var before := tgt.energy
		tgt.energy = mini(tgt.max_energy(), tgt.energy + int(use["energy"]))
		out["events"].append({"type": "energy", "target": tgt.uid, "amount": tgt.energy - before})
		line += " +%d energy." % (tgt.energy - before)
	out["log"].append(line)
	out["consumed"] = item_id
	out["ok"] = true


## Explosion from a grenade or mine. `targets` are all sheets inside the radius.
static func resolve_explosion(item_id: String, source_uid: String, targets: Array, ctx: Dictionary, dice: Dice) -> Dictionary:
	var it: Dictionary = DB.item(item_id)
	var spec: Dictionary = it.get("throw", it.get("mine", {}))
	var out := {"ok": true, "events": [], "log": [], "downed": []}
	out["log"].append("%s detonates." % it.get("name", item_id))
	for t in targets:
		var ts: CharacterSheet = t
		if ts.dead or ts.is_downed():
			continue
		if bool(spec.get("organic_only", false)) and ts.kind == "machine":
			continue
		var failed := true
		var line := ""
		if spec.has("save"):
			var sv := CombatRules.saving_throw(ts, String(spec["save"]), int(spec.get("dc", 14)), dice)
			failed = not bool(sv["success"])
			out["events"].append({"type": "save", "target": ts.uid, "result": sv})
			line = "  %s %s save d20 %d %s = %d vs DC %d: %s." % [ts.display_name, Rules.SAVE_NAMES[sv["save"]], sv["natural"], Rules.signed(int(sv["bonus"])), sv["total"], sv["dc"], "failed" if failed else "succeeded"]
		if spec.has("dice"):
			var r := dice.roll_expr(String(spec["dice"]))
			var amt := int(r["total"])
			if not failed and bool(spec.get("half", false)):
				amt = floori(amt / 2.0)
			var dmg := CombatRules.apply_damage(ts, [{"amount": amt, "dtype": String(spec.get("dtype", "kinetic"))}], {"difficulty": ctx.get("difficulty", "standard")})
			out["events"].append({"type": "damage", "target": ts.uid, "result": dmg, "dtype": spec.get("dtype", "kinetic"), "source": source_uid})
			line += "  %s takes %d %s." % [ts.display_name, int(dmg["dealt"]), spec.get("dtype", "kinetic")]
			if bool(dmg["downed"]):
				out["downed"].append(ts.uid)
				line += " DOWN."
		if failed and not ts.is_downed():
			for key in ["status_on_fail", "machine_status_on_fail"]:
				if spec.has(key) and (key == "status_on_fail" or ts.kind == "machine"):
					var so: Dictionary = spec[key]
					var sr := StatusRules.apply(ts, String(so["id"]), float(so["duration"]), source_uid)
					out["events"].append({"type": "status", "target": ts.uid, "id": so["id"], "result": sr})
					if sr["applied"]:
						line += " %s." % DB.status(String(so["id"])).get("name", so["id"])
		out["log"].append(line)
	return out
