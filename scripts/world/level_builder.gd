class_name LevelBuilder
extends RefCounted
## Builds the ship's static geometry from data/ship_layout.json: floors,
## ceilings, merged wall meshes with glowing trim, camera-collision bodies,
## lights, props (which also block grid cells) and landmark signage.
## Returns what the Atmosphere animates: the environment, per-area lights,
## lamp and trim materials, spark emitters and animated props.

const WALL_H := 3.2
## Camera collision layers: walls (1) and tall props (2, follow camera only).
const LAYER_WALLS := 1
const LAYER_PROPS := 2


static func build(world: Node3D, layout: Dictionary, grid: ShipGrid) -> Dictionary:
	var info := {"env": null, "lights": {}, "lamps": {}, "trims": {}, "sparks": [], "reactor": [], "cores": [], "windows": []}
	var root := Node3D.new()
	root.name = "Level"
	world.add_child(root)
	info["env"] = _environment(world, layout)
	var areas: Dictionary = layout.get("areas", {})
	# Floors per area.
	for aid in areas.keys():
		var a: Dictionary = areas[aid]
		var st := MeshKit.st_begin()
		var fcol := Color(String(a.get("floor", "#2a2f3a")))
		for r in a.get("rects", []):
			var x0 := float(r[0])
			var z0 := float(r[1])
			var x1 := float(r[2])
			var z1 := float(r[3])
			MeshKit.add_box(st, Vector3((x0 + x1) * 0.5, -0.05, (z0 + z1) * 0.5), Vector3(x1 - x0, 0.1, z1 - z0), fcol)
		var mi := MeshInstance3D.new()
		mi.name = "Floor_" + String(aid)
		mi.mesh = st.commit()
		mi.material_override = MeshKit.floor_material()
		root.add_child(mi)
	# Door cell floors.
	var dst := MeshKit.st_begin()
	for d in layout.get("doors", []):
		for c in d.get("cells", []):
			var acol := Color(String(DB.dict(areas, String(d.get("a", ""))).get("floor", "#2a2f3a")))
			MeshKit.add_box(dst, Vector3(float(c[0]) + 0.5, -0.05, float(c[1]) + 0.5), Vector3(1, 0.1, 1), acol.darkened(0.2))
	var dmi := MeshInstance3D.new()
	dmi.mesh = dst.commit()
	dmi.material_override = MeshKit.floor_material()
	root.add_child(dmi)
	_ceilings(root, layout)
	_walls(root, layout, grid, info)
	_lights(root, layout, info)
	for p in layout.get("props", []):
		_prop(root, p, grid, info)
	for s in layout.get("signs", []):
		_sign(root, s)
	return info


## Ceilings over every area and doorway, with darker beams every 4 m. They
## face down only, so the tactical camera above sees straight through them.
static func _ceilings(root: Node3D, layout: Dictionary) -> void:
	var areas: Dictionary = layout.get("areas", {})
	var st := MeshKit.st_begin()
	for aid in areas.keys():
		var a: Dictionary = areas[aid]
		var col := Color(String(a.get("wall", "#3a4150"))).darkened(0.15)
		for r in a.get("rects", []):
			var x0 := float(r[0])
			var z0 := float(r[1])
			var x1 := float(r[2])
			var z1 := float(r[3])
			MeshKit.add_down_quad(st, x0, z0, x1, z1, WALL_H, col)
			var bx := x0 + 2.0
			while bx < x1 - 0.5:
				MeshKit.add_down_quad(st, bx - 0.18, z0, bx + 0.18, z1, WALL_H - 0.09, col.darkened(0.45))
				bx += 4.0
	for d in layout.get("doors", []):
		var col2 := Color(String(DB.dict(areas, String(d.get("a", ""))).get("wall", "#3a4150"))).darkened(0.3)
		for c in d.get("cells", []):
			MeshKit.add_down_quad(st, float(c[0]), float(c[1]), float(c[0]) + 1.0, float(c[1]) + 1.0, WALL_H, col2)
	var mi := MeshInstance3D.new()
	mi.name = "Ceilings"
	mi.mesh = st.commit()
	mi.material_override = MeshKit.vc_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


static func _environment(world: Node3D, layout: Dictionary) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#05070b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#56627a")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.95
	# Haze per area (Atmosphere blends density and colour on area changes).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.0
	env.fog_light_color = Color("#3a4250")
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_energy = 0.32
	sun.light_color = Color("#b9c6e0")
	sun.shadow_enabled = false
	world.add_child(sun)
	return env


