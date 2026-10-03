extends TestCase
## Presentation layer: conversation reveal, voices and reactions, staging
## that never touches the simulation, data-driven cinematics, held toasts.
## Real-time pieces are driven by calling _process by hand, so nothing here
## waits on the wall clock.


class FakeMain:
	extends Node
	var hud: Variant = null
	var screen: Control

	func _init() -> void:
		screen = Control.new()
		add_child(screen)

	func open_levelup(_uid: String) -> void:
		pass


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _world() -> World:
	Saves.save_root = "user://test_saves/"
	Game.new_game(BuildValidator.recommended("vanguard"), "standard")
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	return w


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await _tree().process_frame


func _dialogue_ui(fm: FakeMain) -> DialogueUI:
	var d := DialogueUI.new()
	d.main = fm
	fm.screen.add_child(d)
	d.visible = false
	return d


func _inject(id: String, nodes: Dictionary) -> void:
	DB.dialogues[id] = {"id": id, "entry": [{"node": "start"}], "nodes": nodes}


func test_dialogue_reveal_and_escaping() -> void:
	var speed: Variant = Settings.get_v("text_speed")
	Settings.set_v("text_speed", 20.0, false)
	var w: World = await _world()
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var dui := _dialogue_ui(fm)
	_inject("_t_reveal", {
		"start": {"speaker": "steward", "text": "Hold the [line], Operator. Then we talk.", "next": "two"},
		"two": {"speaker": "steward", "text": "Second line.", "end": true},
	})
	assert_true(w.start_dialogue("_t_reveal", w.actors.get("steward", null)), "dialogue starts")
	dui.open(w.dialogue)
	assert_true(dui.is_revealing(), "the line reveals over time")
	assert_eq(dui.text_label.visible_characters, 0, "nothing shown at first")
	dui._process(0.5)
	assert_eq(dui.text_label.visible_characters, 10, "20 characters per second")
	assert_true(dui.text_label.get_parsed_text().contains("[line]"), "brackets shown literally: " + dui.text_label.get_parsed_text())
	dui._continue()
	assert_false(dui.is_revealing(), "first press completes the line")
	assert_eq(w.dialogue.node_id, "start", "and does not advance")
	dui._continue()
	assert_eq(w.dialogue.node_id, "two", "second press advances")
	Settings.set_v("text_speed", 0.0, false)
	dui._continue()
	dui._continue()
	assert_true(w.dialogue == null or not w.dialogue.active, "conversation ends")
	Settings.set_v("text_speed", speed, false)
	DB.dialogues.erase("_t_reveal")
	GameAudio.voice_stop("dialogue")
	await _free([dui, fm, w])


func test_reactions_replace_plain_effect_lines() -> void:
	var speed: Variant = Settings.get_v("text_speed")
	Settings.set_v("text_speed", 0.0, false)
	var w: World = await _world()
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var dui := _dialogue_ui(fm)
	_inject("_t_react", {
		"start": {"speaker": "narrator", "text": "A choice.", "choices": [
			{"text": "Be kind.", "next": "after", "tone": "compassionate", "effects": [
				{"influence": "iona", "delta": 4, "key": "_t_react_i", "reason": "test"},
				{"alignment": 3, "key": "_t_react_a", "reason": "test"},
				{"xp": 25, "key": "_t_react_x"}]}]},
		"after": {"speaker": "narrator", "text": "Done.", "end": true},
	})
	w.start_dialogue("_t_react")
	dui.open(w.dialogue)
	var row: HBoxContainer = dui.choices_box.get_child(0)
	assert_eq((row.get_child(0) as ColorRect).color, DialogueUI.TONE_COLORS["compassionate"], "tone strip coloured")
	w.dialogue.choose(0)
	var txt := dui.check_label.get_parsed_text()
	assert_true(txt.contains("Iona Rell approves (+4)"), txt)
	assert_true(txt.contains("Mercy +3"), txt)
	assert_true(txt.contains("+25 XP"), txt)
	assert_false(txt.contains("influence +"), "the plain influence line is not repeated: " + txt)
	Settings.set_v("text_speed", speed, false)
	DB.dialogues.erase("_t_react")
	w.end_dialogue()
	await _free([dui, fm, w])


