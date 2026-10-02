class_name TestCase
extends RefCounted
## Minimal assertion base for the headless test runner.

var failures: Array[String] = []
var current := ""
var asserts := 0


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current, msg])


func assert_true(v: bool, msg: String = "") -> void:
	asserts += 1
	if not v:
		fail("expected true. " + msg)


func assert_false(v: bool, msg: String = "") -> void:
	asserts += 1
	if v:
		fail("expected false. " + msg)


func assert_eq(a: Variant, b: Variant, msg: String = "") -> void:
	asserts += 1
	var same: bool = a == b
	if not same and typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		same = absf(float(a) - float(b)) < 0.0001
	if not same:
		fail("expected %s == %s. %s" % [str(a), str(b), msg])


func assert_ne(a: Variant, b: Variant, msg: String = "") -> void:
	asserts += 1
	if a == b:
		fail("expected %s != %s. %s" % [str(a), str(b), msg])


func assert_gte(a: float, b: float, msg: String = "") -> void:
	asserts += 1
	if a < b:
		fail("expected %s >= %s. %s" % [str(a), str(b), msg])


func assert_lte(a: float, b: float, msg: String = "") -> void:
	asserts += 1
	if a > b:
		fail("expected %s <= %s. %s" % [str(a), str(b), msg])


func assert_empty(arr: Array, msg: String = "") -> void:
	asserts += 1
	if not arr.is_empty():
		fail("expected empty, got %s. %s" % [str(arr), msg])


## Fresh game state with a recommended build (no world).
func fresh_state(cls: String = "vanguard") -> GameState:
	Game.new_game(BuildValidator.recommended(cls), "standard")
	Game.state.dice.set_seed(42)
	return Game.state


func before_each() -> void:
	pass
