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
- **Audio is unheard.** It was checked by analysis only.
- **Art and animation:** procedural primitive models with code-driven animation, no textures. Readable, but far
  from production quality.
- **No gamepad support**, no localization, no voice.
- **Visual nits:**
  - The area sign above the commons muster point overlaps the quest tracker at some camera angles.
  - The reactor ring can fill the view in engineering at high pitch.
- **Exit warnings.** Headless runs print "ObjectDB instances leaked at exit" from sounds or tweens still alive
  at quit. They are harmless, but noisy.