static func _walls(root: Node3D, layout: Dictionary, grid: ShipGrid, info: Dictionary) -> void:
	var areas: Dictionary = layout.get("areas", {})
	var per_area := {}
	var trim_st := {}
	var wall_cells := PackedByteArray()
	wall_cells.resize(grid.w * grid.h)
	for z in grid.h:
		for x in grid.w:
			var c := Vector2i(x, z)
			if grid.walk[grid.idx(c)] == 1:
				continue
			var owner := ""
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					var n := c + Vector2i(dx, dz)
					if grid.in_bounds(n) and grid.walk[grid.idx(n)] == 1:
						owner = grid.area_names[grid.area_of[grid.idx(n)]]
			if owner == "":
				continue
			wall_cells[grid.idx(c)] = 1
			if not per_area.has(owner):
				per_area[owner] = MeshKit.st_begin()
				trim_st[owner] = MeshKit.st_begin()
			var a: Dictionary = areas.get(owner, {})
			var wcol := Color(String(a.get("wall", "#3a4150")))
			var center := grid.center_of(c) + Vector3(0, WALL_H * 0.5, 0)
			MeshKit.add_box(per_area[owner], center, Vector3(1.0, WALL_H, 1.0), wcol)
			var acc := Color(String(a.get("accent", "#e8823a")))
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n2: Vector2i = c + off
				if grid.in_bounds(n2) and grid.walk[grid.idx(n2)] == 1:
					var fo := Vector3(off.x, 0, off.y) * 0.51
					var size := Vector3(0.04 if off.x != 0 else 1.0, 0.05, 1.0 if off.x != 0 else 0.04)
					MeshKit.add_box(trim_st[owner], grid.center_of(c) + fo + Vector3(0, 2.42, 0), size, acc, false)
					MeshKit.add_box(trim_st[owner], grid.center_of(c) + fo + Vector3(0, 0.12, 0), size * Vector3(1, 0.6, 1), acc.darkened(0.55), false)
	for aid in per_area.keys():
		var mi := MeshInstance3D.new()
		mi.name = "Walls_" + String(aid)
		mi.mesh = (per_area[aid] as SurfaceTool).commit()
		mi.material_override = MeshKit.wall_material()
		root.add_child(mi)
		var ti := MeshInstance3D.new()
		ti.mesh = (trim_st[aid] as SurfaceTool).commit()
		# Each area's trim has its own material so alerts can tint it alone.
		var tm := MeshKit.glow_material().duplicate() as StandardMaterial3D
		ti.material_override = tm
		root.add_child(ti)
		info["trims"][aid] = tm
	# Camera collision: merge horizontal runs of wall cells.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	for z in grid.h:
		var x := 0
		while x < grid.w:
			if wall_cells[z * grid.w + x] == 1:
				var x0 := x
				while x < grid.w and wall_cells[z * grid.w + x] == 1:
					x += 1
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(x - x0, WALL_H, 1.0)
				cs.shape = bs
				cs.position = Vector3(grid.min_x + (x0 + x) * 0.5, WALL_H * 0.5, grid.min_z + z + 0.5)
				body.add_child(cs)
			else:
				x += 1


static func _lights(root: Node3D, layout: Dictionary, info: Dictionary) -> void:
	var areas: Dictionary = layout.get("areas", {})
	for aid in areas.keys():
		var a: Dictionary = areas[aid]
		var lcol := Color(String(a.get("light", "#ffe2b8")))
		var area_lights: Array = []
		# One lamp material per area, so alerts and flicker change it alone.
		var lamp_mat := MeshKit.unshaded(lcol.lightened(0.3)).duplicate() as StandardMaterial3D
		info["lights"][aid] = area_lights
		info["lamps"][aid] = lamp_mat
		var energy := float(a.get("light_energy", 1.1))
		var lights: Array = a.get("lights", [])
		if lights.is_empty():
			for r in a.get("rects", []):
				var x0 := float(r[0])
				var z0 := float(r[1])
				var x1 := float(r[2])
				var z1 := float(r[3])
				var nx := maxi(1, int(round((x1 - x0) / 8.0)))
				var nz := maxi(1, int(round((z1 - z0) / 8.0)))
				for i in nx:
					for j in nz:
						lights.append({"pos": [x0 + (x1 - x0) * (i + 0.5) / nx, 2.9, z0 + (z1 - z0) * (j + 0.5) / nz]})
		for l in lights:
			var ol := OmniLight3D.new()
			var p: Array = l["pos"]
			ol.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
			ol.light_color = Color(String(l.get("color", lcol.to_html())))
			ol.light_energy = float(l.get("energy", energy))
			ol.omni_range = float(l.get("range", 10.0))
			ol.omni_attenuation = 1.2
			ol.shadow_enabled = false
			root.add_child(ol)
			area_lights.append(ol)
			var lamp := MeshKit.box(Vector3(0.6, 0.06, 0.6), lamp_mat if not l.has("color") else MeshKit.unshaded(ol.light_color.lightened(0.3)))
			lamp.position = ol.position + Vector3(0, 0.25, 0)
			root.add_child(lamp)


