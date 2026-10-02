extends Node
## CPU benchmark of the simulation (no rendering cost): world build time and
## per-step cost of World.sim_step in exploration and in combat, for several
## developer-preset stages. Prints a JSON report.
## Run: godot --headless --path . res://tools/godot/bench.tscn
## Rendering frame rates must be measured on real GPU hardware; under Xvfb
## the renderer falls back to software rasterization (llvmpipe).

const DT := 1.0 / 30.0


func _ready() -> void:
	var report := {"godot": Engine.get_version_info()["string"], "cpu": OS.get_processor_name(), "cores": OS.get_processor_count(), "stages": {}}
	for pid in ["jump_checkpoint", "jump_engineering", "jump_archive", "jump_bay"]:
		DevTools.apply_preset(pid)
		var t0 := Time.get_ticks_usec()
		var w := World.new()
		w.manual_step = true
		add_child(w)
		await get_tree().process_frame
		var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var explore := _measure(w, 300)
		# Typical fight: the nearest pending encounter only.
		var near := ""
		var nd := INF
		for eid in DB.encounters.keys():
			if w.encounter_state(String(eid))["state"] != "pending":
				continue
			var sp: Array = DB.encounters[eid].get("spawns", [])
			if sp.is_empty():
				continue
			var pos: Array = sp[0]["pos"]
			var d := w.controlled().position.distance_to(Vector3(float(pos[0]), 0, float(pos[1])))
			if d < nd:
				nd = d
				near = String(eid)
		var typical := {}
		if near != "":
			w.spawn_encounter(near)
			w.alert_encounter(near)
			typical = _measure(w, 300)
			typical["encounter"] = near
			typical["actors"] = w.actors.size()
		# Then start every encounter on the deck to stress combat.
		for eid in DB.encounters.keys():
			if w.encounter_state(String(eid))["state"] == "pending":
				w.spawn_encounter(String(eid))
				w.alert_encounter(String(eid))
		var actors := w.actors.size()
		var combat := _measure(w, 300)
		report["stages"][pid] = {"world_build_ms": snappedf(build_ms, 0.1), "actors": actors, "explore_step_ms": explore, "typical_combat_step_ms": typical, "stress_combat_step_ms": combat, "combat_active": w.combat.active}
		w.queue_free()
		await get_tree().process_frame
	print("BENCH ", JSON.stringify(report))
	get_tree().quit(0)


func _measure(w: World, n: int) -> Dictionary:
	var samples: Array[float] = []
	for i in n:
		var t := Time.get_ticks_usec()
		w.sim_step(DT)
		samples.append((Time.get_ticks_usec() - t) / 1000.0)
	samples.sort()
	var sum := 0.0
	for s in samples:
		sum += s
	return {"mean": snappedf(sum / n, 0.001), "p95": snappedf(samples[int(n * 0.95)], 0.001), "max": snappedf(samples[n - 1], 0.001)}
