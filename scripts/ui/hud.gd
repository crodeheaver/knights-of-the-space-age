class_name HUD
extends Control
## Exploration and combat HUD: party cards (portrait, health/energy, statuses,
## current action, level-up badge), target information with hit chance,
## action queue (cancel / reorder), action bar, combat log with roll details,
## minimap, objective tracker, notifications, pause banner, stealth meter,
## interaction prompt and dismissible tutorial prompts.

signal open_menu(tab: String)

var world: World
var main: Node
var portraits: Portraits
var party_box: VBoxContainer
var cards: Dictionary = {}
var target_panel: PanelContainer
var target_name: Label
var target_bar: ProgressBar
var target_info: Label
var target_status: HBoxContainer
var queue_box: HBoxContainer
var queue_title: Label
var bar_root: VBoxContainer
var log_label: RichTextLabel
var log_panel: PanelContainer
var log_lines: Array[String] = []
var log_big := false
var log_toggle: Button
var minimap: MiniMap
var area_label: Label
var objective_label: RichTextLabel
var toast_box: VBoxContainer
var pause_banner: PanelContainer
var pause_label: Label
var pause_frame: ReferenceRect
var prompt_panel: PanelContainer
var prompt_label: Label
var stealth_label: Label
var tutorial_panel: PanelContainer
var tutorial_title: Label
var tutorial_text: RichTextLabel
var tutorial_queue: Array = []
var area_banner: Label
var area_sub: Label
var banner_t := 0.0
var _refresh_t := 0.0
var _dirty := true
var form_btn: OptionButton
var order_btn: Button
var solo_btn: Button
var stealth_btn: Button
var hover_target: Node = null
var ally_popup: PopupMenu
var _pending_ally_action: Dictionary = {}
## Toasts raised while the HUD is hidden (conversations, cinematics,
## activities) wait here and appear once it is back.
var _held: Array = []
var _held_t := 0.0


func setup(w: World, m: Node) -> void:
	world = w
	main = m
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	portraits = Portraits.new()
	add_child(portraits)
	_build()
	world.hud_changed.connect(func() -> void: _dirty = true)
	Events.notify.connect(_on_toast)
	Events.combat_log.connect(_on_log)
	Events.event.connect(_on_event)
	_dirty = true


