# Prologue: cabin, commons, the emergency.

INTRO = {
    "id": "intro_wake",
    "names": {"intercom": "Ship Intercom — Purser Dray"},
    "entry": [{"node": "start"}],
    "nodes": {
        "start": N("narrator", "The deck hums against your back. Transfer Cabin 4-C: a bunk, a desk, a viewport full of Haldis Reach shrinking to an amber coin. Somewhere aft, the Cinder Wake's drive is spooling for the jump.", nxt="intercom"),
        "intercom": N("intercom", "Attention passengers. This is Purser Dray. We have cleared Haldis high orbit. All evacuees please report to Muster Point B in the crew commons for manifest check-in before jump. Thank you for flying with the Concord Evacuation Authority. Please do not touch the archive hold.", nxt="memory"),
        "memory": N("narrator", "You remember all of it: the Lattice Corps, the operator's chair, the war over the world below. You remember the last link, the morning you took the cable out of your skull and told your commander you were finished. The hum at the back of your head never quite left.",
            C("The people still on Haldis are waiting for ships that won't come. I owe them better than staring out a window.", "end_c", tone="compassionate", effects=[flag("opening_tone", "compassionate")]),
            C("Check in, keep your head down, make the jump. One step at a time.", "end_p", tone="pragmatic", effects=[flag("opening_tone", "pragmatic")]),
            C("This ticket is the only thing I got out of that war. Nobody is taking it from me.", "end_s", tone="self-interested", effects=[flag("opening_tone", "self")]),
            C("A Concord ship carrying 'medical archive cores' out of a warzone. I've read cargo manifests before.", "end_k", tone="skeptical", effects=[flag("opening_tone", "skeptical")]),
            C("Six years in the Lattice. A cramped cabin is not what scares me.", "end_h", tone="hard", effects=[flag("opening_tone", "hard")])),
        "end_c": N("narrator", "You straighten your coat. Muster Point B, then. Maybe someone there needs a steady hand.", nxt="tut", effects=[]),
        "end_p": N("narrator", "Locker, case, commons. You have done harder checklists under fire.", nxt="tut"),
        "end_s": N("narrator", "You check your pockets twice. The war took enough. The rest is yours.", nxt="tut"),
        "end_k": N("narrator", "You file the thought away where the Lattice taught you to keep things that might matter later.", nxt="tut"),
        "end_h": N("narrator", "You roll your shoulders until the old scar along your neck stops pulling.", nxt="tut"),
        "tut": N("system", "Your locker and operator's case are here in the cabin. Muster Point B is through the door, in the crew commons.", effects=[{"tutorial": "movement"}], end=True),
    },
}