func test_voice_schedule() -> void:
	var iona := DB.voice_for("iona")
	assert_eq(String(iona["bank"]), "hhi")
	assert_gte(int(iona["count"]), 10, "bank size from data")
	var a := GameAudio.voice_schedule("Hello there, friend. How are you?", iona, 7)
	var b := GameAudio.voice_schedule("Hello there, friend. How are you?", iona, 7)
	assert_gte(a.size(), 6, "one or more syllables per word")
	assert_eq(JSON.stringify(a), JSON.stringify(b), "same line, same sounds")
	for it in a:
		assert_true(String(it["id"]).begins_with("vox_hhi_"), String(it["id"]))
		assert_true(GameAudio.stream(String(it["id"])) != null, "syllable exists: " + String(it["id"]))
	var longer := GameAudio.voice_schedule("Hello there, friend. How are you? I have been waiting on this deck for a very long time.", iona, 7)
	assert_gte(longer.size(), a.size() + 8, "longer text, more syllables")
	assert_gte(float(a[a.size() - 1]["pitch"]), float(a[0]["pitch"]), "a question rises at the end")
	# Repeated words reuse their syllables, like a language.
	var rep := GameAudio.voice_schedule("archive archive", iona, 3)
	assert_eq(String(rep[0]["id"]), String(rep[rep.size() / 2]["id"]), "same word, same first syllable")
	assert_true(GameAudio.voice_schedule("Anything.", DB.voice_for("player"), 1).is_empty(), "the player is silent")
	assert_eq(String(DB.voice_for("warden")["bus"]), "radio")
	assert_eq(String(DB.voice_for("tav7")["bank"]), "syn")
	var dur := GameAudio.voice_line("world", "Testing the voice line.", iona, 5)
	assert_gte(dur, 0.3, "voice_line returns its length")
	assert_true(GameAudio.voice_active("world"))
	GameAudio._process(dur + 0.5)
	assert_false(GameAudio.voice_active("world"), "finishes")
	GameAudio.voice_line("world", "And again.", iona, 6)
	GameAudio.voice_stop("world")
	assert_false(GameAudio.voice_active("world"), "stops")


func _sim_snapshot(w: World) -> String:
	var d := {"dice": Game.state.dice.to_dict(), "t": Game.state.sim_time}
	for uid in w.actors.keys():
		var a: Actor = w.actors[uid]
		d[uid] = [snappedf(a.position.x, 0.0001), snappedf(a.position.z, 0.0001), snappedf(a.rotation.y, 0.0001),
			snappedf(a.facing.x, 0.0001), snappedf(a.facing.y, 0.0001), a.sheet.hp, a.current.duplicate(), a.path.size()]
	return JSON.stringify(d)


func test_dialogue_staging_is_visual_only() -> void:
	var w: World = await _world()
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var dui := _dialogue_ui(fm)
	var p: Actor = w.controlled()
	var steward: Actor = w.actors["steward"]
	p.set_pos(steward.position + Vector3(-2.0, 0, 0))
	p.set_facing_deg(-90.0)  # facing away from the purser
	var before := _sim_snapshot(w)
	w.start_dialogue("steward", steward)
	dui.open(w.dialogue)
	for i in 60:
		w._process(0.05)
		dui._process(0.05)
	assert_true(absf(p.visual.rotation_degrees.y) > 60.0, "the player turns towards the speaker (visual): %.1f" % p.visual.rotation_degrees.y)
	assert_true(w.cam.cinematic, "the conversation camera is framing")
	assert_eq(_sim_snapshot(w), before, "nothing in the simulation changed during the conversation")
	dui.close()
	assert_eq(_sim_snapshot(w), before, "nor after it")
	assert_eq(p.visual.rotation.y, 0.0, "visual yaw restored")
	assert_eq(steward.visual.rotation.y, 0.0, "speaker restored")
	assert_false(w.cam.cinematic, "gameplay camera back")
	assert_true(w.stage == null, "stage cleared")
	await _free([dui, fm, w])


func test_camera_shots_avoid_walls() -> void:
	var w: World = await _world()
	await _tree().physics_frame
	# The cabin's back wall is at z = 2; frame a line along it so the
	# over-the-shoulder eye would sit behind the wall.
	var listener := Vector3(5.0, 0, 2.6)
	var speaker := Vector3(5.0, 0, 5.0)
	w.cam.frame_shot(speaker, listener, "ots", 1.0, false)
	var eye: Vector3 = w.cam._cine_to.origin
	assert_gte(eye.z, 2.0, "camera kept inside the cabin: %s" % str(eye))
	for s in ["close", "two", "ots"]:
		w.cam.frame_shot(Vector3(6, 0, 6), Vector3(4, 0, 6), s, -1.0, false)
		var e2: Vector3 = w.cam._cine_to.origin
		assert_true(e2.x > 2.0 and e2.x < 10.0 and e2.z > 2.0 and e2.z < 10.0, "%s shot inside the cabin: %s" % [s, str(e2)])
	w.cam.end_cinematic()
	await _free([w])


