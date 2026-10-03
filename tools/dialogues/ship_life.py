# Ambient voices of the Cinder Wake (data/ship_life.json), played by
# scripts/world/ship_life.gd outside conversations:
#   barks          one-liners on events (combat, kills, a fall, an area, a rest)
#   banter         short exchanges between companions while exploring
#   announcements  WARDEN and intercom calls over the ship's speakers
#   hooks          a companion asks to talk; the topic opens in their hub
# Every line is optional colour: nothing here changes rules, rewards or the
# story's state except one-time ledger keys and the hook flags themselves.
#
# Fields: id, speaker, text, on (the event), match {key: value} on the event's
# data, if (conditions), area ("any" or an area id), chance, once, cooldown (s).

IONA = [{"in_party": "iona"}]
TAV = [{"in_party": "tav7"}]
BOTH = [{"in_party": "iona"}, {"in_party": "tav7"}]
WARDEN_LIVE = [{"flag": "emergency_started"}, {"not": {"flag": "warden_neutralized"}}, {"not": {"flag": "warden_fate"}}]


def B(bid, on, speaker, text, **kw):
    d = {"id": bid, "on": on, "speaker": speaker, "text": text}
    d.update(kw)
    return d


BARKS = [
    # ---- combat starts
    B("bk_iona_cs_1", "combat_started", "iona", "Contact! Get to cover.", chance=0.5),
    B("bk_iona_cs_2", "combat_started", "iona", "Here they come. Stay off the open deck.", chance=0.5),
    B("bk_tav_cs_1", "combat_started", "tav7", "Hostiles. I am going to be brave now. Please notice.", chance=0.4),
    B("bk_tav_cs_2", "combat_started", "tav7", "I will keep you upright. That is my whole plan.", chance=0.4),
    B("bk_iona_chk", "encounter_started", "iona", "That's Kell's checkpoint. Was. Make it count.", match={"id": "enc_checkpoint"}, once=True),
    B("bk_iona_med", "encounter_started", "iona", "Cutters on the patients! Pull them off!", match={"id": "enc_medical"}, once=True),
    B("bk_tav_eng", "encounter_started", "tav7", "The spiders are using the coolant fog as cover. Please do not breathe it.", match={"id": "enc_engineering"}, once=True),
    B("bk_iona_arc", "encounter_started", "iona", "Haldis amber. Reclaimers. They came for the hold.", match={"id": "enc_archive"}, once=True),
    B("bk_tav_arc", "encounter_started", "tav7", "They are not firing near the cores. Note that.", match={"id": "enc_archive"}, once=True, delay=2.5),
    B("bk_iona_bay", "encounter_started", "iona", "Bay's hot! Keep the Petrel between us and their guns.", match={"id": "enc_bay"}, once=True),
    # ---- the other side
    B("bk_rec_cs_1", "combat_started", "reclaimer", "Concord! Down on the deck!", chance=0.35),
    B("bk_rec_cs_2", "combat_started", "reclaimer", "For the lantern halls!", chance=0.35),
    B("bk_drn_cs_1", "combat_started", "drone", "OBSTRUCTION DETECTED. CLEARING.", chance=0.35),
    B("bk_drn_cs_2", "combat_started", "drone", "PLEASE REMAIN STILL.", chance=0.35),
    # ---- kills
    B("bk_iona_kill_d", "enemy_killed", "iona", "Drone down.", match={"template": ["picket_drone", "suppression_drone"]}, chance=0.35),
    B("bk_iona_kill_s", "enemy_killed", "iona", "Scratch one.", chance=0.2),
    B("bk_tav_kill_s", "enemy_killed", "tav7", "Disassembled. Not by the manual's method.", match={"template": ["spider_drone", "warden_turret", "warden_sentinel"]}, chance=0.4),
    B("bk_tav_kill_r", "enemy_killed", "tav7", "I am remembering their face for the Lantern Office.", match={"template": ["reclaimer_breacher", "reclaimer_marksman", "reclaimer_signalist"]}, chance=0.3),
    # ---- someone falls, someone gets up
    B("bk_iona_down_p", "ally_downed", "iona", "Operator's down! Covering!", match={"uid": "player"}),
    B("bk_tav_down_p", "ally_downed", "tav7", "Your vital signs are unacceptable. I am coming.", match={"uid": "player"}),
    B("bk_tav_down_i", "ally_downed", "tav7", "Officer Rell is down. Medpac, please. Now, please.", match={"uid": "iona"}),
    B("bk_iona_down_t", "ally_downed", "iona", "Tav's hit! Somebody get that chassis up!", match={"uid": "tav7"}),
    B("bk_iona_up", "ally_recovered", "iona", "I'm up. That one's going in my report.", match={"uid": "iona"}),
    B("bk_tav_up", "ally_recovered", "tav7", "Rebooted. I have lost eleven seconds. I would like them back.", match={"uid": "tav7"}),
    # ---- after the fight
    B("bk_iona_ce_1", "combat_ended", "iona", "Clear. Check your corners.", chance=0.5),
    B("bk_iona_ce_2", "combat_ended", "iona", "That's the last of them. Breathe.", chance=0.5),
    B("bk_tav_ce_1", "combat_ended", "tav7", "Hostilities concluded. Shall I inventory the wounded? It is us. We are the wounded.", chance=0.4),
    # ---- under pressure (from the combat presentation layer)
    B("bk_iona_low", "low_health", "iona", "I'm bleeding here!", match={"uid": "iona"}, cooldown=40),
    B("bk_tav_low", "low_health", "tav7", "Chassis integrity at one third. This is a polite request for repair.", match={"uid": "tav7"}, cooldown=40),
    B("bk_iona_crit", "crit", "iona", "Good hit.", chance=0.3),
    B("bk_tav_crit", "crit", "tav7", "Excellent. Statistically, at least.", chance=0.3),
    # ---- rest
    B("bk_iona_rest", "rested", "iona", "Two minutes. Then we move."),
    B("bk_tav_rest", "rested", "tav7", "I will watch the doors. I do not need to sit. I like to, though.", delay=1.5),
    # ---- first steps into each part of the ship
    B("bk_iona_chk_in", "area_entered", "iona", "Officer Kell had this post. She'd have hated seeing it like this.", match={"area": "checkpoint", "first": True}, once=True, delay=1.0),
    B("bk_iona_med_in", "area_entered", "iona", "Varga's deck. If anyone's still breathing in there, she's keeping them that way.", match={"area": "medical", "first": True}, once=True, delay=1.0),
    B("bk_iona_ward_in", "area_entered", "iona", "...Ward 2.", match={"area": "ward", "first": True}, once=True, delay=0.8),
    B("bk_tav_eng_in", "area_entered", "tav7", "The drive ring. I was maintained here every quarter. It smells the same. I did not expect that to matter.", match={"area": "engineering", "first": True}, once=True, delay=1.5),
    B("bk_tav_arc_in", "area_entered", "tav7", "Twenty cores. I can hear them, faintly. That is not a figure of speech.", match={"area": "archive", "first": True}, once=True, delay=1.5),
    B("bk_iona_cmd_in", "area_entered", "iona", "Varr's in there. Let me talk first. Or don't. Your call.", match={"area": "command", "first": True}, once=True, delay=1.0),
    B("bk_tav_bay_in", "area_entered", "tav7", "The Petrel. Fifteen seats. I have counted them four times; the number does not change.", match={"area": "bay", "first": True}, once=True, delay=2.0),
    # ---- approval after a conversation (net influence change)
    B("bk_iona_ok_1", "approve", "iona", "That was the right call. I'll remember it."),
    B("bk_iona_ok_2", "approve", "iona", "Huh. You surprised me. In a good way."),
    B("bk_iona_no_1", "disapprove", "iona", "We're going to talk about that later."),
    B("bk_iona_no_2", "disapprove", "iona", "I'd have done that differently. I'd have done it better."),
    B("bk_tav_ok_1", "approve", "tav7", "I approve. I am telling you because I have read that people like to know."),
    B("bk_tav_ok_2", "approve", "tav7", "That was kind. I am adding it to my notes on you."),
    B("bk_tav_no_1", "disapprove", "tav7", "I disagree. I will continue to help. I want that recorded."),
    B("bk_tav_no_2", "disapprove", "tav7", "That decision has been logged. With a frown. I do not have a face for it, but there is a frown."),
]

