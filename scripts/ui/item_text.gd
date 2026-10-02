class_name ItemText
extends RefCounted
## Plain-text and BBCode descriptions of items, shared by inventory, loot,
## vendor and crafting screens so an item reads the same everywhere.


static func type_line(id: String) -> String:
	var it: Dictionary = DB.item(id)
	var t := String(it.get("type", ""))
	match t:
		"weapon":
			var w: Dictionary = it.get("weapon", {})
			return "%s weapon · %s" % [String(w.get("category", "")).capitalize(), "two-handed" if int(w.get("hands", 1)) == 2 else "one-handed"]
		"armor":
			return "%s armor" % String(DB.dict(it, "armor").get("category", "")).capitalize()
		"gear":
			return "Gear · %s slot" % String(it.get("slot", "")).capitalize()
		"upgrade":
			return "Upgrade for: %s" % ", ".join(DB.arr(DB.dict(it, "upgrade"), "applies_to"))
	return t.capitalize()


static func stat_line(id: String) -> String:
	var it: Dictionary = DB.item(id)
	if it.has("weapon"):
		var w: Dictionary = it["weapon"]
		var dmg := String(w.get("dice", "1d4"))
		if int(w.get("damage", 0)) != 0:
			dmg += "%+d" % int(w["damage"])
		var thr := int(w.get("threat", 20))
		var s := "%s %s · crit %s x%d · range %.0f m" % [dmg, w.get("dtype", ""), "20" if thr >= 20 else "%d–20" % thr, int(w.get("crit_mult", 2)), float(w.get("range", 2.0))]
		if int(w.get("attack", 0)) != 0:
			s += " · %+d attack" % int(w["attack"])
		return s
	if it.has("armor"):
		var a: Dictionary = it["armor"]
		return "+%d Defense · max DEX bonus %+d" % [int(a.get("defense", 0)), int(a.get("max_dex", 99))]
	return ""


static func req_line(id: String) -> String:
	var req: Dictionary = DB.item(id).get("req", {})
	var parts: PackedStringArray = []
	for a in (req.get("attrs", {}) as Dictionary).keys():
		parts.append("%s %d" % [String(a).to_upper(), int(req["attrs"][a])])
	if req.has("armor_prof"):
		parts.append("%s Armor Proficiency" % String(req["armor_prof"]).capitalize())
	if req.has("kind"):
		parts.append("synthetic only" if String(req["kind"]) == "machine" else "organic only")
	for f in req.get("feats", []):
		parts.append(String(DB.feat(String(f)).get("name", f)))
	return ", ".join(parts)


## Multi-line BBCode block for tooltips and detail panes.
static func describe(id: String, inst: Dictionary = {}) -> String:
	var it: Dictionary = DB.item(id)
	var name := ItemInst.display_name(inst) if not inst.is_empty() else DB.item_name(id)
	var out := "[b]%s[/b]\n[color=#9c958a]%s[/color]\n" % [name, type_line(id)]
	var sl := stat_line(id)
	if sl != "":
		out += sl + "\n"
	out += String(it.get("desc", "")) + "\n"
	var rl := req_line(id)
	if rl != "":
		out += "[color=#f2c26b]Requires: %s[/color]\n" % rl
	if not inst.is_empty():
		var ups: Array = inst.get("upgrades", [])
		var slots := ItemInst.upgrade_slots(inst)
		if slots > 0:
			out += "Upgrades (%d/%d): %s\n" % [ups.size(), slots, ", ".join(ups.map(func(u: Variant) -> String: return DB.item_name(String(u)))) if not ups.is_empty() else "none"]
	if bool(it.get("bound", false)):
		out += "[color=#7fd0ff]Bound to you: cannot be sold or dismantled.[/color]\n"
	elif bool(it.get("quest", false)):
		out += "[color=#7fd0ff]Quest item.[/color]\n"
	out += "[color=#9c958a]Value %d cr[/color]" % int(it.get("value", 0))
	return out


## Plain-text version (Control.tooltip_text does not render BBCode).
static func plain(id: String, inst: Dictionary = {}) -> String:
	var re := RegEx.new()
	re.compile("\\[/?[a-z]+(=[^\\]]*)?\\]")
	return re.sub(describe(id, inst), "", true)
