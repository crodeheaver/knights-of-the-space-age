class_name CombatRules
extends RefCounted
## Attack, damage, save and skill-check resolution. Pure rules: operates on
## CharacterSheets and a seeded Dice and returns detailed result dictionaries
## (rolls and every modifier) for the combat log. Natural 1/20 rules apply
## ONLY to attack rolls and critical confirmations, never to saves or skills.

const STORY_ENEMY_ATTACK := -2
const STORY_PARTY_DAMAGE_TAKEN := 0.6


# ------------------------------------------------------------ weapons
static func weapon_profile(sheet: CharacterSheet, hand: String) -> Dictionary:
	var inst: Variant = sheet.weapon_inst(hand)
	var id := "unarmed"
	var ups: Array = []
	if inst != null:
		id = String(inst["id"])
		ups = inst.get("upgrades", [])
	var it: Dictionary = DB.item(id)
	var w: Dictionary = DB.dict(it, "weapon")
	var cat := String(w.get("category", "melee"))
	var p := {
		"id": id, "name": String(it.get("name", id)), "category": cat, "prof": String(w.get("prof", "melee")),
		"hands": int(w.get("hands", 1)), "dice": String(w.get("dice", "1d3")), "dtype": String(w.get("dtype", "kinetic")),
		"threat": int(w.get("threat", 20)), "crit_mult": int(w.get("crit_mult", 2)), "range": float(w.get("range", 1.8)),
		"attack": int(w.get("attack", 0)), "damage": int(w.get("damage", 0)), "extra": [],
		"light": bool(w.get("light", false)), "finesse": bool(w.get("finesse", false)) or bool(w.get("energy_blade", false)),
		"energy_blade": bool(w.get("energy_blade", false)), "ranged": cat == "pistol" or cat == "rifle",
		"sound": String(w.get("sound", "blade")), "hand": hand,
	}
	if w.has("extra"):
		p["extra"].append({"dice": String(w["extra"]["dice"]), "dtype": String(w["extra"]["dtype"])})
	for u in ups:
		var wm: Dictionary = DB.dict(DB.dict(DB.item(String(u)), "upgrade"), "weapon_mods")
		p["attack"] = int(p["attack"]) + int(wm.get("attack", 0))
		p["damage"] = int(p["damage"]) + int(wm.get("damage", 0))
		if wm.has("extra"):
			p["extra"].append({"dice": String(wm["extra"]["dice"]), "dtype": String(wm["extra"]["dtype"])})
	return p


static func is_proficient(sheet: CharacterSheet, prof: Dictionary) -> bool:
	var pr := String(prof["prof"])
	if pr == "natural" or prof["id"] == "unarmed":
		return true
	return (sheet.passive().get("weapon_prof", []) as Array).has(pr)


static func dual_penalties(sheet: CharacterSheet) -> Vector2i:
	## x = main-hand penalty, y = off-hand penalty (both <= 0).
	if not sheet.is_dual_wielding():
		return Vector2i.ZERO
	var rank := int(sheet.passive().get("twf_rank", 0))
	var main := -6 + 2 * rank
	var off := -10 + 2 * rank
	var offp := weapon_profile(sheet, "off")
	if bool(offp["light"]):
		main += 2
		off += 2
	return Vector2i(main, off)


