extends TestCase
## UI smoke tests: every screen builds, navigates and drives the same rules
## the gameplay uses, headlessly, without script errors.


class FakeMain:
	extends Node
	var started: Dictionary = {}
	var difficulty := ""
	var closed: Array = []
	var menu_shown := false

	func start_new_game(b: Dictionary, d: String) -> void:
		started = b
		difficulty = d

	func show_main_menu() -> void:
		menu_shown = true

	func close_panel(p: Control) -> void:
		closed.append(p)
		p.queue_free()

	func push_panel(p: Control) -> void:
		add_child(p)


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_character_creator_flow() -> void:
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var cc := CharacterCreator.new()
	cc.main = fm
	fm.add_child(cc)
	await _tree().process_frame
	# Walk every step forwards and back.
	for i in CharacterCreator.STEPS.size():
		cc._go(i)
		await _tree().process_frame
	cc._go(0)
	cc._set_class("operative")
	assert_eq(cc.build["class"], "operative")
	assert_eq((cc.build["feats"] as Array).size(), 0, "class change resets feats")
	cc._use_recommended()
	assert_true(BuildValidator.validate_build(cc.build).size() <= 1, "recommended is valid except possibly the name")
	# Attribute buy respects the budget.
	cc._go(2)
	for a in Rules.ATTRS:
		cc._attrs()[a] = 8
	for k in 40:
		cc._adj_attr("str", 1)
	assert_true(BuildValidator.points_remaining(cc._attrs()) >= 0, "never overspends")
	assert_eq(int(cc._attrs()["str"]), 18, "str maxes at 18 within budget")
	cc._use_recommended()
	cc.build["name"] = "Test Operator"
	cc._go(CharacterCreator.STEPS.size() - 1)
	await _tree().process_frame
	cc._on_next()
	assert_eq(String(fm.started.get("name", "")), "Test Operator", "summary starts the game with the build")
	assert_eq(fm.difficulty, "standard")
	fm.queue_free()
	await _tree().process_frame


func test_creator_blocks_invalid_build() -> void:
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var cc := CharacterCreator.new()
	cc.main = fm
	fm.add_child(cc)
	await _tree().process_frame
	cc.build["name"] = ""
	cc._go(CharacterCreator.STEPS.size() - 1)
	cc._begin()
	assert_true(fm.started.is_empty(), "no name -> cannot start")
	assert_true(cc._msg.text.contains("name"), cc._msg.text)
	fm.queue_free()
	await _tree().process_frame


func _world_setup() -> Array:
	Saves.save_root = "user://test_saves/"
	Game.new_game(BuildValidator.recommended("vanguard"), "standard")
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	return [w, fm]


func _teardown(w: World, fm: Node) -> void:
	fm.queue_free()
	w.queue_free()
	await _tree().process_frame


func test_game_menu_all_tabs() -> void:
	var r: Array = await _world_setup()
	var w: World = r[0]
	var fm: FakeMain = r[1]
	var gm := GameMenu.new()
	gm.main = fm
	fm.add_child(gm)
	await _tree().process_frame
	for t in GameMenu.TABS:
		gm.show_tab(String(t[0]))
		await _tree().process_frame
	for j in ["quests", "choices", "discoveries", "history", "tutorials"]:
		gm.journal_tab = j
		gm.show_tab("journal")
		await _tree().process_frame
	# Equip / unequip through the inventory tab.
	gm.show_tab("inventory")
	var s := Game.state.player()
	Game.state.inventory.add("security_weave")
	var inst := Game.state.inventory.first_instance("security_weave")
	assert_eq(gm._equip_slots_for(s, "security_weave"), ["body"] as Array[String], "vanguard can wear medium armor")
	var before := s.defense()
	var res := EquipmentRules.equip(s, Game.state.inventory, String(inst["uid"]), "body")
	gm._after_change(res)
	assert_true(s.defense() > before, "defense rises with better armor")
	assert_true(Game.state.inventory.first_instance("padded_vest").size() > 0, "old armor returned to inventory")
	# Use a medpac out of combat.
	s.hp = 3
	gm.sel_uid = "player"
	gm._use_item("medpac", "player")
	assert_true(s.hp > 3, "medpac heals out of combat")
	await _teardown(w, fm)


func test_levelup_ui_recommended_and_manual() -> void:
	var r: Array = await _world_setup()
	var w: World = r[0]
	var fm: FakeMain = r[1]
	var s := Game.state.player()
	s.xp = s.xp_for_level(3)
	var lu := LevelUpUI.new()
	lu.main = fm
	lu.uid = "player"
	fm.add_child(lu)
	await _tree().process_frame
	assert_true(lu._confirm.disabled or Progression.validate(s, lu.choices).is_empty(), "confirm reflects validation")
	lu._recommend()
	assert_true(Progression.validate(s, lu.choices).is_empty(), "recommended choices validate")
	var lvl := s.level
	lu._apply()
	assert_eq(s.level, lvl + 1, "level applied")
	assert_true(s.levels_available() > 0, "second level still available")
	# Manual: an illegal over-spend is refused.
	lu.choices = {"attr": "", "skills": {"awareness": 99}, "feats": [], "powers": []}
	lu._apply()
	assert_eq(s.level, lvl + 1, "invalid choices refused")
	await _teardown(w, fm)


