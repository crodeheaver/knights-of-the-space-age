class_name SlipstreamPanel
extends MinigamePanel
## The Slipstream sim booth: pre-race options (Assisted driving, ghost), a
## countdown, the race drawn as a pseudo-3D track (a Control that draws
## itself; no assets), and the results with best time and par reward.
## Simulation: SlipstreamSim, stepped at a fixed rate. Records and prizes:
## MinigameRewards. Respects Settings reduce_flash / reduce_shake.

const DT := 1.0 / 120.0
const SEG := 3.0
const SLICES := 110
const CAM_BEHIND := 8.0
const CURVE_VIS := 0.0055
const SKY_TOP := Color("#0a0618")
const SKY_LOW := Color("#3a1730")
const GROUND_A := Color("#0b0f17")
const GROUND_B := Color("#0e1320")
const ROAD_A := Color("#232838")
const ROAD_B := Color("#272d3f")
const RUMBLE_A := Color("#e8823a")
const RUMBLE_B := Color("#3fb6b0")
const FOG := Color("#2a1830")

var sim: SlipstreamSim
var view: Control
var stage := "setup"
var assisted := false
var use_ghost := true
var ghost_samples: Array = []
var countdown := 0.0
var outcome: Dictionary = {}
var _acc := 0.0
var _cam_x := 0.0
var _sky_scroll := 0.0
var _shake := 0.0
var _flash := 0.0
var _flash_col := Color.WHITE
var _msg := ""
var _msg_t := 0.0
var _stars: Array[Vector3] = []
var _layout: SlipstreamSim = null


func build() -> void:
	make_window("Slipstream: hover-sled sim" + ("  (practice)" if practice else ""), Vector2(1560, 940))
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 120:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.3, 1.0)))
	if Game.state != null and Game.state.minigames.has("slipstream"):
		ghost_samples = (Game.state.minigames["slipstream"] as Dictionary).get("ghost", [])
	_show_setup()


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
	left.add_child(UIKit.label("The booth smells of warm plastic and someone else's nerves. The canopy seals, the commons fade, and a canyon of light unrolls ahead of you: three laps of the Slipstream circuit.", 18, UIKit.DIM, true))
	left.add_child(UIKit.header("How to race"))
	left.add_child(UIKit.rich("Your sled always moves forward. [b]Throttle[/b] pushes it toward top speed, [b]brake[/b] sheds speed fast, and [b]steering[/b] slides it across the three lanes.\n\n[color=#e8823a]Pylons[/color] and [color=#9c958a]debris[/color] block lanes: hitting one costs a lot of speed but never ends the race. [color=#3fb6b0]Boost pads[/color] fire you well past top speed for a moment.\n\nBends push the sled toward the outside; steer into them to hold your lane. Scraping the walls slows you down.", 18))
	left.add_child(UIKit.header("Circuit map (one lap, start on the left)"))
	var map := Control.new()
	map.custom_minimum_size = Vector2(0, 150)
	map.draw.connect(_draw_map.bind(map))
	left.add_child(map)
	left.add_child(UIKit.header("Controls"))
	left.add_child(UIKit.label("%s / ↑  throttle     %s / ↓  brake     %s %s / ← →  steer     Esc  pause" % [Settings.key_label("move_forward"), Settings.key_label("move_back"), Settings.key_label("move_left"), Settings.key_label("move_right")], 17, UIKit.TEXT, true))
	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(440, 0)
	cols.add_child(right)
	right.add_child(UIKit.header("Records"))
	var rec: Dictionary = Game.state.minigames.get("slipstream", {}) if Game.state != null else {}
	var best := float(rec.get("best", 0.0))
	right.add_child(UIKit.label("Best time: %s%s" % [MinigamePanel.fmt_time(best), " (assisted)" if bool(rec.get("best_assisted", false)) and best > 0.0 else ""], 18))
	right.add_child(UIKit.label("Par: %s   ·   Assisted par: %s" % [MinigamePanel.fmt_time(MinigameRewards.slipstream_par(false)), MinigamePanel.fmt_time(MinigameRewards.slipstream_par(true))], 17, UIKit.DIM, true))
	if practice or Game.state == null:
		right.add_child(UIKit.label("Practice run: no times or prizes are recorded.", 17, UIKit.TEAL, true))
	elif Game.state.claimed("slipstream_par"):
		right.add_child(UIKit.label("Par prize already claimed. Race for the record.", 17, UIKit.DIM, true))
	else:
		right.add_child(UIKit.label("Beat par once: %d credits from the booth's prize pool and +%d XP." % [MinigameRewards.SLIPSTREAM_PRIZE, MinigameRewards.SLIPSTREAM_XP], 17, UIKit.GOOD, true))
	right.add_child(UIKit.spacer(0, 10))
	right.add_child(UIKit.header("Options"))
	var assist := CheckBox.new()
	assist.text = "Assisted driving"
	assist.tooltip_text = "The sled steers around obstacles for you and eases off before rows it cannot clear. Top speed is reduced; the par time is adjusted to match."
	assist.button_pressed = assisted
	assist.toggled.connect(func(on: bool) -> void: assisted = on)
	right.add_child(assist)
	right.add_child(UIKit.label("Steers for you and lowers top speed. Hold throttle to beat the assisted par.", 15, UIKit.DIM, true))
	var gh := CheckBox.new()
	gh.text = "Race my best-time ghost"
	gh.disabled = ghost_samples.is_empty()
	gh.button_pressed = use_ghost and not gh.disabled
	if gh.disabled:
		gh.tooltip_text = "Finish a recorded race first."
	gh.toggled.connect(func(on: bool) -> void: use_ghost = on)
	right.add_child(gh)
	right.add_child(UIKit.expand(UIKit.spacer(0, 10)))
	var go := UIKit.button("Start the race  (Enter)", _start_race)
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_size_override("font_size", 22)
	right.add_child(go)
	right.add_child(UIKit.button("Leave the booth", close_now))
	MinigamePanel.focus_later(go)


