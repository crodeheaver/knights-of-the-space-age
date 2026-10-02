extends TestCase
## Attack, save, damage and critical calculations with forced dice.


func _fighter() -> CharacterSheet:
	var s := BuildValidator.make_sheet(BuildValidator.recommended("vanguard"))
	s.set_slot("main", ItemInst.make("vibro_sword"))
	s.mark_dirty()
	return s


func _drone() -> CharacterSheet:
	return CharacterSheet.from_template("picket_drone", "d1")


func test_attack_bonus_breakdown() -> void:
	var s := _fighter()
	var prof := CombatRules.weapon_profile(s, "main")
	# BAB 1 + STR 3
	assert_eq(CombatRules.sum_parts(CombatRules.attack_parts(s, prof)), 4)
	var d := _drone()
	# 10 + DEX 1 + natural 1
	assert_eq(d.defense(), 12)


func test_hit_and_miss_with_forced_rolls() -> void:
	var s := _fighter()
	var d := _drone()
	var dice := Dice.new(1)
	var prof := CombatRules.weapon_profile(s, "main")
	dice.force([8, 5])  # 8 + 4 = 12 vs 12 -> hit; damage d8 = 5
	var r := CombatRules.resolve_attack(s, d, prof, {}, dice)
	assert_true(r["hit"])
	assert_false(r["crit"])
	assert_eq(int(r["components"][0]["amount"]), 8, "5 + STR 3")
	dice.force([7])
	r = CombatRules.resolve_attack(s, d, prof, {}, dice)
	assert_false(r["hit"], "7 + 4 = 11 < 12")


func test_natural_one_and_twenty_on_attacks_only() -> void:
	var s := _fighter()
	var d := _drone()
	d.overrides["defense_bonus"] = 30
	d.mark_dirty()
	var dice := Dice.new(1)
	var prof := CombatRules.weapon_profile(s, "main")
	dice.force([20, 1, 4])  # natural 20 hits regardless; confirm natural 1 fails
	var r := CombatRules.resolve_attack(s, d, prof, {}, dice)
	assert_true(r["hit"], "natural 20 always hits")
	assert_true(r["threat"])
	assert_false(r["crit"], "confirmation natural 1 fails")
	var weak := _drone()
	weak.overrides["defense_bonus"] = -20
	weak.mark_dirty()
	dice.force([1])
	r = CombatRules.resolve_attack(s, weak, prof, {}, dice)
	assert_false(r["hit"], "natural 1 always misses")
	# Saves: no automatic results.
	dice.force([1])
	var sv := CombatRules.saving_throw(s, "fort", 4, dice)
	assert_true(sv["success"], "natural 1 save still succeeds when total >= DC (1+4 >= 4)")
	dice.force([20])
	sv = CombatRules.saving_throw(s, "fort", 30, dice)
	assert_false(sv["success"], "natural 20 save does not auto-succeed")
	dice.force([20])
	var sk := CombatRules.skill_check(s, "security", 40, dice)
	assert_false(sk["success"], "natural 20 skill check does not auto-succeed")
	dice.force([1])
	sk = CombatRules.skill_check(s, "awareness", 2, dice)
	assert_true(sk["success"], "natural 1 skill check is just a 1")


func test_critical_confirmation_and_multiplier() -> void:
	var s := _fighter()
	var d := _drone()
	var dice := Dice.new(1)
	var prof := CombatRules.weapon_profile(s, "main")  # vibrosword threat 19
	dice.force([19, 15, 4, 6])  # threat, confirm 15+4=19>=12, dice 4 and 6
	var r := CombatRules.resolve_attack(s, d, prof, {}, dice)
	assert_true(r["crit"])
	# (4 + 6) + STR 3 x2 = 16
	assert_eq(int(r["components"][0]["amount"]), 16)
	# Critical Strike doubles threat range: 19-20 -> 17-20
	dice.force([17, 15, 1, 1])
	r = CombatRules.resolve_attack(s, d, prof, {"threat_mult": 2}, dice)
	assert_true(r["crit"], "17 threatens with doubled range")
	dice.force([17])
	r = CombatRules.resolve_attack(s, d, prof, {}, dice)
	assert_false(r["threat"], "17 does not threaten normally")