func _build() -> void:
	# Pause frame: border + text, not colour alone.
	pause_frame = ReferenceRect.new()
	pause_frame.border_color = Color("#f2c26b")
	pause_frame.border_width = 4.0
	pause_frame.editor_only = false
	UIKit.full_rect(pause_frame)
	pause_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_frame.visible = false
	add_child(pause_frame)
	# Party cards (top-left)
	party_box = UIKit.vbox(6)
	party_box.position = Vector2(14, 14)
	add_child(party_box)
	# Target panel (top-centre)
	target_panel = UIKit.panel(null, Color(0.07, 0.08, 0.1, 0.88))
	var tv := UIKit.vbox(3)
	target_panel.add_child(tv)
	target_name = UIKit.label("", 20, UIKit.TEXT)
	tv.add_child(target_name)
	target_bar = UIKit.bar(1, 1, UIKit.BAD, 12)
	target_bar.custom_minimum_size = Vector2(340, 12)
	tv.add_child(target_bar)
	target_info = UIKit.label("", 15, UIKit.DIM)
	tv.add_child(target_info)
	target_status = UIKit.hbox(3)
	tv.add_child(target_status)
	UIKit.anchor(target_panel, Vector4(0.5, 0, 0.5, 0), Vector4(-200, 10, 200, 10))
	target_panel.grow_vertical = Control.GROW_DIRECTION_END
	target_panel.visible = false
	add_child(target_panel)
	# Minimap + objective (top-right)
	var tr := UIKit.vbox(4)
	UIKit.anchor(tr, Vector4(1, 0, 1, 0), Vector4(-302, 12, -14, 12))
	add_child(tr)
	area_label = UIKit.label("", 17, UIKit.ACCENT2)
	tr.add_child(area_label)
	minimap = MiniMap.new()
	minimap.world = world
	minimap.custom_minimum_size = Vector2(286, 200)
	minimap.mouse_filter = Control.MOUSE_FILTER_STOP
	minimap.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			open_menu.emit("map"))
	tr.add_child(minimap)
	objective_label = UIKit.rich("", 15)
	objective_label.custom_minimum_size = Vector2(286, 0)
	var op := UIKit.panel(objective_label, Color(0.06, 0.07, 0.09, 0.8))
	tr.add_child(op)
	# Toasts (upper centre)
	toast_box = UIKit.vbox(4)
	UIKit.anchor(toast_box, Vector4(0.5, 0, 0.5, 0), Vector4(-320, 150, 320, 150))
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_box)
	# Pause banner
	pause_banner = UIKit.panel(null, Color(0.18, 0.13, 0.05, 0.92))
	pause_label = UIKit.label("TACTICAL PAUSE", 22, UIKit.ACCENT2)
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_banner.add_child(pause_label)
	UIKit.anchor(pause_banner, Vector4(0.5, 0, 0.5, 0), Vector4(-330, 100, 330, 100))
	pause_banner.visible = false
	add_child(pause_banner)
	# Area banner
	area_banner = UIKit.label("", 40, UIKit.ACCENT2)
	UIKit.anchor(area_banner, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-500, -260, 500, -200))
	area_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area_banner.modulate.a = 0.0
	add_child(area_banner)
	area_sub = UIKit.label("", 20, UIKit.DIM)
	UIKit.anchor(area_sub, Vector4(0.5, 0.5, 0.5, 0.5), Vector4(-500, -200, 500, -170))
	area_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	area_sub.modulate.a = 0.0
	add_child(area_sub)
	# Interaction prompt
	prompt_panel = UIKit.panel(null, Color(0.05, 0.06, 0.08, 0.85))
	prompt_label = UIKit.label("", 17, UIKit.TEXT)
	prompt_panel.add_child(prompt_label)
	UIKit.anchor(prompt_panel, Vector4(0.5, 1, 0.5, 1), Vector4(-300, -300, 300, -264))
	prompt_panel.visible = false
	add_child(prompt_panel)
	# Bottom: queue + action bar
	var bottom := UIKit.vbox(4)
	UIKit.anchor(bottom, Vector4(0.5, 1, 0.5, 1), Vector4(-450, -12, 450, -12))
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(bottom)
	var qrow := UIKit.hbox(6)
	queue_title = UIKit.label("Queue", 15, UIKit.DIM)
	qrow.add_child(queue_title)
	queue_box = UIKit.hbox(4)
	qrow.add_child(queue_box)
	stealth_label = UIKit.label("", 15, UIKit.TEAL)
	stealth_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stealth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qrow.add_child(stealth_label)
	bottom.add_child(qrow)
	var barp := UIKit.panel(null, Color(0.06, 0.07, 0.09, 0.88))
	bar_root = UIKit.vbox(3)
	barp.add_child(bar_root)
	bottom.add_child(barp)
	# Bottom-right controls
	var ctl := UIKit.vbox(4)
	UIKit.anchor(ctl, Vector4(1, 1, 1, 1), Vector4(-246, -12, -14, -12))
	ctl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(ctl)
	ctl.add_child(UIKit.button("Pause [%s]" % Settings.key_label("pause"), func() -> void: world.toggle_pause(), "Freeze the simulation. You can still queue actions, move the camera and open menus."))
	stealth_btn = UIKit.button("Stealth [%s]" % Settings.key_label("toggle_stealth"), func() -> void: world.toggle_stealth(world.controlled()))
	ctl.add_child(stealth_btn)
	ctl.add_child(UIKit.button("Swap weapons [%s]" % Settings.key_label("swap_weapons"), func() -> void: _swap()))
	form_btn = OptionButton.new()
	form_btn.add_item("Form: none")
	for f in ["ember", "bastion", "tide"]:
		form_btn.add_item(String(DB.forms[f]["name"]))
	form_btn.item_selected.connect(_on_form)
	form_btn.tooltip_text = "Combat forms trade offense, defense and energy. Switching locks out another switch for 1 round."
	ctl.add_child(form_btn)
	order_btn = UIKit.button("Party: Follow [%s]" % Settings.key_label("party_hold"), func() -> void: world.set_party_order("hold" if Game.state.party_order == "follow" else "follow"))
	ctl.add_child(order_btn)
	solo_btn = UIKit.button("Solo: off [%s]" % Settings.key_label("solo_mode"), func() -> void: world.set_solo(not Game.state.solo))
	ctl.add_child(solo_btn)
	var mg := GridContainer.new()
	mg.columns = 3
	for e in [["Char", "character", "menu_character"], ["Inv", "inventory", "menu_inventory"], ["Skills", "abilities", "menu_abilities"], ["Party", "party", "menu_party"], ["Journal", "journal", "menu_journal"], ["Map", "map", "menu_map"]]:
		var tab := String(e[1])
		mg.add_child(UIKit.button("%s" % e[0], func() -> void: open_menu.emit(tab), "%s [%s]" % [String(e[1]).capitalize(), Settings.key_label(String(e[2]))]))
	ctl.add_child(mg)
	ctl.add_child(UIKit.button("Menu [Esc]", func() -> void: open_menu.emit("system")))
	# Combat log (bottom-left)
	log_label = UIKit.rich("", 14, false)
	log_label.scroll_following = true
	log_label.custom_minimum_size = Vector2(470, 150)
	log_panel = UIKit.panel(log_label, Color(0.04, 0.05, 0.06, 0.82))
	UIKit.anchor(log_panel, Vector4(0, 1, 0, 1), Vector4(12, -12, 500, -12))
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(log_panel)
	log_toggle = UIKit.button("Log ▲", func() -> void: toggle_log(), "Expand the combat log (L). Hover a line for roll details.")
	UIKit.anchor(log_toggle, Vector4(0, 1, 0, 1), Vector4(12, -228, 110, -194))
	add_child(log_toggle)
	# Tutorial panel (right)
	tutorial_panel = UIKit.panel(null, Color(0.07, 0.09, 0.11, 0.95))
	var tvb := UIKit.vbox(6)
	tutorial_panel.add_child(tvb)
	tutorial_title = UIKit.label("", 19, UIKit.TEAL)
	tvb.add_child(tutorial_title)
	tutorial_text = UIKit.rich("", 16)
	tutorial_text.custom_minimum_size = Vector2(380, 0)
	tvb.add_child(tutorial_text)
	var tb := UIKit.hbox()
	tb.add_child(UIKit.button("Got it", func() -> void: _next_tutorial()))
	tb.add_child(UIKit.button("Hide all tips", func() -> void:
		Settings.set_v("tutorials", false)
		tutorial_queue.clear()
		tutorial_panel.visible = false, "Tips stay available under Journal → Tutorials."))
	tvb.add_child(tb)
	UIKit.anchor(tutorial_panel, Vector4(1, 0.5, 1, 0.5), Vector4(-440, -120, -320, -120))
	tutorial_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	tutorial_panel.visible = false
	add_child(tutorial_panel)
	ally_popup = PopupMenu.new()
	ally_popup.id_pressed.connect(_on_ally_pick)
	add_child(ally_popup)


