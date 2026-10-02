class_name GameMenu
extends PanelBase
## The in-game menu: Character, Inventory & Equipment, Abilities, Party,
## Journal, Map and Controls. The world is paused (modal "menu") while open.
## Every change goes through the same rules functions the world uses
## (EquipmentRules, World.queue_action/execute_action, World.set_behavior...).

const TABS := [["character", "Character"], ["inventory", "Inventory"], ["abilities", "Abilities"], ["party", "Party"], ["journal", "Journal"], ["map", "Map"], ["controls", "Controls"]]
const BEHAVIORS := [["aggressive", "Aggressive", "Attacks the leader's target, heals only in emergencies."], ["ranged", "Ranged", "Prefers ranged weapons and keeps distance; heals allies under 30%."], ["support", "Support", "Heals and revives first, fights second."], ["passive", "Passive", "Only follows your orders. Never acts on its own."]]

var tab := "character"
var sel_uid := "player"
var inv_filter := "all"
var inv_pick: Dictionary = {}
var journal_tab := "quests"
var journal_pick := ""
var _tab_bar: HBoxContainer
var _char_bar: HBoxContainer
var _content: Control


func build() -> void:
	var v := make_window("Operator", Vector2(1680, 940))
	if Game.state != null and Game.state.controlled != "":
		sel_uid = Game.state.controlled
	_tab_bar = UIKit.hbox(6)
	v.add_child(_tab_bar)
	_char_bar = UIKit.hbox(6)
	v.add_child(_char_bar)
	_content = UIKit.vbox(8)
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_content)
	_render()


func show_tab(t: String) -> void:
	tab = t if t != "" else "character"
	inv_pick = {}
	if is_inside_tree():
		_render()


func _render() -> void:
	if _content == null:
		return
	UIKit.clear(_tab_bar)
	for t in TABS:
		var tid := String(t[0])
		var b := UIKit.button(String(t[1]), show_tab.bind(tid))
		b.toggle_mode = true
		b.button_pressed = tid == tab
		b.custom_minimum_size = Vector2(150, 40)
		_tab_bar.add_child(b)
	(win["title"] as Label).text = String(TABS.filter(func(x: Array) -> bool: return x[0] == tab)[0][1]) if TABS.any(func(x: Array) -> bool: return x[0] == tab) else "Operator"
	UIKit.clear(_char_bar)
	_char_bar.visible = tab in ["character", "inventory", "abilities"]
	if _char_bar.visible:
		for uid in Game.state.roster:
			var s := Game.state.get_char(uid)
			if s == null:
				continue
			var lb := "%s  L%d%s" % [s.display_name, s.level, "  ▲" if s.levels_available() > 0 else ""]
			var cb := UIKit.button(lb, func() -> void:
				sel_uid = uid
				inv_pick = {}
				_render())
			cb.toggle_mode = true
			cb.button_pressed = uid == sel_uid
			_char_bar.add_child(cb)
	if Game.state.get_char(sel_uid) == null:
		sel_uid = "player"
	UIKit.clear(_content)
	match tab:
		"character":
			_tab_character()
		"inventory":
			_tab_inventory()
		"abilities":
			_tab_abilities()
		"party":
			_tab_party()
		"journal":
			_tab_journal()
		"map":
			_tab_map()
		"controls":
			_tab_controls()


func _sheet() -> CharacterSheet:
	return Game.state.get_char(sel_uid)


func _portrait(s: CharacterSheet, size: int) -> Control:
	var hud: Variant = main.get("hud") if main != null else null
	if hud != null and (hud as HUD).portraits != null:
		var tr := TextureRect.new()
		tr.texture = (hud as HUD).portraits.texture_for(s, size)
		tr.custom_minimum_size = Vector2(size, size)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	return UIKit.spacer(size, size)


func _parts_text(parts: Array) -> String:
	var out: PackedStringArray = []
	for p in parts:
		out.append("%s %+d" % [p[0], int(p[1])])
	return ", ".join(out)


func _columns(n: int) -> Array:
	var h := UIKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(h)
	var cols: Array = []
	for i in n:
		var c := UIKit.vbox(6)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var p := UIKit.panel(UIKit.scroll(c))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(p)
		cols.append(c)
	return cols