func test_damage_types_and_resistance() -> void:
	var drone := _drone()
	var before := drone.hp
	var res := CombatRules.apply_damage(drone, [{"amount": 3, "dtype": "ion"}])
	assert_eq(int(res["dealt"]), 6, "ion doubled vs machines")
	assert_eq(drone.hp, before - 6)
	var s := _fighter()
	var hp := s.hp
	res = CombatRules.apply_damage(s, [{"amount": 8, "dtype": "ion"}])
	assert_eq(int(res["dealt"]), 2, "ion quartered vs organics")
	var sentinel := CharacterSheet.from_template("warden_sentinel", "s1")
	res = CombatRules.apply_damage(sentinel, [{"amount": 5, "dtype": "kinetic"}])
	assert_eq(int(res["dealt"]), 3, "kinetic DR 2")
	assert_eq(int(res["resisted"]), 2)
	assert_eq(s.hp, hp - 2)


func test_shield_absorption() -> void:
	var s := _fighter()
	StatusRules.apply(s, "shield_basic", 15.0)
	var hp := s.hp
	var res := CombatRules.apply_damage(s, [{"amount": 10, "dtype": "energy"}])
	assert_eq(int(res["absorbed"]), 10)
	assert_eq(s.hp, hp)
	res = CombatRules.apply_damage(s, [{"amount": 9, "dtype": "energy"}])
	assert_eq(int(res["absorbed"]), 5)
	assert_eq(int(res["dealt"]), 4)
	assert_false(s.has_status("shield_basic"), "exhausted shield expires")
	StatusRules.apply(s, "shield_basic", 15.0)
	res = CombatRules.apply_damage(s, [{"amount": 4, "dtype": "thermal"}])
	assert_eq(int(res["absorbed"]), 0, "deflector does not stop thermal")


func test_two_handed_and_offhand_strength() -> void:
	var s := _fighter()
	s.set_slot("main", ItemInst.make("shear_glaive"))
	var dice := Dice.new(1)
	dice.force([15, 3, 3])
	var r := CombatRules.resolve_attack(s, _drone(), CombatRules.weapon_profile(s, "main"), {}, dice)
	assert_eq(int(r["components"][0]["amount"]), 10, "2d6 (6) + floor(3 x 1.5)=4")
	s.set_slot("main", ItemInst.make("vibro_sword"))
	s.set_slot("off", ItemInst.make("vibro_knife"))
	var off := CombatRules.weapon_profile(s, "off")
	dice.force([18, 2])  # off-hand: 18 + BAB 1 + DEX/STR 3 - 8 = 14 vs 12
	r = CombatRules.resolve_attack(s, _drone(), off, {}, dice)
	assert_true(r["hit"])
	assert_eq(int(r["components"][0]["amount"]), 3, "1d4 (2) + floor(STR 3 / 2) = 1")


func test_dual_wield_penalties() -> void:
	var s := _fighter()
	s.set_slot("off", ItemInst.make("vibro_sword"))
	s.mark_dirty()
	assert_eq(CombatRules.dual_penalties(s), Vector2i(-6, -10))
	s.set_slot("off", ItemInst.make("vibro_knife"))
	assert_eq(CombatRules.dual_penalties(s), Vector2i(-4, -8), "light off-hand")
	s.feats.append("two_weapon_1")
	s.mark_dirty()
	assert_eq(CombatRules.dual_penalties(s), Vector2i(-2, -6))
	s.feats.append("two_weapon_2")
	s.mark_dirty()
	assert_eq(CombatRules.dual_penalties(s), Vector2i(0, -4), "ranks use the highest, not the sum")


func test_power_strike_action_modifiers() -> void:
	var s := _fighter()
	var d := _drone()
	var dice := Dice.new(1)
	var res := {"events": [], "log": [], "downed": []}
	d.overrides["hp_max"] = 100
	d.hp = 100
	dice.force([12, 4])  # 12 + 4 - 3 = 13 >= 12 hit; d8=4 +3 +5
	var out := ActionResolver.resolve({"type": "feat", "id": "power_strike_1"}, s, {"target": d}, dice)
	assert_true(out["ok"], str(out.get("reason", "")))
	var ev: Dictionary = out["events"][0]
	assert_eq(int(ev["result"]["bonus"]), 1, "4 - 3")
	assert_eq(int(ev["damage"]["dealt"]), 12)


