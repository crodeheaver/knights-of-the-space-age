class_name ShardsRules
extends RefCounted
## Rules for Shards, the card game Brann Ketterick deals in the crew commons.
## Pure and deterministic: every random draw goes through the given Dice, so a
## seeded Dice (or a stacked deck) replays a match exactly. No nodes and no
## GameState here; wagers and rewards live in MinigameRewards.
##
## A set: a shared main deck holds four each of 1..10. On your turn the deck
## deals you one card; you may then play at most one shard from your hand,
## then end the turn or stand. Over 20 at the end of your turn is a bust and
## loses the set; nine cards on your table without busting wins it outright;
## reaching exactly 20 stands you automatically. When both players stand, the
## total closer to 20 wins and a tie is replayed. First to two sets takes the
## match. Each player's hand of four shards is drawn from their side deck at
## the start of the match and spent shards do not come back.

const TARGET := 20
const TABLE_MAX := 9
const SETS_TO_WIN := 2
const HAND_SIZE := 4
const PLAYER := 0
const OPPONENT := 1
## Hard stop so a freak run of tied sets can never loop forever.
const MAX_SETS := 15

## Side decks as shard codes: "+n" / "-n" adjust by n, "~n" is a swing shard
## played as +n or -n, "E" (echo) repeats your last main-deck card, "N"
## (null) cancels it.
const PLAYER_SIDE: Array[String] = ["+1", "+2", "+3", "+4", "+5", "+6", "-1", "-2", "-3", "-4", "-5", "-6", "~1", "~2", "E", "N"]
const OPPONENT_SIDE: Array[String] = ["+2", "+3", "+4", "+5", "-2", "-3", "-4", "-5", "~1", "~2", "E", "N"]

## How the AI plays. stand_at: always stand at or above this total.
## risk: stand below stand_at when the chance of busting on the next card is
## at least this high and no shard in hand could pull the total back.
const AI_STAND_AT := 18
const AI_RISK := 0.55


## One player's side of the table.
class Seat:
	extends RefCounted
	var name := ""
	var table: Array[Dictionary] = []
	var hand: Array[Dictionary] = []
	var standing := false
	var sets := 0
	var played_shard := false
	var last_main := 0

	func total() -> int:
		var t := 0
		for c in table:
			t += int(c["value"])
		return t


var dice: Dice
var sides: Array[Seat] = []
var deck: Array[int] = []
## Cards forced to the top of the deck (tests and tutorials); dealt in order.
var stacked: Array[int] = []
var active := PLAYER
## "idle" → ("deal" → "act")* → "set_over" | "match_over"
var phase := "idle"
var set_index := 0
var set_results: Array[Dictionary] = []
var match_winner := -1
var log_lines: Array[String] = []


func _init(d: Dice = null) -> void:
	dice = d if d != null else Dice.new(1)
	for i in 2:
		sides.append(Seat.new())
	sides[PLAYER].name = "You"
	sides[OPPONENT].name = "Brann"


# ------------------------------------------------------------ shards
static func parse(code: String) -> Dictionary:
	if code == "E":
		return {"kind": "echo", "value": 0, "code": code}
	if code == "N":
		return {"kind": "null", "value": 0, "code": code}
	var n := absi(int(code.substr(1)))
	match code.substr(0, 1):
		"+":
			return {"kind": "plus", "value": n, "code": code}
		"-":
			return {"kind": "minus", "value": n, "code": code}
		"~":
			return {"kind": "swing", "value": n, "code": code}
	push_error("Unknown shard code " + code)
	return {"kind": "plus", "value": 0, "code": code}


static func label(shard: Dictionary) -> String:
	var v := int(shard.get("value", 0))
	match String(shard.get("kind", "")):
		"plus":
			return "+%d" % v
		"minus":
			return "−%d" % v
		"swing":
			return "±%d" % v
		"echo":
			return "Echo"
		"null":
			return "Null"
	return "?"


static func describe(shard: Dictionary) -> String:
	var v := int(shard.get("value", 0))
	match String(shard.get("kind", "")):
		"plus":
			return "Adds %d to your total." % v
		"minus":
			return "Subtracts %d from your total." % v
		"swing":
			return "Swing shard: play it as +%d or −%d, your choice." % [v, v]
		"echo":
			return "Echo: repeats the value of the last main-deck card you were dealt this set."
		"null":
			return "Null: cancels the last main-deck card you were dealt this set (subtracts its value)."
	return ""


