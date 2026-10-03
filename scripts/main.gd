extends Node
## Application root: screen flow (main menu → character creator → ship →
## ending), the UI layer with every panel, and input routing so focus is
## always correct between gameplay, menus, dialogue and minigames.

var ui: CanvasLayer
var screen: Control
var world: World
var hud: HUD
var panels: Array[Control] = []
var dialogue_ui: DialogueUI
var args: Dictionary = {}
var _last_click_t := 0.0
var _last_click_pos := Vector2.ZERO


func _ready() -> void:
	Game.main = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	var errs := DB.validate()
	for e in errs:
		push_warning("DATA: " + e)
	print("Ashes of the Concord: data validated, %d issue(s)." % errs.size())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	screen = Control.new()
	screen.theme = UIKit.theme()
	UIKit.full_rect(screen)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	if args.has("quickstart"):
		var b := BuildValidator.recommended(String(args["quickstart"]))
		Game.new_game(b, "standard")
		if args.has("dev"):
			Game.state.dev_mode = true
		_apply_debug_view()
		load_world()
		if args.has("open"):
			call_deferred("_debug_open", String(args["open"]))
		return
	if args.has("preset"):
		var pr := DevTools.apply_preset(String(args["preset"]))
		if not bool(pr["ok"]):
			push_warning("Preset failed: " + String(pr["reason"]))
			show_main_menu()
			return
		_apply_debug_view()
		load_world()
		if args.has("open"):
			call_deferred("_debug_open", String(args["open"]))
		return
	show_main_menu()
	# Screenshot/inspection helpers: --ui=creator [--ui_step=N] [--ui_class=adept],
	# --ui=practice_<shards|slipstream|turret>
	if String(args.get("ui", "")).begins_with("practice_"):
		Minigames.open_practice(screen, String(args["ui"]).substr(9))
	if String(args.get("ui", "")) == "creator":
		show_creator()
		var cc: CharacterCreator = screen.get_child(screen.get_child_count() - 1)
		if args.has("ui_class"):
			cc._set_class(String(args["ui_class"]))
			cc._use_recommended()
		cc._go(int(args.get("ui_step", "0")))


# ================================================================ screens
func clear_screen() -> void:
	close_all_panels()
	UIKit.clear(screen)
	hud = null
	dialogue_ui = null


func show_main_menu() -> void:
	unload_world()
	clear_screen()
	var mm := MainMenu.new()
	mm.main = self
	screen.add_child(mm)
	GameAudio.music("music_menu")
	GameAudio.ambient("")


func show_creator() -> void:
	clear_screen()
	var cc := CharacterCreator.new()
	cc.main = self
	screen.add_child(cc)


func start_new_game(build: Dictionary, difficulty: String) -> void:
	Game.new_game(build, difficulty)
	Settings.set_v("difficulty", difficulty)
	load_world()
	call_deferred("_intro")


## --pos=x,z[,rot] places the party; --cam=yaw,pitch,distance frames the view.
func _apply_debug_view() -> void:
	if args.has("pos"):
		var pp := String(args["pos"]).split(",")
		var rot := float(pp[2]) if pp.size() > 2 else 90.0
		Game.state.positions = {"player": [float(pp[0]), float(pp[1]), rot]}
	if args.has("cam"):
		var cp := String(args["cam"]).split(",")
		Game.state.positions["_cam"] = [float(cp[0]), float(cp[1]), float(cp[2])]


## Screenshot/inspection helper for --quickstart runs: --open=<panel>.
func _debug_open(what: String) -> void:
	await get_tree().process_frame
	match what:
		"vendor":
			_open_station("vendor:requisition", "player")
		"workbench", "medstation", "muster":
			_open_station(what, "player")
		"levelup":
			Game.state.player().xp = Game.state.player().xp_for_level(2)
			open_levelup("player")
		"save", "load":
			open_saveload(what)
		"settings":
			open_settings()
		"dev":
			Game.state.dev_mode = true
			open_dev_menu()
		"prestige":
			var pu := PrestigeUI.new()
			pu.main = self
			push_panel(pu)
		_:
			# --open=dialogue:<id> and --open=cinematic:<id> (screenshots).
			if what.begins_with("dialogue:"):
				var did := what.substr(9)
				var npc_id := String(args.get("npc", ""))
				var ctx := {"object": String(args["obj"])} if args.has("obj") else {}
				world.start_dialogue(did, null, npc_id, ctx)
				# --advance=N steps through N lines (choosing the first option).
				for i in int(args.get("advance", "0")):
					await get_tree().process_frame
					if world.dialogue == null or not world.dialogue.active:
						break
					if world.dialogue.choices().is_empty():
						world.dialogue.advance()
					else:
						world.dialogue.choose(int(world.dialogue.choices()[0]["index"]))
			elif what.begins_with("cinematic:"):
				Cinematics.play(self, what.substr(10))
			elif what.begins_with("bark:") and world.ship_life != null:
				world.ship_life.say_line(what.substr(5), true)
			elif what == "banter" and world.ship_life != null:
				world.ship_life.try_banter()
			else:
				open_game_menu(what)


