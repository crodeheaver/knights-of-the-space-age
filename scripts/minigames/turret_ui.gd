class_name TurretPanel
extends MinigamePanel
## The Petrel's dorsal turret during the escape (and the practice drill).
## Briefing with the accessibility options (Assisted targeting, or handing
## the turret to the autopilot for a single seeded skill roll), the fight
## drawn on a Control (starfield, interceptors, reticle, tracers, debris),
## and the result. In the real escape every exit resolves the fight: the
## result goes to the turret_result flag and the launch_after conversation
## continues the story. Practice changes nothing.

const DT := 1.0 / 120.0
const SPACE := Color("#04060c")
const WARDEN_RED := Color("#ff4a3a")
const HULL_COL := Color("#5fd38a")

var sim: TurretSim
var view: Control
var stage := "setup"
var assisted := false
var method := "manual"
var outcome: Dictionary = {}
var _resolved := false
var _acc := 0.0
var _aim := Vector2(-1, -1)
var _aim_moved := false
var _mouse_fire := false
var _stars: Array[Vector3] = []
var _tracers: Array[Dictionary] = []
var _bolts: Array[Dictionary] = []
var _parts: Array[Dictionary] = []
var _flash := 0.0
var _shake := 0.0
var _t := 0.0


func build() -> void:
	make_window(("Dorsal turret drill" if practice else "The Petrel's dorsal turret"), Vector2(1600, 960))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 260:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.15, 1.0)))
	_show_setup()


func _diff() -> String:
	return Minigames.difficulty()


func _extra() -> int:
	return 1 if practice else 0


# ------------------------------------------------------------ setup
func _show_setup() -> void:
	stage = "setup"
	sim = null
	view = null
	close_overlay()
	UIKit.clear(body)
	var cols := UIKit.hbox(28)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var tune: Dictionary = TurretSim.TUNING[_diff()]
	var count := clampi(int(tune["count"]) + _extra(), 2, 4)
	if practice:
		left.add_child(UIKit.label("The fire-control trainer projects WARDEN interceptor profiles onto the canopy. Nothing here can hurt you, and nothing here counts.", 18, UIKit.DIM, true))
	else:
		left.add_child(UIKit.label("You haul yourself up the ladder into the dorsal turret. The canopy is scratched glass and a lot of black. Behind the Petrel the Cinder Wake is already shrinking, and two pale shapes have just dropped off its dorsal rack.\n\nBrann, over the intercom: \"I can make us a hard target. I can't make us an invisible one. Get them off my tail.\"", 18, UIKit.TEXT, true))
	left.add_child(UIKit.header("The fight"))
	left.add_child(UIKit.rich("[b]%d interceptors[/b] weave across the starfield. When one swings in close it locks on ([color=#ff4a3a]red brackets[/color]) and rakes the hull. Destroy them all before the hull falls to [b]%d%%[/b] or [b]%d seconds[/b] pass, or Brann has to break off." % [count, int(TurretSim.HULL_FAIL), int(tune["limit"])], 18))
	left.add_child(UIKit.header("Controls"))
	left.add_child(UIKit.label("Mouse aims, left button fires.   Or: %s %s %s %s / arrow keys move the reticle, Space fires.   Esc pauses." % [Settings.key_label("move_forward"), Settings.key_label("move_left"), Settings.key_label("move_back"), Settings.key_label("move_right")], 17, UIKit.TEXT, true))
	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(470, 0)
	cols.add_child(right)
	right.add_child(UIKit.header("Options"))
	var assist := CheckBox.new()
	assist.text = "Assisted targeting"
	assist.tooltip_text = "Slow motion for everything but your gun and reticle, and shots near a drone are pulled onto it."
	assist.button_pressed = assisted
	assist.toggled.connect(func(on: bool) -> void: assisted = on)
	right.add_child(assist)
	right.add_child(UIKit.label("Half-speed interceptors and generous auto-aim, for less reflex-heavy play.", 15, UIKit.DIM, true))
	right.add_child(UIKit.spacer(0, 8))
	var go := UIKit.button("Man the turret  (Enter)", _start_fight)
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_size_override("font_size", 22)
	right.add_child(go)
	var ap := UIKit.button("Hand the turret to the autopilot", _autopilot, "Resolve the fight without playing it: one roll of d20 + the party's best Awareness.")
	ap.custom_minimum_size = Vector2(0, 46)
	right.add_child(ap)
	right.add_child(UIKit.label(_autopilot_odds(), 15, UIKit.DIM, true))
	if practice:
		right.add_child(UIKit.button("Leave the trainer", close_now))
	MinigamePanel.focus_later(go)


