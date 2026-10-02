extends TestCase
## Developer presets: each builds a coherent state, loads into the real World,
## and demonstrates what it promises (prestige eligibility per variant,
## Iona's Resonance training, checkpoint jumps that can be played onward).

const PRESTIGE := {
	"prestige_bulwark": "bulwark_sentinel", "prestige_iron_marshal": "iron_marshal",
	"prestige_lumen_weaver": "lumen_weaver", "prestige_void_cantor": "void_cantor",
	"prestige_ghost_envoy": "ghost_envoy", "prestige_night_broker": "night_broker",
}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _load_world() -> World:
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	return w


func test_every_preset_applies_and_loads() -> void:
	for pid in DevTools.preset_ids():
		var r := DevTools.apply_preset(pid)
		assert_true(bool(r["ok"]), "%s: %s" % [pid, r.get("reason", "")])
		var st := Game.state
		var pd: Dictionary = DB.dev_presets[pid]
		assert_true(st.dev_mode, "%s is a dev game" % pid)
		assert_eq(st.player().level, int(pd["level"]), "%s level" % pid)
		for c in pd.get("companions", []):
			assert_true(st.party.has(String(c)), "%s has %s" % [pid, c])
		var w: World = await _load_world()
		var sg: Dictionary = DB.dev_stages[String(pd["stage"])]
		assert_eq(w.grid.area_at(w.controlled().position), String(sg["area"]), "%s starts at its stage threshold" % pid)
		for i in 10:
			w.sim_step(0.1)
		assert_false(w.game_over, pid)
		w.queue_free()
		await _tree().process_frame


func test_prestige_presets_are_eligible_for_their_variant_only() -> void:
	for pid in PRESTIGE.keys():
		DevTools.apply_preset(pid)
		var p := Game.state.player()
		var want := String(PRESTIGE[pid])
		var elig := Prestige.eligible_variants(p, Game.state.alignment)
		assert_true(elig.has(want), "%s eligible for %s; errors: %s" % [pid, want, str(Prestige.eligibility_errors(p, want, Game.state.alignment))])
		var fam := String(Prestige.variant(want)["family"])
		for v in elig:
			if String(Prestige.variant(v)["family"]) == fam:
				assert_eq(v, want, "%s: opposite-alignment variant locked" % pid)
		var r := Prestige.adopt(p, want, Game.state.alignment)
		assert_true(bool(r["ok"]), str(r["errors"]))
		assert_eq(p.prestige, want)
		var again := Prestige.adopt(p, want, Game.state.alignment)
		assert_false(bool(again["ok"]), "cannot specialize twice")


func test_iona_training_preset() -> void:
	DevTools.apply_preset("iona_training")
	var w: World = await _load_world()
	var iona := Game.state.get_char("iona")
	assert_false(iona.powers.has("mend"))
	w.talk_companion("iona")
	var eng := w.dialogue
	assert_true(eng != null and eng.active, "Iona's conversation starts")
	var found := false
	for c in eng.choices():
		if String(c.get("tag", "")) == "Resonance training" and bool(c["enabled"]):
			found = true
			eng.choose(int(c["index"]))
			break
	assert_true(found, "training option available")
	for i in 10:
		var ch := eng.choices()
		if ch.is_empty():
			eng.advance()
		else:
			for c2 in ch:
				if String(c2["text"]).contains("Close your eyes"):
					eng.choose(int(c2["index"]))
					break
			break
	assert_true(Game.state.has_flag("iona_trained"), "training completed")
	assert_true(iona.powers.has("mend") and iona.powers.has("echo_sense"), "Iona gained Resonance powers")
	w.queue_free()
	await _tree().process_frame


func test_jump_bay_plays_to_escape() -> void:
	DevTools.apply_preset("jump_bay")
	Saves.save_root = "user://test_saves/"
	var bot := PlaythroughBot.new(_tree(), _tree().root)
	await bot.start_world()
	await Routes.finale(bot, "diplomat", "bay")
	for f in bot.failures:
		fail("jump_bay: " + f)
	assert_true(Game.state.has_flag("escaped"), "escaped from the bay jump")
	await bot.free_world()
