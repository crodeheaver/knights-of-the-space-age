class_name SlipstreamSim
extends RefCounted
## Slipstream, the hover-sled racing program in the crew commons sim booth.
## A deterministic simulation with no rendering: the UI feeds step(dt, input)
## at a fixed rate and draws whatever state results, and tests drive the same
## API with scripted input.
##
## The track is a closed loop laid out from a fixed seed (so best times and
## the ghost stay comparable between runs): straights and bends, obstacle rows
## that block one or two of the three lanes, and boost pads. The sled always
## moves forward; throttle raises the speed toward top speed, brake drops it,
## and steering moves it across the track. Bends push the sled outward, so a
## good line steers into them. Hitting an obstacle costs speed, never the race.
##
## Coordinates: d is distance along the track in metres (laps * LAP_LENGTH at
## the finish), x is the lateral offset from the centreline (-HALF_WIDTH..).

const TRACK_SEED := 7741
const LAP_LENGTH := 1100.0
const LAPS := 3
const HALF_WIDTH := 6.0
const LANE_X: Array[float] = [-4.0, 0.0, 4.0]
const SLED_HALF := 0.8
const OBSTACLE_HALF := 1.5
const PAD_HALF := 1.7
const CRUISE := 38.0
const MAX_SPEED := 62.0
const BOOST_SPEED := 84.0
const MIN_SPEED := 12.0
const ACCEL := 14.0
const BOOST_ACCEL := 40.0
const BRAKE := 32.0
const DRAG := 7.0
const STEER_SPEED := 10.0
const STEER_ACCEL := 45.0
## Outward push in a bend: curvature * speed^2 * DRIFT (m/s sideways).
const DRIFT := 0.0016
const HIT_KEEP := 0.45
const HIT_STUN := 0.6
const BOOST_TIME := 1.6
const WALL_DRAG := 0.9
## Assisted driving: top speeds scale by this and the sled steers itself.
const ASSIST_SPEED := 0.8
const GHOST_DT := 0.25
## Safety valve: a run longer than this ends (recorded as a slow finish).
const TIME_CAP := 600.0

var assisted := false
var d := 0.0
var x := 0.0
var vx := 0.0
var speed := CRUISE
var time := 0.0
var finished := false
var finish_time := 0.0
var boost_t := 0.0
var stun_t := 0.0
var hits := 0
var boosts := 0
var scraping := false
## Effects for the presentation layer since the last drain: {"type": ...}.
var events: Array[Dictionary] = []
## Ghost samples [d0, x0, d1, x1, ...] every GHOST_DT seconds.
var ghost: Array[float] = []
var _ghost_acc := 0.0

## Layout of one lap (repeated for every lap).
var bends: Array[Dictionary] = []      # {"d": start, "len": metres, "c": curvature -1..1}
var obstacles: Array[Dictionary] = []  # {"d", "lane", "kind"}
var pads: Array[Dictionary] = []       # {"d", "lane"}


func _init(assist: bool = false, track_seed: int = TRACK_SEED) -> void:
	assisted = assist
	speed = CRUISE * _k()
	_build_track(track_seed)
	_sample_ghost()


func _k() -> float:
	return ASSIST_SPEED if assisted else 1.0


# ------------------------------------------------------------ track
func _build_track(track_seed: int) -> void:
	var dice := Dice.new(track_seed)
	bends.clear()
	obstacles.clear()
	pads.clear()
	var at := 90.0
	var flip := 1.0 if dice.randf() < 0.5 else -1.0
	while at < LAP_LENGTH - 120.0:
		at += 50.0 + dice.randf() * 90.0
		var ln := 90.0 + dice.randf() * 110.0
		if at + ln > LAP_LENGTH - 40.0:
			break
		flip = -flip if dice.randf() < 0.75 else flip
		bends.append({"d": at, "len": ln, "c": flip * (0.45 + dice.randf() * 0.55)})
		at += ln
	# Obstacle rows. A row blocking two lanes always leaves a lane within one
	# step of a lane that was free in the previous row, so a clean line exists.
	var row_d := 150.0
	var prev_free: Array[int] = [0, 1, 2]
	var row := 0
	while row_d < LAP_LENGTH - 50.0:
		var blocked: Array[int] = []
		if dice.randf() < 0.42:
			var anchor: int = prev_free[dice.randi_range(0, prev_free.size() - 1)]
			var free_lane := clampi(anchor + dice.randi_range(-1, 1), 0, 2)
			for l in 3:
				if l != free_lane:
					blocked.append(l)
		else:
			blocked.append(dice.randi_range(0, 2))
		var kind := "pylon" if dice.randf() < 0.6 else "debris"
		for l in blocked:
			obstacles.append({"d": row_d, "lane": l, "kind": kind})
		var free: Array[int] = []
		for l in 3:
			if not blocked.has(l):
				free.append(l)
		prev_free = free
		var gap := 48.0 + dice.randf() * 40.0
		# Every third gap carries a boost pad in a lane this row left open, a
		# reward for reading the track rather than a trap.
		if row % 3 == 1:
			pads.append({"d": row_d + gap * 0.5, "lane": free[dice.randi_range(0, free.size() - 1)]})
		row_d += gap
		row += 1