func _autopilot_odds() -> String:
	var dc := TurretSim.AUTOPILOT_DC + (-2 if _diff() == "story" else (0 if _diff() == "standard" else 2))
	var who := ""
	var bonus := 0
	if Game.state != null:
		for uid in Game.state.party:
			var s := Game.state.get_char(uid)
			if s != null and not s.dead and (who == "" or s.skill_total("awareness") > bonus):
				who = s.display_name
				bonus = s.skill_total("awareness")
	if who == "":
		return "The autopilot rolls d20 against DC %d." % dc
	var chance := clampi(21 - (dc - bonus), 0, 20) * 5
	return "%s calls targets for the autopilot: d20 %s vs DC %d (about %d%%)." % [who, Rules.signed(bonus), dc, chance]


func _start_fight() -> void:
	close_overlay()
	UIKit.clear(body)
	var seed_ := Minigames.dice_for(practice).randi_range(1, 1000000)
	sim = TurretSim.new(seed_, _diff(), assisted, _extra())
	method = "assisted" if assisted else "manual"
	view = Control.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.focus_mode = Control.FOCUS_ALL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.mouse_default_cursor_shape = Control.CURSOR_CROSS
	view.clip_contents = true
	view.draw.connect(_draw_view)
	view.gui_input.connect(_on_view_input)
	body.add_child(view)
	stage = "fight"
	_acc = 0.0
	_aim_moved = false
	_mouse_fire = false
	_tracers.clear()
	_bolts.clear()
	_parts.clear()
	MinigamePanel.focus_later(view)


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		_aim = _to_field((ev as InputEventMouseMotion).position)
		_aim_moved = true
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_mouse_fire = (ev as InputEventMouseButton).pressed
		_aim = _to_field((ev as InputEventMouseButton).position)
		_aim_moved = true
		view.accept_event()
	elif ev is InputEventKey and not ev.is_action("menu") and (ev as InputEventKey).keycode != KEY_ESCAPE:
		view.accept_event()


## Field placement inside the view: 1600 x 900 scaled to fit, centred.
func _field_xform() -> Vector3:
	var s := minf(view.size.x / TurretSim.W, view.size.y / TurretSim.H)
	var ox := (view.size.x - TurretSim.W * s) * 0.5
	var oy := (view.size.y - TurretSim.H * s) * 0.5
	return Vector3(ox, oy, s)


func _to_field(p: Vector2) -> Vector2:
	var f := _field_xform()
	return (p - Vector2(f.x, f.y)) / maxf(f.z, 0.001)


func _to_view(p: Vector2) -> Vector2:
	var f := _field_xform()
	return Vector2(f.x, f.y) + p * f.z


# ------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if view == null or is_closed():
		return
	if not is_paused():
		_t += delta
		if stage == "fight":
			_acc = minf(_acc + delta, 0.25)
			while _acc >= DT and sim.result == "":
				sim.step(DT, read_input())
				_acc -= DT
			for e in sim.take_events():
				_on_event(e)
			if sim.result != "":
				_end_fight(sim.result, method)
		_age_effects(delta)
	view.queue_redraw()


