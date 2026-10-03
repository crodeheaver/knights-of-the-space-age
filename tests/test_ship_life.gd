extends TestCase
## Ambient voices (ShipLife, data/ship_life.json): barks on events, once-only
## lines, banter, shipwide announcements, companions asking to talk, quiet
## while paused or in a conversation, and no effect on the simulation.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world(preset: String) -> World:
	var r := DevTools.apply_preset(preset)
	assert_true(bool(r["ok"]), String(r.get("reason", "")))
	Saves.save_root = "user://test_saves/"
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	return w


func _life(w: World) -> ShipLife:
	var sl := ShipLife.new()
	w.add_child(sl)
	sl.setup(w)
	w.ship_life = sl
	return sl


func _free(w: World) -> void:
	GameAudio.voice_stop("world")
	GameAudio.voice_stop("ship")
	w.queue_free()
	await _tree().process_frame


var _toasts: Array = []


func _on_toast(text: String, kind: String) -> void:
	_toasts.append([text, kind])


func test_party_barks_on_events_with_cooldowns() -> void:
	var w: World = await _world("jump_checkpoint")
	var sl := _life(w)
	var iona: Actor = w.actors["iona"]
	iona.set_pos(w.controlled().position + Vector3(2, 0, 0))
	Events.post("ally_downed", {"uid": "player"})
	sl._process(0.1)
	assert_eq(sl.bubble_text(iona), "Operator's down! Covering!", "Iona calls it out")
	# Too soon for another bark from her.
	Events.post("ally_downed", {"uid": "player"})
	assert_true(sl._queue.is_empty(), "bark gap and cooldown hold")
	# A once-only line plays once.
	sl.now += 30.0
	Events.post("encounter_started", {"id": "enc_checkpoint"})
	sl._process(0.1)
	assert_true(Game.state.claimed("chatter:bk_iona_chk"), "claimed in the ledger")
	assert_eq(sl.bubble_text(iona), "That's Kell's checkpoint. Was. Make it count.")
	sl.now += 300.0
	Events.post("encounter_started", {"id": "enc_checkpoint"})
	assert_true(sl._queue.is_empty(), "once means once")
	await _free(w)


func test_quiet_while_paused_and_in_conversations() -> void:
	var w: World = await _world("jump_checkpoint")
	var sl := _life(w)
	var iona: Actor = w.actors["iona"]
	iona.set_pos(w.controlled().position + Vector3(2, 0, 0))
	w.set_paused(true)
	Events.post("ally_downed", {"uid": "player"})
	sl._process(1.0)
	assert_eq(sl.bubble_text(iona), "", "nothing said while paused")
	w.set_paused(false)
	sl._process(0.1)
	assert_ne(sl.bubble_text(iona), "", "said once the simulation runs")
	w.set_modal("dialogue", true)
	sl._process(0.1)
	assert_false((sl._bubbles[0]["label"] as Label3D).visible, "bubbles hide behind conversations")
	w.set_modal("dialogue", false)
	await _free(w)


func test_downed_or_distant_speakers_stay_quiet() -> void:
	var w: World = await _world("jump_checkpoint")
	var sl := _life(w)
	var iona: Actor = w.actors["iona"]
	iona.set_pos(w.controlled().position + Vector3(2, 0, 0))
	StatusRules.apply(iona.sheet, "downed", 30.0)
	assert_true(sl.speaker_actor("iona") == null, "a downed companion does not bark")
	StatusRules.remove(iona.sheet, "downed")
	iona.set_pos(w.controlled().position + Vector3(40, 0, 0))
	assert_true(sl.speaker_actor("iona") == null, "nor one out of earshot")
	await _free(w)


func test_announcements_and_bark_effect() -> void:
	var w: World = await _world("jump_checkpoint")
	var sl := _life(w)
	_toasts.clear()
	Events.notify.connect(_on_toast)
	Game.state.set_flag("emergency_started")
	Effects.apply_one({"bark": "an_warden_archive"}, Game.state, {})
	sl._process(0.1)
	var found := false
	for t in _toasts:
		if String(t[0]).contains("PLEASE DO NOT TOUCH THE ARCHIVE") and String(t[1]) == "warden":
			found = true
	assert_true(found, "WARDEN announcement captioned: %s" % str(_toasts))
	assert_true(w._trim_pulse > 0.0, "trims pulse with the announcement")
	# The ship's voice still speaks with party chatter turned off.
	var b: Variant = Settings.get_v("banter")
	Settings.set_v("banter", "off", false)
	assert_true(sl.say_line("an_warden_bay", true), "announcements ignore the chatter setting")
	assert_false(sl.say_line("bk_iona_rest", true), "party lines respect it")
	Settings.set_v("banter", b, false)
	Events.notify.disconnect(_on_toast)
	await _free(w)


