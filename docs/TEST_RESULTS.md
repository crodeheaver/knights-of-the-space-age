# Test results

All results below were produced by commands in this repository, on the build container. They are runs of
**automated tests and bots, not human playtests.**

- **Environment:** Godot 4.4.1-stable (official), headless; Intel Xeon @ 2.80 GHz, 4 cores; no GPU (Mesa llvmpipe
  under Xvfb for anything rendered).
- **Commit:** `d9ccc4c` + `docs/.gdignore` (branch `claude/admiring-faraday-5f1rx1`).

## 1. Full suite — `./tools/run_tests.sh`

```
RESULT: 106 tests, 106 passed, 0 failed
exit code 0, no SCRIPT ERROR lines
```

| File | Tests | Covers |
|---|---|---|
| `test_build.gd` | 9 | point buy, modifiers, skills, feat/power prerequisites, recommended builds, derived stats, cosmetics |
| `test_combat_rules.gd` | 14 | forced-roll hits/misses, natural 1/20 scope, crit confirm, damage types and resistance, shields, 2H/off-hand/dual-wield, Power Strike, deflection, sneak attack, story difficulty, powers and costs, grenades |
| `test_status_queue.gd` | 8 | status refresh, group priority, expiry and pause, immunities, break-on-damage and DoT, flat-footed, queue order/cancel/reorder, cooldowns |
| `test_economy.gd` | 7 | no negative quantities, equip requirements, atomic swaps, crafting conservation, upgrades, vendor stock and no credit loop, consumables |
| `test_story_systems.gd` | 11 | pronoun formatting, dialogue conditions and once-only effects, checks resolve once, companion- and Resonance-assisted checks, one-time influence/alignment/rewards, level-ups, quest state machine, condition operators |
| `test_saves.gd` | 5 | full state round trip, RNG state, file save/load with backup, corrupt and missing files, newer schema refused |
| `test_data.gd` | 3 | every data reference and dialogue destination valid, content minimums, every skill used in the level |
| `test_scripts.gd` | 2 | every script compiles; main scene instantiates |
| `test_ui.gd` | 7 | creator flow and invalid-build blocking, all game-menu tabs and equip/use, level-up (recommended and manual), vendor/crafting/muster, save/load/delete with confirmation, settings and rebinding conflicts, ending outcome |
| `test_world.gd` | 12 | keyboard movement drives the walk animation and freezes with pause, pause freezes everything (incl. behind menus), simultaneous events (dead target, purged queue, kill and down in one blast, grenade after the thrower falls, scene transition mid-throw), stealth LOS, the four checkpoint approaches |
| `test_presets.gd` | 4 | every preset loads into the world; prestige presets eligible for exactly their variant; Iona's training; bay jump plays to the escape |
| `test_minigames.gd` | 16 | Shards rules, AI legality, wager escrow and settlement, Slipstream finish/best/par-once, turret win/loss/autopilot, practice changes nothing |
| `test_audio_assets.gd` | 5 | every sound id loads; length budgets; loops seamless through the mixer |
| `test_playthrough.gd` | 3 | the three bot playthroughs below |

## 2. Automated playthroughs (fixed seeds) — in the suite

The bot plays the real `World` through the same command API the input layer uses. It moves, opens doors, loots,
reads, talks and picks dialogue options by route preference. In fights it queues actions with the shared
tactical AI, heals and revives, and rests after fights. It spends level-ups with the Recommended choices and
equips better armour when it loots some. It runs a mid-level save → load → state comparison and checks that
reloading never grants a discovery twice.

| Route | Build | Result | Ends at | Survivors | Notable checks |
|---|---|---|---|---|---|
| Martial | Vanguard / veteran | **escaped** | level 4 | 5 | checkpoint by combat; took the reserve, sealed the ward, killed Senna, loaded the archive, purged WARDEN, fought through the bay |
| Technical | Operative / colonist | **escaped** | level 4 | 11 | failed Medicine checks (split reserve failed) and continued; terminal checkpoint; pumps, plates, hatch shortcut past the Sentinel; coolant purge; testimony copied; Tav-7 hosts WARDEN |
| Diplomat | Adept / salvager | **escaped** | level 4 | 11 | credential checkpoint, split reserve, rushed ward, bargained with Senna, parley, archive handover, commanded WARDEN, negotiated bay |

Logs with every choice and the full combat log are written to `user://bot_<route>.log` (on Linux:
`~/.local/share/godot/app_userdata/Ashes of the Concord/`).

## 3. Seed robustness sweep — `./tools/bot_sweep.sh 1 8`

The same three routes are replayed with dice offsets 1–8 (24 runs):

```
SWEEP: 22/24 route runs escaped
offset 7: diplomat — party wiped at the forward checkpoint (level 1 Adept + Iona vs turret and two pickets)
offset 8: martial  — party wiped in the bay (Marshal Quill's line, reinforced by the martial route's choices)
```

The failures are combat losses in the two hardest fights for those builds, not script or logic errors. A human
player can pause, take cover, retreat or reload; the bot does not. Balance has not been validated with human
players.

## 4. Simulation performance — `godot --headless --path . res://tools/godot/bench.tscn`

This measures CPU time of `World.sim_step` at 30 Hz (budget 33.3 ms) with no rendering. "Actors" counts
everyone loaded (party, NPCs, enemies).

| Stage | World build | Explore step mean / p95 | One encounter in combat, mean / p95 / max | Every encounter alerted at once (stress), mean / p95 / max |
|---|---|---|---|---|
| jump_checkpoint | 201 ms | 0.57 / 1.87 ms | 1.62 / 3.10 / 4.2 ms (23 actors) | 8.05 / 12.9 / 21.7 ms (33) |
| jump_engineering | 197 ms | 0.75 / 2.13 ms | 3.07 / 4.82 / 8.0 ms (24) | 7.25 / 13.0 / 33.1 ms (34) |
| jump_archive | 136 ms | 0.45 / 1.20 ms | 1.79 / 2.89 / 6.9 ms (20) | 4.57 / 8.4 / 30.7 ms (30) |
| jump_bay | 128 ms | 0.37 / 0.79 ms | 0.51 / 1.38 / 2.2 ms (19) | 3.59 / 5.8 / 10.6 ms (25) |

Benchmarking found and fixed one problem: a 240 ms exploration spike. Its causes were quadratic path smoothing
and preset companions spawning 137 m away. Look-ahead is now bounded, and companions spawn beside the player.

**Not measured:** rendered frame rate on real GPU hardware. Under Xvfb the renderer falls back to llvmpipe
software rasterization, which reports 3–5 FPS at 1920×1080. That reflects the software rasterizer, not the game.

## 5. Exported build

- `godot --headless --path . --export-release "Linux" builds/linux/AshesOfTheConcord.x86_64` → 69.7 MB binary
  plus a 4.2 MB `.pck`. The Windows export is produced the same way.
- The exported Linux binary was launched:
  - **headless** with `--quickstart=vanguard`: it validated all data (0 issues) and ran 90 frames;
  - **under Xvfb** with `--quickstart=operative --shot=…`: it rendered the commons
    (`docs/screenshots/export_run.jpg`).
- Exit prints "ObjectDB instances leaked" warnings (sounds and tweens alive at quit). They are harmless.

## 6. Visual checks

29 screenshots captured under Xvfb are in `docs/screenshots/`: the title, creator steps, all nine areas, the
menus, level-up, vendor, workbench, settings, specialization, developer menu, the three minigames, and the
exported build. They were reviewed by eye for layout, overlap and readability. Remaining nits are listed in
`docs/PROGRESS.md`.