STEWARD = {
    "id": "steward",
    "entry": [
        {"if": [{"flag": "emergency_started"}], "node": "after"},
        {"if": [{"flag": "dray_met"}], "node": "again"},
        {"node": "start"},
    ],
    "nodes": {
        "start": N("steward", "Name? Sorry, sorry, it's the jump, everyone gets nervous at the jump. Passenger {name}, cabin 4-C. Ah. You're the... Lattice Corps. Discharged.", nxt="bg", effects=[flag("dray_met")]),
        "bg": R(([{"background": "veteran"}], "vet"), ([{"background": "colonist"}], "col"), ([{"background": "salvager"}], "sal")),
        "vet": N("steward", "My nephew was a vanguard on the Callan line. Came home with half his hearing. Thank you for, well. For whatever you did out there.", nxt="hub"),
        "col": N("steward", "You're... Haldis-born? Born there and flew for the Concord. That can't have made you many friends on either side. I'm not judging. I'm a purser. I count people, I don't weigh them.", nxt="hub"),
        "sal": N("steward", "Breaker yards after the corps, it says. Then you can probably fix the sim booth. It's eaten three of Brann Ketterick's tokens.", nxt="hub"),
        "hub": N("steward", "Muster check-in only takes a moment, but corridor C-3 stays in departure lockdown until the jump spools, so there's no hurry. There's a card table, the racing sim, and the requisition terminal still takes colony scrip.",
            C("What is this ship actually carrying?", "cargo", tone="skeptical"),
            C("Those ships shadowing us off the port side. Who are they?", "lantern"),
            C("How are the other passengers holding up?", "people", tone="compassionate"),
            C("Tell me about the WARDEN defense network.", "warden"),
            C("Check me in. I'm ready.", "checkin"),
            C("I'll take a look around first.", end=True)),
        "again": N("steward", "Back again? Check-in's open whenever you're ready, {name}.",
            C("What is this ship actually carrying?", "cargo"),
            C("Who's shadowing us?", "lantern"),
            C("Check me in.", "checkin"),
            C("Later.", end=True)),
        "cargo": N("steward", "Passengers, mostly. Medical supplies. And the archive hold, which I'm told contains 'Concord medical archive cores for the Tessaly tribunal' and which I'm told, firmly, not to ask about. Commander Varr has the only access. The WARDEN guards it.",
            C("A tribunal? Who's on trial?", "tribunal"),
            C("Back to the other questions.", "hub")),
        "tribunal": N("steward", "War crimes inquiry, the bulletins say. Both sides accuse the other. I don't follow it. I count heads and hand out blankets.", nxt="hub", effects=[xp(10, "dray_tribunal", "Asked about the tribunal")]),
        "lantern": N("steward", "Lantern Office pickets. Haldis Free Assembly. Reclamation corps, they call themselves. They've been hailing us since orbit, demanding we 'return what was taken'. The commander isn't answering. Don't worry: the Concord flag still means something out here.",
            C("And if it doesn't?", "lantern2", tone="skeptical"),
            C("Back to the other questions.", "hub")),
        "lantern2": N("steward", "Then I suppose we find out what the WARDEN is for.", nxt="hub"),
        "people": N("steward", "Frightened. The Venn woman's boy hasn't said a word since we boarded. Brann's losing at cards to calm his nerves. Three of the medical deck's patients are in a bad way. Don't tell anyone I said that.", nxt="hub", effects=[align(2, "dray_people", "Asked after the other passengers")]),
        "warden": N("steward", "Integrated defense lattice. Concord surplus from the war, refitted. It runs the turrets, the security drones, the locks. It's never said a word to me in three years. It talks to the commander. Honestly, it gives me the shivers.", nxt="hub"),
        "checkin": N("steward", "Lovely. {name}, cabin 4-C, checked in at — ", nxt="boom", effects=[flag("checked_in")]),
        "boom": N("narrator", "The deck jumps. Light fixtures swing on their cables. A long groan of tortured metal rolls forward from the stern, then a muffled thud, then another. Every panel in the commons flashes red.", nxt="warden_says"),
        "warden_says": N("warden", "ARCHIVE PROTECTION PROTOCOL ENGAGED. HULL BREACH: DORSAL, ARCHIVE SECTION. BOARDERS DETECTED. ALL NON-ESSENTIAL PERSONNEL ARE CLASSIFIED AS ARCHIVE OBSTRUCTIONS. OBSTRUCTIONS WILL BE CLEARED. PLEASE REMAIN STILL.", nxt="dray2"),
        "dray2": N("steward", "Remain — WARDEN, belay that! I am the purser, these are passengers! Oh, saints. Oh no. Listen to me. Everyone stay in the commons. {name}! You were Lattice Corps. Security's pinned down in corridor C-3, I can hear them on the band. Please. I can't — I count people.",
            C("Keep everyone here and keep them calm. I'll go.", "go_c", tone="compassionate", effects=[align(5, "dray_go", "Answered Dray's plea for help"), flag("promised_dray")]),
            C("The corridor's the way forward anyway. I'll see what's there.", "go_p", tone="pragmatic"),
            C("Why should I risk my neck for the ship's security?", "go_s", tone="self-interested"),
            C("Dray. Breathe. Lock this door behind me and do not open it for anything that isn't human.", "go_h", tone="hard")),
        "go_c": N("steward", "Thank you. Thank you. We'll be right here.", nxt="unlock"),
        "go_p": N("steward", "Forward, yes. The launch craft's forward too. Bay 2. If anyone makes it off this ship, it's from there.", nxt="unlock"),
        "go_s": N("steward", "Because the launch craft is past them! Because if security falls there's nobody between those drones and the rest of us! I — please.", nxt="unlock"),
        "go_h": N("steward", "Nothing that isn't human. Right. Right.", nxt="unlock"),
        "unlock": N("system", "The lockdown on Corridor C-3 releases. Purser Dray gathers the passengers around Muster Point B; they will follow your route toward the launch bays.",
            effects=[flag("emergency_started"), {"survivors": 4, "key": "commons_group"}, {"world": "d_commons_east", "set": {"locked": False}},
                     {"tutorial": "muster"}, {"sound": "alarm"}], end=True),
        "after": N("steward", "We're holding here, like you said. Bay 2, {name}. The launch craft is at Bay 2. Please hurry.",
            C("Stay together. I'll come back for you or clear the way.", end=True),
            C("Go.", end=True)),
    },
}

