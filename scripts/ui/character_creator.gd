class_name CharacterCreator
extends Control
## Character creation: archetype, background, 30-point attribute buy, skills,
## feats, powers, appearance and identity, then a summary with difficulty.
## Every rule check goes through BuildValidator, so the creator, level-up,
## developer presets and tests agree. Back/Next never lose choices; changing
## archetype clears only the choices that no longer fit.

const STEPS := ["Archetype", "Background", "Attributes", "Skills", "Feats", "Powers", "Appearance", "Summary"]
const ATTR_DESC := {
	"str": "Melee attack and damage, carrying heavy weapons.",
	"dex": "Ranged attack, Defense, Reflex saves, Stealth.",
	"con": "Health per level, Fortitude saves.",
	"int": "Skill points per level, Computer Use, Demolitions, Repair.",
	"wis": "Resonance energy, Will saves, Awareness, Medicine.",
	"cha": "Persuasion and the strength of mind-affecting powers.",
}

var main: Node
var build: Dictionary = {}
var step := 0
var difficulty := "standard"

var _steps_box: VBoxContainer
var _content: VBoxContainer
var _title: Label
var _stats: RichTextLabel
var _back_btn: Button
var _next_btn: Button
var _msg: Label
var _vp: SubViewport
var _preview_root: Node3D
var _visual: ActorVisual
var _yaw := 0.0
var _auto_rotate := true
var _dragging := false


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build = BuildValidator.recommended("vanguard")
	build["name"] = ""
	_layout()
	_refresh()


# ================================================================ layout
func _layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#06080c")
	UIKit.full_rect(bg)
	add_child(bg)
	var root := UIKit.hbox(14)
	UIKit.anchor(root, Vector4(0, 0, 1, 1), Vector4(24, 20, -24, -20))
	add_child(root)
	# Left: step list.
	var left := UIKit.vbox(6)
	left.custom_minimum_size = Vector2(250, 0)
	root.add_child(left)
	left.add_child(UIKit.label("NEW OPERATOR", 26, UIKit.ACCENT2))
	left.add_child(UIKit.label("Build your character", 15, UIKit.DIM))
	left.add_child(UIKit.spacer(0, 10))
	_steps_box = UIKit.vbox(4)
	left.add_child(_steps_box)
	left.add_child(UIKit.spacer(0, 16))
	var rec := UIKit.button("Use Recommended Build", _use_recommended, "Fill every step with the recommended build for this archetype. You can still change anything.")
	left.add_child(rec)
	left.add_child(UIKit.button("Back to Title", func() -> void: main.show_main_menu()))
	# Centre: step content.
	var mid := UIKit.vbox(8)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	_title = UIKit.label("", 30, UIKit.ACCENT2)
	mid.add_child(_title)
	mid.add_child(UIKit.sep())
	_content = UIKit.vbox(8)
	mid.add_child(UIKit.scroll(_content))
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	mid.add_child(_msg)
	var nav := UIKit.hbox(10)
	mid.add_child(nav)
	_back_btn = UIKit.button("◀ Back", func() -> void: _go(step - 1))
	_back_btn.custom_minimum_size = Vector2(160, 46)
	nav.add_child(_back_btn)
	nav.add_child(UIKit.expand(UIKit.spacer()))
	_next_btn = UIKit.button("Next ▶", _on_next)
	_next_btn.custom_minimum_size = Vector2(220, 46)
	nav.add_child(_next_btn)
	# Right: preview + derived stats.
	var right := UIKit.vbox(8)
	right.custom_minimum_size = Vector2(420, 0)
	root.add_child(right)
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.custom_minimum_size = Vector2(420, 470)
	vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	vpc.gui_input.connect(_preview_input)
	vpc.tooltip_text = "Drag to rotate"
	right.add_child(vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vpc.add_child(_vp)
	_build_preview_scene()
	var rot_row := UIKit.hbox(6)
	right.add_child(rot_row)
	rot_row.add_child(UIKit.button("⟲", func() -> void: _yaw -= 0.6, "Rotate left"))
	rot_row.add_child(UIKit.button("⟳", func() -> void: _yaw += 0.6, "Rotate right"))
	var ar := CheckBox.new()
	ar.text = "Auto-rotate"
	ar.button_pressed = true
	ar.toggled.connect(func(v: bool) -> void: _auto_rotate = v)
	rot_row.add_child(ar)
	_stats = UIKit.rich("", 16)
	right.add_child(UIKit.panel(_stats))


func _build_preview_scene() -> void:
	_preview_root = Node3D.new()
	_vp.add_child(_preview_root)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.15, 4.4)
	cam.fov = 36
	_preview_root.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0), Vector3.UP)
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.2
	_preview_root.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.4, 2.0, -1.2)
	rim.light_color = Color("#e8823a")
	rim.light_energy = 1.6
	rim.omni_range = 6
	_preview_root.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(1.6, 1.0, 1.6)
	fill.light_color = Color("#7fd0ff")
	fill.light_energy = 0.6
	fill.omni_range = 6
	_preview_root.add_child(fill)
	var floor_mi := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.04
	floor_mi.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color("#1b1f26")
	fm.emission_enabled = true
	fm.emission = Color("#e8823a") * 0.08
	floor_mi.material_override = fm
	floor_mi.position = Vector3(0, -0.02, 0)
	_preview_root.add_child(floor_mi)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0b0e13")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#5a6070")
	e.ambient_light_energy = 0.7
	env.environment = e
	_preview_root.add_child(env)


