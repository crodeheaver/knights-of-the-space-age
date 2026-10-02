# Asset manifest

There are **no third-party assets** in this project. All content is original and owned by the project.

| Kind | What | Source | Licence |
|---|---|---|---|
| Story, characters, factions, dialogue, codex, quest and item text | ~9,500 words across 28 conversations, 17 codex entries, 16 tutorials | written for this project (`tools/dialogues/*.py`, `data/*.json`) | project-owned |
| Rules and data | classes, skills, feats, powers, items, enemies, encounters, prestige | written for this project; the d20-style mechanics are generic game-design conventions, and no rules text is copied from other games | project-owned |
| Level geometry | 9 main areas + 8 side rooms, doors, props, signs | generated from `data/ship_layout.json` by `scripts/world/level_builder.gd` (procedural boxes, cylinders and capsules) | project-owned |
| Characters and creatures | humanoids, synthetic, drones, cutter spider, turret, sentinel | built from primitives in code (`scripts/world/actor_visual.gd`), with procedural animation | project-owned |
| Shaders | `assets/shaders/floor.gdshader`, `wall.gdshader` (world-space panel seams) | written for this project | project-owned |
| Portraits | rendered live from the character models (`scripts/ui/portraits.gd`) | generated | project-owned |
| UI | theme and widgets in code (`scripts/ui/ui_kit.gd`); minigame visuals drawn with `_draw()` | written for this project | project-owned |
| Audio | 38 files: UI, combat and world SFX, ship ambience, 5 music loops (`assets/audio/*.wav`) | synthesized by `tools/gen_audio.py` (standard library only, deterministic) | original, CC0-equivalent; full per-file table in [ASSETS_AUDIO.md](ASSETS_AUDIO.md) |
| Font | Godot's built-in default UI font | ships with the engine | engine licence (Godot is MIT; its default font is under its open licence) |
| Icon | `icon.svg` | drawn for this project | project-owned |
| Screenshots | `docs/screenshots/*.jpg` | captured from the game under Xvfb (software rendering) | project-owned |
| Engine | Godot Engine 4.4.1-stable | godotengine.org | MIT (© Juan Linietsky, Ariel Manzur and contributors) |

Regenerating content:

```bash
python3 tools/author_layout.py      # data/ship_layout.json
python3 tools/author_dialogue.py    # data/dialogue/*.json
python3 tools/gen_audio.py          # assets/audio/*.wav (+ docs/ASSETS_AUDIO.md)
godot --headless --path . res://tools/godot/gen_dev_stages.tscn   # data/dev_stages.json
```
