class_name Routes
extends RefCounted
## Scripted end-to-end routes through the Cinder Wake for the playthrough bot.
## martial:   Vanguard, fights everything, hard-line choices (takes supplies,
##            seals the ward, kills Senna, loads the archive, purges WARDEN).
## technical: Operative, stealth + skills (terminal, crawlway, pumps, hatch,
##            crane), treats Senna, copies the testimony, Tav-7 hosts WARDEN,
##            bay solved with turrets/apron shield.
## diplomat:  Adept, talks through obstacles (parley passphrase, Varr
##            persuasion, WARDEN command, negotiated bay).

const P := {
	"martial": {
		"intro_wake": ["Six years"], "steward": ["Check me in", "Breathe"],
		"iona_meet": ["We move fast", "Thanks"], "checkpoint_credential": ["I don't know"],
		"tav7_meet": ["We need a technician", "Copies"], "varga_triage": ["If we die"],
		"ward_intercom": ["seal has to hold"], "senna": ["This ends here", "(Do it.)", "Who are you"],
		"reclaimer_parley": ["hard way"], "command_intercom": ["Rell", "passenger"],
		"varr": ["Load the core", "Do it. Seal"], "warden_core": ["I'm ending this", "I'm certain"],
		"bay_quill": ["Then burn it", "Lanterns", "Yes. And I'd"], "launch": ["Brann, full burn"],
		"ending_exchange": ["find every one"],
	},
	"technical": {
		"intro_wake": ["cargo manifests"], "steward": ["Check me in", "corridor's the way"],
		"iona_meet": ["Why would anyone", "Thanks"], "checkpoint_terminal": ["camera logs", "turret offline", "Override the forward", "Log off"],
		"tav7_meet": ["Why aren't you obeying", "evidence and people"], "varga_triage": ["Let me help"],
		"ward_intercom": ["purged. Hang on", "Iona. You sealed it", "Not yet"], "engineering_terminal": ["schematic", "WARDEN system", "Isolate", "Log off"],
		"archive_index": ["Tav-7, can you", "Slice", "program summary", "Open engram", "Copy engram", "Close it", "Close the index"],
		"senna": ["Easy", "What's in the hold", "Hold still", "Use a medpac"],
		"reclaimer_parley": ["Ember-tide", "WARDEN is killing"], "command_intercom": ["Rell"],
		"varr": ["engrams were stolen", "Let's decide", "copied the Vesper", "best of every", "Leave the archive for the Lantern", "Do it. Seal"],
		"warden_core": ["What are you", "Tav-7. Could you", "Do it, Tav-7"],
		"bay_terminal": ["Bring the bay turrets online", "Drop the launch apron", "Log off"],
		"bay_quill": ["Still in the hold"], "launch": ["Tav-7, plot"], "ending_exchange": ["bringing the truth"],
	},
	"diplomat": {
		"intro_wake": ["people still on Haldis"], "steward": ["How are the other", "Check me in", "Keep everyone here"],
		"venn_family": ["Hey, Ilo", "I hope Tessaly", "I promise"],
		"iona_meet": ["bring everyone", "Thanks"], "checkpoint_credential": ["I don't know"],
		"tav7_meet": ["Thank you for protecting", "People"], "varga_triage": ["Iona has field", "Use it on them"],
		"ward_intercom": ["We're opening it now", "Iona. You sealed it"],
		"senna": ["Easy", "What's in the hold", "Help me reach the bay"],
		"reclaimer_parley": ["Ember-tide", "WARDEN is killing"], "command_intercom": ["Rell", "passenger"],
		"varr": ["You had Iona seal", "She's right", "What is a Custodian", "Let's decide", "Hand the archive", "Passengers first", "Those people are Haldis", "Those minds were stolen", "Iona?", "Leave the archive for the Lantern", "No. Some of them"],
		"warden_core": ["What are you", "Stand down", "You know what I'd do"],
		"bay_quill": ["Still in the hold"], "launch": ["Iona, take"], "ending_exchange": ["bringing the truth"],
		"iona_talk": ["Why ship's security", "You've seen what I can do", "Refusing that order", "Never mind"],
	},
}


