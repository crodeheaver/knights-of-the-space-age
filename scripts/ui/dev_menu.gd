class_name DevMenu
extends PanelBase
## Developer menu (F12 when Developer Mode is on, or --dev). Load presets,
## grant experience, set alignment and influence, heal, clear hostiles,
## start any conversation or minigame, adopt a specialization, and inspect
## flags and recent skill checks. Using it marks the game as a dev game.

var _body: VBoxContainer
var _section := "presets"
var _filter := ""


func build() -> void:
	var v := make_window("Developer Menu", Vector2(1400, 880))
	v.add_child(UIKit.label("Testing tools. Saves made after using these are tagged [DEV].", 15, UIKit.WARN))
	var tabs := UIKit.hbox(6)
	v.add_child(tabs)
	for t in [["presets", "Presets"], ["party", "Party & alignment"], ["world", "World"], ["dialogue", "Dialogues & minigames"], ["state", "Flags & checks"]]:
		var tid := String(t[0])
		var b := UIKit.button(String(t[1]), func() -> void:
			_section = tid
			_render())
		tabs.add_child(b)
	_body = UIKit.vbox(6)
	v.add_child(UIKit.scroll(_body))
	if Game.state != null:
		Game.state.dev_mode = true
	_render()


func _render() -> void:
	UIKit.clear(_body)
	match _section:
		"presets":
			for pid in DevTools.preset_ids():
				var pd: Dictionary = DB.dev_presets[pid]
				var p2 := pid
				var b := UIKit.button("%s — %s" % [pd.get("name", pid), pd.get("desc", "")], func() -> void:
					if main != null:
						main.close_panel(self)
					DevTools.load_preset(p2))
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
				b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_body.add_child(b)
		"party":
			_party()
		"world":
			_world()
		"dialogue":
			_dialogues()
		"state":
			_state()


func _party() -> void:
	var st := Game.state
	_body.add_child(UIKit.button("Grant one level of experience to everyone", func() -> void:
		DevTools.grant_levels(1)
		_render()))
	_body.add_child(UIKit.button("Fully heal and restore the party", func() -> void:
		for uid in st.roster:
			var s := st.get_char(uid)
			StatusRules.remove(s, "downed")
			s.hp = s.max_hp()
			s.energy = s.max_energy()
		_render()))
	_body.add_child(UIKit.button("Open Specialization screen", func() -> void:
		var pu := PrestigeUI.new()
		pu.main = main
		main.push_panel(pu)))
	_body.add_child(UIKit.header("Alignment: %s (%+d)" % [GameState.alignment_label(st.alignment), st.alignment]))
	var al := HSlider.new()
	al.min_value = -100
	al.max_value = 100
	al.step = 5
	al.value = st.alignment
	al.custom_minimum_size = Vector2(600, 28)
	al.value_changed.connect(func(v: float) -> void: DevTools.set_alignment(int(v)))
	al.drag_ended.connect(func(_c: bool) -> void: _render())
	_body.add_child(al)
	for cid in ["iona", "tav7"]:
		if not st.influence.has(cid):
			continue
		var c2: String = cid
		_body.add_child(UIKit.header("Influence: %s %d" % [cid, int(st.influence[cid])]))
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 100
		sl.step = 5
		sl.value = int(st.influence[cid])
		sl.custom_minimum_size = Vector2(600, 28)
		sl.value_changed.connect(func(v: float) -> void: DevTools.set_influence(c2, int(v)))
		sl.drag_ended.connect(func(_c: bool) -> void: _render())
		_body.add_child(sl)
	for cid2 in ["iona", "tav7"]:
		if not st.roster.has(cid2):
			var c3: String = cid2
			_body.add_child(UIKit.button("Recruit %s" % c3, func() -> void:
				var w := world()
				if w != null:
					Effects.apply_all([{"join_party": c3}], st)
				else:
					Game.recruit(c3)
				_render()))


func _world() -> void:
	var w := world()
	if w == null:
		_body.add_child(UIKit.label("No ship loaded.", 16, UIKit.DIM))
		return
	_body.add_child(UIKit.button("Defeat every alert hostile", func() -> void:
		for o in w.actors.values():
			var a: Actor = o
			if a.role == "enemy" and a.alert and not a.sheet.dead:
				a.sheet.hp = 0
				w.on_downed(a, "player")
		_render()))
	_body.add_child(UIKit.button("Rest now (ignore nearby hostiles)", func() -> void:
		for p in w.party_actors():
			var s := (p as Actor).sheet
			StatusRules.remove(s, "downed")
			s.hp = s.max_hp()
			s.energy = s.max_energy()
		w.hud_changed.emit()))
	_body.add_child(UIKit.header("Teleport the party"))
	for sid in DB.dev_stages.keys():
		var sg: Dictionary = DB.dev_stages[sid]
		var pos: Array = sg.get("pos", [0, 0, 0])
		var s2 := String(sid)
		_body.add_child(UIKit.button("%s (%.0f, %.0f) — position only; story state is unchanged" % [s2.capitalize(), float(pos[0]), float(pos[1])], func() -> void:
			Effects.apply_all([{"teleport": [float(pos[0]), float(pos[1])]}], Game.state)
			main.close_panel(self)))


func _dialogues() -> void:
	var w := world()
	_body.add_child(UIKit.header("Minigames"))
	var row := UIKit.hbox(6)
	for m in ["shards", "slipstream", "turret_practice"]:
		var mid: String = m
		row.add_child(UIKit.button(mid, func() -> void:
			main.close_panel(self)
			Minigames.open(main, mid)))
	_body.add_child(row)
	_body.add_child(UIKit.header("Start a conversation"))
	var ids: Array = DB.dialogues.keys()
	ids.sort()
	for did in ids:
		var d2 := String(did)
		var b := UIKit.button(d2, func() -> void:
			if w != null:
				main.close_panel(self)
				w.start_dialogue(d2))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = w == null
		_body.add_child(b)


func _state() -> void:
	var st := Game.state
	var fe := LineEdit.new()
	fe.placeholder_text = "filter flags"
	fe.text = _filter
	fe.text_submitted.connect(func(t: String) -> void:
		_filter = t
		_render())
	_body.add_child(fe)
	var keys: Array = st.flags.keys()
	keys.sort()
	var lines: PackedStringArray = []
	for k in keys:
		if _filter == "" or String(k).contains(_filter):
			lines.append("%s = %s" % [k, str(st.flags[k])])
	_body.add_child(UIKit.label("\n".join(lines), 14, UIKit.TEXT, true))
	_body.add_child(UIKit.header("Resolved checks (one roll each, no save-scum rerolls)"))
	var cl: PackedStringArray = []
	for k in st.checks.keys():
		var c: Dictionary = st.checks[k]
		cl.append("%s: %s" % [k, "success" if bool(c.get("success", false)) else "failure"])
	_body.add_child(UIKit.label("\n".join(cl) if not cl.is_empty() else "none", 14, UIKit.DIM, true))
