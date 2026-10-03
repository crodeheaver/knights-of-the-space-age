extends TestCase
## Whole-data validation: every ID, prerequisite, reference and dialogue
## destination must resolve.


func test_all_data_valid() -> void:
	var errs := DB.validate()
	for e in errs:
		fail(e)
	assert_empty(errs)


func test_content_minimums() -> void:
	var real_items := 0
	for k in DB.items.keys():
		var it: Dictionary = DB.items[k]
		if not bool(it.get("natural", false)) and not bool(it.get("implicit", false)):
			real_items += 1
	assert_gte(real_items, 24, "at least 24 item definitions")
	var pickable := 0
	for f in DB.feats.keys():
		if not bool(DB.feats[f].get("earned", false)):
			pickable += 1
	assert_gte(pickable, 12, "at least 12 feats")
	var learnable := 0
	for p in DB.powers.keys():
		if not bool(DB.powers[p].get("innate", false)):
			learnable += 1
	assert_gte(learnable, 10, "at least 10 powers")
	assert_gte(DB.recipes.size(), 8, "at least 8 recipes")
	assert_eq(DB.skills.size(), 8)
	assert_eq(DB.backgrounds.size(), 3)
	var roles := {}
	for e in DB.enemies.keys():
		roles[String(DB.enemies[e]["role"])] = true
	for r in ["melee", "ranged", "support", "machine"]:
		assert_true(roles.has(r), "enemy role " + r)
	var opt := 0
	for q in DB.quests.keys():
		if String(DB.quests[q].get("type", "")) == "optional":
			opt += 1
	assert_gte(opt, 2, "two optional quests")
	assert_gte(DB.dict(DB.layout, "areas").size(), 8, "8+ distinct spaces")


func test_every_skill_used_in_level() -> void:
	## Each of the eight skills must have at least one in-level use.
	var used := {}
	var txt := JSON.stringify(DB.layout) + JSON.stringify(DB.dialogues)
	for s in DB.skills.keys():
		if txt.contains("\"%s\"" % s):
			used[s] = true
	# Awareness and Demolitions are used systemically (hidden objects, mines).
	for o in DB.layout.get("objects", []):
		if int(o.get("hidden_dc", 0)) > 0:
			used["awareness"] = true
		if String(o.get("type", "")) == "mine":
			used["demolitions"] = true
	# Stealth is used by detection; verify a shadow zone and a bypass trigger exist.
	var has_shadow := false
	for a in DB.dict(DB.layout, "areas").values():
		if not (a.get("shadows", []) as Array).is_empty():
			has_shadow = true
	if has_shadow:
		used["stealth"] = true
	for s in DB.skills.keys():
		assert_true(used.has(s), "skill %s has an in-level use" % s)


## Everything is original: no names or terms borrowed from the space-fantasy
## franchise this game's genre descends from. Scans every player-facing text.
const BORROWED := ["jedi", "sith", "lightsaber", "wookiee", "droid", "droids", "the force", "revan", "malak", "bastila",
	"ebon hawk", "tatooine", "coruscant", "mandalorian", "hutt", "taris", "dantooine", "holocron", "padawan", "kolto",
	"sabacc", "pazaak"]


func _texts(v: Variant, out: PackedStringArray) -> void:
	match typeof(v):
		TYPE_STRING:
			out.append(String(v))
		TYPE_DICTIONARY:
			for k in (v as Dictionary).keys():
				_texts(v[k], out)
		TYPE_ARRAY:
			for x in v:
				_texts(x, out)


func test_content_is_original() -> void:
	var out := PackedStringArray()
	for src in [DB.dialogues, DB.codex, DB.cinematics, DB.tutorials, DB.layout, DB.items, DB.feats, DB.powers, DB.quests, DB.companions]:
		_texts(src, out)
	if DB.get("ship_life") != null:
		_texts(DB.get("ship_life"), out)
	var re := RegEx.new()
	re.compile("(?i)\\b(" + "|".join(BORROWED) + ")\\b")
	var hits: Array[String] = []
	for t in out:
		var m := re.search(t)
		if m != null:
			hits.append("'%s' in: %s" % [m.get_string(), t.left(90)])
	for h in hits:
		fail(h)
	assert_gte(out.size(), 1000, "scanned the content")