func test_vendor_crafting_muster_ui() -> void:
	var r: Array = await _world_setup()
	var w: World = r[0]
	var fm: FakeMain = r[1]
	var inv := Game.state.inventory
	inv.credits = 200
	var v := VendorUI.new()
	v.main = fm
	v.vendor_id = "requisition"
	fm.add_child(v)
	await _tree().process_frame
	var med0 := inv.count("medpac")
	v._pick = {"side": "buy", "id": "medpac"}
	v._result(Vendor.buy(Game.state, "requisition", "medpac", 1))
	assert_eq(inv.count("medpac"), med0 + 1)
	assert_eq(inv.credits, 200 - Vendor.buy_price("requisition", "medpac"))
	v._render()
	var c := CraftingUI.new()
	c.main = fm
	c.station = "workbench"
	fm.add_child(c)
	await _tree().process_frame
	for m in ["craft", "dismantle", "upgrade"]:
		c.mode = m
		c._render()
	c.mode = "craft"
	c._pick = "r_frag_grenade"
	c._render()
	inv.add("tech_components", 4)
	var fr0 := inv.count("frag_grenade")
	var crafter := Game.state.player()
	crafter.skill_ranks["demolitions"] = 4
	crafter.mark_dirty()
	var cr := Crafting.craft("r_frag_grenade", crafter, Game.state)
	c._result(cr, "Crafted.")
	assert_true(bool(cr["ok"]), str(cr.get("reason", "")))
	assert_eq(inv.count("frag_grenade"), fr0 + 1)
	var mu := MusterUI.new()
	mu.main = fm
	fm.add_child(mu)
	await _tree().process_frame
	Game.state.player().hp = 1
	assert_eq(w.rest_block_reason(true), "", "safe to rest in the cabin")
	w.rest(true)
	assert_eq(Game.state.player().hp, Game.state.player().max_hp(), "rest restores health")
	await _teardown(w, fm)


func test_saveload_and_settings_ui() -> void:
	var r: Array = await _world_setup()
	var w: World = r[0]
	var fm: FakeMain = r[1]
	Saves.delete_slot("slot_8")
	var sl := SaveLoadUI.new()
	sl.main = fm
	sl.mode = "save"
	fm.add_child(sl)
	await _tree().process_frame
	sl._save("slot_8", false)
	assert_true(bool(Saves.read_file("slot_8")["ok"]), "saved to slot 8")
	var sl2 := SaveLoadUI.new()
	sl2.main = fm
	sl2.mode = "load"
	fm.add_child(sl2)
	await _tree().process_frame
	sl2._delete("slot_8")
	assert_eq(sl2._confirm_kind, "delete", "delete asks first")
	assert_true(bool(Saves.read_file("slot_8")["ok"]), "not deleted before confirm")
	sl2._confirmed("slot_8")
	assert_false(bool(Saves.read_file("slot_8")["ok"]), "deleted after confirm")
	var st := SettingsUI.new()
	st.main = fm
	fm.add_child(st)
	await _tree().process_frame
	for sec in ["gameplay", "controls", "display", "audio"]:
		st.section = sec
		st._render()
	var old := Settings.key_label("toggle_log")
	var stolen := Settings.rebind("toggle_log", KEY_K)
	assert_eq(stolen, "menu_abilities", "conflicting key is moved")
	assert_eq(Settings.key_label("menu_abilities"), "—")
	Settings.reset_bindings()
	assert_eq(Settings.key_label("toggle_log"), old)
	await _teardown(w, fm)


func test_ending_outcome() -> void:
	var r: Array = await _world_setup()
	var w: World = r[0]
	var fm: FakeMain = r[1]
	var st := Game.state
	st.set_flag("survivors", 11)
	st.set_flag("ward_choice", "purged")
	st.set_flag("senna_fate", "treated")
	st.set_flag("archive_fate", "loaded")
	st.set_flag("warden_fate", "hosted")
	Game.recruit("iona")
	Game.recruit("tav7")
	st.set_flag("tav7_hosts_warden", true)
	var o := EndingUI.compute_outcome()
	assert_eq(int(o["survivors"]), 11)
	assert_true((o["decisions"] as Array).size() >= 4, "decisions summarized")
	var tav: Array = (o["companions"] as Array).filter(func(c: Dictionary) -> bool: return c["id"] == "tav7")
	assert_true(String(tav[0]["text"]).contains("WARDEN"), "Tav-7 hosting WARDEN is reflected")
	var e := EndingUI.new()
	e.main = fm
	e.outcome = o
	e.saved = true
	fm.add_child(e)
	await _tree().process_frame
	await _teardown(w, fm)