func _start_race() -> void:
	close_overlay()
	UIKit.clear(body)
	sim = SlipstreamSim.new(assisted)
	view = Control.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.focus_mode = Control.FOCUS_ALL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.clip_contents = true
	view.draw.connect(_draw_view)
	view.gui_input.connect(_on_view_input)
	body.add_child(view)
	stage = "countdown"
	countdown = 3.0
	_acc = 0.0
	_cam_x = 0.0
	_msg = ""
	MinigamePanel.focus_later(view)


func _on_view_input(ev: InputEvent) -> void:
	# Keep arrow keys and Space from moving GUI focus while racing.
	if ev is InputEventKey and not ev.is_action("menu") and (ev as InputEventKey).keycode != KEY_ESCAPE:
		view.accept_event()


# ------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if view == null or is_closed():
		return
	if not is_paused():
		if stage == "countdown":
			var before := ceili(countdown)
			countdown -= delta
			if ceili(countdown) != before and countdown > 0.0:
				GameAudio.play("ui_click", -6.0)
			if countdown <= 0.0:
				stage = "race"
				_message("GO!")
				GameAudio.play("ui_confirm", -6.0)
		elif stage == "race":
			_acc = minf(_acc + delta, 0.25)
			while _acc >= DT and not sim.finished:
				sim.step(DT, read_input())
				_acc -= DT
			for e in sim.take_events():
				_on_event(e)
			if sim.finished:
				_finish()
		_cam_x = lerpf(_cam_x, sim.x * 0.55, minf(1.0, delta * 6.0))
		_sky_scroll += sim.curve_at(sim.d) * sim.speed * delta * 0.9 if stage == "race" else 0.0
		_shake = maxf(0.0, _shake - delta * 2.5)
		_flash = maxf(0.0, _flash - delta * 2.5)
		_msg_t = maxf(0.0, _msg_t - delta)
	view.queue_redraw()


## Live input from the game's move bindings plus the arrow keys.
func read_input() -> Dictionary:
	var accel := Input.is_action_pressed("move_forward") or Input.is_physical_key_pressed(KEY_UP)
	var brake := Input.is_action_pressed("move_back") or Input.is_physical_key_pressed(KEY_DOWN)
	var steer := 0.0
	if Input.is_action_pressed("move_left") or Input.is_physical_key_pressed(KEY_LEFT):
		steer -= 1.0
	if Input.is_action_pressed("move_right") or Input.is_physical_key_pressed(KEY_RIGHT):
		steer += 1.0
	return {"accel": accel, "brake": brake, "steer": steer}


