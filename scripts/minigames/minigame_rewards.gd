class_name MinigameRewards
extends RefCounted
## Everything a minigame is allowed to change in the GameState: wagers,
## prizes, one-time XP, story flags and the per-game records kept in
## GameState.minigames. The UI calls these; practice runs never do, which is
## what guarantees practice changes nothing. All credit movements go through
## an Inventory transaction, so a failed step changes nothing.

const SHARDS_WAGERS: Array[int] = [0, 10, 25, 50]
const SHARDS_FIRST_WIN_XP := 50

## Slipstream par times in seconds (three laps). Assisted runs drive slower,
## so they race against a proportionally slower par.
const SLIPSTREAM_PAR := 50.0
const SLIPSTREAM_PRIZE := 75
const SLIPSTREAM_XP := 40


## The record dictionary for one game, created with defaults on first use.
static func record(st: GameState, id: String) -> Dictionary:
	if not st.minigames.has(id) or typeof(st.minigames[id]) != TYPE_DICTIONARY:
		st.minigames[id] = {}
	var r: Dictionary = st.minigames[id]
	match id:
		"shards":
			for k in ["wins", "losses", "matches", "net"]:
				if not r.has(k):
					r[k] = 0
		"slipstream":
			for k in ["runs", "best"]:
				if not r.has(k):
					r[k] = 0
		"turret":
			if not r.has("attempts"):
				r["attempts"] = 0
	return r


# ------------------------------------------------------------ Shards
## Wagers the player can afford right now.
static func shards_wager_options(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for w in SHARDS_WAGERS:
		if w <= st.inventory.credits:
			out.append(w)
	return out


## Puts the wager in escrow when the match starts. Returns
## {"ok", "reason", "ticket"}; the ticket is handed back to shards_settle.
## A rejected wager changes nothing.
static func shards_stake(st: GameState, wager: int) -> Dictionary:
	if not SHARDS_WAGERS.has(wager):
		return {"ok": false, "reason": "Brann only plays for 0, 10, 25 or 50 credits.", "ticket": {}}
	if wager > st.inventory.credits:
		return {"ok": false, "reason": "You don't have %d credits." % wager, "ticket": {}}
	if wager > 0:
		var tx := st.inventory.tx().credits_delta(-wager)
		if not tx.commit():
			return {"ok": false, "reason": tx.error, "ticket": {}}
	return {"ok": true, "reason": "", "ticket": {"game": "shards", "wager": wager, "settled": false}}


## Settles a staked match exactly once. A win returns the stake plus an equal
## amount from Brann; a loss (or forfeit) leaves the stake with him. The first
## match ever won also grants one-time XP and sets the flag shards_won.
## Returns {"ok", "reason", "payout", "net", "xp", "first_win"}.
static func shards_settle(st: GameState, ticket: Dictionary, won: bool) -> Dictionary:
	var out := {"ok": false, "reason": "", "payout": 0, "net": 0, "xp": 0, "first_win": false}
	if ticket.is_empty() or String(ticket.get("game", "")) != "shards":
		out["reason"] = "No wager on the table."
		return out
	if bool(ticket.get("settled", false)):
		out["reason"] = "Already settled."
		return out
	var wager := int(ticket.get("wager", 0))
	if won and wager > 0:
		var tx := st.inventory.tx().credits_delta(wager * 2)
		if not tx.commit():
			out["reason"] = tx.error
			return out
		out["payout"] = wager * 2
	ticket["settled"] = true
	var r := record(st, "shards")
	r["matches"] = int(r["matches"]) + 1
	var net := wager if won else -wager
	r["net"] = int(r["net"]) + net
	out["net"] = net
	if won:
		r["wins"] = int(r["wins"]) + 1
		out["first_win"] = not st.has_flag("shards_won")
		out["xp"] = st.grant_xp(SHARDS_FIRST_WIN_XP, "shards_first_win", "Beat Brann at Shards")
		st.set_flag("shards_won", true)
	else:
		r["losses"] = int(r["losses"]) + 1
	out["ok"] = true
	return out


# ------------------------------------------------------------ Slipstream
static func slipstream_par(assisted: bool) -> float:
	return snappedf(SLIPSTREAM_PAR / SlipstreamSim.ASSIST_SPEED, 0.1) if assisted else SLIPSTREAM_PAR


## Records a finished run: best time (and its ghost), run count and the
## one-time par prize (credits + XP). Returns
## {"time", "best", "new_best", "par", "beat_par", "prize", "xp"}.
static func slipstream_finish(st: GameState, time: float, assisted: bool, ghost: Array = []) -> Dictionary:
	var r := record(st, "slipstream")
	var t := snappedf(time, 0.01)
	r["runs"] = int(r["runs"]) + 1
	var best := float(r.get("best", 0))
	var new_best := best <= 0.0 or t < best
	if new_best:
		r["best"] = t
		r["best_assisted"] = assisted
		r["ghost"] = ghost.duplicate()
	var par := slipstream_par(assisted)
	var out := {"time": t, "best": float(r["best"]), "new_best": new_best, "par": par, "beat_par": t <= par, "prize": 0, "xp": 0}
	if t <= par and not st.claimed("slipstream_par"):
		var tx := st.inventory.tx().credits_delta(SLIPSTREAM_PRIZE)
		if tx.commit():
			st.claim("slipstream_par")
			out["prize"] = SLIPSTREAM_PRIZE
		out["xp"] = st.grant_xp(SLIPSTREAM_XP, "slipstream_par", "Beat par on the Slipstream sim")
		r["par_beaten"] = true
	return out


# ------------------------------------------------------------ Turret
## Records the escape's turret result for LAUNCH_AFTER to read. method is
## "manual", "assisted" or "autopilot". XP comes from that dialogue.
static func turret_finish(st: GameState, result: String, method: String, hull: int = 0) -> void:
	var r := record(st, "turret")
	r["attempts"] = int(r["attempts"]) + 1
	r["result"] = result
	r["method"] = method
	r["hull"] = hull
	st.set_flag("turret_result", result)
