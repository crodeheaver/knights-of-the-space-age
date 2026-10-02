class_name FX
extends Node3D
## Cosmetic effects (bolts, floating combat text, bursts). Purely visual:
## outcomes were already resolved by the rules layer. Effects advance with the
## simulation clock, so tactical pause freezes them mid-flight.

var items: Array = []


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


func text(pos: Vector3, txt: String, col: Color, big: bool = false) -> void:
	if not bool(Settings.get_v("damage_numbers")) and txt.is_valid_int():
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
		if k >= 1.0:
			n.queue_free()
			items.remove_at(i)


func clear_all() -> void:
	for it in items:
		if is_instance_valid(it["node"]):
			(it["node"] as Node).queue_free()
	items.clear()