func _on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"hit":
			_message("IMPACT")
			_bump(0.55, UIKit.BAD)
			GameAudio.play("bash", -4.0)
		"boost":
			_message("BOOST")
			_bump(0.0, UIKit.TEAL)
			GameAudio.play("cast", -8.0)
		"lap":
			_message("LAP %d / %d" % [int(e["lap"]), SlipstreamSim.LAPS])
			GameAudio.play("ui_confirm", -8.0)
		"scrape":
			_bump(0.15, Color.TRANSPARENT)


func _bump(shake: float, col: Color) -> void:
	if not Minigames.reduce_shake():
		_shake = maxf(_shake, shake)
	if col.a > 0.0:
		_flash = 0.25 if Minigames.reduce_flash() else 0.6
		_flash_col = col


func _message(m: String) -> void:
	_msg = m
	_msg_t = 1.2


func _finish() -> void:
	if stage == "done":
		return
	stage = "done"
	var t := sim.finish_time
	var lines: Array[String] = ["Time: [b]%s[/b]   (impacts %d, boosts %d)" % [MinigamePanel.fmt_time(t), sim.hits, sim.boosts]]
	var par := MinigameRewards.slipstream_par(assisted)
	if practice or Game.state == null:
		lines.append("Par %s: %s" % [MinigamePanel.fmt_time(par), "beaten" if t <= par else "missed"])
		lines.append("Practice run: nothing recorded.")
		outcome = {"time": t}
	else:
		outcome = MinigameRewards.slipstream_finish(Game.state, t, assisted, sim.ghost)
		if bool(outcome["new_best"]):
			lines.append("[color=#f2c26b]New best time![/color]")
			ghost_samples = sim.ghost.duplicate()
		else:
			lines.append("Best: %s" % MinigamePanel.fmt_time(float(outcome["best"])))
		lines.append("Par %s: %s" % [MinigamePanel.fmt_time(par), "[color=#5fd38a]beaten[/color]" if bool(outcome["beat_par"]) else "missed"])
		if int(outcome["prize"]) > 0:
			lines.append("[color=#5fd38a]Prize: %d credits.[/color]" % int(outcome["prize"]))
		if int(outcome["xp"]) > 0:
			lines.append("[color=#f2c26b]+%d XP.[/color]" % int(outcome["xp"]))
	if assisted:
		lines.append("[color=#9c958a]Assisted driving was on.[/color]")
	Minigames.post_finished("slipstream", "par" if t <= par else "finished", practice)
	show_overlay("Finish!", "\n".join(lines), [["Race again", _start_race], ["Options", _show_setup], ["Leave", close_now]], 2)


# ------------------------------------------------------------ esc / keys
func on_escape() -> void:
	if stage == "countdown" or stage == "race":
		show_overlay("Race paused", "The sim holds the frame. Leaving now records no time.", [["Resume", _resume], ["Restart", _start_race], ["Leave", close_now]], 0, 520.0)
	else:
		close_now()


func _resume() -> void:
	close_overlay()
	if view != null:
		MinigamePanel.focus_later(view)


func handle_key(ev: InputEventKey) -> void:
	if stage == "setup" and (ev.keycode == KEY_ENTER or ev.keycode == KEY_KP_ENTER):
		_start_race()


