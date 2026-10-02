extends TestCase
## Dialogue conditions/effects, checks resolved once, influence/alignment,
## one-time rewards, quests and progression.


func test_text_formatting_pronouns() -> void:
	var st := fresh_state("vanguard")
	st.player().pronouns = "she"
	assert_eq(Game.fmt("{They} {are} {name}; {their} call."), "She is %s; her call." % st.player().display_name)
	st.player().pronouns = "they"
	assert_eq(Game.fmt("{They} {are} ready."), "They are ready.")


func test_dialogue_conditions_and_once_only_effects() -> void:
	var st := fresh_state("vanguard")
	var eng := DialogueEngine.new(st)
	assert_true(eng.start("test_fixture"))
	var xp0 := st.player().xp
	assert_eq(st.player().xp, xp0)
	var texts: Array = []
	for c in eng.choices():
		texts.append(c["text"])
	assert_true(texts.has("Veterans only."), "background condition")
	assert_false(texts.has("[Iona] Let Iona talk."), "companion check hidden when not in party")
	var locked: Array = eng.choices().filter(func(c: Dictionary) -> bool: return c["text"] == "Locked option.")
	assert_eq(locked.size(), 1)
	assert_false(locked[0]["enabled"], "locked shown disabled with reason")
	var sway: Array = eng.choices().filter(func(c: Dictionary) -> bool: return c["text"] == "Sway them.")
	assert_false(sway[0]["enabled"], "Sway check needs the Sway power")
	# Node effects applied once even if the node is visited again.
	var xp1 := st.player().xp
	eng.finish()
	st.flags.erase("fixture_done")
	eng.start("test_fixture")
	assert_eq(st.player().xp, xp1, "no double XP for re-entering a node")


func test_check_resolves_once_and_failure_continues() -> void:
	var st := fresh_state("vanguard")
	var eng := DialogueEngine.new(st)
	eng.start("test_fixture")
	st.dice.force([1])
	var idx := -1
	for c in eng.choices():
		if c["text"] == "Persuade me.":
			idx = int(c["index"])
	var r := eng.choose(idx)
	assert_true(r["ok"])
	assert_false(r["check"]["success"])
	assert_eq(eng.node_id, "lost", "failure continues coherently")
	assert_true(st.checks.has("fixture_persuade"))
	eng.choose(int(eng.choices()[0]["index"]))
	assert_false(eng.active)
	# Re-entering: the resolved check is not offered again.
	st.flags.erase("fixture_done")
	eng.start("test_fixture")
	for c in eng.choices():
		assert_ne(c["text"], "Persuade me.", "resolved check not re-offered")


func test_companion_assisted_check_uses_companion_skill() -> void:
	var st := fresh_state("vanguard")
	Game.recruit("iona")
	var eng := DialogueEngine.new(st)
	eng.start("test_fixture")
	var opt: Dictionary = {}
	for c in eng.choices():
		if String(c["text"]).begins_with("[Iona]"):
			opt = c
	assert_false(opt.is_empty(), "visible with Iona in party")
	assert_eq(opt["check"]["who_name"], "Iona Rell")
	assert_eq(int(opt["check"]["bonus"]), st.get_char("iona").skill_total("persuasion"))


func test_resonance_assisted_persuasion() -> void:
	var st := fresh_state("operative")
	var p := st.player()
	p.energy = 10
	var eng := DialogueEngine.new(st)
	eng.start("test_fixture")
	var opt: Dictionary = {}
	for c in eng.choices():
		if c["text"] == "Sway them.":
			opt = c
	assert_true(opt["enabled"], "operative recommended build knows Sway")
	assert_eq(int(opt["check"]["bonus"]), p.skill_total("persuasion") + 5, "power adds +5")
	st.dice.force([15])
	var a0 := st.alignment
	eng.choose(int(opt["index"]))
	assert_eq(p.energy, 7, "Sway costs energy")
	assert_eq(st.alignment, a0 - 5, "coercion shifts toward Dominion")


func test_influence_and_alignment_are_one_time() -> void:
	var st := fresh_state("vanguard")
	Game.recruit("iona")
	Game.recruit("tav7")
	var eng := DialogueEngine.new(st)
	eng.start("test_fixture")
	for c in eng.choices():
		if c["text"] == "Be kind.":
			eng.choose(int(c["index"]))
			break
	assert_eq(int(st.influence["iona"]), 58)
	assert_eq(int(st.influence["tav7"]), 47, "companions judge separately")
	assert_eq(st.alignment, 10)
	assert_eq(st.influence_log.size(), 2)
	assert_eq(String(st.influence_log[0]["reason"]), "Kind to a stranger", "reason recorded")
	# Replaying the same choice cannot farm influence.
	st.flags.erase("fixture_done")
	eng.start("test_fixture")
	for c in eng.choices():
		if c["text"] == "Be kind.":
			eng.choose(int(c["index"]))
			break
	assert_eq(int(st.influence["iona"]), 58, "no influence farming")
	assert_eq(st.alignment, 10, "no alignment farming")
	assert_eq(st.add_influence("iona", 500, "big", "test"), 42, "clamped at 100")
	assert_eq(st.add_alignment(-500, "x", "test"), -110, "clamped at -100")
	assert_eq(st.alignment, -100)