func toggle_log() -> void:
	log_big = not log_big
	log_label.custom_minimum_size = Vector2(760, 420) if log_big else Vector2(470, 150)
	log_panel.offset_right = 790 if log_big else 500
	log_toggle.offset_top = -500 if log_big else -228
	log_toggle.offset_bottom = log_toggle.offset_top + 34
	log_toggle.text = "Log ▼" if log_big else "Log ▲"


# ------------------------------------------------------------ refresh
func _process(delta: float) -> void:
	if world == null:
		return
	_refresh_t -= delta
	if _dirty:
		_dirty = false
		_rebuild()
	if _refresh_t <= 0.0:
		_refresh_t = 0.1
		_update_dynamic()
	if banner_t > 0.0:
		banner_t -= delta
		var a := clampf(banner_t, 0.0, 1.0) if banner_t < 1.0 else clampf((3.5 - banner_t) * 2.0, 0.0, 1.0)
		area_banner.modulate.a = a
		area_sub.modulate.a = a
	visible = not _hidden_by_modal()
	if visible and not _held.is_empty():
		_held_t -= delta
		if _held_t <= 0.0:
			_held_t = 0.25
			var h: Array = _held.pop_front()
			_show_toast(String(h[0]), String(h[1]))


func _hidden_by_modal() -> bool:
	return world != null and (world.modal.has("dialogue") or world.modal.has("cinematic") or world.modal.has("minigame"))


func _rebuild() -> void:
	_rebuild_cards()
	_rebuild_bar()
	_update_dynamic()


