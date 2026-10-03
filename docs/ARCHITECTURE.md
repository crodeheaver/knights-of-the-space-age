# Architecture and rules reference

## 1. Layers

```
data/*.json ──► DB (autoload) ──► DataValidator (startup + tests)
                  │
                  ▼
scripts/rules/*   pure RefCounted classes: no nodes, no globals except DB data and a passed-in Dice
                  ▲   (CombatRules, StatusRules, ActionResolver, ActionQueue, Inventory/Tx, EquipmentRules,
                  │    Crafting, Vendor, Progression, BuildValidator, Prestige, Conditions, Effects,
                  │    QuestSystem, DialogueEngine, StealthRules, Dice)
Game (autoload) ──► GameState: the single authoritative, serializable state (to_dict/from_dict)
                  │
World (Node3D)  ──► the simulation driver and presentation: ShipGrid, LevelBuilder, Actors, WorldObjects,
                  │  CombatManager, AIBrain, CameraRig, FX. It asks the rules to resolve each action
                  │  exactly once, applies the result to GameState, then hands the result to visuals and logs.
                  │  Presentation-only children: Atmosphere, OverheadBars, DialogueStage (during a
                  │  conversation) and, in the real game only, ShipLife (see section 14).
UI (CanvasLayer) ─► HUD and panels: they read state and issue commands through World/Game APIs only.
Events (autoload): central bus. post(name, data) for game events, toast() for notifications, log_combat().
Saves (autoload): versioned JSON files with safe writes. Settings (autoload): options, bindings.
GameAudio (autoload): Music, SFX, Ambience, UI and Voice buses (plus a band-passed VoiceRadio bus), crossfaded
                  music and ambience, positional prop loops, footsteps, and babbled voice lines.
```

Rules never touch nodes, so they are unit-tested directly with forced dice (`Dice.force([..])`). Animations,
sounds and floating numbers only display results that have already been resolved; nothing is ever rolled twice.

## 2. Simulation, pause and modality

- The world advances in fixed steps (`World.FIXED_DT`, 1/60 s in play; tests, bots and the bench step at 1/30 s)
  through `World.sim_step(dt)`, and only while `sim_running()`: not paused,
  no modal (`menu`, `dialogue`, `minigame`, `cinematic`), and not game over. Every timer is driven only by
  `sim_step`: statuses, cooldowns, round clocks, recovery, projectiles, bash jobs, hazards, stealth, regeneration and
  pending corpses. Pausing therefore freezes all of them. (`tests/test_world.gd::test_pause_freezes_everything`
  snapshots every actor, status, cooldown and projectile across 45 paused frames.)
- Keyboard movement is sampled each physics frame into the controlled actor's `input_dir` and applied inside
  `Actor.sim_step`, exactly like click-to-move paths, so it shares the pause gate and drives the walk animation
  from the distance actually covered.
- Tests and bots set `manual_step = true` and call `sim_step` themselves.
- `Game.state.sim_time` is the deterministic clock. `play_time` is wall-clock while unpaused.
- Saving is refused while a conversation, cinematic or minigame is open, during unpaused combat, with a grenade in
  flight, or while a door is being forced (`World.save_block_reason`).

## 3. Combat (real time with pause)

- **Rounds:** each actor has its own 3 s round clock, so rounds are staggered and there is no global turn. An
  action takes the actor's round (half a round for a weapon-set swap), then a recovery period. Initiative staggers
  first actions by d20 + DEX.
- **Queue:** each party member has a 4-slot queue (`ActionQueue`) supporting add, cancel, reorder and clear. Queued
  actions are validated when queued and again when executed. Actions whose target has died are purged
  (`queue.purge_target`). An actor with an empty queue makes a basic attack on its target, or acts by AI
  behaviour if it is a companion not under your control.
- **Auto-attack** (Settings → Gameplay, on by default): when combat starts and the controlled character has
  nothing queued, a basic attack on the selected enemy (or the nearest one in sight) is queued and shown as
  "(auto)". Queuing any action, moving (click or keys) or entering stealth replaces it, even while the
  automatic attack is still closing on its target; re-selecting a target re-aims it. When the target falls and the queue is empty, the character moves on to the nearest enemy, unless
  "pause when the queue empties" is on, in which case the game pauses instead. Player movement is never
  overridden by an automatic attack.
