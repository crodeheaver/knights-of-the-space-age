extends TestCase
## Automated end-to-end playthroughs (bot-driven, not human playtests).
## Each drives the real World from a fresh game to the escape.


func _run(style: String, cls: String, bg: String, seed_v: int) -> PlaythroughBot:
	Saves.save_root = "user://test_saves/"
	var tree := Engine.get_main_loop() as SceneTree
	var bot := PlaythroughBot.new(tree, tree.root)
	var b := BuildValidator.recommended(cls)
	b["background"] = bg
	# AOTC_SEED_OFFSET re-runs the same routes with different dice (robustness
	# sweeps); the default run uses the fixed seeds below.
	seed_v += int(OS.get_environment("AOTC_SEED_OFFSET")) if OS.has_environment("AOTC_SEED_OFFSET") else 0
	await bot.new_game(b, "standard", seed_v)
	await Routes.run(bot, style)
	for f in bot.failures:
		fail(f)
	var out := FileAccess.open("user://bot_%s.log" % style, FileAccess.WRITE)
	if out:
		out.store_string("\n".join(bot.log) + "\n\nCHOICES:\n" + "\n".join(PackedStringArray(bot.choice_trace)) + "\n\nCOMBAT LOG:\n" + "\n".join(bot.combat_lines))
		out.close()
	await bot.free_world()
	return bot


func test_playthrough_martial() -> void:
	var bot: PlaythroughBot = await _run("martial", "vanguard", "veteran", 11)
	assert_true(Game.state.has_flag("escaped"), "martial route escaped")
	assert_eq(String(Game.state.flags.get("senna_fate", "")), "killed")


func test_playthrough_technical() -> void:
	var bot: PlaythroughBot = await _run("technical", "operative", "colonist", 23)
	assert_true(Game.state.has_flag("escaped"), "technical route escaped")


func test_playthrough_diplomat() -> void:
	var bot: PlaythroughBot = await _run("diplomat", "adept", "salvager", 37)
	assert_true(Game.state.has_flag("escaped"), "diplomat route escaped")
