class_name WorldObject
extends Node3D
## Data-driven interactable (doors, containers, terminals, readables, corpses,
## mines, hazards, stations, repairable machinery). Definitions come from
## data/ship_layout.json; mutable state lives in GameState.world[id] so it is
## saved and restored. Options are evaluated per acting character.

var id: String = ""
var def: Dictionary = {}
var kind: String = ""
var world: World
var label: Label3D
var mesh_root: Node3D
var panels: Array[Node3D] = []
var indicator: MeshInstance3D
var cells: Array = []
var reach := 2.2
var center := Vector3.ZERO
var _anim := 0.0


func setup(d: Dictionary, w: World) -> void:
	def = d
	id = String(d["id"])
	kind = String(d.get("type", "panel"))
	world = w
	name = "Obj_" + id
	var p: Array = d.get("pos", [0, 0])
	position = Vector3(float(p[0]), 0, float(p[1]))
	rotation_degrees.y = float(d.get("rot", 0))
	center = position
	reach = float(d.get("reach", 2.2))
	if kind == "door":
		cells = d.get("cells", [])
		var c0: Array = cells[0]
		var c1: Array = cells[cells.size() - 1]
		position = Vector3((float(c0[0]) + float(c1[0])) * 0.5 + 0.5, 0, (float(c0[1]) + float(c1[1])) * 0.5 + 0.5)
		center = position
	mesh_root = Node3D.new()
	add_child(mesh_root)
	_build_visual()
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 26
	label.outline_size = 8
	label.pixel_size = 0.006
	label.position = Vector3(0, float(d.get("label_h", 1.9)), 0)
	label.visible = false
	add_child(label)
	refresh()


func st() -> Dictionary:
	return Game.state.world_obj(id)


func display_name() -> String:
	return Game.fmt(String(def.get("name", id.capitalize())))


# ------------------------------------------------------------ state
func is_open() -> bool:
	return bool(st().get("open", def.get("open", false)))


func is_locked() -> bool:
	return bool(st().get("locked", def.get("locked", false)))


func is_detected() -> bool:
	if int(def.get("hidden_dc", 0)) <= 0:
		return true
	return bool(st().get("detected", false))


func is_active() -> bool:
	## Hazards/mines: armed and active conditions.
	if bool(st().get("disabled", false)):
		return false
	if def.has("active_if") and not Conditions.eval_all(def["active_if"], Game.state):
		return false
	return true


func is_visible_obj() -> bool:
	if def.has("if") and not Conditions.eval_all(def["if"], Game.state):
		return false
	if bool(st().get("removed", false)):
		return false
	return is_detected()


func refresh() -> void:
	visible = is_visible_obj() or kind == "door"
	if kind == "door":
		_apply_door()
	elif kind == "hazard":
		mesh_root.visible = is_detected() and is_active()
	elif kind == "mine":
		mesh_root.visible = is_detected() and not bool(st().get("disarmed", false))
	if indicator:
		var col := Color("#5fd38a")
		if kind == "door":
			if is_locked():
				col = Color("#ff5a4a") if not bool(def.get("sealed", false)) else Color("#f2c26b")
			elif is_open():
				col = Color("#5fd38a")
			else:
				col = Color("#7fd0ff")
		elif kind == "container" and bool(st().get("looted", false)):
			col = Color("#555a60")
		indicator.material_override = MeshKit.unshaded(col)


func _apply_door() -> void:
	var open := is_open()
	world.grid.set_blocked(cells, not open, true)
	var span := float(cells.size())
	for i in panels.size():
		var pn: Node3D = panels[i]
		var side := -1.0 if i == 0 else 1.0
		var off := side * (span * 0.25 + (span * 0.47 if open else 0.0))
		pn.position = Vector3(off, 0, 0) if _axis() == "x" else Vector3(0, 0, off)
	if label:
		label.text = display_name() + (" [LOCKED]" if is_locked() else "")


