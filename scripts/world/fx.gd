class_name FX
extends Node3D
## Cosmetic effects (bolts, floating combat text, bursts). Purely visual:
## outcomes were already resolved by the rules layer. Effects advance with the
## simulation clock, so tactical pause freezes them mid-flight.

var items: Array = []
static var _spark_mesh: BoxMesh
static var _flash_mesh: SphereMesh
## Sparks come from a fixed pool (no nodes made or freed per hit).
const SPARK_POOL := 48
var _sparks: Array[MeshInstance3D] = []
var _spark_i := 0


func bolt(from: Vector3, to: Vector3, col: Color, dur: float = 0.16, thick: float = 0.06) -> void:
	var mi := MeshKit.box(Vector3(thick, thick, 0.7), MeshKit.unshaded(col))
	add_child(mi)
	mi.position = from
	if from.distance_to(to) > 0.05:
		mi.look_at_from_position(from, to, Vector3.UP)
	items.append({"node": mi, "kind": "bolt", "t": 0.0, "dur": dur, "from": from, "to": to})


func slash(pos: Vector3, col: Color) -> void:
	var mi := MeshKit.torus(0.35, 0.42, MeshKit.unshaded(col))
	add_child(mi)
	mi.position = pos + Vector3(0, 1.1, 0)
	mi.rotation_degrees = Vector3(70, randf() * 360.0, 0)
	items.append({"node": mi, "kind": "fade", "t": 0.0, "dur": 0.2})


## Sparks thrown off an impact (cosmetic, global randf).
func sparks(pos: Vector3, col: Color, count: int = 6, speed: float = 2.6) -> void:
	var m := MeshKit.unshaded(col)
	if _sparks.is_empty():
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3(0.04, 0.04, 0.04)
		for j in SPARK_POOL:
			var pm := MeshInstance3D.new()
			pm.mesh = _spark_mesh
			pm.visible = false
			add_child(pm)
			_sparks.append(pm)
	for i in count:
		var mi := _sparks[_spark_i]
		_spark_i = (_spark_i + 1) % SPARK_POOL
		for k in range(items.size() - 1, -1, -1):
			if items[k]["node"] == mi:
				items.remove_at(k)
		mi.material_override = m
		mi.visible = true
		mi.position = pos
		var v := Vector3(randf_range(-1.0, 1.0), randf_range(0.2, 1.2), randf_range(-1.0, 1.0)).normalized() * speed * randf_range(0.5, 1.0)
		items.append({"node": mi, "kind": "spark", "t": 0.0, "dur": randf_range(0.25, 0.45), "v": v})


## A muzzle flash at a weapon's end.
func muzzle(pos: Vector3, col: Color) -> void:
	var c := col.lightened(0.35)
	if not bool(Settings.get_v("reduce_flash")):
		c = Color(c.r * 1.6, c.g * 1.6, c.b * 1.6)
	if _flash_mesh == null:
		_flash_mesh = SphereMesh.new()
		_flash_mesh.radius = 0.09
		_flash_mesh.height = 0.18
		_flash_mesh.radial_segments = 8
		_flash_mesh.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.material_override = MeshKit.unshaded(c)
	add_child(mi)
	mi.position = pos
	items.append({"node": mi, "kind": "flash", "t": 0.0, "dur": 0.09})


## Floating combat text. With damage numbers turned off, numbers and their
## variants ("CRIT 12", "-3 shield", "+4 EN", "+50 XP") are all hidden.
func text(pos: Vector3, txt: String, col: Color, big: bool = false) -> void:
	if not bool(Settings.get_v("damage_numbers")) and _numeric(txt):
		return
	var l := Label3D.new()
	l.text = txt
	l.modulate = col
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.font_size = 44 if big else 34
	l.outline_size = 10
	l.pixel_size = 0.006
	add_child(l)
	l.position = pos + Vector3(randf_range(-0.2, 0.2), 2.0, 0)
	items.append({"node": l, "kind": "float", "t": 0.0, "dur": 1.1})


func burst(pos: Vector3, col: Color, radius: float) -> void:
	var flashy := not bool(Settings.get_v("reduce_flash"))
	var c := col
	c.a = 0.55 if flashy else 0.3
	var mi := MeshKit.sphere(1.0, MeshKit.unshaded(c), 16)
	add_child(mi)
	mi.position = pos + Vector3(0, 0.6, 0)
	mi.scale = Vector3.ONE * 0.2
	items.append({"node": mi, "kind": "burst", "t": 0.0, "dur": 0.45, "r": radius})


func pulse(pos: Vector3, col: Color, radius: float = 1.2) -> void:
	var c := col
	c.a = 0.7
	var mi := MeshKit.torus(0.9, 1.0, MeshKit.unshaded(c))
	add_child(mi)
	mi.position = pos + Vector3(0, 0.1, 0)
	items.append({"node": mi, "kind": "pulse", "t": 0.0, "dur": 0.6, "r": radius})


static func _numeric(txt: String) -> bool:
	for ch in txt:
		if "0123456789".contains(ch):
			return true
	return false


func step(dt: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it["t"] = float(it["t"]) + dt
		var k := float(it["t"]) / float(it["dur"])
		var n: Node3D = it["node"]
		if not is_instance_valid(n):
			items.remove_at(i)
			continue
		match String(it["kind"]):
			"bolt":
				n.position = (it["from"] as Vector3).lerp(it["to"], clampf(k, 0.0, 1.0))
			"float":
				n.position.y += dt * 0.9
				(n as Label3D).modulate.a = clampf(1.4 - k, 0.0, 1.0)
			"burst":
				n.scale = Vector3.ONE * lerpf(0.2, float(it["r"]), clampf(k * 1.6, 0.0, 1.0))
			"pulse":
				n.scale = Vector3.ONE * lerpf(0.3, float(it["r"]), k)
			"fade":
				n.scale = Vector3.ONE * (1.0 + k * 0.4)
			"spark":
				var v: Vector3 = it["v"]
				n.position += v * dt
				v.y -= 9.0 * dt
				it["v"] = v
				n.scale = Vector3.ONE * maxf(0.05, 1.0 - k)
			"flash":
				n.scale = Vector3.ONE * (1.0 + k * 1.5)
		if k >= 1.0:
			if String(it["kind"]) == "spark":
				n.visible = false  # back to the pool
			else:
				n.queue_free()
			items.remove_at(i)


func clear_all() -> void:
	for it in items:
		if is_instance_valid(it["node"]):
			if String(it["kind"]) == "spark":
				(it["node"] as Node3D).visible = false
			else:
				(it["node"] as Node).queue_free()
	items.clear()