static func _prop(root: Node3D, p: Dictionary, grid: ShipGrid, info: Dictionary = {}) -> void:
	var t := String(p.get("t", "crate"))
	var pos: Array = p.get("p", [0, 0])
	var sz: Array = p.get("s", [1, 1])
	var h := float(p.get("h", 1.0))
	var col := Color(String(p.get("c", "#4a515c")))
	var n := Node3D.new()
	n.position = Vector3(float(pos[0]), 0, float(pos[1]))
	n.rotation_degrees.y = float(p.get("rot", 0))
	root.add_child(n)
	var w := float(sz[0])
	var d := float(sz[1])
	var m := MeshKit.mat(col, 0.6, 0.35)
	var dark := MeshKit.mat(col.darkened(0.45), 0.6, 0.4)
	match t:
		"crate":
			_pb(n, Vector3(w * 0.96, h, d * 0.96), Vector3(0, h * 0.5, 0), m)
			_pb(n, Vector3(w, 0.06, d), Vector3(0, h - 0.1, 0), dark)
			_pb(n, Vector3(w, 0.06, d), Vector3(0, 0.12, 0), dark)
		"table":
			_pb(n, Vector3(w, 0.06, d), Vector3(0, h, 0), m)
			_pb(n, Vector3(0.12, h, 0.12), Vector3(0, h * 0.5, 0), dark)
		"bunk":
			_pb(n, Vector3(w, 0.35, d), Vector3(0, 0.3, 0), dark)
			_pb(n, Vector3(w * 0.95, 0.12, d * 0.9), Vector3(0, 0.53, 0), MeshKit.mat(Color("#8a8f98"), 0.9, 0.0))
			_pb(n, Vector3(w * 0.3, 0.1, d * 0.6), Vector3(w * 0.3, 0.64, 0), MeshKit.mat(Color("#c8ccd2"), 0.9, 0.0))
			if h > 1.2:
				_pb(n, Vector3(w, 0.2, d), Vector3(0, 1.5, 0), dark)
				_pb(n, Vector3(0.08, 1.6, 0.08), Vector3(-w * 0.45, 0.8, d * 0.45), dark)
		"bench":
			_pb(n, Vector3(w, 0.45, d), Vector3(0, 0.225, 0), m)
		"counter":
			_pb(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), m)
			_pb(n, Vector3(w + 0.1, 0.06, d + 0.1), Vector3(0, h, 0), MeshKit.mat(Color("#c9cdd3"), 0.3, 0.6))
		"pillar":
			_pb(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), m)
			_pb(n, Vector3(w + 0.04, 0.08, d + 0.04), Vector3(0, h * 0.75, 0), MeshKit.unshaded(Color(String(p.get("g", "#e8823a")))))
		"pipe":
			var pi := MeshKit.cyl(float(p.get("r", 0.15)), float(p.get("r", 0.15)), w, m, 10)
			pi.rotation_degrees = Vector3(0, 0, 90)
			pi.position = Vector3(0, h, 0)
			n.add_child(pi)
		"archive":
			var shell := MeshKit.cyl(w * 0.45, w * 0.48, h, MeshKit.mat(Color(0.3, 0.6, 0.65, 0.28), 0.1, 0.3), 14)
			shell.position = Vector3(0, h * 0.5, 0)
			n.add_child(shell)
			var core := MeshKit.cyl(w * 0.22, w * 0.22, h * 0.82, MeshKit.mat(Color(String(p.get("g", "#3fb6b0"))), 0.3, 0.0, 2.2), 10)
			core.position = Vector3(0, h * 0.5, 0)
			n.add_child(core)
			if info.has("cores"):
				info["cores"].append(core)
			var cap := MeshKit.cyl(w * 0.5, w * 0.5, 0.12, dark, 14)
			cap.position = Vector3(0, h, 0)
			n.add_child(cap)
			var base := MeshKit.cyl(w * 0.52, w * 0.55, 0.25, dark, 14)
			base.position = Vector3(0, 0.12, 0)
			n.add_child(base)
		"reactor":
			var rc := MeshKit.cyl(w * 0.5, w * 0.5, h, MeshKit.mat(Color("#20262d"), 0.3, 0.8), 24)
			rc.position = Vector3(0, h * 0.5, 0)
			n.add_child(rc)
			var band_mat := MeshKit.unshaded(Color(String(p.get("g", "#e8823a")))).duplicate() as StandardMaterial3D
			for i in 3:
				var band := MeshKit.torus(w * 0.48, w * 0.54, band_mat)
				band.position = Vector3(0, 1.0 + i * 1.2, 0)
				n.add_child(band)
				if info.has("reactor"):
					info["reactor"].append(band)
			_collider(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0))
		"debris":
			for i in 3:
				var b := _pb(n, Vector3(w * (0.6 - i * 0.12), 0.3 + i * 0.1, d * (0.5 + i * 0.1)), Vector3((i - 1) * 0.3, 0.2 + i * 0.12, (i - 1) * 0.2), dark if i % 2 == 0 else m)
				b.rotation_degrees = Vector3(i * 9.0, i * 31.0, i * -7.0)
		"window":
			_pb(n, Vector3(w, h, 0.1), Vector3(0, float(p.get("y", 1.6)), 0), MeshKit.unshaded(Color("#0d1a33")))
			var stars: Array = []
			for i in 12:
				var star := _pb(n, Vector3(0.04, 0.04, 0.02), Vector3(-w * 0.45 + fmod(i * 0.73, 1.0) * w * 0.9, float(p.get("y", 1.6)) - h * 0.4 + fmod(i * 0.37, 1.0) * h * 0.8, 0.06), MeshKit.unshaded(Color("#e8eefc")))
				star.scale = Vector3.ONE
				stars.append(star)
			var planet := MeshKit.sphere(h * 0.3, MeshKit.unshaded(Color("#c9773a")), 16)
			planet.position = Vector3(w * 0.25, float(p.get("y", 1.6)), 0.07)
			planet.scale = Vector3(1, 1, 0.1)
			n.add_child(planet)
			if info.has("windows"):
				info["windows"].append({"stars": stars, "w": w})
		"craft":
			n.name = "Petrel"
			_craft(n, w, d, col)
		"pod":
			var pd := MeshKit.capsule(w * 0.45, h, MeshKit.mat(Color("#cfd4da"), 0.3, 0.3))
			pd.rotation_degrees = Vector3(90, 0, 0)
			pd.position = Vector3(0, 0.6, 0)
			n.add_child(pd)
			_pb(n, Vector3(w * 0.5, 0.05, h * 0.4), Vector3(0, 1.0 + w * 0.2, 0), MeshKit.unshaded(Color("#7fd0ff")))
		"railing":
			_pb(n, Vector3(w, 0.05, 0.05), Vector3(0, 1.0, 0), MeshKit.mat(Color("#9aa3ad"), 0.3, 0.8))
			_pb(n, Vector3(w, 0.05, 0.05), Vector3(0, 0.55, 0), MeshKit.mat(Color("#9aa3ad"), 0.3, 0.8))
		"crane":
			_pb(n, Vector3(w, 0.4, 0.5), Vector3(0, h, 0), MeshKit.mat(Color("#d8a43a"), 0.5, 0.5))
			var hook := MeshKit.cyl(0.03, 0.03, h - 1.6, dark)
			hook.position = Vector3(0, (h + 1.6) * 0.5, 0)
			n.add_child(hook)
			_pb(n, Vector3(1.6, 1.2, 1.2), Vector3(0, 1.6, 0), MeshKit.mat(Color("#5b4a36"), 0.8, 0.1))
		"machine":
			_pb(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), m)
			for i in 3:
				_pb(n, Vector3(w * 0.2, 0.06, 0.02), Vector3(-w * 0.3 + i * w * 0.3, h * 0.7, d * 0.5 + 0.01), MeshKit.unshaded(Color(String(p.get("g", "#5fd38a")))))
		"glow":
			_pb(n, Vector3(w, h, d), Vector3(0, float(p.get("y", 0.0)) + h * 0.5, 0), MeshKit.unshaded(col))
		"chair":
			_pb(n, Vector3(0.5, 0.45, 0.5), Vector3(0, 0.225, 0), m)
			_pb(n, Vector3(0.5, 0.6, 0.08), Vector3(0, 0.75, -0.21), m)
		"sparks":
			var ps := CPUParticles3D.new()
			ps.amount = 16
			ps.lifetime = 0.6
			ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			ps.emission_sphere_radius = 0.2
			ps.direction = Vector3(0, -1, 0)
			ps.spread = 50.0
			ps.initial_velocity_min = 1.0
			ps.initial_velocity_max = 2.5
			ps.gravity = Vector3(0, -6, 0)
			ps.scale_amount_min = 0.03
			ps.scale_amount_max = 0.06
			var qm := QuadMesh.new()
			qm.size = Vector2(0.5, 0.5)
			qm.material = MeshKit.unshaded(Color("#ffd27a"))
			ps.mesh = qm
			ps.position = Vector3(0, h, 0)
			n.add_child(ps)
			if info.has("sparks"):
				info["sparks"].append(ps)
		_:
			_pb(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0), m)
	if bool(p.get("solid", not (t in ["pipe", "window", "glow", "railing", "sparks", "crane"]))):
		var cells: Array = []
		var hw := w * 0.5
		var hd := d * 0.5
		var rot := int(round(float(p.get("rot", 0)))) % 180
		if rot == 90:
			var tmp := hw
			hw = hd
			hd = tmp
		for x in range(floori(float(pos[0]) - hw + 0.01), ceili(float(pos[0]) + hw - 0.01)):
			for z in range(floori(float(pos[1]) - hd + 0.01), ceili(float(pos[1]) + hd - 0.01)):
				cells.append([x, z])
		grid.set_blocked(cells, true, bool(p.get("los", h >= 1.4)))
		# Tall props keep the close follow camera out of them.
		if h >= 1.4 and t != "reactor":
			_collider(n, Vector3(w, h, d), Vector3(0, h * 0.5, 0))


