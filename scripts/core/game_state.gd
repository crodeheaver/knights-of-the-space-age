class_name GameState
extends RefCounted
## The authoritative, serializable game state. Everything that must survive a
## save/load lives here (or is produced by to_dict of an owned object).

const SCHEMA_VERSION := 1

var characters: Dictionary = {}
var roster: Array[String] = []
var party: Array[String] = []
var controlled: String = "player"
var inventory := Inventory.new()
var flags: Dictionary = {}
var quests: Dictionary = {}
var tracked_quest: String = "q_main"
var influence: Dictionary = {"iona": 50, "tav7": 50}
var influence_log: Array = []
var alignment: int = 0
var alignment_log: Array = []
var ledger: Dictionary = {}
var world: Dictionary = {}
var enemies: Dictionary = {}
var encounters: Dictionary = {}
var explored: PackedByteArray = PackedByteArray()
var areas_visited: Array[String] = []
var discoveries: Array[String] = []
var dialogue_history: Array = []
var seen_nodes: Dictionary = {}
var checks: Dictionary = {}
var vendor_stock: Dictionary = {}
var tutorials_seen: Dictionary = {}
var positions: Dictionary = {}
var area: String = "cabin"
var dice := Dice.new(20240917)
var sim_time: float = 0.0
var play_time: float = 0.0
var difficulty: String = "standard"
var dev_mode: bool = false
var preset_id: String = ""
var queues: Dictionary = {}
var combat: Dictionary = {}
var minigames: Dictionary = {}
var ending: Dictionary = {}
var stats: Dictionary = {"xp_total": 0, "kills": 0, "checks_passed": 0, "checks_failed": 0}
var party_order: String = "follow"
var solo: bool = false
var npcs: Dictionary = {}


func get_char(uid: String) -> CharacterSheet:
	return characters.get(uid, null)


func player() -> CharacterSheet:
	return characters.get("player", null)


func flag(name: String, default_value: Variant = null) -> Variant:
	return flags.get(name, default_value)


func has_flag(name: String) -> bool:
	var v: Variant = flags.get(name, null)
	return v != null and v != false and not (typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) == 0.0)


func set_flag(name: String, value: Variant = true) -> void:
	var old: Variant = flags.get(name, null)
	flags[name] = value
	if old != value:
		Events.post("flag_changed", {"flag": name, "value": value, "old": old})


## One-time ledger. Returns true the first time a key is claimed.
func claim(key: String) -> bool:
	if key == "":
		return true
	if ledger.has(key):
		return false
	ledger[key] = sim_time
	return true


func claimed(key: String) -> bool:
	return ledger.has(key)


func grant_xp(amount: int, key: String, reason: String) -> int:
	if amount <= 0:
		return 0
	if key != "" and not claim("xp:" + key):
		return 0
	for uid in roster:
		var s := get_char(uid)
		if s != null:
			s.xp += amount
	stats["xp_total"] = int(stats.get("xp_total", 0)) + amount
	Events.post("xp_gained", {"amount": amount, "key": key, "reason": reason})
	return amount


func add_influence(comp: String, delta: int, key: String, reason: String) -> int:
	if not influence.has(comp) or delta == 0:
		return 0
	if key != "" and not claim("inf:%s:%s" % [comp, key]):
		return 0
	var before := int(influence[comp])
	var after := clampi(before + delta, 0, 100)
	influence[comp] = after
	influence_log.append({"companion": comp, "delta": after - before, "requested": delta, "reason": reason, "key": key, "time": snappedf(play_time, 0.1), "value": after})
	Events.post("influence_changed", {"companion": comp, "delta": after - before, "value": after, "reason": reason})
	return after - before


func add_alignment(delta: int, key: String, reason: String) -> int:
	if delta == 0:
		return 0
	if key != "" and not claim("align:" + key):
		return 0
	var before := alignment
	alignment = clampi(alignment + delta, -100, 100)
	alignment_log.append({"delta": alignment - before, "requested": delta, "reason": reason, "key": key, "value": alignment, "time": snappedf(play_time, 0.1)})
	Events.post("alignment_changed", {"delta": alignment - before, "value": alignment, "reason": reason})
	return alignment - before


static func alignment_label(v: int) -> String:
	if v >= 60:
		return "Mercy (devoted)"
	if v >= 25:
		return "Mercy"
	if v > -25:
		return "Balanced"
	if v > -60:
		return "Dominion"
	return "Dominion (absolute)"


func world_obj(id: String) -> Dictionary:
	if not world.has(id):
		world[id] = {}
	return world[id]


func discover(entry: String) -> bool:
	if discoveries.has(entry):
		return false
	discoveries.append(entry)
	Events.post("discovery", {"id": entry})
	return true


func add_history(speaker: String, text: String, dialogue_id: String) -> void:
	dialogue_history.append({"speaker": speaker, "text": text, "dialogue": dialogue_id, "time": snappedf(play_time, 0.1)})
	if dialogue_history.size() > 600:
		dialogue_history.pop_front()


func survivors() -> int:
	return int(flags.get("survivors", 0))