# ================================================================ character
func _tab_character() -> void:
	var s := _sheet()
	var cols := _columns(3)
	var c0: VBoxContainer = cols[0]
	var top := UIKit.hbox(10)
	top.add_child(_portrait(s, 128))
	var idv := UIKit.vbox(2)
	idv.add_child(UIKit.label(s.display_name, 26, UIKit.ACCENT2))
	var kname := String(DB.klass(s.class_id).get("name", s.class_id))
	if s.prestige != "":
		kname += " / " + String(DB.prestige.get(s.prestige, {}).get("name", s.prestige))
	idv.add_child(UIKit.label("Level %d %s" % [s.level, kname], 18))
	if s.is_player:
		idv.add_child(UIKit.label(String(DB.backgrounds.get(s.background, {}).get("name", "")), 15, UIKit.DIM))
	top.add_child(idv)
	c0.add_child(top)
	var nxt := s.xp_for_level(s.level + 1)
	c0.add_child(UIKit.label("Experience %d / %d" % [s.xp, nxt], 16))
	c0.add_child(UIKit.bar(float(s.xp - s.xp_for_level(s.level)), float(maxi(1, nxt - s.xp_for_level(s.level))), UIKit.ACCENT2, 10))
	if s.levels_available() > 0 and main != null and main.has_method("open_levelup"):
		var lu := UIKit.button("LEVEL UP (%d available)" % s.levels_available(), func() -> void: main.open_levelup(s.uid))
		lu.add_theme_color_override("font_color", UIKit.GOOD)
		c0.add_child(lu)
	c0.add_child(UIKit.label("Health %d / %d" % [s.hp, s.max_hp()], 16))
	c0.add_child(UIKit.bar(s.hp, s.max_hp(), UIKit.GOOD, 12))
	c0.add_child(UIKit.label("Energy %d / %d" % [s.energy, s.max_energy()], 16))
	c0.add_child(UIKit.bar(s.energy, s.max_energy(), UIKit.MERCY, 12))
	c0.add_child(UIKit.sep())
	# Alignment (the player's, shared by the party) and influence.
	var al := Game.state.alignment
	c0.add_child(UIKit.label("Alignment: %s (%+d)" % [GameState.alignment_label(al), al], 18, UIKit.MERCY if al > 0 else (UIKit.DOMINION if al < 0 else UIKit.TEXT)))
	var ab := UIKit.bar(float(al + 100), 200.0, UIKit.MERCY if al >= 0 else UIKit.DOMINION, 10)
	ab.tooltip_text = "−100 Dominion … 0 … +100 Mercy. Mercy powers cost less toward Mercy; Dominion powers toward Dominion."
	c0.add_child(ab)
	if Game.state.influence.has(s.uid):
		var inf := int(Game.state.influence[s.uid])
		c0.add_child(UIKit.label("Influence with you: %d / 100 (%s)" % [inf, _inf_label(inf)], 16))
		c0.add_child(UIKit.bar(inf, 100, UIKit.TEAL, 10))
	if not s.statuses.is_empty():
		c0.add_child(UIKit.header("Active effects"))
		var sh := HFlowContainer.new()
		for st in s.statuses:
			sh.add_child(UIKit.status_chip(String(st["id"]), float(st["remaining"])))
		c0.add_child(sh)
	# Attributes and derived stats.
	var c1: VBoxContainer = cols[1]
	c1.add_child(UIKit.header("Attributes"))
	for a in Rules.ATTRS:
		var row := UIKit.hbox(6)
		var nl := UIKit.label(Rules.ATTR_NAMES[a], 18)
		nl.custom_minimum_size = Vector2(170, 0)
		row.add_child(nl)
		var val := s.attr(a)
		var perm := s.attr_perm(a)
		var vl := UIKit.label("%d (%+d)" % [val, s.amod(a)], 18, UIKit.ACCENT2 if val == perm else UIKit.GOOD)
		if val != perm:
			vl.tooltip_text = "Base %d, modified by gear or effects." % perm
			vl.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(vl)
		c1.add_child(row)
	c1.add_child(UIKit.sep())
	c1.add_child(UIKit.header("Combat"))
	var prof := CombatRules.weapon_profile(s, "main")
	var atk_parts := CombatRules.attack_parts(s, prof)
	var snap := EquipmentRules.snapshot(s)
	c1.add_child(_stat_row("Defense", str(s.defense()), _parts_text(s.defense_parts())))
	c1.add_child(_stat_row("Attack (%s)" % DB.item_name(String(prof.get("id", "unarmed"))), "%+d" % CombatRules.sum_parts(atk_parts), _parts_text(atk_parts)))
	c1.add_child(_stat_row("Average damage", "%.1f" % float(snap["Avg damage"]), "Weapon dice + bonuses, before the target's resistances."))
	for sv in ["fort", "ref", "will"]:
		c1.add_child(_stat_row(Rules.SAVE_NAMES[sv], "%+d" % s.save_total(sv), "Class base + %s modifier + gear/effects" % String(Rules.SAVE_ATTR[sv]).to_upper()))
	c1.add_child(_stat_row("Speed", "%.1f m/s" % s.speed(), ""))
	# Skills, feats, powers.
	var c2: VBoxContainer = cols[2]
	c2.add_child(UIKit.header("Skills"))
	for sid in DB.skill_ids():
		var sd: Dictionary = DB.skill(sid)
		c2.add_child(_stat_row(String(sd["name"]) + (" ★" if DB.arr(DB.klass(s.class_id), "class_skills").has(sid) else ""), "%+d" % s.skill_total(sid), "%s\n%s" % [_parts_text(s.skill_parts(sid)), sd.get("uses", "")]))
	c2.add_child(UIKit.sep())
	c2.add_child(UIKit.header("Feats"))
	c2.add_child(UIKit.label(", ".join(s.feats.map(func(f: String) -> String: return String(DB.feat(f).get("name", f)))), 15, UIKit.TEXT, true))
	c2.add_child(UIKit.header("Powers"))
	c2.add_child(UIKit.label(", ".join(s.powers.map(func(p: String) -> String: return String(DB.power(p).get("name", p)))) if not s.powers.is_empty() else "none", 15, UIKit.TEXT, true))


