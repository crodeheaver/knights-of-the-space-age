class_name CameraRig
extends Node3D
## Third-person camera in two modes (Settings → Controls → Camera):
## * follow (default): low behind the leader, swinging round behind them as
##   they walk forward or follow a click path, like the classic d20 space
##   RPGs. Strafing or backing up never swings it, and orbiting by hand
##   holds it for a moment.
## * tactical: the high free orbit for reading a fight.
## Right/middle-drag orbits, the wheel zooms, Q/T rotate. A SpringArm3D keeps
## the camera out of walls (and, following, out of tall props). Works while
## the simulation is paused. Also frames dialogue shots (cinematic mode).

const PROFILES := {
	"follow": {"pitch": -17.0, "distance": 5.0, "fov": 62.0, "min": 2.2, "max": 9.0, "pmin": -50.0, "pmax": -4.0, "focus": 1.55, "mask": 3},
	"tactical": {"pitch": -38.0, "distance": 8.5, "fov": 55.0, "min": 3.0, "max": 18.0, "pmin": -80.0, "pmax": -8.0, "focus": 1.3, "mask": 1},
}

var target: Node3D
var mode := "tactical"
var yaw := 0.0
var pitch := -38.0
var distance := 8.5
var min_dist := 3.0
var max_dist := 18.0
var focus_h := 1.3
var _pmin := -80.0
var _pmax := -8.0
var _manual_hold := 0.0
var _move_t := 0.0
var arm: SpringArm3D
var cam: Camera3D
var cine_cam: Camera3D
var dragging := false
var cinematic := false
## A Cinematics script drives cine_cam directly; the rig keeps its hands off.
var scripted := false
var _cine_from: Transform3D
var _cine_to: Transform3D
var _cine_t := 1.0
var _cine_speed := 1.8
## Slow push-in after each conversation cut (metres per second, capped).
var _drift := Vector3.ZERO
var _drift_left := 0.0
var shake := 0.0
var _focus := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	var sh := SphereShape3D.new()
	sh.radius = 0.3
	arm.shape = sh
	arm.margin = 0.2
	add_child(arm)
	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.1
	cam.far = 200.0
	arm.add_child(cam)
	cam.current = true
	cine_cam = Camera3D.new()
	cine_cam.fov = 45.0
	cine_cam.top_level = true
	add_child(cine_cam)
	set_mode(String(Settings.get_v("camera_mode")), true)
	Settings.changed.connect(_on_setting)
	_apply()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting):
		Settings.changed.disconnect(_on_setting)


func _on_setting(key: String) -> void:
	if key == "camera_mode":
		set_mode(String(Settings.get_v("camera_mode")), true)


## Switches between "follow" and "tactical". `reset` puts pitch and
## distance at the mode's defaults (and swings behind the leader).
func set_mode(m: String, reset: bool = false) -> void:
	if not PROFILES.has(m):
		m = "follow"
	mode = m
	var pr: Dictionary = PROFILES[m]
	cam.fov = float(pr["fov"])
	min_dist = float(pr["min"])
	max_dist = float(pr["max"])
	_pmin = float(pr["pmin"])
	_pmax = float(pr["pmax"])
	focus_h = float(pr["focus"])
	arm.collision_mask = int(pr["mask"])
	if reset:
		pitch = float(pr["pitch"])
		distance = float(pr["distance"])
		if m == "follow":
			face_behind()
	pitch = clampf(pitch, _pmin, _pmax)
	distance = clampf(distance, min_dist, max_dist)
	_apply()


## Turns the camera to look the way the target faces.
func face_behind() -> void:
	var a := target as Actor
	if a != null and is_instance_valid(a):
		yaw = rad_to_deg(atan2(a.facing.x, a.facing.y)) + 180.0
		_apply()


func snap() -> void:
	if target:
		_focus = target.global_position + Vector3(0, focus_h, 0)
		global_position = _focus


func _apply() -> void:
	rotation_degrees = Vector3(0, yaw, 0)
	arm.rotation_degrees = Vector3(pitch, 0, 0)
	arm.spring_length = distance


