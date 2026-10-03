class_name ActorVisual
extends Node3D
## Procedural, stylized character models with code-driven animation.
## Models: humanoid (appearance presets), synthetic (Tav-7), drone,
## support drone, spider, turret, sentinel. Animation time only advances when
## the simulation advances, so tactical pause freezes every pose.
## Visuals never decide outcomes; they only display resolved results.

const OUTFITS := {
	"travel_jacket": Color("#6b4f3a"), "padded_vest": Color("#59606b"), "operator_coat": Color("#1f4a52"),
	"security_weave": Color("#253a5e"), "reclaimer_mesh": Color("#8a7232"), "breacher_plate": Color("#4b4f57"),
	"chassis_plating": Color("#7a7f86"), "none": Color("#4a4a52"),
}

var model := "humanoid"
var appearance: Dictionary = {}
var accent := Color("#e8823a")
var outfit := Color("#59606b")
var skin := Color("#c79a72")
var hair_col := Color("#15120f")

var body: Node3D
var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D
var hand_l: Node3D
var weapon_r: Node3D
var weapon_l: Node3D
var turret_head: Node3D
var spider_legs: Array[Node3D] = []
var ring: MeshInstance3D
var marker: MeshInstance3D
var stealth_alpha := 1.0

var t := 0.0
var move_speed := 0.0
var one_shot := ""
var one_shot_t := 0.0
var one_shot_len := 0.4
var downed := false
var down_amt := 0.0
var crouch := 0.0
var _mats: Array[StandardMaterial3D] = []
var _glows: Array[StandardMaterial3D] = []
var _glow_base: Array[float] = []

# Conversation staging (see present()). Real-time and visual-only.
var pres_on := false
var pres_look := Vector3.ZERO
var pres_has_look := false
var pres_talk := 0.0
var pres_gesture := ""
var pres_gesture_t := 0.0
var pres_gesture_len := 1.0
var _pt := 0.0
var _pres_yaw := 0.0
var _head_yaw := 0.0
var _glow_boost := 0.0

const GESTURE_LEN := {"nod": 0.8, "shake": 0.9, "shrug": 0.9, "gesture": 1.2, "point": 1.0, "look_away": 1.8}


func build(model_id: String, app: Dictionary, sheet: CharacterSheet = null) -> void:
	model = model_id
	appearance = app
	for c in get_children():
		c.queue_free()
	_mats.clear()
	_glows.clear()
	_glow_base.clear()
	spider_legs.clear()
	body = Node3D.new()
	add_child(body)
	accent = _app_color("accent", "accent", Color("#e8823a"))
	if app.has("accent_color"):
		accent = Color(String(app["accent_color"]))
	skin = _app_color("skin", "skin", Color("#c79a72"))
	hair_col = _app_color("hair_color", "hair_color", Color("#15120f"))
	outfit = OUTFITS.get(_armor_id(sheet), OUTFITS["none"])
	match model:
		"humanoid":
			_build_humanoid(false)
		"synthetic":
			_build_humanoid(true)
		"drone", "drone_support":
			_build_drone(model == "drone_support")
		"spider":
			_build_spider()
		"turret":
			_build_turret()
		"sentinel":
			_build_sentinel()
		_:
			_build_humanoid(false)
	_build_ring()
	if sheet != null:
		refresh_weapons(sheet)
	var sc: Array = [1.0, 1.0, 1.0]
	for b in DB.arr(DB.appearance, "body"):
		if b["id"] == app.get("body", "average"):
			sc = b["scale"]
	if model == "humanoid" or model == "synthetic":
		body.scale = Vector3(float(sc[0]), float(sc[1]), float(sc[2]))


func _armor_id(sheet: CharacterSheet) -> String:
	if sheet == null:
		return "none"
	var b: Variant = sheet.equipment.get("body", null)
	return String(b["id"]) if b != null else "none"


func _app_color(key: String, table: String, def: Color) -> Color:
	var v := String(appearance.get(key, ""))
	for e in DB.arr(DB.appearance, table):
		if e["id"] == v:
			return Color(String(e["color"]))
	return def


func _m(col: Color, rough: float = 0.6, metal: float = 0.1, emit: float = 0.0) -> StandardMaterial3D:
	# Per-actor materials so stealth translucency and hit flashes stay local.
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
		_glows.append(m)
		_glow_base.append(emit)
	_mats.append(m)
	return m


