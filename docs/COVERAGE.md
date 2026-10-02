# Coverage matrix

**Status:** ✅ done and verified by an automated check · 🟡 done, verified only by inspection or screenshots ·
⚠️ partial or with a stated limitation.

Unless noted otherwise, every test listed is in `tests/` and runs in `./tools/run_tests.sh`.

## Character creation

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Name, pronouns (4 sets, used in all text) | ✅ | `ui/character_creator.gd`, `Game.fmt` | `test_ui::test_character_creator_flow`, `test_story_systems::test_text_formatting_pronouns` |
| Body/head/hair/skin/hair colour/accent presets, rotating 3D preview (drag or auto) | 🟡 | `character_creator.gd` (SubViewport + `ActorVisual`) | screenshots `docs/screenshots/cc_*.jpg` |
| Cosmetics never change stats | ✅ | `data/appearance.json` | `test_build::test_cosmetics_do_not_change_stats` |
| 3 archetypes (Vanguard, Operative, Adept) | ✅ | `data/classes.json` | `test_build::test_derived_stats` |
| 6 attributes, 30-point buy, 1/2/3 cost tiers, 8–18 | ✅ | `rules/build_validator.gd` | `test_build::test_point_buy_costs`, `test_ui` (cannot overspend) |
| 8 skills, class/cross-class costs, rank caps | ✅ | `build_validator.gd`, `data/skills.json` | `test_build::test_skill_rules` |
| Feats and powers with prerequisites and reasons | ✅ | `BuildValidator.feat_errors/power_errors` | `test_build::test_feat_prerequisites`, `test_power_prerequisites` |
| 3 backgrounds (skill bonus, gear, credits, dialogue options) | ✅ | `data/backgrounds.json`, dialogue `background` conditions | `test_data`, bot routes use all three |
| Recommended builds | ✅ | `data/builds.json` | `test_build::test_recommended_builds_validate` |
| Back/next without losing choices, summary, blocks invalid builds | ✅ | `character_creator.gd` | `test_ui::test_creator_blocks_invalid_build` |

## Progression

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| XP with one-time keys; levels 1→4 across the slice | ✅ | `GameState.grant_xp`, `data/progression.json` | bots end at level 4; `test_story_systems::test_one_time_rewards_ledger` |
| Manual and Recommended level-up (same validation) | ✅ | `rules/progression.gd`, `ui/levelup_ui.gd` | `test_story_systems::test_levelup_manual_and_recommended`, `test_ui::test_levelup_ui_recommended_and_manual` |
| Companion level-ups | ✅ | `Progression` | `test_story_systems::test_companion_levelup` |

## Combat

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Real time with pause, 3 s per-actor rounds | ✅ | `world/combat_manager.gd` | bot playthroughs |
| 4-slot queue: add, cancel, reorder, clear | ✅ | `rules/action_queue.gd`, HUD queue strip | `test_status_queue::test_queue_order_cancel_reorder` |
| Pause freezes everything; menus too | ✅ | `World.sim_running` gate | `test_world::test_pause_freezes_everything` |
| Auto-pause (start, member down, queue empty, target defeated) | ✅ | Settings + `combat_manager.gd`/`world.gd` | 🟡 option toggles exercised in UI test |
| d20 attack, natural 1/20 on attacks only, crit threat and confirm | ✅ | `rules/combat_rules.gd` | `test_combat_rules` (forced rolls) |
| Saving throws, skill checks (no auto 1/20) | ✅ | `CombatRules.saving_throw/skill_check` | `test_combat_rules`, `test_story_systems` |
| Damage types, resistances, ion vs machines, shields | ✅ | `apply_damage` | `test_combat_rules::test_damage_types_and_resistance`, `test_shield_absorption` |
| Weapons: unarmed, 8 melee (1H, 2H, dual), 3 pistols, 3 rifles, 5 grenades, 3 mines, shields, stims, medpacs | ✅ | `data/items.json` | `test_combat_rules::test_two_handed_and_offhand_strength`, `test_dual_wield_penalties`, `test_grenade_explosion_once` |
| Lumen Edge and Bolt Deflection | ✅ | `combat_rules.gd` | `test_combat_rules::test_bolt_deflection` |
| Statuses: refresh, group priority, immunities, break-on-damage, DoT | ✅ | `rules/status_rules.gd` | `test_status_queue` (6 tests) |
| 3 combat forms | ✅ | `data/forms.json`, HUD selector | 🟡 HUD screenshot |
| Feats and powers in combat (Power Strike, Flurry, Rapid Shot, Hold, Arc Lance…) | ✅ | `rules/action_resolver.gd` | `test_combat_rules::test_power_resolution_and_costs`, `test_power_strike_action_modifiers` |
| Sneak attack (flat-footed, unaware) | ✅ | `combat_rules.gd` | `test_combat_rules::test_sneak_attack_flat_footed` |
| 4 enemy roles (melee, ranged, support, security machine) and companion behaviours | ✅ | `world/ai_brain.gd` | bot playthroughs (combat log in `bot_*.log`) |
| Downed state, revive, game over | ✅ | `World.on_downed`, `GameOverUI` | `test_world::test_kill_and_down_in_the_same_explosion`; bot sweep wipes reach game over |
| Combat log with roll breakdowns | ✅ | `World._apply_events`, HUD log | each attack logged once (fixed and covered by bot logs) |
| Simultaneous events (dead targets, canceled queue, kill and down in one blast, grenade after thrower falls, scene transition mid-throw) | ✅ | `world.gd` | `test_world` (5 tests) |

