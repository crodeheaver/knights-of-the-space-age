class_name CharacterSheet
extends RefCounted
## Authoritative character build and condition: attributes, skills, feats,
## powers, equipment, statuses and resources. Derived statistics are computed
## here (or in CombatRules for attacks) following the order in docs/RULES.md.

const SLOTS: Array[String] = ["head", "body", "hands", "belt", "implant", "wrist", "main", "off", "main2", "off2"]
const GEAR_SLOTS: Array[String] = ["head", "body", "hands", "belt", "implant", "wrist"]
const SLOT_NAMES := {"head": "Head", "body": "Body", "hands": "Hands", "belt": "Belt", "implant": "Implant", "wrist": "Wrist Device", "main": "Main Hand (Set 1)", "off": "Off-Hand (Set 1)", "main2": "Main Hand (Set 2)", "off2": "Off-Hand (Set 2)"}
const MACHINE_SLOT_NAMES := {"head": "Sensor Array", "body": "Chassis Plating", "hands": "Manipulators", "belt": "Utility Mount", "implant": "Core Module", "wrist": "Interface Port", "main": "Primary Tool (Set 1)", "off": "Secondary Tool (Set 1)", "main2": "Primary Tool (Set 2)", "off2": "Secondary Tool (Set 2)"}
## Passive keys aggregated by maximum (upgrade chains), not by sum.
const MAX_KEYS: Array[String] = ["twf_rank", "deflect_rank", "sneak_dice", "implant_tier", "power_dc", "heal_item_bonus", "dueling", "grants_resonance"]
const UNION_KEYS: Array[String] = ["weapon_prof", "armor_prof", "immune"]
const BASE_SPEED := 4.6

