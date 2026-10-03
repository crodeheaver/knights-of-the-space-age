"""Interactive content for the Cinder Wake layout: objects, NPCs, triggers and
derived-flag rules. Imported by tools/author_layout.py."""

IONA_APP = {"body": "average", "head": "angular", "hair": "tail", "skin": "s2", "hair_color": "h1", "accent": "a2"}
TAV_APP = {"model": "synthetic", "body": "slight", "head": "long", "hair": "shaved", "skin": "s5", "hair_color": "h5", "accent": "a1"}


def populate(L, obj, npc, trigger):
    rules = L.setdefault("rules", [])

    # ================================================================ CABIN
    obj("cabin_locker", "container", "cabin", (2.7, 7.6), rot=90, model="locker", name="Personal Locker",
        loot={"medpac": 1, "credits": 40, "travel_jacket": 1})
    obj("cabin_case", "container", "cabin", (6.0, 9.2), rot=180, model="case", name="Sealed Operator's Case",
        loot={"focus_ampoule": 1, "resonance_band": 1},
        on_looted=[{"codex": "cx_operator_case"}, {"set_flag": "case_opened"}, {"tutorial": "inventory"}])
    obj("cabin_datapad", "readable", "cabin", (8.6, 8.8), model="datapad", name="Transfer Orders", codex="cx_transfer_orders")

    # ================================================================ COMMONS
    obj("commons_vendor", "vendor", "commons", (23.5, 0.6), rot=0, model="vendor", name="Crew Requisition Terminal", vendor="requisition")
    obj("commons_cards", "minigame", "commons", (16.0, 8.0), model="card_table", name="Shards Table", minigame="shards", verb="Play Shards with Brann")
    obj("commons_sim", "minigame", "commons", (25.5, 2.5), rot=180, model="booth", name="Slipstream Racing Sim", minigame="slipstream", verb="Race the Slipstream sim")
    obj("commons_muster", "muster", "commons", (13.5, 9.0), rot=0, model="muster", name="Muster Point B")
    npc("steward", "Purser Hollis Dray", "commons", (24.0, 7.5), rot=-90,
        appearance={"body": "broad", "head": "round", "hair": "shaved", "skin": "s1", "hair_color": "h5", "accent": "a1"}, armor_look="padded_vest", dialogue="steward", idle="fidget")
    npc("dalia", "Dalia Venn", "commons", (14.6, 5.0), rot=60,
        appearance={"body": "slight", "head": "long", "hair": "long", "skin": "s3", "hair_color": "h2", "accent": "a3"}, armor_look="travel_jacket", dialogue="venn_family", idle="talk")
    npc("ilo", "Ilo Venn", "commons", (15.3, 4.4), rot=60,
        appearance={"body": "slight", "head": "round", "hair": "crop", "skin": "s3", "hair_color": "h2", "accent": "a3"}, armor_look="travel_jacket", dialogue="venn_family", idle="fidget")
    npc("ketterick", "Brann Ketterick", "commons", (16.9, 8.9), rot=200,
        appearance={"body": "broad", "head": "square", "hair": "crest", "skin": "s5", "hair_color": "h4", "accent": "a4"}, armor_look="travel_jacket", dialogue="ketterick", idle="cards")
    trigger("t_commons_tut", [11, 0, 28, 14], effects=[{"tutorial": "interaction"}])

    # ================================================================ LOUNGE
    obj("lounge_history", "readable", "lounge", (15.2, -7.3), model="datapad", name="Memorial Placard", codex="cx_haldis_war", verb="Read")
    obj("lounge_manifest", "readable", "lounge", (22.8, -2.0), rot=180, model="terminal", name="Passenger Manifest Terminal", codex="cx_manifest", verb="Read manifest")
    obj("lounge_bag", "container", "lounge", (19.5, -4.0), model="crate", name="Abandoned Travel Bag", loot={"credits": 60, "reflex_stim": 1, "antitox": 1})

    # ================================================================ CORRIDOR
    npc("iona_npc", "Iona Rell", "corridor", (44.6, 7.0), rot=-90, appearance=IONA_APP, armor_look="security_weave",
        if_=None)
    obj("corr_body", "corpse", "corridor", (34.5, 8.2), rot=30, name="Body of Crewman Jessa Orrin", cloth="#253a5e", loot={"medpac": 1, "credits": 25})
    obj("corr_ticket", "readable", "corridor", (35.4, 8.9), model="datapad", name="Dropped Datapad", codex="cx_maintenance_ticket")
    obj("corr_locker", "container", "corridor", (38.0, 13.4), rot=180, model="locker", name="Emergency Locker",
        loot={"frag_grenade": 1, "repair_kit": 1, "tech_components": 2, "medpac": 1})
    trigger("t_corridor", [29, 3, 37, 11], if_=[{"flag": "emergency_started"}],
            effects=[{"join_party": "iona"}, {"set_flag": "iona_recruited"}, {"start_encounter": "enc_corridor"},
                     {"notify": "Iona Rell: \"You're armed? Good. Get behind cover and help me drop these pickets!\""}])

    # ================================================================ CHECKPOINT
    obj("chk_terminal", "terminal", "checkpoint", (52.0, 9.55), rot=180, model="terminal", name="Checkpoint Security Terminal", dialogue="checkpoint_terminal")
    obj("chk_mine", "mine", "checkpoint", (50.6, 7.0), model="mine", name="WARDEN Shock Mine", mine_item="shock_mine", hidden_dc=11,
        notice_range=6.0, owner="warden", xp=40, on_detect=[{"tutorial": "skills_world"}])
    obj("chk_body", "corpse", "checkpoint", (56.0, 8.4), rot=120, name="Body of Officer Tamsin Kell", cloth="#253a5e", loot={"shield_cell": 1, "credits": 30, "sensor_visor": 1})
    obj("armory_locker", "container", "armory", (54.5, -5.3), model="locker", name="Armory Weapons Locker",
        loot={"ion_grenade": 2, "shield_cell": 2, "insulated_lining": 1, "credits": 50, "carbine": 1, "security_weave": 1})
    obj("armory_manifest", "readable", "armory", (57.0, -2.0), rot=-90, model="terminal", name="Armory Manifest", codex="cx_armory_manifest")
    obj("crawl_cache", "container", "crawlway", (66.0, 25.4), model="crate", name="Technician's Cache", loot={"tech_components": 2, "power_cell": 1, "antitox": 1})
    obj("crawl_note", "readable", "crawlway", (59.5, 18.5), model="datapad", name="Note Soldered to a Panel", codex="cx_crawl_log")
    obj("med_release", "panel", "medical", (63.7, 10.0), rot=90, model="junction", name="Blast Door Manual Release",
        options=[{"id": "release", "label": "Pull the manual release", "hide_if": [{"flag": "checkpoint_solved"}],
                  "success": [{"world": "d_blast", "set": {"locked": False, "open": True}}, {"set_flag": "checkpoint_solved"},
                              {"set_flag": "checkpoint_by", "value": "crawlway"}],
                  "success_text": "The blast door grinds open from this side.", "xp": 40, "key": "checkpoint_door"}])
    trigger("t_storage_bypass", [74, 18, 81, 26], if_=[{"encounter": "enc_checkpoint", "state": "pending"}],
            effects=[{"resolve_encounter": "enc_checkpoint", "resolution": "bypassed"}, {"set_flag": "checkpoint_bypassed"},
                     {"notify": "You slipped past the checkpoint's guns unseen."}])
    trigger("t_checkpoint_tut", [48, 0, 56, 15], effects=[{"tutorial": "stealth"}])

    # ================================================================ MEDICAL
    npc("tav7_npc", "Tav-7", "medical", (75.5, 9.5), rot=-90, appearance=TAV_APP, armor_look="chassis_plating", kind="machine")
    npc("varga", "Dr. Ilse Varga", "medical", (69.0, 10.4), rot=180,
        appearance={"body": "slight", "head": "angular", "hair": "tail", "skin": "s4", "hair_color": "h5", "accent": "a4"}, armor_look="operator_coat", dialogue="varga_triage", idle="work")
    for nid, nm, x in [("corin", "Corin Ashe", 65.5), ("mae", "Mae Toller", 68.5), ("benedikt", "Benedikt Sorrow", 71.5)]:
        npc(nid, nm, "medical", (x, 13.6), rot=0, appearance={"body": "average", "head": "round", "hair": "crop", "skin": "s3", "hair_color": "h2", "accent": "a1"},
            armor_look="travel_jacket", downed=True, dialogue="wounded")
    obj("med_station", "medstation", "medical", (80.6, 2.2), rot=-90, model="medstation", name="Medical Fabricator")
    obj("med_vendor", "vendor", "medical", (80.6, 5.4), rot=-90, model="vendor", name="Medical Dispensary", vendor="med_dispensary")
    obj("med_muster", "muster", "medical", (65.6, 2.6), model="muster", name="Medical Muster Point")
    obj("ward_intercom", "terminal", "medical", (73.4, 0.6), rot=0, model="terminal", name="Ward 2 Intercom", dialogue="ward_intercom", color="#e0b03a")
    obj("ward_purge", "panel", "medical", (67.0, 0.6), rot=0, model="valve", name="Ward Coolant Purge Valve", color="#7fd0ff",
        options=[{"id": "purge", "label": "Purge the ward's vented coolant", "skill": "repair", "dc": 13, "max_attempts": 2,
                  "hide_if": [{"any": [{"flag": "ward_purged"}, {"flag": "ward_decided"}]}],
                  "success": [{"set_flag": "ward_purged"}, {"codex": "cx_triage_notes"}], "success_text": "The ward's scrubbers cycle clean. Opening it is safe now.",
                  "failure": [{"damage_party": 2, "dtype": "thermal", "who": "actor"}], "failure_text": "A jet of freezing coolant bursts from the valve. It isn't purged yet.",
                  "xp": 50, "key": "ward_purge"}])
    obj("med_notes", "readable", "medical", (76.5, 12.6), model="datapad", name="Triage Notes", codex="cx_triage_notes")
    obj("storage_crate", "container", "storage", (79.6, 21.5), model="crate", name="Medical Supply Crate", loot={"med_reagents": 3, "medpac": 1})
    for i, (nid, nm, x, z) in enumerate([("pell", "Pell Okafor", 69.0, -4.0), ("ward_a", "Ward Patient Ruth Calder", 71.5, -5.5),
                                         ("ward_b", "Ward Patient Joss Maren", 73.5, -3.5), ("ward_c", "Ward Patient Aya Senn", 68.0, -6.0),
                                         ("ward_d", "Ward Patient Tomas Lir", 74.0, -6.5)]):
        npc(nid, nm, "ward", (x, z), rot=180, appearance={"body": "average", "head": ["round", "long", "square", "angular", "round"][i], "hair": ["crop", "long", "swept", "tail", "shaved"][i],
            "skin": ["s1", "s3", "s5", "s2", "s6"][i], "hair_color": "h2", "accent": "a3"}, armor_look="travel_jacket",
            if_=[{"flag": "ward_open"}], dialogue="ward_patient", idle="fidget")
    trigger("t_medical", [63, 0, 70, 17], if_=[{"not": {"recruited": "tav7"}}],
            effects=[{"join_party": "tav7"}, {"set_flag": "tav7_recruited"}, {"start_encounter": "enc_medical"},
                     {"notify": "Tav-7: \"Assistance would be statistically welcome. Their cutters are aimed at my patients.\""}])

    # ================================================================ ENGINEERING
    obj("eng_terminal", "terminal", "engineering", (84.6, 2.2), rot=90, model="terminal", name="Engineering Grid Terminal", dialogue="engineering_terminal")
    obj("eng_body", "corpse", "engineering", (86.4, 11.5), rot=200, name="Body of Chief Engineer Osei Marsh", cloth="#6b4f3a",
        loot={"tech_components": 3, "respirator_mask": 1, "operator_coat": 1})
    obj("eng_log", "readable", "engineering", (87.4, 12.6), model="datapad", name="Chief Engineer's Datapad", codex="cx_marsh_log",
        on_read=[{"set_flag": "pump_seal_known"}, {"tutorial": "hazards"}])
    pump_opts = lambda flag, key: [
        {"id": "restart", "label": "Reseat the seal and restart the pump", "skill": "repair", "dc": 12, "max_attempts": 2, "hide_if": [{"flag": flag}],
         "success": [{"set_flag": flag}], "success_text": "The pump shudders and catches. Coolant pressure stabilises.",
         "failure": [{"damage_party": 3, "dtype": "thermal", "who": "actor"}], "failure_text": "Scalding vapour lashes out; the seal is still loose.", "xp": 40, "key": key},
        {"id": "kit", "label": "Install a Pump Seal Kit (no check)", "requires_item": "pump_seal", "consume_item": True, "hide_if": [{"flag": flag}],
         "success": [{"set_flag": flag}], "success_text": "The fabricated seal clicks into place and the pump restarts.", "xp": 40, "key": key}]
    obj("pump_n", "pump", "engineering", (100.0, -4.7), model="pump", name="North Coolant Pump", options=pump_opts("pump_north_fixed", "pump_n"))
    obj("pump_s", "pump", "engineering", (88.0, 19.8), model="pump", name="South Coolant Pump", options=pump_opts("pump_south_fixed", "pump_s"))
    rules.append({"id": "r_pumps", "if": [{"flag": "pump_north_fixed"}, {"flag": "pump_south_fixed"}], "effects": [{"set_flag": "pumps_restored"}, {"notify": "Both coolant pumps are running. The archive purge and the bay turrets have power again."}]})
    obj("vent_n", "hazard", "engineering", (96.5, -3.0), model="hazard", name="Venting Coolant", hazard="toxin", size=[12, 6], color="#7fd0ff",
        active_if=[{"not": {"flag": "pump_north_fixed"}}])
    for i, (x, z) in enumerate([(93.0, 19.0), (97.0, 17.5), (100.5, 20.0), (104.0, 18.0)]):
        obj("plate_%d" % (i + 1), "hazard", "engineering", (x, z), model="hazard", name="Live Deck Plate", hazard="shock", size=[2, 2], color="#7fd0ff",
            hidden_dc=13, notice_range=5.0, active_if=[{"not": {"flag": "plates_disabled"}}])
    obj("eng_junction", "panel", "engineering", (90.2, 21.6), rot=180, model="junction", name="Deck Grid Junction",
        options=[{"id": "isolate", "label": "Isolate the live deck plates", "skill": "repair", "dc": 12, "max_attempts": 2, "hide_if": [{"flag": "plates_disabled"}],
                  "success": [{"set_flag": "plates_disabled"}], "success_text": "The plates go dark.",
                  "failure": [{"damage_party": 3, "dtype": "energy", "who": "actor"}], "failure_text": "The junction bites back with a jolt.", "xp": 40, "key": "plates"}])
    obj("eng_workbench", "workbench", "workshop", (96.0, 27.9), rot=180, model="workbench", name="Workshop Bench")
    obj("eng_muster", "muster", "workshop", (98.6, 24.4), model="muster", name="Workshop Muster Point")
    trigger("t_eng_tut", [83, 0, 89, 16], effects=[{"tutorial": "crafting"}])
    trigger("t_duct_bypass", [112, 21, 114, 26], if_=[{"encounter": "enc_engineering", "state": "pending"}],
            effects=[{"resolve_encounter": "enc_engineering", "resolution": "bypassed"}, {"set_flag": "engineering_bypassed"}, {"notify": "The maintenance duct carried you past the Sentinel post."}])
    trigger("t_archive_bypass_eng", [112, -4, 120, 20], if_=[{"encounter": "enc_engineering", "state": "pending"}],
            effects=[{"resolve_encounter": "enc_engineering", "resolution": "bypassed"}, {"set_flag": "engineering_bypassed"}])

    # ================================================================ ARCHIVE
    obj("arc_index", "terminal", "archive", (131.0, -2.4), rot=0, model="terminal", name="Archive Index Terminal", dialogue="archive_index", color="#3fb6b0")
    obj("arc_slate", "readable", "archive", (114.6, 12.4), model="datapad", name="Reclaimer Field Slate", codex="cx_lantern")
    obj("arc_crane", "panel", "archive", (131.5, 17.2), rot=180, model="console", name="Cargo Crane Console", color="#d8a43a",
        options=[{"id": "drop", "label": "Drop the crane's load on the central aisle", "skill": "computer_use", "dc": 12, "max_attempts": 2,
                  "hide_if": [{"any": [{"flag": "crane_dropped"}, {"encounter": "enc_archive", "state": "resolved"}]}],
                  "success": [{"set_flag": "crane_dropped"}, {"area_damage": [124.0, 8.0], "radius": 3.2, "dice": "3d6", "dtype": "kinetic", "status": "knocked_down", "duration": 6.0, "faction": "lantern"},
                              {"start_encounter": "enc_archive"}],
                  "success_text": "Two tonnes of cargo crash into the aisle.", "failure_text": "The console rejects the command.", "noise": 4, "xp": 30, "key": "crane"}])
    obj("arc_purge", "panel", "archive", (115.0, 17.6), rot=180, model="valve", name="Archive Coolant Purge", color="#7fd0ff",
        options=[{"id": "purge", "label": "Flood the central aisle with freezing coolant", "if": [{"flag": "pumps_restored"}],
                  "locked_text": "No pressure: the engineering coolant pumps are down.",
                  "hide_if": [{"any": [{"flag": "arc_purged"}, {"encounter": "enc_archive", "state": "resolved"}]}],
                  "success": [{"set_flag": "arc_purged"}, {"area_damage": [124.0, 8.0], "radius": 4.5, "dice": "1d6", "dtype": "thermal", "status": "immobilized", "duration": 9.0, "faction": "lantern"},
                              {"start_encounter": "enc_archive"}],
                  "success_text": "A white wall of coolant fog rolls down the aisle and freezes the reclaimers in place.", "xp": 30, "key": "arc_purge"}])
    obj("arc_intercom", "terminal", "archive", (132.6, 10.4), rot=-90, model="terminal", name="Command Intercom", dialogue="command_intercom", color="#e8823a")
    obj("cold_crates", "container", "coldstore", (119.2, 24.4), model="crate", name="Cold Storage Crates",
        loot={"med_reagents": 2, "frag_mine": 1, "power_cell": 1},
        on_looted=[{"set_flag": "senna_found"}, {"npc": "senna", "set": {"spawn": True}}])
    obj("senna_spot", "readable", "coldstore", (124.0, 24.8), model="datapad", name="Smeared Blood Trail", hidden_dc=12, notice_range=8.0, codex="cx_lantern",
        on_detect=[{"set_flag": "senna_found"}, {"npc": "senna", "set": {"spawn": True}}, {"notify": "Someone is breathing behind the crates."}])
    npc("senna", "Senna Thorne", "coldstore", (124.5, 23.6), rot=200, template="senna_thorne", faction="lantern",
        appearance={"body": "slight", "head": "angular", "hair": "swept", "skin": "s6", "hair_color": "h3", "accent": "a1"}, armor_look="travel_jacket",
        dialogue="senna", if_=[{"flag": "senna_found"}], downed_pose=True)
    trigger("t_cold", [118, 21, 126, 27], if_=[{"not": {"flag": "senna_found"}}],
            effects=[{"set_flag": "senna_found"}, {"npc": "senna", "set": {"spawn": True}}, {"notify": "A wounded reclaimer is hiding behind the cold-storage crates."}])

    # ================================================================ COMMAND
    npc("varr", "Commander Ysolde Varr", "command", (145.0, 9.5), rot=-90, template="commander_varr", faction="crew",
        appearance={"body": "average", "head": "long", "hair": "tail", "skin": "s1", "hair_color": "h5", "accent": "a2"}, armor_look="security_weave", dialogue="varr", idle="guard")
    obj("cmd_core", "terminal", "command", (140.0, 3.0), model="core", name="Archive Master Core (WARDEN)", dialogue="warden_core", verb="Commune with the WARDEN")
    obj("cmd_console", "terminal", "command", (146.4, 3.6), rot=-90, model="launch_console", name="Launch Control", dialogue="launch_console", verb="Use launch control")
    obj("cmd_muster", "muster", "command", (137.6, 14.0), model="muster", name="Command Muster Point")

    # ================================================================ BAY
    obj("bay_spec", "readable", "bay", (151.0, 10.0), rot=90, model="terminal", name="Petrel Launch Placard", codex="cx_petrel")
    obj("bay_terminal", "terminal", "bay", (152.4, 21.0), rot=90, model="terminal", name="Bay Defense Terminal", dialogue="bay_terminal")
    obj("petrel_ramp", "panel", "bay", (166.0, 12.8), model="launch_console", name="Petrel Boarding Ramp",
        options=[{"id": "board", "label": "Board the Petrel and launch", "if": [{"flag": "bay_resolved"}], "locked_text": "The bay is not secure yet.",
                  "dialogue": "launch"}])
    trigger("t_bay", [150, -8, 158, 24], encounter="enc_bay", alert=False, dialogue="bay_quill", speaker_uid="bay_quill",
            effects=[{"autosave": "Evacuation Bay"}])

    # NPC conditions use 'if' in JSON (if_ avoids the Python keyword).
    for n in L["npcs"].values():
        if "if_" in n:
            v = n.pop("if_")
            if v:
                n["if"] = v
    for o in L["objects"]:
        pass
    for t in L["triggers"]:
        if "if_" in t:
            v = t.pop("if_")
            if v:
                t["if"] = v