## Curvature at track distance dd (eased in and out over 25 m).
func curve_at(dd: float) -> float:
	var ld := fposmod(dd, LAP_LENGTH)
	for b in bends:
		var b0 := float(b["d"])
		var bl := float(b["len"])
		if ld >= b0 and ld < b0 + bl:
			var e := minf(1.0, minf(ld - b0, b0 + bl - ld) / 25.0)
			return float(b["c"]) * smoothstep(0.0, 1.0, e)
	return 0.0


func total_length() -> float:
	return LAP_LENGTH * LAPS


func lap() -> int:
	return mini(LAPS, int(d / LAP_LENGTH) + 1)


func progress() -> float:
	return clampf(d / total_length(), 0.0, 1.0)


## True when world distance `od + k * LAP_LENGTH` for some lap k lies in (d0, d1].
func _crossed(od: float, d0: float, d1: float) -> bool:
	var k0 := int(floor(d0 / LAP_LENGTH))
	var k1 := int(floor(d1 / LAP_LENGTH))
	for k in range(k0, k1 + 1):
		if k >= LAPS:
			break
		var wd := od + k * LAP_LENGTH
		if wd > d0 and wd <= d1:
			return true
	return false


# ------------------------------------------------------------ simulation
## input: {"accel": bool, "brake": bool, "steer": -1..1}. Missing keys = idle.
func step(dt: float, input: Dictionary = {}) -> void:
	if finished or dt <= 0.0:
		return
	time += dt
	var accel := bool(input.get("accel", false))
	var brake := bool(input.get("brake", false))
	var steer := clampf(float(input.get("steer", 0.0)), -1.0, 1.0)
	if assisted and absf(steer) < 0.05:
		steer = auto_steer()
		# Assisted driving also eases off for a row it cannot clear cleanly.
		if not brake and _blocked_ahead(speed * 0.6):
			brake = true
	var k := _k()
	var target := CRUISE * k
	if accel:
		target = MAX_SPEED * k
	if brake:
		target = MIN_SPEED
	var boosting := boost_t > 0.0
	if boosting:
		boost_t -= dt
		target = maxf(target, BOOST_SPEED * k)
	if stun_t > 0.0:
		stun_t -= dt
	if speed < target:
		speed = minf(target, speed + (BOOST_ACCEL if boosting else ACCEL) * dt)
	else:
		speed = maxf(target, speed - (BRAKE if brake else DRAG) * dt)
	var want_vx := steer * STEER_SPEED * (0.4 if stun_t > 0.0 else 1.0)
	vx = move_toward(vx, want_vx, STEER_ACCEL * dt)
	x += (vx + drift()) * dt
	var lim := HALF_WIDTH - SLED_HALF
	scraping = absf(x) > lim
	if scraping:
		x = clampf(x, -lim, lim)
		vx = 0.0
		speed *= 1.0 - WALL_DRAG * dt
		if events.is_empty() or String(events[events.size() - 1].get("type", "")) != "scrape":
			events.append({"type": "scrape"})
	var d0 := d
	d += speed * dt
	for o in obstacles:
		if _crossed(float(o["d"]), d0, d) and absf(x - LANE_X[int(o["lane"])]) < OBSTACLE_HALF + SLED_HALF:
			speed *= HIT_KEEP
			stun_t = HIT_STUN
			boost_t = 0.0
			hits += 1
			events.append({"type": "hit", "kind": String(o["kind"])})
	for p in pads:
		if _crossed(float(p["d"]), d0, d) and absf(x - LANE_X[int(p["lane"])]) < PAD_HALF:
			boost_t = BOOST_TIME
			boosts += 1
			events.append({"type": "boost"})
	if int(d0 / LAP_LENGTH) != int(d / LAP_LENGTH) and d < total_length():
		events.append({"type": "lap", "lap": lap()})
	_ghost_acc += dt
	while _ghost_acc >= GHOST_DT:
		_ghost_acc -= GHOST_DT
		_sample_ghost()
	if d >= total_length():
		# Interpolate the crossing inside this step for a fair time.
		var over := (d - total_length()) / maxf(speed, 0.001)
		finish_time = maxf(0.0, time - over)
		finished = true
		_sample_ghost()
		events.append({"type": "finish", "time": finish_time})
	elif time >= TIME_CAP:
		finish_time = time
		finished = true
		events.append({"type": "finish", "time": finish_time})