func _intro() -> void:
	if world != null:
		# An establishing flythrough of the ship, then the first conversation.
		Cinematics.play(self, "prologue", "intro_wake")


func unload_world() -> void:
	if world != null:
		world.queue_free()
		remove_child(world)
		world = null
	Game.world = null


func load_world() -> void:
	unload_world()
	clear_screen()
	world = World.new()
	world.name = "World"
	add_child(world)
	world.ui_request.connect(_on_ui_request)
	hud = HUD.new()
	screen.add_child(hud)
	hud.setup(world, self)
	hud.open_menu.connect(open_game_menu)
	dialogue_ui = DialogueUI.new()
	dialogue_ui.main = self
	screen.add_child(dialogue_ui)
	dialogue_ui.visible = false
	# Ambient voices: barks, banter, announcements, companions asking to talk.
	var sl := ShipLife.new()
	sl.name = "ShipLife"
	world.add_child(sl)
	sl.setup(world)
	world.ship_life = sl
	if Game.state.dev_mode or bool(Settings.get_v("dev_mode")):
		pass


func load_from_slot(slot: String) -> void:
	var r := Saves.load_game(slot)
	if not bool(r["ok"]):
		Events.toast("Load failed: " + String(r["reason"]), "warn")
		return
	if slot == "end_of_intro" or Game.state.has_flag("escaped"):
		# The slice ends at the escape: show that run's summary again.
		unload_world()
		clear_screen()
		var e := EndingUI.new()
		e.main = self
		e.outcome = Game.state.ending if not Game.state.ending.is_empty() else EndingUI.compute_outcome()
		e.saved = true
		screen.add_child(e)
		GameAudio.music("music_ending")
		return
	load_world()
	if String(r.get("reason", "")) != "":
		Events.toast(String(r["reason"]), "warn")
	Events.toast("Loaded %s." % slot.replace("_", " "), "info")


func show_ending() -> void:
	var data := EndingUI.compute_outcome()
	Game.state.ending = data
	var r := Saves.write_file("end_of_intro", {"header": {"schema": GameState.SCHEMA_VERSION, "label": "End of Intro", "time": Time.get_datetime_string_from_system(false, true), "unix": Time.get_unix_time_from_system(), "area": "petrel", "area_name": "Launch craft Petrel", "player": Game.state.player().display_name, "level": Game.state.player().level, "class": String(DB.klass(Game.state.player().class_id).get("name", "")), "play_time": Game.state.play_time, "dev": Game.state.dev_mode}, "state": Game.state.to_dict()})
	unload_world()
	clear_screen()
	var e := EndingUI.new()
	e.main = self
	e.outcome = data
	e.saved = bool(r["ok"])
	screen.add_child(e)
	GameAudio.music("music_ending")


# ================================================================ panels
func push_panel(p: Control) -> void:
	panels.append(p)
	screen.add_child(p)
	if world != null:
		world.set_modal("menu", true)
	GameAudio.play("ui_open", -10.0)


func close_panel(p: Control) -> void:
	if p == null:
		return
	panels.erase(p)
	if is_instance_valid(p):
		p.queue_free()
	if panels.is_empty() and world != null:
		world.set_modal("menu", false)
		if hud:
			hud._dirty = true


func close_top_panel() -> bool:
	if panels.is_empty():
		return false
	var p: Control = panels[panels.size() - 1]
	if p.has_method("request_close"):
		p.call("request_close")
	else:
		close_panel(p)
	return true


func close_all_panels() -> void:
	for p in panels.duplicate():
		close_panel(p)
	panels.clear()


