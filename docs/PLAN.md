# Ashes of the Concord — Implementation Plan

This is the plan written before implementation. Live status is tracked in `docs/PROGRESS.md`; the
final per-mechanic status lives in `docs/COVERAGE.md`.

## 1. Platform decisions

| Decision | Choice | Reason |
|---|---|---|
| Engine | **Godot 4.4.1-stable** (pinned), typed GDScript | Brief default; empty repo, so nothing to preserve. |
| Renderer | `gl_compatibility` (OpenGL 3.3 / GLES3) | Runs on the widest range of desktop GPUs, including the Mesa llvmpipe software rasterizer in the build container. The same project can also export to the web. |
| Content authoring | JSON data in `res://data` plus procedural scene construction in code | Without an editor GUI, generating geometry from data is easier to verify than hand-written `.tscn` files. Every room, prop, door and NPC comes from `data/ship_layout.json`. |
| Navigation and line of sight | Grid-based (`AStarGrid2D` on 1 m cells), with doors and props as dynamic solids | Deterministic, testable headless and easy to keep in sync with door state. Physics is used only for camera collision. |
| Audio | Synthesized at runtime (`AudioStreamWAV` from generated PCM) | Fully original, with no binary assets to license. |
| Art | Stylized primitives (merged `SurfaceTool` meshes, emissive trims, coloured rim lights) | Original and readable; distinct silhouettes come from part shapes. |

## 2. Architecture overview (see `docs/ARCHITECTURE.md` for details)

```
data/*.json  ──►  DB (autoload: loads + validates)  ──►  rules/*  (pure, RefCounted, seeded Dice)
                                                           ▲
Game (autoload) owns GameState (authoritative, serializable) ─┘
Events (autoload) central event bus  ◄── quests, tutorials, UI, audio subscribe
World (Node3D) = presentation + simulation driver: grid, actors, interactables, CombatManager
UI (CanvasLayer) = HUD + panels; reads state, issues commands via World/Game APIs
Saves (autoload) = versioned JSON save files with temp-file + rename safe writes
```

The rules layer never touches nodes. The world asks the rules layer to resolve an action exactly once,
applies the returned result to the authoritative sheets, and then hands the result to visuals and
logs. Animations only display results that have already been resolved.

## 3. Increments

1. Runnable 3D room: project, autoloads, layout builder, controllable actor, camera orbit/zoom/collision, doors, containers, readables.
2. Character creation (archetype → background → attributes → skills → feats → powers → appearance → summary), with saved character state.
3. Combat: sim clock, pause, per-actor 3 s rounds, 4-slot queues, rules resolver, status effects, AI roles, first encounter, HUD, combat log.
4. Dialogue engine (structured conditions/effects), quests, journal, influence, alignment, and the companion recruitment conversations.
5. Inventory/equipment, vendor, crafting (workbench + med station), upgrades, world skill uses (terminals, locks, mines, hazards, stealth), level-up.
6. Full escape route: nine areas, all encounters, three major decisions, two optional quests, final encounter variants, ending.
7. Prestige specializations, Iona's Resonance training, developer presets and menu, and the three minigames.
8. Presentation (audio, animation, lighting), accessibility, balancing, the automated playthrough bot, screenshots, export, docs.

## 4. System coverage matrix (planned → see COVERAGE.md for final status)

