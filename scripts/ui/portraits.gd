class_name Portraits
extends Node
## Renders head-and-shoulders portraits of characters into SubViewports so
## appearance choices show up in the HUD, dialogue and menus.

var _cache: Dictionary = {}


func texture_for(sheet: CharacterSheet, size: int = 96) -> Texture2D:
	var key := "%s|%s|%d" % [sheet.uid, JSON.stringify(sheet.appearance) + str(sheet.equipment.get("body", {})), size]
	if _cache.has(key):
		return (_cache[key] as SubViewport).get_texture()
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var vis := ActorVisual.new()
	root.add_child(vis)
	var model := String(sheet.appearance.get("model", "humanoid"))
	vis.build(model, sheet.appearance, sheet)
	vis.animate(0.0, 0.0)
	var cam := Camera3D.new()
	var hy := 1.62
	var dist := 0.95
	match model:
		"drone", "drone_support":
			hy = 1.5
			dist = 1.4
		"spider":
			hy = 0.5
			dist = 1.4
		"turret":
			hy = 1.0
			dist = 1.8
		"sentinel":
			hy = 2.0
			dist = 2.2
	cam.position = Vector3(0.25, hy + 0.05, dist)
	cam.fov = 40
	root.add_child(cam)
	cam.look_at(Vector3(0, hy - 0.05, 0), Vector3.UP)
	cam.current = true
	var l := OmniLight3D.new()
	l.position = Vector3(0.6, hy + 0.6, 1.2)
	l.light_energy = 1.6
	l.omni_range = 5
	root.add_child(l)
	var l2 := OmniLight3D.new()
	l2.position = Vector3(-0.8, hy, -0.6)
	l2.light_color = Color("#e8823a")
	l2.light_energy = 0.9
	l2.omni_range = 4
	root.add_child(l2)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#6a7080")
	e.ambient_light_energy = 0.6
	env.environment = e
	root.add_child(env)
	_cache[key] = vp
	# Render a few frames then freeze to save GPU time.
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		if is_instance_valid(vp):
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE)
	return vp.get_texture()


func clear_cache() -> void:
	for k in _cache.keys():
		(_cache[k] as Node).queue_free()
	_cache.clear()