func _preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_dragging = (ev as InputEventMouseButton).pressed
	elif ev is InputEventMouseMotion and _dragging:
		_yaw += (ev as InputEventMouseMotion).relative.x * 0.01


func _process(delta: float) -> void:
	if _auto_rotate and not _dragging:
		_yaw += delta * 0.5
	if _visual != null:
		_visual.rotation.y = _yaw
		_visual.animate(delta, 0.0)


func _refresh_preview() -> void:
	if _visual != null:
		_visual.queue_free()
	_visual = ActorVisual.new()
	_preview_root.add_child(_visual)
	var s := _preview_sheet()
	_visual.build("humanoid", build.get("appearance", {}), s)
	if _visual.ring != null:
		_visual.ring.visible = false
	if _visual.marker != null:
		_visual.marker.visible = false


# ================================================================ state
## A sheet with the archetype's starting equipment, used for live stats.
func _preview_sheet() -> CharacterSheet:
	var s := BuildValidator.make_sheet(build)
	var se: Dictionary = DB.dict(DB.klass(String(build.get("class", "vanguard"))), "starting_equipment")
	for slot in se.keys():
		s.set_slot(String(slot), ItemInst.make(String(se[slot])))
	s.mark_dirty()
	s.hp = s.max_hp()
	s.energy = s.max_energy()
	return s


func _cls() -> String:
	return String(build.get("class", "vanguard"))


func _attrs() -> Dictionary:
	if not build.has("attrs"):
		build["attrs"] = {}
	return build["attrs"]


func _skills() -> Dictionary:
	if not build.has("skills"):
		build["skills"] = {}
	return build["skills"]


func _list(key: String) -> Array:
	if not build.has(key):
		build[key] = []
	return build[key]


func _go(i: int) -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	_msg.text = ""
	_refresh()


func _on_next() -> void:
	if step == STEPS.size() - 1:
		_begin()
		return
	var warn := _step_warning(step)
	if warn != "":
		_msg.text = warn + "  (You can continue; the summary lists anything left unspent.)"
	_go(step + 1)
	if warn != "":
		_msg.text = warn + " — you can come back to it."