## Signs a shard can be played with: swing shards both ways, others once.
static func signs_for(shard: Dictionary) -> Array[int]:
	if String(shard.get("kind", "")) == "swing":
		return [1, -1]
	return [1]


## What a shard would add to player p's total right now.
func shard_value(p: int, shard: Dictionary, sign_: int = 1) -> int:
	var v := int(shard.get("value", 0))
	match String(shard.get("kind", "")):
		"plus":
			return v
		"minus":
			return -v
		"swing":
			return v if sign_ >= 0 else -v
		"echo":
			return sides[p].last_main
		"null":
			return -sides[p].last_main
	return 0


# ------------------------------------------------------------ match flow
func start_match(player_side: Array[String] = PLAYER_SIDE, opponent_side: Array[String] = OPPONENT_SIDE) -> void:
	set_index = 0
	set_results.clear()
	match_winner = -1
	log_lines.clear()
	for s in sides:
		s.sets = 0
	sides[PLAYER].hand = _draw_hand(player_side)
	sides[OPPONENT].hand = _draw_hand(opponent_side)
	start_set()


func _draw_hand(codes: Array[String]) -> Array[Dictionary]:
	var pool: Array[String] = codes.duplicate()
	_shuffle_strings(pool)
	var out: Array[Dictionary] = []
	for i in mini(HAND_SIZE, pool.size()):
		out.append(parse(pool[i]))
	return out


## Replaces a hand outright (tests, or a fixed tutorial hand).
func set_hand(p: int, codes: Array) -> void:
	var h: Array[Dictionary] = []
	for c in codes:
		h.append(parse(String(c)))
	sides[p].hand = h


func start_set() -> void:
	for s in sides:
		s.table.clear()
		s.standing = false
		s.played_shard = false
		s.last_main = 0
	deck = _fresh_deck()
	# Sets alternate who opens, replays included.
	active = PLAYER if set_index % 2 == 0 else OPPONENT
	phase = "deal"
	_log("Set %d. %s open%s." % [set_index + 1, sides[active].name, "" if active == PLAYER else "s"])


## From "set_over": deal the next set. Returns false if the match is over.
func next_set() -> bool:
	if phase != "set_over":
		return false
	set_index += 1
	start_set()
	return true


func _fresh_deck() -> Array[int]:
	var d: Array[int] = []
	for v in range(1, 11):
		for i in 4:
			d.append(v)
	# Fisher-Yates with the seeded dice.
	for i in range(d.size() - 1, 0, -1):
		var j := dice.randi_range(0, i)
		var tmp := d[i]
		d[i] = d[j]
		d[j] = tmp
	return d


