extends TestCase
## Inventory validity, equipment rules, crafting and trading conservation.


func test_inventory_never_negative() -> void:
	var st := fresh_state("vanguard")
	var inv := st.inventory
	var n := inv.count("medpac")
	assert_false(inv.remove("medpac", n + 1), "cannot remove more than held")
	assert_eq(inv.count("medpac"), n)
	var tx := inv.tx().remove_items("medpac", n).remove_items("medpac", 1)
	assert_false(tx.commit(), "combined removals validated together")
	assert_eq(inv.count("medpac"), n, "failed transaction changes nothing")
	var before := inv.credits
	assert_false(inv.tx().add_items("frag_grenade", 1).credits_delta(-before - 1).commit())
	assert_eq(inv.credits, before)
	assert_eq(inv.count("frag_grenade"), 1, "vanguard starts with one; failed tx added none")


func test_equip_requirements() -> void:
	var st := fresh_state("adept")
	var p := st.player()
	st.inventory.add("security_weave")
	st.inventory.add("breacher_plate")
	st.inventory.add("shear_glaive")
	st.inventory.add("chassis_plating")
	assert_ne(EquipmentRules.can_equip(p, "security_weave", "body"), "", "adept lacks medium armor proficiency")
	assert_ne(EquipmentRules.can_equip(p, "shear_glaive", "main"), "", "STR 13 required")
	assert_ne(EquipmentRules.can_equip(p, "chassis_plating", "body"), "", "machine only")
	assert_ne(EquipmentRules.can_equip(p, "sensor_visor", "body"), "", "wrong slot")
	var v := fresh_state("vanguard").player()
	Game.state.inventory.add("shear_glaive")
	var inst: Dictionary = Game.state.inventory.first_instance("shear_glaive")
	var r := EquipmentRules.equip(v, Game.state.inventory, String(inst["uid"]), "main")
	assert_true(r["ok"], String(r["reason"]))
	assert_eq(v.weapon_id("main"), "shear_glaive")
	assert_ne(EquipmentRules.can_equip(v, "vibro_knife", "off"), "", "two-hander blocks off-hand")
	assert_eq(Game.state.inventory.count("lumen_edge"), 1, "old main hand returned to inventory")


func test_equip_atomic_swap_preserves_items() -> void:
	var st := fresh_state("vanguard")
	var p := st.player()
	var total_before := st.inventory.instances.size() + p.equipment.size()
	st.inventory.add("vibro_sword")
	st.inventory.add("vibro_knife")
	var sword: Dictionary = st.inventory.first_instance("vibro_sword")
	var knife: Dictionary = st.inventory.first_instance("vibro_knife")
	assert_true(EquipmentRules.equip(p, st.inventory, String(sword["uid"]), "main")["ok"])
	assert_true(EquipmentRules.equip(p, st.inventory, String(knife["uid"]), "off")["ok"])
	assert_true(p.is_dual_wielding())
	assert_true(EquipmentRules.unequip(p, st.inventory, "main")["ok"])
	assert_false(p.is_dual_wielding(), "removing main hand also clears off-hand")
	assert_eq(st.inventory.instances.size() + p.equipment.size(), total_before + 2, "no item lost or duplicated")
	var cmp := EquipmentRules.compare(p, "security_weave", "body")
	assert_true(cmp["delta"].has("Defense"), "comparison shows defense change")


func test_crafting_conservation_and_gates() -> void:
	var st := fresh_state("vanguard")
	var p := st.player()
	st.inventory.add("tech_components", 3)
	var before := st.inventory.count("tech_components")
	var r := Crafting.craft("r_frag_mine", p, st)
	assert_false(r["ok"], "Demolitions gate (needs 5)")
	assert_eq(st.inventory.count("tech_components"), before, "failed craft consumes nothing")
	p.skill_ranks["demolitions"] = 3
	p.mark_dirty()
	r = Crafting.craft("r_frag_grenade", p, st)
	assert_true(r["ok"], String(r.get("reason", "")))
	assert_eq(st.inventory.count("tech_components"), before - 2)
	var grenades := st.inventory.count("frag_grenade")
	r = Crafting.dismantle(st, "frag_grenade")
	assert_true(r["ok"])
	assert_eq(st.inventory.count("frag_grenade"), grenades - 1)
	assert_eq(st.inventory.count("tech_components"), before - 1, "dismantle yields less than the recipe cost")
	assert_false(Crafting.dismantle(st, "lumen_edge")["ok"], "bound item")
	st.inventory.add("vesper_testimony")
	assert_ne(Crafting.can_dismantle(st, "vesper_testimony"), "", "quest item")
	# A loop of craft + dismantle can only lose components.
	st.inventory.add("tech_components", 10)
	var start := st.inventory.count("tech_components")
	for i in 5:
		Crafting.craft("r_frag_grenade", p, st)
		Crafting.dismantle(st, "frag_grenade")
	assert_lte(st.inventory.count("tech_components"), start - 5)