## Party, influence and alignment

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Iona Rell and Tav-7: recruitment, control switch, follow/hold/solo, behaviours | ✅ | `world.gd`, `ui/game_menu.gd` (Party) | bots; `test_ui::test_game_menu_all_tabs` |
| Influence 0–100, logged with reasons, one-time keys | ✅ | `GameState.add_influence` | `test_story_systems::test_influence_and_alignment_are_one_time` |
| Mercy/Dominion −100…+100, changes power costs | ✅ | `GameState.add_alignment`, `CharacterSheet.power_cost` | `test_combat_rules::test_power_resolution_and_costs` |
| Companion conversations and interjections; influence gates content (training, ending lines) | ✅ | `tools/dialogues/companions.py`, `act3.py` | `test_presets::test_iona_training_preset` |

## Exploration and skills

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| WASD and click-move (both animate the walk cycle and stop on pause); orbit and zoom camera with collision | ✅ | `World._direct_input` → `Actor.input_dir` → `Actor.sim_step`; `world/camera_rig.gd` | `test_world::test_keyboard_movement_drives_walk_animation`; camera 🟡 screenshots |
| Doors, containers, corpses, readables, explored map | ✅ | `world/world_object.gd`, `ui/minimap.gd` | bots loot and read along every route |
| All 8 skills have world uses | ✅ | `data/ship_layout.json` options | `test_data::test_every_skill_used_in_level` |
| Stealth: LOS, cone, distance, suspicion, shadows, detection | ✅ | `rules/stealth_rules.gd`, `World._stealth_step` | `test_world::test_stealth_detection_line_of_sight`; technical bot sneaks to the north pump |
| Hidden mines and hazards, Awareness, disarm and recover | ✅ | `world.gd` | 🟡 bots trigger, notice and avoid them |
| Major obstacle (forward checkpoint): combat, technical, stealth, conversation | ✅ | `d_blast`, terminal, crawlway, credential dialogue | `test_world::test_checkpoint_*_approach` (4 tests) |
| Skill shortcuts elsewhere (maintenance hatch, coolant purge, bay turrets) | ✅ | layout options | technical bot route |

## Dialogue, quests and consequences

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Data-driven dialogue: conditions, effects, checks once, failure continues, history, framing | ✅ | `rules/dialogue_engine.gd`, `data/dialogue/` (28 files, about 430 nodes) | `test_story_systems` (5 tests), `test_data` (all destinations) |
| Main quest and 2 optional quests (+ Cold Restart objective chain) | ✅ | `data/quests.json`, `rules/quest_system.gd` | `test_story_systems::test_quest_state_machine`; bots complete them |
| 3+ decisions with visible consequences | ✅ | see `docs/BRANCH_MAP.md` | bots take different branches; the ending summary differs (5 vs 11 survivors) |

## Economy

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Inventory and equipment: 10 slots, 76 item definitions | ✅ | `rules/inventory.gd`, `rules/equipment_rules.gd` | `test_economy` (7 tests) |
| Vendor with finite stock; sell < buy | ✅ | `rules/vendor.gd`, `ui/vendor_ui.gd` | `test_economy::test_vendor_finite_stock_and_no_credit_loop` |
| Crafting (14 recipes, 2 stations), dismantle, upgrades | ✅ | `rules/crafting.gd`, `ui/crafting_ui.gd` | `test_economy::test_crafting_conservation_and_gates`, `test_upgrade_changes_combat_stats` |
| Atomic transactions | ✅ | `Inventory.Tx` | `test_economy::test_inventory_never_negative`, `test_equip_atomic_swap_preserves_items` |