static func run(bot: PlaythroughBot, style: String) -> void:
	bot.prefs = P[style]
	bot.default_prefs = ["Continue", "Close", "Leave", "Log off", "(Step"]
	var w := bot.world
	bot.note("=== route: %s ===" % style)
	# ---------------- cabin
	w.start_dialogue("intro_wake")
	await bot.pump()
	await bot.loot("cabin_locker")
	await bot.loot("cabin_case")
	await bot.read("cabin_datapad")
	bot.expect(bot.flag("case_opened") == true, "operator case opened")
	await bot.open_door("d_cabin")
	if bot.halted():
		return
	# ---------------- commons
	await bot.walk(Vector3(16, 0, 6))
	if style == "diplomat":
		await bot.talk("dalia")
	if style == "technical":
		# Recreation before the emergency: buy a stealth-helping item.
		Vendor.buy(Game.state, "requisition", "frag_grenade")
	await bot.talk("steward")
	bot.expect(bot.flag("emergency_started") == true, "emergency started after check-in")
	if style == "diplomat":
		await bot.talk("dalia")
	await bot.open_door("d_commons_east")
	if bot.halted():
		return
	# ---------------- corridor
	await bot.walk(Vector3(32, 0, 6.5))
	await bot.step(1.0)
	if w.combat.active:
		await bot.fight()
	await bot.step(1.0)
	await bot.pump()
	bot.expect(Game.state.party.has("iona"), "Iona recruited")
	await bot.loot("corr_locker")
	await bot.loot("corr_body")
	if bot.halted():
		return
	# ---------------- checkpoint
	await bot.open_door("d_corridor_east")
	if style == "technical":
		await _checkpoint_technical(bot)
	else:
		await bot.walk(Vector3(52, 0, 6.0))
		await bot.step(2.0)
		if w.combat.active:
			await bot.fight()
		await bot.use("d_armory", "keycard")
		await bot.loot("armory_locker")
		await bot.use("d_blast", "credential")
		await bot.pump()
	bot.expect(bot.flag("checkpoint_solved") == true, "forward blast door opened (%s)" % str(bot.flag("checkpoint_by")))
	if bot.halted():
		return
	# ---------------- medical
	await bot.walk(Vector3(66, 0, 8.5))
	await bot.step(1.0)
	if w.combat.active:
		await bot.fight()
	await bot.step(1.0)
	await bot.pump()
	bot.expect(Game.state.party.has("tav7"), "Tav-7 recruited")
	bot.expect(bot.flag("medical_secured") == true, "medical deck secured")
	await bot.talk("varga")
	bot.expect(bot.flag("supplies_decided") == true, "medical reserve decided: %s" % str(bot.flag("med_supplies_choice")))
	if style == "technical":
		await bot.switch_to("tav7")
		await bot.use("ward_purge", "purge")
		if bot.flag("ward_purged") != true:
			await bot.use("ward_purge", "purge")
		await bot.switch_to("player")
	await bot.use("ward_intercom", "_dialogue")
	await bot.pump()
	bot.expect(bot.flag("ward_decided") == true, "ward decided: %s" % str(bot.flag("ward_choice")))
	if style != "martial":
		await bot.loot("storage_crate")
	if bot.halted():
		return
	# ---------------- engineering
	await bot.open_door("d_med_east")
	await bot.walk(Vector3(86, 0, 9))
	await bot.read("eng_log")
	if style == "technical":
		await _engineering_technical(bot)
	else:
		await bot.walk(Vector3(88, 0, 14))
		await bot.walk(Vector3(91, 0, 18.5))
		await bot.walk(Vector3(103, 0, 20.5))
		await bot.walk(Vector3(107, 0, 15.5))
		await bot.step(2.0)
		if w.combat.active:
			await bot.fight()
		await bot.open_door("d_eng_east")
		await bot.walk(Vector3(114, 0, 7.5))
	if bot.halted():
		return
	# ---------------- archive
	await bot.step(1.0)
	await bot.pump()
	if w.combat.active:
		await bot.fight()
	await _archive(bot, style)
	if bot.halted():
		return
	# mid-level save/reload check
	await _reload_check(bot)
	w = bot.world
	if bot.halted():
		return
	# ---------------- command
	await bot.use("arc_intercom", "_dialogue")
	await bot.pump()
	bot.expect(bot.flag("command_open") == true, "command chamber opened")
	await bot.walk(Vector3(139, 0, 8))
	await bot.talk("varr")
	await bot.pump()
	if w.combat.active:
		await bot.fight()
	if bot.flag("launch_decided") != true:
		await bot.use("cmd_console", "_dialogue")
		await bot.pump()
	bot.expect(bot.flag("launch_decided") == true, "launch decided: %s, archive %s" % [str(bot.flag("evac_choice")), str(bot.flag("archive_fate"))])
	await bot.use("cmd_core", "_dialogue")
	await bot.pump()
	bot.note("WARDEN fate: %s" % str(bot.flag("warden_fate")))
	if bot.halted():
		return
	# ---------------- bay
	await bot.open_door("d_bay")
	await bot.walk(Vector3(153.5, 0, 8.0))
	await bot.step(1.0)
	await bot.pump()
	if style == "technical" and bot.flag("bay_resolved") != true:
		await bot.use("bay_terminal", "_dialogue")
		await bot.pump()
	if w.combat.active:
		await bot.fight(400.0)
	await bot.step(2.0)
	await bot.pump()
	bot.expect(bot.flag("bay_resolved") == true, "bay resolved: %s" % str(bot.flag("bay_resolution")))
	await bot.use("petrel_ramp", "board")
	await bot.pump()
	await bot.step(0.5)
	await bot.pump()
	if bot.flag("escaped") != true and w.modal.has("minigame") == false:
		# Player-turret path: the minigame UI is absent in tests; resolve it the
		# way the minigame reports a result.
		Game.state.set_flag("turret_result", "player_win")
		w.start_dialogue("launch_after")
		await bot.pump()
	bot.expect(bot.flag("escaped") == true, "escaped the Cinder Wake")
	bot.note("survivors %d, level %d, xp %d, alignment %d, influence %s" % [Game.state.survivors(), Game.state.player().level, Game.state.player().xp, Game.state.alignment, str(Game.state.influence)])