func _rebuild_cards() -> void:
	UIKit.clear(party_box)
	cards.clear()
	for uid in Game.state.party:
		var s := Game.state.get_char(uid)
		if s == null:
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.08, 0.1, 0.9)))
		card.custom_minimum_size = Vector2(330, 0)
		var h := UIKit.hbox(8)
		card.add_child(h)
		var tex := TextureRect.new()
		tex.texture = portraits.texture_for(s, 84)
		tex.custom_minimum_size = Vector2(72, 72)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(tex)
		var v := UIKit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var top := UIKit.hbox(4)
		var nm := UIKit.label(s.display_name, 17, UIKit.TEXT)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
		var lvl := UIKit.label("L%d" % s.level, 14, UIKit.DIM)
		top.add_child(lvl)
		v.add_child(top)
		var hp := UIKit.bar(s.hp, s.max_hp(), UIKit.GOOD, 12)
		v.add_child(hp)
		var hpl := UIKit.label("", 12, UIKit.DIM)
		v.add_child(hpl)
		var en := UIKit.bar(s.energy, maxi(1, s.max_energy()), UIKit.TEAL, 8)
		en.visible = s.max_energy() > 0
		v.add_child(en)
		var act := UIKit.label("", 13, UIKit.ACCENT2)
		v.add_child(act)
		var stb := HFlowContainer.new()
		v.add_child(stb)
		var lu := UIKit.button("LEVEL UP", func() -> void: main.open_levelup(uid), "Spend your new level")
		lu.visible = false
		lu.add_theme_color_override("font_color", UIKit.ACCENT2)
		v.add_child(lu)
		var uid_c := uid
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				world.switch_control(uid_c)
			elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
				open_menu.emit("party"))
		card.tooltip_text = "Left-click: take control. Right-click: party orders."
		party_box.add_child(card)
		cards[uid] = {"card": card, "hp": hp, "hpl": hpl, "en": en, "act": act, "st": stb, "lu": lu, "name": nm, "lvl": lvl}


