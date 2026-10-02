extends TestCase
## Status stacking/refresh/expiry/immunity and action-queue behaviour.


func _s() -> CharacterSheet:
	return BuildValidator.make_sheet(BuildValidator.recommended("vanguard"))


func test_refresh_same_id() -> void:
	var s := _s()
	StatusRules.apply(s, "suppressed", 6.0)
	StatusRules.tick(s, 4.0)
	var r := StatusRules.apply(s, "suppressed", 3.0)
	assert_eq(r["reason"], "refreshed")
	assert_eq(float(s.get_status("suppressed")["remaining"]), 3.0, "max(2, 3)")
	assert_eq(s.statuses.size(), 1, "same id never stacks")
	assert_eq(int(s.status_mods().get("attack", 0)), -2)


func test_group_priority() -> void:
	var s := _s()
	StatusRules.apply(s, "overdrive", 15.0)
	var r := StatusRules.apply(s, "surge", 15.0)
	assert_false(r["applied"], "weaker speed effect rejected")
	assert_eq(r["reason"], "weaker")
	assert_true(s.has_status("overdrive"))
	s.statuses.clear()
	StatusRules.apply(s, "surge", 15.0)
	r = StatusRules.apply(s, "overdrive", 15.0)
	assert_eq(r["reason"], "replaced")
	assert_false(s.has_status("surge"))
	# different groups add
	StatusRules.apply(s, "suppressed", 6.0)
	assert_eq(int(s.status_mods().get("attack", 0)), -1, "+1 overdrive -2 suppressed")


func test_expiration_and_pause() -> void:
	var s := _s()
	StatusRules.apply(s, "stunned", 3.0)
	assert_false(s.can_act())
	var exp := StatusRules.tick(s, 2.9)
	assert_empty(exp)
	assert_false(s.can_act())
	exp = StatusRules.tick(s, 0.2)
	assert_eq(exp, ["stunned"])
	assert_true(s.can_act())


func test_immunities() -> void:
	var drone := CharacterSheet.from_template("picket_drone", "d")
	assert_eq(StatusRules.apply(drone, "feared", 9.0)["reason"], "immune", "machines are fearless")
	assert_eq(StatusRules.apply(drone, "held", 6.0)["reason"], "immune")
	assert_true(StatusRules.apply(drone, "stunned", 3.0)["applied"], "machines can be stunned")
	var s := _s()
	s.set_slot("head", ItemInst.make("respirator_mask"))
	assert_eq(StatusRules.apply(s, "toxin", 9.0)["reason"], "immune", "respirator blocks coolant")
	StatusRules.apply(s, "antitox", 30.0)
	assert_eq(StatusRules.apply(s, "bleeding", 9.0)["reason"], "immune", "antitox grants immunity")


func test_break_on_damage_and_dot() -> void:
	var s := _s()
	StatusRules.apply(s, "feared", 9.0)
	StatusRules.apply(s, "burning", 9.0)
	CombatRules.apply_damage(s, [{"amount": 2, "dtype": "kinetic"}])
	assert_false(s.has_status("feared"), "damage ends fear")
	assert_true(s.has_status("burning"))
	var dice := Dice.new(1)
	dice.force([4])
	var dots := StatusRules.dot_rolls(s, dice)
	assert_eq(dots.size(), 1)
	assert_eq(int(dots[0]["rolled"]), 4)


func test_flat_footed_loses_dex() -> void:
	var s := BuildValidator.make_sheet(BuildValidator.recommended("operative"))
	var d0 := s.defense()
	StatusRules.apply(s, "stunned", 3.0)
	assert_eq(s.defense(), d0 - 3, "DEX 16 bonus lost while stunned")


func test_queue_order_cancel_reorder() -> void:
	var q := ActionQueue.new()
	var a := q.push({"type": "attack", "target": "e1"})
	var b := q.push({"type": "feat", "id": "power_strike_1", "target": "e1"})
	var c := q.push({"type": "item", "id": "medpac"})
	var d := q.push({"type": "power", "id": "aegis"})
	assert_true(q.push({"type": "attack"}).is_empty(), "queue holds at most four")
	assert_eq(q.size(), 4)
	assert_true(q.move(3, -1))
	assert_eq(String(q.items[2]["type"]), "power", "reordered")
	assert_false(q.move(0, -1), "cannot move first earlier")
	assert_true(q.cancel(int(b["qid"])))
	assert_eq(q.size(), 3)
	assert_false(q.cancel(int(b["qid"])), "cancelled once")
	assert_eq(String(q.pop_front()["type"]), "attack")
	assert_eq(String(q.front()["type"]), "power")
	q.push({"type": "attack", "target": "e2"})
	assert_eq(q.purge_target("e2"), 1)
	var arr := q.to_array()
	var q2 := ActionQueue.new()
	q2.from_array(arr)
	assert_eq(q2.to_array(), arr, "queue round-trips")
	var e := q2.push({"type": "swap"})
	assert_gte(int(e["qid"]), int(d["qid"]) + 1, "qids stay unique after load")
	assert_true(a.has("qid") and c.has("qid"))


func test_feat_cooldown_and_self_status() -> void:
	var s := _s()
	s.feats.append("flurry_1")
	s.set_slot("main", ItemInst.make("vibro_sword"))
	var d := CharacterSheet.from_template("reclaimer_breacher", "b")
	d.overrides["hp_max"] = 200
	d.hp = 200
	var dice := Dice.new(5)
	var out := ActionResolver.resolve({"type": "feat", "id": "flurry_1"}, s, {"target": d}, dice)
	assert_true(out["ok"])
	var attacks := (out["events"] as Array).filter(func(e: Dictionary) -> bool: return e["type"] == "attack")
	assert_eq(attacks.size(), 2, "flurry adds one attack")
	assert_true(s.has_status("exposed"))
	assert_eq(int(s.status_mods().get("defense", 0)), -4)
	s.feats.append("covering_fire")
	s.set_slot("main", ItemInst.make("carbine"))
	out = ActionResolver.resolve({"type": "feat", "id": "covering_fire"}, s, {"target": d}, dice)
	assert_true(out["ok"])
	assert_ne(ActionResolver.feat_usable(s, "covering_fire", d), "", "on cooldown")
	StatusRules.tick(s, 6.1)
	assert_eq(ActionResolver.feat_usable(s, "covering_fire", d), "", "cooldown expired")