## Later-game systems

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Prestige: 3 families × Mercy/Dominion variants, eligibility reasons, permanent adoption, rule features | ✅ | `rules/prestige.gd`, `data/prestige.json`, `ui/prestige_ui.gd` | `test_presets::test_prestige_presets_are_eligible_for_their_variant_only` |
| Iona's Resonance training | ✅ | `iona_talk` dialogue | `test_presets::test_iona_training_preset` |
| Developer presets and menu | ✅ | `core/dev_tools.gd`, `data/dev_presets.json`, `data/dev_stages.json`, `ui/dev_menu.gd` | `test_presets::test_every_preset_applies_and_loads`, `test_jump_bay_plays_to_escape` |

## Level

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| 9 main areas + 8 side rooms, in the planned progression | ✅ | `data/ship_layout.json` | bots traverse all 9; `docs/screenshots/area_*.jpg` |
| Escape, companion exchange, revelation, summary, end-of-intro save | ✅ | `launch`, `ending_exchange` dialogues, cinematic, `ui/ending_ui.gd`, `Main.show_ending` | `test_ui::test_ending_outcome`; bots reach `escaped` |

## Minigames

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Shards card game with wagers (escrow, single settlement) and AI | ✅ | `minigames/shards_rules.gd` | `test_minigames` |
| Slipstream hover racing (assisted driving, par prize once) | ✅ | `minigames/slipstream_sim.gd` | `test_minigames` |
| Turret: real-time, assisted targeting, autopilot roll; dialogue alternatives (Iona, Tav-7, Brann) | ✅ | `minigames/turret_sim.gd`, `launch` dialogue | `test_minigames` |
| Practice mode from the title screen, no state changes | ✅ | `Minigames.open_practice` | `test_minigames` (state snapshot) |

## UI and accessibility

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| HUD, character, inventory, abilities, party, journal (quests, choices, codex, conversations, tutorials), map, controls | ✅ | `ui/hud.gd`, `ui/game_menu.gd` | `test_ui::test_game_menu_all_tabs`, screenshots |
| Key rebinding with conflict handling, reset | ✅ | `core/settings.gd`, `ui/settings_ui.gd` | `test_ui::test_saveload_and_settings_ui` |
| Mouse sensitivity, invert, edge pan | 🟡 | `camera_rig.gd` | inspection |
| UI and text scale | 🟡 | `Settings` → `content_scale_factor` | inspection |
| Captions for ambient speech | ⚠️ | HUD | There is no voice acting, so every line is already text. The setting enlarges ambient speech and keeps it on screen longer. |
| Reduced shake and flash; status symbols plus text, not colour alone | 🟡 | `camera_rig.gd`, `fx.gd`, `UIKit.status_chip` | inspection |
| Story / Standard difficulty | ✅ | `CombatRules` story modifiers | `test_combat_rules::test_story_difficulty` |

## Persistence

| Mechanic | Status | Implementation | Verification |
|---|---|---|---|
| Versioned saves, safe writes, backup recovery, corrupt and missing files reported | ✅ | `core/saves.gd` | `test_saves` (5 tests) |
| Quicksave, 3 rotating autosaves, 8 manual slots, end-of-intro | ✅ | `Saves`, `ui/saveload_ui.gd` | `test_ui::test_saveload_and_settings_ui`; bots' mid-level reload check |
| RNG and one-time ledger persist (no reload re-rolls or double rewards) | ✅ | `GameState` | `test_saves::test_rng_state_persists`; bot "no repeated discovery XP after reload" |

## Delivery

| Item | Status | Notes |
|---|---|---|
| Automated tests | ✅ | 106 tests; see `docs/TEST_RESULTS.md` |
| Playtest-style verification | ⚠️ | Three automated bot playthroughs and a seed sweep. **No human playtest** has been run. |
| Runnable build | ✅ | Linux and Windows exports; the Linux export was launched headless and under Xvfb (see TEST_RESULTS) |
| Screenshots | ✅ | `docs/screenshots/` (29 images) |
| Performance | ⚠️ | Simulation CPU cost measured (`tools/godot/bench.tscn`). **GPU frame rate not measured on real hardware**: the container only has the llvmpipe software rasterizer (3–5 FPS, not representative). |
| Art and animation | ⚠️ | Original procedural primitive models with code-driven animation. No skeletal or motion-captured animation and no textures. |
| Audio | ⚠️ | Original synthesized SFX and music (`tools/gen_audio.py`); checked by level, seam and spectrum analysis, **not by listening**. No voice acting. |
