extends Node
## Versioned save files with safe writes (write temp -> verify -> rotate backup
## -> rename). Corrupt or missing files are reported, never fatal. Developer
## presets are not save slots; they live in data/dev_presets.json.

const DIR := "user://saves/"
const MANUAL_SLOTS := 8
const AUTOSAVE_SLOTS := 3

var save_root := DIR
var last_error := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(save_root)


func slot_path(slot: String) -> String:
	return save_root + slot + ".json"


## "" if saving is allowed right now, otherwise a player-facing reason.
func block_reason() -> String:
	if Game.state == null or Game.state.player() == null:
		return "No game in progress."
	if Game.world != null and Game.world.has_method("save_block_reason"):
		return String(Game.world.save_block_reason())
	if Game.world == null:
		return "Saving is only available on the ship."
	return ""


func save_game(slot: String, label: String = "") -> Dictionary:
	var reason := block_reason()
	if reason != "":
		return {"ok": false, "reason": reason}
	if Game.world != null and Game.world.has_method("sync_to_state"):
		Game.world.sync_to_state()
	var st := Game.state
	var p := st.player()
	var header := {
		"schema": GameState.SCHEMA_VERSION, "game_version": ProjectSettings.get_setting("application/config/version", "0"),
		"slot": slot, "label": label if label != "" else slot, "time": Time.get_datetime_string_from_system(false, true),
		"unix": Time.get_unix_time_from_system(), "area": st.area,
		"area_name": String(DB.dict(DB.dict(DB.layout, "areas"), st.area).get("name", st.area)),
		"player": p.display_name, "level": p.level, "class": String(DB.klass(p.class_id).get("name", "")),
		"play_time": st.play_time, "dev": st.dev_mode,
	}
	return write_file(slot, {"header": header, "state": st.to_dict()})


func write_file(slot: String, data: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(save_root)
	var path := slot_path(slot)
	var tmp := path + ".tmp"
	var txt := JSON.stringify(data, "", false)
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "Cannot write %s (%s)." % [tmp, error_string(FileAccess.get_open_error())]
		return {"ok": false, "reason": last_error}
	f.store_string(txt)
	f.flush()
	f.close()
	# Verify the temp file parses before replacing the old save.
	var check: Variant = JSON.parse_string(FileAccess.get_file_as_string(tmp))
	if typeof(check) != TYPE_DICTIONARY:
		DirAccess.remove_absolute(tmp)
		last_error = "Save verification failed."
		return {"ok": false, "reason": last_error}
	if FileAccess.file_exists(path):
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			DirAccess.remove_absolute(bak)
		DirAccess.rename_absolute(path, bak)
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		last_error = "Could not finalize save (%s)." % error_string(err)
		return {"ok": false, "reason": last_error}
	Events.post("game_saved", {"slot": slot})
	return {"ok": true, "reason": "", "path": path}


func read_file(slot: String) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "Empty slot.", "missing": true}
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY or not (data as Dictionary).has("state") or not (data as Dictionary).has("header"):
		# Try the backup copy before giving up.
		var bak := path + ".bak"
		if FileAccess.file_exists(bak):
			var bd: Variant = JSON.parse_string(FileAccess.get_file_as_string(bak))
			if typeof(bd) == TYPE_DICTIONARY and (bd as Dictionary).has("state"):
				return {"ok": true, "reason": "Recovered from backup (the main file was corrupt).", "data": bd, "recovered": true}
		return {"ok": false, "reason": "Save file is corrupt.", "corrupt": true}
	var schema := int(data["header"].get("schema", 0))
	if schema > GameState.SCHEMA_VERSION:
		return {"ok": false, "reason": "Save is from a newer version (schema %d)." % schema}
	if schema < GameState.SCHEMA_VERSION:
		data = migrate(data, schema)
	return {"ok": true, "reason": "", "data": data}


func migrate(data: Dictionary, from_schema: int) -> Dictionary:
	# Schema 1 is the first release; future migrations chain here.
	data["header"]["schema"] = GameState.SCHEMA_VERSION
	return data


func load_game(slot: String) -> Dictionary:
	var r := read_file(slot)
	if not bool(r["ok"]):
		return r
	var st := GameState.from_dict(r["data"]["state"])
	Game.set_state(st)
	Events.post("game_loaded", {"slot": slot})
	return {"ok": true, "reason": String(r.get("reason", "")), "state": st}


func list_slots() -> Array:
	var out: Array = []
	var slots: Array[String] = ["quicksave"]
	for i in AUTOSAVE_SLOTS:
		slots.append("autosave_%d" % (i + 1))
	for i in MANUAL_SLOTS:
		slots.append("slot_%d" % (i + 1))
	slots.append("end_of_intro")
	for s in slots:
		var r := read_file(s)
		var row := {"slot": s, "ok": r["ok"], "reason": r.get("reason", "")}
		if bool(r["ok"]):
			row["header"] = r["data"]["header"]
		row["missing"] = bool(r.get("missing", false))
		row["corrupt"] = bool(r.get("corrupt", false))
		out.append(row)
	return out


func has_any_save() -> bool:
	for row in list_slots():
		if bool(row["ok"]):
			return true
	return false


func latest_slot() -> String:
	var best := ""
	var best_t := -1.0
	for row in list_slots():
		if bool(row["ok"]):
			var t := float(row["header"].get("unix", 0))
			if t > best_t:
				best_t = t
				best = String(row["slot"])
	return best


func quicksave() -> Dictionary:
	return save_game("quicksave", "Quicksave")


## Rotating checkpoint autosaves.
func autosave(label: String) -> Dictionary:
	if block_reason() != "":
		return {"ok": false, "reason": block_reason()}
	var oldest := ""
	var oldest_t := INF
	for i in AUTOSAVE_SLOTS:
		var s := "autosave_%d" % (i + 1)
		var r := read_file(s)
		if not bool(r["ok"]):
			oldest = s
			break
		var t := float(r["data"]["header"].get("unix", 0))
		if t < oldest_t:
			oldest_t = t
			oldest = s
	var res := save_game(oldest, "Autosave: " + label)
	if bool(res["ok"]):
		Events.toast("Checkpoint saved: " + label, "save")
	return res


func delete_slot(slot: String) -> void:
	for p in [slot_path(slot), slot_path(slot) + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