## Live input: mouse aim (when it moved), move keys / arrows, fire buttons.
func read_input() -> Dictionary:
	var mv := Vector2.ZERO
	if Input.is_action_pressed("move_left") or Input.is_physical_key_pressed(KEY_LEFT):
		mv.x -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_physical_key_pressed(KEY_RIGHT):
		mv.x += 1.0
	if Input.is_action_pressed("move_forward") or Input.is_physical_key_pressed(KEY_UP):
		mv.y -= 1.0
	if Input.is_action_pressed("move_back") or Input.is_physical_key_pressed(KEY_DOWN):
		mv.y += 1.0
	var fire := _mouse_fire or Input.is_physical_key_pressed(KEY_SPACE) or Input.is_action_pressed("attack_target")
	var inp := {"move": mv, "fire": fire}
	if _aim_moved:
		inp["aim"] = _aim
		_aim_moved = false
	return inp


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"shot":
			var at: Vector2 = e["at"]
			for gun in [Vector2(TurretSim.W * 0.32, TurretSim.H + 20.0), Vector2(TurretSim.W * 0.68, TurretSim.H + 20.0)]:
				_tracers.append({"a": gun, "b": at, "life": 0.07})
			if bool(e["hit"]):
				for i in 3:
					_parts.append({"p": at, "v": Vector2(randf_range(-160, 160), randf_range(-160, 160)), "life": 0.25, "max": 0.25, "col": UIKit.ACCENT2})
		"kill":
			var at2: Vector2 = e["at"]
			var n := 26 if not Minigames.reduce_flash() else 14
			for i in n:
				var a := randf() * TAU
				var spd := randf_range(80.0, 420.0) * (0.6 + float(e["z"]))
				_parts.append({"p": at2, "v": Vector2(cos(a), sin(a)) * spd, "life": randf_range(0.5, 1.1), "max": 1.1, "col": UIKit.ACCENT if i % 3 else UIKit.ACCENT2})
			_parts.append({"p": at2, "v": Vector2.ZERO, "life": 0.45, "max": 0.45, "col": Color.WHITE, "ring": true})
			GameAudio.play("explosion", -4.0)
			if not Minigames.reduce_shake():
				_shake = maxf(_shake, 0.35)
		"hull_hit":
			var from: Vector2 = e["from"]
			_bolts.append({"a": from, "b": Vector2(TurretSim.W * randf_range(0.3, 0.7), TurretSim.H + 40.0), "life": 0.12})
			_flash = 1.0
			if not Minigames.reduce_shake():
				_shake = maxf(_shake, 0.5)
			GameAudio.play("crit", -8.0)


func _age_effects(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 3.0)
	_shake = maxf(0.0, _shake - delta * 2.5)
	for arr in [_tracers, _bolts, _parts]:
		var list: Array = arr
		for i in range(list.size() - 1, -1, -1):
			var fx: Dictionary = list[i]
			fx["life"] = float(fx["life"]) - delta
			if fx.has("v"):
				var pos: Vector2 = fx["p"]
				var vel: Vector2 = fx["v"]
				fx["p"] = pos + vel * delta
				fx["v"] = vel * (1.0 - 1.8 * delta)
			if float(fx["life"]) <= 0.0:
				list.remove_at(i)


# ------------------------------------------------------------ outcomes
func _autopilot() -> void:
	close_overlay()
	var dice := Minigames.dice_for(practice)
	var r := TurretSim.autopilot(Game.state, dice, _diff())
	var line := "d20 %d %s = %d vs DC %d" % [int(r["natural"]), Rules.signed(int(r["bonus"])), int(r["total"]), int(r["dc"])]
	if String(r["who"]) != "":
		line = "%s calls targets: %s" % [String(r["who"]), line]
	outcome = r
	_end_fight(String(r["result"]), "autopilot", line)