func test_hook_opens_a_topic() -> void:
	var w: World = await _world("jump_checkpoint")
	var sl := _life(w)
	var iona: Actor = w.actors["iona"]
	iona.set_pos(w.controlled().position + Vector3(2, 0, 0))
	Game.state.encounters["enc_corridor"] = {"state": "resolved"}
	Game.state.set_flag("checkpoint_clear")
	sl._hook_t = 0.0
	sl._process(0.1)
	assert_true(Game.state.has_flag("hook_iona_orrin"), "Iona asks to talk")
	assert_false(ShipLife.pending_hook("iona").is_empty(), "a pending hook")
	w.start_dialogue("iona_talk", iona)
	var texts: Array = []
	for c in w.dialogue.choices():
		texts.append(String(c["text"]))
	assert_true(texts.has("You wanted to talk. About Jessa Orrin?"), str(texts))
	for c in w.dialogue.choices():
		if String(c["text"]).begins_with("You wanted to talk"):
			w.dialogue.choose(int(c["index"]))
			break
	w.dialogue.choose(0)
	while w.dialogue != null and w.dialogue.active and w.dialogue.choices().is_empty():
		w.dialogue.advance()
	assert_true(Game.state.has_flag("iona_orrin_done"), "topic done")
	assert_true(ShipLife.pending_hook("iona").is_empty(), "nothing pending")
	w.end_dialogue()
	await _free(w)


func test_banter_plays_once() -> void:
	var w: World = await _world("jump_engineering")
	var sl := _life(w)
	assert_true(Game.state.party.has("iona") and Game.state.party.has("tav7"), "both companions")
	var lead := w.controlled()
	w.actors["iona"].set_pos(lead.position + Vector3(1.5, 0, 0))
	w.actors["tav7"].set_pos(lead.position + Vector3(-1.5, 0, 0))
	assert_true(sl.try_banter(), "an exchange starts")
	var first := String(sl._queue[0]["id"])
	assert_true(Game.state.claimed("chatter:" + first), "claimed")
	for i in 40:
		sl._process(0.5)
	assert_true(sl._queue.is_empty(), "all lines spoken")
	sl.now += 1000.0
	if sl.try_banter():
		assert_ne(String(sl._queue[0]["id"]), first, "the same exchange does not repeat")
	await _free(w)


func _sim_snapshot(w: World) -> String:
	var d := {"dice": Game.state.dice.to_dict(), "t": snappedf(Game.state.sim_time, 0.0001)}
	for uid in w.actors.keys():
		var a: Actor = w.actors[uid]
		d[uid] = [snappedf(a.position.x, 0.001), snappedf(a.position.z, 0.001), a.sheet.hp, a.sheet.dead]
	return JSON.stringify(d)


func _run_fight(with_life: bool) -> String:
	var w: World = await _world("jump_checkpoint")
	var sl: ShipLife = _life(w) if with_life else null
	w.alert_encounter("enc_checkpoint")
	for i in 240:
		w.sim_step(0.05)
		if sl != null:
			sl._process(0.05)
	var snap := _sim_snapshot(w)
	await _free(w)
	return snap


func test_ship_life_does_not_touch_the_simulation() -> void:
	var a: String = await _run_fight(false)
	var b: String = await _run_fight(true)
	assert_eq(b, a, "the same fight with and without ambient voices")


func test_validator_checks_ship_life() -> void:
	var sl: Dictionary = DB.ship_life
	var saved := sl.duplicate(true)
	(sl["barks"] as Array).append({"id": "_t_bad", "on": "teatime", "speaker": "nobody", "text": ""})
	(sl["hooks"] as Array).append({"id": "_t_hook", "companion": "iona", "flag": "_t_unused_flag", "done_flag": "_t_unused_done"})
	var all := "\n".join(DataValidator.new().validate_all(DB))
	assert_true(all.contains("unknown event 'teatime'"), all)
	assert_true(all.contains("unknown speaker 'nobody'"), all)
	assert_true(all.contains("empty text"), all)
	assert_true(all.contains("'_t_unused_flag' is not used by iona_talk"), all)
	DB.ship_life = saved
	assert_true(DataValidator.new().validate_all(DB).is_empty(), "clean again")


func test_npc_idle_styles_are_visual() -> void:
	Game.new_game(BuildValidator.recommended("vanguard"), "standard")
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	var k: Actor = w.actors["ketterick"]
	assert_eq(k.visual.idle_style, "cards", "from the layout")
	var p0 := k.position
	for i in 30:
		w.sim_step(0.1)
	assert_eq(k.position, p0, "idling never moves anyone")
	assert_true(absf(k.visual.arm_r.rotation_degrees.x) > 20.0, "arms at the card table")
	await _free(w)
