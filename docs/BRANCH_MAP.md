# Branch map: decisions and their consequences

This map follows the main decisions and the flags they set, then where each flag shows up later. All flags live
in `GameState.flags`. The dialogue sources are `tools/dialogues/*.py`; the layout options, triggers and rules are
in `tools/layout_content.py` and `tools/author_layout.py`. The ending screen (`scripts/ui/ending_ui.gd`) restates
each decision in plain language.

```
cabin ─ commons (check-in: +4 survivors) ─ corridor (Iona joins) ─ CHECKPOINT ─ medical (Tav-7 joins)
   ─ RESERVE + WARD ─ engineering (COLD RESTART?) ─ archive (SENNA, SQUAD, INDEX) ─ command (LAUNCH, ARCHIVE, WARDEN)
   ─ bay (QUILL) ─ launch (PURSUIT) ─ companion exchange ─ revelation (Instance Four) ─ ending + end-of-intro save
```

## 1. Forward checkpoint: the major obstacle (`checkpoint_by`)

| Approach | How | Sets | Later effect |
|---|---|---|---|
| Combat | Destroy the turret and pickets, then crank the dead lock (`d_blast` → manual) | `checkpoint_by=combat` | none beyond the fight and XP |
| Technical | Checkpoint terminal: Computer Use DC 15 to override the door (also turret DC 13, drones DC 17), or Security DC 17 on the lock | `checkpoint_by=terminal` or `security` | A failed check starts the fight (`checkpoint_alarm`) |
| Stealth | Unbolt the maintenance grate (Repair DC 10, or force it noisily), crawl, then pull the manual release from the medical side | `checkpoint_by=crawlway`, `found_crawlway` | The crawlway cache. The checkpoint encounter is bypassed. |
| Conversation | Resonance credential: WARDEN recognises you and stands the checkpoint down | `checkpoint_by=credential`, `used_credential`, **`warden_tracking`** | WARDEN now tracks you: a second Cutter Spider joins the engineering Sentinel post. Iona asks about it (honest, deferred and dismissive answers move influence). Unlocks Iona's first Resonance conversation (`iona_res_seen`). |

## 2. Medical reserve (`med_supplies_choice`, quest *The Sealed Ward*)

| Choice | Check | Survivors | Other |
|---|---|---|---|
| Spend it on the wounded (`treated`) | — | +3 | Mercy +8 |
| Split it, with Iona's or your Medicine (`split`) | Medicine DC 12/14 | +3 | Party keeps a trauma pack and reagents; Iona +5 if you trusted her |
| Split it, failed (`split_failed`) | — | +2 | One patient dies; noted later |
| Take it for the party (`took`) | — | +1 | Dominion; Iona and Varga disapprove |

## 3. Sealed passenger ward (`ward_choice`)

| Choice | Requirement | Survivors | Later |
|---|---|---|---|
| Purge the bad air, then open (`purged`) | Tav-7 runs the purge panel | +5 | Iona's ending line ("Pell Okafor hugged me") |
| Open it now (`rushed`) | — | +4 | Iona: "It cost something. It was worth it." |
| Keep it sealed (`sealed`) | — | +0 | Iona carries it into the ending. If the Lantern rescue is negotiated in the bay, Quill promises to open it (`lantern_rescues`). |
| Leave it undecided and enter command | — | — | *The Sealed Ward* fails |

## 4. Cold Restart (optional, engineering)

Restarting both coolant pumps (Repair checks, or Pump Seal Kits crafted at the workshop bench) sets
`pumps_restored`. That enables the **archive coolant purge** (a skill route through the reclaimer squad) and powers
the **bay turrets and apron shield** (the technical bay resolution). The live deck plates can be disabled from the
terminal or the junction (`plates_disabled`). The maintenance hatch (Repair or Security DC 14) bypasses the
Sentinel post (`engineering_bypassed`).

## 5. Senna Thorne (`senna_fate`, quest *Lantern in the Dark*)

| Choice | Sets | Later |
|---|---|---|
| Treat her (Medicine check or a medpac) (`treated`) | `senna_message`, `lantern_passphrase`, Mercy | The archive squad accepts the passphrase "ember-tide" at parley. Quill hears Senna's message (+3 on bay persuasion). |
| Bargain: her freedom for the passphrase (`bargained`) | `promised_lantern`, `lantern_passphrase` | Parley open; Quill expects your promise |
| Interrogate (Persuasion DC 14 intimidate) (`interrogated`) | `lantern_passphrase`, Dominion | Parley open; Iona −3 |
| Release her (`released`) | — | — |
| Kill her (`killed`) | Dominion | Quill's opening line changes. An **extra breacher** joins the bay, and the whole bay encounter gets **+1 attack**. |