func test_one_time_rewards_ledger() -> void:
	var st := fresh_state("vanguard")
	var xp := st.player().xp
	assert_eq(st.grant_xp(100, "enc:test", "fight"), 100)
	assert_eq(st.grant_xp(100, "enc:test", "fight again"), 0)
	assert_eq(st.player().xp, xp + 100)
	Effects.apply_all([{"give_item": "medpac", "count": 2, "key": "box1"}], st)
	var n := st.inventory.count("medpac")
	Effects.apply_all([{"give_item": "medpac", "count": 2, "key": "box1"}], st)
	assert_eq(st.inventory.count("medpac"), n, "keyed loot claimable once")


func test_levelup_manual_and_recommended() -> void:
	var st := fresh_state("vanguard")
	var p := st.player()
	assert_eq(p.levels_available(), 0)
	p.xp = 4600
	assert_eq(p.levels_available(), 3, "xp table 1000/2500/4500")
	var hp0 := p.max_hp()
	var pv := Progression.preview(p)
	assert_eq(int(pv["hp_gain"]), 9, "7 + CON 2")
	var bad := Progression.apply_level_up(p, {"skills": {"stealth": 5}})
	assert_false(bad["ok"], "rank limit enforced")
	assert_eq(p.level, 1)
	var ch := Progression.recommended_choices(p)
	assert_empty(Progression.validate(p, ch))
	assert_true(Progression.apply_level_up(p, ch)["ok"])
	assert_eq(p.level, 2)
	assert_eq(p.max_hp(), hp0 + 9 + (2 if p.feats.has("toughness") else 0), "Toughness adds 1 per level")
	for i in 2:
		ch = Progression.recommended_choices(p)
		var r := Progression.apply_level_up(p, ch)
		assert_true(r["ok"], str(r["errors"]))
	assert_eq(p.level, 4)
	assert_eq(int(p.attr_increases.get("str", 0)), 1, "level 4 attribute increase")
	assert_true(p.feats.has("power_strike_2") or p.feats.has("toughness"), "level 3 feat chosen")
	assert_eq(p.levels_available(), 0)


func test_companion_levelup() -> void:
	var st := fresh_state("vanguard")
	var i := Game.recruit("iona")
	i.xp = 2600
	var ch := Progression.recommended_choices(i)
	assert_true(Progression.apply_level_up(i, ch)["ok"])
	assert_true(Progression.apply_level_up(i, Progression.recommended_choices(i))["ok"])
	assert_eq(i.level, 3)
	assert_eq(i.max_energy(), 0, "Iona has no Resonance until trained")


func test_quest_state_machine() -> void:
	var st := fresh_state("vanguard")
	st.quests.clear()
	DB.quests["q_test"] = {"name": "Test", "start": "a", "complete_xp": 40, "stages": {"a": {"text": "A", "objectives": ["o1"]}, "b": {"text": "B", "objectives": ["o2"]}},
		"objectives": {"o1": {"text": "one"}, "o2": {"text": "two", "optional": true}},
		"transitions": [{"event": "flag_changed", "match": {"flag": "go_b"}, "stage": "b"}]}
	assert_eq(QuestSystem.state_of(st, "q_test"), "inactive")
	QuestSystem.set_state(st, "q_test", "active")
	assert_eq(String(st.quests["q_test"]["stage"]), "a")
	st.set_flag("go_b")
	assert_eq(String(st.quests["q_test"]["stage"]), "b", "event-driven transition")
	assert_eq(String(st.quests["q_test"]["objectives"]["o1"]), "completed")
	var xp := st.player().xp
	QuestSystem.set_state(st, "q_test", "completed")
	assert_eq(st.player().xp, xp + 40)
	assert_false(QuestSystem.set_state(st, "q_test", "failed"), "completed quests cannot fail")
	assert_false(QuestSystem.set_state(st, "q_test", "completed"))
	assert_eq(st.player().xp, xp + 40, "completion XP once")
	DB.quests.erase("q_test")


func test_conditions_operators() -> void:
	var st := fresh_state("adept")
	st.set_flag("n", 3)
	assert_true(Conditions.eval_all([{"flag": "n", "gte": 3}], st))
	assert_false(Conditions.eval_all([{"flag": "n", "gte": 4}], st))
	assert_true(Conditions.eval_all([{"any": [{"flag": "nope"}, {"class": "adept"}]}], st))
	assert_true(Conditions.eval_all([{"not": {"flag": "nope"}}], st))
	assert_true(Conditions.eval_all([{"power": "mend"}], st))
	assert_true(Conditions.eval_all([{"attr": "wis", "gte": 16}], st))
	assert_false(Conditions.eval_all([{"influence": "iona", "gte": 65}], st))
	assert_true(Conditions.eval_all([{"alignment_lte": 0}], st))
	assert_empty(Conditions.unknown_keys([{"flag": "x"}, {"any": [{"skill": "repair", "gte": 2}]}]))
	assert_eq(Conditions.unknown_keys([{"exec": "rm -rf"}]), ["exec"], "no arbitrary code: unknown keys are rejected by validation")