# ------------------------------------------------------------ attack bonus
## opts: attack_mod (action), difficulty, label
static func attack_parts(sheet: CharacterSheet, prof: Dictionary, opts: Dictionary = {}) -> Array:
	var parts: Array = [["BAB", sheet.bab()]]
	if bool(prof["ranged"]):
		parts.append(["DEX", sheet.amod("dex")])
	elif bool(prof["finesse"]):
		var s := sheet.amod("str")
		var d := sheet.amod("dex")
		parts.append(["DEX (finesse)" if d > s else "STR", maxi(s, d)])
	else:
		parts.append(["STR", sheet.amod("str")])
	if int(prof["attack"]) != 0:
		parts.append(["Weapon", int(prof["attack"])])
	if not is_proficient(sheet, prof):
		parts.append(["Not proficient", -4])
	var pas := sheet.passive()
	var g := sheet.gear()
	if bool(prof["ranged"]):
		if int(pas.get("attack_ranged", 0)) != 0:
			parts.append(["Weapon Focus", int(pas["attack_ranged"])])
		if int(g.get("attack_ranged", 0)) != 0:
			parts.append(["Gear", int(g["attack_ranged"])])
	else:
		if int(pas.get("attack_melee", 0)) != 0:
			parts.append(["Weapon Focus", int(pas["attack_melee"])])
		if int(g.get("attack_melee", 0)) != 0:
			parts.append(["Gear", int(g["attack_melee"])])
		if int(pas.get("dueling", 0)) > 0 and sheet.is_dueling_stance():
			parts.append(["Dueling", 1])
	var dp := dual_penalties(sheet)
	if dp != Vector2i.ZERO:
		parts.append(["Dual wield (%s)" % ("off-hand" if prof["hand"] == "off" else "main"), dp.y if prof["hand"] == "off" else dp.x])
	var st := int(sheet.status_mods().get("attack", 0))
	if st != 0:
		parts.append(["Effects", st])
	var fm := int(sheet.form_mods().get("attack", 0))
	if fm != 0:
		parts.append(["Form", fm])
	if int(sheet.overrides.get("attack_bonus", 0)) != 0:
		parts.append(["Training", int(sheet.overrides["attack_bonus"])])
	if int(opts.get("attack_mod", 0)) != 0:
		parts.append([String(opts.get("label", "Action")), int(opts["attack_mod"])])
	if String(opts.get("difficulty", "standard")) == "story" and sheet.faction != "party":
		parts.append(["Story difficulty", STORY_ENEMY_ATTACK])
	return parts


static func sum_parts(parts: Array) -> int:
	var t := 0
	for p in parts:
		t += int(p[1])
	return t


static func parts_text(parts: Array) -> String:
	var bits: PackedStringArray = []
	for p in parts:
		if int(p[1]) != 0 or p[0] == "BAB":
			bits.append("%s %s" % [Rules.signed(int(p[1])), p[0]])
	return ", ".join(bits)


