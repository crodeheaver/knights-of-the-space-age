# Test results

All results below were produced by commands in this repository, on the build container. They are runs of
**automated tests and bots, not human playtests.**

- **Environment:** Godot 4.4.1-stable (official), headless; Intel Xeon @ 2.80 GHz, 4 cores; no GPU (Mesa llvmpipe
  under Xvfb for anything rendered).
- **Commit:** `00bcfee` (branch `claude/wonderful-wozniak-62qtg1`, the presentation pass) for sections 1–4 and 6.
  Section 5 is from `d9ccc4c` (branch `claude/admiring-faraday-5f1rx1`) and was not re-run for this pass.

## 1. Full suite — `./tools/run_tests.sh`

```
RESULT: 144 tests, 144 passed, 0 failed
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
| `test_data.gd` | 4 | every data reference and dialogue destination valid, content minimums, every skill used in the level, a scan of all player-facing text for borrowed franchise terms |
| `test_scripts.gd` | 2 | every script compiles; main scene instantiates |
| `test_ui.gd` | 7 | creator flow and invalid-build blocking, all game-menu tabs and equip/use, level-up (recommended and manual), vendor/crafting/muster, save/load/delete with confirmation, settings and rebinding conflicts, ending outcome |
| `test_world.gd` | 16 | auto-attack at combat start (queued, replaced by player choices and moves, off/sneaking, moves on after a kill), keyboard movement drives the walk animation and freezes with pause, pause freezes everything (incl. behind menus), simultaneous events (dead target, purged queue, kill and down in one blast, grenade after the thrower falls, scene transition mid-throw), stealth LOS, the four checkpoint approaches |
| `test_presets.gd` | 4 | every preset loads into the world; prestige presets eligible for exactly their variant; Iona's training; bay jump plays to the escape |
| `test_minigames.gd` | 16 | Shards rules, AI legality, wager escrow and settlement, Slipstream finish/best/par-once, turret win/loss/autopilot, practice changes nothing |
| `test_audio_assets.gd` | 7 | every sound id loads; length budgets; loops seamless through the mixer; the four voice banks (count, length, level, distinct timbre); music crossfades and resumes |
| `test_presentation.gd` | 22 | conversations: text reveal and escaping, reactions instead of plain effect lines, voice timing, staging and camera shots that avoid walls, cinematics from data, bad staging rejected; dialogue staging, misses, pushes and downed falls leave the simulation unchanged; follow camera swings behind, tactical camera holds still; ceilings, sliding doors, alert lighting, props freezing on pause; stance and blade, bodies, alignment look, health bars, damage-number setting; HUD feedback toasts, held during conversations |
| `test_ship_life.gd` | 9 | barks with cooldowns and once-only lines, quiet while paused, in conversations, downed or out of earshot; announcements and the `bark` effect; a companion hook opens its topic; banter plays once; NPC idle styles move no one; the validator checks the data; a fight steps identically with and without ambient voices |
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

The presentation pass is checked against these logs: after each of its four commits, the three default-seed logs
were byte-identical to the logs recorded before the pass started. Voices, camera, lighting, barks and combat
effects did not change a single choice, roll or combat-log line.

## 3. Seed robustness sweep — `./tools/bot_sweep.sh 1 8`

The same three routes are replayed with dice offsets 1–8 (24 runs):

```
SWEEP: 23/24 route runs escaped
offset 7: diplomat — party wiped at the forward checkpoint (level 1 Adept + Iona vs turret and two pickets)
```

This run was made on `00bcfee`, after the presentation pass. Every one of the 24 runs ended the same way as in
the sweep recorded before the pass started (on `7f81223`). The pass changed no outcome.

The first 23/24 sweep was made after auto-attack was added (commit `2f3da3c`). In combat the bot picks its own actions, and
they replace the automatic attack, as a player's would. The earlier sweep, before auto-attack, was 22/24: offset 7
diplomat failed at the same checkpoint and offset 8 martial wiped in the bay. Dice consumption changed with
auto-attack, so individual offsets are not comparable across the two sweeps.

The remaining failure is a combat loss in the hardest fight for that build, not a script or logic error. A human
player can pause, take cover, retreat or reload; the bot does not. Balance has not been validated with human
players.

## 4. Simulation performance — `godot --headless --path . res://tools/godot/bench.tscn`

This measures CPU time of `World.sim_step` at 30 Hz (budget 33.3 ms) with no rendering. "Actors" counts
everyone loaded (party, NPCs, enemies). The step includes the presentation work that runs on the simulation
clock: character animation (now including combat stances, flourishes and the Lumen Edge) and effects (now
including sparks, muzzle flashes and damage-number pops).