static func _checkpoint_technical(bot: PlaythroughBot) -> void:
	var w := bot.world
	var a := bot.lead()
	# Companions hold while the operative sneaks (solo mode via stealth).
	w.toggle_stealth(a)
	await bot.walk(Vector3(49.5, 0, 9.0))
	await bot.use("chk_terminal", "_dialogue")
	await bot.pump()
	if w.combat.active:
		await bot.fight()
	if bot.flag("checkpoint_solved") != true:
		# Fall back to the crawlway side passage.
		await bot.walk(Vector3(58.5, 0, 13.5))
		await bot.use("d_vent", "unbolt")
		if bot.flag("found_crawlway") != true:
			await bot.use("d_vent", "unbolt")
		if bot.flag("found_crawlway") != true:
			await bot.switch_to("iona")
			await bot.use("d_vent", "unbolt")
			await bot.switch_to("player")
		if bot.flag("found_crawlway") != true:
			await bot.use("d_vent", "pry")
			await bot.step(8.0)
			if w.combat.active:
				await bot.fight()
		await bot.loot("crawl_cache")
		await bot.read("crawl_note")
		await bot.open_door("d_crawl_exit")
		await bot.walk(Vector3(77.5, 0, 22))
		await bot.open_door("d_storage")
		await bot.use("med_release", "release")
	if a.stealth:
		w.break_stealth(a, "")
	w.set_solo(false)
	if bot.flag("checkpoint_bypassed") == true:
		bot.note("checkpoint bypassed via the crawlway")


static func _engineering_technical(bot: PlaythroughBot) -> void:
	var w := bot.world
	await bot.use("eng_terminal", "_dialogue")
	await bot.pump()
	await bot.switch_to("tav7")
	await bot.use("pump_s", "restart")
	if bot.flag("pump_south_fixed") != true:
		await bot.use("pump_s", "restart")
	await bot.switch_to("player")
	await bot.open_door("d_workshop")
	var crafter: CharacterSheet = Game.state.get_char("tav7")
	var cr := Crafting.craft("r_pump_seal", crafter, Game.state)
	bot.expect(bool(cr["ok"]), "fabricated a pump seal kit at the workbench (%s)" % str(cr.get("reason", "")))
	if bot.flag("pump_south_fixed") != true:
		await bot.use("pump_s", "kit")
		cr = Crafting.craft("r_pump_seal", crafter, Game.state)
	# Kill the live deck plates in the west leg, then take the west leg
	# north (well away from the Sentinel post in the east leg).
	if bot.flag("plates_disabled") != true:
		await bot.switch_to("tav7")
		await bot.use("eng_junction", "isolate")
		await bot.switch_to("player")
	await bot.walk(Vector3(87, 0, 18))
	await bot.walk(Vector3(86, 0, 8))
	# North pump: it sits in sight of the Sentinel post's drone, so the
	# operative sneaks in alone (companions hold) through the venting coolant.
	var a := bot.lead()
	await bot.walk(Vector3(86, 0, -2.5))
	w.toggle_stealth(a)
	await bot.use("pump_n", "kit")
	if bot.flag("pump_north_fixed") != true:
		await bot.switch_to("tav7")
		await bot.use("pump_n", "restart")
		await bot.switch_to("player")
	bot.expect(bot.flag("pumps_restored") == true, "both coolant pumps restarted")
	await bot.walk(Vector3(86, 0, -2.5))
	if a.stealth:
		w.break_stealth(a, "")
	w.set_solo(false)
	await bot.walk(Vector3(86, 0, 8))
	await bot.walk(Vector3(88, 0, 18))
	await bot.walk(Vector3(95.5, 0, 20.5))
	await bot.switch_to("tav7")
	await bot.use("d_hatch", "repair")
	if bot.flag("hatch_open") != true:
		await bot.switch_to("player")
		await bot.use("d_hatch", "security")
	await bot.switch_to("player")
	if bot.flag("hatch_open") == true:
		await bot.walk(Vector3(105, 0, 27))
		await bot.walk(Vector3(113, 0, 23))
		await bot.open_door("d_duct_hold")
		await bot.walk(Vector3(113, 0, 18.5))
		bot.expect(bot.flag("engineering_bypassed") == true, "skill shortcut bypassed the Sentinel post")
	else:
		await bot.walk(Vector3(103, 0, 20.5))
		await bot.walk(Vector3(107, 0, 15.5))
		await bot.step(2.0)
		if w.combat.active:
			await bot.fight()
		await bot.open_door("d_eng_east")
		await bot.walk(Vector3(114, 0, 7.5))


