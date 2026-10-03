# Progress log

The plan (`docs/PLAN.md`) was written before implementation. This file records what was built in each
increment, where the result departs from the plan, and what is still open.

## Increments

| # | Increment | Commits (branch `claude/admiring-faraday-5f1rx1`) |
|---|---|---|
| 1 | Project skeleton, data files, rules layer, first unit tests | `e46230d`, `e2cf222` |
| 2 | World runtime: grid navigation, level builder, actors, camera, interactables, combat manager, AI, HUD, dialogue UI | `a7a70f6` |
| 3 | Narrative content: quests, encounters, codex, tutorials, the full ship layout, 27 conversations | `5c16b77` |
| 4 | End-to-end bot playthroughs for 3 routes; rest, hazard-aware pathing, door rules, tactical AI, balance passes | `f972016`, `f6d4802` |
| 5 | Every UI screen: creator with 3D preview, game menu (7 tabs), level-up, vendor, crafting/upgrades, muster, save/load, settings and rebinding, ending, launch cinematic | `b0fd95e` |
| 6 | Developer presets (6 prestige, Iona training, 5 jumps), dev menu, specialization screen, compile-all test | `e95e8c5` |
| 7 | World regression tests, combat approach at the checkpoint, bay level scaling | `9ec2be0` |
| 8 | Procedural audio (delegated to a sub-agent, then reviewed and merged) | `26e6eca`, `e49c117` |
| 9 | Minigames: Shards, Slipstream, turret, practice mode (delegated, reviewed, merged) | `3623be7`, `5ec8085` |
| 10 | Performance tooling and fixes, export presets and builds, screenshots, documentation | `d9ccc4c` and its neighbours |
| 11 | Follow-ups: keyboard movement drives the walk animation; auto-attack at combat start | `9f41655`, `a4c7e4b`, `2f3da3c` |

Immersion pass (branch `claude/wonderful-wozniak-62qtg1`), aiming at the feel of the classic d20 space RPGs:

| # | Increment | Commit |
|---|---|---|
| 12 | Dialogue and voice: babbled voices, text reveal, staged conversations and camera coverage, reactions, prologue cinematic | `50c10ed` |
| 13 | Living companions and ship: barks, banter, announcements, companion hooks, NPC idles | `05aa537` |
| 14 | Atmosphere and the follow camera: ceilings, alert lighting, haze, living props, layered audio | `d1eb65b` |
| 15 | Combat feel and feedback: stances, reactions, sparks, Lumen Edge, bodies, health bars, HUD feedback, alignment look | `00bcfee` |

## Departures from the plan

- **Audio** is synthesized offline by `tools/gen_audio.py` into committed WAV files. The plan said runtime
  synthesis; offline files are easier to test and cheaper at runtime.
- **Party controller.** The plan named `scripts/world/party_controller.gd` and `scripts/ui/map_panel.gd`. Party
  logic lives in `World` and the map in `GameMenu` + `MiniMap`.
- **Integration bot.** It runs inside the normal suite (`tests/test_playthrough.gd`) rather than a separate
  `playthrough_runner.tscn`.
- **Combat approach at the checkpoint.** Destroying the defences originally left the blast door locked. A
  "crank the dead lock" option now makes combat a complete approach on its own.
- **Rest.** A KOTOR-style rest (V, or at muster points) was added after the bot runs showed that attrition alone
  made later fights unwinnable.
- **Level scaling.** The final bay fight scales down for parties below level 4 (the martial route reaches the
  bay at level 3).
- **Equipment.** Upgrades sit on weapon and armor instances; there are 10 equipment slots (two weapon sets).
- **Developer presets.** They start from world-state snapshots captured during a real bot playthrough
  (`data/dev_stages.json`) instead of hand-written states, so jumps match real play.

- **Immersion pass (12–15).**
  - **Conversations:** facing during a conversation is applied to the actor's visual only, never to the
    `Actor`, because party following and stealth read `facing`.
  - **Companion hooks** prompt the player (a "wants to talk" badge, E beside them) instead of starting a
    conversation themselves.
  - **Prologue:** an in-engine flythrough with captions, not a scrolling crawl (too close to the source
    genre's signature).
  - **Combat:** no hit-stop or slow motion, since both would change combat timing.
  - **Footsteps** play for the party only.
  - **Babble:** generated per syllable at run time from four banks, not recorded lines.

## Balance notes (from bot runs and the seed sweep)

- **Causes of party wipes the bots exposed:** no healing between fights, unobtainable armor upgrades, a ×3
  glaive critical, a 2d6 checkpoint mine against a 9-HP Adept, companions standing on live plates, followers
  opening doors into other encounters, and noise carrying through bulkheads.
- **Fixes:** rest, armor in the armory, glaive 1d10 ×2, a 1d6 mine, hazard avoidance, door rules, muffled noise,
  lighter reclaimers, and a slimmer bay composition.
- **Current state:** 23/24 seeded bot runs escape (`tools/bot_sweep.sh 1 8`, after auto-attack). The one
  failure is the level-1 Adept at the checkpoint. The previous sweep also lost a martial bay fight: killing
  Senna and loading the archive add enemies there. That is intended consequence, but the margin is thin.
- A human can pause, reposition, use the terrain and retry, but this has **not been verified with human
  players**.

## Open items and known issues

- **No human playtest yet.** Pacing, difficulty and readability need real players.
- **Performance on real GPUs has not been measured.** The container only has software rendering. The
  simulation's CPU cost is measured: see `docs/TEST_RESULTS.md`.
- **Audio is unheard.** It was checked by analysis only. That includes the four voice banks: pitch and
  brightness were measured per bank, but nobody has listened to the babble.
- **Art and animation:** procedural primitive models with code-driven animation, no textures. Readable, but far
  from production quality.
- **No gamepad support**, no localization, no recorded voice (lines are babbled from synthesised syllables).
- **Follow camera** constants (swing rate, hold after a manual orbit, lift over walls) were tuned from screenshots
  only. They need tuning in hands-on play. With the leader's back against a wall it rises over the room, and
  tactical mode remains one setting away.
- **Presentation cost:** the combat presentation (stances, sparks, flourishes) adds roughly 10–15% to the
  simulation step means, a fraction of a millisecond in absolute terms; see `docs/TEST_RESULTS.md`.
- **Visual nits:**
  - The area sign above the commons muster point overlaps the quest tracker at some camera angles.
  - Haze and red alert are tuned for llvmpipe screenshots and may read differently on a real GPU.
  - The reactor ring can fill the view in engineering at high pitch.
- **Exit warnings.** Headless runs print "ObjectDB instances leaked at exit" from sounds or tweens still alive
  at quit. They are harmless, but noisy.