func orbit(dx: float, dy: float) -> void:
	var sens := float(Settings.get_v("mouse_sensitivity"))
	var inv := -1.0 if bool(Settings.get_v("invert_y")) else 1.0
	yaw -= dx * 0.25 * sens
	pitch = clampf(pitch - dy * 0.2 * sens * inv, _pmin, _pmax)
	_manual_hold = 1.5
	_apply()


func zoom(dz: float) -> void:
	distance = clampf(distance + dz, min_dist, max_dist)
	_apply()


func add_shake(amount: float) -> void:
	if bool(Settings.get_v("reduce_shake")):
		return
	shake = maxf(shake, amount)


func _process(delta: float) -> void:
	if cinematic:
		if scripted:
			return
		_cine_t = minf(1.0, _cine_t + delta * _cine_speed)
		var tt := smoothstep(0.0, 1.0, _cine_t)
		cine_cam.global_transform = _cine_from.interpolate_with(_cine_to, tt)
		if _cine_t >= 1.0 and _drift_left > 0.0:
			var step := minf(_drift_left, delta * _drift.length())
			_drift_left -= step
			_cine_to.origin += _drift.normalized() * step
		return
	if target and is_instance_valid(target):
		var want := target.global_position + Vector3(0, focus_h, 0)
		_focus = _focus.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
		global_position = _focus
	_follow_swing(delta)
	var rot := 0.0
	if Input.is_action_pressed("camera_left"):
		rot += 1.0
	if Input.is_action_pressed("camera_right"):
		rot -= 1.0
	if bool(Settings.get_v("edge_pan")) and DisplayServer.window_is_focused():
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x <= 6.0 and mp.y > 0.0:
			rot += 1.0
		elif mp.x >= vs.x - 6.0 and mp.y < vs.y:
			rot -= 1.0
	if rot != 0.0 and not Game.ui_blocked():
		yaw += rot * 90.0 * delta
		_manual_hold = 1.5
		_apply()
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.5)
		cam.h_offset = randf_range(-1, 1) * shake * 0.15
		cam.v_offset = randf_range(-1, 1) * shake * 0.15
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


## Follow mode: ease round behind the leader while they walk forward (W) or
## along a click path. Never on strafe or backing up (no circling), and not
## for a moment after the player orbits by hand.
func _follow_swing(delta: float) -> void:
	_manual_hold = maxf(0.0, _manual_hold - delta)
	if mode != "follow" or dragging or _manual_hold > 0.0 or not bool(Settings.get_v("camera_swing")):
		_move_t = 0.0
		return
	var a := target as Actor
	var w := Game.world as World
	if a == null or not is_instance_valid(a) or w == null or not w.sim_running():
		return
	var fwd := Input.is_action_pressed("move_forward") and not Input.is_action_pressed("move_back")
	var keys := fwd or Input.is_action_pressed("move_back") or Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right")
	var moving := a.speed_now > 0.5 and (fwd or (a.is_moving() and not keys))
	_move_t = _move_t + delta if moving else 0.0
	if _move_t < 0.2:
		return
	var want := rad_to_deg(atan2(a.facing.x, a.facing.y)) + 180.0
	var d := wrapf(want - yaw, -180.0, 180.0)
	var rate := 110.0 * clampf(absf(d) / 60.0, 0.25, 1.0)
	if not fwd and absf(d) > 150.0:
		rate = 40.0  # walking back towards the camera: turn slowly
	yaw += signf(d) * minf(absf(d), rate * delta)
	pitch = move_toward(pitch, float(PROFILES["follow"]["pitch"]), 8.0 * delta) if pitch > -30.0 else pitch
	_apply()


func handle_input(event: InputEvent) -> bool:
	if cinematic:
		return false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = mb.pressed
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(-0.8)
			return true
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(0.8)
			return true
	elif event is InputEventMouseMotion and dragging:
		var mm := event as InputEventMouseMotion
		orbit(mm.relative.x, mm.relative.y)
		return true
	return false


## Planar forward/right vectors for WASD relative to the camera.
func basis_flat() -> Array[Vector3]:
	var f := -global_transform.basis.z
	f.y = 0
	f = f.normalized()
	var r := global_transform.basis.x
	r.y = 0
	r = r.normalized()
	return [f, r]