BANTER = [
    {"id": "bn_iona_alone", "area": "any", "if": IONA + [{"not": {"recruited": "tav7"}}, {"cleared": "enc_corridor"}], "once": True, "lines": [
        {"speaker": "iona", "text": "For the record: I didn't sign up to escort a Lattice operator through a hostile ship."},
        {"speaker": "iona", "text": "For the record, I'm glad it's you anyway. Don't make me regret saying that.", "delay": 1.2}]},
    {"id": "bn_kell", "area": "any", "if": BOTH + [{"flag": "checkpoint_clear"}], "once": True, "priority": 2, "lines": [
        {"speaker": "iona", "text": "Tav. You knew Tamsin Kell?"},
        {"speaker": "tav7", "text": "She requested maintenance on her door chime every week. There was never a fault. I think she liked the company.", "delay": 0.8},
        {"speaker": "iona", "text": "...Yeah. That sounds like Tamsin.", "delay": 1.0}]},
    {"id": "bn_boot", "area": "any", "if": BOTH, "once": True, "lines": [
        {"speaker": "tav7", "text": "Officer Rell. Your left boot is coolant-burned through the second layer."},
        {"speaker": "iona", "text": "I know. I was there.", "delay": 0.6},
        {"speaker": "tav7", "text": "I can patch it. I would like to. It would give my hands something to do that is not fear.", "delay": 0.8},
        {"speaker": "iona", "text": "...Fine. After. Thank you, Tav.", "delay": 1.0}]},
    {"id": "bn_coffee", "area": "engineering", "if": BOTH, "once": True, "priority": 2, "lines": [
        {"speaker": "iona", "text": "Marsh kept a coffee maker on the drive ring. Against regulations."},
        {"speaker": "tav7", "text": "It ran at ninety-six degrees. Also against regulations. I never reported it.", "delay": 0.6},
        {"speaker": "iona", "text": "Look at you. A rule-breaker.", "delay": 0.6},
        {"speaker": "tav7", "text": "I am practising that too.", "delay": 0.6}]},
    {"id": "bn_cores", "area": "archive", "if": BOTH + [{"flag": "index_open"}], "once": True, "priority": 3, "lines": [
        {"speaker": "iona", "text": "Twenty cores. Varr told me it was medical data."},
        {"speaker": "tav7", "text": "It is, in a sense. It is what happened to people.", "delay": 0.8},
        {"speaker": "iona", "text": "Don't. Not yet. Let me be angry at her for one more hour.", "delay": 1.0}]},
    {"id": "bn_count", "area": "any", "if": BOTH + [{"flag": "tav7_disclosed"}], "once": True, "priority": 2, "lines": [
        {"speaker": "tav7", "text": "Officer Rell, how many people are aboard?"},
        {"speaker": "iona", "text": "I don't know anymore. Fewer than this morning.", "delay": 0.8},
        {"speaker": "tav7", "text": "I keep counting the ones in my storage. I do not know if they count.", "delay": 1.0},
        {"speaker": "iona", "text": "They count, Tav. Keep counting them.", "delay": 1.2}]},
    {"id": "bn_operator", "area": "any", "if": BOTH + [{"any": [{"flag": "used_credential"}, {"flag": "custodian_revealed"}]}], "once": True, "lines": [
        {"speaker": "iona", "text": "Operator. When this is over, are you going to tell me what the Lattice actually did?"},
        {"speaker": "tav7", "text": "I would also like to know. I have a folder.", "delay": 0.8},
        {"speaker": "iona", "text": "Of course you do.", "delay": 0.6}]},
]