VENN = {
    "id": "venn_family",
    "names": {"dalia": "Dalia Venn"},
    "entry": [
        {"if": [{"flag": "emergency_started"}, {"flag": "venn_emergency_talked"}], "node": "after2"},
        {"if": [{"flag": "emergency_started"}], "node": "after"},
        {"if": [{"flag": "venn_met"}], "node": "again"},
        {"node": "start"},
    ],
    "nodes": {},
}
VENN["nodes"]["start"] = N("dalia", "Oh, sorry, we're in your way. Ilo, sit down, love. He hasn't spoken since we left the surface. He keeps looking at the hull like it's going to open.",
    C("Hey, Ilo. Ships like this are built to take a beating. I've seen worse hold together.", "kind", tone="compassionate", effects=[align(3, "venn_kind", "Comforted a frightened child")]),
    C("Where are you headed?", "where"),
    C("(In Haldis dialect) Little sparrow, the sky only looks big from the ground.", "dialect", tone="compassionate", cond=[{"background": "colonist"}], tag="Haldis Native"),
    C("Keep him close and keep out of the way if anything happens.", "practical", tone="pragmatic"),
    effects=[flag("venn_met")])
VENN["nodes"].update({
    "kind": N("dalia", "Did you hear that, Ilo? The operator says so. Thank you. You don't know what that face does to me.", nxt="where"),
    "dialect": N("narrator", "Ilo's head snaps around at the sound of home. For the first time since you sat down, he almost smiles.", nxt="dialect2", effects=[xp(20, "venn_dialect", "Reached Ilo in his own language")]),
    "dialect2": N("dalia", "You're from the Reach. And you flew for the Lattice. I worked for the Concord too. A clerk. Nobody asks clerks what they signed.", nxt="where"),
    "practical": N("dalia", "Out of the way. Yes. That's been our whole war.", nxt="where"),
    "where": N("dalia", "Tessaly. My sister's there. I filed Concord paperwork for nine years on Haldis, and now the Assembly calls me a collaborator and the Concord calls me a refugee. Ilo just calls me tired.",
        C("For what it's worth, I hope Tessaly is kind to you both.", end=True, effects=[align(1, "venn_hope", "Wished the Venns well")]),
        C("The Concord owes you. Make them pay it.", end=True),
        C("Good luck.", end=True)),
    "again": N("dalia", "Ilo's drawing ships now. That's an improvement.", C("Take care of each other.", end=True)),
    "after": N("dalia", "What's happening? The announcement said obstructions, what does that mean, are we obstructions? Ilo, Ilo, look at me.",
        C("Stay with Purser Dray at the muster point. I promise I'll clear the way to the launch craft.", "promise", tone="compassionate", effects=[flag("promised_venns"), align(4, "venn_promise", "Promised the Venns safe passage")]),
        C("Stay here and stay down. That's all I can tell you.", "down", tone="pragmatic"),
        C("I don't know. Nobody does. Keep him quiet.", "down", tone="hard")),
    "promise": N("dalia", "You promise. All right. All right, Ilo, the operator promised.", effects=[flag("venn_emergency_talked")], end=True),
    "down": N("dalia", "Down. We know how to do down.", effects=[flag("venn_emergency_talked")], end=True),
    "after2": N("dalia", "We're staying with Dray. Go. Please.", C("I'm going.", end=True)),
})

KETTERICK = {
    "id": "ketterick",
    "entry": [
        {"if": [{"flag": "emergency_started"}], "node": "after"},
        {"if": [{"flag": "brann_met"}], "node": "again"},
        {"node": "start"},
    ],
    "nodes": {},
}
KETTERICK["nodes"]["start"] = N("ketterick", "Brann Ketterick, contract pilot, temporarily unemployed by an outbreak of peace. You play Shards? Twenty's the number, shards bend the count, and the house — me — is losing badly to the purser's nephew's cousin.",
    C("Deal me in.", "deal"),
    C("How do you play?", "rules"),
    C("Not now.", end=True),
    effects=[flag("brann_met")])
KETTERICK["nodes"].update({
    "rules": N("ketterick", "Each round you draw from the shared deck and your total climbs. Stay at or under twenty, as close as you can. You get four shards from your own side deck: little adjusters, plus or minus. One per turn. Stand when you like. Best of three sets. Bust and you lose the set. Simple. Ruinous.",
        C("Deal me in.", "deal"), C("Maybe later.", end=True)),
    "deal": N("ketterick", "That's the spirit. Wager's yours to call. Sit.", effects=[{"minigame": "shards"}], end=True),
    "again": N("ketterick", "Another set? The deck's warm.", C("Deal me in.", "deal"), C("Later.", end=True)),
    "after": N("ketterick", "Cards can wait for the end of the world, apparently. You want a hand to steady your nerves? I'm serious. My hands are shaking and I fly for a living.",
        C("One set. Deal.", "deal"), C("Stay with Dray, Brann.", end=True)),
})