Before the presentation pass (`7f81223`) and after it (`00bcfee`, two runs), on the same machine. Each cell is
mean / p95 / max in ms.

| Stage (actors) | | Explore step | One encounter in combat | Every encounter alerted at once (stress) |
|---|---|---|---|---|
| jump_checkpoint (33) | before | 0.57 / 1.89 / 2.3 | 0.96 / 2.74 / 5.3 | 5.75 / 9.40 / 24.8 |
| | after | 0.70 / 2.06 / 2.6 · 0.69 / 1.97 / 2.5 | 1.38 / 3.93 / 7.3 · 1.24 / 3.49 / 8.0 | 6.00 / 8.63 / 20.3 · 5.79 / 8.26 / 20.0 |
| jump_engineering (34) | before | 0.67 / 2.06 / 3.4 | 1.99 / 4.67 / 16.0 | 3.85 / 5.93 / 23.9 |
| | after | 0.75 / 2.15 / 3.5 · 0.70 / 2.09 / 2.4 | 1.98 / 4.60 / 14.2 · 2.01 / 4.51 / 22.3 | 4.61 / 7.08 / 14.3 · 4.53 / 8.35 / 14.6 |
| jump_archive (29) | before | 0.43 / 1.17 / 1.3 | 0.88 / 1.83 / 6.8 | 2.92 / 5.69 / 11.5 |
| | after | 0.57 / 1.36 / 1.6 · 0.54 / 1.27 / 1.5 | 1.14 / 2.26 / 7.9 · 1.05 / 2.06 / 7.9 | 3.41 / 6.24 / 12.2 · 3.09 / 5.88 / 11.7 |
| jump_bay (25) | before | 0.37 / 0.80 / 0.9 | 0.40 / 0.81 / 1.2 | 1.68 / 4.23 / 12.4 |
| | after | 0.54 / 1.08 / 2.2 · 0.44 / 0.84 / 1.1 | 0.49 / 0.91 / 1.1 · 0.48 / 0.89 / 1.1 | 2.61 / 6.42 / 24.5 · 2.23 / 6.09 / 25.3 |

Summed over all twelve cells, the mean rose from 20.5 ms to 22.8–24.2 ms (+11–18%) and the p95 from 41.2 ms to
45.7–46.7 ms (+11–13%). Every mean stays under 7 ms and every p95 under 9 ms. The largest single step in any run
was 25.3 ms, against 33.1 ms in the earlier measurement on `d9ccc4c`. Maxima are single steps and vary from run
to run. During the pass, profiling removed three costs the new code had first added: a `max_hp()` recomputation every step, creating a spark
node per hit (now a pool of 48), and transform writes for visuals that had not moved.

The earlier measurement (`d9ccc4c`) found and fixed one problem: a 240 ms exploration spike. Its causes were quadratic path smoothing
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

40 screenshots captured under Xvfb are in `docs/screenshots/`: the title, creator steps, all nine areas, the
menus, level-up, vendor, workbench, settings, specialization, developer menu, the three minigames, and the
exported build. They were reviewed by eye for layout, overlap and readability. Remaining nits are listed in
`docs/PROGRESS.md`.

The presentation pass added 11:

| File | Shows |
|---|---|
| `cine_prologue.jpg` | the opening cinematic: an in-engine shot of the commons with a caption |
| `dlg_ots.jpg`, `dlg_close.jpg` | Commander Varr's conversation: over-the-shoulder and close-up shots, with tone strips on the choices |
| `dlg_warden.jpg` | a WARDEN terminal conversation, framed on the terminal, with the drawn WARDEN portrait |
| `dlg_parley_archive.jpg` | the Reclaimer parley in the archive, with check odds on the choices |
| `life_banter.jpg` | Iona and Tav-7 bantering in Medical Storage: speech bubble and caption |
| `life_warden.jpg` | a WARDEN shipwide announcement with its red caption |
| `cam_follow_corridor.jpg` | the default follow camera in the corridor under red alert |
| `cam_tactical.jpg` | the tactical camera, one setting away |
| `combat_follow.jpg` | combat start with the follow camera: health bars, a combat bark, the target panel |
| `align_dominion.jpg` | a Dominion-leaning player: paler skin and ember eyes |

Screenshots under llvmpipe show layout and framing. They do not show how the game feels in motion, and the voices
and sounds were checked by analysis (length, level, spectrum), not by listening.