func test_cinematic_from_data_then_dialogue() -> void:
	var w: World = await _world()
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	Cinematics.play(fm, "prologue")
	var c: Cinematics = fm.screen.get_child(fm.screen.get_child_count() - 1)
	assert_eq(c.then_dialogue, "intro_wake", "follow-up from data")
	c._process(0.0)
	assert_true(w.modal.has("cinematic"), "cinematic is modal")
	assert_true(w.cam.scripted, "the script drives the camera")
	var total := 0.0
	for sh in DB.cinematics["prologue"]["shots"]:
		total += float(sh["dur"])
	var t := 0.0
	while t < total + 1.0 and is_instance_valid(c) and not c._done:
		c._process(0.25)
		t += 0.25
	assert_false(w.modal.has("cinematic"), "modal cleared")
	assert_false(w.cam.scripted, "camera released")
	assert_true(w.dialogue != null and w.dialogue.dialogue_id == "intro_wake", "the first conversation follows")
	w.end_dialogue()
	await _free([fm, w])


func test_validator_rejects_bad_staging() -> void:
	_inject("_t_bad", {"start": {"speaker": "narrator", "text": "x", "shot": "dolly", "anim": "dance", "end": true}})
	DB.cinematics["_t_bad"] = {"then": "no_such_dialogue", "shots": [{"dur": 0, "from": [0, 0]}]}
	var errs := DataValidator.new().validate_all(DB)
	var all := "\n".join(errs)
	assert_true(all.contains("unknown shot 'dolly'"), all)
	assert_true(all.contains("unknown anim 'dance'"), all)
	assert_true(all.contains("unknown follow-up dialogue"), all)
	assert_true(all.contains("needs a positive dur"), all)
	DB.dialogues.erase("_t_bad")
	DB.cinematics.erase("_t_bad")
	assert_true(DataValidator.new().validate_all(DB).is_empty(), "clean again")


func test_hud_holds_toasts_during_conversations() -> void:
	var w: World = await _world()
	var fm := FakeMain.new()
	_tree().root.add_child(fm)
	var hud := HUD.new()
	fm.screen.add_child(hud)
	hud.setup(w, fm)
	await _tree().process_frame
	var n0 := hud.toast_box.get_child_count()
	w.set_modal("dialogue", true)
	Events.toast("Quest updated", "quest")
	Events.toast("Iona Rell approves (+2)", "approve")
	assert_eq(hud.toast_box.get_child_count(), n0, "nothing shown behind the conversation")
	assert_eq(hud._held.size(), 2, "held")
	w.set_modal("dialogue", false)
	for i in 4:
		hud._process(0.3)
	assert_eq(hud.toast_box.get_child_count(), n0 + 2, "shown once the HUD is back")
	assert_true(hud._held.is_empty())
	await _free([fm, w])


# ---------------------------------------------------------------- atmosphere and camera
var _saved_cam: Variant = null


func _cam_world(mode: String) -> World:
	_saved_cam = Settings.get_v("camera_mode")
	Settings.set_v("camera_mode", mode, false)
	var w: World = await _world()
	return w


func _cam_done(w: World) -> void:
	Settings.set_v("camera_mode", _saved_cam, false)
	await _free([w])


func _press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


func test_follow_camera_swings_behind() -> void:
	var w: World = await _cam_world("follow")
	var cam := w.cam
	assert_eq(cam.mode, "follow")
	var p: Actor = w.controlled()
	p.set_facing_deg(90.0)
	p.speed_now = 3.0
	_press("move_forward", true)
	for i in 180:
		cam._follow_swing(1.0 / 60.0)
	_press("move_forward", false)
	var want := 90.0 + 180.0
	assert_lte(absf(wrapf(cam.yaw - want, -180.0, 180.0)), 3.0, "behind the leader: yaw %.1f" % cam.yaw)
	# Strafing never swings it (no running in circles).
	p.set_facing_deg(0.0)
	var y0 := cam.yaw
	_press("move_left", true)
	for i in 120:
		cam._follow_swing(1.0 / 60.0)
	_press("move_left", false)
	assert_eq(cam.yaw, y0, "no swing on strafe")
	# Orbiting by hand holds the swing for a moment.
	cam.orbit(40.0, 0.0)
	var y1 := cam.yaw
	_press("move_forward", true)
	for i in 30:
		cam._follow_swing(1.0 / 60.0)
	assert_eq(cam.yaw, y1, "manual orbit holds")
	for i in 180:
		cam._follow_swing(1.0 / 60.0)
	_press("move_forward", false)
	assert_ne(cam.yaw, y1, "and then it eases back behind")
	p.speed_now = 0.0
	await _cam_done(w)