func _end_fight(result: String, how: String, detail: String = "") -> void:
	if stage == "done":
		return
	stage = "done"
	method = how
	var won := result == "player_win"
	var title := ""
	var text := ""
	if how == "autopilot":
		title = "Autopilot: interceptors down" if won else "Autopilot: they got through"
		text = detail + ("\n\nThe turret slews on its own, Brann flies the angles your spotter calls, and the interceptors come apart one by one." if won else "\n\nThe autopilot drives most of them off, but one interceptor gets a long burst into the Petrel's spine before it breaks away.")
	elif sim == null:
		title = "Brann breaks off"
		text = "Nobody mans the dorsal turret. Brann throws the Petrel into a long, ugly burn and takes what the interceptors give him."
	elif won:
		title = "Interceptors destroyed"
		text = "Hull integrity %d%%. %d of %d shots on target." % [int(sim.hull), sim.hits, sim.shots]
	else:
		title = "Hull breach: Brann breaks off" if sim.reason == "hull" else "Out of time: Brann breaks off"
		text = "Hull integrity %d%%. %d of %d interceptors destroyed." % [int(sim.hull), sim.kills, sim.drones.size()]
	if assisted and how != "autopilot":
		text += "\n[color=#9c958a]Assisted targeting was on.[/color]"
	GameAudio.play("ui_confirm" if won else "ui_error", -4.0)
	if practice:
		Minigames.post_finished("turret", result, true)
		show_overlay(title, text + "\n\nDrill complete. Nothing was recorded.", [["Run the drill again", _show_setup], ["Leave", close_now]], 1)
	else:
		show_overlay(title, text, [["Continue", func() -> void: _resolve(result, how)]], 0)


## Real escape only: record the result, close, and let the story continue.
func _resolve(result: String, how: String) -> void:
	if _resolved or practice:
		return
	_resolved = true
	var hull := int(sim.hull) if sim != null else 0
	if Game.state != null:
		MinigameRewards.turret_finish(Game.state, result, how, hull)
	Minigames.post_finished("turret", result, false)
	close_now()
	if Game.world != null and is_instance_valid(Game.world):
		Game.world.start_dialogue("launch_after")


# ------------------------------------------------------------ esc / keys
func on_escape() -> void:
	if practice:
		if stage == "fight":
			show_overlay("Drill paused", "", [["Resume", _resume], ["Restart", _start_fight], ["Leave", close_now]], 0, 520.0)
		else:
			close_now()
		return
	if stage == "done":
		return
	# The real fight cannot be skipped: every way out resolves it.
	var lines := "The interceptors are still out there."
	var buttons: Array = [["Back to the turret" if stage == "fight" else "Back", _resume], ["Hand to the autopilot", _autopilot], ["Break off (counts as a loss)", _break_off]]
	show_overlay("Paused", lines + " Brann can try the autopilot, or break off and run with what the hull can take.", buttons, 0, 640.0)


func _resume() -> void:
	close_overlay()
	if view != null:
		MinigamePanel.focus_later(view)


func _break_off() -> void:
	close_overlay()
	_end_fight("player_loss", method if stage == "fight" else "manual")


func handle_key(ev: InputEventKey) -> void:
	if stage == "setup" and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER):
		_start_fight()


# ------------------------------------------------------------ drawing
func _draw_view() -> void:
	if sim == null or view == null:
		return
	var f := _field_xform()
	var sh := Vector2.ZERO
	if _shake > 0.0:
		sh = Vector2(sin(_t * 87.0), cos(_t * 71.0)) * _shake * 12.0
	view.draw_rect(Rect2(Vector2.ZERO, view.size), SPACE)
	view.draw_set_transform(Vector2(f.x, f.y) + sh, 0.0, Vector2(f.z, f.z))
	_draw_space()
	for dr in sim.drones:
		if dr.alive and dr.t >= dr.delay:
			_draw_drone(dr)
	for b in _bolts:
		var c := WARDEN_RED
		c.a = clampf(float(b["life"]) / 0.12, 0.0, 1.0)
		view.draw_line(b["a"], b["b"], c, 4.0)
	for tr in _tracers:
		var c2 := Color(1.0, 0.9, 0.5, clampf(float(tr["life"]) / 0.07, 0.0, 1.0))
		view.draw_line(tr["a"], tr["b"], c2, 3.0)
	for p in _parts:
		var k := clampf(float(p["life"]) / float(p["max"]), 0.0, 1.0)
		var pc: Color = p["col"]
		pc.a = k
		if p.has("ring"):
			if not Minigames.reduce_flash():
				view.draw_circle(p["p"], 90.0 * (1.0 - k) + 10.0, Color(1, 1, 1, k * 0.35))
			view.draw_arc(p["p"], 110.0 * (1.0 - k) + 10.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.5, k), 4.0)
		else:
			var pp: Vector2 = p["p"]
			view.draw_rect(Rect2(pp - Vector2(3, 3), Vector2(6, 6)), pc)
	_draw_frame()
	_draw_reticle()
	view.draw_set_transform(Vector2.ZERO)
	if _flash > 0.0:
		if Minigames.reduce_flash():
			view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(1, 0.2, 0.15, _flash * 0.35), false, 10.0)
		else:
			view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(1, 0.2, 0.15, _flash * 0.22))
	_draw_hud()


