class_name Dice
extends RefCounted
## Seeded, serializable random source used by every rules resolution.
## Tests can force upcoming results with force([..]) for exact scenarios.

var _rng := RandomNumberGenerator.new()
var seed_value: int = 1
var forced: Array[int] = []
var rolls_made: int = 0


func _init(seed_: int = 1) -> void:
	set_seed(seed_)


func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s
	rolls_made = 0


## Queue exact results for the next rolls (any die size). Used by tests.
func force(values: Array) -> void:
	for v in values:
		forced.append(int(v))


func roll(sides: int) -> int:
	rolls_made += 1
	if not forced.is_empty():
		return clampi(forced.pop_front(), 1, maxi(1, sides))
	if sides <= 1:
		return 1
	return _rng.randi_range(1, sides)


func d20() -> int:
	return roll(20)


func roll_dice(count: int, sides: int) -> Array[int]:
	var out: Array[int] = []
	for i in count:
		out.append(roll(sides))
	return out


## Rolls an expression like "2d6+3" and returns {total, rolls, bonus, expr}.
func roll_expr(expr: String) -> Dictionary:
	var p := Rules.parse_dice(expr)
	var rolls := roll_dice(int(p["count"]), int(p["sides"]))
	var total := int(p["bonus"])
	for r in rolls:
		total += r
	return {"total": total, "rolls": rolls, "bonus": int(p["bonus"]), "expr": expr}


func randf() -> float:
	rolls_made += 1
	return _rng.randf()


func randi_range(a: int, b: int) -> int:
	rolls_made += 1
	return _rng.randi_range(a, b)


func to_dict() -> Dictionary:
	# 64-bit state is stored as a string: JSON numbers are doubles.
	return {"seed": str(seed_value), "state": str(_rng.state), "rolls": rolls_made}


func from_dict(d: Dictionary) -> void:
	seed_value = int(String(d.get("seed", "1")))
	_rng.seed = seed_value
	_rng.state = int(String(d.get("state", "0")))
	rolls_made = int(d.get("rolls", 0))
	forced.clear()