- **Auto-pause** options: combat start, member down, controlled character's queue empty, target defeated.
- **Movement into range:** actions with a range move the actor until it is in range and has line of sight, then
  resolve. Enemies treat closed doors as walls. During combat, only the character you control opens doors.

### Attack roll

`d20 + attack bonus ≥ target Defense` hits. A natural 20 always hits and a natural 1 always misses; this applies
to **attack rolls only**, not saves or skill checks.

Attack bonus parts, in order (each is shown in the combat log breakdown):

1. BAB (class table)
2. STR (melee); DEX (ranged); for finesse weapons, the higher of STR and DEX
3. Weapon attack bonus (including upgrades)
4. −4 if not proficient
5. Weapon Focus feats and gear (melee or ranged)
6. Dueling +1 (one-handed weapon, empty off-hand)
7. Dual-wield penalties (main/off-hand; reduced by Two-Weapon Fighting feats)
8. Status effects (e.g. Suppressed −2, Wavering −2)
9. Combat form
10. Template training bonus (enemies)
11. Action modifier (Power Strike −3, Flurry −4, Rapid Shot…)
12. Story difficulty −2 for enemies

**Defense** = 10 + DEX (capped by armor max-DEX; 0 if flat-footed) + armor + gear + natural (enemies)
+ Dueling 2 + effects + form.

**Critical hits:** a natural roll in the weapon's threat range threatens. Then a confirmation roll
(d20 + the same bonus) must hit Defense (a natural 20 confirms, a natural 1 fails). A confirmed critical
multiplies the weapon dice and static damage by the weapon multiplier (×2 normally).

**Bolt deflection:** a Lumen Edge wielder with Bolt Deflection rolls d20 + 5 (rank 2: + 9) + DEX against
every incoming ranged energy attack total that hit. This only works if they can act and are not flat-footed.

### Damage

1. Weapon dice (× crit multiplier), plus static parts: STR for melee (×1.5 two-handed, ×0.5 off-hand, never
   multiplied up when negative), weapon damage, action bonus, effects and form, all × crit multiplier.
   Minimum 1.