func _update_dynamic() -> void:
	var st := Game.state
	var lead := world.controlled()
	for uid in cards.keys():
		var c: Dictionary = cards[uid]
		var s := st.get_char(uid)
		if s == null:
			continue
		var hpb: ProgressBar = c["hp"]
		hpb.max_value = s.max_hp()
		hpb.value = s.hp
		(c["hpl"] as Label).text = "HP %d/%d%s" % [s.hp, s.max_hp(), ("   EN %d/%d" % [s.energy, s.max_energy()]) if s.max_energy() > 0 else ""]
		var enb: ProgressBar = c["en"]
		enb.max_value = maxi(1, s.max_energy())
		enb.value = s.energy
		var a: Actor = world.actors.get(uid, null)
		var act_text := ""
		if s.is_downed():
			act_text = "DOWN — recovers after combat (or use a medpac)"
		elif a != null:
			if not a.current.is_empty():
				act_text = "▶ " + world.action_label(a.current)
			elif a.in_combat and world.valid_hostile_target(a, a.target_uid) and a.queue.is_empty():
				act_text = "▶ Attack (repeat)"
			elif a.stealth:
				act_text = "Sneaking"
			if s.behavior != "" and uid != "player":
				act_text += ("   · " if act_text != "" else "") + s.behavior.capitalize()
		(c["act"] as Label).text = act_text
		var card: PanelContainer = c["card"]
		var col := UIKit.TEAL if uid == st.controlled else UIKit.BORDER
		if s.is_downed():
			col = UIKit.BAD
		card.add_theme_stylebox_override("panel", UIKit.panel_style(Color(0.07, 0.08, 0.1, 0.9), col))
		(c["lvl"] as Label).text = "L%d%s" % [s.level, " ★" if uid == st.controlled else ""]
		var stb: HFlowContainer = c["st"]
		UIKit.clear(stb)
		for se in s.statuses:
			if se["id"] == "downed":
				continue
			stb.add_child(UIKit.status_chip(String(se["id"]), float(se["remaining"])))
		if s.form != "" and s.has_resonance():
			var fl := UIKit.label(String(DB.forms[s.form]["symbol"]), 13, UIKit.MERCY)
			fl.tooltip_text = String(DB.forms[s.form]["desc"])
			stb.add_child(fl)
		(c["lu"] as Button).visible = s.levels_available() > 0
	# Target
	var t: Actor = null
	if lead != null and world.actors.has(lead.target_uid):
		t = world.actors[lead.target_uid]
	if hover_target is Actor and (hover_target as Actor).role != "party":
		t = hover_target
	target_panel.visible = t != null
	if t != null:
		var hos := lead != null and world.hostile(lead, t)
		target_name.text = "%s%s" % [t.sheet.display_name, "  — HOSTILE" if hos else ("  — neutral" if t.role != "party" else "")]
		target_name.add_theme_color_override("font_color", UIKit.BAD if hos else UIKit.ACCENT2)
		target_bar.max_value = t.sheet.max_hp()
		target_bar.value = t.sheet.hp
		var info := "HP %d/%d   DEF %d" % [t.sheet.hp, t.sheet.max_hp(), t.sheet.defense()]
		if hos and lead != null:
			var prof := CombatRules.weapon_profile(lead.sheet, "main")
			info += "   Hit chance %d%% (%s)" % [CombatRules.hit_chance(lead.sheet, t.sheet, prof, {"difficulty": st.difficulty}), prof["name"]]
			info += "   %.1f m" % lead.position.distance_to(t.position)
		if t.sheet.kind == "machine":
			info += "   Machine: weak to ion"
		target_info.text = info
		UIKit.clear(target_status)
		for se in t.sheet.statuses:
			target_status.add_child(UIKit.status_chip(String(se["id"]), float(se["remaining"])))
	# Queue
	UIKit.clear(queue_box)
	if lead != null:
		queue_title.text = "%s queue:" % lead.sheet.display_name
		if not lead.current.is_empty():
			var cur := UIKit.label("[now] " + world.action_label(lead.current), 14, UIKit.ACCENT2)
			queue_box.add_child(cur)
		for i in ActionQueue.MAX:
			if i < lead.queue.size():
				var q: Dictionary = lead.queue.items[i]
				var slot := UIKit.hbox(1)
				var idx := i
				slot.add_child(UIKit.button("◀", func() -> void:
					lead.queue.move(idx, -1)
					_dirty = true, "Move earlier"))
				var lbl := world.action_label(q)
				if q.has("target") and world.actors.has(String(q["target"])) and String(q["target"]) != lead.uid:
					lbl += " → " + (world.actors[String(q["target"])] as Actor).sheet.display_name
				if bool(q.get("auto_queued", false)):
					lbl += " (auto)"
				slot.add_child(UIKit.button("%d. %s ✕" % [i + 1, lbl], func() -> void:
					lead.queue.cancel_index(idx)
					_dirty = true, "Cancel this action"))
				slot.add_child(UIKit.button("▶", func() -> void:
					lead.queue.move(idx, 1)
					_dirty = true, "Move later"))
				queue_box.add_child(slot)
			else:
				queue_box.add_child(UIKit.label("[ %d ]" % (i + 1), 14, Color(0.4, 0.4, 0.42)))
		# Stealth meter
		if lead.stealth:
			var sus := world.max_suspicion_on(lead.uid)
			stealth_label.text = "STEALTH: %s" % ("hidden" if sus <= 0.01 else "being noticed %d%%" % int(sus * 100))
			stealth_label.add_theme_color_override("font_color", UIKit.TEAL if sus < 0.5 else UIKit.WARN)
		else:
			stealth_label.text = ""
		stealth_btn.text = ("Stop sneaking" if lead.stealth else "Stealth") + " [%s]" % Settings.key_label("toggle_stealth")
		form_btn.disabled = not lead.sheet.has_resonance()
		var fi := ["", "ember", "bastion", "tide"].find(lead.sheet.form)
		if form_btn.selected != fi:
			form_btn.select(maxi(0, fi))
	order_btn.text = "Party: %s [%s]" % ["Follow" if st.party_order == "follow" else "Hold", Settings.key_label("party_hold")]
	solo_btn.text = "Solo: %s [%s]" % ["ON" if st.solo else "off", Settings.key_label("solo_mode")]
	# Pause
	pause_banner.visible = world.paused and not world.game_over
	pause_frame.visible = world.paused and not world.game_over
	pause_label.text = "TACTICAL PAUSE — %s. Press %s to resume." % [world.pause_reason if world.pause_reason != "" else "Paused", Settings.key_label("pause")]
	# Area & objective
	area_label.text = String(DB.dict(DB.dict(DB.layout, "areas"), world.current_area).get("name", ""))
	objective_label.text = _objective_text()
	minimap.queue_redraw()
	_update_prompt()