func open_game_menu(tab: String) -> void:
	if world == null:
		return
	if world.modal.has("dialogue") or world.modal.has("minigame") or world.modal.has("cinematic"):
		return
	for p in panels:
		if p is GameMenu:
			(p as GameMenu).show_tab(tab)
			return
	if tab == "system":
		var sm := SystemMenu.new()
		sm.main = self
		push_panel(sm)
		return
	var gm := GameMenu.new()
	gm.main = self
	push_panel(gm)
	gm.show_tab(tab)


func open_levelup(uid: String) -> void:
	var lu := LevelUpUI.new()
	lu.main = self
	lu.uid = uid
	push_panel(lu)


func open_saveload(mode: String) -> void:
	var s := SaveLoadUI.new()
	s.main = self
	s.mode = mode
	push_panel(s)


func open_settings() -> void:
	var s := SettingsUI.new()
	s.main = self
	push_panel(s)


func open_dev_menu() -> void:
	if not (Game.state.dev_mode or bool(Settings.get_v("dev_mode"))):
		Events.toast("Developer menu is disabled. Enable Developer Mode in Settings → Gameplay, or launch with --dev.", "warn")
		return
	var d := DevMenu.new()
	d.main = self
	push_panel(d)


func _on_ui_request(kind: String, data: Dictionary) -> void:
	match kind:
		"area_banner":
			if hud:
				hud.show_banner(String(data["name"]), String(data["sub"]))
		"hover":
			if hud:
				hud.hover_target = data.get("node", null)
		"tutorial":
			if hud:
				hud.show_tutorial(String(data.get("id", "")))
		"interact_menu":
			var im := InteractMenu.new()
			im.main = self
			im.data = data
			push_panel(im)
		"loot":
			var l := LootUI.new()
			l.main = self
			l.object_id = String(data["object"])
			push_panel(l)
		"reader":
			var r := ReaderUI.new()
			r.main = self
			r.data = data
			push_panel(r)
		"station":
			_open_station(String(data["what"]), String(data.get("actor", "player")))
		"open":
			_open_station(String(data.get("what", "")), String(data.get("actor", "player")))
		"minigame":
			_open_station("minigame:" + String(data.get("id", "")), "player")
		"dialogue":
			dialogue_ui.open(world.dialogue)
		"end_dialogue":
			if dialogue_ui:
				dialogue_ui.close()
		"cinematic":
			Cinematics.play(self, String(data.get("id", "")), String(data.get("then", "")))
		"game_over":
			var g := GameOverUI.new()
			g.main = self
			push_panel(g)


func _open_station(what: String, actor_uid: String) -> void:
	if what.begins_with("vendor:"):
		var v := VendorUI.new()
		v.main = self
		v.vendor_id = what.substr(7)
		push_panel(v)
	elif what == "workbench" or what == "medstation":
		var c := CraftingUI.new()
		c.main = self
		c.station = what
		c.crafter_uid = actor_uid
		push_panel(c)
	elif what == "muster":
		var m := MusterUI.new()
		m.main = self
		push_panel(m)
	elif what.begins_with("minigame:"):
		Minigames.open(self, what.substr(9))
	elif what == "ending":
		show_ending()


# ================================================================ input
var _frames := 0