# ------------------------------------------------------------ visuals
func _build_visual() -> void:
	var model := String(def.get("model", kind))
	var accent := Color(String(def.get("color", "#7fd0ff")))
	var dark := MeshKit.mat(Color("#2b3038"), 0.5, 0.6)
	var mid := MeshKit.mat(Color("#4a515c"), 0.5, 0.5)
	var glow := MeshKit.unshaded(accent)
	match model:
		"door", "blast", "grate", "hatch", "sealed":
			_build_door(model)
		"locker":
			_box(Vector3(0.9, 2.0, 0.6), Vector3(0, 1.0, 0), mid)
			_box(Vector3(0.02, 1.8, 0.62), Vector3(0, 1.0, 0), dark)
			indicator = _box(Vector3(0.08, 0.08, 0.05), Vector3(0.3, 1.4, 0.31), glow)
		"case":
			_box(Vector3(0.8, 0.25, 0.5), Vector3(0, 0.95, 0), MeshKit.mat(Color("#1d2026"), 0.4, 0.7))
			_box(Vector3(0.82, 0.04, 0.52), Vector3(0, 1.0, 0), MeshKit.unshaded(Color("#ffd27a")))
			_box(Vector3(1.0, 0.8, 0.7), Vector3(0, 0.4, 0), mid)
			indicator = _box(Vector3(0.06, 0.06, 0.06), Vector3(0.3, 1.12, 0.2), glow)
		"crate":
			_box(Vector3(1.0, 0.8, 0.8), Vector3(0, 0.4, 0), MeshKit.mat(Color("#5b4a36"), 0.8, 0.1))
			_box(Vector3(1.02, 0.08, 0.82), Vector3(0, 0.7, 0), dark)
			indicator = _box(Vector3(0.1, 0.1, 0.02), Vector3(0, 0.45, 0.41), glow)
		"terminal", "console":
			_box(Vector3(0.9, 1.0, 0.5), Vector3(0, 0.5, 0), mid)
			var scr := _box(Vector3(0.8, 0.5, 0.05), Vector3(0, 1.25, 0.05), glow)
			scr.rotation_degrees.x = -15
			_box(Vector3(0.9, 0.08, 0.4), Vector3(0, 1.0, 0.12), dark)
			indicator = scr
		"datapad":
			_box(Vector3(0.6, 0.75, 0.4), Vector3(0, 0.375, 0), mid)
			_box(Vector3(0.24, 0.02, 0.32), Vector3(0, 0.77, 0), glow)
		"corpse":
			var c := Node3D.new()
			mesh_root.add_child(c)
			var cloth := MeshKit.mat(Color(String(def.get("cloth", "#3d4552"))), 0.8, 0.1)
			_box(Vector3(0.42, 0.22, 1.5), Vector3(0, 0.12, 0), cloth)
			mesh_root.add_child(MeshKit.sphere(0.13, MeshKit.mat(Color("#9c8f86"))))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.14, 0.88)
			_box(Vector3(0.9, 0.01, 0.7), Vector3(0.1, 0.005, 0.2), MeshKit.mat(Color("#3a1414"), 0.3, 0.0))
		"wreck":
			_box(Vector3(0.7, 0.3, 0.6), Vector3(0, 0.15, 0), dark)
			_box(Vector3(0.3, 0.2, 0.5), Vector3(0.3, 0.1, 0.2), mid)
			indicator = _box(Vector3(0.06, 0.06, 0.06), Vector3(0, 0.32, 0), MeshKit.unshaded(Color("#ff5a4a")))
		"workbench":
			_box(Vector3(2.0, 0.9, 0.9), Vector3(0, 0.45, 0), mid)
			_box(Vector3(2.0, 0.06, 0.9), Vector3(0, 0.92, 0), dark)
			_box(Vector3(0.5, 0.25, 0.3), Vector3(-0.5, 1.07, -0.1), dark)
			_box(Vector3(1.8, 0.8, 0.08), Vector3(0, 1.4, -0.42), MeshKit.mat(Color("#383e47"), 0.6, 0.4))
			indicator = _box(Vector3(0.3, 0.05, 0.3), Vector3(0.5, 0.96, 0.1), MeshKit.unshaded(Color("#7fd0ff")))
		"medstation":
			_box(Vector3(1.2, 1.6, 0.8), Vector3(0, 0.8, 0), MeshKit.mat(Color("#d9dde2"), 0.4, 0.2))
			_box(Vector3(0.12, 0.45, 0.02), Vector3(0, 1.25, 0.41), MeshKit.unshaded(Color("#5fd38a")))
			_box(Vector3(0.45, 0.12, 0.02), Vector3(0, 1.25, 0.41), MeshKit.unshaded(Color("#5fd38a")))
			indicator = _box(Vector3(0.8, 0.3, 0.02), Vector3(0, 0.7, 0.41), MeshKit.unshaded(Color("#7fd0ff")))
		"vendor":
			_box(Vector3(1.0, 2.1, 0.7), Vector3(0, 1.05, 0), MeshKit.mat(Color("#3a3248"), 0.5, 0.4))
			indicator = _box(Vector3(0.75, 0.6, 0.03), Vector3(0, 1.45, 0.36), MeshKit.unshaded(Color("#f2c26b")))
			_box(Vector3(0.6, 0.08, 0.2), Vector3(0, 0.95, 0.4), dark)
		"booth":
			_box(Vector3(1.6, 0.6, 2.0), Vector3(0, 0.3, 0), dark)
			_box(Vector3(1.4, 1.2, 0.1), Vector3(0, 1.2, -0.9), MeshKit.mat(Color("#20242b"), 0.5, 0.5))
			indicator = _box(Vector3(1.2, 0.7, 0.03), Vector3(0, 1.35, -0.84), MeshKit.unshaded(Color("#8a6ad8")))
			_box(Vector3(0.6, 0.5, 0.6), Vector3(0, 0.85, 0.3), mid)
		"card_table":
			mesh_root.add_child(MeshKit.cyl(0.8, 0.8, 0.06, MeshKit.mat(Color("#2f5a3f"), 0.8, 0.0), 20))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.82, 0)
			mesh_root.add_child(MeshKit.cyl(0.12, 0.2, 0.8, dark))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.4, 0)
			for i in 4:
				var card := _box(Vector3(0.12, 0.01, 0.18), Vector3(-0.3 + i * 0.2, 0.86, 0.1), MeshKit.unshaded(Color("#e8e0c8") if i % 2 == 0 else Color("#e8823a")))
				card.rotation_degrees.y = i * 12.0
			indicator = null
		"pump":
			mesh_root.add_child(MeshKit.cyl(0.5, 0.55, 1.8, mid))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.9, 0)
			mesh_root.add_child(MeshKit.torus(0.48, 0.6, dark))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 1.3, 0)
			indicator = _box(Vector3(0.2, 0.2, 0.05), Vector3(0, 1.0, 0.55), glow)
		"valve", "junction":
			_box(Vector3(0.8, 1.2, 0.4), Vector3(0, 0.9, 0), mid)
			indicator = _box(Vector3(0.5, 0.15, 0.03), Vector3(0, 1.2, 0.21), glow)
		"mine":
			mesh_root.add_child(MeshKit.cyl(0.25, 0.28, 0.08, MeshKit.mat(Color("#2b2f35"), 0.4, 0.8)))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.04, 0)
			indicator = _box(Vector3(0.06, 0.04, 0.06), Vector3(0, 0.1, 0), MeshKit.unshaded(Color("#ff5a4a")))
		"hazard":
			var sz: Array = def.get("size", [2, 2])
			var hcol := Color(String(def.get("color", "#7fd0ff")))
			hcol.a = 0.35
			var q := _box(Vector3(float(sz[0]), 0.02, float(sz[1])), Vector3(0, 0.02, 0), MeshKit.unshaded(hcol))
			q.position = Vector3.ZERO + Vector3(0, 0.02, 0)
		"muster":
			mesh_root.add_child(MeshKit.torus(0.8, 0.95, MeshKit.unshaded(Color("#5fd38a"))))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 0.03, 0)
			_box(Vector3(0.5, 1.4, 0.3), Vector3(0, 0.7, -1.2), mid)
			indicator = _box(Vector3(0.4, 0.3, 0.02), Vector3(0, 1.2, -1.04), MeshKit.unshaded(Color("#5fd38a")))
		"core":
			mesh_root.add_child(MeshKit.cyl(0.6, 0.6, 2.6, MeshKit.mat(Color("#20242b"), 0.4, 0.7)))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 1.3, 0)
			mesh_root.add_child(MeshKit.cyl(0.45, 0.45, 2.4, MeshKit.unshaded(Color("#e8823a"))))
			mesh_root.get_child(mesh_root.get_child_count() - 1).position = Vector3(0, 1.3, 0)
			mesh_root.get_child(mesh_root.get_child_count() - 1).scale = Vector3(1.02, 1, 0.3)
			indicator = null
		"launch_console":
			_box(Vector3(2.2, 1.0, 0.8), Vector3(0, 0.5, 0), mid)
			var s2 := _box(Vector3(2.0, 0.6, 0.05), Vector3(0, 1.3, 0.1), MeshKit.unshaded(Color("#e8823a")))
			s2.rotation_degrees.x = -20
			indicator = s2
		_:
			_box(Vector3(0.6, 0.9, 0.5), Vector3(0, 0.45, 0), mid)
			indicator = _box(Vector3(0.3, 0.1, 0.03), Vector3(0, 0.7, 0.26), glow)


