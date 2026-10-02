class_name CraftingUI
extends PanelBase
## Workbench / medical fabricator: craft from recipes, dismantle items into
## parts, and install or remove weapon/armor upgrades. The crafter's skill
## (chosen from the party) gates recipes. All operations are Crafting rules
## calls, each an atomic inventory transaction.

var station := "workbench"
var crafter_uid := "player"
var mode := "craft"
var _pick := ""
var _cols: Array = []
var _top: HBoxContainer
var _msg: Label


func build() -> void:
	var title := "Medical Fabricator" if station == "medstation" else "Workbench"
	var v := make_window(title, Vector2(1500, 880))
	_top = UIKit.hbox(8)
	v.add_child(_top)
	var h := UIKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	for i in 2:
		var c := UIKit.vbox(6)
		var p := UIKit.panel(UIKit.scroll(c))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(p)
		_cols.append(c)
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	v.add_child(_msg)
	if not Game.state.party.has(crafter_uid):
		crafter_uid = "player"
	_render()


func _crafter() -> CharacterSheet:
	return Game.state.get_char(crafter_uid)


func _render() -> void:
	UIKit.clear(_top)
	for m in [["craft", "Craft"], ["dismantle", "Dismantle"], ["upgrade", "Upgrades"]]:
		if station == "medstation" and String(m[0]) == "upgrade":
			continue
		var mid := String(m[0])
		var b := UIKit.button(String(m[1]), func() -> void:
			mode = mid
			_pick = ""
			_render())
		b.toggle_mode = true
		b.button_pressed = mode == mid
		_top.add_child(b)
	_top.add_child(UIKit.spacer(30))
	_top.add_child(UIKit.label("Crafter:", 17, UIKit.DIM))
	for uid in Game.state.party:
		var s := Game.state.get_char(uid)
		var u2 := String(uid)
		var cb := UIKit.button(s.display_name, func() -> void:
			crafter_uid = u2
			_render(), "Repair %+d · Medicine %+d · Demolitions %+d" % [s.skill_total("repair"), s.skill_total("medicine"), s.skill_total("demolitions")])
		cb.toggle_mode = true
		cb.button_pressed = u2 == crafter_uid
		_top.add_child(cb)
	_top.add_child(UIKit.expand(UIKit.spacer()))
	_top.add_child(UIKit.label("Parts: %d components · %d reagents · %d power cells" % [Game.state.inventory.count("tech_components"), Game.state.inventory.count("med_reagents"), Game.state.inventory.count("power_cell")], 16, UIKit.ACCENT2))
	for c in _cols:
		UIKit.clear(c)
	match mode:
		"craft":
			_craft()
		"dismantle":
			_dismantle()
		"upgrade":
			_upgrades()


