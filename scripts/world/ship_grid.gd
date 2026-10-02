class_name ShipGrid
extends RefCounted
## Navigation, collision and line-of-sight grid for the ship (1 m cells).
## Walkable floor comes from area rectangles and door cells; closed doors and
## props mark cells solid. Pathfinding uses AStarGrid2D; line of sight samples
## the segment through cells. Also tracks explored cells for the map.

var min_x := 0
var min_z := 0
var w := 1
var h := 1
var walk := PackedByteArray()
var solid := PackedByteArray()
var los_block := PackedByteArray()
var area_of := PackedByteArray()
var area_names: Array[String] = [""]
var explored := PackedByteArray()
var shadow := PackedByteArray()
var astar := AStarGrid2D.new()


func setup(layout: Dictionary) -> void:
	var g: Dictionary = layout.get("grid", {})
	min_x = int(g.get("min_x", 0))
	min_z = int(g.get("min_z", 0))
	w = int(g.get("w", 64))
	h = int(g.get("h", 64))
	var n := w * h
	walk.resize(n)
	walk.fill(0)
	solid.resize(n)
	solid.fill(0)
	los_block.resize(n)
	los_block.fill(0)
	area_of.resize(n)
	area_of.fill(0)
	shadow.resize(n)
	shadow.fill(0)
	explored.resize(n)
	explored.fill(0)
	area_names = [""]
	var areas: Dictionary = layout.get("areas", {})
	for aid in areas.keys():
		area_names.append(String(aid))
		var ai := area_names.size() - 1
		for r in areas[aid].get("rects", []):
			for x in range(int(r[0]), int(r[2])):
				for z in range(int(r[1]), int(r[3])):
					var c := Vector2i(x - min_x, z - min_z)
					if in_bounds(c):
						walk[idx(c)] = 1
						area_of[idx(c)] = ai
		for r in areas[aid].get("shadows", []):
			for x in range(int(r[0]), int(r[2])):
				for z in range(int(r[1]), int(r[3])):
					var c2 := Vector2i(x - min_x, z - min_z)
					if in_bounds(c2):
						shadow[idx(c2)] = 1
	for d in layout.get("doors", []):
		for cell in d.get("cells", []):
			var c3 := Vector2i(int(cell[0]) - min_x, int(cell[1]) - min_z)
			if in_bounds(c3):
				walk[idx(c3)] = 1
				var aa := area_names.find(String(d.get("a", "")))
				area_of[idx(c3)] = maxi(0, aa)
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for i in n:
		if walk[i] == 0:
			astar.set_point_solid(Vector2i(i % w, i / w), true)


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x) - min_x, floori(p.z) - min_z)


func world_cell(x: int, z: int) -> Vector2i:
	return Vector2i(x - min_x, z - min_z)


func center_of(c: Vector2i) -> Vector3:
	return Vector3(c.x + min_x + 0.5, 0.0, c.y + min_z + 0.5)


func passable(c: Vector2i) -> bool:
	return in_bounds(c) and walk[idx(c)] == 1 and solid[idx(c)] == 0


func see_through(c: Vector2i) -> bool:
	return in_bounds(c) and walk[idx(c)] == 1 and los_block[idx(c)] == 0


func set_blocked(cells: Array, blocked: bool, blocks_los: bool = true) -> void:
	for cell in cells:
		var c: Vector2i = cell if cell is Vector2i else Vector2i(int(cell[0]) - min_x, int(cell[1]) - min_z)
		if not in_bounds(c):
			continue
		var i := idx(c)
		solid[i] = 1 if blocked else 0
		if blocks_los:
			los_block[i] = 1 if blocked else 0
		astar.set_point_solid(c, blocked or walk[i] == 0)


## Doors: open = free; closed but unlocked = blocks movement and sight but
## stays plannable (doors open automatically on approach); locked = solid.
func set_door(cells: Array, open: bool, locked: bool) -> void:
	for cell in cells:
		var c := Vector2i(int(cell[0]) - min_x, int(cell[1]) - min_z)
		if not in_bounds(c):
			continue
		var i := idx(c)
		solid[i] = 0 if open else 1
		los_block[i] = 0 if open else 1
		astar.set_point_solid(c, locked and not open)


func area_at(p: Vector3) -> String:
	var c := cell_of(p)
	if not in_bounds(c):
		return ""
	return area_names[area_of[idx(c)]]


func is_shadow(p: Vector3) -> bool:
	var c := cell_of(p)
	return in_bounds(c) and shadow[idx(c)] == 1


## True if a circle of `radius` at p overlaps only passable cells.
func can_stand(p: Vector3, radius: float = 0.3) -> bool:
	for off in [Vector2(-radius, -radius), Vector2(radius, -radius), Vector2(-radius, radius), Vector2(radius, radius), Vector2.ZERO]:
		if not passable(cell_of(p + Vector3(off.x, 0, off.y))):
			return false
	return true