func _box(size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshKit.box(size, m)
	mesh_root.add_child(mi)
	mi.position = pos
	return mi


func _build_door(model: String) -> void:
	var span := float(cells.size())
	var axis := _axis()
	var col := Color("#5a6370")
	match model:
		"blast":
			col = Color("#6b5a3a")
		"grate":
			col = Color("#3a4048")
		"hatch":
			col = Color("#4a5260")
		"sealed":
			col = Color("#6b4a3a")
	var m := MeshKit.mat(col, 0.45, 0.7)
	var hgt := 3.0 if model != "grate" and model != "hatch" else 1.6
	var thick := 0.35 if model == "blast" else 0.2
	for i in 2:
		var pn := Node3D.new()
		mesh_root.add_child(pn)
		var size := Vector3(span * 0.5, hgt, thick) if axis == "x" else Vector3(thick, hgt, span * 0.5)
		var b := MeshKit.box(size, m)
		pn.add_child(b)
		b.position = Vector3(0, hgt * 0.5, 0)
		var stripe := MeshKit.box(Vector3(size.x * 0.9, 0.08, size.z + 0.02) if axis == "x" else Vector3(size.x + 0.02, 0.08, size.z * 0.9), MeshKit.unshaded(Color("#e8823a") if model == "blast" else Color("#7fd0ff")))
		pn.add_child(stripe)
		stripe.position = Vector3(0, 1.4, 0)
		panels.append(pn)
	# frame + indicator light (shape + colour + label for accessibility)
	indicator = MeshKit.box(Vector3(0.18, 0.18, 0.18), MeshKit.unshaded(Color("#7fd0ff")))
	mesh_root.add_child(indicator)
	indicator.position = Vector3(0, hgt + 0.25, 0)
	label_offset_door(hgt)


func label_offset_door(hgt: float) -> void:
	def["label_h"] = hgt + 0.6


func _axis() -> String:
	if cells.size() >= 2 and int(cells[0][0]) != int(cells[1][0]):
		return "x"
	return "z"


func _process(delta: float) -> void:
	if kind == "mine" and indicator and mesh_root.visible:
		_anim += delta
		indicator.visible = fmod(_anim, 1.0) < 0.5


# ------------------------------------------------------------ interaction
func distance_to_actor(a: Actor) -> float:
	if kind == "door":
		var best := INF
		for c in cells:
			best = minf(best, Vector2(float(c[0]) + 0.5, float(c[1]) + 0.5).distance_to(a.pos2()))
		return best
	return Vector2(position.x, position.z).distance_to(a.pos2())


func approach_point(a: Actor) -> Vector3:
	var grid: ShipGrid = world.grid
	if kind == "door":
		# Stand on the actor's side of the doorway.
		var best := Vector3.ZERO
		var bd := INF
		for c in cells:
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var cc := grid.world_cell(int(c[0]) + off.x, int(c[1]) + off.y)
				if grid.passable(cc):
					var p := grid.center_of(cc)
					var d := p.distance_to(a.position)
					if d < bd:
						bd = d
						best = p
		return best if bd < INF else a.position
	return grid.nearest_passable(position + (a.position - position).normalized() * 1.0, 3)


## Interaction options for an acting character.
func options(actor: Actor) -> Array:
	var out: Array = []
	var s: CharacterSheet = actor.sheet
	match kind:
		"door":
			if not is_open() and not is_locked():
				out.append({"id": "_open", "label": "Open", "enabled": true})
			elif is_locked():
				var lt := String(st().get("lock_text", def.get("lock_text", "Locked.")))
				out.append({"id": "_info", "label": Game.fmt(lt), "enabled": false, "reason": ""})
		"container", "corpse", "wreck":
			if not bool(st().get("looted", false)) and not is_locked():
				out.append({"id": "_loot", "label": "Search" if kind != "container" else "Open", "enabled": true})
			elif bool(st().get("looted", false)):
				out.append({"id": "_info", "label": "Empty.", "enabled": false, "reason": ""})
		"readable":
			out.append({"id": "_read", "label": String(def.get("verb", "Read")), "enabled": true})
		"terminal":
			if def.has("dialogue"):
				out.append({"id": "_dialogue", "label": String(def.get("verb", "Access terminal")), "enabled": true})
		"workbench":
			out.append({"id": "_open_station", "label": "Use workbench", "enabled": true, "what": "workbench"})
		"medstation":
			out.append({"id": "_open_station", "label": "Use medical fabricator", "enabled": true, "what": "medstation"})
		"vendor":
			out.append({"id": "_open_station", "label": "Browse stock", "enabled": true, "what": "vendor:" + String(def.get("vendor", ""))})
		"minigame":
			out.append({"id": "_open_station", "label": String(def.get("verb", "Play")), "enabled": true, "what": "minigame:" + String(def.get("minigame", ""))})
		"muster":
			out.append({"id": "_open_station", "label": "Muster point: change party / rest", "enabled": true, "what": "muster"})
		"mine":
			if is_detected() and not bool(st().get("disarmed", false)):
				var dc := int(def.get("disarm_dc", DB.dict(DB.item(String(def.get("mine_item", "frag_mine"))), "mine").get("disarm_dc", 14)))
				out.append(_skill_opt("_disarm", "Disarm mine", "demolitions", dc, s))
				out.append(_skill_opt("_recover", "Recover mine", "demolitions", dc + 5, s))
	for o in def.get("options", []):
		var od: Dictionary = o
		if od.has("hide_if") and Conditions.eval_all(od["hide_if"], Game.state, {"actor": actor.uid}):
			continue
		if bool(od.get("once", false)) and bool(DB.dict(st(), "done").get(String(od["id"]), false)):
			continue
		var row := {"id": String(od["id"]), "label": Game.fmt(String(od.get("label", od["id"]))), "enabled": true, "reason": "", "data": od}
		if od.has("if") and not Conditions.eval_all(od["if"], Game.state, {"actor": actor.uid}):
			if not od.has("locked_text"):
				continue
			row["enabled"] = false
			row["reason"] = Game.fmt(String(od["locked_text"]))
		if od.has("skill"):
			var so := _skill_opt(String(od["id"]), row["label"], String(od["skill"]), int(od.get("dc", 10)), s)
			row.merge(so, true)
			row["data"] = od
		if od.has("requires_item") and Game.state.inventory.count(String(od["requires_item"])) <= 0:
			row["enabled"] = false
			row["reason"] = "Requires %s" % DB.item_name(String(od["requires_item"]))
		if od.has("energy"):
			if s.energy < int(od["energy"]):
				row["enabled"] = false
				row["reason"] = "Needs %d energy" % int(od["energy"])
			if not s.is_player and bool(od.get("player_only", false)):
				row["enabled"] = false
				row["reason"] = "Only you can do this"
		if bool(od.get("player_only", false)) and not s.is_player:
			row["enabled"] = false
			row["reason"] = "Only %s can do this" % Game.state.player().display_name
		if od.has("max_attempts"):
			var used := _attempts(String(od["id"]), actor.uid if String(od.get("attempt_scope", "character")) == "character" else "_all")
			if used >= int(od["max_attempts"]):
				row["enabled"] = false
				row["reason"] = "%s already tried — another approach or party member is needed" % (actor.sheet.display_name if String(od.get("attempt_scope", "character")) == "character" else "Already attempted")
		if od.has("bash"):
			row["bash"] = od["bash"]
		out.append(row)
	return out


func _skill_opt(oid: String, label_text: String, skill: String, dc: int, s: CharacterSheet) -> Dictionary:
	var total := s.skill_total(skill)
	var chance := clampi((21 - (dc - total)) * 5, 0, 100)
	return {"id": oid, "label": label_text, "enabled": true, "reason": "", "skill": skill, "dc": dc, "bonus": total, "chance": chance,
		"tag": "%s %d · %s %s (%d%%)" % [DB.skill(skill).get("name", skill), dc, s.display_name, Rules.signed(total), chance]}


func _attempts(oid: String, who: String) -> int:
	return int(DB.dict(DB.dict(st(), "attempts"), oid).get(who, 0))


func record_attempt(oid: String, who: String) -> void:
	var s := st()
	if not s.has("attempts"):
		s["attempts"] = {}
	if not s["attempts"].has(oid):
		s["attempts"][oid] = {}
	s["attempts"][oid][who] = int(s["attempts"][oid].get(who, 0)) + 1


func mark_done(oid: String) -> void:
	var s := st()
	if not s.has("done"):
		s["done"] = {}
	s["done"][oid] = true


func remaining_loot() -> Dictionary:
	var s := st()
	if s.has("loot_left"):
		return s["loot_left"]
	var l: Dictionary = (def.get("loot", {}) as Dictionary).duplicate()
	s["loot_left"] = l
	return l