var uid: String = ""
var display_name: String = ""
var pronouns: String = "they"
var kind: String = "organic"
var faction: String = "party"
var template: String = ""
var class_id: String = "vanguard"
var background: String = ""
var level: int = 1
var xp: int = 0
var base_attrs: Dictionary = {"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}
var attr_increases: Dictionary = {}
var skill_ranks: Dictionary = {}
var feats: Array[String] = []
var powers: Array[String] = []
var appearance: Dictionary = {}
var hp: int = 1
var energy: int = 0
var equipment: Dictionary = {}
var active_set: int = 0
var form: String = ""
var statuses: Array = []
var cooldowns: Dictionary = {}
var prestige: String = ""
var behavior: String = "aggressive"
var overrides: Dictionary = {}
var kit: Dictionary = {}
var level_log: Array = []
var is_player: bool = false
var dead: bool = false
var skill_bank: int = 0

var _passive_cache: Dictionary = {}
var _gear_cache: Dictionary = {}
var _dirty := true


# ------------------------------------------------------------ construction
static func from_companion(comp_id: String) -> CharacterSheet:
	var c: Dictionary = DB.companions.get(comp_id, {})
	var s := CharacterSheet.new()
	s.uid = comp_id
	s.template = comp_id
	s.display_name = String(c.get("name", comp_id))
	s.pronouns = String(c.get("pronouns", "they"))
	s.kind = String(c.get("kind", "organic"))
	s.class_id = String(c.get("class", "companion_iona"))
	s.level = int(c.get("level", 1))
	s.base_attrs = (c.get("attrs", {}) as Dictionary).duplicate()
	for k in s.base_attrs.keys():
		s.base_attrs[k] = int(s.base_attrs[k])
	s.skill_ranks = {}
	var sk: Dictionary = c.get("skills", {})
	for k in sk.keys():
		s.skill_ranks[String(k)] = int(sk[k])
	s.feats = DB.str_arr(c.get("feats", []))
	s.powers = DB.str_arr(c.get("powers", []))
	s.behavior = String(c.get("behavior", "aggressive"))
	s.appearance = (c.get("appearance", {}) as Dictionary).duplicate(true)
	var eq: Dictionary = c.get("equipment", {})
	for slot in eq.keys():
		s.equipment[String(slot)] = ItemInst.make(String(eq[slot]))
	s.mark_dirty()
	s.hp = s.max_hp()
	s.energy = s.max_energy()
	return s


static func from_template(template_id: String, new_uid: String) -> CharacterSheet:
	var t: Dictionary = DB.enemy(template_id)
	var s := CharacterSheet.new()
	s.uid = new_uid
	s.template = template_id
	s.display_name = String(t.get("name", template_id))
	s.kind = String(t.get("kind", "organic"))
	s.faction = String(t.get("faction", "warden"))
	s.class_id = "enemy"
	s.level = int(t.get("level", 1))
	var a: Dictionary = t.get("attrs", {})
	for k in Rules.ATTRS:
		s.base_attrs[k] = int(a.get(k, 10))
	var sk: Dictionary = t.get("skills", {})
	for k in sk.keys():
		s.skill_ranks[String(k)] = int(sk[k])
	s.feats = DB.str_arr(t.get("feats", []))
	s.powers = DB.str_arr(t.get("powers", []))
	s.behavior = String(t.get("role", "melee"))
	s.overrides = {
		"hp_max": int(t.get("hp", 10)),
		"bab": int(t.get("bab", 1)),
		"defense_bonus": int(t.get("defense_bonus", 0)),
		"attack_bonus": int(t.get("attack_bonus", 0)),
		"saves": t.get("saves", {}),
		"resist": t.get("resist", {}),
		"speed": float(t.get("speed", BASE_SPEED)),
		"sight": float(t.get("sight", 12.0)),
		"role": String(t.get("role", "melee")),
		"stationary": bool(t.get("stationary", false)),
	}
	var w: Dictionary = t.get("weapons", {})
	for slot in w.keys():
		s.equipment[String(slot)] = ItemInst.make(String(w[slot]))
	if t.has("armor"):
		s.equipment["body"] = ItemInst.make(String(t["armor"]))
	var k2: Dictionary = t.get("kit", {})
	for k in k2.keys():
		s.kit[String(k)] = int(k2[k])
	s.appearance = {"model": String(t.get("model", "humanoid")), "accent_color": String(t.get("color", "#c9a24a"))}
	s.mark_dirty()
	s.hp = s.max_hp()
	s.energy = s.max_energy()
	return s


func klass() -> Dictionary:
	return DB.klass(class_id)


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	if not _dirty:
		return
	_passive_cache = _compute_passive()
	_gear_cache = _compute_gear()
	_dirty = false


# ------------------------------------------------------------ aggregation
static func _merge_mods(into: Dictionary, mods: Dictionary, use_max: bool = false) -> void:
	for key in mods.keys():
		var k := String(key)
		var v: Variant = mods[key]
		if UNION_KEYS.has(k):
			var cur: Array = into.get(k, [])
			for x in v:
				if not cur.has(x):
					cur.append(x)
			into[k] = cur
		elif typeof(v) == TYPE_DICTIONARY:
			var sub: Dictionary = into.get(k, {})
			for sk in (v as Dictionary).keys():
				sub[sk] = int(sub.get(sk, 0)) + int(v[sk])
			into[k] = sub
		elif typeof(v) == TYPE_FLOAT and k == "speed_mult":
			into[k] = float(into.get(k, 0.0)) + float(v)
		elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			if use_max and MAX_KEYS.has(k):
				into[k] = maxi(int(into.get(k, 0)), int(v))
			else:
				into[k] = int(into.get(k, 0)) + int(v)


func _compute_passive() -> Dictionary:
	var out := {}
	for f in feats:
		var fd: Dictionary = DB.feat(f)
		if fd.has("passive"):
			_merge_mods(out, fd["passive"], true)
	if prestige != "":
		var pv := Prestige.variant(prestige)
		if pv.has("passive"):
			_merge_mods(out, pv["passive"], true)
	return out


func _compute_gear() -> Dictionary:
	var out := {}
	for slot in equipment.keys():
		var inst: Variant = equipment[slot]
		if inst == null:
			continue
		if not is_slot_active(String(slot)):
			continue
		var it: Dictionary = DB.item(String(inst["id"]))
		if it.has("mods"):
			_merge_mods(out, it["mods"])
		for up in inst.get("upgrades", []):
			var ud: Dictionary = DB.dict(DB.item(String(up)), "upgrade")
			if ud.has("mods"):
				_merge_mods(out, ud["mods"])
	return out


func is_slot_active(slot: String) -> bool:
	if slot in ["main", "off"]:
		return active_set == 0
	if slot in ["main2", "off2"]:
		return active_set == 1
	return true


func passive() -> Dictionary:
	_refresh()
	return _passive_cache


func gear() -> Dictionary:
	_refresh()
	return _gear_cache


func status_mods() -> Dictionary:
	var out := {}
	for s in statuses:
		var def: Dictionary = DB.status(String(s["id"]))
		var m: Dictionary = s.get("mods", def.get("mods", {}))
		if not m.is_empty():
			_merge_mods(out, m)
	return out


func form_mods() -> Dictionary:
	if form == "" or not has_resonance():
		return {}
	return DB.dict(DB.forms.get(form, {}), "mods")


static func _get_int(d: Dictionary, key: String) -> int:
	return int(d.get(key, 0))


static func _get_sub(d: Dictionary, key: String, sub: String) -> int:
	var x: Variant = d.get(key, {})
	if typeof(x) == TYPE_DICTIONARY:
		return int((x as Dictionary).get(sub, 0))
	return 0


# ------------------------------------------------------------ attributes
func attr_perm(a: String) -> int:
	return int(base_attrs.get(a, 10)) + int(attr_increases.get(a, 0)) + _get_sub(gear(), "attrs", a)


func attr(a: String) -> int:
	return attr_perm(a) + _get_sub(status_mods(), "attrs", a)


func amod(a: String) -> int:
	return Rules.mod(attr(a))


func amod_perm(a: String) -> int:
	return Rules.mod(attr_perm(a))


# ------------------------------------------------------------ resources
func max_hp() -> int:
	if overrides.has("hp_max"):
		return maxi(1, int(overrides["hp_max"]) + _get_int(gear(), "hp_max"))
	var k := klass()
	var conm := amod_perm("con")
	var total := maxi(1, int(k.get("hp_first", 8)) + conm)
	for i in range(1, level):
		total += maxi(1, int(k.get("hp_per_level", 5)) + conm)
	total += _get_int(passive(), "hp_per_level") * level
	total += _get_int(gear(), "hp_max")
	return maxi(1, total)


func has_resonance() -> bool:
	if is_player:
		return true
	if _get_int(passive(), "grants_resonance") > 0:
		return true
	var k := klass()
	return int(k.get("energy_base", 0)) > 0 and class_id != "enemy"


func max_energy() -> int:
	if class_id == "enemy":
		return 0
	if not has_resonance():
		return 0
	var k := klass()
	var wism := amod_perm("wis")
	var base := int(k.get("energy_base", 0)) + int(k.get("energy_per_level", 0)) * (level - 1)
	base += int(k.get("energy_wis_mult", 0)) * wism * level
	var p := passive()
	base += _get_int(p, "energy_flat") + _get_int(p, "energy_per_level") * level
	base += _get_int(gear(), "energy_max")
	return maxi(0, base)


func bab() -> int:
	if overrides.has("bab"):
		return int(overrides["bab"])
	var t: Array = klass().get("bab", [0])
	return int(t[clampi(level - 1, 0, t.size() - 1)])


func save_base(t: String) -> int:
	if overrides.has("saves"):
		return int((overrides["saves"] as Dictionary).get(t, 0))
	var tbl: Array = DB.dict(klass(), "saves").get(t, [0])
	return int(tbl[clampi(level - 1, 0, tbl.size() - 1)])


func save_total(t: String) -> int:
	var total := save_base(t) + amod(Rules.SAVE_ATTR[t])
	total += _get_sub(passive(), "saves", t)
	total += _get_sub(gear(), "saves", t)
	total += _get_sub(status_mods(), "saves", t)
	total += _get_sub(form_mods(), "saves", t)
	return total


func is_class_skill(s: String) -> bool:
	return DB.arr(klass(), "class_skills").has(s)


func skill_rank(s: String) -> int:
	return int(skill_ranks.get(s, 0))


func skill_total(s: String) -> int:
	var sd: Dictionary = DB.skill(s)
	var a := String(sd.get("attr", "int"))
	var total := skill_rank(s) + amod(a)
	total += _get_sub(passive(), "skills", s)
	total += _get_sub(gear(), "skills", s)
	total += _get_sub(status_mods(), "skills", s)
	if background != "":
		total += int(DB.dict(DB.backgrounds.get(background, {}), "skill_bonus").get(s, 0))
	return total


func skill_parts(s: String) -> Array:
	var sd: Dictionary = DB.skill(s)
	var a := String(sd.get("attr", "int"))
	var parts: Array = [["Ranks", skill_rank(s)], [String(a).to_upper() + " mod", amod(a)]]
	var f := _get_sub(passive(), "skills", s)
	if f != 0:
		parts.append(["Feats", f])
	var g := _get_sub(gear(), "skills", s)
	if g != 0:
		parts.append(["Gear", g])
	var st := _get_sub(status_mods(), "skills", s)
	if st != 0:
		parts.append(["Effects", st])
	if background != "":
		var b := int(DB.dict(DB.backgrounds.get(background, {}), "skill_bonus").get(s, 0))
		if b != 0:
			parts.append(["Background", b])
	return parts


# ------------------------------------------------------------ equipment
func slot_name(slot: String) -> String:
	return String(MACHINE_SLOT_NAMES[slot] if kind == "machine" else SLOT_NAMES[slot])


func get_slot(slot: String) -> Variant:
	return equipment.get(slot, null)


func set_slot(slot: String, inst: Variant) -> void:
	if inst == null:
		equipment.erase(slot)
	else:
		equipment[slot] = inst
	mark_dirty()


func weapon_slot(hand: String) -> String:
	if hand == "main":
		return "main" if active_set == 0 else "main2"
	return "off" if active_set == 0 else "off2"


func weapon_inst(hand: String) -> Variant:
	return equipment.get(weapon_slot(hand), null)


func weapon_id(hand: String) -> String:
	var w: Variant = weapon_inst(hand)
	if w == null:
		return "unarmed" if hand == "main" else ""
	return String(w["id"])


func is_dual_wielding() -> bool:
	return weapon_inst("main") != null and weapon_inst("off") != null


func armor_data() -> Dictionary:
	var b: Variant = equipment.get("body", null)
	if b == null:
		return {}
	return DB.dict(DB.item(String(b["id"])), "armor")


func armor_category() -> String:
	return String(armor_data().get("category", "none"))


func immunities() -> Array:
	var out: Array = []
	for x in passive().get("immune", []):
		out.append(x)
	for x in gear().get("immune", []):
		if not out.has(x):
			out.append(x)
	for s in statuses:
		for x in DB.status(String(s["id"])).get("grants_immunity", []):
			if not out.has(x):
				out.append(x)
	return out


# ------------------------------------------------------------ status flags
func has_status(id: String) -> bool:
	for s in statuses:
		if s["id"] == id:
			return true
	return false


func get_status(id: String) -> Dictionary:
	for s in statuses:
		if s["id"] == id:
			return s
	return {}


func has_flag(flag: String) -> bool:
	for s in statuses:
		if DB.arr(DB.status(String(s["id"])), "flags").has(flag):
			return true
	return false


func is_downed() -> bool:
	return has_status("downed") or hp <= 0


func can_act() -> bool:
	return not dead and not has_flag("cannot_act") and not is_downed()


func can_move() -> bool:
	return can_act() and not has_flag("cannot_move") and not bool(overrides.get("stationary", false))


func can_attack() -> bool:
	return can_act() and not has_flag("cannot_attack")


func is_flat_footed() -> bool:
	return has_flag("flat_footed")


func speed() -> float:
	var base := float(overrides.get("speed", BASE_SPEED))
	var mult := 1.0 + float(status_mods().get("speed_mult", 0.0)) + float(form_mods().get("speed_mult", 0.0))
	return maxf(0.0, base * maxf(0.2, mult))


func sight_range() -> float:
	return float(overrides.get("sight", 14.0))


# ------------------------------------------------------------ defense
func defense_parts() -> Array:
	var parts: Array = [["Base", 10]]
	var ad := armor_data()
	var dexm := amod("dex")
	var maxdex := int(ad.get("max_dex", 99))
	var dexb := mini(dexm, maxdex)
	if is_flat_footed():
		dexb = mini(dexb, 0)
	parts.append(["DEX" + (" (capped)" if dexm > maxdex else "") + (" (flat-footed)" if is_flat_footed() else ""), dexb])
	if not ad.is_empty():
		parts.append(["Armor", int(ad.get("defense", 0))])
	var g := _get_int(gear(), "defense")
	if g != 0:
		parts.append(["Gear", g])
	if overrides.has("defense_bonus") and int(overrides["defense_bonus"]) != 0:
		parts.append(["Natural", int(overrides["defense_bonus"])])
	if _get_int(passive(), "dueling") > 0 and is_dueling_stance():
		parts.append(["Dueling", 2])
	var st := _get_int(status_mods(), "defense")
	if st != 0:
		parts.append(["Effects", st])
	var fm := _get_int(form_mods(), "defense")
	if fm != 0:
		parts.append(["Form", fm])
	return parts


func defense() -> int:
	var t := 0
	for p in defense_parts():
		t += int(p[1])
	return t


func is_dueling_stance() -> bool:
	var m: Variant = weapon_inst("main")
	if m == null or weapon_inst("off") != null:
		return false
	var w: Dictionary = DB.dict(DB.item(String(m["id"])), "weapon")
	return String(w.get("category", "")) == "melee" and int(w.get("hands", 1)) == 1


# ------------------------------------------------------------ powers
func power_dc(school: String = "universal") -> int:
	var dc := 10 + floori(level / 2.0) + amod("wis") + _get_int(passive(), "power_dc")
	if prestige != "":
		dc += Prestige.dc_bonus(self, school)
	return dc


## Returns {cost, blocked, reason, parts} for a power at the given alignment.
## Order: base, armor, alignment tier, form, prestige; minimum 1.
func power_cost(pid: String, alignment: int) -> Dictionary:
	var pd: Dictionary = DB.power(pid)
	var base := int(pd.get("cost", 0))
	var parts: Array = [["Base", base]]
	if bool(pd.get("innate", false)):
		return {"cost": 0, "blocked": false, "reason": "", "parts": parts}
	if not has_resonance():
		return {"cost": base, "blocked": true, "reason": "%s has no Resonance." % display_name, "parts": parts}
	var cost := base
	var cat := armor_category()
	if cat == "heavy":
		return {"cost": base, "blocked": true, "reason": "Heavy armor blocks Resonance powers.", "parts": parts}
	if cat == "medium":
		cost += 2
		parts.append(["Medium armor", 2])
	var school := String(pd.get("school", "universal"))
	var am := alignment_cost_mod(school, alignment)
	if am != 0:
		cost += am
		parts.append(["Alignment", am])
	if form != "":
		var fc := int(DB.forms.get(form, {}).get("power_cost_mod", 0))
		if fc != 0:
			cost += fc
			parts.append(["Form", fc])
	if prestige != "":
		var pc := Prestige.power_cost_mod(prestige, school)
		if pc != 0:
			cost += pc
			parts.append(["Specialization", pc])
	cost = maxi(1, cost)
	return {"cost": cost, "blocked": false, "reason": "", "parts": parts}


## Mercy is +, Dominion is -. Matching school: -1 at 25+, -2 at 60+.
## Opposing school: +1 at 25+, +2 at 60+. Universal powers are unaffected.
static func alignment_cost_mod(school: String, alignment: int) -> int:
	if school == "universal":
		return 0
	var lean := alignment if school == "mercy" else -alignment
	if lean >= 60:
		return -2
	if lean >= 25:
		return -1
	if lean <= -60:
		return 2
	if lean <= -25:
		return 1
	return 0


func chain_best(list: Array[String], kind_dict: Dictionary) -> Array[String]:
	## Returns ids with only the highest rank per chain.
	var best := {}
	for id in list:
		var d: Dictionary = kind_dict.get(id, {})
		var chain := String(d.get("chain", id))
		var r := int(d.get("rank", 1))
		if not best.has(chain) or int(kind_dict[best[chain]].get("rank", 1)) < r:
			best[chain] = id
	var out: Array[String] = []
	for id in list:
		var d: Dictionary = kind_dict.get(id, {})
		if best.get(String(d.get("chain", id)), "") == id:
			out.append(id)
	return out


func action_feats() -> Array[String]:
	var withact: Array[String] = []
	for f in feats:
		if DB.feat(f).has("action"):
			withact.append(f)
	return chain_best(withact, DB.feats)


func usable_powers() -> Array[String]:
	return chain_best(powers, DB.powers)


# ------------------------------------------------------------ progression
func xp_for_level(l: int) -> int:
	var t: Array = DB.progression.get("xp_table", [0])
	return int(t[clampi(l - 1, 0, t.size() - 1)])


func levels_available() -> int:
	var maxl := int(DB.progression.get("max_level", 10))
	var n := 0
	var l := level
	while l < maxl and xp >= xp_for_level(l + 1):
		n += 1
		l += 1
	return n


func pronoun(form_key: String) -> String:
	for p in DB.arr(DB.appearance, "pronouns"):
		if p["id"] == pronouns:
			return String(p.get(form_key, "they"))
	return "they"


# ------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	return {
		"uid": uid, "name": display_name, "pronouns": pronouns, "kind": kind, "faction": faction,
		"template": template, "class": class_id, "background": background, "level": level, "xp": xp,
		"attrs": base_attrs.duplicate(), "attr_inc": attr_increases.duplicate(), "skills": skill_ranks.duplicate(),
		"feats": feats.duplicate(), "powers": powers.duplicate(), "appearance": appearance.duplicate(true),
		"hp": hp, "energy": energy, "equipment": equipment.duplicate(true), "active_set": active_set,
		"form": form, "statuses": statuses.duplicate(true), "cooldowns": cooldowns.duplicate(),
		"prestige": prestige, "behavior": behavior, "overrides": overrides.duplicate(true), "kit": kit.duplicate(),
		"level_log": level_log.duplicate(true), "is_player": is_player, "dead": dead, "skill_bank": skill_bank,
	}