static func _collider(n: Node3D, size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER_PROPS
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	body.add_child(cs)
	n.add_child(body)


static func _pb(n: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshKit.box(size, m)
	mi.position = pos
	n.add_child(mi)
	return mi


static func _craft(n: Node3D, w: float, d: float, col: Color) -> void:
	var hull := MeshKit.mat(Color("#c9cdd3"), 0.35, 0.6)
	var dark := MeshKit.mat(Color("#2b3038"), 0.4, 0.6)
	var body := MeshKit.capsule(d * 0.32, w, hull)
	body.rotation_degrees = Vector3(0, 0, 90)
	body.position = Vector3(0, 1.6, 0)
	body.scale = Vector3(1, 1, 0.75)
	n.add_child(body)
	var cockpit := MeshKit.sphere(d * 0.25, MeshKit.unshaded(Color("#7fd0ff")), 14)
	cockpit.position = Vector3(w * 0.42, 1.95, 0)
	cockpit.scale = Vector3(1, 0.5, 0.8)
	n.add_child(cockpit)
	for s in [-1, 1]:
		var wing := MeshKit.box(Vector3(w * 0.4, 0.12, d * 0.5), hull)
		wing.position = Vector3(-w * 0.1, 1.2, s * d * 0.5)
		n.add_child(wing)
		var eng := MeshKit.cyl(0.35, 0.45, 1.2, dark)
		eng.rotation_degrees = Vector3(0, 0, 90)
		eng.position = Vector3(-w * 0.45, 1.3, s * d * 0.3)
		n.add_child(eng)
		var glow := MeshKit.cyl(0.3, 0.3, 0.05, MeshKit.unshaded(col))
		glow.rotation_degrees = Vector3(0, 0, 90)
		glow.position = Vector3(-w * 0.45 - 0.62, 1.3, s * d * 0.3)
		n.add_child(glow)
	var ramp := MeshKit.box(Vector3(1.6, 0.1, 2.4), dark)
	ramp.position = Vector3(0, 0.5, d * 0.45)
	ramp.rotation_degrees = Vector3(-22, 0, 0)
	n.add_child(ramp)
	var stripe := MeshKit.box(Vector3(w * 0.8, 0.12, 0.02), MeshKit.unshaded(Color("#e8823a")))
	stripe.position = Vector3(0, 1.8, d * 0.24)
	n.add_child(stripe)


static func _sign(root: Node3D, s: Dictionary) -> void:
	var l := Label3D.new()
	l.text = String(s.get("text", ""))
	var p: Array = s.get("p", [0, 2.6, 0])
	l.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	l.rotation_degrees.y = float(s.get("rot", 0))
	l.font_size = int(s.get("size", 64))
	l.pixel_size = 0.008
	l.modulate = Color(String(s.get("c", "#f2c26b")))
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.double_sided = false
	root.add_child(l)