# ------------------------------------------------------------ drawing
## The lap layout as a strip: bends shaded (arrow shows which way), the three
## lanes, obstacle rows and boost pads. Same seed as the race, so it is exact.
func _draw_map(map: Control) -> void:
	if _layout == null:
		_layout = SlipstreamSim.new(false)
	var lay := _layout
	var w := map.size.x
	var h := map.size.y
	var font := map.get_theme_default_font()
	var top := 22.0
	var lane_h := (h - top - 8.0) / 3.0
	var sx := w / SlipstreamSim.LAP_LENGTH
	map.draw_rect(Rect2(0, top, w, lane_h * 3.0), Color(0.12, 0.13, 0.17))
	for b in lay.bends:
		var r := Rect2(float(b["d"]) * sx, top, float(b["len"]) * sx, lane_h * 3.0)
		map.draw_rect(r, Color(0.45, 0.22, 0.35, 0.45))
		var arrow := "bend →" if float(b["c"]) > 0.0 else "← bend"
		map.draw_string(font, Vector2(r.position.x, top - 6.0), arrow, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 13, UIKit.DIM)
	for l in 2:
		map.draw_line(Vector2(0, top + lane_h * (l + 1)), Vector2(w, top + lane_h * (l + 1)), Color(0.5, 0.5, 0.55, 0.4), 1.0)
	for p in lay.pads:
		map.draw_rect(Rect2(float(p["d"]) * sx - 5.0, top + lane_h * int(p["lane"]) + 4.0, 10.0, lane_h - 8.0), UIKit.TEAL)
	for o in lay.obstacles:
		var col := Color("#e8823a") if String(o["kind"]) == "pylon" else Color("#7a7f8b")
		map.draw_rect(Rect2(float(o["d"]) * sx - 3.0, top + lane_h * int(o["lane"]) + 3.0, 6.0, lane_h - 6.0), col)
	map.draw_rect(Rect2(0, top, 4, lane_h * 3.0), Color.WHITE)


func _draw_view() -> void:
	if sim == null or view == null:
		return
	var w := view.size.x
	var h := view.size.y
	var off := Vector2.ZERO
	if _shake > 0.0:
		off = Vector2(sin(sim.time * 91.0), cos(sim.time * 73.0)) * _shake * 10.0
	view.draw_set_transform(off)
	var horizon := h * 0.36
	_draw_sky(w, horizon)
	view.draw_rect(Rect2(-20, horizon, w + 40, h - horizon + 20), GROUND_A)
	# Projection: the road is ~80% of the width at the sled and the sled sits
	# near the bottom of the view.
	var focal := 0.8 * w * CAM_BEHIND / (2.0 * SlipstreamSim.HALF_WIDTH)
	var cam_h := (h * 0.86 - horizon) * CAM_BEHIND / focal
	var cam_d := sim.d - CAM_BEHIND
	var zs := PackedFloat32Array()
	var cs := PackedFloat32Array()
	var z := SEG - fposmod(cam_d, SEG)
	var cx := 0.0
	var dcx := 0.0
	for i in SLICES + 1:
		zs.append(z)
		cs.append(cx)
		if z > CAM_BEHIND:
			dcx += sim.curve_at(cam_d + z) * CURVE_VIS * SEG
		cx += dcx * SEG
		z += SEG
	var ctx := {"w": w, "horizon": horizon, "focal": focal, "cam_h": cam_h, "zs": zs, "cs": cs}
	var hw := SlipstreamSim.HALF_WIDTH
	for i in range(SLICES - 1, -1, -1):
		var z1 := zs[i]
		var z2 := zs[i + 1]
		if z1 < 0.6:
			continue
		var a := _proj(ctx, z1, cs[i])
		var b := _proj(ctx, z2, cs[i + 1])
		if b.y > h + 40.0:
			continue
		var seg_i := int(floor((cam_d + z1) / SEG))
		var alt := seg_i % 2 == 0
		var fog := clampf(z1 / (SEG * SLICES), 0.0, 1.0) * 0.75
		view.draw_rect(Rect2(-20, b.y, w + 40, a.y - b.y + 1.0), (GROUND_A if alt else GROUND_B).lerp(FOG, fog))
		_quad(a, (hw + 0.9) * a.z, b, (hw + 0.9) * b.z, (RUMBLE_A if alt else RUMBLE_B).darkened(0.25).lerp(FOG, fog))
		_quad(a, hw * a.z, b, hw * b.z, (ROAD_A if alt else ROAD_B).lerp(FOG, fog))
		if (seg_i >> 1) % 2 == 0:
			for lx in [-2.0, 2.0]:
				var lxf: float = lx
				_quad(Vector3(a.x + lxf * a.z, a.y, a.z), 0.09 * a.z, Vector3(b.x + lxf * b.z, b.y, b.z), 0.09 * b.z, Color(0.85, 0.85, 0.9, 0.5).lerp(FOG, fog))
		# Start/finish and lap lines.
		var wd := cam_d + z1
		var lap_line := fposmod(wd, SlipstreamSim.LAP_LENGTH)
		if lap_line < SEG and wd > SEG and wd <= sim.total_length() + SEG:
			_quad(a, hw * a.z, b, hw * b.z, Color(0.95, 0.95, 0.95).lerp(FOG, fog))
	_draw_pads(ctx, cam_d)
	_draw_uprights(ctx, cam_d)
	view.draw_set_transform(Vector2.ZERO)
	if _flash > 0.0:
		var fc := _flash_col
		fc.a = _flash * (0.12 if Minigames.reduce_flash() else 0.3)
		view.draw_rect(Rect2(Vector2.ZERO, view.size), fc)
	_draw_hud(w, h)