func _process(_delta: float) -> void:
	_frames += 1
	if args.has("quit_after") and _frames >= int(args["quit_after"]):
		if args.has("shot"):
			var img := get_viewport().get_texture().get_image()
			img.save_png(String(args["shot"]))
			print("saved screenshot ", args["shot"], " fps=", Engine.get_frames_per_second())
		get_tree().quit(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		if close_top_panel():
			get_viewport().set_input_as_handled()
			return
		if world != null and dialogue_ui != null and dialogue_ui.visible:
			return
		if world != null:
			open_game_menu("system")
			get_viewport().set_input_as_handled()
		return
	if world == null or not panels.is_empty():
		return
	if world.modal.has("dialogue") or world.modal.has("minigame") or world.modal.has("cinematic"):
		return
	if world.cam.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var now := Time.get_ticks_msec() / 1000.0
			var dbl := mb.double_click or (now - _last_click_t < 0.35 and mb.position.distance_to(_last_click_pos) < 8.0)
			_last_click_t = now
			_last_click_pos = mb.position
			world.handle_click(mb.position, MOUSE_BUTTON_LEFT, dbl)
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or not event.is_pressed() or (event as InputEventKey).echo:
		return
	var lead := world.controlled()
	if event.is_action_pressed("pause"):
		world.toggle_pause()
	elif event.is_action_pressed("switch_character"):
		world.cycle_control()
	elif event.is_action_pressed("interact"):
		_interact_nearest()
	elif event.is_action_pressed("cycle_target"):
		_cycle_target()
	elif event.is_action_pressed("attack_target") and lead != null:
		if world.valid_hostile_target(lead, lead.target_uid):
			world.queue_action(lead, {"type": "attack", "target": lead.target_uid})
		else:
			_cycle_target()
	elif event.is_action_pressed("toggle_stealth"):
		world.toggle_stealth(lead)
	elif event.is_action_pressed("swap_weapons") and hud:
		hud._swap()
	elif event.is_action_pressed("clear_queue") and lead != null:
		lead.queue.clear()
		hud._dirty = true
	elif event.is_action_pressed("party_hold"):
		world.set_party_order("hold" if Game.state.party_order == "follow" else "follow")
	elif event.is_action_pressed("solo_mode"):
		world.set_solo(not Game.state.solo)
	elif event.is_action_pressed("rest"):
		world.rest()
	elif event.is_action_pressed("quicksave"):
		var r := Saves.quicksave()
		Events.toast("Quicksaved." if r["ok"] else "Cannot save: " + String(r["reason"]), "save" if r["ok"] else "warn")
	elif event.is_action_pressed("quickload"):
		load_from_slot("quicksave")
	elif event.is_action_pressed("menu_character"):
		open_game_menu("character")
	elif event.is_action_pressed("menu_inventory"):
		open_game_menu("inventory")
	elif event.is_action_pressed("menu_journal"):
		open_game_menu("journal")
	elif event.is_action_pressed("menu_map"):
		open_game_menu("map")
	elif event.is_action_pressed("menu_abilities"):
		open_game_menu("abilities")
	elif event.is_action_pressed("menu_party"):
		open_game_menu("party")
	elif event.is_action_pressed("toggle_log") and hud:
		hud.toggle_log()
	elif event.is_action_pressed("help"):
		open_game_menu("controls")
	elif event.is_action_pressed("dev_menu"):
		open_dev_menu()
	else:
		for i in 10:
			if event.is_action_pressed("slot_%d" % (i + 1)) and hud:
				hud.trigger_slot(i + 1)
				break
	get_viewport().set_input_as_handled()


func _interact_nearest() -> void:
	var lead := world.controlled()
	if lead == null:
		return
	var best: Node = null
	var bd := 3.2
	for o in world.objects.values():
		var wo: WorldObject = o
		if not wo.is_visible_obj() or wo.kind == "hazard":
			continue
		var d := wo.distance_to_actor(lead)
		if d < bd:
			bd = d
			best = wo
	for a in world.actors.values():
		var aa: Actor = a
		if aa.role == "npc" and not aa.sheet.dead and aa.position.distance_to(lead.position) < bd:
			bd = aa.position.distance_to(lead.position)
			best = aa
	# A companion who has asked to talk, standing right here.
	for uid in Game.state.party:
		var ca: Actor = world.actors.get(uid, null)
		if ca != null and ca != lead and not ShipLife.pending_hook(String(uid)).is_empty() and ca.position.distance_to(lead.position) < minf(bd, 2.5):
			world.talk_companion(String(uid))
			return
	if best is WorldObject:
		world.cmd_interact(lead, best, "")
	elif best is Actor:
		world.cmd_talk(lead, best)
	else:
		Events.toast("Nothing to interact with nearby.", "info")


func _cycle_target() -> void:
	var lead := world.controlled()
	if lead == null:
		return
	var hs: Array = []
	for a in world.actors.values():
		var aa: Actor = a
		if aa.role != "party" and world.hostile(lead, aa) and not aa.sheet.is_downed() and aa.position.distance_to(lead.position) < 25.0 and (aa.alert or world.grid.los(lead.position, aa.position)):
			hs.append(aa)
	if hs.is_empty():
		Events.toast("No visible hostiles.", "info")
		return
	hs.sort_custom(func(x: Actor, y: Actor) -> bool: return x.position.distance_to(lead.position) < y.position.distance_to(lead.position))
	var idx := -1
	for i in hs.size():
		if (hs[i] as Actor).uid == lead.target_uid:
			idx = i
	var nxt: Actor = hs[(idx + 1) % hs.size()]
	world.cmd_target(lead, nxt.uid)