2. Extra components (for example the Shock Spanner's ion 1d4) and sneak attack: Operative dice against
   flat-footed, unaware or feared targets, plus the Night Broker prestige bonus.
3. For each component, in order:
   - **kind multiplier:** ion ×2 vs machines and ×0.25 vs organics.
   - **immunity:** toxin, or shock-flagged energy.
   - **Story scale:** ×0.6 for damage taken by the party.
   - **resistance (DR)** by damage type.
   - **shield absorption:** Deflector and Aegis statuses, matching damage types.
4. HP ≤ 0: party members are **downed**. They revive after combat at 25% HP, or with a medpac or repair kit.
   If the whole party is down, the game is over. Enemies die, leaving corpses or wrecks to loot.

**Saving throws:** d20 + save (class base + attribute + feats, gear and effects) ≥ DC. There is no automatic
success or failure on natural 1 or 20. Power DC = 10 + floor(level/2) + WIS modifier (+ Resonance Focus feats, + prestige school bonus).
Grenade and mine DCs are listed on the item.

**Statuses** (`StatusRules`): the same status refreshes its duration. Within a group (control, fear, snare,
damage-over-time, shield…) the higher priority replaces the lower and the weaker is refused. Immunities are
by kind or tag. Some statuses break on damage (fear, pacify). Damage-over-time ticks at the bearer's round
boundary. Every status has a symbol and a name, so colour is never the only signal.

**Forms** (`data/forms.json`): three stances trading attack, damage, Defense and energy. Switching locks out
another switch for one round.

## 4. AI

`AIBrain.enemy_action` works by role:

- **melee:** close in.
- **ranged:** keep line of sight.
- **support:** repair or heal allies under 55%, suppression field on clusters, stun or adhesive grenades.
- **machine:** suppression pulse when crowded.

Enemies use frag grenades on clusters, use feats with some probability, and drink medpacs at low HP. Target
choice prefers near and wounded targets and sticks with the current target.

`AIBrain.companion_action` is the same brain your companions use; the playthrough bots also use it for the
character you control. It runs these checks in order:

1. Revive downed allies (medpac or repair kit).
2. Heal with powers or items below the behaviour's threshold.
3. Self-heal below 30%.
4. Self-buffs (Aegis).
5. Grenades into clusters, never near the party.
6. Control and damage powers on healthy targets.
7. Active feats.
8. Attack the leader's target.

Behaviours: aggressive, ranged, support, passive (passive companions only follow orders).

Companions step out of known hazards (detected hazard cells are expensive in pathing and never cut through by
path smoothing).

## 5. Stealth (`StealthRules`)

- **When an observer can perceive you:** within sight range, with line of sight, and either inside its 120° cone
  or within 2.5 m.
- **Check:** each second you are perceivable while sneaking, the observer rolls d20 + Awareness − floor(distance/2)
  against 10 + Stealth (+2 if you stood still). Success adds 0.4 suspicion, or 1.0 if it beats the DC by 10+;
  the Ghost Envoy prestige halves this.
- **Detection:** at suspicion 1.0 you are detected, and the encounter alerts (or offers its parley conversation the
  first time).
- **Decay:** suspicion decays at 0.25/s while you are not perceivable.

Noise (explosions, forcing doors) alerts listeners in the same area or with line of sight, so bulkheads muffle it.
Standing in a shadowed cell (maintenance ducts, dark corners) adds +4 to your Stealth DC. Being detected, attacking or using a power breaks stealth.

## 6. Characters and progression

- **Point buy:** 30 points, scores 8–18, costing 1 per step to 14, 2 per step to 16 and 3 per step to 18.
  Modifier = floor((score − 10)/2).
- **Skills:** points per level = class points + INT modifier (minimum 1), ×2 at level 1. Class skills cost 1 per
  rank, others 2. Rank cap = level + 3 for class skills, half that (floored) otherwise. Unspent points are banked.
- **Level-up:**
  - XP thresholds are in `progression.json`.
  - Attribute increases come at levels 4 and 8.
  - Feat and power picks per level are in the class tables.
  - "Recommended" uses `builds.json` priorities and goes through the same `Progression.apply_level_up` validation
    as manual choices.
- **Rewards:** XP, influence and alignment changes are keyed, so each is granted once. `GameState.grant_xp(amount,
  key)` and `add_influence(comp, delta, key)` refuse a key they have already seen, and so do skill-check results,
  which are rolled once and stored in `GameState.checks`. Reloading or replaying a conversation never pays twice.
- **Alignment:** −100 (Dominion) to +100 (Mercy). Mercy powers cost less toward Mercy and more toward Dominion,
  and Dominion powers the reverse. Universal powers are unaffected. Medium armor adds +2 energy to power costs and
  heavy armor blocks powers.
- **Prestige** (`data/prestige.json`, `Prestige`): available from level 6. There are three families, each with a
  requirement (Warden: BAB +5 and a martial technique; Weaver: 5 powers and WIS 14; Shade: 6 Stealth plus 6
  Security or Computer Use). Each family has a Mercy (alignment ≥ +30) and a Dominion (≤ −30) variant. The
  features are generic data keys read by the rules:

  | Key | Effect |
  |---|---|
  | `aura` | an aura applied to nearby allies |
  | `crit_status` | a status applied on critical hits |
  | `power_cost` | power cost adjustments |
  | `heal_mult` | healing multiplier |
  | `dc_bonus` | save DC bonus |
  | `chain_bonus` | extra chain targets |
  | `detection_mult` | changes how fast observers notice you |
  | `sneak_bonus` | extra sneak attack damage |
  | `passive` | passive bonuses |

## 7. Conditions and effects (data-only scripting)

Dialogue choices, interaction options, triggers, layout rules, quests and encounters all use structured
dictionaries. There is no expression parsing and no code evaluation. `Conditions.KNOWN` and `Effects.KNOWN` list
every key; `DataValidator` rejects unknown keys and dangling references (dialogue destinations, item, feat,
power, quest and encounter ids, layout objects) at startup and in `tests/test_data.gd`.

- **Conditions:** flags with eq/gte/lte, attr, skill, item, equipped, feat, power, class, background, alignment,
  influence, recruited, in_party, quest/stage/objective state, encounter state, cleared, level_gte, credits_gte,
  energy_gte, controlled, difficulty, check results, any/all/not.
- **Effects:** set/inc flags, XP, influence, alignment, items and credits, quest state/stage/objective,
  survivors, join/leave party, start/resolve encounter, world object state, npc state, damage/heal/status,
  area damage, teleport, codex, tutorial, notify, start_dialogue, open (station or ending), minigame,
  cinematic (+ `then` dialogue), autosave, and evac (seat arithmetic).

## 8. Dialogue (`DialogueEngine`)

- **Structure:** a conversation has entry nodes chosen by condition. A node has a speaker, text with pronoun
  tokens (`{they}`, `{them}`, `{their}`, `{are}`, `{s}`…), effects, and either `nxt`, choices or a router (`R`)
  of conditional branches.
- **Choices:**
  - Each choice can carry conditions (`hide_if` hides it, `show_locked` shows it disabled with a reason), a
    tone, effects and an optional check.
  - A check is a skill check by the acting character, or by a named companion for companion-assisted choices.
    Resonance-assisted persuasion checks require the power and spend energy.
  - Checks resolve once and are stored; the success and failure branches both continue the story.
  - The UI shows the skill, DC and the actual chance.
- **History and camera:** every line is appended to the conversation history (Journal → Conversations). The
  camera frames the speaker over the listener's shoulder.
- **Authoring:** dialogue is written in Python (`tools/dialogues/*.py`, helpers in `tools/author_dialogue.py`) and
  generated into `data/dialogue/*.json`. The generator and `DataValidator` both check every destination.

## 9. Quests (`QuestSystem`)

- **States:** inactive → active → completed | failed. Illegal transitions are refused, with a warning.
- **Stages:** stages carry journal text and objectives; objectives can be optional.
- **Transitions:**
  - Event-driven transitions are declared in `quests.json` (`event`, `match`, `from`/`from_state`, `if`).
  - Effects can also set state directly.
  - Completion XP is keyed.
- **The quests:**
  - `q_main` Escape the Cinder Wake.
  - `q_ward` The Sealed Ward.
  - `q_lantern` Lantern in the Dark.
  - `q_restart` Cold Restart (optional objective chain).

## 10. Economy

- **Inventory** (`Inventory`):
  - Stackable items are counts; equipment items are unique instances (`{uid, id, upgrades}`).
  - Every multi-step change (buy, sell, craft, dismantle, equip swap, upgrade install or remove, wagers) is one
    `Inventory.Tx`. A transaction validates every step against a staged copy before committing, so quantities
    never go negative and nothing is duplicated or lost on failure.
- **Equipment slots:** head, body, hands, belt, implant, wrist, and two weapon sets (main and off-hand each).
  Synthetics use the same slots under machine names.
- **Vendors:** finite stock; sell price is always below buy price (validated), so trading cannot create credits.
- **Crafting:** recipes need a station and a skill minimum. Dismantling returns less than an item's inputs
  (validated). Upgrades go in weapon or armor upgrade slots and are removable.

## 11. World construction

- **Generation:**
  - `tools/author_layout.py` and `tools/layout_content.py` generate `data/ship_layout.json`: area rectangles,
    doors with interaction options, props, signs, objects, NPCs, triggers and rules.
  - `LevelBuilder` turns it into merged meshes, wall collision runs (used for camera collision only), lights and
    props.
- **Navigation:** `ShipGrid` is a 1 m `AStarGrid2D`.
  - Closed but unlocked doors stay plannable and open automatically for a party member whose path crosses them.
  - Locked doors are solid.
  - Detected hazards cost 3×.
  - Line of sight is sampled on the grid.
- **State:** doors, containers and other world objects keep their state in `GameState.world[id]`, enemies in
  `GameState.enemies`, encounters in `GameState.encounters`, NPCs in `GameState.npcs`, and one-time triggers in
  the ledger.

## 12. Saves (`Saves`)

- **Format:** `{header, state}` JSON with `header.schema` (current 1). Newer schemas are refused; older ones go
  through `migrate()`.
- **Safe writes:** write a temp file, parse it back to verify, rotate the old file to `.bak`, then rename into
  place. A corrupt main file is recovered from `.bak` if possible and reported, never fatal.
- **Slots:**
  - quicksave (F5/F9)
  - three rotating checkpoint autosaves (area entries)
  - eight manual slots
  - `end_of_intro`, written at the ending. It shows that run's summary; it is not a resume point.
- **Persistence:** the RNG state, item uid counter, positions, queues, combat state and all of the above persist.
  `tests/test_saves.gd` round-trips a full state and corrupts files on purpose, and the playthrough bots check a
  mid-level save/reload against a snapshot.

## 13. Tooling

| Tool | Purpose |
|---|---|
| `tools/run_tests.sh` | import + headless suite; fails on any `SCRIPT ERROR` |
| `tools/bot_sweep.sh A B` | replay the bot playthroughs with dice offsets A…B |
| `tools/godot/gen_dev_stages.tscn` | regenerate `data/dev_stages.json` from a diplomat bot run |
| `tools/godot/bench.tscn` | CPU benchmark of the simulation (JSON report) |
| `tools/gen_audio.py` | regenerate all audio (deterministic) |
| `tools/author_layout.py`, `tools/author_dialogue.py` | regenerate layout and dialogue JSON (the dialogue tool also writes `voices.json`, `cinematics.json` and `ship_life.json` from `tools/dialogues/*.py` `OUTPUTS`) |

## 14. Presentation layer (voices, staging, ambient life, atmosphere, combat feel)

Everything in this section is presentation. It never writes `Actor` position, facing, path, queue or clocks,
character sheets, or `Game.state.dice`; cosmetic randomness uses the global `randf()`. The default-seed bot logs
(choices and full combat log) are byte-identical with and without it, and
`tests/test_ship_life.gd::test_ship_life_does_not_touch_the_simulation` runs the same fight both ways.

- **Two clocks.** Sim-clock presentation (`ActorVisual.animate`, `FX.step`) freezes on pause. Real-time
  presentation (`World._process`, `CameraRig`, `GameAudio`, `Atmosphere`, `ShipLife`, `OverheadBars`) may run
  during pauses and conversations but only touches visual nodes, materials, the camera, audio and UI.
  `World.present_visual(v)` lets a visual finish settling while paused (a fall started by an auto-pause).
- **Voices** (`GameAudio.voice_line`, `data/voices.json`): lines are babbled from four synthesised syllable banks
  (`vox_hlo/hhi/syn/wrd_NN`, `tools/gen_audio.py`). `voice_schedule()` is pure: syllables per word from vowel groups,
  word-stable syllable choice, pauses at punctuation, declination and a question rise, paced towards the text
  reveal speed. Channels: `dialogue`, `world` (barks) and `ship` (announcements).
- **Conversations.** `DialogueUI` reveals lines at the Text speed setting, voices them, shows reactions
  (approval, Mercy/Dominion, XP, codex) from `Events` while it is open, and colours choice tones.
  `DialogueStage` turns participants (`ActorVisual.present`: body and head yaw on the visual only, talk beats,
  gestures) and picks shots (`CameraRig.frame_shot`: `two`, `ots`, `close`; optional per-line `shot`/`anim`
  fields, validated). Shots stay on one side of the line and pull in front of walls (`safe_eye`).
- **Cinematics** are data (`data/cinematics.json`): shots with from/to/look, title cards, fades, voiced captions,
  `hide_party`, `hide_enemies`, `craft`, `then`. `CameraRig.scripted` keeps the rig from overriding them.
- **ShipLife** (`data/ship_life.json`): barks on events (`on` + `match` + conditions, chance, cooldowns,
  once-only via `chatter:<id>` ledger keys), banter by area, WARDEN and intercom announcements (the `bark`
  effect, area `on_enter`, flags, timers), approval reactions after conversations, and companion hooks that set a
  flag opening a topic in the companion's talk hub. Main creates it; tests and bots do not.
- **Atmosphere** (area fields `ambient`, `ambient_energy`, `fog`, `fog_density`, `alert`, `flicker`,
  `ambience`): blends light and haze, pulses alert red after `emergency_started`, flickers damaged lights, applies
  announcement trim pulses, animates the reactor, cores and viewport stars, freezes sparks on pause, and places
  positional loops. Only the current area and its neighbours are styled; no lights are added.
- **Camera modes** (`CameraRig.PROFILES`): `follow` (default; swings behind the leader on forward or path
  movement, never on strafe; lifts over walls that block the arm and fades the leader if still too close) and
  `tactical`. Tall props are on collision layer 2 for the follow camera. Ceilings face down only.
- **Combat feel.** `World._apply_events` adds sparks, muzzle flashes, dodge/block reactions, the miss sound,
  RESISTED and freed-status text, a crit FOV punch and push slides; `ActorVisual` adds a combat stance,
  flourishes between blows, the Lumen Edge igniting and retracting, and alignment on the protagonist's look.
  Bodies keep their fallen model (`WorldObject.adopt_visual`). `World.presented` (a signal, not an event) feeds
  ShipLife's crit barks. `OverheadBars` draws camera-facing health bars.
