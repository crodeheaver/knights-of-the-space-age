class_name Atmosphere
extends Node
## The ship's mood, area by area (fields on areas in data/ship_layout.json):
## * ambient / ambient_energy / fog / fog_density: light and haze, blended
##   as the party moves between areas;
## * alert: once the emergency starts, red alert washes the area's lights,
##   lamps and wall trims in a slow pulse (until the escape);
## * flicker: damaged lights stutter;
## plus shipwide trim pulses for WARDEN announcements, the reactor turning,
## the archive cores breathing, stars drifting past viewports and spark
## emitters that hold still on tactical pause.
## Visual only: lights, materials and particles. Only the current area and
## its neighbours are touched each frame, and no lights are added.

const ALERT_RED := Color("#ff2a1a")
const DEFAULT_AMBIENT := Color("#56627a")

var world: World
var env: Environment
var areas: Dictionary = {}
var lights: Dictionary = {}  # aid -> Array[OmniLight3D]
var lamps: Dictionary = {}  # aid -> StandardMaterial3D
var trims: Dictionary = {}  # aid -> StandardMaterial3D
var sparks: Array = []
var reactor: Array = []
var cores: Array = []
var windows: Array = []
var _base: Dictionary = {}  # OmniLight3D -> [color, energy]
var _lamp_base: Dictionary = {}  # aid -> Color
var _neighbors: Dictionary = {}  # aid -> Array[String]
var _active: Array = []  # areas styled last frame
var _t := 0.0
var _anim_t := 0.0
var _flick: Dictionary = {}  # OmniLight3D -> seconds left dimmed
var _paused := false


func setup(w: World, info: Dictionary) -> void:
	world = w
	env = info.get("env", null)
	areas = DB.dict(DB.layout, "areas")
	lights = info.get("lights", {})
	lamps = info.get("lamps", {})
	trims = info.get("trims", {})
	sparks = info.get("sparks", [])
	reactor = info.get("reactor", [])
	cores = info.get("cores", [])
	windows = info.get("windows", [])
	for aid in lights.keys():
		for l in lights[aid]:
			var ol: OmniLight3D = l
			_base[ol] = [ol.light_color, ol.light_energy]
	for aid in lamps.keys():
		_lamp_base[aid] = (lamps[aid] as StandardMaterial3D).albedo_color
	for d in DB.layout.get("doors", []):
		var a := String(d.get("a", ""))
		var b := String(d.get("b", ""))
		if not _neighbors.has(a):
			_neighbors[a] = []
		if not _neighbors.has(b):
			_neighbors[b] = []
		(_neighbors[a] as Array).append(b)
		(_neighbors[b] as Array).append(a)
	_emitters()
	if env != null:
		var a0: Dictionary = areas.get(w.current_area, {})
		env.ambient_light_color = Color(String(a0.get("ambient", DEFAULT_AMBIENT.to_html())))
		env.ambient_light_energy = float(a0.get("ambient_energy", 0.55))
		env.fog_light_color = Color(String(a0.get("fog", "#3a4250")))
		env.fog_density = float(a0.get("fog_density", 0.0))


## Positional hums on the props that make noise.
func _emitters() -> void:
	if not reactor.is_empty():
		GameAudio.loop_at("loop_reactor", (reactor[0] as Node3D).global_position + Vector3(0, 1.0, 0), world, 30.0, -2.0)
	for p in sparks:
		GameAudio.loop_at("loop_sparks", (p as Node3D).global_position, world, 11.0, -8.0)
	if not cores.is_empty():
		var c := Vector3.ZERO
		for m in cores:
			c += (m as Node3D).global_position
		GameAudio.loop_at("loop_machine", c / cores.size(), world, 18.0, -8.0)


## Tactical pause freezes the moving parts (sparks, reactor, stars).
func set_paused(on: bool) -> void:
	_paused = on
	for p in sparks:
		(p as CPUParticles3D).speed_scale = 0.0 if on else 1.0


func trim_materials() -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	for aid in trims.keys():
		out.append(trims[aid])
	return out


func alert_on() -> bool:
	return Game.state.has_flag("emergency_started") and not Game.state.has_flag("escaped")


