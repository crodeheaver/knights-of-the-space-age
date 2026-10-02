class_name Rules
extends RefCounted
## Core d20 arithmetic shared across the rules layer. See docs/RULES.md for the
## authoritative description of modifier order.

const ATTRS: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const ATTR_NAMES := {"str": "Strength", "dex": "Dexterity", "con": "Constitution", "int": "Intelligence", "wis": "Wisdom", "cha": "Charisma"}
const SAVE_ATTR := {"fort": "con", "ref": "dex", "will": "wis"}
const SAVE_NAMES := {"fort": "Fortitude", "ref": "Reflex", "will": "Will"}
const ROUND := 3.0


## Attribute modifier = floor((score - 10) / 2). Uses float division so that
## odd scores below 10 round toward negative infinity (9 -> -1).
static func mod(score: int) -> int:
	return floori((score - 10) / 2.0)


static func parse_dice(expr: String) -> Dictionary:
	var e := expr.strip_edges().to_lower().replace(" ", "")
	var count := 0
	var sides := 0
	var bonus := 0
	if e == "":
		return {"count": 0, "sides": 0, "bonus": 0}
	var bonus_part := ""
	var dice_part := e
	var plus := e.find("+", 1)
	var minus := e.find("-", 1)
	var split := -1
	if plus >= 0:
		split = plus
	if minus >= 0 and (split < 0 or minus < split):
		split = minus
	if split >= 0:
		dice_part = e.substr(0, split)
		bonus_part = e.substr(split)
	if dice_part.contains("d"):
		var parts := dice_part.split("d")
		count = int(parts[0]) if parts[0] != "" else 1
		sides = int(parts[1])
	else:
		bonus += int(dice_part)
	if bonus_part != "":
		bonus += int(bonus_part)
	return {"count": count, "sides": sides, "bonus": bonus}


static func dice_avg(expr: String) -> float:
	var p := parse_dice(expr)
	return float(p["count"]) * (float(p["sides"]) + 1.0) / 2.0 + float(p["bonus"])


static func signed(v: int) -> String:
	return ("+%d" % v) if v >= 0 else str(v)


## Damage-type multiplier by creature kind. Ion is anti-machine.
static func kind_multiplier(dtype: String, kind: String) -> float:
	if dtype == "ion":
		return 2.0 if kind == "machine" else 0.25
	if dtype == "toxic" and kind == "machine":
		return 0.0
	return 1.0


static func round_seconds() -> float:
	return float(DB.progression.get("round_seconds", ROUND)) if DB and not DB.progression.is_empty() else ROUND