func _draw_space() -> void:
	var W := TurretSim.W
	var H := TurretSim.H
	var speed := 0.5 if assisted else 1.0
	for s in _stars:
		# Stars stream toward the vanishing point behind the Petrel.
		var ph := fposmod(s.x + _t * 0.05 * s.z * speed, 1.0)
		var c := Vector2(W * 0.5, H * 0.32)
		var dir := Vector2(cos(s.y * TAU), sin(s.y * TAU))
		var p := c + dir * (1.0 - ph) * W * 0.75
		var a := (1.0 - ph) * s.z
		view.draw_rect(Rect2(p, Vector2(2.0, 2.0) * (0.5 + s.z)), Color(0.85, 0.9, 1.0, a))
	# The Cinder Wake, receding.
	var cw := Vector2(W * 0.5, H * 0.32)
	var sc := maxf(0.25, 1.0 - sim.time / maxf(sim.time_limit, 1.0) * 0.6)
	view.draw_rect(Rect2(cw + Vector2(-110, -14) * sc, Vector2(220, 28) * sc), Color("#1a1d22"))
	view.draw_rect(Rect2(cw + Vector2(-60, -30) * sc, Vector2(90, 16) * sc), Color("#1a1d22"))
	view.draw_rect(Rect2(cw + Vector2(-140, -6) * sc, Vector2(30, 14) * sc), Color("#e8823a"))
	view.draw_circle(Vector2(W * 0.12, H * 0.95), 300.0, Color("#3a1d10", 0.6))
	view.draw_circle(Vector2(W * 0.1, H * 0.97), 270.0, Color("#7a3a1a", 0.35))


func _draw_drone(dr: TurretSim.Drone) -> void:
	var r := dr.radius()
	var p := dr.pos
	var body_col := Color("#3a3f4a") if dr.flash <= 0.0 else (Color("#ffffff") if not Minigames.reduce_flash() else Color("#6a7080"))
	var wing := PackedVector2Array([p + Vector2(-r * 1.4, -r * 0.1), p + Vector2(-r * 0.3, -r * 0.35), p + Vector2(0, r * 0.15), p + Vector2(r * 0.3, -r * 0.35), p + Vector2(r * 1.4, -r * 0.1), p + Vector2(r * 0.4, r * 0.35), p + Vector2(-r * 0.4, r * 0.35)])
	view.draw_colored_polygon(wing, body_col.darkened(0.25))
	view.draw_polyline(wing + PackedVector2Array([wing[0]]), Color("#6a7080"), 2.0)
	var core := PackedVector2Array([p + Vector2(0, -r * 0.6), p + Vector2(r * 0.42, 0), p + Vector2(0, r * 0.6), p + Vector2(-r * 0.42, 0)])
	view.draw_colored_polygon(core, body_col)
	view.draw_circle(p, r * 0.18, WARDEN_RED)
	# Engine glow
	view.draw_circle(p + Vector2(0, -r * 0.55), r * 0.12, Color(1.0, 0.6, 0.3, 0.8))
	# Damage pips
	var w := r * 1.2
	var frac := float(dr.hp) / float(dr.max_hp)
	view.draw_rect(Rect2(p + Vector2(-w * 0.5, r * 0.75), Vector2(w, 5)), Color(0, 0, 0, 0.6))
	view.draw_rect(Rect2(p + Vector2(-w * 0.5, r * 0.75), Vector2(w * frac, 5)), WARDEN_RED)
	if dr.attacking():
		# Lock brackets
		var b := r * 1.25
		var lc := WARDEN_RED
		lc.a = 0.6 + (0.0 if Minigames.reduce_flash() else 0.4 * sin(_t * 18.0))
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				var c := p + Vector2(sx * b, sy * b)
				view.draw_line(c, c - Vector2(sx * b * 0.4, 0), lc, 3.0)
				view.draw_line(c, c - Vector2(0, sy * b * 0.4), lc, 3.0)