func test_upgrade_changes_combat_stats() -> void:
	var st := fresh_state("vanguard")
	var p := st.player()
	var edge: Dictionary = p.equipment["main"]
	var prof0 := CombatRules.weapon_profile(p, "main")
	var atk0 := CombatRules.sum_parts(CombatRules.attack_parts(p, prof0))
	st.inventory.add("focusing_lens")
	st.inventory.add("edge_emitter")
	assert_true(Crafting.install(st, "focusing_lens", String(edge["uid"]))["ok"])
	assert_true(Crafting.install(st, "edge_emitter", String(edge["uid"]))["ok"])
	var prof := CombatRules.weapon_profile(p, "main")
	assert_eq(CombatRules.sum_parts(CombatRules.attack_parts(p, prof)), atk0 + 1, "lens +1 attack")
	assert_eq(int(prof["damage"]), int(prof0["damage"]) + 2, "emitter +2 damage")
	st.inventory.add("recoil_dampener")
	assert_false(Crafting.install(st, "recoil_dampener", String(edge["uid"]))["ok"], "incompatible")
	st.inventory.add("balanced_grip")
	assert_false(Crafting.install(st, "balanced_grip", String(edge["uid"]))["ok"], "slots full (2)")
	assert_true(Crafting.remove_upgrade(st, String(edge["uid"]), "focusing_lens")["ok"])
	assert_eq(st.inventory.count("focusing_lens"), 1, "upgrade returned")
	assert_eq(CombatRules.sum_parts(CombatRules.attack_parts(p, CombatRules.weapon_profile(p, "main"))), atk0)


func test_vendor_finite_stock_and_no_credit_loop() -> void:
	var st := fresh_state("vanguard")
	st.inventory.credits = 1000
	var stock := Vendor.stock(st, "requisition")
	var n := int(stock["medpac"])
	var have := st.inventory.count("medpac")
	for i in n:
		assert_true(Vendor.buy(st, "requisition", "medpac")["ok"])
	assert_false(Vendor.buy(st, "requisition", "medpac")["ok"], "finite stock")
	assert_eq(st.inventory.count("medpac"), have + n)
	var value := st.inventory.total_value()
	var cr := st.inventory.credits
	assert_true(Vendor.sell(st, "requisition", "medpac")["ok"])
	assert_true(Vendor.buy(st, "requisition", "medpac")["ok"], "sold item rejoins stock")
	assert_lt_credits(cr, st.inventory.credits)
	assert_lte(st.inventory.total_value(), value, "buy/sell round trips never create value")
	assert_false(Vendor.sell(st, "requisition", "lumen_edge")["ok"], "bound items cannot be sold")
	st.inventory.add("vesper_testimony")
	assert_false(Vendor.sell(st, "requisition", "vesper_testimony")["ok"], "quest items cannot be sold")
	st.inventory.credits = 5
	var c0 := st.inventory.count("frag_grenade")
	assert_false(Vendor.buy(st, "requisition", "frag_grenade")["ok"], "insufficient credits")
	assert_eq(st.inventory.count("frag_grenade"), c0)
	assert_eq(st.inventory.credits, 5)


func assert_lt_credits(before: int, after: int) -> void:
	assert_true(after < before, "a sell+buy round trip costs credits (%d -> %d)" % [before, after])


func test_consumable_use_respects_action_and_stock() -> void:
	var st := fresh_state("vanguard")
	var p := st.player()
	p.hp = 3
	var n := st.inventory.count("medpac")
	var out := ActionResolver.resolve({"type": "item", "id": "medpac"}, p, {"inventory": st.inventory, "target": p}, st.dice)
	assert_true(out["ok"])
	assert_eq(st.inventory.count("medpac"), n - 1)
	assert_gte(p.hp, 4)
	st.inventory.remove("medpac", st.inventory.count("medpac"))
	out = ActionResolver.resolve({"type": "item", "id": "medpac"}, p, {"inventory": st.inventory, "target": p}, st.dice)
	assert_false(out["ok"], "no medpacs left")
	var tav := Game.recruit("tav7")
	st.inventory.add("medpac", 1)
	out = ActionResolver.resolve({"type": "item", "id": "medpac"}, p, {"inventory": st.inventory, "target": tav}, st.dice)
	assert_false(out["ok"], "medpacs do not repair machines")
	assert_eq(st.inventory.count("medpac"), 1, "rejected use consumes nothing")
