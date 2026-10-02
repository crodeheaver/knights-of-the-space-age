class_name LevelUpUI
extends PanelBase
## Level-up for one character: attribute increase (on increase levels), skill
## ranks, feats and powers, with a live preview. "Recommended" fills the same
## choices the playthrough bots use; "Confirm" goes through
## Progression.apply_level_up, which re-validates everything.

var uid := "player"
var choices: Dictionary = {"attr": "", "skills": {}, "feats": [], "powers": []}
var _body: VBoxContainer
var _msg: Label
var _confirm: Button


func build() -> void:
	var s := _sheet()
	var v := make_window("Level Up — %s" % (s.display_name if s != null else "?"), Vector2(1500, 900))
	_body = UIKit.vbox(8)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_body)
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	v.add_child(_msg)
	var nav := UIKit.hbox(10)
	v.add_child(nav)
	nav.add_child(UIKit.button("Recommended", _recommend, "Fill every choice from this character's recommended priorities."))
	nav.add_child(UIKit.button("Clear choices", func() -> void:
		choices = {"attr": "", "skills": {}, "feats": [], "powers": []}
		_render()))
	nav.add_child(UIKit.expand(UIKit.spacer()))
	_confirm = UIKit.button("Confirm level %d" % (s.level + 1 if s != null else 0), _apply)
	_confirm.custom_minimum_size = Vector2(260, 46)
	nav.add_child(_confirm)
	_render()


func _sheet() -> CharacterSheet:
	return Game.state.get_char(uid) if Game.state != null else null


func _recommend() -> void:
	choices = Progression.recommended_choices(_sheet())
	_msg.text = "Recommended choices filled in. Review or change them, then confirm."
	_render()


func _apply() -> void:
	var s := _sheet()
	var r := Progression.apply_level_up(s, choices)
	if not bool(r["ok"]):
		_msg.text = "Cannot confirm: " + "; ".join(r["errors"])
		GameAudio.play("ui_error", -6.0)
		return
	Events.toast("%s reached level %d." % [s.display_name, s.level], "quest")
	if s.levels_available() > 0:
		choices = {"attr": "", "skills": {}, "feats": [], "powers": []}
		(win["title"] as Label).text = "Level Up — %s" % s.display_name
		_confirm.text = "Confirm level %d" % (s.level + 1)
		_msg.text = "Another level is available."
		_render()
	else:
		request_close()


