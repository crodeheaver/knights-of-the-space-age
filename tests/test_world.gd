extends TestCase
## World-level regressions on the real World node: pause freezes everything,
## simultaneous events (dead targets, canceled actions, kills and downs in one
## step, grenades in flight across a scene transition), stealth detection,
## and the four approaches to the forward checkpoint.


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world(preset: String, manual: bool = true) -> World:
	var r := DevTools.apply_preset(preset)
	assert_true(bool(r["ok"]), String(r.get("reason", "")))
	Saves.save_root = "user://test_saves/"
	var w := World.new()
	w.manual_step = manual
	_tree().root.add_child(w)
	await _tree().process_frame
	return w


func _free(w: World) -> void:
	w.queue_free()
	await _tree().process_frame


func _snapshot(w: World) -> Dictionary:
	var d := {"t": Game.state.sim_time, "proj": [], "actors": {}}
	for p in w.projectiles:
		d["proj"].append(float(p["t"]))
	for uid in w.actors.keys():
		var a: Actor = w.actors[uid]
		var sts: Array = []
		for s in a.sheet.statuses:
			sts.append([s["id"], snappedf(float(s["remaining"]), 0.0001)])
		d["actors"][uid] = [snappedf(a.position.x, 0.0001), snappedf(a.position.z, 0.0001), a.sheet.hp, sts, a.sheet.cooldowns.duplicate(), snappedf(a.round_clock, 0.0001), snappedf(a.recovery, 0.0001)]
	return d


func test_pause_freezes_everything() -> void:
	var ap: Variant = Settings.get_v("autopause_combat_start")
	Settings.set_v("autopause_combat_start", false, false)
	var w: World = await _world("jump_checkpoint", false)
	var p := w.controlled()
	w.alert_encounter("enc_checkpoint")
	for i in 20:
		await _tree().physics_frame
	assert_true(w.combat.active, "combat running")
	# Something of everything in motion: a status, a cooldown, a move order,
	# a grenade in the air.
	StatusRules.apply(p.sheet, "surge", 12.0)
	p.sheet.cooldowns["feat:test"] = 9.0
	w.cmd_move(w.actors["iona"], p.position + Vector3(0, 0, 3))
	w._spawn_grenade(p, "frag_grenade", "chk_d1")
	await _tree().physics_frame
	w.set_paused(true, "test")
	var before := _snapshot(w)
	for i in 45:
		await _tree().physics_frame
	assert_eq(JSON.stringify(_snapshot(w)), JSON.stringify(before), "nothing changes while paused")
	# A modal menu freezes the same way.
	w.set_paused(false)
	w.set_modal("menu", true)
	var before2 := _snapshot(w)
	for i in 30:
		await _tree().physics_frame
	assert_eq(JSON.stringify(_snapshot(w)), JSON.stringify(before2), "nothing changes behind a menu")
	w.set_modal("menu", false)
	for i in 30:
		await _tree().physics_frame
	assert_true(Game.state.sim_time > float(before2["t"]), "simulation resumes")
	Settings.set_v("autopause_combat_start", ap, false)
	await _free(w)


func test_second_attacker_on_dead_target() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	var p: Actor = w.actors["player"]
	var iona: Actor = w.actors["iona"]
	var e: Actor = w.actors["chk_d1"]
	e.set_pos(p.position + Vector3(1.0, 0, 0))
	e.sheet.hp = 1
	var xp0: int = Game.state.player().xp
	Game.state.dice.force([19, 6])
	w.execute_action(p, {"type": "attack", "target": "chk_d1"})
	assert_true(e.sheet.dead, "first attack kills")
	# Iona's in-progress attack on the same target is now invalid, not a crash.
	iona.current = {"type": "attack", "target": "chk_d1"}
	assert_ne(w.validate_action(iona, iona.current), "", "dead target refused")
	for i in 10:
		w.sim_step(0.1)
	assert_true(String(iona.current.get("target", "")) != "chk_d1", "Iona dropped the dead target")
	# A late second death report changes nothing.
	w.on_downed(e, "iona")
	var kills := Events.history.filter(func(h: Dictionary) -> bool: return h["name"] == "enemy_killed" and String(h["data"].get("uid", "")) == "chk_d1").size()
	assert_eq(kills, 1, "killed once")
	var gained: int = Game.state.player().xp - xp0
	assert_eq(gained, int(DB.enemy("picket_drone")["xp"]), "XP granted once")
	await _free(w)