## Cinematic over-the-shoulder framing: camera behind `listener`, looking at
## `speaker`'s face. (Kept for callers that want the classic shot.)
func frame(speaker_pos: Vector3, listener_pos: Vector3) -> void:
	frame_shot(speaker_pos, listener_pos, "ots", 1.0, true)


## Conversation shots. `side` (+1/-1) keeps the camera on one side of the
## line between the two characters for a whole conversation.
##   ots    over the listener's shoulder onto the speaker's face
##   close  head-and-shoulders on the speaker, from the listener's side
##   two    both characters in profile, from the side of the line
## `blend` eases from the current view (the first shot); later shots cut.
func frame_shot(speaker_pos: Vector3, listener_pos: Vector3, shot: String = "ots", side: float = 1.0, blend: bool = false,
		speaker_h: float = 1.55, listener_h: float = 1.55) -> void:
	if not cinematic:
		_cine_from = cam.global_transform
		blend = true
	else:
		_cine_from = cine_cam.global_transform
	cinematic = true
	cine_cam.current = true
	var head := speaker_pos + Vector3(0, speaker_h, 0)
	var dir := speaker_pos - listener_pos
	dir.y = 0
	if dir.length() < 0.2:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var sidev := Vector3(-dir.z, 0, dir.x) * side
	var eye: Vector3
	var look := head
	match shot:
		"close":
			# Head and shoulders; aimed a little low so the face sits in the
			# upper part of the frame, clear of the subtitles.
			eye = head - dir * 2.1 + sidev * 0.55 + Vector3(0, 0.02, 0)
			look = head - Vector3(0, 0.24, 0)
		"two":
			var mid := (speaker_pos + listener_pos) * 0.5
			var gap := maxf(3.0, speaker_pos.distance_to(listener_pos) * 1.55)
			eye = mid + sidev * gap - dir * 0.4 + Vector3(0, 1.7, 0)
			look = mid + Vector3(0, 1.2, 0)
		_:
			# Behind and beside the listener at shoulder height; the speaker
			# sits a little off-centre, towards the open side of the frame.
			eye = listener_pos - dir * 1.9 + sidev * 1.15 + Vector3(0, listener_h + 0.2, 0)
			look = head - sidev * 0.3 - Vector3(0, 0.18, 0)
	eye = safe_eye(look, eye, sidev)
	var t := Transform3D(Basis(), eye)
	_cine_to = t.looking_at(look, Vector3.UP)
	_cine_t = 0.0 if blend else 1.0
	_cine_speed = 1.8
	if not blend:
		cine_cam.global_transform = _cine_to
	# A slow push-in towards the subject, like a dolly on the cut.
	_drift = (look - eye).normalized() * 0.05
	_drift_left = 0.35


## Pulls a camera position in front of any wall between it and what it looks
## at; if that leaves it too close, tries the mirrored side.
func safe_eye(look: Vector3, eye: Vector3, sidev: Vector3 = Vector3.ZERO) -> Vector3:
	if not is_inside_tree():
		return eye
	var space := get_world_3d().direct_space_state
	if space == null:
		return eye
	var res := _clear_eye(space, look, eye)
	if res.distance_to(look) < 1.0 and sidev != Vector3.ZERO:
		var mirrored := eye - sidev * 2.0 * sidev.dot(eye - look) / maxf(0.0001, sidev.length_squared())
		var alt := _clear_eye(space, look, mirrored)
		if alt.distance_to(look) > res.distance_to(look):
			return alt
	return res


func _clear_eye(space: PhysicsDirectSpaceState3D, look: Vector3, eye: Vector3) -> Vector3:
	var q := PhysicsRayQueryParameters3D.create(look, eye, arm.collision_mask | 1)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return eye
	var hp: Vector3 = hit["position"]
	return hp + (look - hp).normalized() * 0.3


func end_cinematic() -> void:
	cinematic = false
	scripted = false
	_drift_left = 0.0
	cam.current = true
	_apply()


func active_camera() -> Camera3D:
	return cine_cam if cinematic else cam


func screen_ray(mouse: Vector2) -> Array[Vector3]:
	var c := active_camera()
	return [c.project_ray_origin(mouse), c.project_ray_normal(mouse)]
