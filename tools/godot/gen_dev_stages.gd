extends Node
## Generates data/dev_stages.json: world-state snapshots taken at the start of
## each major area during a full bot playthrough (diplomat route). Developer
## presets start from these snapshots so checkpoint jumps are consistent with
## real play (doors, cleared encounters, claimed triggers, quest stages).
## Run: godot --headless --path . res://tools/godot/gen_dev_stages.tscn

const STAGES := ["checkpoint", "medical", "engineering", "archive", "command", "bay"]
const KEEP := ["flags", "world", "encounters", "enemies", "npcs", "quests", "areas_visited", "discoveries", "ledger", "tutorials_seen", "vendor_stock", "seen_nodes", "checks"]

var out: Dictionary = {}
var bot: PlaythroughBot


func _ready() -> void:
	Saves.save_root = "user://gen_saves/"
	Events.event.connect(_on_event)
	bot = PlaythroughBot.new(get_tree(), self)
	var b := BuildValidator.recommended("adept")
	b["background"] = "salvager"
	await bot.new_game(b, "standard", 37)
	await Routes.run(bot, "diplomat")
	var f := FileAccess.open("res://data/dev_stages.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", true) + "\n")
	f.close()
	print("dev stages written: ", out.keys(), " failures: ", bot.failures)
	get_tree().quit(0 if bot.failures.is_empty() else 1)


func _on_event(name: String, data: Dictionary) -> void:
	if name != "area_entered" or not bool(data.get("first", false)):
		return
	var aid := String(data.get("area", ""))
	if aid in STAGES and not out.has(aid):
		_capture(aid)  # synchronously: before this step's triggers fire


func _capture(aid: String) -> void:
	var w: World = bot.world
	w.sync_to_state()
	var d := Game.state.to_dict()
	var snap := {}
	for k in KEEP:
		if d.has(k):
			snap[k] = d[k]
	# Keep only finished enemies; untouched encounters respawn from data.
	var enemies: Dictionary = {}
	for uid in (snap.get("enemies", {}) as Dictionary).keys():
		var e: Dictionary = snap["enemies"][uid]
		if String(e.get("state", "")) in ["dead", "gone"]:
			e.erase("sheet")
			enemies[uid] = e
	snap["enemies"] = enemies
	for eid in (snap.get("encounters", {}) as Dictionary).keys():
		var es: Dictionary = snap["encounters"][eid]
		if String(es.get("state", "")) == "pending":
			es["spawned"] = false
	var lead := w.controlled()
	snap["area"] = aid
	snap["pos"] = [snappedf(lead.position.x, 0.1), snappedf(lead.position.z, 0.1), snappedf(lead.rotation_degrees.y, 1.0)]
	snap["party"] = Game.state.party.duplicate()
	snap["player_level"] = Game.state.player().level
	out[aid] = snap
	print("captured stage ", aid, " at ", snap["pos"])