ANNOUNCEMENTS = [
    # Right after the emergency is declared: the ship's new priorities.
    {"id": "an_warden_obstruct", "speaker": "warden", "on": "flag", "match": {"flag": "emergency_started"}, "once": True, "delay": 2.0,
     "text": "ATTENTION. ALL NON-COMMAND PERSONNEL ARE RECLASSIFIED AS ARCHIVE OBSTRUCTIONS. OBSTRUCTIONS WILL BE CLEARED. PLEASE REMAIN STILL."},
    # First steps into an area (layout on_enter: {"bark": id}).
    {"id": "an_warden_checkpoint", "speaker": "warden", "if": WARDEN_LIVE, "text": "FORWARD CHECKPOINT SEALED. AUTHORIZED PERSONNEL ONLY. CUSTODIAN EXCEPTION ON FILE."},
    {"id": "an_warden_medical", "speaker": "warden", "if": WARDEN_LIVE, "text": "MEDICAL DECK: TRIAGE CAPACITY EXCEEDED. ARCHIVE PRIORITY UNCHANGED."},
    {"id": "an_warden_engineering", "speaker": "warden", "if": WARDEN_LIVE, "text": "COOLANT LOSS IN THE DRIVE RING. THE ARCHIVE REMAINS AT TEMPERATURE. THANK YOU FOR YOUR PATIENCE."},
    {"id": "an_warden_archive", "speaker": "warden", "if": WARDEN_LIVE, "text": "YOU ARE IN THE ARCHIVE HOLD. PLEASE DO NOT TOUCH THE ARCHIVE. PLEASE."},
    {"id": "an_warden_command", "speaker": "warden", "if": WARDEN_LIVE, "text": "COMMAND CHAMBER. CUSTODIAN, THE COMMANDER IS EXPECTING YOU. SO AM I."},
    {"id": "an_warden_bay", "speaker": "warden", "if": WARDEN_LIVE, "text": "EVACUATION BAY 2. FIFTEEN SEATS. RECOUNTING."},
    # Now and then while exploring.
    {"id": "an_warden_t1", "speaker": "warden", "on": "timer", "if": WARDEN_LIVE, "once": True,
     "text": "REMINDER: RUNNING IN CORRIDORS IS AN OBSTRUCTION."},
    {"id": "an_warden_t2", "speaker": "warden", "on": "timer", "if": WARDEN_LIVE, "once": True,
     "text": "DEFENSE LATTICE AT NINETY-ONE PERCENT. ARCHIVE INTEGRITY AT ONE HUNDRED PERCENT. THIS IS ACCEPTABLE."},
    {"id": "an_warden_t3", "speaker": "warden", "on": "timer", "if": WARDEN_LIVE, "once": True,
     "text": "PASSENGERS WISHING TO FILE A COMPLAINT MAY DO SO AFTER THE ARCHIVE HAS BEEN DELIVERED."},
    {"id": "an_warden_t4", "speaker": "warden", "on": "timer", "if": WARDEN_LIVE + [{"flag": "used_credential"}], "once": True,
     "text": "CUSTODIAN. YOUR HEART RATE IS ELEVATED. I HAVE NOTED IT. I HAVE NOTED EVERYTHING."},
    {"id": "an_dray_1", "speaker": "intercom", "on": "timer", "if": [{"flag": "emergency_started"}, {"cleared": "enc_corridor"}], "once": True,
     "text": "This is Purser Dray. I have everyone from Deck B in the commons. I've counted twice. If you're out there: we're still here."},
    {"id": "an_dray_2", "speaker": "intercom", "on": "timer", "if": [{"cleared": "enc_medical"}], "once": True,
     "text": "Dray again. Someone says the medical deck has gone quiet. If that was you, thank you. Please keep doing it."},
    {"id": "an_dray_3", "speaker": "intercom", "on": "flag", "match": {"flag": "pumps_restored"}, "once": True, "delay": 3.0,
     "text": "Dray here. The vents just stopped screaming. I don't know who did that. I'm putting them on the manifest twice."},
]

