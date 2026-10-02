class_name Minigames
extends RefCounted
## Entry points for the three minigames: Shards (cards with Brann Ketterick),
## Slipstream (the hover-racing sim booth) and the Petrel's dorsal turret.
##
## open() is used in play: the world reaches it through main._open_station
## ("minigame:<id>") from a station object or a dialogue effect. Ids:
## "shards", "slipstream", "turret" and "turret_practice" (the drill offered
## after a clean launch: practice rules, no flags, no follow-up dialogue).
## open_practice() is the Simulation Deck on the main menu: no wagers, no
## rewards, no state changes, and no world needed.
##
## The rules live in ShardsRules / SlipstreamSim / TurretSim (pure, seeded,
## headless-testable); everything that touches the GameState lives in
## MinigameRewards; the panels only present and route input.

const IDS: Array[String] = ["shards", "slipstream", "turret"]


static func open(main: Node, id: String) -> void:
	var practice := id == "turret_practice"
	var gid := "turret" if practice else id
	if not IDS.has(gid):
		Events.toast("Unknown activity: %s." % id, "warn")
		return
	var w := Game.world as World
	if w != null and w.modal.has("minigame"):
		return
	# When the line that launched the game closes the conversation (Brann's
	# "Sit."), it is read first and the table opens as the conversation ends.
	# A choice that opens a game mid-conversation (the turret, the drill) opens
	# it at once, on top; the conversation waits underneath.
	if w != null and w.dialogue != null and w.dialogue.active and _closing_line(w.dialogue):
		var reopen := func(_d: String) -> void:
			Minigames._open_later(main, id, w)
		w.dialogue.ended.connect(reopen, CONNECT_ONE_SHOT)
		return
	_push(main, id)


static func _push(main: Node, id: String) -> void:
	var practice := id == "turret_practice"
	var p := make_panel("turret" if practice else id, practice)
	p.main = main
	main.push_panel(p)


## True when the current line ends the conversation once it has been read.
static func _closing_line(eng: DialogueEngine) -> bool:
	return eng.choices().is_empty() and (bool(eng.node.get("end", false)) or String(eng.node.get("next", "")) == "")


static func _open_later(main: Node, id: String, w: World) -> void:
	var cb := func() -> void:
		# Skip if the player has left that world meanwhile (loaded, quit...).
		if not is_instance_valid(main) or not is_instance_valid(w) or Game.world != w or w.modal.has("minigame"):
			return
		Minigames._push(main, id)
	cb.call_deferred()


static func open_practice(parent: Node, id: String) -> void:
	var gid := "turret" if id == "turret_practice" else id
	if not IDS.has(gid) or parent == null:
		return
	var p := make_panel(gid, true)
	p.main = null
	parent.add_child(p)


static func make_panel(gid: String, practice: bool) -> MinigamePanel:
	var p: MinigamePanel
	match gid:
		"shards":
			p = ShardsPanel.new()
		"slipstream":
			p = SlipstreamPanel.new()
		_:
			p = TurretPanel.new()
	p.game_id = gid
	p.practice = practice
	p.name = "Minigame_" + gid
	return p


## Posted once whenever a game ends (also in practice).
static func post_finished(id: String, result: String, practice: bool) -> void:
	Events.post("minigame_finished", {"id": id, "result": result, "practice": practice})


## Seeded dice for a run. Real play uses the save's dice (deterministic and
## persisted); practice gets its own so it cannot disturb the saved stream.
static func dice_for(practice: bool) -> Dice:
	if practice or Game.state == null:
		return Dice.new(int(Time.get_ticks_usec() % 2147483647) + 1)
	return Game.state.dice


## "story", "standard" or "hard", from the difficulty setting.
static func difficulty() -> String:
	var d := String(Settings.get_v("difficulty")) if Settings.get_v("difficulty") != null else ""
	if d == "" and Game.state != null:
		d = Game.state.difficulty
	return TurretSim.difficulty_key(d)


static func reduce_flash() -> bool:
	return bool(Settings.get_v("reduce_flash"))


static func reduce_shake() -> bool:
	return bool(Settings.get_v("reduce_shake"))