static func from_dict(d: Dictionary) -> CharacterSheet:
	var s := CharacterSheet.new()
	s.uid = String(d.get("uid", ""))
	s.display_name = String(d.get("name", ""))
	s.pronouns = String(d.get("pronouns", "they"))
	s.kind = String(d.get("kind", "organic"))
	s.faction = String(d.get("faction", "party"))
	s.template = String(d.get("template", ""))
	s.class_id = String(d.get("class", "vanguard"))
	s.background = String(d.get("background", ""))
	s.level = int(d.get("level", 1))
	s.xp = int(d.get("xp", 0))
	s.base_attrs = _int_dict(d.get("attrs", {}))
	s.attr_increases = _int_dict(d.get("attr_inc", {}))
	s.skill_ranks = _int_dict(d.get("skills", {}))
	s.feats = DB.str_arr(d.get("feats", []))
	s.powers = DB.str_arr(d.get("powers", []))
	s.appearance = (d.get("appearance", {}) as Dictionary).duplicate(true)
	s.hp = int(d.get("hp", 1))
	s.energy = int(d.get("energy", 0))
	s.equipment = {}
	var eq: Dictionary = d.get("equipment", {})
	for k in eq.keys():
		if eq[k] != null:
			s.equipment[String(k)] = ItemInst.normalize(eq[k])
	s.active_set = int(d.get("active_set", 0))
	s.form = String(d.get("form", ""))
	s.statuses = []
	for st in d.get("statuses", []):
		var sd: Dictionary = (st as Dictionary).duplicate(true)
		sd["remaining"] = float(sd.get("remaining", 0.0))
		if sd.has("absorb_left"):
			sd["absorb_left"] = int(sd["absorb_left"])
		s.statuses.append(sd)
	s.cooldowns = {}
	var cd: Dictionary = d.get("cooldowns", {})
	for k in cd.keys():
		s.cooldowns[String(k)] = float(cd[k])
	s.prestige = String(d.get("prestige", ""))
	s.behavior = String(d.get("behavior", "aggressive"))
	s.overrides = (d.get("overrides", {}) as Dictionary).duplicate(true)
	for key in ["hp_max", "bab", "defense_bonus", "attack_bonus"]:
		if s.overrides.has(key):
			s.overrides[key] = int(s.overrides[key])
	s.kit = _int_dict(d.get("kit", {}))
	s.level_log = (d.get("level_log", []) as Array).duplicate(true)
	s.is_player = bool(d.get("is_player", false))
	s.dead = bool(d.get("dead", false))
	s.skill_bank = int(d.get("skill_bank", 0))
	s.mark_dirty()
	return s


static func _int_dict(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in (v as Dictionary).keys():
			out[String(k)] = int(v[k])
	return out