func _proj(ctx: Dictionary, z: float, centre: float, lateral: float = 0.0) -> Vector3:
	# Returns screen x, screen y and the pixels-per-metre scale at depth z.
	var s := float(ctx["focal"]) / maxf(z, 0.1)
	var sx := float(ctx["w"]) * 0.5 + (centre + lateral - _cam_x) * s
	var sy := float(ctx["horizon"]) + float(ctx["cam_h"]) * s
	return Vector3(sx, sy, s)


func _centre_at(ctx: Dictionary, z: float) -> float:
	var zs: PackedFloat32Array = ctx["zs"]
	var cs: PackedFloat32Array = ctx["cs"]
	var f := (z - zs[0]) / SEG
	var i := clampi(int(floor(f)), 0, zs.size() - 2)
	return lerpf(cs[i], cs[i + 1], clampf(f - i, 0.0, 1.0))


func _quad(a: Vector3, ha: float, b: Vector3, hb: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(a.x - ha, a.y), Vector2(a.x + ha, a.y), Vector2(b.x + hb, b.y), Vector2(b.x - hb, b.y)])
	view.draw_colored_polygon(pts, col)


func _draw_sky(w: float, horizon: float) -> void:
	var bands := 8
	for i in bands:
		var t0 := float(i) / bands
		view.draw_rect(Rect2(-20, horizon * t0, w + 40, horizon / bands + 1.0), SKY_TOP.lerp(SKY_LOW, t0))
	for s in _stars:
		var sx := fposmod(s.x * w - _sky_scroll * 0.3 * s.z, w)
		view.draw_rect(Rect2(sx, s.y * horizon * 0.9, 2.0 * s.z, 2.0 * s.z), Color(0.9, 0.85, 1.0, 0.25 + 0.5 * s.z))
	# Haldis on the horizon, sliding with the bends.
	var px := fposmod(w * 0.7 - _sky_scroll * 1.2, w + 600.0) - 300.0
	view.draw_circle(Vector2(px, horizon + 30.0), 160.0, Color("#7a3a1a"))
	view.draw_circle(Vector2(px - 24.0, horizon + 14.0), 138.0, Color("#b8622a", 0.75))
	view.draw_rect(Rect2(-20, horizon - 2.0, w + 40, 4.0), Color("#e8823a", 0.5))


func _draw_pads(ctx: Dictionary, cam_d: float) -> void:
	var lap0 := int(sim.d / SlipstreamSim.LAP_LENGTH)
	var far := SEG * (SLICES - 1)
	for k in range(lap0, mini(lap0 + 2, SlipstreamSim.LAPS)):
		for p in sim.pads:
			var z := float(p["d"]) + k * SlipstreamSim.LAP_LENGTH - cam_d
			if z < 1.0 or z > far:
				continue
			var lx: float = SlipstreamSim.LANE_X[int(p["lane"])]
			var a := _proj(ctx, z, _centre_at(ctx, z), lx)
			var b := _proj(ctx, z + 5.0, _centre_at(ctx, z + 5.0), lx)
			var glow := 0.75 + (0.0 if Minigames.reduce_flash() else 0.25 * sin(sim.time * 12.0))
			_quad(a, SlipstreamSim.PAD_HALF * a.z, b, SlipstreamSim.PAD_HALF * b.z, Color(0.25, 0.71, 0.69, glow))
			# Chevrons
			for c in 2:
				var zc := z + 1.2 + c * 1.8
				var m := _proj(ctx, zc, _centre_at(ctx, zc), lx)
				var tip := _proj(ctx, zc + 1.0, _centre_at(ctx, zc + 1.0), lx)
				view.draw_polyline(PackedVector2Array([Vector2(m.x - 1.1 * m.z, m.y), Vector2(tip.x, tip.y), Vector2(m.x + 1.1 * m.z, m.y)]), Color(0.9, 1.0, 1.0, 0.9), maxf(1.5, 0.18 * m.z))