func _craft() -> void:
	var c0: VBoxContainer = _cols[0]
	var c1: VBoxContainer = _cols[1]
	var cr := _crafter()
	c0.add_child(UIKit.header("Recipes"))
	for rid in Crafting.recipes_for(station):
		var r: Dictionary = DB.recipes[rid]
		if r.has("requires_flag") and not Game.state.has_flag(String(r["requires_flag"])) and bool(r.get("hidden_until_known", true)):
			continue
		var pv := Crafting.preview(rid, cr, Game.state)
		var outp: Dictionary = r.get("output", {})
		var out_id := String(outp.keys()[0]) if not outp.is_empty() else ""
		var r2 := rid
		var b := UIKit.button("%s%s" % [String(r.get("name", DB.item_name(out_id))), "" if bool(pv["ok"]) else "  (unavailable)"], func() -> void:
			_pick = r2
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = _pick == rid
		if not bool(pv["ok"]):
			b.add_theme_color_override("font_color", UIKit.DIM)
		c0.add_child(b)
	if _pick == "" or not DB.recipes.has(_pick):
		_pick = ""
		c1.add_child(UIKit.label("Select a recipe. The chosen crafter's skill must meet the recipe's minimum.", 16, UIKit.DIM, true))
		return
	var rd: Dictionary = DB.recipes[_pick]
	var pv2 := Crafting.preview(_pick, cr, Game.state)
	var outp2: Dictionary = rd.get("output", {})
	for oid in outp2.keys():
		c1.add_child(UIKit.rich(ItemText.describe(String(oid)) + ("  ×%d" % int(outp2[oid]) if int(outp2[oid]) > 1 else ""), 17))
	c1.add_child(UIKit.sep())
	if String(pv2.get("skill", "")) != "":
		var ok_sk := int(pv2["skill_have"]) >= int(pv2["skill_need"])
		c1.add_child(UIKit.label("Requires %s %d — %s has %+d" % [DB.skill(String(pv2["skill"])).get("name", ""), int(pv2["skill_need"]), cr.display_name, int(pv2["skill_have"])], 16, UIKit.GOOD if ok_sk else UIKit.BAD))
	for inp in pv2["inputs"]:
		var ok_i := int(inp["have"]) >= int(inp["need"])
		c1.add_child(UIKit.label("%s: %d / %d" % [DB.item_name(String(inp["id"])), int(inp["have"]), int(inp["need"])], 16, UIKit.GOOD if ok_i else UIKit.BAD))
	var cb := UIKit.button("Craft", func() -> void: _result(Crafting.craft(_pick, cr, Game.state), "Crafted."))
	cb.disabled = not bool(pv2["ok"])
	if cb.disabled:
		cb.tooltip_text = " ".join(PackedStringArray(pv2["reasons"]))
	c1.add_child(cb)


func _dismantle() -> void:
	var c0: VBoxContainer = _cols[0]
	var c1: VBoxContainer = _cols[1]
	c0.add_child(UIKit.header("Items that can be broken down"))
	var any := false
	for r in Game.state.inventory.rows("all"):
		var rid := String(r["id"])
		if not DB.item(rid).has("dismantle"):
			continue
		any = true
		var rinst: Dictionary = r["inst"]
		var key := rid + "|" + (String(rinst["uid"]) if not rinst.is_empty() else "")
		var b := UIKit.button("%s%s" % [ItemInst.display_name(rinst) if not rinst.is_empty() else DB.item_name(rid), "  ×%d" % int(r["count"]) if int(r["count"]) > 1 else ""], func() -> void:
			_pick = key
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = _pick == key
		c0.add_child(b)
	if not any:
		c0.add_child(UIKit.label("Nothing in your inventory can be dismantled.", 16, UIKit.DIM, true))
	if _pick == "" or not _pick.contains("|"):
		c1.add_child(UIKit.label("Dismantling returns parts worth less than buying or crafting the item.", 16, UIKit.DIM, true))
		return
	var parts := _pick.split("|")
	var id := parts[0]
	var iuid := parts[1]
	var inst := Game.state.inventory.find_instance(iuid) if iuid != "" else {}
	c1.add_child(UIKit.rich(ItemText.describe(id, inst), 17))
	var y: Dictionary = DB.dict(DB.item(id), "dismantle")
	c1.add_child(UIKit.label("Yields: " + ", ".join(y.keys().map(func(k: Variant) -> String: return "%d %s" % [int(y[k]), DB.item_name(String(k))])), 16, UIKit.ACCENT2, true))
	var why := Crafting.can_dismantle(Game.state, id, iuid)
	var b2 := UIKit.button("Dismantle", func() -> void:
		var res := Crafting.dismantle(Game.state, id, iuid)
		if bool(res.get("ok", false)) and (iuid != "" or Game.state.inventory.stack_count(id) <= 0):
			_pick = ""
		_result(res, "Dismantled."))
	b2.disabled = why != ""
	b2.tooltip_text = why
	c1.add_child(b2)


func _upgrades() -> void:
	var c0: VBoxContainer = _cols[0]
	var c1: VBoxContainer = _cols[1]
	c0.add_child(UIKit.header("Upgradeable items (inventory and equipped)"))
	var cands: Array = []
	for inst in Game.state.inventory.instances:
		if ItemInst.upgrade_slots(inst) > 0:
			cands.append({"inst": inst, "where": "inventory"})
	for uid in Game.state.roster:
		var s := Game.state.get_char(uid)
		for slot in s.equipment.keys():
			var e: Variant = s.equipment[slot]
			if e != null and ItemInst.upgrade_slots(e) > 0:
				cands.append({"inst": e, "where": "%s (%s)" % [s.display_name, s.slot_name(String(slot))]})
	if cands.is_empty():
		c0.add_child(UIKit.label("No items with upgrade slots.", 16, UIKit.DIM))
	for cnd in cands:
		var inst: Dictionary = cnd["inst"]
		var u2 := String(inst["uid"])
		var b := UIKit.button("%s — %s  [%d/%d]" % [ItemInst.display_name(inst), cnd["where"], (inst.get("upgrades", []) as Array).size(), ItemInst.upgrade_slots(inst)], func() -> void:
			_pick = u2
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = _pick == u2
		c0.add_child(b)
	if _pick == "":
		c1.add_child(UIKit.label("Select an item, then install a compatible upgrade from your inventory or remove one (it returns to your inventory).", 16, UIKit.DIM, true))
		return
	var loc := Crafting.locate(Game.state, _pick)
	if loc.is_empty():
		_pick = ""
		return
	var tinst: Dictionary = loc["inst"]
	c1.add_child(UIKit.rich(ItemText.describe(String(tinst["id"]), tinst), 17))
	c1.add_child(UIKit.header("Installed"))
	for up in tinst.get("upgrades", []):
		var up_id := String(up)
		c1.add_child(UIKit.button("Remove %s" % DB.item_name(up_id), func() -> void: _result(Crafting.remove_upgrade(Game.state, _pick, up_id), "Upgrade removed.")))
	c1.add_child(UIKit.header("Available upgrades"))
	var found := false
	for id in Game.state.inventory.stacks.keys():
		var sid := String(id)
		if String(DB.item(sid).get("type", "")) != "upgrade":
			continue
		if not Crafting.upgrade_applies(sid, String(tinst["id"])):
			continue
		found = true
		var ib := UIKit.button("Install %s (×%d) — %s" % [DB.item_name(sid), Game.state.inventory.stack_count(sid), DB.item(sid).get("desc", "")], func() -> void: _result(Crafting.install(Game.state, sid, _pick), "Upgrade installed."))
		ib.alignment = HORIZONTAL_ALIGNMENT_LEFT
		ib.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ib.disabled = (tinst.get("upgrades", []) as Array).size() >= ItemInst.upgrade_slots(tinst)
		c1.add_child(ib)
	if not found:
		c1.add_child(UIKit.label("No compatible upgrades in your inventory.", 15, UIKit.DIM))


func _result(r: Dictionary, ok_text: String) -> void:
	if bool(r.get("ok", false)):
		_msg.text = ok_text
		_msg.add_theme_color_override("font_color", UIKit.GOOD)
		GameAudio.play("loot", -6.0)
		var w := world()
		if w != null:
			for a in w.party_actors():
				(a as Actor).visual.refresh_weapons((a as Actor).sheet)
	else:
		_msg.text = String(r.get("reason", "Not possible."))
		_msg.add_theme_color_override("font_color", UIKit.WARN)
		GameAudio.play("ui_error", -6.0)
	_render()
