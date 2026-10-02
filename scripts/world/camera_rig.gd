class_name CameraRig
extends Node3D
## Third-person orbit camera: right/middle-drag to orbit, wheel to zoom, Q/T to
## rotate. A SpringArm3D keeps the camera out of walls. Works while the
## simulation is paused. Also frames dialogue shots (cinematic mode).

var target: Node3D
var yaw := 0.0
var pitch := -38.0
var distance := 8.5
var min_dist := 3.0
var max_dist := 18.0
var arm: SpringArm3D
var cam: Camera3D
var cine_cam: Camera3D
var dragging := false
var cinematic := false
var _cine_from: Transform3D
var _cine_to: Transform3D
var _cine_t := 1.0
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
	_apply()


func snap() -> void:
	if target:
		_focus = target.global_position + Vector3(0, 1.3, 0)
		global_position = _focus


func _apply() -> void:
	rotation_degrees = Vector3(0, yaw, 0)
	arm.rotation_degrees = Vector3(pitch, 0, 0)
	arm.spring_length = distance


func orbit(dx: float, dy: float) -> void:
	var sens := float(Settings.get_v("mouse_sensitivity"))
	var inv := -1.0 if bool(Settings.get_v("invert_y")) else 1.0
	yaw -= dx * 0.25 * sens
	pitch = clampf(pitch - dy * 0.2 * sens * inv, -80.0, -8.0)
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
		_cine_t = minf(1.0, _cine_t + delta * 1.8)
		var tt := smoothstep(0.0, 1.0, _cine_t)
		cine_cam.global_transform = _cine_from.interpolate_with(_cine_to, tt)
		return
	if target and is_instance_valid(target):
		var want := target.global_position + Vector3(0, 1.3, 0)
		_focus = _focus.lerp(want, clampf(delta * 8.0, 0.0, 1.0))
		global_position = _focus
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
		_apply()
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 2.5)
		cam.h_offset = randf_range(-1, 1) * shake * 0.15
		cam.v_offset = randf_range(-1, 1) * shake * 0.15
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0


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
## `speaker`'s face.
func frame(speaker_pos: Vector3, listener_pos: Vector3) -> void:
	if not cinematic:
		_cine_from = cam.global_transform
	else:
		_cine_from = cine_cam.global_transform
	cinematic = true
	cine_cam.current = true
	var head := speaker_pos + Vector3(0, 1.55, 0)
	var dir := (speaker_pos - listener_pos)
	dir.y = 0
	if dir.length() < 0.2:
		dir = Vector3(0, 0, 1)
	dir = dir.normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	var eye := listener_pos - dir * 1.4 + side * 0.75 + Vector3(0, 1.75, 0)
	var t := Transform3D(Basis(), eye)
	_cine_to = t.looking_at(head, Vector3.UP)
	_cine_t = 0.0


func end_cinematic() -> void:
	cinematic = false
	cam.current = true
	_apply()


func active_camera() -> Camera3D:
	return cine_cam if cinematic else cam


func screen_ray(mouse: Vector2) -> Array[Vector3]:
	var c := active_camera()
	return [c.project_ray_origin(mouse), c.project_ray_normal(mouse)]