HOOKS = [
    {"id": "hk_iona_orrin", "companion": "iona", "flag": "hook_iona_orrin", "done_flag": "iona_orrin_done",
     "if": IONA + [{"cleared": "enc_corridor"}, {"flag": "checkpoint_clear"}],
     "bark": "When you get a second... I need to say something about Jessa Orrin."},
    {"id": "hk_tav_triage", "companion": "tav7", "flag": "hook_tav_triage", "done_flag": "tav_triage_done",
     "if": TAV + [{"flag": "supplies_decided"}, {"cleared": "enc_medical"}],
     "bark": "Operator. I have a question about the doctor's arithmetic, when you have a moment."},
]

SHIP_LIFE = {
    "config": {
        "range": 18.0,          # party speakers within this distance of the leader
        "bark_gap": 6.0,        # minimum seconds between barks
        "speaker_gap": 10.0,    # minimum seconds before the same speaker barks again
        "cooldown": 90.0,       # default per-line cooldown for repeatable lines
        "banter_gap": [70, 140],
        "announce_gap": [110, 200],
    },
    "barks": BARKS,
    "banter": BANTER,
    "announcements": ANNOUNCEMENTS,
    "hooks": HOOKS,
}

DIALOGUES = []
OUTPUTS = {"ship_life": SHIP_LIFE}