func test_queued_actions_purged_when_target_dies() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	var iona: Actor = w.actors["iona"]
	for i in 3:
		w.queue_action(iona, {"type": "attack", "target": "chk_d2"})
	assert_eq(iona.queue.size(), 3)
	var e: Actor = w.actors["chk_d2"]
	e.sheet.hp = 0
	w.on_downed(e, "player")
	assert_eq(iona.queue.size(), 0, "queued attacks on a dead target are canceled")
	await _free(w)


func test_kill_and_down_in_the_same_explosion() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	var iona: Actor = w.actors["iona"]
	var e: Actor = w.actors["chk_d1"]
	var spot := iona.position + Vector3(0.8, 0, 0)
	e.set_pos(spot)
	iona.sheet.hp = 1
	e.sheet.hp = 1
	# Failed saves and high damage for everyone in the blast.
	Game.state.dice.force([1, 1, 1, 1, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6])
	w._explode("frag_grenade", spot, "chk_turret")
	assert_true(e.sheet.dead, "enemy killed")
	assert_true(iona.sheet.is_downed(), "ally downed by the same blast")
	assert_false(w.game_over, "others still standing")
	for i in 10:
		w.sim_step(0.1)
	assert_true(w.combat.active, "combat continues")
	await _free(w)


func test_grenade_in_flight_thrower_downed() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	var p: Actor = w.actors["player"]
	var e: Actor = w.actors["chk_d2"]
	var hp0 := e.sheet.hp
	w._spawn_grenade(p, "frag_grenade", "chk_d2")
	p.sheet.hp = 0
	w.on_downed(p, "chk_turret")
	Game.state.dice.force([1, 6, 6, 6])
	for i in 15:
		w.sim_step(0.1)
	assert_true(w.projectiles.is_empty(), "grenade landed")
	assert_true(e.sheet.hp < hp0 or e.sheet.dead, "the grenade still detonates after its thrower falls")
	await _free(w)


func test_scene_transition_with_grenade_pending() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	w.set_paused(true)
	var p: Actor = w.actors["player"]
	var frags := Game.state.inventory.count("frag_grenade")
	w.set_paused(false)
	w.execute_action(p, {"type": "item", "id": "frag_grenade", "target": "chk_d1"})
	assert_eq(Game.state.inventory.count("frag_grenade"), frags - 1, "consumed once when thrown")
	assert_false(w.projectiles.is_empty())
	w.set_paused(true)
	var r := Saves.save_game("slot_7")
	assert_false(bool(r["ok"]), "saving refused mid-throw")
	assert_true(String(r["reason"]).contains("grenade"), String(r["reason"]))
	var e_hp := (w.actors["chk_d1"] as Actor).sheet.hp
	# Leave the scene with the grenade still in the air.
	w.sync_to_state()
	w.queue_free()
	await _tree().process_frame
	var w2 := World.new()
	w2.manual_step = true
	_tree().root.add_child(w2)
	await _tree().process_frame
	assert_true(w2.projectiles.is_empty(), "no phantom grenade after the transition")
	for i in 15:
		w2.sim_step(0.1)
	assert_eq(Game.state.inventory.count("frag_grenade"), frags - 1, "not consumed twice")
	assert_eq((w2.actors["chk_d1"] as Actor).sheet.hp, e_hp, "no delayed explosion in the new scene")
	await _free(w2)


func test_stealth_detection_line_of_sight() -> void:
	var w: World = await _world("jump_checkpoint")
	Game.state.solo = true
	var p := w.controlled()
	w.toggle_stealth(p)
	assert_true(p.stealth, "in stealth")
	# Hidden behind the corridor wall, well away: never noticed.
	p.set_pos(Vector3(44.0, 0, 7.0))
	for i in 60:
		w.sim_step(0.1)
	assert_false((w.actors["chk_d1"] as Actor).alert, "unseen behind cover")
	# In the open, in sight and close: suspicion builds until spotted.
	var d1: Actor = w.actors["chk_d1"]
	p.set_pos(d1.position + Vector3(-3.0, 0, 0))
	var spotted := false
	for i in 200:
		w.sim_step(0.1)
		if d1.alert:
			spotted = true
			break
	assert_true(spotted, "spotted in plain sight")
	await _free(w)


