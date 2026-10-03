class_name OverheadBars
extends Node3D
## Health bars over combatants' heads (Settings → Gameplay → Health bars:
## off / in combat / always). Two quads per bar, turned to face the active
## camera every frame; hostile red, party green, neutral amber. Hidden during
## conversations and cinematics. Visual only: reads sheets, writes nothing.

const W := 0.8
const H := 0.07
const RANGE := 30.0

var world: World
var bars: Dictionary = {}  # Actor -> {"root": Node3D, "fill": MeshInstance3D}
var _t := 0.0
static var _mats: Dictionary = {}


static func _mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.render_priority = 10
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func setup(w: World) -> void:
	world = w


func _process(delta: float) -> void:
	if world == null:
		return
	var mode := String(Settings.get_v("overhead_health"))
	var staged := world.modal.has("dialogue") or world.modal.has("cinematic")
	visible = mode != "off" and not staged
	if not visible:
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.1
		_sync(mode)
	var cam := world.cam.active_camera() if world.cam != null else null
	if cam == null or not cam.is_inside_tree():
		return
	var basis := cam.global_transform.basis
	var eye := cam.global_position
	for a in bars.keys():
		if not is_instance_valid(a):
			continue
		var b: Dictionary = bars[a]
		var root: Node3D = b["root"]
		root.global_position = (a as Actor).global_position + Vector3(0, DialogueStage.head_height(a) + 0.55, 0)
		root.global_basis = basis
		# A bar right in front of the lens (the leader, close) would fill the view.
		root.visible = root.global_position.distance_to(eye) > 2.5


func wants(a: Actor, mode: String) -> bool:
	if a.sheet.dead or not a.visible:
		return false
	if a.role == "npc" and not a.alert:
		return false
	var lead := world.controlled()
	if lead != null and a.position.distance_to(lead.position) > RANGE:
		return false
	if mode == "always":
		return a.role == "party" or a.alert or a.sheet.hp < a.sheet.max_hp()
	return world.combat.active and (a.in_combat or (a.role != "party" and a.alert))


func _sync(mode: String) -> void:
	for a in bars.keys():
		if not is_instance_valid(a) or not wants(a, mode):
			_drop(a)
	for o in world.actors.values():
		var a: Actor = o
		if not wants(a, mode):
			continue
		if not bars.has(a):
			bars[a] = _make()
		var b: Dictionary = bars[a]
		var frac := clampf(float(a.sheet.hp) / float(maxi(1, a.sheet.max_hp())), 0.0, 1.0)
		var fill: MeshInstance3D = b["fill"]
		fill.scale = Vector3(maxf(0.001, frac), 1.0, 1.0)
		fill.position = Vector3(-W * 0.5 * (1.0 - frac), 0.0, 0.002)
		var col := Color("#5fd38a")
		if a.role != "party":
			var lead := world.controlled()
			col = Color("#ff5a4a") if lead != null and world.hostile(lead, a) else Color("#f2c26b")
		fill.material_override = _mat(col)


func _make() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var bg := MeshInstance3D.new()
	var qb := QuadMesh.new()
	qb.size = Vector2(W + 0.04, H + 0.04)
	bg.mesh = qb
	bg.material_override = _mat(Color(0.02, 0.02, 0.03, 0.75))
	root.add_child(bg)
	var fill := MeshInstance3D.new()
	var qf := QuadMesh.new()
	qf.size = Vector2(W, H)
	fill.mesh = qf
	root.add_child(fill)
	return {"root": root, "fill": fill}


func _drop(a: Variant) -> void:
	var b: Dictionary = bars.get(a, {})
	if b.has("root") and is_instance_valid(b["root"]):
		(b["root"] as Node).queue_free()
	bars.erase(a)


## How many bars are showing (tests).
func count() -> int:
	return bars.size()
