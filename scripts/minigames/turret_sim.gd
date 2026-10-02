class_name TurretSim
extends RefCounted
## The Petrel's dorsal turret during the escape from the Cinder Wake. A
## deterministic simulation in a virtual 1600 x 900 field: WARDEN interceptor
## drones swoop in from the edges, weave across the starfield and make attack
## runs (when they come close, z > ATTACK_Z) that chip at the hull. The gunner
## moves a reticle and fires a hitscan cannon. Win: every interceptor
## destroyed. Loss: the hull falls to HULL_FAIL (Brann has to break off) or
## the time limit runs out.
##
## Assisted targeting runs the whole fight in slow motion (the gun and the
## reticle keep real-time speed) and pulls shots onto the nearest drone, for
## players who prefer less reflex-heavy play. autopilot() resolves the fight
## with a single seeded skill roll instead.

const W := 1600.0
const H := 900.0
const HULL_MAX := 100.0
const HULL_FAIL := 25.0
const FIRE_INTERVAL := 0.11
const SHOT_SLOP := 10.0
const RETICLE_SPEED := 950.0
const ATTACK_Z := 0.74
const ENTRY_TIME := 1.6
const ASSIST_SLOWMO := 0.5
const ASSIST_RADIUS := 190.0
const ASSIST_PULL := 520.0
const AUTOPILOT_DC := 12

## Per-difficulty tuning. count: interceptors; hp: hits to destroy one;
## dmg: hull lost per enemy shot; fire: seconds between enemy shots during an
## attack run; speed: path speed multiplier; limit: seconds to win in.
const TUNING := {
	"story": {"count": 2, "hp": 5, "dmg": 2.5, "fire": 0.75, "speed": 0.8, "limit": 100.0},
	"standard": {"count": 2, "hp": 7, "dmg": 4.0, "fire": 0.6, "speed": 1.0, "limit": 75.0},
	"hard": {"count": 3, "hp": 8, "dmg": 4.5, "fire": 0.55, "speed": 1.15, "limit": 70.0},
}


## One interceptor. Its path is a sum of sines (deterministic from the seed),
## eased in from an off-screen spawn point.
class Drone:
	extends RefCounted
	var pos := Vector2.ZERO
	var spawn := Vector2.ZERO
	var hp := 1
	var max_hp := 1
	var alive := true
	var z := 0.4
	var t := 0.0
	var delay := 0.0
	var amp := Vector2(520, 230)
	var freq := Vector3(0.7, 1.1, 0.55)
	var phase := Vector3.ZERO
	var center := Vector2(800, 380)
	var fire_cd := 0.0
	var flash := 0.0

	func path(tt: float) -> Vector2:
		return center + Vector2(amp.x * sin(freq.x * tt + phase.x), amp.y * sin(freq.y * tt + phase.y))

	func depth(tt: float) -> float:
		return clampf(0.48 + 0.44 * sin(freq.z * tt + phase.z), 0.12, 1.0)

	func radius() -> float:
		return 22.0 + 40.0 * z

	func attacking() -> bool:
		return alive and t > delay + TurretSim.ENTRY_TIME and z > TurretSim.ATTACK_Z


var drones: Array[Drone] = []
var reticle := Vector2(W / 2.0, H / 2.0)
var hull := HULL_MAX
var time := 0.0
var time_limit := 75.0
var result := ""
var reason := ""
var shots := 0
var hits := 0
var kills := 0
var assisted := false
var difficulty := "standard"
var events: Array[Dictionary] = []
var _gun_cd := 0.0
var _tune: Dictionary = {}