func _step_warning(i: int) -> String:
	var u := BuildValidator.unspent(build)
	match STEPS[i]:
		"Attributes":
			if int(u["attr_points"]) > 0:
				return "%d attribute point(s) unspent." % int(u["attr_points"])
		"Skills":
			if int(u["skill_points"]) > 0:
				return "%d skill point(s) unspent." % int(u["skill_points"])
		"Feats":
			if int(u["feats"]) > 0:
				return "%d feat pick(s) unspent." % int(u["feats"])
		"Powers":
			if int(u["powers"]) > 0:
				return "%d power pick(s) unspent." % int(u["powers"])
	return ""


func _use_recommended() -> void:
	var keep_name := String(build.get("name", ""))
	var keep_pron := String(build.get("pronouns", "they"))
	var keep_app: Dictionary = (build.get("appearance", {}) as Dictionary).duplicate()
	build = BuildValidator.recommended(_cls())
	if keep_name != "":
		build["name"] = keep_name
	build["pronouns"] = keep_pron
	if not keep_app.is_empty():
		build["appearance"] = keep_app
	_msg.text = "Recommended %s build applied. Review the summary or adjust any step." % DB.klass(_cls()).get("name", "")
	_refresh()


func _set_class(cid: String) -> void:
	if cid == _cls():
		return
	build["class"] = cid
	# Skills, feats and powers depend on the archetype; attributes, background
	# and appearance carry over.
	build["skills"] = {}
	build["feats"] = []
	build["powers"] = []
	_msg.text = "Archetype changed: skills, feats and powers were reset. Use Recommended Build to fill them."
	_refresh()


func _begin() -> void:
	var errs := BuildValidator.validate_build(build)
	if not errs.is_empty():
		_msg.text = "Fix before starting: " + "; ".join(errs)
		return
	build["name"] = String(build["name"]).strip_edges()
	main.start_new_game(build, difficulty)