# ------------------------------------------------------------ attack
## Resolve one attack roll and its damage. Does NOT apply damage.
## opts: attack_mod, damage_bonus, threat_mult, crit_mult_bonus, sneak (bool:
## target unaware), difficulty, label
static func resolve_attack(attacker: CharacterSheet, defender: CharacterSheet, prof: Dictionary, opts: Dictionary, dice: Dice) -> Dictionary:
	var parts := attack_parts(attacker, prof, opts)
	var bonus := sum_parts(parts)
	var def_parts := defender.defense_parts()
	var defense := sum_parts(def_parts)
	var natural := dice.d20()
	var total := natural + bonus
	var hit := natural == 20 or (natural != 1 and total >= defense)
	var res := {
		"attacker": attacker.uid, "defender": defender.uid, "weapon": prof["name"], "hand": prof["hand"],
		"natural": natural, "bonus": bonus, "total": total, "defense": defense, "parts": parts, "def_parts": def_parts,
		"hit": hit, "crit": false, "threat": false, "confirm": 0, "deflected": false, "components": [], "damage_text": "",
	}
	if not hit:
		return res
	# Bolt deflection: energy-blade wielders with the feat vs ranged energy bolts.
	if bool(prof["ranged"]) and String(prof["dtype"]) == "energy":
		var dr := int(defender.passive().get("deflect_rank", 0))
		if dr > 0 and defender.can_act() and not defender.is_flat_footed():
			var dprof := weapon_profile(defender, "main")
			if bool(dprof["energy_blade"]):
				var dnat := dice.d20()
				var dbonus := (5 if dr == 1 else 9) + defender.amod("dex")
				res["deflect_roll"] = dnat
				res["deflect_total"] = dnat + dbonus
				if dnat + dbonus >= total:
					res["deflected"] = true
					res["hit"] = false
					return res
	# Critical threat and confirmation.
	var threat_size := (21 - int(prof["threat"])) * int(opts.get("threat_mult", 1))
	var threat_min := 21 - threat_size
	if natural >= threat_min:
		res["threat"] = true
		var c := dice.d20()
		res["confirm"] = c
		if c == 20 or (c != 1 and c + bonus >= defense):
			res["crit"] = true
	var mult := (int(prof["crit_mult"]) + int(opts.get("crit_mult_bonus", 0))) if res["crit"] else 1
	# Damage.
	var dp := Rules.parse_dice(String(prof["dice"]))
	var rolls: Array[int] = []
	for i in mult:
		rolls.append_array(dice.roll_dice(int(dp["count"]), int(dp["sides"])))
	var weapon_dmg := int(dp["bonus"]) * mult
	for r in rolls:
		weapon_dmg += r
	var static_parts: Array = []
	if not bool(prof["ranged"]):
		var sm := attacker.amod("str")
		if prof["hand"] == "off":
			sm = floori(sm / 2.0) if sm > 0 else sm
		elif int(prof["hands"]) == 2 and sm > 0:
			sm = floori(sm * 1.5)
		static_parts.append(["STR", sm])
	if int(prof["damage"]) != 0:
		static_parts.append(["Weapon", int(prof["damage"])])
	if int(opts.get("damage_bonus", 0)) != 0:
		static_parts.append([String(opts.get("label", "Action")), int(opts["damage_bonus"])])
	var sd := int(attacker.status_mods().get("damage", 0))
	if sd != 0:
		static_parts.append(["Effects", sd])
	var fd := int(attacker.form_mods().get("damage", 0))
	if fd != 0:
		static_parts.append(["Form", fd])
	var static_total := sum_parts(static_parts) * mult
	var main_amount := maxi(1, weapon_dmg + static_total)
	var comps: Array = [{"amount": main_amount, "dtype": String(prof["dtype"])}]
	var roll_strs: PackedStringArray = []
	for r in rolls:
		roll_strs.append(str(r))
	var txt := "%s%s(%s)%s" % [prof["dice"], (" x%d" % mult) if mult > 1 else "", ",".join(roll_strs), (" %s" % Rules.signed(static_total)) if static_total != 0 else ""]
	for e in prof["extra"]:
		var er := dice.roll_expr(String(e["dice"]))
		comps.append({"amount": int(er["total"]), "dtype": String(e["dtype"])})
		txt += " + %s(%d) %s" % [e["dice"], int(er["total"]), e["dtype"]]
	var sneak_n := int(attacker.passive().get("sneak_dice", 0))
	if sneak_n > 0:
		sneak_n += Prestige.sneak_bonus(attacker)
	if sneak_n > 0 and (bool(opts.get("sneak", false)) or defender.is_flat_footed() or defender.has_status("feared")):
		var sr := dice.roll_dice(sneak_n, 6)
		var stotal := 0
		for r in sr:
			stotal += r
		comps.append({"amount": stotal, "dtype": String(prof["dtype"]), "sneak": true})
		txt += " + sneak %dd6(%d)" % [sneak_n, stotal]
		res["sneak"] = true
	res["components"] = comps
	res["damage_text"] = txt
	res["static_parts"] = static_parts
	return res