func test_bolt_deflection() -> void:
	var s := _fighter()
	s.set_slot("main", ItemInst.make("lumen_edge"))
	s.mark_dirty()
	var drone := _drone()
	var dice := Dice.new(1)
	dice.force([18, 15])  # drone hits (18+2=20); deflect 15 + 5 + DEX 1 = 21 >= 20
	var r := CombatRules.resolve_attack(drone, s, CombatRules.weapon_profile(drone, "main"), {}, dice)
	assert_true(r["deflected"], "Vanguard rec build has Bolt Deflection")
	assert_false(r["hit"])
	s.set_slot("main", ItemInst.make("vibro_sword"))
	dice.force([18, 3])
	r = CombatRules.resolve_attack(drone, s, CombatRules.weapon_profile(drone, "main"), {}, dice)
	assert_false(r["deflected"], "needs an energy blade")


func test_sneak_attack_flat_footed() -> void:
	var s := BuildValidator.make_sheet(BuildValidator.recommended("operative"))
	s.set_slot("main", ItemInst.make("vibro_knife"))
	var d := _drone()
	d.overrides["hp_max"] = 100
	d.hp = 100
	StatusRules.apply(d, "stunned", 3.0)
	var dice := Dice.new(1)
	dice.force([10, 2, 5])
	var r := CombatRules.resolve_attack(s, d, CombatRules.weapon_profile(s, "main"), {}, dice)
	assert_true(r["hit"])
	assert_true(r.get("sneak", false), "stunned target is flat-footed")
	assert_eq(r["components"].size(), 2)
	assert_eq(int(r["components"][1]["amount"]), 5)


func test_story_difficulty() -> void:
	var s := _fighter()
	var drone := _drone()
	var parts := CombatRules.attack_parts(drone, CombatRules.weapon_profile(drone, "main"), {"difficulty": "story"})
	assert_eq(CombatRules.sum_parts(parts), 0, "drone +2 with story -2")
	var hp := s.hp
	CombatRules.apply_damage(s, [{"amount": 10, "dtype": "energy"}], {"difficulty": "story"})
	assert_eq(s.hp, hp - 6)


func test_power_resolution_and_costs() -> void:
	var a := BuildValidator.make_sheet(BuildValidator.recommended("adept"))
	var d := CharacterSheet.from_template("reclaimer_breacher", "b1")
	var dice := Dice.new(3)
	a.energy = 20
	dice.force([2])  # breacher Will: 2 + 1 + WIS0 = 3 vs DC 14 -> held
	var out := ActionResolver.resolve({"type": "power", "id": "hold"}, a, {"target": d, "alignment": 0}, dice)
	assert_true(out["ok"], str(out["reason"]))
	assert_eq(a.energy, 15, "hold costs 5")
	assert_true(d.has_status("held"))
	assert_false(d.can_act())
	var machine := _drone()
	assert_ne(ActionResolver.power_usable(a, "hold", machine, 0), "", "machines immune to Hold: action disabled with reason")
	# Alignment cost: mercy power at +60 costs 2 less (min 1)
	assert_eq(int(a.power_cost("mend", 60)["cost"]), 2)
	assert_eq(int(a.power_cost("mend", -30)["cost"]), 5)
	assert_eq(int(a.power_cost("hold", 80)["cost"]), 5, "universal unaffected")
	a.set_slot("body", ItemInst.make("security_weave"))
	assert_eq(int(a.power_cost("hold", 0)["cost"]), 7, "medium armor +2")
	a.set_slot("body", ItemInst.make("breacher_plate"))
	assert_true(bool(a.power_cost("hold", 0)["blocked"]), "heavy armor blocks")


func test_grenade_explosion_once() -> void:
	var targets := [_drone(), CharacterSheet.from_template("picket_drone", "d2")]
	var dice := Dice.new(9)
	var out := ActionResolver.resolve_explosion("ion_grenade", "player", targets, {}, dice)
	assert_eq(out["events"].filter(func(e: Dictionary) -> bool: return e["type"] == "damage").size(), 2)
	# Downed targets are skipped by a second explosion
	for t in targets:
		(t as CharacterSheet).hp = 0
	out = ActionResolver.resolve_explosion("ion_grenade", "player", targets, {}, dice)
	assert_eq(out["events"].size(), 0, "no effects on downed targets")