# ================================================================ render
func _refresh() -> void:
	UIKit.clear(_steps_box)
	for i in STEPS.size():
		var label := "%d. %s" % [i + 1, STEPS[i]]
		if _step_warning(i) != "":
			label += "  •"
		var b := UIKit.button(label, _go.bind(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_pressed = i == step
		_steps_box.add_child(b)
	_title.text = STEPS[step]
	_back_btn.disabled = step == 0
	_next_btn.text = "Begin the Escape ▶" if step == STEPS.size() - 1 else "Next ▶"
	_next_btn.disabled = false
	UIKit.clear(_content)
	match STEPS[step]:
		"Archetype":
			_step_archetype()
		"Background":
			_step_background()
		"Attributes":
			_step_attributes()
		"Skills":
			_step_skills()
		"Feats":
			_step_feats()
		"Powers":
			_step_powers()
		"Appearance":
			_step_appearance()
		"Summary":
			_step_summary()
	_refresh_stats()
	_refresh_preview()


func _refresh_stats() -> void:
	var s := _preview_sheet()
	var snap := EquipmentRules.snapshot(s)
	var t := "[b]%s[/b]  [color=#9c958a]%s · %s[/color]\n" % [String(build.get("name", "")) if String(build.get("name", "")) != "" else "(unnamed)", DB.klass(_cls()).get("name", ""), DB.backgrounds.get(String(build.get("background", "")), {}).get("name", "no background")]
	t += "Health [b]%d[/b]   Energy [b]%d[/b]   Defense [b]%d[/b]\n" % [s.max_hp(), s.max_energy(), s.defense()]
	t += "Attack %+d   Avg damage %.1f\n" % [int(snap["Attack"]), float(snap["Avg damage"])]
	t += "Fort %+d  Ref %+d  Will %+d\n" % [s.save_total("fort"), s.save_total("ref"), s.save_total("will")]
	var sk: PackedStringArray = []
	for sid in DB.skill_ids():
		sk.append("%s %+d" % [String(DB.skill(sid)["name"]).split(" ")[0], s.skill_total(sid)])
	t += "[color=#9c958a]" + ", ".join(sk) + "[/color]"
	_stats.text = t


func _row(parts: Array) -> HBoxContainer:
	var h := UIKit.hbox(8)
	for p in parts:
		h.add_child(p)
	return h


func _card(title: String, body: String, selected: bool, cb: Callable, disabled_reason: String = "") -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = selected
	b.text = title + "\n" + body
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(0, 70)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if disabled_reason != "":
		b.disabled = true
		b.tooltip_text = disabled_reason
	b.pressed.connect(cb)
	b.pressed.connect(func() -> void: GameAudio.play("ui_click", -10.0))
	return b


# ---------------------------------------------------------------- steps
func _step_archetype() -> void:
	_content.add_child(UIKit.label("Your archetype sets health, attack progression, class skills, and how many feats and powers you gain. All three can use the Lumen Edge and Resonance.", 17, UIKit.DIM, true))
	for cid in ["vanguard", "operative", "adept"]:
		var k: Dictionary = DB.klass(cid)
		var body := "%s\nHealth %d +%d/level · Energy %d +%d/level · Class skills: %s" % [k.get("desc", ""), int(k.get("hp_first", 0)), int(k.get("hp_per_level", 0)), int(k.get("energy_base", 0)), int(k.get("energy_per_level", 0)),
			", ".join(DB.arr(k, "class_skills").map(func(x: Variant) -> String: return String(DB.skill(String(x)).get("name", x))))]
		_content.add_child(_card(String(k.get("name", cid)).to_upper() + " — " + String(k.get("summary", "")), body, cid == _cls(), _set_class.bind(cid)))


func _step_background() -> void:
	_content.add_child(UIKit.label("Your background gives a small skill bonus, starting gear and credits, and opens dialogue options with certain people aboard.", 17, UIKit.DIM, true))
	for bid in DB.backgrounds.keys():
		if String(bid).begins_with("_"):
			continue
		var bd: Dictionary = DB.backgrounds[bid]
		var cb := func() -> void:
			build["background"] = String(bid)
			_refresh()
		_content.add_child(_card(String(bd.get("name", bid)), "%s\n[%s]" % [bd.get("desc", ""), bd.get("benefit", "")], String(build.get("background", "")) == String(bid), cb))


func _step_attributes() -> void:
	var at := _attrs()
	var rem := BuildValidator.points_remaining(at)
	var pbd := BuildValidator.pb()
	_content.add_child(UIKit.label("Point buy: %d points. Scores start at %d. Raising a score costs 1 point per step up to 14, 2 up to 16 and 3 up to 18." % [int(pbd.get("budget", 30)), int(pbd.get("base", 8))], 17, UIKit.DIM, true))
	_content.add_child(UIKit.label("Points remaining: %d" % rem, 22, UIKit.GOOD if rem == 0 else (UIKit.BAD if rem < 0 else UIKit.ACCENT2)))
	for a in Rules.ATTRS:
		var sc := int(at.get(a, 8))
		var m := Rules.mod(sc)
		var name_l := UIKit.label(Rules.ATTR_NAMES[a], 20)
		name_l.custom_minimum_size = Vector2(160, 0)
		var minus := UIKit.button("−", _adj_attr.bind(a, -1), BuildValidator.can_lower(at, a))
		minus.disabled = BuildValidator.can_lower(at, a) != ""
		var val := UIKit.label("%d (%+d)" % [sc, m], 20, UIKit.ACCENT2)
		val.custom_minimum_size = Vector2(90, 0)
		var why := BuildValidator.can_raise(at, a)
		var plus := UIKit.button("+", _adj_attr.bind(a, 1), why if why != "" else "Costs %d" % BuildValidator.step_cost(sc))
		plus.disabled = why != ""
		var cost := UIKit.label("next: %s" % ("—" if why != "" else str(BuildValidator.step_cost(sc))), 14, UIKit.DIM)
		cost.custom_minimum_size = Vector2(70, 0)
		var desc := UIKit.label(ATTR_DESC[a], 15, UIKit.DIM, true)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(_row([name_l, minus, val, plus, cost, desc]))
	_content.add_child(UIKit.button("Reset attributes to 8", func() -> void:
		for a in Rules.ATTRS:
			_attrs()[a] = 8
		_refresh()))


func _adj_attr(a: String, d: int) -> void:
	var at := _attrs()
	if d > 0 and BuildValidator.can_raise(at, a) == "":
		at[a] = int(at.get(a, 8)) + 1
	elif d < 0 and BuildValidator.can_lower(at, a) == "":
		at[a] = int(at.get(a, 8)) - 1
	_refresh()


func _step_skills() -> void:
	var cid := _cls()
	var sk := _skills()
	var total := BuildValidator.skill_points_for_level(cid, int(_attrs().get("int", 8)), 1)
	var spent := BuildValidator.skill_spend(cid, sk)
	_content.add_child(UIKit.label("Skill points: %d (from archetype and Intelligence; doubled at level 1). Class skills cost 1 per rank, others 2. Every skill is used somewhere aboard the Cinder Wake." % total, 17, UIKit.DIM, true))
	_content.add_child(UIKit.label("Points remaining: %d" % (total - spent), 22, UIKit.GOOD if spent == total else (UIKit.BAD if spent > total else UIKit.ACCENT2)))
	if spent > total:
		_content.add_child(UIKit.label("Lowering Intelligence reduced your points: remove ranks until you are within budget.", 16, UIKit.BAD, true))
	for sid in DB.skill_ids():
		var sd: Dictionary = DB.skill(sid)
		var cls_skill := DB.arr(DB.klass(cid), "class_skills").has(sid)
		var r := int(sk.get(sid, 0))
		var mx := BuildValidator.max_rank(cid, sid, 1)
		var cost := BuildValidator.rank_cost(cid, sid)
		var nm := UIKit.label("%s%s" % [sd["name"], " ★" if cls_skill else ""], 19, UIKit.ACCENT2 if cls_skill else UIKit.TEXT)
		nm.custom_minimum_size = Vector2(200, 0)
		nm.tooltip_text = "%s\nUsed for: %s" % [sd.get("desc", ""), sd.get("uses", "")]
		nm.mouse_filter = Control.MOUSE_FILTER_PASS
		var minus := UIKit.button("−", _adj_skill.bind(sid, -1))
		minus.disabled = r <= 0
		var val := UIKit.label("%d / %d" % [r, mx], 18)
		val.custom_minimum_size = Vector2(70, 0)
		var plus := UIKit.button("+", _adj_skill.bind(sid, 1), "Costs %d" % cost)
		plus.disabled = r >= mx or spent + cost > total
		var info := UIKit.label("%s · cost %d · %s" % [String(sd.get("attr", "")).to_upper(), cost, sd.get("desc", "")], 14, UIKit.DIM, true)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_content.add_child(_row([nm, minus, val, plus, info]))
	_content.add_child(UIKit.label("★ class skill", 14, UIKit.DIM))


func _adj_skill(sid: String, d: int) -> void:
	var sk := _skills()
	var r := int(sk.get(sid, 0)) + d
	if r <= 0:
		sk.erase(sid)
	else:
		sk[sid] = r
	_refresh()


func _step_feats() -> void:
	var cid := _cls()
	var picks := BuildValidator.feat_picks(cid, 1)
	var chosen := _list("feats")
	var s := BuildValidator.base_sheet(build)
	var granted := s.feats.duplicate()
	_content.add_child(UIKit.label("Choose %d feat(s). Feats with unmet prerequisites are shown with the reason. Granted by your archetype: %s." % [picks, ", ".join(granted.map(func(f: Variant) -> String: return String(DB.feat(String(f)).get("name", f))))], 17, UIKit.DIM, true))
	_content.add_child(UIKit.label("Picks remaining: %d" % (picks - chosen.size()), 22, UIKit.GOOD if chosen.size() == picks else UIKit.ACCENT2))
	var owned: Array[String] = granted.duplicate()
	for f in chosen:
		owned.append(String(f))
	var ids: Array = DB.feats.keys().filter(func(k: Variant) -> bool: return not String(k).begins_with("_") and not granted.has(String(k)) and not bool(DB.feat(String(k)).get("hidden", false)) and not bool(DB.feat(String(k)).get("earned", false)) and String(DB.feat(String(k)).get("category", "")) != "prestige")
	# Chosen first, then what you could take now, then the rest.
	var rank := func(k: Variant) -> int:
		if chosen.has(k):
			return 0
		return 1 if BuildValidator.feat_errors(s, String(k), owned).is_empty() else 2
	ids.sort_custom(func(x: Variant, y: Variant) -> bool:
		var rx: int = rank.call(x)
		var ry: int = rank.call(y)
		if rx != ry:
			return rx < ry
		return String(DB.feat(String(x))["name"]) < String(DB.feat(String(y))["name"]))
	for fid in ids:
		var fd: Dictionary = DB.feat(String(fid))
		var sel := chosen.has(fid)
		var errs := BuildValidator.feat_errors(s, String(fid), owned.filter(func(o: String) -> bool: return o != String(fid)))
		var reason := ""
		if not sel and not errs.is_empty():
			reason = errs[0]
		elif not sel and chosen.size() >= picks:
			reason = "No feat picks left."
		var title := String(fd["name"]) + ("  ✓" if sel else "")
		var body := String(fd.get("desc", "")) + ("" if reason == "" else "\n[Unavailable: %s]" % reason)
		var b := _card(title, body, sel, _toggle_pick.bind("feats", String(fid)), reason)
		_content.add_child(b)


func _step_powers() -> void:
	var cid := _cls()
	var picks := BuildValidator.power_picks(cid, 1)
	var chosen := _list("powers")
	var s := BuildValidator.make_sheet(build)
	_content.add_child(UIKit.label("Choose %d Resonance power(s). Mercy powers grow cheaper as your alignment moves toward Mercy, Dominion powers toward Dominion; universal powers are unaffected. Medium armor makes powers cost more; heavy armor blocks them." % picks, 17, UIKit.DIM, true))
	_content.add_child(UIKit.label("Picks remaining: %d" % (picks - chosen.size()), 22, UIKit.GOOD if chosen.size() == picks else UIKit.ACCENT2))
	var ids: Array = DB.powers.keys().filter(func(k: Variant) -> bool: return not String(k).begins_with("_") and not bool(DB.power(String(k)).get("innate", false)) and not bool(DB.power(String(k)).get("enemy_only", false)))
	var prank := func(k: Variant) -> int:
		if chosen.has(k):
			return 0
		return 1 if BuildValidator.power_errors(s, String(k), []).is_empty() else 2
	ids.sort_custom(func(x: Variant, y: Variant) -> bool:
		var rx: int = prank.call(x)
		var ry: int = prank.call(y)
		if rx != ry:
			return rx < ry
		return String(DB.power(String(x))["name"]) < String(DB.power(String(y))["name"]))
	for pid in ids:
		var pd: Dictionary = DB.power(String(pid))
		var sel := chosen.has(pid)
		var owned: Array[String] = []
		for p in chosen:
			if String(p) != String(pid):
				owned.append(String(p))
		var errs := BuildValidator.power_errors(s, String(pid), owned)
		var reason := ""
		if not sel and not errs.is_empty():
			reason = errs[0]
		elif not sel and chosen.size() >= picks:
			reason = "No power picks left."
		var school := String(pd.get("school", "universal"))
		var title := "%s  [%s · %d energy]%s" % [pd["name"], school.capitalize(), int(pd.get("cost", 0)), "  ✓" if sel else ""]
		var body := String(pd.get("desc", "")) + ("" if reason == "" else "\n[Unavailable: %s]" % reason)
		_content.add_child(_card(title, body, sel, _toggle_pick.bind("powers", String(pid)), reason))


func _toggle_pick(key: String, id: String) -> void:
	var l := _list(key)
	if l.has(id):
		l.erase(id)
		# Dropping a prerequisite drops what depended on it.
		var s := BuildValidator.base_sheet(build)
		var owned: Array[String] = s.feats.duplicate()
		for f in _list("feats"):
			owned.append(String(f))
		for f in _list("feats").duplicate():
			var others: Array[String] = owned.filter(func(o: String) -> bool: return o != String(f))
			if not BuildValidator.feat_errors(s, String(f), others).is_empty():
				_list("feats").erase(f)
	else:
		var picks := BuildValidator.feat_picks(_cls(), 1) if key == "feats" else BuildValidator.power_picks(_cls(), 1)
		if l.size() < picks:
			l.append(id)
	_refresh()


func _step_appearance() -> void:
	_content.add_child(UIKit.label("Identity", 20, UIKit.ACCENT2))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Your name"
	name_edit.max_length = BuildValidator.NAME_MAX
	name_edit.text = String(build.get("name", ""))
	name_edit.custom_minimum_size = Vector2(360, 40)
	name_edit.text_changed.connect(func(t: String) -> void:
		build["name"] = t
		_refresh_stats())
	var rnd := UIKit.button("Suggest", func() -> void:
		var names := ["Kael Varenne", "Sela Ondry", "Ilun Marro", "Teshar Vey", "Adair Quen", "Moro Halvik", "Rinna Sol", "Daven Ashe", "Juno Karrow", "Ezo Marr"]
		build["name"] = names[randi() % names.size()]
		_refresh())
	_content.add_child(_row([UIKit.label("Name", 18), name_edit, rnd]))
	var pron_row := UIKit.hbox(6)
	pron_row.add_child(UIKit.label("Pronouns", 18))
	for p in DB.arr(DB.appearance, "pronouns"):
		var pid := String(p["id"])
		var b := UIKit.button(String(p["label"]), func() -> void:
			build["pronouns"] = pid
			_refresh())
		b.toggle_mode = true
		b.button_pressed = String(build.get("pronouns", "they")) == pid
		pron_row.add_child(b)
	_content.add_child(pron_row)
	_content.add_child(UIKit.label("Pronouns are used in every line of dialogue that refers to you. Appearance is cosmetic only.", 15, UIKit.DIM, true))
	_content.add_child(UIKit.sep())
	_content.add_child(UIKit.label("Appearance", 20, UIKit.ACCENT2))
	if not build.has("appearance"):
		build["appearance"] = {}
	var app: Dictionary = build["appearance"]
	for key in [["body", "Body"], ["head", "Head"], ["hair", "Hair"], ["skin", "Skin tone"], ["hair_color", "Hair colour"], ["accent", "Accent colour"]]:
		var k := String(key[0])
		var opts: Array = DB.arr(DB.appearance, k)
		if opts.is_empty():
			continue
		var cur := 0
		for i in opts.size():
			if String(opts[i]["id"]) == String(app.get(k, opts[0]["id"])):
				cur = i
		var nm := UIKit.label(String(key[1]), 18)
		nm.custom_minimum_size = Vector2(150, 0)
		var prev := UIKit.button("◀", _cycle_app.bind(k, -1))
		var val := UIKit.label(String(opts[cur]["name"]), 18, UIKit.ACCENT2)
		val.custom_minimum_size = Vector2(170, 0)
		var nxt := UIKit.button("▶", _cycle_app.bind(k, 1))
		var parts: Array = [nm, prev, val, nxt]
		if opts[cur].has("color"):
			var sw := ColorRect.new()
			sw.color = Color(String(opts[cur]["color"]))
			sw.custom_minimum_size = Vector2(28, 28)
			parts.append(sw)
		_content.add_child(_row(parts))
	_content.add_child(UIKit.button("Randomise appearance", func() -> void:
		for k2 in ["body", "head", "hair", "skin", "hair_color", "accent"]:
			var o2: Array = DB.arr(DB.appearance, k2)
			if not o2.is_empty():
				app[k2] = String(o2[randi() % o2.size()]["id"])
		_refresh()))


func _cycle_app(k: String, d: int) -> void:
	var app: Dictionary = build["appearance"]
	var opts: Array = DB.arr(DB.appearance, k)
	var cur := 0
	for i in opts.size():
		if String(opts[i]["id"]) == String(app.get(k, opts[0]["id"])):
			cur = i
	app[k] = String(opts[posmod(cur + d, opts.size())]["id"])
	_refresh()


func _step_summary() -> void:
	var errs := BuildValidator.validate_build(build)
	var u := BuildValidator.unspent(build)
	var k: Dictionary = DB.klass(_cls())
	var bd: Dictionary = DB.backgrounds.get(String(build.get("background", "")), {})
	var t := "[b]%s[/b] (%s) — %s, %s\n\n" % [String(build.get("name", "")) if String(build.get("name", "")) != "" else "(unnamed)", _pron_label(), k.get("name", ""), bd.get("name", "no background")]
	var at := _attrs()
	var al: PackedStringArray = []
	for a in Rules.ATTRS:
		al.append("%s %d (%+d)" % [String(a).to_upper(), int(at.get(a, 8)), Rules.mod(int(at.get(a, 8)))])
	t += "[b]Attributes[/b]  " + "  ".join(al) + "\n"
	var sl: PackedStringArray = []
	for sid in _skills().keys():
		sl.append("%s %d" % [DB.skill(String(sid))["name"], int(_skills()[sid])])
	t += "[b]Skill ranks[/b]  " + (", ".join(sl) if not sl.is_empty() else "none") + "\n"
	t += "[b]Feats[/b]  " + ", ".join(_list("feats").map(func(f: Variant) -> String: return String(DB.feat(String(f)).get("name", f)))) + "\n"
	t += "[b]Powers[/b]  " + ", ".join(_list("powers").map(func(p: Variant) -> String: return String(DB.power(String(p)).get("name", p)))) + "\n"
	t += "[b]Background benefit[/b]  %s\n" % bd.get("benefit", "—")
	var starting: Dictionary = DB.dict(k, "starting_equipment")
	t += "[b]Starting gear[/b]  " + ", ".join(starting.values().map(func(i: Variant) -> String: return DB.item_name(String(i)))) + "\n"
	_content.add_child(UIKit.rich(t, 18))
	var warn: PackedStringArray = []
	if int(u["attr_points"]) > 0:
		warn.append("%d attribute point(s)" % int(u["attr_points"]))
	if int(u["skill_points"]) > 0:
		warn.append("%d skill point(s)" % int(u["skill_points"]))
	if int(u["feats"]) > 0:
		warn.append("%d feat pick(s)" % int(u["feats"]))
	if int(u["powers"]) > 0:
		warn.append("%d power pick(s)" % int(u["powers"]))
	if not warn.is_empty():
		_content.add_child(UIKit.label("Unspent: " + ", ".join(warn) + ". Unspent points are lost at creation.", 17, UIKit.WARN, true))
	if not errs.is_empty():
		_content.add_child(UIKit.label("Required before starting:\n• " + "\n• ".join(errs), 17, UIKit.BAD, true))
	_content.add_child(UIKit.sep())
	_content.add_child(UIKit.label("Difficulty (can be changed later in Settings)", 20, UIKit.ACCENT2))
	for d in [["story", "Story", "Enemies attack at a penalty and your party takes reduced damage. Skill checks and choices are unchanged. For players here for the story."], ["standard", "Standard", "The intended d20 balance. Pause often."]]:
		var did := String(d[0])
		_content.add_child(_card(String(d[1]), String(d[2]), difficulty == did, func() -> void:
			difficulty = did
			_refresh()))
	_next_btn.disabled = not errs.is_empty()


func _pron_label() -> String:
	for p in DB.arr(DB.appearance, "pronouns"):
		if String(p["id"]) == String(build.get("pronouns", "they")):
			return String(p["label"])
	return "they/them"