# ------------------------------------------------------------ damage
## Applies damage components to a sheet. Order per component: creature-kind
## multiplier (ion/toxic), flat resistance, difficulty scaling, then shield
## absorption, then health. Returns totals and whether the target went down.
static func apply_damage(sheet: CharacterSheet, components: Array, opts: Dictionary = {}) -> Dictionary:
	var res := {"dealt": 0, "absorbed": 0, "resisted": 0, "hp_before": sheet.hp, "hp_after": sheet.hp, "downed": false, "parts": [], "broke": []}
	if sheet.dead or sheet.is_downed():
		res["ignored"] = true
		return res
	var resist: Dictionary = sheet.overrides.get("resist", {})
	var immune := sheet.immunities()
	var scale := 1.0
	if String(opts.get("difficulty", "standard")) == "story" and sheet.faction == "party":
		scale = STORY_PARTY_DAMAGE_TAKEN
	for c in components:
		var dtype := String(c["dtype"])
		var amt := float(c["amount"]) * Rules.kind_multiplier(dtype, sheet.kind)
		if dtype == "toxic" and immune.has("toxin"):
			amt = 0.0
		if dtype == "energy" and bool(c.get("shock", false)) and immune.has("shock"):
			amt = 0.0
		var a := floori(amt * scale)
		var dr := int(resist.get(dtype, 0))
		var after := maxi(0, a - dr)
		res["resisted"] = int(res["resisted"]) + (a - after)
		# Shield absorption.
		for s in sheet.statuses:
			if after <= 0:
				break
			if s.has("absorb_left") and int(s["absorb_left"]) > 0:
				var types: Array = DB.dict(DB.status(String(s["id"])), "absorb").get("types", [])
				if types.has(dtype):
					var take := mini(int(s["absorb_left"]), after)
					s["absorb_left"] = int(s["absorb_left"]) - take
					after -= take
					res["absorbed"] = int(res["absorbed"]) + take
		res["dealt"] = int(res["dealt"]) + after
		res["parts"].append({"dtype": dtype, "amount": after})
	# Exhausted shields expire.
	for i in range(sheet.statuses.size() - 1, -1, -1):
		var s2: Dictionary = sheet.statuses[i]
		if s2.has("absorb_left") and int(s2["absorb_left"]) <= 0:
			sheet.statuses.remove_at(i)
			sheet.mark_dirty()
	if int(res["dealt"]) > 0:
		sheet.hp -= int(res["dealt"])
		res["broke"] = StatusRules.on_damaged(sheet)
	if sheet.hp <= 0:
		sheet.hp = 0
		res["downed"] = true
	res["hp_after"] = sheet.hp
	return res


static func heal(sheet: CharacterSheet, amount: int, revive: bool = false) -> int:
	if sheet.dead:
		return 0
	if sheet.is_downed() and not revive:
		return 0
	if revive:
		StatusRules.remove(sheet, "downed")
	var before := sheet.hp
	sheet.hp = mini(sheet.max_hp(), sheet.hp + maxi(0, amount))
	return sheet.hp - before


# ------------------------------------------------------------ saves & skills
## Saving throw: d20 + save bonus vs DC. No automatic natural 1/20 results.
static func saving_throw(sheet: CharacterSheet, save_type: String, dc: int, dice: Dice) -> Dictionary:
	var nat := dice.d20()
	var bonus := sheet.save_total(save_type)
	return {"save": save_type, "natural": nat, "bonus": bonus, "total": nat + bonus, "dc": dc, "success": nat + bonus >= dc}


## Skill check: d20 + skill total (+bonus) vs DC. No automatic natural 1/20.
static func skill_check(sheet: CharacterSheet, skill: String, dc: int, dice: Dice, bonus: int = 0) -> Dictionary:
	var nat := dice.d20()
	var sb := sheet.skill_total(skill) + bonus
	var total := nat + sb
	return {"skill": skill, "actor": sheet.uid, "actor_name": sheet.display_name, "natural": nat, "bonus": sb, "total": total, "dc": dc, "success": total >= dc, "margin": total - dc}


static func hit_chance(attacker: CharacterSheet, defender: CharacterSheet, prof: Dictionary, opts: Dictionary = {}) -> int:
	var need := defender.defense() - sum_parts(attack_parts(attacker, prof, opts))
	var faces := clampi(21 - need, 1, 19)
	return int(round(faces * 5.0))