func _draw_frame() -> void:
	# The turret canopy struts and the twin barrels tracking the reticle.
	var W := TurretSim.W
	var H := TurretSim.H
	var frame := Color("#11141a")
	view.draw_colored_polygon(PackedVector2Array([Vector2(-40, H + 40), Vector2(-40, H * 0.72), Vector2(W * 0.18, H * 0.9), Vector2(W * 0.82, H * 0.9), Vector2(W + 40, H * 0.72), Vector2(W + 40, H + 40)]), frame)
	view.draw_line(Vector2(-40, -40), Vector2(W * 0.16, H * 0.9), frame, 26.0)
	view.draw_line(Vector2(W + 40, -40), Vector2(W * 0.84, H * 0.9), frame, 26.0)
	for gx in [W * 0.32, W * 0.68]:
		var base := Vector2(gx, H + 20.0)
		var dir := (sim.reticle - base).normalized()
		view.draw_line(base, base + dir * 150.0, Color("#2a2f38"), 22.0)
		view.draw_line(base + dir * 120.0, base + dir * 160.0, Color("#4a505c"), 14.0)


func _draw_reticle() -> void:
	var p := sim.reticle
	var on := false
	for dr in sim.drones:
		if dr.alive and dr.t >= dr.delay and dr.pos.distance_to(p) <= dr.radius() * 0.8 + TurretSim.SHOT_SLOP:
			on = true
	var col := WARDEN_RED if on else UIKit.TEAL
	view.draw_arc(p, 30.0, 0.0, TAU, 40, col, 2.5)
	view.draw_circle(p, 3.0, col)
	for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		view.draw_line(p + d * 18.0, p + d * 44.0, col, 2.5)
	if assisted:
		view.draw_arc(p, TurretSim.ASSIST_RADIUS * 0.6, 0.0, TAU, 48, Color(UIKit.TEAL, 0.25), 1.5)


func _draw_hud() -> void:
	var font := view.get_theme_default_font()
	var w := view.size.x
	view.draw_rect(Rect2(16, 16, 420, 96), Color(0, 0, 0, 0.5))
	view.draw_string(font, Vector2(30, 46), "HULL INTEGRITY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)
	var bar := Rect2(30, 58, 390, 24)
	view.draw_rect(bar, Color(0.12, 0.12, 0.14))
	var frac := sim.hull / TurretSim.HULL_MAX
	var hc := HULL_COL if frac > 0.5 else (UIKit.WARN if frac > TurretSim.HULL_FAIL / TurretSim.HULL_MAX + 0.1 else UIKit.BAD)
	view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), hc)
	var fx := bar.position.x + bar.size.x * TurretSim.HULL_FAIL / TurretSim.HULL_MAX
	view.draw_line(Vector2(fx, bar.position.y - 4), Vector2(fx, bar.end.y + 4), UIKit.BAD, 2.0)
	view.draw_string(font, Vector2(30, 104), "%d%%   (Brann breaks off at %d%%)" % [int(sim.hull), int(TurretSim.HULL_FAIL)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.TEXT)
	view.draw_rect(Rect2(w - 336, 16, 320, 96), Color(0, 0, 0, 0.5))
	view.draw_string(font, Vector2(w - 322, 50), "TIME  %d s" % ceili(sim.time_left()), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.TEXT)
	view.draw_string(font, Vector2(w - 322, 84), "INTERCEPTORS  %d" % sim.alive_count(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, WARDEN_RED)
	if assisted:
		view.draw_string(font, Vector2(w - 322, 106), "ASSISTED · SLOW MOTION", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UIKit.TEAL)
	if sim.time < 2.5 and stage == "fight":
		var c := UIKit.ACCENT2
		c.a = clampf(2.5 - sim.time, 0.0, 1.0)
		view.draw_string(font, Vector2(0, view.size.y * 0.55), "INTERCEPTORS INBOUND", HORIZONTAL_ALIGNMENT_CENTER, w, 44, c)