func _process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	if not _paused:
		_anim_t += delta
	var soft := bool(Settings.get_v("reduce_flash"))
	var cur := world.current_area
	var a: Dictionary = areas.get(cur, {})
	# Light and haze blend towards the current area's profile.
	if env != null:
		var k := clampf(delta * 0.8, 0.0, 1.0)
		env.ambient_light_color = env.ambient_light_color.lerp(Color(String(a.get("ambient", DEFAULT_AMBIENT.to_html()))), k)
		env.ambient_light_energy = lerpf(env.ambient_light_energy, float(a.get("ambient_energy", 0.55)), k)
		env.fog_light_color = env.fog_light_color.lerp(Color(String(a.get("fog", "#3a4250"))), k)
		env.fog_density = lerpf(env.fog_density, float(a.get("fog_density", 0.0)), k)
	# Alert, flicker and announcement pulses for this area and its neighbours.
	var now_active: Array = [cur]
	for n in _neighbors.get(cur, []):
		if not now_active.has(n):
			now_active.append(n)
	for aid in _active:
		if not now_active.has(aid):
			_style_area(String(aid), false, soft, delta)
	for aid in now_active:
		_style_area(String(aid), true, soft, delta)
	_active = now_active
	_animate_props(soft)


func _style_area(aid: String, active: bool, soft: bool, delta: float) -> void:
	var ad: Dictionary = areas.get(aid, {})
	var alert := active and alert_on() and bool(ad.get("alert", false))
	var k := 0.0
	if alert:
		k = (0.5 + 0.5 * sin(_t * TAU * 0.45)) * (0.4 if soft else 1.0)
	var flicker := active and bool(ad.get("flicker", false)) and not soft
	for l in lights.get(aid, []):
		var ol: OmniLight3D = l
		var base: Array = _base[ol]
		var col: Color = base[0]
		var en: float = base[1]
		if alert:
			col = col.lerp(ALERT_RED, 0.3 * k + 0.06)
		if flicker:
			var left := float(_flick.get(ol, 0.0))
			if left > 0.0:
				_flick[ol] = left - delta
				en *= 0.25
			elif randf() < delta * 0.35:
				_flick[ol] = randf_range(0.05, 0.22)
		ol.light_color = col
		ol.light_energy = en
	if lamps.has(aid):
		var lb: Color = _lamp_base[aid]
		(lamps[aid] as StandardMaterial3D).albedo_color = lb.lerp(ALERT_RED, 0.55 * k + 0.15) if alert else lb
	if trims.has(aid):
		var tint := Color.WHITE.lerp(ALERT_RED, 0.7 * k + 0.1) if alert else Color.WHITE
		var p := world.trim_pulse_amount()
		if p > 0.0:
			tint = tint.lerp(world._trim_pulse_col, p * (0.45 if soft else 1.0))
		(trims[aid] as StandardMaterial3D).albedo_color = tint


func _animate_props(soft: bool) -> void:
	var t := _anim_t
	for i in reactor.size():
		var band: Node3D = reactor[i]
		band.rotation_degrees.y = t * (14.0 + 6.0 * i) * (-1.0 if i % 2 == 1 else 1.0)
		var s := 1.0 + 0.012 * sin(t * 2.3 + i)
		band.scale = Vector3(s, 1.0, s)
	if not reactor.is_empty():
		var bm := (reactor[0] as MeshInstance3D).material_override as StandardMaterial3D
		if bm != null:
			var base := Color("#e8823a")
			bm.albedo_color = base * (1.0 + (0.0 if soft else 0.35) * (0.5 + 0.5 * sin(t * 1.7)))
	if not cores.is_empty():
		var cm := (cores[0] as MeshInstance3D).material_override as StandardMaterial3D
		if cm != null:
			cm.emission_energy_multiplier = 2.2 + (0.0 if soft else 0.9) * (0.5 + 0.5 * sin(t * 0.9))
	for wd in windows:
		var w := float(wd["w"])
		var stars: Array = wd["stars"]
		for j in stars.size():
			var st: Node3D = stars[j]
			st.position.x = fposmod(fmod(j * 0.73, 1.0) * w * 0.9 + t * (0.04 + 0.02 * (j % 3)), w * 0.9) - w * 0.45
