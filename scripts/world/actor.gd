class_name Actor
extends Node3D
## A character in the world: party member, NPC or enemy. Holds a reference to
## its authoritative CharacterSheet and simulation-side state (path, facing,
## action queue, round clock, stealth). All updates happen in sim_step(),
## which the World calls only while the simulation runs (paused = frozen).

const RADIUS := 0.32

var uid: String = ""
var sheet: CharacterSheet
var role: String = "party"      # party | enemy | npc
var npc_id: String = ""
var encounter_id: String = ""
var world: World = null
var visual: ActorVisual
var label: Label3D

var queue := ActionQueue.new()
var path := PackedVector3Array()
var path_i := 0
var facing := Vector2(0, 1)
var speed_now := 0.0
var manual_move := false
var follow_offset := Vector3.ZERO

# combat scheduling
var recovery := 0.0
var round_clock := 0.0
var current: Dictionary = {}
var target_uid: String = ""
var approach_repath := 0.0
var in_combat := false

# AI and awareness
var alert := false
var hostile_override := ""
var home := Vector3.ZERO
var suspicion: Dictionary = {}
var detect_clock := 0.0
var lost_track := 0.0
var stealth := false
var still_time := 0.0
var last_pos := Vector3.ZERO
var stationary := false
var flee_from := Vector3.ZERO
var interaction: Dictionary = {}
var anim_lock := 0.0


func setup(s: CharacterSheet, r: String, w: World) -> void:
	sheet = s
	uid = s.uid
	role = r
	world = w
	name = "Actor_" + uid
	visual = ActorVisual.new()
	add_child(visual)
	var model := String(s.appearance.get("model", "humanoid"))
	visual.build(model, s.appearance, s)
	visual.idle_phase = float(absi(hash(uid)) % 628) / 100.0
	stationary = bool(s.overrides.get("stationary", false))
	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 28
	label.outline_size = 8
	label.pixel_size = 0.006
	label.position = Vector3(0, 1.4 if model == "spider" else 2.55, 0)
	label.modulate = Color(1, 1, 1, 0.9)
	label.visible = false
	add_child(label)
	last_pos = position


func pos2() -> Vector2:
	return Vector2(position.x, position.z)


func set_pos(p: Vector3) -> void:
	position = Vector3(p.x, 0, p.z)
	last_pos = position


func face_towards(p: Vector3) -> void:
	var d := Vector2(p.x - position.x, p.z - position.z)
	if d.length_squared() > 0.0001:
		facing = d.normalized()
		rotation.y = atan2(facing.x, facing.y)


func set_facing_deg(deg: float) -> void:
	rotation_degrees.y = deg
	facing = Vector2(sin(rotation.y), cos(rotation.y))


func move_to(p: Vector3, manual: bool = false) -> bool:
	if not sheet.can_move():
		return false
	var grid: ShipGrid = world.grid
	var doors_block := role == "enemy" or (role == "party" and world.combat.active and uid != Game.state.controlled)
	var pth := grid.path(position, p, true, doors_block)
	if pth.is_empty():
		return false
	path = pth
	path_i = 0
	manual_move = manual
	return true


func stop() -> void:
	path = PackedVector3Array()
	path_i = 0
	manual_move = false


func is_moving() -> bool:
	return path_i < path.size()


func destination() -> Vector3:
	return path[path.size() - 1] if not path.is_empty() else position


## Keyboard (WASD) movement wanted this frame, in world space. The World sets
## it from input every physics frame; sim_step() applies it at the fixed
## simulation rate, so keyboard movement freezes with the pause, runs at the
## same speed as click-movement and drives the walk animation the same way.
var input_dir := Vector3.ZERO
## Last direct push direction and its sim time, so doors open for a player
## walking into them.
var push_dir := Vector3.ZERO
var push_time := -10.0


func direct_move(dir: Vector3, dt: float) -> void:
	if not sheet.can_move() or dir.length_squared() < 0.0001:
		return
	stop()
	push_dir = dir.normalized()
	push_time = Game.state.sim_time if Game.state != null else 0.0
	var sp := move_speed()
	var np: Vector3 = world.grid.try_move(position, dir.normalized() * sp * dt, RADIUS)
	speed_now = position.distance_to(np) / maxf(dt, 0.0001)
	position = np
	face_towards(position + dir)


func move_speed() -> float:
	var s := sheet.speed()
	if stealth:
		s *= 0.6
	if sheet.has_status("feared"):
		s *= 1.1
	return s


func sim_step(dt: float) -> void:
	speed_now = 0.0
	if sheet.dead or sheet.is_downed():
		stop()
		input_dir = Vector3.ZERO
	elif input_dir.length_squared() > 0.0001 and sheet.can_move():
		direct_move(input_dir, dt)  # sets speed_now from the distance covered
	elif is_moving() and sheet.can_move():
		var target := path[path_i]
		var to := Vector3(target.x - position.x, 0, target.z - position.z)
		var dist := to.length()
		var step := move_speed() * dt
		if dist <= step:
			position = Vector3(target.x, 0, target.z)
			path_i += 1
			if path_i >= path.size():
				manual_move = false
		else:
			position += to / dist * step
		if dist > 0.001:
			face_towards(target)
		speed_now = move_speed()
	var moved := position.distance_to(last_pos)
	still_time = 0.0 if moved > 0.02 else still_time + dt
	last_pos = position
	if visual != null:
		visual.crouch = move_toward(visual.crouch, 1.0 if stealth else 0.0, dt * 4.0)
		visual.set_downed(sheet.is_downed() or sheet.dead)
		visual.animate(dt, speed_now)


func show_label(text: String, col: Color) -> void:
	label.text = text
	label.modulate = col
	label.visible = text != ""


func eye_pos() -> Vector3:
	return position + Vector3(0, 1.5, 0)


func is_party() -> bool:
	return role == "party"


func is_enemy() -> bool:
	return role == "enemy"