func _shuffle_strings(a: Array[String]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := dice.randi_range(0, i)
		var tmp := a[i]
		a[i] = a[j]
		a[j] = tmp


## Forces the next main-deck cards (in order). Used by tests.
func stack_deck(values: Array) -> void:
	for v in values:
		stacked.append(clampi(int(v), 1, 10))


func _draw_main() -> int:
	if not stacked.is_empty():
		var v: int = stacked.pop_front()
		# Keep the deck honest: take the forced card out of it if present.
		var at := deck.find(v)
		if at >= 0:
			deck.remove_at(at)
		return v
	if deck.is_empty():
		deck = _fresh_deck()
	return deck.pop_back()


## Deals the active player's main-deck card for this turn. Returns its value,
## or 0 when no deal is due.
func deal() -> int:
	if phase != "deal":
		return 0
	var s := sides[active]
	var v := _draw_main()
	s.table.append({"value": v, "src": "main", "label": str(v), "kind": "main"})
	s.last_main = v
	s.played_shard = false
	phase = "act"
	_log("%s draw%s %d (total %d)." % [s.name, "" if active == PLAYER else "s", v, s.total()])
	return v


## "" when player p may play hand[idx] with this sign now, else the reason.
func can_play(p: int, idx: int, sign_: int = 1) -> String:
	if phase != "act":
		return "Wait for your card."
	if p != active:
		return "Not your turn."
	var s := sides[p]
	if s.played_shard:
		return "One shard per turn."
	if idx < 0 or idx >= s.hand.size():
		return "No such shard."
	if not signs_for(s.hand[idx]).has(1 if sign_ >= 0 else -1):
		return "That shard has no sign choice."
	var k := String(s.hand[idx]["kind"])
	if (k == "echo" or k == "null") and s.last_main <= 0:
		return "Needs a dealt card this set."
	return ""


## The active player plays shard idx. Returns "" on success, else the reason
## (and nothing changes).
func play_shard(idx: int, sign_: int = 1) -> String:
	var why := can_play(active, idx, sign_)
	if why != "":
		return why
	var s := sides[active]
	var shard: Dictionary = s.hand[idx]
	var v := shard_value(active, shard, sign_)
	s.hand.remove_at(idx)
	s.played_shard = true
	var lbl := label(shard)
	if String(shard["kind"]) == "swing":
		lbl = ("+%d" if v >= 0 else "−%d") % absi(v)
	s.table.append({"value": v, "src": "shard", "label": lbl, "kind": String(shard["kind"]), "shard": label(shard)})
	_log("%s play%s %s (total %d)." % [s.name, "" if active == PLAYER else "s", label(shard), s.total()])
	return ""


func end_turn() -> String:
	if phase != "act":
		return "Wait for your card."
	_end_of_turn(false)
	return ""


func stand() -> String:
	if phase != "act":
		return "Wait for your card."
	_end_of_turn(true)
	return ""


func _end_of_turn(standing: bool) -> void:
	var p := active
	var s := sides[p]
	var t := s.total()
	if t > TARGET:
		_log("%s bust%s at %d." % [s.name, "" if p == PLAYER else "s", t])
		_finish_set(1 - p, "bust")
		return
	if s.table.size() >= TABLE_MAX:
		_log("%s fill%s the table with nine cards." % [s.name, "" if p == PLAYER else "s"])
		_finish_set(p, "nine")
		return
	if standing or t == TARGET:
		s.standing = true
		_log("%s stand%s on %d." % [s.name, "" if p == PLAYER else "s", t])
	var o := 1 - p
	if not sides[o].standing:
		active = o
	elif not s.standing:
		active = p
	else:
		var a := sides[PLAYER].total()
		var b := sides[OPPONENT].total()
		if a == b:
			_log("Both stand on %d. The set is replayed." % a)
			_finish_set(-1, "tie")
		else:
			_finish_set(PLAYER if a > b else OPPONENT, "stand")
		return
	phase = "deal"


func _finish_set(winner: int, reason: String) -> void:
	set_results.append({"winner": winner, "reason": reason, "totals": [sides[PLAYER].total(), sides[OPPONENT].total()]})
	if winner >= 0:
		sides[winner].sets += 1
		_log("%s take%s the set." % [sides[winner].name, "" if winner == PLAYER else "s"])
		if sides[winner].sets >= SETS_TO_WIN:
			match_winner = winner
			phase = "match_over"
			_log("%s win%s the match." % [sides[winner].name, "" if winner == PLAYER else "s"])
			return
	elif set_results.size() >= MAX_SETS:
		# Practically unreachable; settle on sets won so far (player keeps ties).
		match_winner = PLAYER if sides[PLAYER].sets >= sides[OPPONENT].sets else OPPONENT
		phase = "match_over"
		return
	phase = "set_over"


## Player p concedes. Ends the match at once.
func forfeit(p: int) -> void:
	if phase == "match_over":
		return
	match_winner = 1 - p
	phase = "match_over"
	set_results.append({"winner": 1 - p, "reason": "forfeit", "totals": [sides[PLAYER].total(), sides[OPPONENT].total()]})
	_log("%s fold%s." % [sides[p].name, "" if p == PLAYER else "s"])


# ------------------------------------------------------------ queries
func total(p: int) -> int:
	return sides[p].total()


func is_over() -> bool:
	return phase == "match_over"


func last_set() -> Dictionary:
	return set_results[set_results.size() - 1] if not set_results.is_empty() else {}


## Chance that player p busts on the next main-deck card (counting the cards
## still in the deck, which is what a careful player tracks from the tables).
func bust_chance(p: int) -> float:
	if deck.is_empty():
		return 0.0
	var room := TARGET - sides[p].total()
	var bad := 0
	for v in deck:
		if v > room:
			bad += 1
	return float(bad) / float(deck.size())


func _log(s: String) -> void:
	log_lines.append(s)
	if log_lines.size() > 60:
		log_lines.pop_front()


# ------------------------------------------------------------ opponent AI
## Decides the active player's move after their deal without changing
## anything: {"shard": hand index or -1, "sign": 1|-1, "stand": bool}.
func ai_decide() -> Dictionary:
	var p := active
	var me := sides[p]
	var foe := sides[1 - p]
	var t := me.total()
	var n := me.table.size()
	var opts: Array[Dictionary] = []
	if not me.played_shard:
		for i in me.hand.size():
			for sg in signs_for(me.hand[i]):
				if can_play(p, i, sg) == "":
					var dv := shard_value(p, me.hand[i], sg)
					opts.append({"shard": i, "sign": sg, "total": t + dv, "delta": dv})
	# 1. Over twenty: rescue with the shard that leaves the best legal total.
	if t > TARGET:
		var fix := _best_opt(opts, -99, TARGET)
		if fix.is_empty():
			return {"shard": -1, "sign": 1, "stand": false}
		return {"shard": fix["shard"], "sign": fix["sign"], "stand": _stand_after(p, int(fix["total"]))}
	# 2. Eight cards down: any shard that keeps us legal fills the table.
	if n == TABLE_MAX - 1:
		var fill := _best_opt(opts, -99, TARGET)
		if not fill.is_empty():
			return {"shard": fill["shard"], "sign": fill["sign"], "stand": false}
	# 3. The other player has stood: beat their total or keep drawing.
	if foe.standing:
		var ft := foe.total()
		if t > ft:
			return {"shard": -1, "sign": 1, "stand": true}
		var beat := _best_opt(opts, ft + 1, TARGET)
		if not beat.is_empty():
			return {"shard": beat["shard"], "sign": beat["sign"], "stand": true}
		if t == ft and t >= 17:
			return {"shard": -1, "sign": 1, "stand": true}
		return {"shard": -1, "sign": 1, "stand": false}
	if t == TARGET:
		return {"shard": -1, "sign": 1, "stand": true}
	# 4. A shard that lands exactly on twenty from a strong position.
	if t >= 14:
		var hit := _best_opt(opts, TARGET, TARGET)
		if not hit.is_empty():
			return {"shard": hit["shard"], "sign": hit["sign"], "stand": true}
	# 5. Stand on a good total, or when the next card is too likely to bust
	# and there is nothing in hand to pull it back.
	if t >= AI_STAND_AT:
		return {"shard": -1, "sign": 1, "stand": true}
	if t >= 15 and bust_chance(p) >= AI_RISK and not _has_rescue(p):
		return {"shard": -1, "sign": 1, "stand": true}
	return {"shard": -1, "sign": 1, "stand": false}


## Highest-total option within [lo, hi]; ties keep the smaller shard.
func _best_opt(opts: Array[Dictionary], lo: int, hi: int) -> Dictionary:
	var best: Dictionary = {}
	for o in opts:
		var ot := int(o["total"])
		if ot < lo or ot > hi:
			continue
		if best.is_empty() or ot > int(best["total"]) or (ot == int(best["total"]) and absi(int(o["delta"])) < absi(int(best["delta"]))):
			best = o
	return best


func _stand_after(p: int, t: int) -> bool:
	var foe := sides[1 - p]
	if foe.standing:
		return t > foe.total() or (t == foe.total() and t >= 17)
	return t >= AI_STAND_AT - 1


## True when the hand holds something that can take back at least 3.
func _has_rescue(p: int) -> bool:
	for sh in sides[p].hand:
		var k := String(sh["kind"])
		if k == "minus" and int(sh["value"]) >= 3:
			return true
		if k == "null" or (k == "swing" and int(sh["value"]) >= 2):
			return true
	return false


## Plays one whole AI turn for the active player (deal, shard, end/stand).
## Returns what happened: {"dealt", "shard", "error", "stood"}.
func ai_turn() -> Dictionary:
	var out := {"dealt": 0, "shard": "", "error": "", "stood": false}
	if phase == "deal":
		out["dealt"] = deal()
	if phase != "act":
		return out
	var dec := ai_decide()
	if int(dec["shard"]) >= 0:
		var lbl := label(sides[active].hand[int(dec["shard"])])
		var err := play_shard(int(dec["shard"]), int(dec["sign"]))
		out["error"] = err
		if err == "":
			out["shard"] = lbl
	out["stood"] = bool(dec["stand"])
	if bool(dec["stand"]):
		stand()
	else:
		end_turn()
	return out