func test_checkpoint_technical_approach() -> void:
	var w: World = await _world("jump_checkpoint")
	var bot := PlaythroughBot.new(_tree(), _tree().root)
	bot.world = w
	bot.prefs = {"checkpoint_terminal": ["Override the forward", "Log off"]}
	w.start_dialogue("checkpoint_terminal", null, "", {"actor": "player", "object": "chk_terminal"})
	Game.state.dice.force([19])
	await bot.pump()
	assert_eq(String(Game.state.flags.get("checkpoint_by", "")), "terminal")
	assert_true((w.objects["d_blast"] as WorldObject).is_open(), "blast door open")
	await _free(w)


func test_checkpoint_conversation_approach() -> void:
	var w: World = await _world("jump_checkpoint")
	var bot := PlaythroughBot.new(_tree(), _tree().root)
	bot.world = w
	bot.prefs = {"checkpoint_credential": ["I don't know"]}
	var r := w.perform_option(w.actors["player"], w.objects["d_blast"], "credential")
	assert_true(bool(r.get("ok", false)), str(r))
	await bot.pump()
	assert_eq(String(Game.state.flags.get("checkpoint_by", "")), "credential")
	assert_eq(String(w.encounter_state("enc_checkpoint")["state"]), "resolved", "WARDEN stands the checkpoint down")
	await _free(w)


func test_checkpoint_stealth_approach() -> void:
	var w: World = await _world("jump_checkpoint")
	var p := w.controlled()
	p.set_pos(Vector3(58.5, 0, 13.6))
	Game.state.dice.force([18])
	var r := w.perform_option(p, w.objects["d_vent"], "unbolt")
	assert_true(bool(Game.state.has_flag("found_crawlway")), str(r))
	p.set_pos(Vector3(63.9, 0, 10.0))
	w.perform_option(p, w.objects["med_release"], "release")
	assert_eq(String(Game.state.flags.get("checkpoint_by", "")), "crawlway")
	assert_true((w.objects["d_blast"] as WorldObject).is_open())
	await _free(w)


func test_checkpoint_combat_approach() -> void:
	var w: World = await _world("jump_checkpoint")
	w.alert_encounter("enc_checkpoint")
	var p := w.controlled()
	var opts: Array = (w.objects["d_blast"] as WorldObject).options(p)
	var manual: Array = opts.filter(func(o: Dictionary) -> bool: return o["id"] == "manual")
	assert_true(manual.is_empty() or not bool(manual[0].get("enabled", true)), "not while the defenses stand")
	for uid in ["chk_turret", "chk_d1", "chk_d2"]:
		var e: Actor = w.actors[uid]
		e.sheet.hp = 0
		w.on_downed(e, "player")
	for i in 5:
		w.sim_step(0.1)
	assert_eq(String(w.encounter_state("enc_checkpoint")["state"]), "resolved")
	p.set_pos(Vector3(61.2, 0, 7.5))
	var r := w.perform_option(p, w.objects["d_blast"], "manual")
	assert_true(bool(r.get("ok", r.get("success", false))), str(r))
	assert_eq(String(Game.state.flags.get("checkpoint_by", "")), "combat")
	await _free(w)


func test_keyboard_movement_drives_walk_animation() -> void:
	Game.new_game(BuildValidator.recommended("vanguard"), "standard")
	Game.state.positions = {"player": [6.0, 6.0, 0.0]}
	var w := World.new()
	_tree().root.add_child(w)
	await _tree().process_frame
	var p := w.controlled()
	var start := p.position
	Input.action_press("move_forward")
	for i in 30:
		await _tree().physics_frame
	assert_true(p.position.distance_to(start) > 0.5, "keyboard moves the character (%.2f m)" % p.position.distance_to(start))
	assert_true(p.visual.move_speed > 2.0, "walk animation driven by keyboard movement (speed %.2f)" % p.visual.move_speed)
	assert_true(absf(p.visual.leg_l.rotation_degrees.x) > 1.0 or absf(p.visual.leg_r.rotation_degrees.x) > 1.0, "legs swing")
	# Pausing freezes keyboard movement too, even with the key held.
	w.set_paused(true)
	var held := p.position
	for i in 20:
		await _tree().physics_frame
	assert_eq(p.position, held, "no keyboard movement while paused")
	w.set_paused(false)
	Input.action_release("move_forward")
	for i in 40:
		await _tree().physics_frame
	assert_true(p.visual.move_speed < 0.3, "back to idle after releasing (speed %.2f)" % p.visual.move_speed)
	assert_eq(p.input_dir, Vector3.ZERO)
	w.queue_free()
	await _tree().process_frame