## extra_drones: added on top of the difficulty count (the practice drill
## flies one more). Count is kept within 2..4.
func _init(seed_: int = 1, diff: String = "standard", assist: bool = false, extra_drones: int = 0) -> void:
	difficulty = difficulty_key(diff)
	assisted = assist
	_tune = TUNING[difficulty]
	time_limit = float(_tune["limit"])
	var dice := Dice.new(seed_)
	var count := clampi(int(_tune["count"]) + extra_drones, 2, 4)
	var spd := float(_tune["speed"])
	for i in count:
		var dr := Drone.new()
		dr.max_hp = int(_tune["hp"])
		dr.hp = dr.max_hp
		dr.delay = i * 1.3
		dr.amp = Vector2(430.0 + dice.randf() * 200.0, 170.0 + dice.randf() * 110.0)
		dr.freq = Vector3((0.55 + dice.randf() * 0.35) * spd, (0.8 + dice.randf() * 0.5) * spd, (0.45 + dice.randf() * 0.25) * spd)
		dr.phase = Vector3(dice.randf() * TAU, dice.randf() * TAU, dice.randf() * TAU)
		dr.center = Vector2(W / 2.0 + (dice.randf() - 0.5) * 160.0, H * 0.4 + (dice.randf() - 0.5) * 80.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		dr.spawn = Vector2(W / 2.0 + side * (W * 0.7), -120.0 + dice.randf() * 200.0)
		dr.pos = dr.spawn
		dr.z = 0.2
		dr.fire_cd = float(_tune["fire"]) * (0.5 + dice.randf())
		drones.append(dr)


func alive_count() -> int:
	var n := 0
	for dr in drones:
		if dr.alive:
			n += 1
	return n


func time_left() -> float:
	return maxf(0.0, time_limit - time)


## input: {"aim": Vector2 (absolute, field units), "move": Vector2 (-1..1),
## "fire": bool}. Missing keys = no input.
func step(dt: float, input: Dictionary = {}) -> void:
	if result != "" or dt <= 0.0:
		return
	var sdt := dt * (ASSIST_SLOWMO if assisted else 1.0)
	time += sdt
	if input.has("aim"):
		reticle = input["aim"]
	var mv: Vector2 = input.get("move", Vector2.ZERO)
	reticle += mv.limit_length(1.0) * RETICLE_SPEED * dt
	if assisted:
		var near := _nearest(reticle, ASSIST_RADIUS)
		if near != null:
			reticle = reticle.move_toward(near.pos, ASSIST_PULL * dt)
	reticle = reticle.clamp(Vector2.ZERO, Vector2(W, H))
	for dr in drones:
		if dr.alive:
			_step_drone(dr, sdt)
	_gun_cd -= dt
	if bool(input.get("fire", false)) and _gun_cd <= 0.0:
		_gun_cd = FIRE_INTERVAL
		_fire()
	if alive_count() == 0:
		result = "player_win"
		reason = "destroyed"
	elif hull <= HULL_FAIL:
		result = "player_loss"
		reason = "hull"
	elif time >= time_limit:
		result = "player_loss"
		reason = "time"
	if result != "":
		events.append({"type": "end", "result": result, "reason": reason})


func _step_drone(dr: Drone, sdt: float) -> void:
	dr.t += sdt
	dr.flash = maxf(0.0, dr.flash - sdt)
	if dr.t < dr.delay:
		return
	var tt := dr.t - dr.delay
	var e := clampf(tt / ENTRY_TIME, 0.0, 1.0)
	var ease_e := e * e * (3.0 - 2.0 * e)
	dr.pos = dr.spawn.lerp(dr.path(tt), ease_e)
	dr.z = lerpf(0.2, dr.depth(tt), ease_e)
	if dr.attacking():
		dr.fire_cd -= sdt
		if dr.fire_cd <= 0.0:
			dr.fire_cd = float(_tune["fire"])
			hull = maxf(0.0, hull - float(_tune["dmg"]))
			events.append({"type": "hull_hit", "from": dr.pos, "hull": hull})


func _nearest(p: Vector2, within: float) -> Drone:
	var best: Drone = null
	var bd := within
	for dr in drones:
		if not dr.alive or dr.t < dr.delay:
			continue
		var dd := dr.pos.distance_to(p) - dr.radius()
		if dd < bd:
			bd = dd
			best = dr
	return best


func _fire() -> void:
	shots += 1
	var tgt: Drone = null
	for dr in drones:
		if dr.alive and dr.t >= dr.delay and dr.pos.distance_to(reticle) <= dr.radius() * 0.8 + SHOT_SLOP:
			tgt = dr
			break
	if tgt == null and assisted:
		# Auto-aim: a shot near a drone is pulled onto it.
		tgt = _nearest(reticle, ASSIST_RADIUS * 0.6)
	events.append({"type": "shot", "at": tgt.pos if tgt != null else reticle, "hit": tgt != null})
	if tgt == null:
		return
	hits += 1
	tgt.hp -= 1
	tgt.flash = 0.08
	if tgt.hp <= 0:
		tgt.alive = false
		kills += 1
		events.append({"type": "kill", "at": tgt.pos, "z": tgt.z})


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events.duplicate()
	events.clear()
	return out


## The best target for scripted "perfect aim": the first live drone on screen.
func aim_hint() -> Vector2:
	for dr in drones:
		if dr.alive and dr.t >= dr.delay + ENTRY_TIME * 0.5:
			return dr.pos
	return reticle


## Hands the turret to the Petrel's autopilot: one roll of d20 + the party's
## best Awareness against AUTOPILOT_DC (+/- 2 by difficulty), using the given
## seeded dice. st may have no characters (main-menu practice): then the roll
## is a plain d20. Returns {"result", "natural", "bonus", "total", "dc", "who"}.
static func autopilot(st: GameState, dice: Dice, diff: String = "standard") -> Dictionary:
	var dc := AUTOPILOT_DC + (-2 if diff == "story" else (0 if diff == "standard" else 2))
	var best: CharacterSheet = null
	if st != null:
		for uid in st.party:
			var s := st.get_char(uid)
			if s == null or s.dead:
				continue
			if best == null or s.skill_total("awareness") > best.skill_total("awareness"):
				best = s
	var out := {}
	if best != null:
		var r := CombatRules.skill_check(best, "awareness", dc, dice)
		out = {"natural": int(r["natural"]), "bonus": int(r["bonus"]), "total": int(r["total"]), "dc": dc, "who": best.display_name, "success": bool(r["success"])}
	else:
		var nat := dice.d20()
		out = {"natural": nat, "bonus": 0, "total": nat, "dc": dc, "who": "", "success": nat >= dc}
	out["result"] = "player_win" if bool(out["success"]) else "player_loss"
	return out


## Difficulty key for TUNING from a settings value.
static func difficulty_key(diff: String) -> String:
	if diff == "story" or diff == "standard":
		return diff
	return "hard" if diff != "" else "standard"