WOUNDED = {
    "id": "wounded",
    "entry": [
        {"if": [{"flag": "supplies_decided"}], "node": "after"},
        {"node": "start"},
    ],
    "nodes": {
        "start": N("narrator", "The patient is barely conscious, breath rattling. Dr. Varga's tag on the bed reads CRITICAL — TRAUMA GEL REQUIRED.", C("(Step back and speak to Dr. Varga.)", end=True)),
        "after": R(([{"flag": "med_supplies_choice", "eq": "took"}, {"flag": "patient_lost_note"}], "lost"), ([], "stable")),
        "stable": N("narrator", "The patient is breathing easier now. Someone has written THANK YOU on the bed tag in shaky marker.", C("(Leave them to rest.)", end=True)),
        "lost": N("narrator", "A sheet has been drawn up over the bed. Dr. Varga does not look at you.", C("(Step away.)", end=True)),
    },
}

PATIENT = {
    "id": "ward_patient",
    "entry": [{"node": "start"}],
    "nodes": {
        "start": R(([{"flag": "ward_choice", "eq": "rushed"}], "rushed"), ([], "ok")),
        "ok": N("narrator", "The ward patient grips your arm. \"Pell said someone was talking on the intercom. Was that you? Thank you. We'll follow the doctor to the bays.\"", C("Stay close to Dr. Varga.", end=True)),
        "rushed": N("narrator", "The patient coughs, eyes streaming from the coolant still hanging in the air. \"We're out. We're out. Thank you.\"", C("Keep moving. The air's better forward.", end=True)),
    },
}

DIALOGUES = [INTRO, STEWARD, VENN, KETTERICK, WOUNDED, PATIENT]


# In-engine cinematics (data/cinematics.json). Each shot moves the camera from
# `from` to `to` while looking at `look` (world metres; y is height) for `dur`
# seconds, with an optional caption. `black` shots are title cards. A
# `speaker` shot babbles the caption in that speaker's voice. `then` names the
# conversation that starts when the cinematic ends (or is skipped).
CINEMATICS = {
    "prologue": {
        "then": "intro_wake",
        # 0612: the boarders have not arrived yet.
        "hide_enemies": True,
        "shots": [
            {"black": True, "dur": 4.5, "title": "ASHES OF THE CONCORD",
             "caption": "Haldis Reach. Day eighty-nine of the ninety the ceasefire allowed."},
            {"from": [152.5, 4.4, 22.5], "to": [155.5, 3.4, 21.0], "look": [166.0, 1.2, 8.0], "dur": 6.0,
             "caption": "The Concord is leaving the world it fought six years to keep. The evacuation tender Cinder Wake is one of the last ships out."},
            {"from": [113.5, 2.2, 8.2], "to": [117.5, 1.9, 8.2], "look": [126.0, 1.6, 8.0], "dur": 6.0,
             "caption": "Its cargo manifest lists twenty medical archive cores. Nobody aboard has asked what that means."},
            {"from": [137.5, 2.7, 1.5], "to": [139.0, 2.3, 3.5], "look": [142.0, 1.8, 16.0], "dur": 5.5, "speaker": "warden",
             "caption": "0612 SHIP TIME. CUSTODIAN HANDSHAKE RECEIVED. ORIGIN: CABIN 4-C. LOGGING."},
            {"from": [26.5, 2.3, 12.0], "to": [23.5, 2.0, 11.0], "look": [17.0, 1.3, 6.0], "dur": 5.5,
             "caption": "At Muster Point B, Purser Dray counts the passengers, and then counts them again."},
            {"from": [9.0, 1.9, 9.0], "to": [7.6, 1.7, 7.4], "look": [4.6, 1.2, 6.0], "dur": 5.5, "fade_out": 1.0,
             "caption": "In Transfer Cabin 4-C, a discharged Lattice operator is trying very hard to sleep."},
        ],
    },
    "petrel_escape": {
        "hide_party": True, "craft": "Petrel", "sound": "door",
        "shots": [
            {"from": [156.0, 5.5, 20.0], "to": [158.0, 4.0, 17.0], "look": [166.0, 1.6, 8.0], "dur": 3.0,
             "caption": "The docking clamps let go with a sound like a held breath released."},
            {"from": [170.0, 3.0, 18.0], "to": [176.0, 3.5, 16.0], "look": [178.0, 2.0, 8.0], "dur": 3.5, "fly": True,
             "caption": "The Petrel slides out through Bay 2's shimmering field, into the dark above Haldis Reach."},
        ],
    },
}

OUTPUTS = {"cinematics": CINEMATICS}