func _stat_row(name: String, val: String, tip: String) -> HBoxContainer:
	var row := UIKit.hbox(6)
	var nl := UIKit.label(name, 17)
	nl.custom_minimum_size = Vector2(220, 0)
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nl)
	var vl := UIKit.label(val, 17, UIKit.ACCENT2)
	row.add_child(vl)
	if tip != "":
		row.tooltip_text = tip
		nl.tooltip_text = tip
		vl.tooltip_text = tip
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		vl.mouse_filter = Control.MOUSE_FILTER_PASS
	return row


func _inf_label(v: int) -> String:
	if v >= 80:
		return "devoted"
	if v >= 65:
		return "trusting"
	if v >= 36:
		return "neutral"
	if v >= 20:
		return "wary"
	return "hostile"


# ================================================================ inventory
func _tab_inventory() -> void:
	var s := _sheet()
	var cols := _columns(3)
	var c0: VBoxContainer = cols[0]
	c0.add_child(UIKit.header("%s — equipment" % s.display_name))
	c0.add_child(UIKit.label("Active weapon set: %d (swap with %s)" % [s.active_set + 1, Settings.key_label("swap_weapons")], 15, UIKit.DIM))
	for slot in CharacterSheet.SLOTS:
		var cur: Variant = s.equipment.get(slot, null)
		var row := UIKit.hbox(6)
		var sl := UIKit.label(s.slot_name(slot), 15, UIKit.DIM)
		sl.custom_minimum_size = Vector2(190, 0)
		row.add_child(sl)
		var txt := ItemInst.display_name(cur) if cur != null else "— empty —"
		var b := UIKit.button(txt, func() -> void:
			if cur != null:
				inv_pick = {"slot": slot, "inst": cur, "id": String(cur["id"])}
				_render())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if cur != null:
			b.tooltip_text = ItemText.plain(String(cur["id"]), cur)
		row.add_child(b)
		c0.add_child(row)
	c0.add_child(UIKit.sep())
	c0.add_child(UIKit.label("Defense %d · Attack %+d · Health %d" % [s.defense(), int(EquipmentRules.snapshot(s)["Attack"]), s.max_hp()], 16))
	# Inventory list.
	var c1: VBoxContainer = cols[1]
	var inv := Game.state.inventory
	c1.add_child(UIKit.label("Credits: %d" % inv.credits, 20, UIKit.ACCENT2))
	var fr := HFlowContainer.new()
	for f in [["all", "All"], ["weapons", "Weapons"], ["armor", "Armor & gear"], ["consumables", "Consumables"], ["resources", "Parts & upgrades"], ["quest", "Quest"]]:
		var fid := String(f[0])
		var fb := UIKit.button(String(f[1]), func() -> void:
			inv_filter = fid
			_render())
		fb.toggle_mode = true
		fb.button_pressed = inv_filter == fid
		fr.add_child(fb)
	c1.add_child(fr)
	var rows := inv.rows(inv_filter)
	if rows.is_empty():
		c1.add_child(UIKit.label("Nothing here.", 16, UIKit.DIM))
	for r in rows:
		var rid := String(r["id"])
		var rinst: Dictionary = r["inst"]
		var nm := ItemInst.display_name(rinst) if not rinst.is_empty() else DB.item_name(rid)
		if int(r["count"]) > 1:
			nm += "  ×%d" % int(r["count"])
		var ok_here := _equip_slots_for(s, rid).size() > 0
		var b := UIKit.button(nm, func() -> void:
			inv_pick = {"id": rid, "inst": rinst}
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = ItemText.plain(rid, rinst)
		if not rinst.is_empty() and not ok_here and String(DB.item(rid).get("type", "")) in ["weapon", "armor", "gear"]:
			b.add_theme_color_override("font_color", UIKit.DIM)
		c1.add_child(b)
	# Details / actions.
	var c2: VBoxContainer = cols[2]
	if inv_pick.is_empty():
		c2.add_child(UIKit.label("Select an item to see details, compare and equip it.", 16, UIKit.DIM, true))
		return
	var pid := String(inv_pick["id"])
	var pinst: Dictionary = inv_pick.get("inst", {})
	c2.add_child(UIKit.rich(ItemText.describe(pid, pinst), 17))
	if inv_pick.has("slot"):
		var slot := String(inv_pick["slot"])
		c2.add_child(UIKit.button("Unequip from %s" % s.slot_name(slot), func() -> void:
			var r := EquipmentRules.unequip(s, Game.state.inventory, slot)
			_after_change(r)))
		return
	var slots := _equip_slots_for(s, pid)
	for slot2 in slots:
		var cmp := EquipmentRules.compare(s, pid, slot2)
		var delta: Dictionary = cmp.get("delta", {})
		var dl: PackedStringArray = []
		for k in delta.keys():
			dl.append("%s %+.1f" % [k, float(delta[k])] if absf(float(delta[k]) - roundf(float(delta[k]))) > 0.01 else "%s %+d" % [k, int(delta[k])])
		var cmp_t := "[color=#9c958a]If equipped in %s:[/color] %s" % [s.slot_name(slot2), ", ".join(dl) if not dl.is_empty() else "no stat change"]
		c2.add_child(UIKit.rich(cmp_t, 15))
		if not pinst.is_empty():
			var sl2 := slot2
			c2.add_child(UIKit.button("Equip → %s" % s.slot_name(slot2), func() -> void:
				var r := EquipmentRules.equip(s, Game.state.inventory, String(pinst["uid"]), sl2)
				_after_change(r)))
	if slots.is_empty() and String(DB.item(pid).get("type", "")) in ["weapon", "armor", "gear"]:
		var why := EquipmentRules.can_equip(s, pid, String(DB.item(pid).get("slot", "main")) if String(DB.item(pid).get("type", "")) != "weapon" else "main")
		c2.add_child(UIKit.label("%s cannot equip this: %s" % [s.display_name, why], 15, UIKit.BAD, true))
	var t := String(DB.item(pid).get("type", ""))
	if t == "consumable":
		for uid in Game.state.party:
			var ts := Game.state.get_char(uid)
			var why2 := ActionResolver.item_usable(s, pid, ts, Game.state.inventory)
			var tuid := uid
			var ub := UIKit.button("Use on %s" % ts.display_name, func() -> void: _use_item(pid, tuid))
			if why2 != "":
				ub.disabled = true
				ub.tooltip_text = why2
			c2.add_child(ub)
	if t == "upgrade" or (not pinst.is_empty() and ItemInst.upgrade_slots(pinst) > 0):
		c2.add_child(UIKit.label("Upgrades are installed and removed at a workbench.", 15, UIKit.DIM, true))


## Slots this character could put the item in right now.
func _equip_slots_for(s: CharacterSheet, id: String) -> Array[String]:
	var out: Array[String] = []
	var it: Dictionary = DB.item(id)
	var t := String(it.get("type", ""))
	if t == "weapon":
		for sl in ["main", "off", "main2", "off2"]:
			if EquipmentRules.can_equip(s, id, sl) == "":
				out.append(sl)
	elif t == "armor" or t == "gear":
		var sl2 := String(it.get("slot", ""))
		if EquipmentRules.can_equip(s, id, sl2) == "":
			out.append(sl2)
	return out


func _use_item(id: String, target_uid: String) -> void:
	var w := world()
	if w == null:
		return
	var a: Actor = w.actors.get(sel_uid, null)
	if a == null:
		Events.toast("%s is not here." % _sheet().display_name, "warn")
		return
	var act := {"type": "item", "id": id, "target": target_uid}
	if w.combat.active:
		var r := w.queue_action(a, act)
		if r == "":
			Events.toast("Queued: %s will use %s." % [a.sheet.display_name, DB.item_name(id)], "info")
	else:
		var why := w.validate_action(a, act)
		if why != "":
			Events.toast(why, "warn")
		else:
			w.execute_action(a, act)
	_render()


func _after_change(r: Dictionary) -> void:
	if not bool(r.get("ok", false)):
		Events.toast(String(r.get("reason", "Not possible.")), "warn")
		GameAudio.play("ui_error", -6.0)
	else:
		GameAudio.play("loot", -8.0)
		var w := world()
		if w != null and w.actors.has(sel_uid):
			(w.actors[sel_uid] as Actor).visual.refresh_weapons(_sheet())
	inv_pick = {}
	_render()


# ================================================================ abilities
func _tab_abilities() -> void:
	var s := _sheet()
	var cols := _columns(3)
	var c0: VBoxContainer = cols[0]
	c0.add_child(UIKit.header("Feats"))
	for f in s.feats:
		var fd: Dictionary = DB.feat(f)
		var active := fd.has("action")
		c0.add_child(UIKit.rich("[b]%s[/b]%s\n[color=#9c958a]%s[/color]" % [fd.get("name", f), "  [color=#f2c26b](active)[/color]" if active else "", fd.get("desc", "")], 15))
	var c1: VBoxContainer = cols[1]
	c1.add_child(UIKit.header("Resonance powers"))
	if s.powers.is_empty():
		c1.add_child(UIKit.label("No powers known.", 15, UIKit.DIM))
	for p in s.powers:
		var pd: Dictionary = DB.power(p)
		var cost := s.power_cost(p, Game.state.alignment)
		var cs := "%d energy" % int(cost["cost"])
		if bool(cost.get("blocked", false)):
			cs = "[color=#ff6a5a]%s[/color]" % String(cost.get("reason", "blocked"))
		elif int(cost["cost"]) != int(pd.get("cost", 0)):
			cs += " (base %d, adjusted by alignment/armor)" % int(pd.get("cost", 0))
		c1.add_child(UIKit.rich("[b]%s[/b]  [color=#9c958a]%s · %s[/color]\n%s" % [pd.get("name", p), String(pd.get("school", "universal")).capitalize(), cs, pd.get("desc", "")], 15))
	var c2: VBoxContainer = cols[2]
	c2.add_child(UIKit.header("Combat forms"))
	c2.add_child(UIKit.label("Choose a form from the HUD selector. Switching locks out another switch for one round.", 15, UIKit.DIM, true))
	for fid in DB.forms.keys():
		if String(fid).begins_with("_"):
			continue
		var fdd: Dictionary = DB.forms[fid]
		var cur := s.form == String(fid)
		c2.add_child(UIKit.rich("[b]%s[/b]%s\n[color=#9c958a]%s[/color]" % [fdd.get("name", fid), "  [color=#5fd38a](current)[/color]" if cur else "", fdd.get("desc", "")], 15))
	c2.add_child(UIKit.sep())
	c2.add_child(UIKit.header("Action bar"))
	c2.add_child(UIKit.label("Active feats, powers and usable items appear on the action bar automatically in this order; slots 1–0 trigger them (%s…%s)." % [Settings.key_label("slot_1"), Settings.key_label("slot_10")], 15, UIKit.DIM, true))


# ================================================================ party
func _tab_party() -> void:
	var st := Game.state
	_content.add_child(UIKit.label("Everyone with you is in the active party (up to three). Behaviour applies when a character is not under your direct control. Party: %s · Order: %s%s" % [", ".join(st.party.map(func(u: String) -> String: return st.get_char(u).display_name)), st.party_order, " · Solo mode" if st.solo else ""], 16, UIKit.DIM, true))
	var row := UIKit.hbox(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(row)
	for uid in st.roster:
		var s := st.get_char(uid)
		var v := UIKit.vbox(6)
		var p := UIKit.panel(v)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(p)
		var top := UIKit.hbox(8)
		top.add_child(_portrait(s, 96))
		var idv := UIKit.vbox(2)
		idv.add_child(UIKit.label(s.display_name, 22, UIKit.ACCENT2))
		idv.add_child(UIKit.label("Level %d %s" % [s.level, DB.klass(s.class_id).get("name", "")], 15))
		idv.add_child(UIKit.label("Health %d/%d · Energy %d/%d%s" % [s.hp, s.max_hp(), s.energy, s.max_energy(), " · DOWN" if s.is_downed() else ""], 15, UIKit.BAD if s.is_downed() else UIKit.TEXT))
		top.add_child(idv)
		v.add_child(top)
		if st.influence.has(uid):
			var inf := int(st.influence[uid])
			v.add_child(UIKit.label("Influence %d (%s)" % [inf, _inf_label(inf)], 16))
			v.add_child(UIKit.bar(inf, 100, UIKit.TEAL, 10))
			var recent: Array = st.influence_log.filter(func(e: Dictionary) -> bool: return String(e.get("companion", "")) == uid)
			for i in range(maxi(0, recent.size() - 3), recent.size()):
				var e: Dictionary = recent[i]
				v.add_child(UIKit.label("%+d  %s" % [int(e["delta"]), e.get("reason", "")], 14, UIKit.GOOD if int(e["delta"]) > 0 else UIKit.BAD, true))
		if uid != "player":
			v.add_child(UIKit.header("Behaviour"))
			for bh in BEHAVIORS:
				var bid := String(bh[0])
				var bb := UIKit.button(String(bh[1]), func() -> void:
					if world() != null:
						world().set_behavior(uid, bid)
					else:
						s.behavior = bid
					_render(), String(bh[2]))
				bb.toggle_mode = true
				bb.button_pressed = s.behavior == bid
				v.add_child(bb)
			var tb := UIKit.button("Talk to %s" % s.display_name, func() -> void:
				var w := world()
				if w != null:
					main.close_panel(self)
					w.talk_companion(uid))
			if world() == null or world().combat.active or DB.dialogue(String(DB.companions.get(uid, {}).get("dialogue", uid + "_talk"))).is_empty():
				tb.disabled = true
			v.add_child(tb)
			var spec := String(DB.companions.get(uid, {}).get("specialization", ""))
			if spec != "":
				v.add_child(UIKit.label("Specialization: " + spec, 14, UIKit.DIM, true))
			if uid == "iona":
				v.add_child(UIKit.label(_iona_training_text(), 14, UIKit.MERCY, true))
		var cb := UIKit.button("Take control", func() -> void:
			if world() != null:
				world().switch_control(uid)
			_render())
		cb.disabled = world() == null or st.controlled == uid or s.is_downed() or not st.party.has(uid)
		v.add_child(cb)


func _iona_training_text() -> String:
	var st := Game.state
	var stage := String(st.flags.get("iona_training", ""))
	match stage:
		"":
			return "Iona has Resonance potential she has never trained. High influence and the right conversation could change that."
		"offered":
			return "Resonance training: offered. Talk to her when you can."
		"trained":
			return "Resonance training: complete — Iona channels Resonance."
	return "Resonance training: " + stage


# ================================================================ journal
func _tab_journal() -> void:
	var tabs := UIKit.hbox(6)
	_content.add_child(tabs)
	for jt in [["quests", "Quests"], ["choices", "Choices & consequences"], ["discoveries", "Discoveries"], ["history", "Conversations"], ["tutorials", "Tutorials"]]:
		var jid := String(jt[0])
		var b := UIKit.button(String(jt[1]), func() -> void:
			journal_tab = jid
			journal_pick = ""
			_render())
		b.toggle_mode = true
		b.button_pressed = journal_tab == jid
		tabs.add_child(b)
	match journal_tab:
		"quests":
			_journal_quests()
		"choices":
			_journal_choices()
		"discoveries":
			_journal_discoveries()
		"history":
			_journal_history()
		"tutorials":
			_journal_tutorials()


func _journal_quests() -> void:
	var cols := _columns(2)
	var c0: VBoxContainer = cols[0]
	var st := Game.state
	var order := {"active": 0, "completed": 1, "failed": 2}
	var qids: Array = st.quests.keys().filter(func(q: Variant) -> bool: return String(st.quests[q]["state"]) != "inactive")
	qids.sort_custom(func(a: Variant, b: Variant) -> bool:
		var oa: int = order.get(String(st.quests[a]["state"]), 3)
		var ob: int = order.get(String(st.quests[b]["state"]), 3)
		if oa != ob:
			return oa < ob
		return String(DB.quests.get(a, {}).get("type", "")) == "main")
	if journal_pick == "" and not qids.is_empty():
		journal_pick = String(qids[0])
	for q in qids:
		var qd: Dictionary = DB.quests.get(q, {})
		var qs := String(st.quests[q]["state"])
		var col: Color = {"active": UIKit.TEXT, "completed": UIKit.GOOD, "failed": UIKit.BAD}.get(qs, UIKit.DIM)
		var qid := String(q)
		var b := UIKit.button("%s%s  [%s]" % ["★ " if String(qd.get("type", "")) == "main" else "", qd.get("name", q), qs], func() -> void:
			journal_pick = qid
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color", col)
		b.toggle_mode = true
		b.button_pressed = journal_pick == qid
		c0.add_child(b)
	var c1: VBoxContainer = cols[1]
	if journal_pick == "" or not st.quests.has(journal_pick):
		c1.add_child(UIKit.label("No quests yet.", 16, UIKit.DIM))
		return
	var q2: Dictionary = st.quests[journal_pick]
	var qd2: Dictionary = DB.quests.get(journal_pick, {})
	c1.add_child(UIKit.label(String(qd2.get("name", journal_pick)), 26, UIKit.ACCENT2))
	c1.add_child(UIKit.label(Game.fmt(String(qd2.get("summary", ""))), 16, UIKit.DIM, true))
	var stage := String(q2.get("stage", ""))
	if stage != "":
		c1.add_child(UIKit.label(Game.fmt(String(DB.dict(DB.dict(qd2, "stages"), stage).get("text", ""))), 17, UIKit.TEXT, true))
	if String(q2.get("outcome", "")) != "":
		c1.add_child(UIKit.label("Outcome: " + Game.fmt(String(q2["outcome"])), 17, UIKit.ACCENT2, true))
	c1.add_child(UIKit.header("Objectives"))
	for o in QuestSystem.active_objectives(st, journal_pick):
		var mark: String = {"active": "○", "completed": "●", "failed": "✕"}.get(String(o["state"]), "○")
		var col2: Color = {"active": UIKit.TEXT, "completed": UIKit.GOOD, "failed": UIKit.BAD}.get(String(o["state"]), UIKit.TEXT)
		c1.add_child(UIKit.label("%s %s%s" % [mark, o["text"], "  (optional)" if bool(o["optional"]) else ""], 16, col2, true))
	c1.add_child(UIKit.header("Log"))
	var lg: Array = q2.get("log", [])
	for i in range(lg.size() - 1, -1, -1):
		c1.add_child(UIKit.label("%s  %s" % [_fmt_time(float(lg[i].get("t", 0))), Game.fmt(String(lg[i].get("text", "")))], 14, UIKit.DIM, true))


func _journal_choices() -> void:
	var cols := _columns(2)
	var c0: VBoxContainer = cols[0]
	var st := Game.state
	c0.add_child(UIKit.header("Decisions"))
	for d in [["med_supplies_choice", "Medical reserve"], ["ward_choice", "Sealed passenger ward"], ["senna_fate", "Senna Thorne"], ["evac_choice", "Launch priority"], ["archive_fate", "The Vesper archive"], ["warden_fate", "WARDEN"], ["bay_resolution", "Evacuation bay"], ["checkpoint_by", "Forward checkpoint"]]:
		var v: Variant = st.flags.get(String(d[0]), null)
		if v == null:
			continue
		c0.add_child(UIKit.label("%s: %s" % [d[1], String(v).replace("_", " ")], 16, UIKit.TEXT, true))
	c0.add_child(UIKit.label("Survivors with you: %d" % st.survivors(), 18, UIKit.ACCENT2))
	c0.add_child(UIKit.header("Alignment changes"))
	for i in range(st.alignment_log.size() - 1, -1, -1):
		var e: Dictionary = st.alignment_log[i]
		c0.add_child(UIKit.label("%+d  %s" % [int(e["delta"]), e.get("reason", "")], 14, UIKit.MERCY if int(e["delta"]) > 0 else UIKit.DOMINION, true))
	var c1: VBoxContainer = cols[1]
	c1.add_child(UIKit.header("Influence changes"))
	for i in range(st.influence_log.size() - 1, -1, -1):
		var e2: Dictionary = st.influence_log[i]
		var who := st.get_char(String(e2["companion"]))
		c1.add_child(UIKit.label("%s %+d  %s" % [who.display_name if who != null else e2["companion"], int(e2["delta"]), e2.get("reason", "")], 14, UIKit.GOOD if int(e2["delta"]) > 0 else UIKit.BAD, true))


func _journal_discoveries() -> void:
	var cols := _columns(2)
	var c0: VBoxContainer = cols[0]
	var st := Game.state
	if st.discoveries.is_empty():
		c0.add_child(UIKit.label("Read terminals, datapads and logs to fill the codex.", 16, UIKit.DIM, true))
	for cid in st.discoveries:
		var cd: Dictionary = DB.codex.get(cid, {})
		var b := UIKit.button("%s  [%s]" % [cd.get("title", cid), cd.get("category", "")], func() -> void:
			journal_pick = cid
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = journal_pick == cid
		c0.add_child(b)
	var c1: VBoxContainer = cols[1]
	if journal_pick != "" and DB.codex.has(journal_pick):
		var cd2: Dictionary = DB.codex[journal_pick]
		c1.add_child(UIKit.label(String(cd2.get("title", "")), 24, UIKit.ACCENT2))
		c1.add_child(UIKit.label(Game.fmt(String(cd2.get("text", ""))), 16, UIKit.TEXT, true))


func _journal_history() -> void:
	var h := Game.state.dialogue_history
	var out: PackedStringArray = []
	for i in range(maxi(0, h.size() - 300), h.size()):
		var e: Dictionary = h[i]
		var sp := String(e.get("speaker", ""))
		var tx := String(e.get("text", "")).replace("[", "(").replace("]", ")")
		out.append(("[color=#f2c26b]%s:[/color] %s" % [sp, tx]) if sp != "" else "[color=#9c958a][i]%s[/i][/color]" % tx)
	var r := UIKit.rich("\n".join(out) if not out.is_empty() else "[color=#9c958a]No conversations yet.[/color]", 15, false)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.scroll_following = true
	_content.add_child(UIKit.panel(r))
	(r.get_parent() as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL


func _journal_tutorials() -> void:
	var cols := _columns(2)
	var c0: VBoxContainer = cols[0]
	var ids: Array = DB.tutorials.keys().filter(func(k: Variant) -> bool: return not String(k).begins_with("_"))
	for tid in ids:
		var td: Dictionary = DB.tutorials[tid]
		var seen := Game.state.tutorials_seen.has(tid)
		var t2 := String(tid)
		var b := UIKit.button("%s%s" % [td.get("title", tid), "" if seen else "  (not yet shown)"], func() -> void:
			journal_pick = t2
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = journal_pick == t2
		c0.add_child(b)
	var c1: VBoxContainer = cols[1]
	if journal_pick != "" and DB.tutorials.has(journal_pick):
		var td2: Dictionary = DB.tutorials[journal_pick]
		c1.add_child(UIKit.label(String(td2.get("title", "")), 24, UIKit.ACCENT2))
		c1.add_child(UIKit.rich(_keys(String(td2.get("text", ""))), 17))


func _keys(t: String) -> String:
	var out := t
	for a in Settings.ACTION_LABELS.keys():
		out = out.replace("{key:%s}" % a, "[color=#f2c26b]%s[/color]" % Settings.key_label(a))
	return out


func _fmt_time(t: float) -> String:
	return "%02d:%02d" % [int(t) / 60, int(t) % 60]


# ================================================================ map
func _tab_map() -> void:
	var w := world()
	var h := UIKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(h)
	if w != null:
		var mm := MiniMap.new()
		mm.world = w
		mm.full = true
		mm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mm.size_flags_vertical = Control.SIZE_EXPAND_FILL
		mm.custom_minimum_size = Vector2(1100, 640)
		h.add_child(mm)
	var leg := UIKit.vbox(6)
	leg.custom_minimum_size = Vector2(420, 0)
	h.add_child(leg)
	leg.add_child(UIKit.header("Legend"))
	leg.add_child(UIKit.rich("[color=#7fd0ff]●[/color] you   [color=#5fd38a]●[/color] party\n[color=#ff5a4a]▲[/color] hostile (seen)   [color=#f2c26b]■[/color] person\n[color=#f2c26b]■[/color] unlooted container   [color=#5fd38a]●[/color] station\n[color=#7fd0ff]□[/color] door   [color=#ff6a5a]□[/color] locked door   [color=#ff5a4a]✕[/color] known mine/hazard", 16))
	leg.add_child(UIKit.label("Only areas you have seen are drawn.", 14, UIKit.DIM, true))
	leg.add_child(UIKit.header("Areas"))
	var areas: Dictionary = DB.layout.get("areas", {})
	for aid in areas.keys():
		var visited := Game.state.areas_visited.has(String(aid))
		var here := Game.state.area == String(aid)
		leg.add_child(UIKit.label("%s%s" % ["▶ " if here else "", String(areas[aid].get("name", aid)) if visited else "??? (unexplored)"], 15, UIKit.ACCENT2 if here else (UIKit.TEXT if visited else UIKit.DIM)))


# ================================================================ controls
func _tab_controls() -> void:
	var cols := _columns(2)
	var keys: Array = Settings.ACTION_LABELS.keys()
	var half := ceili(keys.size() / 2.0)
	for i in keys.size():
		var a := String(keys[i])
		var c: VBoxContainer = cols[0] if i < half else cols[1]
		c.add_child(_stat_row(String(Settings.ACTION_LABELS[a]), Settings.key_label(a), ""))
	var c1: VBoxContainer = cols[1]
	c1.add_child(UIKit.sep())
	c1.add_child(UIKit.label("Mouse: left-click to move, target, talk or interact; right-drag to orbit the camera; wheel to zoom. Double-click a hostile to attack. Click a portrait to select a party member.", 15, UIKit.DIM, true))
	if main != null and main.has_method("open_settings"):
		c1.add_child(UIKit.button("Rebind keys in Settings…", func() -> void: main.open_settings()))