func _objective_text() -> String:
	var st := Game.state
	var qid := st.tracked_quest
	var q: Dictionary = st.quests.get(qid, {})
	if q.is_empty():
		return ""
	var qd: Dictionary = DB.quests.get(qid, {})
	var out := "[color=#f2c26b]%s[/color]" % qd.get("name", qid)
	var sd: Dictionary = DB.dict(DB.dict(qd, "stages"), String(q.get("stage", "")))
	if String(q.get("state", "")) == "completed":
		return out + "\n[color=#5fd38a]Completed[/color]"
	for o in QuestSystem.active_objectives(st, qid):
		if String(o["state"]) == "active" and DB.arr(sd, "objectives").has(o["id"]):
			out += "\n• " + String(o["text"]) + (" [color=#9c958a](optional)[/color]" if o["optional"] else "")
	return out


func _update_prompt() -> void:
	var lead := world.controlled()
	var n: Node = hover_target
	if lead == null or n == null or not is_instance_valid(n):
		prompt_panel.visible = false
		return
	var txt := ""
	if n is WorldObject:
		var wo := n as WorldObject
		var opts := wo.options(lead)
		var first := ""
		for o in opts:
			if bool(o.get("enabled", false)):
				first = String(o["label"])
				break
		txt = "Click: %s — %s   (acting: %s)" % [first if first != "" else "Examine", wo.display_name(), lead.sheet.display_name]
		if wo.kind == "door" and wo.is_locked():
			txt = "%s — LOCKED. Click for options (acting: %s)" % [wo.display_name(), lead.sheet.display_name]
	elif n is Actor:
		var a := n as Actor
		if a.role == "party":
			txt = "Click: take control of %s" % a.sheet.display_name
		elif world.hostile(lead, a):
			txt = "Click: target %s · %s: attack · double-click: attack" % [a.sheet.display_name, Settings.key_label("attack_target")]
		else:
			txt = "Double-click or %s: talk to %s" % [Settings.key_label("interact"), a.sheet.display_name]
	prompt_label.text = txt
	prompt_panel.visible = txt != ""


# ------------------------------------------------------------ action bar
func _rebuild_bar() -> void:
	UIKit.clear(bar_root)
	var lead := world.controlled()
	if lead == null:
		return
	var s := lead.sheet
	var entries := action_entries(lead)
	var rows := {"Attacks": UIKit.hbox(4), "Powers": UIKit.hbox(4), "Items": UIKit.hbox(4)}
	var n := 0
	for e in entries:
		n += 1
		var key := ("[%d] " % (n % 10)) if n <= 10 else ""
		var b := UIKit.button(key + String(e["label"]), func() -> void: trigger_entry(e), String(e["tip"]))
		b.add_theme_font_size_override("font_size", 15)
		if String(e.get("reason", "")) != "":
			b.modulate = Color(0.7, 0.7, 0.7)
			b.tooltip_text = String(e["tip"]) + "\nUnavailable: " + String(e["reason"])
		(rows[e["row"]] as HBoxContainer).add_child(b)
	for r in ["Attacks", "Powers", "Items"]:
		var row: HBoxContainer = rows[r]
		if row.get_child_count() == 0:
			continue
		var line := UIKit.hbox(6)
		var l := UIKit.label(r, 13, UIKit.DIM)
		l.custom_minimum_size = Vector2(56, 0)
		line.add_child(l)
		line.add_child(row)
		bar_root.add_child(line)
	if s.max_energy() > 0:
		pass