func _draw_uprights(ctx: Dictionary, cam_d: float) -> void:
	# Obstacles, the ghost and the sled, far to near.
	var items: Array[Dictionary] = []
	var lap0 := int(sim.d / SlipstreamSim.LAP_LENGTH)
	var far := SEG * (SLICES - 1)
	for k in range(lap0, mini(lap0 + 2, SlipstreamSim.LAPS)):
		for o in sim.obstacles:
			var z := float(o["d"]) + k * SlipstreamSim.LAP_LENGTH - cam_d
			if z > 1.0 and z < far:
				items.append({"z": z, "kind": String(o["kind"]), "x": SlipstreamSim.LANE_X[int(o["lane"])]})
	if use_ghost and not ghost_samples.is_empty() and stage != "setup":
		var g := SlipstreamSim.ghost_at(ghost_samples, sim.time)
		var gz := g.x - cam_d
		if g.x >= 0.0 and gz > 1.5 and gz < far:
			items.append({"z": gz, "kind": "ghost", "x": g.y})
	items.append({"z": CAM_BEHIND, "kind": "sled", "x": sim.x})
	items.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p["z"]) > float(q["z"]))
	for it in items:
		var z := float(it["z"])
		var p := _proj(ctx, z, _centre_at(ctx, z), float(it["x"]))
		var fog := clampf(z / far, 0.0, 1.0) * 0.7
		match String(it["kind"]):
			"pylon":
				var hw := SlipstreamSim.OBSTACLE_HALF * p.z
				var ht := 1.5 * p.z
				view.draw_rect(Rect2(p.x - hw, p.y - ht, hw * 2.0, ht), Color("#e8823a").lerp(FOG, fog))
				for sidx in 3:
					view.draw_rect(Rect2(p.x - hw, p.y - ht + ht * (0.15 + sidx * 0.3), hw * 2.0, ht * 0.12), Color("#1a1d22").lerp(FOG, fog))
				view.draw_rect(Rect2(p.x - hw, p.y - ht - 0.12 * p.z, hw * 2.0, 0.12 * p.z), Color("#f2c26b").lerp(FOG, fog))
			"debris":
				var r := SlipstreamSim.OBSTACLE_HALF * p.z
				var pts := PackedVector2Array([Vector2(p.x - r, p.y), Vector2(p.x - r * 0.7, p.y - r * 0.7), Vector2(p.x - r * 0.1, p.y - r * 0.95), Vector2(p.x + r * 0.5, p.y - r * 0.6), Vector2(p.x + r, p.y)])
				view.draw_colored_polygon(pts, Color("#5a5f6b").lerp(FOG, fog))
				view.draw_polyline(pts, Color("#9c958a").lerp(FOG, fog), maxf(1.0, 0.05 * p.z))
			"ghost":
				_draw_sled(p, 0.0, Color(0.5, 0.85, 1.0, 0.35), true)
			"sled":
				_draw_sled(p, sim.vx / SlipstreamSim.STEER_SPEED, Color("#e9e2d4"), false)