func _add(parent: Node3D, mi: MeshInstance3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	parent.add_child(mi)
	mi.position = pos
	mi.rotation_degrees = rot
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	n.position = pos
	return n


# ------------------------------------------------------------ humanoid
func _build_humanoid(synthetic: bool) -> void:
	var cloth := _m(outfit, 0.8, 0.05)
	var dark := _m(outfit.darkened(0.45), 0.85, 0.05)
	var acc := _m(accent, 0.4, 0.3, 1.4)
	var skin_m := _m(skin, 0.7, 0.0)
	var hair_m := _m(hair_col, 0.9, 0.0)
	var metal := _m(Color("#9aa3ad"), 0.35, 0.8)
	if synthetic:
		cloth = _m(Color("#8c939b"), 0.4, 0.7)
		dark = _m(Color("#3a3f46"), 0.5, 0.6)
		skin_m = _m(Color("#b7bcc2"), 0.35, 0.8)
	hips = _pivot(body, Vector3(0, 0.95, 0))
	torso = _pivot(hips, Vector3.ZERO)
	var tw := 0.36 if synthetic else 0.42
	_add(torso, MeshKit.box(Vector3(tw, 0.56, 0.24), cloth), Vector3(0, 0.3, 0))
	_add(torso, MeshKit.box(Vector3(tw * 0.9, 0.18, 0.22), dark), Vector3(0, 0.02, 0))
	# chest accent / insignia
	_add(torso, MeshKit.box(Vector3(0.06, 0.06, 0.02), acc), Vector3(0.1, 0.45, 0.125))
	if synthetic:
		_add(torso, MeshKit.sphere(0.07, acc, 10), Vector3(0, 0.38, 0.11))
		_add(torso, MeshKit.box(Vector3(0.08, 0.5, 0.08), dark), Vector3(0, 0.3, -0.13))
	var outfit_id := String(appearance.get("outfit", ""))
	if _mats.size() > 0 and (outfit == OUTFITS["operator_coat"] or outfit_id == "coat"):
		# long coat skirt
		_add(torso, MeshKit.box(Vector3(tw * 1.02, 0.5, 0.26), cloth), Vector3(0, -0.22, 0))
	if outfit == OUTFITS["security_weave"] or outfit == OUTFITS["reclaimer_mesh"] or outfit == OUTFITS["breacher_plate"]:
		_add(torso, MeshKit.box(Vector3(tw + 0.04, 0.22, 0.28), _m(outfit.lightened(0.15), 0.4, 0.5)), Vector3(0, 0.44, 0))
		_add(torso, MeshKit.box(Vector3(0.14, 0.08, 0.2), _m(outfit.lightened(0.2), 0.4, 0.5)), Vector3(0.26, 0.56, 0))
		_add(torso, MeshKit.box(Vector3(0.14, 0.08, 0.2), _m(outfit.lightened(0.2), 0.4, 0.5)), Vector3(-0.26, 0.56, 0))
	head = _pivot(torso, Vector3(0, 0.66, 0))
	_build_head(synthetic, skin_m, hair_m, acc, dark)
	var arm_r_ := 0.05 if synthetic else 0.06
	arm_l = _pivot(torso, Vector3(-tw * 0.5 - 0.06, 0.52, 0))
	arm_r = _pivot(torso, Vector3(tw * 0.5 + 0.06, 0.52, 0))
	for arm in [arm_l, arm_r]:
		_add(arm, MeshKit.capsule(arm_r_, 0.62, cloth if not synthetic else metal), Vector3(0, -0.3, 0))
		var hand := _pivot(arm, Vector3(0, -0.62, 0.02))
		_add(hand, MeshKit.sphere(0.055, skin_m, 8), Vector3.ZERO)
		if arm == arm_l:
			hand_l = hand
		else:
			hand_r = hand
	leg_l = _pivot(hips, Vector3(-0.11, 0.0, 0))
	leg_r = _pivot(hips, Vector3(0.11, 0.0, 0))
	for leg in [leg_l, leg_r]:
		_add(leg, MeshKit.capsule(0.075 if not synthetic else 0.06, 0.9, dark if not synthetic else metal), Vector3(0, -0.45, 0))
		_add(leg, MeshKit.box(Vector3(0.12, 0.08, 0.22), _m(Color("#22252b"))), Vector3(0, -0.9, 0.04))
	if synthetic:
		for leg in [leg_l, leg_r]:
			_add(leg, MeshKit.sphere(0.05, acc, 8), Vector3(0, -0.45, 0.05))


func _build_head(synthetic: bool, skin_m: StandardMaterial3D, hair_m: StandardMaterial3D, acc: StandardMaterial3D, dark: StandardMaterial3D) -> void:
	var shape := String(appearance.get("head", "round"))
	var hair := String(appearance.get("hair", "crop"))
	if synthetic:
		_add(head, MeshKit.capsule(0.11, 0.36, skin_m), Vector3(0, 0.14, 0))
		_add(head, MeshKit.box(Vector3(0.2, 0.05, 0.05), acc), Vector3(0, 0.17, 0.095))
		_add(head, MeshKit.cyl(0.008, 0.008, 0.22, acc), Vector3(0.07, 0.38, -0.02), Vector3(0, 0, -12))
		_add(head, MeshKit.sphere(0.02, acc, 6), Vector3(0.095, 0.49, -0.02))
		return
	_add(head, MeshKit.cyl(0.05, 0.055, 0.1, skin_m, 8), Vector3(0, -0.02, 0))
	match shape:
		"angular":
			_add(head, MeshKit.box(Vector3(0.2, 0.25, 0.22), skin_m), Vector3(0, 0.13, 0), Vector3(0, 45, 0)).scale = Vector3(0.75, 1, 0.75)
		"long":
			_add(head, MeshKit.capsule(0.1, 0.32, skin_m), Vector3(0, 0.14, 0))
		"square":
			_add(head, MeshKit.box(Vector3(0.21, 0.23, 0.22), skin_m), Vector3(0, 0.13, 0))
		_:
			_add(head, MeshKit.sphere(0.125, skin_m, 14), Vector3(0, 0.13, 0))
	var eye := _m(Color("#101216"), 0.3, 0.0)
	_add(head, MeshKit.box(Vector3(0.035, 0.022, 0.01), eye), Vector3(-0.045, 0.15, 0.115))
	_add(head, MeshKit.box(Vector3(0.035, 0.022, 0.01), eye), Vector3(0.045, 0.15, 0.115))
	match hair:
		"shaved":
			_add(head, MeshKit.sphere(0.128, hair_m, 12), Vector3(0, 0.16, -0.01)).scale = Vector3(1, 0.55, 1)
		"crop":
			_add(head, MeshKit.sphere(0.135, hair_m, 12), Vector3(0, 0.19, -0.015)).scale = Vector3(1, 0.65, 1)
		"swept":
			_add(head, MeshKit.sphere(0.135, hair_m, 12), Vector3(0, 0.2, -0.02)).scale = Vector3(1, 0.7, 1.05)
			_add(head, MeshKit.box(Vector3(0.22, 0.06, 0.12), hair_m), Vector3(0.02, 0.27, 0.06), Vector3(-20, 0, -12))
		"tail":
			_add(head, MeshKit.sphere(0.135, hair_m, 12), Vector3(0, 0.19, -0.02)).scale = Vector3(1, 0.68, 1)
			_add(head, MeshKit.capsule(0.04, 0.3, hair_m), Vector3(0, 0.05, -0.15), Vector3(25, 0, 0))
		"crest":
			_add(head, MeshKit.box(Vector3(0.05, 0.12, 0.28), hair_m), Vector3(0, 0.29, -0.01))
		"long":
			_add(head, MeshKit.sphere(0.14, hair_m, 12), Vector3(0, 0.18, -0.02)).scale = Vector3(1.05, 0.72, 1.05)
			_add(head, MeshKit.box(Vector3(0.26, 0.36, 0.08), hair_m), Vector3(0, 0.0, -0.11))


# ------------------------------------------------------------ machines
func _build_drone(support: bool) -> void:
	var shell := _m(Color("#3b4048"), 0.35, 0.8)
	var acc := _m(accent, 0.3, 0.2, 2.0)
	hips = _pivot(body, Vector3(0, 1.5, 0))
	torso = hips
	_add(hips, MeshKit.sphere(0.28, shell, 16), Vector3.ZERO)
	_add(hips, MeshKit.torus(0.3, 0.36, _m(Color("#2a2e34"), 0.4, 0.7)), Vector3.ZERO, Vector3(90, 0, 0))
	_add(hips, MeshKit.sphere(0.08, acc, 10), Vector3(0, 0.02, 0.25))
	for s in [-1, 1]:
		_add(hips, MeshKit.box(Vector3(0.36, 0.04, 0.16), shell), Vector3(s * 0.42, 0, -0.05), Vector3(0, 0, s * 12))
	if support:
		for s in [-1, 1]:
			_add(hips, MeshKit.cyl(0.01, 0.01, 0.35, acc), Vector3(s * 0.12, 0.38, 0), Vector3(0, 0, s * 15))
		_add(hips, MeshKit.torus(0.18, 0.21, acc), Vector3(0, -0.3, 0))
	head = hips
	hand_r = _pivot(hips, Vector3(0, -0.1, 0.3))


func _build_spider() -> void:
	var shell := _m(Color("#33383f"), 0.35, 0.8)
	var acc := _m(accent, 0.3, 0.2, 2.0)
	hips = _pivot(body, Vector3(0, 0.45, 0))
	torso = hips
	_add(hips, MeshKit.box(Vector3(0.5, 0.18, 0.62), shell), Vector3.ZERO)
	_add(hips, MeshKit.box(Vector3(0.28, 0.12, 0.2), shell), Vector3(0, 0.05, 0.38))
	_add(hips, MeshKit.sphere(0.05, acc, 8), Vector3(-0.07, 0.08, 0.48))
	_add(hips, MeshKit.sphere(0.05, acc, 8), Vector3(0.07, 0.08, 0.48))
	for i in 4:
		var side := -1 if i < 2 else 1
		var fz := 0.2 if i % 2 == 0 else -0.2
		var leg := _pivot(hips, Vector3(side * 0.25, 0, fz))
		_add(leg, MeshKit.box(Vector3(0.4, 0.05, 0.05), shell), Vector3(side * 0.2, 0.08, 0), Vector3(0, 0, side * -25))
		_add(leg, MeshKit.box(Vector3(0.05, 0.5, 0.05), shell), Vector3(side * 0.4, -0.12, 0), Vector3(0, 0, side * 15))
		spider_legs.append(leg)
	head = hips
	hand_r = _pivot(hips, Vector3(0, 0, 0.5))


func _build_turret() -> void:
	var shell := _m(Color("#3b4048"), 0.35, 0.8)
	var acc := _m(accent, 0.3, 0.2, 2.0)
	hips = _pivot(body, Vector3(0, 0, 0))
	torso = hips
	_add(hips, MeshKit.cyl(0.35, 0.45, 0.9, shell), Vector3(0, 0.45, 0))
	turret_head = _pivot(hips, Vector3(0, 1.05, 0))
	_add(turret_head, MeshKit.box(Vector3(0.55, 0.32, 0.5), shell), Vector3.ZERO)
	_add(turret_head, MeshKit.cyl(0.05, 0.05, 0.7, _m(Color("#22252b"), 0.3, 0.9)), Vector3(0.12, 0, 0.45), Vector3(90, 0, 0))
	_add(turret_head, MeshKit.cyl(0.05, 0.05, 0.7, _m(Color("#22252b"), 0.3, 0.9)), Vector3(-0.12, 0, 0.45), Vector3(90, 0, 0))
	_add(turret_head, MeshKit.sphere(0.06, acc, 8), Vector3(0, 0.1, 0.26))
	head = turret_head
	hand_r = _pivot(turret_head, Vector3(0, 0, 0.8))


func _build_sentinel() -> void:
	var shell := _m(Color("#41464f"), 0.3, 0.8)
	var dark := _m(Color("#25282e"), 0.4, 0.7)
	var acc := _m(accent, 0.3, 0.2, 2.2)
	hips = _pivot(body, Vector3(0, 1.1, 0))
	torso = _pivot(hips, Vector3.ZERO)
	_add(torso, MeshKit.box(Vector3(0.9, 0.8, 0.6), shell), Vector3(0, 0.45, 0))
	_add(torso, MeshKit.box(Vector3(0.5, 0.12, 0.05), acc), Vector3(0, 0.62, 0.31))
	head = _pivot(torso, Vector3(0, 0.95, 0.05))
	_add(head, MeshKit.box(Vector3(0.36, 0.22, 0.34), dark), Vector3.ZERO)
	_add(head, MeshKit.box(Vector3(0.26, 0.05, 0.02), acc), Vector3(0, 0.02, 0.175))
	arm_l = _pivot(torso, Vector3(-0.58, 0.7, 0))
	arm_r = _pivot(torso, Vector3(0.58, 0.7, 0))
	for arm in [arm_l, arm_r]:
		_add(arm, MeshKit.box(Vector3(0.24, 0.7, 0.26), shell), Vector3(0, -0.3, 0))
		_add(arm, MeshKit.cyl(0.07, 0.09, 0.5, dark), Vector3(0, -0.6, 0.18), Vector3(90, 0, 0))
	hand_r = _pivot(arm_r, Vector3(0, -0.6, 0.45))
	hand_l = _pivot(arm_l, Vector3(0, -0.6, 0.45))
	leg_l = _pivot(hips, Vector3(-0.25, 0, 0))
	leg_r = _pivot(hips, Vector3(0.25, 0, 0))
	for leg in [leg_l, leg_r]:
		_add(leg, MeshKit.box(Vector3(0.26, 1.1, 0.3), dark), Vector3(0, -0.55, 0))
		_add(leg, MeshKit.box(Vector3(0.32, 0.12, 0.45), shell), Vector3(0, -1.05, 0.06))


# ------------------------------------------------------------ weapons
func refresh_weapons(sheet: CharacterSheet) -> void:
	if weapon_r != null:
		weapon_r.queue_free()
		weapon_r = null
	if weapon_l != null:
		weapon_l.queue_free()
		weapon_l = null
	if hand_r == null:
		return
	if model in ["drone", "drone_support", "spider", "turret", "sentinel"]:
		return
	var wm: Variant = sheet.weapon_inst("main")
	if wm != null:
		weapon_r = _weapon_mesh(String(wm["id"]))
		hand_r.add_child(weapon_r)
	var wo: Variant = sheet.weapon_inst("off")
	if wo != null and hand_l != null:
		weapon_l = _weapon_mesh(String(wo["id"]))
		hand_l.add_child(weapon_l)


func _weapon_mesh(id: String) -> Node3D:
	var root := Node3D.new()
	var w: Dictionary = DB.dict(DB.item(id), "weapon")
	var cat := String(w.get("category", "melee"))
	var metal := MeshKit.mat(Color("#8b939c"), 0.3, 0.85)
	var grip := MeshKit.mat(Color("#2a2d33"), 0.7, 0.2)
	if bool(w.get("energy_blade", false)):
		var a := MeshKit.unshaded(Color("#ffd27a"))
		var core := MeshKit.unshaded(Color("#fff6e0"))
		_add(root, MeshKit.cyl(0.025, 0.025, 0.2, grip, 8), Vector3(0, 0, 0), Vector3(90, 0, 0))
		_add(root, MeshKit.cyl(0.035, 0.035, 0.04, metal, 8), Vector3(0, 0, 0.1), Vector3(90, 0, 0))
		_add(root, MeshKit.cyl(0.022, 0.03, 0.85, a, 8), Vector3(0, 0, 0.55), Vector3(90, 0, 0))
		_add(root, MeshKit.cyl(0.01, 0.012, 0.85, core, 6), Vector3(0, 0, 0.55), Vector3(90, 0, 0))
	elif cat == "melee":
		var hands := int(w.get("hands", 1))
		match id:
			"shear_glaive":
				_add(root, MeshKit.cyl(0.02, 0.02, 1.5, grip, 6), Vector3(0, 0, 0.3), Vector3(90, 0, 0))
				_add(root, MeshKit.box(Vector3(0.03, 0.18, 0.4), metal), Vector3(0, 0.06, 1.1))
			"breach_maul":
				_add(root, MeshKit.cyl(0.025, 0.025, 1.1, grip, 6), Vector3(0, 0, 0.3), Vector3(90, 0, 0))
				_add(root, MeshKit.box(Vector3(0.18, 0.18, 0.3), metal), Vector3(0, 0, 0.85))
			"stun_baton", "shock_spanner":
				_add(root, MeshKit.cyl(0.025, 0.03, 0.55, grip, 8), Vector3(0, 0, 0.25), Vector3(90, 0, 0))
				_add(root, MeshKit.sphere(0.04, MeshKit.unshaded(Color("#7fd0ff")), 6), Vector3(0, 0, 0.53))
			"vibro_knife":
				_add(root, MeshKit.box(Vector3(0.015, 0.04, 0.28), metal), Vector3(0, 0, 0.18))
			_:
				_add(root, MeshKit.box(Vector3(0.02, 0.05, 0.8), metal), Vector3(0, 0, 0.45))
				_add(root, MeshKit.box(Vector3(0.12, 0.02, 0.03), grip), Vector3(0, 0, 0.05))
		if hands == 2:
			root.position = Vector3(0, 0, -0.1)
	elif cat == "pistol":
		_add(root, MeshKit.box(Vector3(0.05, 0.1, 0.06), grip), Vector3(0, -0.03, 0))
		_add(root, MeshKit.box(Vector3(0.05, 0.06, 0.26), metal), Vector3(0, 0.03, 0.1))
		if String(w.get("dtype", "")) == "ion":
			_add(root, MeshKit.box(Vector3(0.06, 0.02, 0.1), MeshKit.unshaded(Color("#7fd0ff"))), Vector3(0, 0.07, 0.12))
	elif cat == "rifle":
		_add(root, MeshKit.box(Vector3(0.06, 0.1, 0.7), metal), Vector3(0, 0.02, 0.25))
		_add(root, MeshKit.box(Vector3(0.05, 0.12, 0.08), grip), Vector3(0, -0.05, 0.0))
		_add(root, MeshKit.box(Vector3(0.05, 0.08, 0.2), grip), Vector3(0, 0, -0.15))
	return root


# ------------------------------------------------------------ markers
func _build_ring() -> void:
	ring = MeshKit.torus(0.42, 0.5, MeshKit.unshaded(Color(1, 1, 1, 0.9)))
	add_child(ring)
	ring.position = Vector3(0, 0.03, 0)
	ring.visible = false
	marker = MeshKit.prism(Vector3(0.22, 0.22, 0.05), MeshKit.unshaded(Color(1, 1, 1)))
	add_child(marker)
	marker.rotation_degrees = Vector3(180, 0, 0)
	marker.position = Vector3(0, 2.25 if model != "spider" else 1.2, 0)
	marker.visible = false


## kind: "" (none), "ally", "controlled", "hostile", "neutral"
func set_selection(kind: String) -> void:
	if ring == null:
		return
	ring.visible = kind != ""
	marker.visible = kind == "hostile" or kind == "controlled"
	var col := Color("#5fd38a")
	match kind:
		"controlled":
			col = Color("#7fd0ff")
		"hostile":
			col = Color("#ff5a4a")
		"neutral":
			col = Color("#f2c26b")
	ring.material_override = MeshKit.unshaded(col)
	marker.material_override = MeshKit.unshaded(col)


func set_stealth(on: bool) -> void:
	var a := 0.45 if on else 1.0
	if absf(a - stealth_alpha) < 0.01:
		return
	stealth_alpha = a
	for m in _mats:
		var c := m.albedo_color
		c.a = a
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else BaseMaterial3D.TRANSPARENCY_DISABLED


func flash(col: Color) -> void:
	for m in _mats:
		if _glows.has(m):
			continue
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.9
	_flash_left = 0.12


var _flash_left := 0.0


func _update_flash(dt: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= dt
	if _flash_left <= 0.0:
		for m in _mats:
			if not _glows.has(m):
				m.emission_enabled = false


# ------------------------------------------------------------ animation
func play(kind: String, length: float = 0.45) -> void:
	one_shot = kind
	one_shot_t = 0.0
	one_shot_len = length


func set_downed(v: bool) -> void:
	downed = v


## Advance animation by sim dt. speed = current ground speed.
func animate(dt: float, speed: float) -> void:
	t += dt
	_update_flash(dt)
	move_speed = lerpf(move_speed, speed, clampf(dt * 10.0, 0.0, 1.0))
	if one_shot != "":
		one_shot_t += dt
		if one_shot_t >= one_shot_len:
			one_shot = ""
	down_amt = move_toward(down_amt, 1.0 if downed else 0.0, dt * 2.5)
	_pose()


## Applies the pose for the current animation state (no time advance).
func _pose() -> void:
	match model:
		"humanoid", "synthetic":
			_anim_humanoid()
		"drone", "drone_support":
			_anim_drone()
		"spider":
			_anim_spider()
		"turret":
			_anim_turret()
		"sentinel":
			_anim_humanoid()


# ------------------------------------------------------------ presentation
## Conversation staging, ticked in real time while the simulation is frozen
## (DialogueStage), and the finish of a knock-down fall during a pause. Only
## this node and its child pivots move: never the Actor's position or
## facing, and nothing the simulation reads. `idle` keeps the breathing and
## one-shot clocks running (conversations); without it only a fall settles.
## Returns whether it still needs ticks.
func present(dt: float, idle: bool = true) -> bool:
	_pt += dt
	if idle:
		animate(dt, 0.0)
	else:
		down_amt = move_toward(down_amt, 1.0 if downed else 0.0, dt * 2.5)
		_pose()
	var bodied := model in ["humanoid", "synthetic", "sentinel"]
	var want_body := 0.0
	var want_head := 0.0
	if pres_has_look and is_inside_tree() and down_amt < 0.05 and model != "turret":
		var par := get_parent() as Node3D
		var d := pres_look - (par.global_position if par != null else global_position)
		var local: Vector3 = (par.global_transform.basis.inverse() * d) if par != null else d
		var ang := rad_to_deg(atan2(local.x, local.z))
		if absf(ang) > 25.0 or not bodied:
			want_body = clampf(ang, -100.0, 100.0)
		want_head = clampf(ang - want_body, -45.0, 45.0) if bodied else 0.0
	_pres_yaw = move_toward(_pres_yaw, want_body, dt * 220.0)
	_head_yaw = move_toward(_head_yaw, want_head, dt * 260.0)
	rotation.y = deg_to_rad(_pres_yaw)
	var hx := 0.0
	var hy := _head_yaw
	var hz := 0.0
	var talking := pres_talk > 0.0
	pres_talk = maxf(0.0, pres_talk - dt)
	if talking and bodied and down_amt < 0.05:
		hx += sin(_pt * 7.5) * 3.0
		hz += sin(_pt * 3.1) * 2.0
		if arm_r != null:
			# A beat gesture every 1.6 s while the line lasts.
			var beat := fmod(_pt, 1.6) / 1.6
			if beat < 0.45:
				var a := sin(beat / 0.45 * PI)
				arm_r.rotation_degrees.x -= 32.0 * a
				arm_r.rotation_degrees.z += 14.0 * a
				if torso != null:
					torso.rotation_degrees.y += 4.0 * a
	if pres_gesture != "":
		pres_gesture_t += dt
		var p := clampf(pres_gesture_t / pres_gesture_len, 0.0, 1.0)
		var s := sin(p * PI)
		if bodied and down_amt < 0.05:
			match pres_gesture:
				"nod":
					hx += 12.0 * absf(sin(p * TAU))
				"shake":
					hy += 20.0 * sin(p * PI * 3.0) * s
				"shrug":
					hz += 6.0 * s
					if arm_l != null and arm_r != null:
						arm_l.rotation_degrees += Vector3(-12.0 * s, 0, -16.0 * s)
						arm_r.rotation_degrees += Vector3(-12.0 * s, 0, 16.0 * s)
				"gesture":
					if arm_l != null and arm_r != null:
						arm_l.rotation_degrees += Vector3(-45.0 * s, 0, -10.0 * s)
						arm_r.rotation_degrees += Vector3(-45.0 * s, 0, 10.0 * s)
				"point":
					if arm_r != null:
						arm_r.rotation_degrees.x = lerpf(arm_r.rotation_degrees.x, -85.0, s)
				"look_away":
					hy += -40.0 * s
					hx += 8.0 * s
		if p >= 1.0:
			pres_gesture = ""
	if bodied and head != null:
		head.rotation_degrees = Vector3(hx, hy, hz)
	if _glow_boost > 0.0:
		_glow_boost = maxf(0.0, _glow_boost - dt * 6.0)
		_apply_glow()
	return pres_on or (downed and down_amt < 0.999)


func look_at_point(p: Vector3) -> void:
	pres_look = p
	pres_has_look = true


func talk(sec: float) -> void:
	pres_talk = maxf(pres_talk, sec)


func gesture(kind: String) -> void:
	if not GESTURE_LEN.has(kind):
		return
	pres_gesture = kind
	pres_gesture_t = 0.0
	pres_gesture_len = float(GESTURE_LEN[kind])


## A synthetic's accent lights brighten with each syllable it speaks.
func pulse_glow(amp: float) -> void:
	_glow_boost = maxf(_glow_boost, clampf(amp, 0.0, 1.0) * 1.5)
	_apply_glow()


func _apply_glow() -> void:
	for i in mini(_glows.size(), _glow_base.size()):
		_glows[i].emission_energy_multiplier = _glow_base[i] * (1.0 + _glow_boost)


## Ends conversation staging and returns to the simulation's pose.
func clear_presentation() -> void:
	pres_on = false
	pres_has_look = false
	pres_talk = 0.0
	pres_gesture = ""
	_pres_yaw = 0.0
	_head_yaw = 0.0
	_glow_boost = 0.0
	rotation.y = 0.0
	if model in ["humanoid", "synthetic", "sentinel"] and head != null:
		head.rotation_degrees = Vector3.ZERO
	_apply_glow()
	_pose()


func _os_phase() -> float:
	return clampf(one_shot_t / maxf(0.01, one_shot_len), 0.0, 1.0)


func _anim_humanoid() -> void:
	if hips == null:
		return
	var walk := clampf(move_speed / 4.5, 0.0, 1.4)
	var cyc := t * (4.0 + walk * 6.0)
	var swing := sin(cyc) * 38.0 * walk
	var bob := absf(sin(cyc)) * 0.04 * walk
	var breathe := sin(t * 2.0) * 0.01
	hips.position.y = (1.1 if model == "sentinel" else 0.95) + bob + breathe - crouch * 0.18
	if leg_l:
		leg_l.rotation_degrees.x = swing - crouch * 25.0
		leg_r.rotation_degrees.x = -swing - crouch * 25.0
	if arm_l:
		arm_l.rotation_degrees = Vector3(-swing * 0.7, 0, -6)
		arm_r.rotation_degrees = Vector3(swing * 0.7, 0, 6)
	if torso:
		torso.rotation_degrees = Vector3(walk * 6.0 + crouch * 18.0, 0, 0)
	var p := _os_phase()
	match one_shot:
		"melee":
			if arm_r:
				var a := sin(p * PI)
				arm_r.rotation_degrees = Vector3(-60.0 - 80.0 * a, 0, 20.0 * a)
				torso.rotation_degrees.y = -25.0 * a
		"ranged":
			if arm_r:
				arm_r.rotation_degrees = Vector3(-85.0 + 10.0 * sin(p * PI * 3.0), 0, 0)
				if arm_l:
					arm_l.rotation_degrees = Vector3(-70.0, 0, 20)
		"cast":
			if arm_r:
				var c := sin(p * PI)
				arm_r.rotation_degrees = Vector3(-90.0 * c, 0, 15)
				arm_l.rotation_degrees = Vector3(-90.0 * c, 0, -15)
		"hit":
			if torso:
				torso.rotation_degrees.x = -14.0 * sin(p * PI)
		"use":
			if arm_r:
				arm_r.rotation_degrees = Vector3(-45.0 * sin(p * PI), 0, 0)
	if down_amt > 0.0:
		body.rotation_degrees.x = -88.0 * down_amt
		body.position.y = 0.15 * down_amt
	else:
		body.rotation_degrees.x = 0.0
		body.position.y = 0.0


func _anim_drone() -> void:
	if hips == null:
		return
	hips.position.y = 1.5 + sin(t * 2.4) * 0.08 - down_amt * 1.25
	hips.rotation_degrees.z = sin(t * 1.3) * 4.0 + down_amt * 35.0
	if one_shot == "ranged" or one_shot == "cast":
		hips.rotation_degrees.x = -10.0 * sin(_os_phase() * PI)
	elif one_shot == "hit":
		hips.position.x = sin(_os_phase() * PI * 4.0) * 0.06


func _anim_spider() -> void:
	if hips == null:
		return
	var walk := clampf(move_speed / 4.0, 0.0, 1.5)
	for i in spider_legs.size():
		var ph := t * 12.0 + (PI if i % 2 == 0 else 0.0)
		spider_legs[i].rotation_degrees.y = sin(ph) * 22.0 * walk
	hips.position.y = 0.45 + absf(sin(t * 12.0)) * 0.03 * walk - down_amt * 0.3
	if one_shot == "melee":
		hips.rotation_degrees.x = -20.0 * sin(_os_phase() * PI)
	else:
		hips.rotation_degrees.x = 0.0
	hips.rotation_degrees.z = down_amt * 60.0


func _anim_turret() -> void:
	if turret_head == null:
		return
	if one_shot == "ranged":
		turret_head.position.z = -0.08 * sin(_os_phase() * PI)
	turret_head.rotation_degrees.x = down_amt * 40.0
