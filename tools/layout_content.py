"""Interactive content for the Cinder Wake layout: objects, NPCs, triggers.
Imported by tools/author_layout.py."""


def populate(L, obj, npc, trigger):
    # ------------------------------------------------------------ cabin
    obj("cabin_locker", "container", "cabin", (2.7, 7.6), rot=90, model="locker", name="Personal Locker",
        loot={"medpac": 1, "credits": 40, "travel_jacket": 1})
    obj("cabin_case", "container", "cabin", (6.0, 9.2), rot=180, model="case", name="Sealed Operator's Case",
        loot={"focus_ampoule": 1, "resonance_band": 1},
        on_looted=[{"codex": "cx_operator_case"}, {"set_flag": "case_opened"}])
    obj("cabin_datapad", "readable", "cabin", (8.6, 8.8), model="datapad", name="Transfer Orders", codex="cx_transfer_orders")
    # ------------------------------------------------------------ commons
    obj("commons_vendor", "vendor", "commons", (23.5, 0.6), rot=0, model="vendor", name="Crew Requisition Terminal", vendor="requisition")
    obj("commons_cards", "minigame", "commons", (16.0, 8.0), model="card_table", name="Shards Table", minigame="shards", verb="Play Shards")
    obj("commons_sim", "minigame", "commons", (25.5, 2.5), rot=180, model="booth", name="Slipstream Racing Sim", minigame="slipstream", verb="Race the sim")
    obj("commons_muster", "muster", "commons", (13.5, 9.0), rot=0, model="muster", name="Muster Point B")
    npc("steward", "Purser Hollis Dray", "commons", (24.0, 7.5), rot=-90, appearance={"body": "broad", "head": "round", "hair": "shaved", "skin": "s1", "hair_color": "h5", "accent": "a1"}, armor_look="padded_vest", dialogue="steward")
    npc("dalia", "Dalia Venn", "commons", (14.6, 5.0), rot=60, appearance={"body": "slight", "head": "long", "hair": "long", "skin": "s3", "hair_color": "h2", "accent": "a3"}, armor_look="travel_jacket", dialogue="venn_family")
    npc("ilo", "Ilo Venn", "commons", (15.3, 4.4), rot=60, appearance={"body": "slight", "head": "round", "hair": "crop", "skin": "s3", "hair_color": "h2", "accent": "a3"}, armor_look="travel_jacket", dialogue="venn_family")
    npc("ketterick", "Brann Ketterick", "commons", (16.9, 8.9), rot=200, appearance={"body": "broad", "head": "square", "hair": "crest", "skin": "s5", "hair_color": "h4", "accent": "a4"}, armor_look="travel_jacket", dialogue="ketterick")