func _draw_sled(p: Vector3, lean: float, col: Color, ghost: bool) -> void:
	var s := p.z
	var hw := SlipstreamSim.SLED_HALF * s
	var hover := 0.25 * s + (0.0 if ghost or Minigames.reduce_flash() else sin(sim.time * 9.0) * 0.04 * s)
	var base := Vector2(p.x, p.y - hover)
	var sk := lean * 0.35 * hw
	if not ghost:
		# Ground glow (a flat ellipse under the sled) and boost flame.
		var glow := PackedVector2Array()
		for i in 20:
			var a := TAU * i / 20.0
			glow.append(Vector2(p.x + cos(a) * hw * 1.35, p.y + sin(a) * hw * 0.32))
		view.draw_colored_polygon(glow, Color(0.25, 0.71, 0.69, 0.3))
		if sim.boost_t > 0.0:
			var fl := 0.6 + (0.0 if Minigames.reduce_flash() else 0.4 * sin(sim.time * 40.0))
			view.draw_colored_polygon(PackedVector2Array([base + Vector2(-hw * 0.5, 0), base + Vector2(hw * 0.5, 0), base + Vector2(0, hw * 1.4 * fl)]), Color(0.5, 1.0, 1.0, 0.7))
	var hull := PackedVector2Array([base + Vector2(-hw, 0), base + Vector2(hw, 0), base + Vector2(hw * 0.55 + sk, -0.55 * s), base + Vector2(-hw * 0.55 + sk, -0.55 * s)])
	view.draw_colored_polygon(hull, col.darkened(0.55) if not ghost else col)
	view.draw_polyline(PackedVector2Array([hull[0], hull[1], hull[2], hull[3], hull[0]]), col, maxf(1.0, 0.05 * s))
	# Canopy and fins.
	view.draw_colored_polygon(PackedVector2Array([base + Vector2(-hw * 0.3 + sk, -0.5 * s), base + Vector2(hw * 0.3 + sk, -0.5 * s), base + Vector2(sk * 1.3, -0.85 * s)]), Color(0.25, 0.71, 0.69, 0.8 if not ghost else 0.3))
	view.draw_rect(Rect2(base + Vector2(-hw * 1.05, -0.2 * s), Vector2(hw * 0.25, 0.2 * s)), Color("#e8823a", 0.9 if not ghost else 0.3))
	view.draw_rect(Rect2(base + Vector2(hw * 0.8, -0.2 * s), Vector2(hw * 0.25, 0.2 * s)), Color("#e8823a", 0.9 if not ghost else 0.3))


func _draw_hud(w: float, h: float) -> void:
	var font := view.get_theme_default_font()
	var t := sim.time if stage != "countdown" else 0.0
	view.draw_rect(Rect2(14, 14, 330, 132), Color(0, 0, 0, 0.45))
	view.draw_string(font, Vector2(28, 50), "LAP %d / %d" % [sim.lap(), SlipstreamSim.LAPS], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UIKit.ACCENT2)
	view.draw_string(font, Vector2(28, 88), "TIME  " + MinigamePanel.fmt_time(maxf(t, 0.001) if stage != "countdown" else 0.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UIKit.TEXT)
	var par := MinigameRewards.slipstream_par(assisted)
	view.draw_string(font, Vector2(28, 122), "PAR  %s%s" % [MinigamePanel.fmt_time(par), "   ASSISTED" if assisted else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UIKit.DIM)
	# Speed and race progress.
	var top := (SlipstreamSim.BOOST_SPEED * (SlipstreamSim.ASSIST_SPEED if assisted else 1.0))
	var sp := clampf(sim.speed / top, 0.0, 1.0)
	var bar := Rect2(w - 360, h - 54, 330, 22)
	view.draw_rect(bar, Color(0, 0, 0, 0.5))
	view.draw_rect(Rect2(bar.position, Vector2(bar.size.x * sp, bar.size.y)), UIKit.TEAL if sim.boost_t > 0.0 else UIKit.ACCENT)
	view.draw_string(font, Vector2(w - 360, h - 62), "%d km/h" % int(sim.speed * 3.6), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UIKit.TEXT)
	var prog := Rect2(w * 0.5 - 300, 18, 600, 10)
	view.draw_rect(prog, Color(0, 0, 0, 0.5))
	view.draw_rect(Rect2(prog.position, Vector2(prog.size.x * sim.progress(), prog.size.y)), UIKit.ACCENT2)
	if use_ghost and not ghost_samples.is_empty():
		var g := SlipstreamSim.ghost_at(ghost_samples, sim.time)
		if g.x >= 0.0:
			var gx := prog.position.x + prog.size.x * clampf(g.x / sim.total_length(), 0.0, 1.0)
			view.draw_rect(Rect2(gx - 2, prog.position.y - 4, 4, prog.size.y + 8), Color(0.5, 0.85, 1.0, 0.9))
	if stage == "countdown":
		view.draw_string(font, Vector2(0, h * 0.45), str(ceili(countdown)), HORIZONTAL_ALIGNMENT_CENTER, w, 120, UIKit.ACCENT2)
	elif _msg_t > 0.0 and _msg != "":
		var c := UIKit.ACCENT2
		c.a = clampf(_msg_t, 0.0, 1.0)
		view.draw_string(font, Vector2(0, h * 0.3), _msg, HORIZONTAL_ALIGNMENT_CENTER, w, 56, c)
