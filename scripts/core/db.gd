extends Node
## Data registry. Loads every JSON definition under res://data and exposes
## read-only lookups. All gameplay content (classes, items, feats, powers,
## enemies, dialogue, quests, encounters, layout) is data, validated by
## DataValidator at startup and in tests.

const DATA_DIR := "res://data/"

var classes: Dictionary = {}
var skills: Dictionary = {}
var progression: Dictionary = {}
var feats: Dictionary = {}
var powers: Dictionary = {}
var statuses: Dictionary = {}
var forms: Dictionary = {}
var backgrounds: Dictionary = {}
var appearance: Dictionary = {}
var items: Dictionary = {}
var recipes: Dictionary = {}
var enemies: Dictionary = {}
var companions: Dictionary = {}
var quests: Dictionary = {}
var encounters: Dictionary = {}
var prestige: Dictionary = {}
var vendors: Dictionary = {}
var tutorials: Dictionary = {}
var codex: Dictionary = {}
var layout: Dictionary = {}
var dev_presets: Dictionary = {}
var dev_stages: Dictionary = {}
var builds: Dictionary = {}
var dialogues: Dictionary = {}
var voices: Dictionary = {}
var cinematics: Dictionary = {}
var ship_life: Dictionary = {}
var load_errors: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	load_errors.clear()
	classes = _load("classes.json")
	skills = _load("skills.json")
	progression = _load("progression.json")
	feats = _load("feats.json")
	powers = _load("powers.json")
	statuses = _load("statuses.json")
	forms = _load("forms.json")
	backgrounds = _load("backgrounds.json")
	appearance = _load("appearance.json")
	items = _load("items.json")
	recipes = _load("recipes.json")
	enemies = _load("enemies.json")
	companions = _load("companions.json")
	quests = _load("quests.json")
	encounters = _load("encounters.json")
	prestige = _load("prestige.json")
	vendors = _load("vendors.json")
	tutorials = _load("tutorials.json")
	codex = _load("codex.json")
	layout = _load("ship_layout.json")
	dev_presets = _load("dev_presets.json")
	dev_stages = _load("dev_stages.json")
	builds = _load("builds.json")
	voices = _load("voices.json")
	cinematics = _load("cinematics.json")
	ship_life = _load("ship_life.json")
	dialogues.clear()
	var ddir := DATA_DIR + "dialogue/"
	var files := DirAccess.get_files_at(ddir)
	for f in files:
		var fname := String(f)
		if fname.ends_with(".json"):
			var d := _load("dialogue/" + fname)
			if d.has("id"):
				dialogues[String(d["id"])] = d
			else:
				load_errors.append("dialogue file without id: " + fname)
	for e in load_errors:
		push_error("DB: " + e)


func _load(rel: String) -> Dictionary:
	var path := DATA_DIR + rel
	if not FileAccess.file_exists(path):
		load_errors.append("missing data file " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(txt)
	if err != OK:
		load_errors.append("%s: JSON error line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		load_errors.append(path + ": root must be an object")
		return {}
	var out: Dictionary = json.data
	out.erase("_comment")
	return out


# ---------------------------------------------------------------- lookups
func item(id: String) -> Dictionary:
	return items.get(id, {})


func feat(id: String) -> Dictionary:
	return feats.get(id, {})


func power(id: String) -> Dictionary:
	return powers.get(id, {})


func status(id: String) -> Dictionary:
	return statuses.get(id, {})


func klass(id: String) -> Dictionary:
	return classes.get(id, {})


func skill(id: String) -> Dictionary:
	return skills.get(id, {})


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


func dialogue(id: String) -> Dictionary:
	return dialogues.get(id, {})


## Voice for a speaker id: {bank, count, pitch, rate, bus}. Unlisted
## speakers get a stable voice derived from their id; machines sound synthetic.
func voice_for(sid: String) -> Dictionary:
	var v: Dictionary = dict(voices, "default").duplicate()
	var sp: Dictionary = dict(voices, "speakers")
	if sp.has(sid):
		v.merge(sp[sid], true)
	else:
		var h := absi(hash(sid))
		var model := String(dict(dict(dict(layout, "npcs"), sid), "appearance").get("model", ""))
		if model in ["synthetic", "drone", "drone_support", "spider", "turret", "sentinel"]:
			v["bank"] = "syn"
		else:
			v["bank"] = "hhi" if h % 2 == 0 else "hlo"
		v["pitch"] = 0.9 + float(h % 21) / 100.0
	v["count"] = int(dict(voices, "banks").get(String(v.get("bank", "")), 0))
	return v


## An ambient line by id (barks and announcements in data/ship_life.json).
func ship_line(id: String) -> Dictionary:
	for sec in ["barks", "announcements"]:
		for l in arr(ship_life, sec):
			if String(l.get("id", "")) == id:
				return l
	return {}


func item_name(id: String) -> String:
	return String(item(id).get("name", id))


func skill_ids() -> Array[String]:
	var out: Array[String] = []
	for k in skills.keys():
		out.append(String(k))
	out.sort_custom(func(a: String, b: String) -> bool: return int(skills[a].get("order", 0)) < int(skills[b].get("order", 0)))
	return out


func validate() -> Array[String]:
	var v := DataValidator.new()
	return v.validate_all(self)


# ---------------------------------------------------------------- helpers
static func num(d: Dictionary, key: String, default_value: int = 0) -> int:
	if d.has(key) and d[key] != null:
		return int(d[key])
	return default_value


static func numf(d: Dictionary, key: String, default_value: float = 0.0) -> float:
	if d.has(key) and d[key] != null:
		return float(d[key])
	return default_value


static func arr(d: Dictionary, key: String) -> Array:
	if d.has(key) and typeof(d[key]) == TYPE_ARRAY:
		return d[key]
	return []


static func dict(d: Dictionary, key: String) -> Dictionary:
	if d.has(key) and typeof(d[key]) == TYPE_DICTIONARY:
		return d[key]
	return {}


## JSON numbers are floats; Array.has() is type-strict, so convert first.
static func int_arr(v: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append(int(x))
	return out


static func str_arr(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			out.append(String(x))
	return out