**Archive squad:** parley with the passphrase or Persuasion; failure means a fight. The coolant purge freezes
them first. Success sets `archive_peace` (+3 on Quill's oath check).

**Archive index:** Tav-7 or a Computer Use check opens the engram records (`archive_evidence_*`). You can copy
the Vesper testimony item, which adds +2 to Quill's oath check and enables the testimony launch option.

## 6. Launch control (`evac_choice`, `archive_fate`, `warden_fate`)

The Petrel seats **15 − party size**, and the archive cradle takes 5 of those seats (`Effects.evac` computes
`evac_aboard` and `evac_left`).

| Choice | Sets | Later |
|---|---|---|
| Passengers first (persuade, compel or arrest Varr) | `evac_choice=passengers` | Iona +4. The archive stays behind or is handed over. |
| Load the archive core | `evac_choice=archive`, `archive_fate=loaded` | 5 fewer seats (`evac_left` may be > 0). Tav-7 +4, Iona −6. An **extra marksman** joins the bay unless the breach was sealed. |
| Hand the archive to the Lantern | `evac_choice=handover`, `archive_fate=handed_over` | Every seat for people; Quill's people take the core home |
| Carry the Vesper testimony instead | `evac_choice=testimony` | Every seat for people. The core's fate is then decided: hand over, purge or leave. |
| Archive fate | `archive_fate=handed_over/purged/left` | Quill's reaction and checks in the bay. Purging requires Persuasion DC 17 to avoid a fight. |
| Seal Bay 2's hull breach | `breach_sealed`, `lantern_reduced` | **Two fewer** reclaimers (the second breacher and marksman), and no signalist |

**WARDEN core:** order it to stand down, bargain, let Tav-7 host it (`tav7_hosts_warden`, which
grants Tav-7 a feat), purge it (Tav-7 −10) or ignore it. All but "ignore" set `warden_neutralized`, which removes
the WARDEN pursuit drones from the bay and means no interceptors chase the Petrel.

## 7. Evacuation bay (`bay_resolution`)

| Resolution | How | Composition |
|---|---|---|
| Negotiated (`negotiated`, `lantern_truce`) | Quill's parley: Persuasion checks get bonuses from Senna's message (+3), archive peace (+3), the testimony (+2) and the kinship token (+2). Haldis-native options exist. | No fight; possible `lantern_rescues` |
| Technical (`technical`) | Bay terminal: bring the turrets online and drop the launch apron shield (requires `pumps_restored`) | The bay's two turrets switch to your side |
| Combat (`combat`) | Fight Marshal Quill's line | Quill + breacher + marksman, plus the conditional spawns above (Senna killed, archive loaded, breach not sealed, WARDEN not neutralized). Parties below level 4 face 75% health and −1 attack. |

## 8. Pursuit, exchange and revelation

- **Pursuit:** if WARDEN is not neutralized, two interceptors chase the Petrel (`turret_result`). You can:
  - Man the turret yourself (the turret minigame, with assisted targeting or the autopilot roll).
  - Send Iona (Awareness).
  - Send Tav-7 (Computer Use).
  - Have Brann burn hard (always succeeds, but damages the Petrel).

  A damaged hull (`petrel_damaged`) is noted in the summary.
- **Companion exchange:** each companion's lines depend on influence, with thresholds at 65+ and 35−:
  - Iona: "I want to be on your references" at high influence; at 35 or below she leaves when the Petrel docks
    (`iona_leaves`).
  - Tav-7: stays at high influence; leaves at 35 or below (`tav7_leaves`); has unique lines if hosting WARDEN.
  - Iona also reflects the ward decision; the narration reflects the archive's fate.
- **Revelation:** Instance Four of the Custodian template hails the Petrel. You are one of nine. Your final stance
  (truth, control, wary or silence) is recorded (`final_stance`), then the ending summary appears and the
  end-of-intro save is written.

## Observed bot branches (latest run)

| Route | Checkpoint | Reserve / ward | Senna | Launch / archive / WARDEN | Bay | Survivors |
|---|---|---|---|---|---|---|
| Martial (Vanguard) | combat | took / sealed | killed | archive / loaded / purged | combat | 5 |
| Technical (Operative) | terminal | split_failed / purged | treated | testimony / handed_over / hosted | negotiated | 11 |
| Diplomat (Adept) | credential | split / rushed | bargained | handover / handed_over / commanded | negotiated | 11 |

These come from the fixed-seed runs in `tests/test_playthrough.gd`. Other seeds take other branches where a
check fails (see `tools/bot_sweep.sh`).