func _start_checkpoint_fight(w: World) -> void:
	w.alert_encounter("enc_checkpoint")
	w.sim_step(0.1)


func test_combat_start_auto_queues_basic_attack() -> void:
	var w: World = await _world("jump_checkpoint")
	var p := w.controlled()
	p.set_pos(Vector3(50.0, 0, 8.0))
	assert_true(p.queue.is_empty())
	_start_checkpoint_fight(w)
	assert_true(w.combat.active, "combat started")
	assert_eq(p.queue.size(), 1, "one basic attack queued automatically")
	var q: Dictionary = p.queue.front()
	assert_eq(String(q["type"]), "attack")
	assert_true(bool(q.get("auto_queued", false)), "marked as automatic")
	assert_eq(String(q["target"]), p.target_uid, "targets the selected enemy")
	assert_eq(w.auto_target(p).uid, p.target_uid, "the nearest visible enemy")
	# Unpaused, the attack actually happens.
	w.set_paused(false)
	# (Lambdas capture locals by value, so collect into an array.)
	var hits: Array = []
	var on_log := func(e: Dictionary) -> void:
		if String(e.get("text", "")).begins_with(p.sheet.display_name + " →"):
			hits.append(e["text"])
	Events.combat_log.connect(on_log)
	for i in 120:
		w.sim_step(0.1)
		if not hits.is_empty():
			break
	Events.combat_log.disconnect(on_log)
	var logged := not hits.is_empty()
	assert_true(logged, "the auto-queued attack is resolved")
	await _free(w)


func test_player_choice_replaces_auto_attack() -> void:
	var w: World = await _world("jump_checkpoint")
	var p := w.controlled()
	p.set_pos(Vector3(50.0, 0, 8.0))
	_start_checkpoint_fight(w)
	assert_eq(p.queue.size(), 1)
	var feats := p.sheet.action_feats()
	assert_false(feats.is_empty(), "vanguard has an active feat")
	assert_eq(w.queue_action(p, {"type": "feat", "id": feats[0], "target": p.target_uid}), "")
	assert_eq(p.queue.size(), 1, "the automatic attack was replaced, not pushed back")
	assert_eq(String(p.queue.front()["type"]), "feat")
	# Re-selecting a target moves a pending automatic attack with it.
	p.queue.clear()
	assert_true(w.auto_queue_attack(p))
	var other := ""
	for uid in ["chk_d1", "chk_d2", "chk_turret"]:
		if uid != p.target_uid:
			other = uid
			break
	w.cmd_target(p, other)
	assert_eq(String(p.queue.front()["target"]), other, "auto attack follows the new selection")
	# Moving is the player's choice too.
	w.cmd_move(p, p.position + Vector3(-4, 0, 0))
	assert_true(p.queue.is_empty(), "moving drops the automatic attack")
	await _free(w)


func test_no_auto_attack_when_disabled_or_sneaking() -> void:
	var w: World = await _world("jump_checkpoint")
	var p := w.controlled()
	p.set_pos(Vector3(50.0, 0, 8.0))
	Settings.set_v("auto_attack", false, false)
	_start_checkpoint_fight(w)
	assert_true(p.queue.is_empty(), "setting off: nothing queued")
	Settings.set_v("auto_attack", true, false)
	await _free(w)
	var w2: World = await _world("jump_checkpoint")
	var p2 := w2.controlled()
	p2.set_pos(Vector3(44.0, 0, 7.0))
	Game.state.solo = true
	w2.toggle_stealth(p2)
	assert_true(p2.stealth)
	_start_checkpoint_fight(w2)
	assert_true(p2.queue.is_empty(), "a sneaking character is not given an attack that would break stealth")
	await _free(w2)


func test_auto_attack_moves_on_when_target_falls() -> void:
	var w: World = await _world("jump_checkpoint")
	var p := w.controlled()
	p.set_pos(Vector3(50.0, 0, 8.0))
	_start_checkpoint_fight(w)
	w.set_paused(false)
	var first := p.target_uid
	var e: Actor = w.actors[first]
	e.sheet.hp = 0
	w.on_downed(e, "iona")
	assert_true(p.queue.is_empty(), "attack on the fallen target was purged")
	p.current = {}
	p.recovery = 0.0
	for i in 5:
		w.sim_step(0.1)
	assert_true(p.target_uid != "" and p.target_uid != first, "picked the next enemy (%s)" % p.target_uid)
	assert_true(String(p.current.get("type", "attack")) == "attack", "and keeps attacking")
	await _free(w)