| Area | Key mechanics | Planned location |
|---|---|---|
| Character creation | point-buy 30 (1/2/3 cost tiers), 3 archetypes, 3 backgrounds, 8 skills, feats/powers with prereqs, appearance presets, recommended builds, summary | `scripts/rules/build_validator.gd`, `scripts/ui/character_creator.gd`, `data/classes.json` |
| Progression | XP ledger, L1→~4 in intro, manual + recommended level-up, central tables | `scripts/rules/progression.gd`, `data/progression.json` |
| Combat | RTwP, 3 s rounds, queue ≤4 (add/cancel/reorder), pause freezes sim, auto-pause options, d20 rules, crit confirm, saves, resistances, weapons (unarmed/1H/2H/dual/pistol/rifle/grenade/mine/shield/stim/medpac), forms, statuses | `scripts/rules/combat_rules.gd`, `status_rules.gd`, `scripts/world/combat_manager.gd` |
| AI | melee aggressor, ranged, support/controller, security machine; companion behaviours | `scripts/world/ai_brain.gd` |
| Party | 2 companions, control switching, follow/hold/solo, behaviours, muster-point roster | `scripts/world/party_controller.gd` |
| Influence/alignment | per-companion 0–100 logged changes with one-time keys; Mercy(+)/Dominion(−) axis −100…+100 that changes power costs | `scripts/core/game_state.gd`, `scripts/rules/effects.gd` |
| Exploration | WASD + click-move, interaction targeting, doors, containers, corpses, logs, explored map | `scripts/world/*`, `scripts/ui/map_panel.gd` |
| Skills in world | all 8 skills with uses on the ship | `data/ship_layout.json` interaction options |
| Stealth | awareness vs stealth, distance, LOS, cone, suspicion meter | `scripts/rules/stealth_rules.gd` |
| Dialogue | data-driven branching, conditions/effects, checks resolved once, companion interjections, history, camera framing | `scripts/rules/dialogue_engine.gd`, `data/dialogue/*.json` |
| Quests | explicit states, event-driven transitions, main + 2 optional | `scripts/rules/quest_system.gd`, `data/quests.json` |
| Economy | shared inventory, 8 slots, ≥24 items, vendor with finite stock, ≥8 recipes, upgrades, atomic transactions | `scripts/rules/inventory.gd`, `crafting.gd`, `vendor.gd` |
| Later-game | prestige 3 families × 2 variants, Iona training, dev presets | `scripts/rules/prestige.gd`, `data/prestige.json`, `data/dev_presets.json` |
| Minigames | Shards (cards), Slipstream (racing), turret | `scripts/minigames/*` |
| Persistence | versioned saves, quicksave/load, autosave checkpoints, safe writes, corrupt handling | `scripts/core/saves.gd` |
| Accessibility | rebinding, sensitivity, UI scale, subtitles, volumes, reduced shake/flash, symbol+text statuses, difficulty | `scripts/core/settings.gd`, `scripts/ui/settings_panel.gd` |

## 5. Level and quest graph

```
 [1 Transfer Cabin] ─D1─ [2 Crew Commons] ─D2─ [3 Transit Corridor] ─D3─ [4 Security Checkpoint] ═BLAST═ [5 Medical Deck] ─D5─ [6 Engineering Loop] ─D6─ [7 Archive Hold] ─D7─ [8 Command / Launch Control] ─D8─ [9 Evacuation Bay]
        |                     |  (Observation Lounge)                     |  (Armory locker)            ▲   | (Sealed Ward)          |  ring around core      |  (Cold Storage)
        |                     |  cards, sim, vendor                       |                             |   | (Med Storage)           |  maintenance hatch ────┘ (skill shortcut)
        |                     |                                           └── crawlway (side passage) ──┘───┘  loop: checkpoint → crawl → storage → medical → blast door
```

Main quest **Escape the Cinder Wake** (`q_main`):
`wake → muster → corridor (Iona) → checkpoint → medical (Tav-7) → engineering → archive → command → bay → escaped`

Optional quest A **The Sealed Ward** (`q_ward`), medical deck: decide how the treatment reserve is used and whether the sealed compartment is opened. Feeds survivor count, seats at launch control and Iona's confrontation with the commander.

Optional quest B **Lantern in the Dark** (`q_lantern`), archive hold: the wounded reclaimer scout Senna Thorne (treat / interrogate / bargain / kill / release) and the Vesper testimony. Changes the archive-hold encounter, the command chamber arguments and the composition of the final encounter, and opens a negotiated finale.

Optional objective **Cold Restart** (engineering pumps): reduces hazards, enables the coolant purge in the archive hold, and powers the bay turrets.

Major decisions:
1. Medical reserve and sealed ward (survivors, resources, influence, later dialogue).
2. Senna Thorne's fate (final encounter composition, parley availability).
3. Evacuation priorities and the archives at launch control (passengers vs. archive vs. testimony copy vs. handover), plus the WARDEN's fate.

## 6. Testing strategy

* **Unit/rules tests** (`tests/test_*.gd`, run by `tests/test_runner.tscn` headless): attribute budgets, prerequisites, attack/save/damage math with a seeded RNG, crit confirmation, natural 1/20 scope, pause freezing, queue ordering/cancellation, status stacking/expiry, inventory/equipment validity, crafting/trading conservation, one-time rewards, dialogue conditions/effects, influence/alignment, save/load round trips, simultaneous-event regression.
* **Data validation**: every ID, prerequisite, reference and dialogue destination is checked at startup and in tests.
* **Integration bot** (`tests/playthrough_runner.tscn`): drives the real World through the same command API that input uses (move, interact, choose dialogue options, queue actions) for martial, technical and dialogue builds, from character creation to the ending, including a failed check, a low-resource fight and a mid-level save/reload comparison.
* **Visual checks**: runs under Xvfb capture screenshots of each area and UI screen, and record performance samples.
* The results of each run go in `docs/TEST_RESULTS.md`. An automated bot run is reported as automated, never as a human playtest.