func action_entries(a: Actor) -> Array:
	var s := a.sheet
	var out: Array = []
	var align := Game.state.alignment
	var tgt: CharacterSheet = null
	if world.actors.has(a.target_uid):
		tgt = (world.actors[a.target_uid] as Actor).sheet
	var prof := CombatRules.weapon_profile(s, "main")
	out.append({"row": "Attacks", "label": "Attack", "action": {"type": "attack"}, "needs": "enemy", "tip": "Basic attack with %s (%s %s). With Auto-attack on (Settings → Gameplay), a basic attack is queued when combat starts and repeats against the selected (or nearest) enemy whenever your queue is empty; anything you queue replaces it." % [prof["name"], prof["dice"], prof["dtype"]]})
	for f in s.action_feats():
		var fd: Dictionary = DB.feat(f)
		var act: Dictionary = fd["action"]
		var k := String(act.get("kind", "melee"))
		var needs := "enemy" if k in ["melee", "ranged"] else "none"
		out.append({"row": "Attacks", "label": String(fd["name"]), "action": {"type": "feat", "id": f}, "needs": needs, "tip": String(fd.get("desc", "")), "reason": ActionResolver.feat_usable(s, f, tgt) if needs == "none" or tgt != null else ""})
	for p in s.usable_powers():
		var pd: Dictionary = DB.power(p)
		if bool(pd.get("innate", false)):
			continue
		var c := s.power_cost(p, align)
		var tm := String(pd.get("target", "enemy"))
		var needs2 := "enemy" if tm in ["enemy", "area_enemy"] else ("ally" if tm == "ally" else "none")
		var parts := ""
		for pp in c["parts"]:
			parts += "%s %s, " % [pp[0], Rules.signed(int(pp[1]))]
		out.append({"row": "Powers", "label": "%s (%d)" % [pd["name"], int(c["cost"])], "action": {"type": "power", "id": p}, "needs": needs2,
			"tip": "%s\nEnergy cost %d (%s)%s" % [pd.get("desc", ""), int(c["cost"]), parts.trim_suffix(", "), "\nSave DC %d" % s.power_dc(String(pd.get("school", "universal"))) if pd.has("save") else ""],
			"reason": String(c["reason"]) if bool(c["blocked"]) else ("Not enough energy" if s.energy < int(c["cost"]) else "")})
	var inv := Game.state.inventory
	for id in inv.stacks.keys():
		var it: Dictionary = DB.item(String(id))
		var t := String(it.get("type", ""))
		if t not in ["consumable", "grenade", "mine"]:
			continue
		var needs3 := "enemy" if t == "grenade" else ("ally" if String(DB.dict(it, "use").get("target", "self")) == "ally" else "none")
		out.append({"row": "Items", "label": "%s ×%d" % [it["name"], inv.count(String(id))], "action": {"type": "item", "id": String(id)}, "needs": needs3, "tip": String(it.get("desc", "")) + "\nUsing an item takes this character's action for the round."})
	return out


func trigger_entry(e: Dictionary) -> void:
	var lead := world.controlled()
	if lead == null:
		return
	var act: Dictionary = (e["action"] as Dictionary).duplicate()
	match String(e["needs"]):
		"enemy":
			if not world.valid_hostile_target(lead, lead.target_uid):
				Events.toast("Select a hostile target first (click an enemy or press %s)." % Settings.key_label("cycle_target"), "warn")
				return
			act["target"] = lead.target_uid
		"ally":
			_pending_ally_action = act
			ally_popup.clear()
			var i := 0
			for uid in Game.state.party:
				var s := Game.state.get_char(uid)
				ally_popup.add_item("%s (%d/%d HP)%s" % [s.display_name, s.hp, s.max_hp(), " — DOWN" if s.is_downed() else ""], i)
				ally_popup.set_item_metadata(i, uid)
				i += 1
			ally_popup.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(0, -40 - 26 * i)
			ally_popup.popup()
			return
	world.queue_action(lead, act)


func _on_ally_pick(id: int) -> void:
	var uid := String(ally_popup.get_item_metadata(id))
	var act := _pending_ally_action.duplicate()
	act["target"] = uid
	world.queue_action(world.controlled(), act)


func trigger_slot(n: int) -> void:
	var lead := world.controlled()
	if lead == null:
		return
	var entries := action_entries(lead)
	if n - 1 < entries.size():
		trigger_entry(entries[n - 1])


func _swap() -> void:
	var lead := world.controlled()
	if lead == null:
		return
	if world.combat.active:
		world.queue_action(lead, {"type": "swap"})
	else:
		lead.sheet.active_set = 1 - lead.sheet.active_set
		lead.sheet.mark_dirty()
		lead.visual.refresh_weapons(lead.sheet)
		Events.toast("%s: weapon set %d (%s)" % [lead.sheet.display_name, lead.sheet.active_set + 1, CombatRules.weapon_profile(lead.sheet, "main")["name"]], "info")
		_dirty = true