# ------------------------------------------------------------ persistence
func to_dict() -> Dictionary:
	var chars := {}
	for k in characters.keys():
		chars[k] = (characters[k] as CharacterSheet).to_dict()
	return {
		"schema": SCHEMA_VERSION,
		"characters": chars, "roster": roster.duplicate(), "party": party.duplicate(), "controlled": controlled,
		"inventory": inventory.to_dict(), "flags": flags.duplicate(true), "quests": quests.duplicate(true),
		"tracked_quest": tracked_quest, "influence": influence.duplicate(), "influence_log": influence_log.duplicate(true),
		"alignment": alignment, "alignment_log": alignment_log.duplicate(true), "ledger": ledger.duplicate(),
		"world": world.duplicate(true), "enemies": enemies.duplicate(true), "encounters": encounters.duplicate(true),
		"explored": Marshalls.raw_to_base64(explored), "areas_visited": areas_visited.duplicate(),
		"discoveries": discoveries.duplicate(), "dialogue_history": dialogue_history.duplicate(true),
		"seen_nodes": seen_nodes.duplicate(), "checks": checks.duplicate(true), "vendor_stock": vendor_stock.duplicate(true),
		"tutorials_seen": tutorials_seen.duplicate(), "positions": positions.duplicate(true), "area": area,
		"dice": dice.to_dict(), "sim_time": sim_time, "play_time": play_time, "difficulty": difficulty,
		"dev_mode": dev_mode, "preset_id": preset_id, "queues": queues.duplicate(true), "combat": combat.duplicate(true),
		"minigames": minigames.duplicate(true), "ending": ending.duplicate(true), "stats": stats.duplicate(),
		"party_order": party_order, "solo": solo, "npcs": npcs.duplicate(true), "item_uid_counter": ItemInst.counter,
	}


static func from_dict(d: Dictionary) -> GameState:
	var g := GameState.new()
	var chars: Dictionary = d.get("characters", {})
	for k in chars.keys():
		g.characters[String(k)] = CharacterSheet.from_dict(chars[k])
	g.roster = DB.str_arr(d.get("roster", []))
	g.party = DB.str_arr(d.get("party", []))
	g.controlled = String(d.get("controlled", "player"))
	g.inventory.from_dict(d.get("inventory", {}))
	g.flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	g.quests = (d.get("quests", {}) as Dictionary).duplicate(true)
	g.tracked_quest = String(d.get("tracked_quest", "q_main"))
	g.influence = {}
	var inf: Dictionary = d.get("influence", {"iona": 50, "tav7": 50})
	for k in inf.keys():
		g.influence[String(k)] = int(inf[k])
	g.influence_log = (d.get("influence_log", []) as Array).duplicate(true)
	g.alignment = int(d.get("alignment", 0))
	g.alignment_log = (d.get("alignment_log", []) as Array).duplicate(true)
	g.ledger = (d.get("ledger", {}) as Dictionary).duplicate()
	g.world = (d.get("world", {}) as Dictionary).duplicate(true)
	g.enemies = (d.get("enemies", {}) as Dictionary).duplicate(true)
	g.encounters = (d.get("encounters", {}) as Dictionary).duplicate(true)
	g.explored = Marshalls.base64_to_raw(String(d.get("explored", "")))
	g.areas_visited = DB.str_arr(d.get("areas_visited", []))
	g.discoveries = DB.str_arr(d.get("discoveries", []))
	g.dialogue_history = (d.get("dialogue_history", []) as Array).duplicate(true)
	g.seen_nodes = (d.get("seen_nodes", {}) as Dictionary).duplicate()
	g.checks = (d.get("checks", {}) as Dictionary).duplicate(true)
	g.vendor_stock = {}
	var vs: Dictionary = d.get("vendor_stock", {})
	for v in vs.keys():
		var st := {}
		for k in (vs[v] as Dictionary).keys():
			st[String(k)] = int(vs[v][k])
		g.vendor_stock[String(v)] = st
	g.tutorials_seen = (d.get("tutorials_seen", {}) as Dictionary).duplicate()
	g.positions = (d.get("positions", {}) as Dictionary).duplicate(true)
	g.area = String(d.get("area", "cabin"))
	g.dice.from_dict(d.get("dice", {}))
	g.sim_time = float(d.get("sim_time", 0.0))
	g.play_time = float(d.get("play_time", 0.0))
	g.difficulty = String(d.get("difficulty", "standard"))
	g.dev_mode = bool(d.get("dev_mode", false))
	g.preset_id = String(d.get("preset_id", ""))
	g.queues = (d.get("queues", {}) as Dictionary).duplicate(true)
	g.combat = (d.get("combat", {}) as Dictionary).duplicate(true)
	g.minigames = (d.get("minigames", {}) as Dictionary).duplicate(true)
	g.ending = (d.get("ending", {}) as Dictionary).duplicate(true)
	g.stats = (d.get("stats", {}) as Dictionary).duplicate()
	g.party_order = String(d.get("party_order", "follow"))
	g.solo = bool(d.get("solo", false))
	g.npcs = (d.get("npcs", {}) as Dictionary).duplicate(true)
	ItemInst.counter = maxi(ItemInst.counter, int(d.get("item_uid_counter", 0)))
	return g