static func _archive(bot: PlaythroughBot, style: String) -> void:
	var w := bot.world
	if style == "technical":
		await bot.open_door("d_cold")
		await bot.walk(Vector3(121.5, 0, 22.5))
		await bot.step(1.0)
		await bot.talk("senna")
		await bot.loot("cold_crates")
		bot.expect(bot.flag("senna_decided") == true, "Senna's fate: %s" % str(bot.flag("senna_fate")))
		await bot.walk(Vector3(116, 0, 19))
		if bot.flag("pumps_restored") == true:
			await bot.use("arc_purge", "purge")
			await bot.step(1.0)
		if w.combat.active:
			await bot.fight()
		await bot.walk(Vector3(130, 0, -2.0))
		await bot.use("arc_index", "_dialogue")
		await bot.pump()
		bot.expect(Game.state.inventory.count("vesper_testimony") > 0, "Vesper testimony copied")
		await bot.walk(Vector3(131.5, 0, 9.5))
	elif style == "diplomat":
		var a := bot.lead()
		await bot.open_door("d_cold")
		await bot.walk(Vector3(121.5, 0, 22.5))
		await bot.step(1.0)
		await bot.talk("senna")
		bot.expect(bot.flag("senna_decided") == true, "Senna's fate: %s" % str(bot.flag("senna_fate")))
		await bot.walk(Vector3(121.5, 0, 17))
		await bot.step(2.0)
		await bot.pump()
		if w.combat.active:
			await bot.fight()
		await bot.walk(Vector3(131.5, 0, 9.5))
	else:
		await bot.walk(Vector3(118, 0, 8))
		await bot.step(2.0)
		await bot.pump()
		if w.combat.active:
			await bot.fight()
		await bot.open_door("d_cold")
		await bot.walk(Vector3(121.5, 0, 22.5))
		await bot.step(1.0)
		await bot.talk("senna")
		bot.expect(bot.flag("senna_decided") == true, "Senna's fate: %s" % str(bot.flag("senna_fate")))
		await bot.walk(Vector3(131.5, 0, 9.5))
	await bot.pump()
	if w.combat.active:
		await bot.fight()


static func _reload_check(bot: PlaythroughBot) -> void:
	await bot.pump()
	if bot.world.combat.active:
		await bot.fight()
	var before := bot.snapshot()
	var r := Saves.save_game("bot_mid", "Bot mid-level")
	bot.expect(bool(r["ok"]), "mid-level save (%s)" % str(r.get("reason", "")))
	var lr := Saves.load_game("bot_mid")
	bot.expect(bool(lr["ok"]), "mid-level load")
	await bot.start_world()
	var after := bot.snapshot()
	bot.expect(JSON.stringify(before) == JSON.stringify(after), "reload preserves survivors, inventory, quests, influence, alignment")
	if JSON.stringify(before) != JSON.stringify(after):
		bot.note("before: " + JSON.stringify(before))
		bot.note("after:  " + JSON.stringify(after))
	# No double rewards after reload: re-reading a codex entry grants nothing.
	var xp0: int = Game.state.player().xp
	bot.world.read_object(bot.world.objects["cabin_datapad"], bot.lead())
	bot.expect(Game.state.player().xp == xp0, "no repeated discovery XP after reload")