func _render() -> void:
	var s := _sheet()
	UIKit.clear(_body)
	if s == null or s.levels_available() <= 0:
		_body.add_child(UIKit.label("No level-up available.", 18, UIKit.DIM))
		_confirm.disabled = true
		return
	var pv := Progression.preview(s)
	var tmp := Progression.staged_sheet(s, choices)
	var h := UIKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(h)
	var cols: Array = []
	for i in 3:
		var c := UIKit.vbox(6)
		var p := UIKit.panel(UIKit.scroll(c))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(p)
		cols.append(c)
	# Summary + attribute.
	var c0: VBoxContainer = cols[0]
	c0.add_child(UIKit.label("Level %d → %d" % [s.level, int(pv["level"])], 24, UIKit.ACCENT2))
	c0.add_child(UIKit.label("Health +%d · Energy +%d · Base attack +%d" % [int(pv["hp_gain"]), int(pv["energy_gain"]), int(pv["bab"])], 17))
	var cf: Array = pv["class_features"]
	if not cf.is_empty():
		c0.add_child(UIKit.label("New class features: " + ", ".join(cf.map(func(f: Variant) -> String: return String(DB.feat(String(f)).get("name", f)))), 16, UIKit.GOOD, true))
	if bool(pv["attr_increase"]):
		c0.add_child(UIKit.header("Attribute increase (+1)"))
		for a in Rules.ATTRS:
			var aid := String(a)
			var b := UIKit.button("%s %d → %d" % [Rules.ATTR_NAMES[a], s.attr_perm(a), s.attr_perm(a) + (1 if String(choices["attr"]) == aid else 0)], func() -> void:
				choices["attr"] = aid
				_render())
			b.toggle_mode = true
			b.button_pressed = String(choices["attr"]) == aid
			c0.add_child(b)
	else:
		c0.add_child(UIKit.label("No attribute increase at this level (next at levels %s)." % ", ".join(DB.int_arr(DB.progression.get("attribute_increase_levels", [])).map(func(x: int) -> String: return str(x))), 15, UIKit.DIM, true))
	c0.add_child(UIKit.sep())
	c0.add_child(UIKit.header("After this level"))
	var tmp2 := _final_preview(s)
	c0.add_child(UIKit.label("Health %d · Energy %d · Defense %d" % [tmp2.max_hp(), tmp2.max_energy(), tmp2.defense()], 16))
	c0.add_child(UIKit.label("Fort %+d · Ref %+d · Will %+d" % [tmp2.save_total("fort"), tmp2.save_total("ref"), tmp2.save_total("will")], 16))
	# Skills.
	var c1: VBoxContainer = cols[1]
	var points := int(pv["skill_points"])
	var added: Dictionary = choices["skills"]
	var spent := BuildValidator.skill_spend(s.class_id, added)
	c1.add_child(UIKit.header("Skills — %d of %d points left" % [points - spent, points]))
	if s.skill_bank > 0:
		c1.add_child(UIKit.label("Includes %d banked point(s) from earlier levels." % s.skill_bank, 14, UIKit.DIM))
	for sid in DB.skill_ids():
		var cur := int(s.skill_ranks.get(sid, 0))
		var add := int(added.get(sid, 0))
		var mx := BuildValidator.max_rank(s.class_id, sid, tmp.level)
		var cost := BuildValidator.rank_cost(s.class_id, sid)
		var row := UIKit.hbox(6)
		var nl := UIKit.label("%s%s" % [DB.skill(sid)["name"], " ★" if s.is_class_skill(sid) else ""], 16)
		nl.custom_minimum_size = Vector2(190, 0)
		row.add_child(nl)
		var mb := UIKit.button("−", _adj_skill.bind(sid, -1))
		mb.disabled = add <= 0
		row.add_child(mb)
		row.add_child(UIKit.label("%d%s / %d" % [cur + add, " (+%d)" % add if add > 0 else "", mx], 16, UIKit.GOOD if add > 0 else UIKit.TEXT))
		var pb := UIKit.button("+", _adj_skill.bind(sid, 1), "Costs %d" % cost)
		pb.disabled = cur + add >= mx or spent + cost > points
		row.add_child(pb)
		c1.add_child(row)
	if points - spent > 0:
		c1.add_child(UIKit.label("Unspent points are banked for your next level.", 14, UIKit.DIM, true))
	# Feats and powers.
	var c2: VBoxContainer = cols[2]
	var fp := int(pv["feat_picks"])
	var chosen_f: Array = choices["feats"]
	c2.add_child(UIKit.header("Feats — %d of %d" % [chosen_f.size(), fp]))
	if fp > 0:
		var owned: Array[String] = tmp.feats.duplicate()
		for f in chosen_f:
			owned.append(String(f))
		var cand: Array = BuildValidator.selectable_feats(tmp, owned)
		for f in chosen_f:
			if not cand.has(f):
				cand.push_front(f)
		for fid in cand:
			var fd: Dictionary = DB.feat(String(fid))
			var sel := chosen_f.has(fid)
			var f2 := String(fid)
			var b := UIKit.button("%s%s — %s" % ["✓ " if sel else "", fd.get("name", fid), fd.get("desc", "")], func() -> void: _toggle("feats", f2, fp))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.toggle_mode = true
			b.button_pressed = sel
			b.disabled = not sel and chosen_f.size() >= fp
			c2.add_child(b)
	else:
		c2.add_child(UIKit.label("No feat at this level.", 15, UIKit.DIM))
	var pp := int(pv["power_picks"])
	var chosen_p: Array = choices["powers"]
	c2.add_child(UIKit.header("Powers — %d of %d" % [chosen_p.size(), pp]))
	if pp > 0:
		var pown: Array[String] = tmp.powers.duplicate()
		for p in chosen_p:
			pown.append(String(p))
		var pc: Array = BuildValidator.selectable_powers(tmp, pown)
		for p in chosen_p:
			if not pc.has(p):
				pc.push_front(p)
		for pid in pc:
			var pd: Dictionary = DB.power(String(pid))
			var sel2 := chosen_p.has(pid)
			var p2 := String(pid)
			var b2 := UIKit.button("%s%s [%s, %d] — %s" % ["✓ " if sel2 else "", pd.get("name", pid), String(pd.get("school", "")).capitalize(), int(pd.get("cost", 0)), pd.get("desc", "")], func() -> void: _toggle("powers", p2, pp))
			b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b2.toggle_mode = true
			b2.button_pressed = sel2
			b2.disabled = not sel2 and chosen_p.size() >= pp
			c2.add_child(b2)
	else:
		c2.add_child(UIKit.label("No power at this level.", 15, UIKit.DIM))
	var errs := Progression.validate(s, choices)
	_confirm.disabled = not errs.is_empty()
	if not errs.is_empty():
		_confirm.tooltip_text = "; ".join(errs)
	else:
		_confirm.tooltip_text = ""


func _final_preview(s: CharacterSheet) -> CharacterSheet:
	var tmp := CharacterSheet.from_dict(s.to_dict())
	# A dry run on a copy: keep its level_up event off the bus.
	var was_muted := Events.muted
	Events.muted = true
	var r := Progression.apply_level_up(tmp, choices.duplicate(true))
	Events.muted = was_muted
	if not bool(r["ok"]):
		return Progression.staged_sheet(s, choices)
	return tmp


func _adj_skill(sid: String, d: int) -> void:
	var added: Dictionary = choices["skills"]
	var n := int(added.get(sid, 0)) + d
	if n <= 0:
		added.erase(sid)
	else:
		added[sid] = n
	_render()


func _toggle(key: String, id: String, cap: int) -> void:
	var l: Array = choices[key]
	if l.has(id):
		l.erase(id)
	elif l.size() < cap:
		l.append(id)
	_render()
