extends TestCase
## Attribute budgets, skill allocation, feat/power prerequisites, builds.


func test_attribute_modifier_floor() -> void:
	assert_eq(Rules.mod(10), 0)
	assert_eq(Rules.mod(11), 0)
	assert_eq(Rules.mod(9), -1, "odd scores below 10 round down")
	assert_eq(Rules.mod(8), -1)
	assert_eq(Rules.mod(7), -2)
	assert_eq(Rules.mod(18), 4)
	assert_eq(Rules.mod(1), -5)


func test_point_buy_costs() -> void:
	assert_eq(BuildValidator.attr_cost(8), 0)
	assert_eq(BuildValidator.attr_cost(14), 6, "1 point per increase through 14")
	assert_eq(BuildValidator.attr_cost(15), 8, "15 costs 2")
	assert_eq(BuildValidator.attr_cost(16), 10)
	assert_eq(BuildValidator.attr_cost(17), 13, "17 costs 3")
	assert_eq(BuildValidator.attr_cost(18), 16)
	var a := {"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}
	assert_eq(BuildValidator.points_remaining(a), 30)
	a["str"] = 18
	a["dex"] = 18
	assert_eq(BuildValidator.points_remaining(a), -2)
	assert_false(BuildValidator.validate_attrs(a).is_empty(), "over budget must fail")
	a["dex"] = 16
	assert_eq(BuildValidator.points_remaining(a), 4)
	assert_true(BuildValidator.validate_attrs(a).is_empty())
	assert_ne(BuildValidator.can_raise({"str": 18, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}, "str"), "", "cannot exceed 18")
	assert_ne(BuildValidator.can_lower({"str": 8}, "str"), "", "cannot go below 8")
	var tight := {"str": 16, "dex": 16, "con": 14, "int": 8, "wis": 8, "cha": 8}
	assert_eq(BuildValidator.points_remaining(tight), 4)
	tight["con"] = 15
	assert_eq(BuildValidator.points_remaining(tight), 2)


func test_recommended_builds_validate() -> void:
	for c in ["vanguard", "operative", "adept"]:
		var b := BuildValidator.recommended(c)
		assert_empty(BuildValidator.validate_build(b), c)
		var un := BuildValidator.unspent(b)
		for k in un.keys():
			assert_eq(int(un[k]), 0, "%s %s unspent" % [c, k])


func test_skill_rules() -> void:
	assert_eq(BuildValidator.rank_cost("operative", "stealth"), 1)
	assert_eq(BuildValidator.rank_cost("vanguard", "stealth"), 2, "cross-class costs 2")
	assert_eq(BuildValidator.max_rank("operative", "stealth", 1), 4)
	assert_eq(BuildValidator.max_rank("vanguard", "stealth", 1), 2)
	assert_eq(BuildValidator.skill_points_for_level("operative", 14, 1), 16, "(6+2)*2")
	assert_eq(BuildValidator.skill_points_for_level("vanguard", 8, 1), 2, "(2-1)*2")
	assert_eq(BuildValidator.skill_points_for_level("vanguard", 8, 2), 1, "min 1 per level")
	var errs := BuildValidator.validate_skills("vanguard", 1, {}, {"stealth": 3}, 10)
	assert_false(errs.is_empty(), "cross-class rank limit")
	errs = BuildValidator.validate_skills("vanguard", 1, {}, {"awareness": 2, "repair": 2, "stealth": 1}, 4)
	assert_false(errs.is_empty(), "spending 6 of 4 points must fail")


func test_feat_prerequisites() -> void:
	var b := BuildValidator.recommended("vanguard")
	var s := BuildValidator.make_sheet(b)
	assert_false(BuildValidator.feat_errors(s, "power_strike_2").is_empty(), "needs level 3 and rank 1")
	assert_true(BuildValidator.feat_errors(s, "toughness").is_empty())
	assert_false(BuildValidator.feat_errors(s, "covering_fire").is_empty(), "earned feats not selectable")
	s.level = 3
	s.mark_dirty()
	assert_true(BuildValidator.feat_errors(s, "power_strike_2").is_empty(), "level 3 + power strike 1 + STR 16")
	s.base_attrs["str"] = 12
	s.mark_dirty()
	assert_false(BuildValidator.feat_errors(s, "power_strike_2").is_empty(), "STR 13 required")
	var bad := b.duplicate(true)
	bad["feats"] = ["power_strike_2", "toughness"]
	assert_false(BuildValidator.validate_build(bad).is_empty())
	bad["feats"] = ["toughness", "conditioning", "dueling"]
	assert_false(BuildValidator.validate_build(bad).is_empty(), "too many feats")


func test_power_prerequisites() -> void:
	var b := BuildValidator.recommended("adept")
	var s := BuildValidator.make_sheet(b)
	assert_false(BuildValidator.power_errors(s, "restore").is_empty(), "restore needs level 3")
	assert_false(BuildValidator.power_errors(s, "repair_beam").is_empty(), "innate not learnable")
	assert_true(BuildValidator.power_errors(s, "arc_lance").is_empty())
	var bad := b.duplicate(true)
	bad["powers"] = ["mend", "restore"]
	assert_false(BuildValidator.validate_build(bad).is_empty())


func test_cosmetics_do_not_change_stats() -> void:
	var b := BuildValidator.recommended("vanguard")
	var s1 := BuildValidator.make_sheet(b)
	var b2 := b.duplicate(true)
	b2["appearance"] = {"body": "slight", "head": "round", "hair": "long", "skin": "s6", "hair_color": "h6", "accent": "a4"}
	var s2 := BuildValidator.make_sheet(b2)
	assert_eq(EquipmentRules.snapshot(s1), EquipmentRules.snapshot(s2))


func test_build_validation_messages() -> void:
	var b := BuildValidator.recommended("operative")
	b["name"] = ""
	assert_false(BuildValidator.validate_build(b).is_empty(), "name required")
	b["name"] = "Ok"
	b["pronouns"] = "zz"
	assert_false(BuildValidator.validate_build(b).is_empty(), "pronouns validated")


func test_derived_stats() -> void:
	var s := BuildValidator.make_sheet(BuildValidator.recommended("vanguard"))
	# Vanguard CON 14: 12 + 2
	assert_eq(s.max_hp(), 14)
	# Energy: 6 base + WIS 12 (+1) x1 x level1 = 7
	assert_eq(s.max_energy(), 7)
	assert_eq(s.bab(), 1)
	assert_eq(s.save_total("fort"), 4, "2 + CON 2")
	var a := BuildValidator.make_sheet(BuildValidator.recommended("adept"))
	assert_eq(a.max_energy(), 22, "16 + 2*3*1")
	assert_eq(a.power_dc(), 14, "10 + 0 + WIS 3 + focus 1")