func test_tactical_camera_holds_still() -> void:
	var w: World = await _cam_world("tactical")
	var cam := w.cam
	assert_eq(cam.mode, "tactical")
	assert_eq(cam.pitch, -38.0, "the high orbit")
	var p: Actor = w.controlled()
	p.set_facing_deg(90.0)
	p.speed_now = 3.0
	var y0 := cam.yaw
	_press("move_forward", true)
	for i in 120:
		cam._follow_swing(1.0 / 60.0)
	_press("move_forward", false)
	assert_eq(cam.yaw, y0, "tactical never swings")
	w.sync_to_state()
	var c: Array = Game.state.positions["_cam"]
	assert_eq(String(c[3]), "tactical", "mode saved with the camera")
	p.speed_now = 0.0
	await _cam_done(w)


func test_ceilings_face_down() -> void:
	var w: World = await _world()
	var ceil := w.find_child("Ceilings", true, false) as MeshInstance3D
	assert_true(ceil != null, "ceilings built")
	var arr := ceil.mesh.surface_get_arrays(0)
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	assert_gte(normals.size(), 100, "covers the ship")
	var all_down := true
	for n in normals:
		if n.y > -0.99:
			all_down = false
	assert_true(all_down, "only downward faces: invisible from the tactical camera above")
	for v in verts:
		if v.y < LevelBuilder.WALL_H - 0.1 or v.y > LevelBuilder.WALL_H + 0.001:
			fail("ceiling vertex at height %.2f" % v.y)
			break
	await _free([w])


func test_door_slides_but_grid_opens_at_once() -> void:
	var w: World = await _world()
	var d: WorldObject = w.objects["d_cabin"]
	var cell: Array = d.cells[0]
	var c := Vector2i(int(cell[0]), int(cell[1]))
	var p0 := d.panels[0].position
	d.st()["open"] = true
	d.refresh()
	assert_true(w.grid.walk[w.grid.idx(w.grid.cell_of(Vector3(c.x + 0.5, 0, c.y + 0.5)))] == 1, "passable immediately")
	assert_eq(d.panels[0].position, p0, "panel starts where it was and slides")
	await _tree().create_timer(0.6).timeout
	assert_ne(d.panels[0].position, p0, "panel has slid open")
	await _free([w])


func test_sparks_and_props_freeze_on_pause() -> void:
	var r := DevTools.apply_preset("jump_checkpoint")
	assert_true(bool(r["ok"]))
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	assert_gte(w.atmosphere.sparks.size(), 1, "spark emitters registered")
	w.set_paused(true)
	for p in w.atmosphere.sparks:
		assert_eq((p as CPUParticles3D).speed_scale, 0.0, "sparks hold still on pause")
	var t0 := w.atmosphere._anim_t
	w.atmosphere._process(0.5)
	assert_eq(w.atmosphere._anim_t, t0, "props freeze")
	w.set_paused(false)
	for p in w.atmosphere.sparks:
		assert_eq((p as CPUParticles3D).speed_scale, 1.0)
	await _free([w])


func test_alert_lighting_after_the_emergency() -> void:
	var r := DevTools.apply_preset("jump_checkpoint")
	assert_true(bool(r["ok"]))
	var w := World.new()
	w.manual_step = true
	_tree().root.add_child(w)
	await _tree().process_frame
	var area := w.current_area
	assert_true(bool(DB.dict(DB.dict(DB.layout, "areas"), area).get("alert", false)), "%s is an alert area" % area)
	assert_true(Game.state.has_flag("emergency_started"))
	w.atmosphere._process(0.3)
	var trim: StandardMaterial3D = w.atmosphere.trims[area]
	assert_true(trim.albedo_color.g < 0.95, "trims wash red: %s" % str(trim.albedo_color))
	# The calm commons stays as built.
	assert_eq((w.atmosphere.trims["cabin"] as StandardMaterial3D).albedo_color, Color.WHITE)
	# Announcement pulses go through the same trims.
	w.pulse_trims(Color("#ff4a3a"), 1.0)
	w._process(0.5)
	assert_gte(w.trim_pulse_amount(), 0.5, "pulse at its peak")
	await _free([w])