## Sideways push from the current bend (outward, i.e. against the bend).
func drift() -> float:
	return -curve_at(d) * speed * speed * DRIFT


func _sample_ghost() -> void:
	ghost.append(snappedf(d, 0.01))
	ghost.append(snappedf(x, 0.01))


func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = events.duplicate()
	events.clear()
	return out


## Next obstacle rows ahead within `look` metres: [{"d": world d, "blocked": [lanes]}].
func rows_ahead(look: float) -> Array[Dictionary]:
	var rows: Dictionary = {}
	var lap0 := int(d / LAP_LENGTH)
	for o in obstacles:
		for k in range(lap0, mini(lap0 + 2, LAPS)):
			var wd := float(o["d"]) + k * LAP_LENGTH
			if wd > d and wd - d <= look:
				if not rows.has(wd):
					rows[wd] = []
				(rows[wd] as Array).append(int(o["lane"]))
	var out: Array[Dictionary] = []
	var keys := rows.keys()
	keys.sort()
	for wd in keys:
		out.append({"d": float(wd), "blocked": rows[wd]})
	return out


## Lane the sled is closest to.
func lane_of(px: float) -> int:
	var best := 0
	for l in 3:
		if absf(px - LANE_X[l]) < absf(px - LANE_X[best]):
			best = l
	return best


## Steering that follows a clean line: the free lane of the next obstacle row
## nearest to the sled (preferring one also free in the row after), otherwise
## the lane of an upcoming boost pad, compensating for bend drift. Used by
## Assisted mode and by tests as "perfect" input.
func auto_steer() -> float:
	var look := maxf(70.0, speed * 1.6)
	var rows := rows_ahead(look * 1.8)
	var target_x := x
	if not rows.is_empty():
		var first: Array = rows[0]["blocked"]
		var second: Array = rows[1]["blocked"] if rows.size() > 1 else []
		var best_l := -1
		var best_cost := INF
		for l in 3:
			if first.has(l):
				continue
			var cost := absf(LANE_X[l] - x)
			if second.has(l):
				cost += 3.0
			if cost < best_cost:
				best_cost = cost
				best_l = l
		if best_l >= 0:
			target_x = LANE_X[best_l]
		if float(rows[0]["d"]) - d > look:
			target_x = _pad_lane_x(look, target_x)
	else:
		target_x = _pad_lane_x(look, LANE_X[lane_of(x)])
	var want := clampf((target_x - x) * 3.0, -STEER_SPEED, STEER_SPEED)
	return clampf((want - drift()) / STEER_SPEED, -1.0, 1.0)


func _pad_lane_x(look: float, fallback: float) -> float:
	var lap0 := int(d / LAP_LENGTH)
	for p in pads:
		for k in range(lap0, mini(lap0 + 2, LAPS)):
			var wd := float(p["d"]) + k * LAP_LENGTH
			if wd > d and wd - d <= look:
				return LANE_X[int(p["lane"])]
	return fallback


## True when the sled's current x would hit the next row within `look` metres.
func _blocked_ahead(look: float) -> bool:
	var rows := rows_ahead(look)
	if rows.is_empty():
		return false
	for l in rows[0]["blocked"]:
		if absf(x - LANE_X[int(l)]) < OBSTACLE_HALF + SLED_HALF:
			return true
	return false


## Ghost position at time t from a recorded sample array: Vector2(d, x), or
## Vector2(-1, 0) when there is no ghost.
static func ghost_at(samples: Array, t: float) -> Vector2:
	var n := samples.size() >> 1
	if n < 1:
		return Vector2(-1, 0)
	var f := t / GHOST_DT
	var i := int(floor(f))
	if i >= n - 1:
		return Vector2(float(samples[(n - 1) * 2]), float(samples[(n - 1) * 2 + 1]))
	var a := Vector2(float(samples[i * 2]), float(samples[i * 2 + 1]))
	var b := Vector2(float(samples[(i + 1) * 2]), float(samples[(i + 1) * 2 + 1]))
	return a.lerp(b, f - i)