func _on_form(idx: int) -> void:
	var lead := world.controlled()
	if lead == null:
		return
	var f: String = ["", "ember", "bastion", "tide"][idx]
	if f == lead.sheet.form:
		return
	if not lead.sheet.has_resonance():
		Events.toast("%s cannot use Resonance forms." % lead.sheet.display_name, "warn")
		return
	if lead.sheet.cooldowns.has("form"):
		Events.toast("Form change recharging (%.0fs)." % float(lead.sheet.cooldowns["form"]), "warn")
		_dirty = true
		return
	lead.sheet.form = f
	lead.sheet.cooldowns["form"] = 3.0
	lead.sheet.mark_dirty()
	Events.toast("%s adopts %s." % [lead.sheet.display_name, DB.forms[f]["name"] if f != "" else "no form"], "info")
	_dirty = true


# ------------------------------------------------------------ messages
func _on_toast(text: String, kind: String) -> void:
	if _hidden_by_modal():
		_held.append([text, kind])
		while _held.size() > 6:
			_held.pop_front()
		return
	_show_toast(text, kind)


func _show_toast(text: String, kind: String) -> void:
	var col := UIKit.TEXT
	match kind:
		"warn":
			col = UIKit.WARN
		"danger", "alert":
			col = UIKit.BAD
		"success", "reward", "quest", "approve":
			col = UIKit.GOOD
		"discovery", "story":
			col = UIKit.ACCENT2
		"disapprove":
			col = Color("#ff8a7a")
		"mercy":
			col = UIKit.MERCY
		"dominion":
			col = UIKit.DOMINION
		"xp":
			col = Color("#b9a7ff")
	var caption := kind == "story" and bool(Settings.get_v("subtitles"))
	var l := UIKit.label(text, 21 if caption else 17, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := UIKit.panel(l, Color(0.04, 0.05, 0.06, 0.88 if caption else 0.8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.add_child(p)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).queue_free()
		toast_box.remove_child(toast_box.get_child(0))
	var tw := p.create_tween()
	# Captions for ambient speech stay up long enough to read.
	tw.tween_interval(clampf(text.length() * 0.06, 3.2, 8.0) if caption else 3.2)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)
	if kind == "warn":
		GameAudio.play("ui_error", -12.0)


func _on_log(entry: Dictionary) -> void:
	var text := String(entry.get("text", "")).replace("[", "(").replace("]", ")")
	var detail := String(entry.get("detail", "")).replace("[", "(").replace("]", ")")
	var col := "#e9e2d4"
	match String(entry.get("kind", "")):
		"system":
			col = "#f2c26b"
		"warn":
			col = "#ffb04a"
		"damage":
			col = "#ff9a8a"
		"skill":
			col = "#9fe6e0"
		"stealth":
			col = "#b9a7ff"
	var line := "[color=%s]%s[/color]" % [col, text]
	if detail != "":
		line = "[hint=%s]%s ⓘ[/hint]" % [detail.replace("=", ":"), line]
	log_lines.append(line)
	if log_lines.size() > 200:
		log_lines.pop_front()
	log_label.text = "\n".join(log_lines)


func _on_event(name: String, data: Dictionary) -> void:
	match name:
		"tutorial":
			show_tutorial(String(data.get("id", "")))
		"inventory_changed", "equipment_changed", "level_up", "party_changed", "control_changed", "companion_recruited", "feat_granted":
			_dirty = true


func show_banner(title: String, sub: String) -> void:
	area_banner.text = title
	area_sub.text = sub
	banner_t = 3.5


func show_tutorial(tid: String) -> void:
	var td: Dictionary = DB.tutorials.get(tid, {})
	if td.is_empty():
		return
	if Game.state.tutorials_seen.has(tid):
		return
	Game.state.tutorials_seen[tid] = true
	if not bool(Settings.get_v("tutorials")):
		return
	tutorial_queue.append(td)
	if not tutorial_panel.visible:
		_next_tutorial()


func _next_tutorial() -> void:
	if tutorial_queue.is_empty():
		tutorial_panel.visible = false
		return
	var td: Dictionary = tutorial_queue.pop_front()
	tutorial_title.text = "TIP: " + String(td.get("title", ""))
	tutorial_text.text = _keys(String(td.get("text", "")))
	tutorial_panel.visible = true


func _keys(t: String) -> String:
	# {key:action} placeholders show the current binding.
	var out := t
	for a in Settings.ACTION_LABELS.keys():
		out = out.replace("{key:%s}" % a, "[color=#f2c26b]%s[/color]" % Settings.key_label(a))
	return out
