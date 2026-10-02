extends Node
## Game session facade. Owns the authoritative GameState, routes events to
## the quest system and offers helpers used by the world and UI.

signal state_replaced

var state: GameState = GameState.new()
var world: Node = null
var main: Node = null
var ui_blockers: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.event.connect(_on_event)


func _on_event(name: String, data: Dictionary) -> void:
	if state == null:
		return
	QuestSystem.on_event(state, name, data)


func set_state(s: GameState) -> void:
	state = s
	state_replaced.emit()
	Events.changed("all")


# ------------------------------------------------------------ new game
func new_game(build: Dictionary, difficulty: String = "standard") -> void:
	ItemInst.counter = 0
	var s := GameState.new()
	s.difficulty = difficulty
	var p := BuildValidator.make_sheet(build)
	s.characters["player"] = p
	s.roster = ["player"]
	s.party = ["player"]
	s.controlled = "player"
	var k: Dictionary = DB.klass(p.class_id)
	var eq: Dictionary = k.get("starting_equipment", {})
	for slot in eq.keys():
		p.set_slot(String(slot), ItemInst.make(String(eq[slot])))
	var items: Dictionary = k.get("starting_items", {})
	for id in items.keys():
		s.inventory.add(String(id), int(items[id]))
	var bg: Dictionary = DB.backgrounds.get(p.background, {})
	for id in DB.dict(bg, "starting_items").keys():
		s.inventory.add(String(id), int(bg["starting_items"][id]))
	s.inventory.credits = int(bg.get("credits", 150))
	p.mark_dirty()
	p.hp = p.max_hp()
	p.energy = p.max_energy()
	s.flags["survivors"] = 0
	s.dice.set_seed(int(Time.get_unix_time_from_system()) % 1000000 + 7)
	set_state(s)
	QuestSystem.start_auto(state)


func recruit(comp_id: String) -> CharacterSheet:
	if state.characters.has(comp_id):
		return state.characters[comp_id]
	var c := CharacterSheet.from_companion(comp_id)
	var p := state.player()
	if p != null:
		c.xp = p.xp
	state.characters[comp_id] = c
	if not state.roster.has(comp_id):
		state.roster.append(comp_id)
	if state.party.size() < 3 and not state.party.has(comp_id):
		state.party.append(comp_id)
	Events.post("companion_recruited", {"id": comp_id})
	Events.changed("party")
	return c


func set_active(comp_id: String, active: bool) -> String:
	if comp_id == "player":
		return "The protagonist cannot leave the party."
	if not state.roster.has(comp_id):
		return "Not recruited."
	if active:
		if state.party.has(comp_id):
			return ""
		if state.party.size() >= 3:
			return "The active party is full (you plus two companions)."
		state.party.append(comp_id)
	else:
		state.party.erase(comp_id)
		if state.controlled == comp_id:
			state.controlled = "player"
	Events.post("party_changed", {"id": comp_id, "active": active})
	Events.changed("party")
	return ""


func controlled_sheet() -> CharacterSheet:
	return state.get_char(state.controlled)


# ------------------------------------------------------------ text
func fmt(text: String) -> String:
	if text.find("{") < 0:
		return text
	var p := state.player() if state != null else null
	var name := p.display_name if p != null else "Operator"
	var subj := p.pronoun("subj") if p != null else "they"
	var obj := p.pronoun("obj") if p != null else "them"
	var poss := p.pronoun("poss") if p != null else "their"
	var refl := p.pronoun("refl") if p != null else "themself"
	var t := text
	t = t.replace("{name}", name).replace("{they}", subj).replace("{them}", obj).replace("{their}", poss).replace("{themself}", refl)
	t = t.replace("{They}", subj.capitalize()).replace("{Their}", poss.capitalize()).replace("{Them}", obj.capitalize())
	# Verb agreement helpers: {are} -> are/is, {have} -> have/has, {s} -> ""/"s"
	var plural := subj == "they"
	t = t.replace("{are}", "are" if plural else "is").replace("{have}", "have" if plural else "has").replace("{s}", "" if plural else "s").replace("{were}", "were" if plural else "was")
	if p != null:
		t = t.replace("{class}", String(DB.klass(p.class_id).get("name", p.class_id)))
		t = t.replace("{background}", String(DB.backgrounds.get(p.background, {}).get("name", "")))
	t = t.replace("{survivors}", str(state.survivors() if state != null else 0))
	return t


func block_ui(key: String, on: bool) -> void:
	if on:
		ui_blockers[key] = true
	else:
		ui_blockers.erase(key)


func ui_blocked() -> bool:
	return not ui_blockers.is_empty()
