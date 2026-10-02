extends TestCase
## Save/load round trips, safe writes, corruption handling, schema checks.


func before_each() -> void:
	Saves.save_root = "user://test_saves/"
	DirAccess.make_dir_recursive_absolute(Saves.save_root)


func _populated() -> GameState:
	var st := fresh_state("operative")
	Game.recruit("iona")
	Game.recruit("tav7")
	st.set_flag("ward_opened", true)
	st.add_influence("iona", 7, "k1", "reason one")
	st.add_alignment(-12, "k2", "reason two")
	st.grant_xp(300, "k3", "test")
	st.inventory.add("ion_grenade", 3)
	st.inventory.credits = 777
	var p := st.player()
	StatusRules.apply(p, "surge", 9.0)
	p.cooldowns["power:sway"] = 4.5
	st.queues["player"] = [{"qid": 3, "type": "attack", "target": "e1"}]
	st.world["chk_blast_door"] = {"locked": false, "open": true}
	st.enemies["e1"] = {"template": "picket_drone", "state": "dead"}
	st.dice.d20()
	st.dice.d20()
	return st


func test_gamestate_round_trip() -> void:
	var st := _populated()
	var d := st.to_dict()
	var json := JSON.stringify(d)
	var back := GameState.from_dict(JSON.parse_string(json))
	var d2 := back.to_dict()
	d2["item_uid_counter"] = d["item_uid_counter"]
	# Compare after one JSON normalization (ints become floats in JSON).
	assert_eq(JSON.stringify(JSON.parse_string(JSON.stringify(d2))), JSON.stringify(JSON.parse_string(json)), "lossless JSON round trip")
	assert_eq(back.get_char("player").get_status("surge")["remaining"], 9.0)
	assert_eq(int(back.influence["iona"]), 57)
	assert_eq(back.alignment, -12)
	assert_eq(back.inventory.credits, 777)
	assert_true(back.claimed("xp:k3"), "ledger persists so rewards are not repeated")
	assert_eq(back.grant_xp(300, "k3", "again"), 0)


func test_rng_state_persists() -> void:
	var st := _populated()
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_dict()))
	var a := [st.dice.d20(), st.dice.d20(), st.dice.d20()]
	var back := GameState.from_dict(d)
	var b := [back.dice.d20(), back.dice.d20(), back.dice.d20()]
	assert_eq(a, b, "reloading reproduces the same upcoming rolls")


func test_file_save_load_and_backup() -> void:
	var st := _populated()
	var r := Saves.write_file("slot_t", {"header": {"schema": GameState.SCHEMA_VERSION}, "state": st.to_dict()})
	assert_true(r["ok"], String(r.get("reason", "")))
	st.inventory.credits = 5
	r = Saves.write_file("slot_t", {"header": {"schema": GameState.SCHEMA_VERSION}, "state": st.to_dict()})
	assert_true(FileAccess.file_exists(Saves.slot_path("slot_t") + ".bak"), "previous save kept as backup")
	var lr := Saves.load_game("slot_t")
	assert_true(lr["ok"])
	assert_eq(Game.state.inventory.credits, 5)
	assert_false(FileAccess.file_exists(Saves.slot_path("slot_t") + ".tmp"), "no temp file left")


func test_corrupt_and_missing_saves() -> void:
	var r := Saves.read_file("does_not_exist")
	assert_false(r["ok"])
	assert_true(r.get("missing", false))
	var f := FileAccess.open(Saves.slot_path("slot_bad"), FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	r = Saves.read_file("slot_bad")
	assert_false(r["ok"])
	assert_true(r.get("corrupt", false), "corrupt file reported, not fatal")
	# Corrupt main file with a good backup recovers.
	var st := _populated()
	Saves.write_file("slot_rec", {"header": {"schema": 1}, "state": st.to_dict()})
	Saves.write_file("slot_rec", {"header": {"schema": 1}, "state": st.to_dict()})
	f = FileAccess.open(Saves.slot_path("slot_rec"), FileAccess.WRITE)
	f.store_string("garbage")
	f.close()
	r = Saves.read_file("slot_rec")
	assert_true(r["ok"])
	assert_true(r.get("recovered", false))


func test_newer_schema_refused() -> void:
	var f := FileAccess.open(Saves.slot_path("slot_new"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"header": {"schema": 99}, "state": {}}))
	f.close()
	var r := Saves.read_file("slot_new")
	assert_false(r["ok"])
	assert_true(String(r["reason"]).contains("newer"))