## Slide-move used for direct (WASD) control.
func try_move(p: Vector3, delta: Vector3, radius: float = 0.3) -> Vector3:
	var np := p + delta
	if can_stand(np, radius):
		return np
	var nx := p + Vector3(delta.x, 0, 0)
	if can_stand(nx, radius):
		return nx
	var nz := p + Vector3(0, 0, delta.z)
	if can_stand(nz, radius):
		return nz
	return p


func nearest_passable(p: Vector3, max_r: int = 6) -> Vector3:
	var c := cell_of(p)
	if passable(c):
		return Vector3(p.x, 0, p.z)
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var cc := c + Vector2i(dx, dz)
				if passable(cc):
					return center_of(cc)
	return Vector3(p.x, 0, p.z)


## Line of sight between two points (eye height ignored: walls are full height).
func los(a: Vector3, b: Vector3) -> bool:
	var d := Vector2(b.x - a.x, b.z - a.z)
	var dist := d.length()
	if dist < 0.01:
		return true
	var steps := int(ceil(dist / 0.25))
	var ca := cell_of(a)
	var cb := cell_of(b)
	for i in range(1, steps):
		var t := float(i) / steps
		var c := cell_of(Vector3(a.x + d.x * t, 0, a.z + d.y * t))
		if c == ca or c == cb:
			continue
		if not see_through(c):
			return false
	return true


## Known hazards: AI paths treat these cells as expensive and path smoothing
## never cuts through them, so companions route around a visible live plate.
var avoid := PackedByteArray()


func set_avoid(cells: Array, on: bool) -> void:
	if avoid.size() != w * h:
		avoid.resize(w * h)
		avoid.fill(0)
	for cell in cells:
		var c: Vector2i = cell
		if not in_bounds(c):
			continue
		avoid[idx(c)] = 1 if on else 0
		astar.set_point_weight_scale(c, 12.0 if on else 1.0)


func is_avoided(c: Vector2i) -> bool:
	return avoid.size() == w * h and in_bounds(c) and avoid[idx(c)] == 1


## Clear walking line (used for path smoothing), with width margin.
func walk_clear(a: Vector3, b: Vector3, radius: float = 0.3) -> bool:
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var dist := d.length()
	if dist < 0.01:
		return true
	var perp := Vector3(-d.z, 0, d.x).normalized() * radius
	var steps := int(ceil(dist / 0.25))
	var start_avoid := is_avoided(cell_of(a))
	for i in range(0, steps + 1):
		var t := float(i) / steps
		var p := a + d * t
		if not passable(cell_of(p)) or not passable(cell_of(p + perp)) or not passable(cell_of(p - perp)):
			return false
		if not start_avoid and is_avoided(cell_of(p)):
			return false
	return true


## doors_block: closed doors count as walls (enemies don't open doors, so a
## closed door breaks pursuit).
func path(from: Vector3, to: Vector3, allow_partial: bool = true, doors_block: bool = false) -> PackedVector3Array:
	var out := PackedVector3Array()
	var cf := cell_of(from)
	var ct := cell_of(to)
	if not passable(cf):
		cf = cell_of(nearest_passable(from))
	if not in_bounds(ct):
		return out
	if not passable(ct):
		ct = cell_of(nearest_passable(to))
	if cf == ct:
		out.append(Vector3(to.x, 0, to.z) if passable(cell_of(to)) else center_of(ct))
		return out
	var ids: Array[Vector2i] = astar.get_id_path(cf, ct, allow_partial)
	if ids.is_empty():
		return out
	if doors_block:
		for c in ids:
			if c != cf and solid[idx(c)] == 1:
				return out
	var pts: Array[Vector3] = []
	for c in ids:
		pts.append(center_of(c))
	if passable(cell_of(to)) and ids[ids.size() - 1] == ct:
		pts[pts.size() - 1] = Vector3(to.x, 0, to.z)
	# String-pulling smoothing.
	var cur := Vector3(from.x, 0, from.z)
	var i := 0
	while i < pts.size():
		var far := i
		for j in range(pts.size() - 1, i, -1):
			if walk_clear(cur, pts[j]):
				far = j
				break
		out.append(pts[far])
		cur = pts[far]
		i = far + 1
	return out


func path_length(p: PackedVector3Array, from: Vector3) -> float:
	var l := 0.0
	var cur := from
	for q in p:
		l += cur.distance_to(q)
		cur = q
	return l


func reveal(p: Vector3, radius: float) -> int:
	var c := cell_of(p)
	var r := int(ceil(radius))
	var n := 0
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			if dx * dx + dz * dz > r * r:
				continue
			var cc := c + Vector2i(dx, dz)
			if in_bounds(cc) and walk[idx(cc)] == 1 and explored[idx(cc)] == 0:
				explored[idx(cc)] = 1
				n += 1
	return n
