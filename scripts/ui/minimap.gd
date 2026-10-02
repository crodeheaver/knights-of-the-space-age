class_name MiniMap
extends Control
## Explored-cell map. Used small in the HUD and full-size in the map panel.
## Only cells the party has seen are drawn; markers use shape + colour.

var world: World
var scale_px := 3.0
var full := false
var center_override := Vector2.INF


func _draw() -> void:
	if world == null:
		return
	var g := world.grid
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.05, 0.9))
	var lead := world.controlled()
	var c := Vector2(lead.position.x, lead.position.z) if lead != null else Vector2.ZERO
	if full:
		# Fit the whole explored ship.
		scale_px = minf(size.x / float(g.w), size.y / float(g.h))
		c = Vector2(g.min_x + g.w * 0.5, g.min_z + g.h * 0.5)
	var origin := size * 0.5 - c * scale_px
	var floor_col := Color(0.32, 0.36, 0.4)
	var wall_col := Color(0.6, 0.55, 0.45)
	for z in g.h:
		for x in g.w:
			var i := z * g.w + x
			if g.explored[i] == 0:
				continue
			var wp := Vector2(x + g.min_x, z + g.min_z)
			var sp := origin + wp * scale_px
			if sp.x < -scale_px or sp.y < -scale_px or sp.x > size.x or sp.y > size.y:
				continue
			var col := floor_col if g.solid[i] == 0 else wall_col.darkened(0.3)
			draw_rect(Rect2(sp, Vector2(scale_px, scale_px)), col)
	# doors
	for o in world.objects.values():
		var wo: WorldObject = o
		var sp2 := origin + Vector2(wo.center.x, wo.center.z) * scale_px
		if not Rect2(Vector2.ZERO, size).has_point(sp2):
			continue
		var cell := g.cell_of(wo.center)
		if not g.in_bounds(cell) or g.explored[g.idx(cell)] == 0:
			continue
		var r := maxf(2.0, scale_px * 0.7)
		match wo.kind:
			"door":
				draw_rect(Rect2(sp2 - Vector2(r, r), Vector2(r, r) * 2), Color("#ff6a5a") if wo.is_locked() else Color("#7fd0ff"), false, 1.5)
			"workbench", "medstation", "vendor", "muster", "minigame":
				draw_circle(sp2, r, Color("#5fd38a"))
			"container", "corpse", "wreck":
				if not bool(wo.st().get("looted", false)) and wo.is_visible_obj():
					draw_rect(Rect2(sp2 - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), Color("#f2c26b"))
			"mine", "hazard":
				if wo.is_detected() and wo.mesh_root.visible:
					draw_line(sp2 + Vector2(-r, -r), sp2 + Vector2(r, r), Color("#ff5a4a"), 1.5)
					draw_line(sp2 + Vector2(-r, r), sp2 + Vector2(r, -r), Color("#ff5a4a"), 1.5)
	for a in world.actors.values():
		var aa: Actor = a
		if aa.sheet.dead:
			continue
		var p := origin + aa.pos2() * scale_px
		if not Rect2(Vector2.ZERO, size).has_point(p):
			continue
		var cell2 := g.cell_of(aa.position)
		if aa.role != "party" and (not g.in_bounds(cell2) or g.explored[g.idx(cell2)] == 0):
			continue
		var rr := maxf(3.0, scale_px * 0.9)
		if aa.role == "party":
			var col2 := Color("#7fd0ff") if aa == lead else Color("#5fd38a")
			draw_circle(p, rr, col2)
			draw_line(p, p + aa.facing * rr * 2.2, col2, 2.0)
		elif lead != null and world.hostile(lead, aa) and (aa.alert or world.grid.los(lead.position, aa.position)):
			var tri := PackedVector2Array([p + Vector2(0, -rr * 1.3), p + Vector2(rr, rr), p + Vector2(-rr, rr)])
			draw_colored_polygon(tri, Color("#ff5a4a"))
		elif aa.role == "npc":
			draw_rect(Rect2(p - Vector2(rr, rr) * 0.7, Vector2(rr, rr) * 1.4), Color("#f2c26b"))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.45, 0.38, 0.28), false, 1.0)
