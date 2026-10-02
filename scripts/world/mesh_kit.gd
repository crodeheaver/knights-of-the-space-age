class_name MeshKit
extends RefCounted
## Procedural geometry helpers: merged vertex-coloured box meshes for the
## ship structure and cached materials for props and characters.

static var _mats: Dictionary = {}
static var _floor_mat: ShaderMaterial
static var _wall_mat: ShaderMaterial
static var _vc_mat: StandardMaterial3D
static var _glow_mat: StandardMaterial3D


static func st_begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(b)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(a)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_color(col)
	st.set_normal(n)
	st.add_vertex(d)


## Axis-aligned box centered at c with size s. skip_bottom avoids hidden faces.
static func add_box(st: SurfaceTool, c: Vector3, s: Vector3, col: Color, skip_bottom: bool = true) -> void:
	var h := s * 0.5
	var x0 := c.x - h.x
	var x1 := c.x + h.x
	var y0 := c.y - h.y
	var y1 := c.y + h.y
	var z0 := c.z - h.z
	var z1 := c.z + h.z
	# top
	_quad(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
	if not skip_bottom:
		_quad(st, Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3.DOWN, col)
	# +x
	_quad(st, Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3.RIGHT, col)
	# -x
	_quad(st, Vector3(x0, y1, z0), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x0, y0, z0), Vector3.LEFT, col)
	# +z
	_quad(st, Vector3(x0, y1, z1), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x0, y0, z1), Vector3.BACK, col)
	# -z
	_quad(st, Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3.FORWARD, col)


static func floor_material() -> ShaderMaterial:
	if _floor_mat == null:
		_floor_mat = ShaderMaterial.new()
		_floor_mat.shader = load("res://assets/shaders/floor.gdshader")
	return _floor_mat


static func wall_material() -> ShaderMaterial:
	if _wall_mat == null:
		_wall_mat = ShaderMaterial.new()
		_wall_mat.shader = load("res://assets/shaders/wall.gdshader")
	return _wall_mat


static func vc_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.roughness = 0.7
		_vc_mat.metallic = 0.2
	return _vc_mat


static func glow_material() -> StandardMaterial3D:
	if _glow_mat == null:
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.vertex_color_use_as_albedo = true
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _glow_mat


static func mat(col: Color, rough: float = 0.6, metal: float = 0.2, emit: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [col.to_html(), rough, metal, emit]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	if col.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func unshaded(col: Color) -> StandardMaterial3D:
	var key := "u|" + col.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if col.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


static func box(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	return mi


static func cyl(r_top: float, r_bot: float, height: float, m: Material, segs: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = height
	cm.radial_segments = segs
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	return mi


static func sphere(r: float, m: Material, segs: int = 16) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = segs
	sm.rings = maxi(4, segs / 2)
	mi.mesh = sm
	mi.material_override = m
	return mi


static func capsule(r: float, height: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = height
	cm.radial_segments = 12
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = m
	return mi


static func prism(size: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.material_override = m
	return mi


static func torus(inner: float, outer: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = inner
	tm.outer_radius = outer
	tm.rings = 24
	tm.ring_segments = 8
	mi.mesh = tm
	mi.material_override = m
	return mi
