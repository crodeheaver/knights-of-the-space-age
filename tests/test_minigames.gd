extends TestCase
## Minigames: Shards rules and AI, wager settlement, Slipstream and Turret
## simulations, the one-time rewards, practice isolation, and the panel
## lifecycle (modal held and released, turret hand-off to launch_after).

const P := ShardsRules.PLAYER
const O := ShardsRules.OPPONENT


## Stand-ins for main.gd and World so panels can be driven without a world.
class StubWorld:
	extends Node
	var modal: Dictionary = {}
	var started: Array[String] = []

	func set_modal(key: String, on: bool) -> void:
		if on:
			modal[key] = true
		else:
			modal.erase(key)

	func start_dialogue(did: String, _npc: Node = null, _npc_id: String = "", _ctx: Dictionary = {}) -> bool:
		started.append(did)
		return true


class StubMain:
	extends Node
	var panels: Array = []

	func push_panel(p: Control) -> void:
		panels.append(p)
		add_child(p)

	func close_panel(p: Control) -> void:
		panels.erase(p)
		if is_instance_valid(p):
			p.queue_free()


func _rules(deal: Array, player_hand: Array = ["+1", "+2", "+3", "+4"], opp_hand: Array = ["+2", "+3", "-2", "-3"]) -> ShardsRules:
	var r := ShardsRules.new(Dice.new(3))
	r.start_match()
	r.set_hand(P, player_hand)
	r.set_hand(O, opp_hand)
	r.stack_deck(deal)
	return r


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int) -> void:
	for i in n:
		await _tree().process_frame


## What practice must never touch.
func _snap(st: GameState) -> String:
	var d := st.to_dict()
	return JSON.stringify({"flags": d["flags"], "credits": d["inventory"]["credits"], "stacks": d["inventory"]["stacks"], "minigames": d["minigames"], "ledger": d["ledger"], "dice": d["dice"], "xp": st.player().xp, "stats": d["stats"]})


# ------------------------------------------------------------ Shards rules
func test_shards_bust_and_rescue() -> void:
	var r := _rules([10, 5, 9, 4, 8])
	assert_eq(r.active, P, "player opens set 1")
	assert_eq(r.deal(), 10)
	assert_eq(r.end_turn(), "")
	assert_eq(r.active, O)
	r.deal()
	r.end_turn()
	r.deal()
	assert_eq(r.total(P), 19)
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	assert_eq(r.total(P), 27)
	r.end_turn()
	assert_eq(r.phase, "set_over", "over twenty at end of turn ends the set")
	assert_eq(int(r.last_set()["winner"]), O)
	assert_eq(String(r.last_set()["reason"]), "bust")
	assert_eq(r.sides[O].sets, 1)
	# Rescue: over twenty mid-turn is fine if a shard brings it back.
	var r2 := _rules([10, 5, 9, 4, 5], ["-4", "+1", "+2", "+3"])
	for i in 4:
		r2.deal()
		r2.end_turn()
	r2.deal()
	assert_eq(r2.total(P), 24)
	assert_eq(r2.play_shard(0), "")
	assert_eq(r2.total(P), 20)
	assert_ne(r2.play_shard(0), "", "one shard per turn")
	r2.end_turn()
	assert_eq(r2.phase, "deal", "no bust after the rescue")
	assert_true(r2.sides[P].standing, "exactly twenty stands automatically")
	assert_eq(r2.active, O)


func test_shards_stand_compare_and_tie() -> void:
	var r := _rules([10, 10, 8, 7])
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	assert_eq(r.stand(), "")
	assert_true(r.sides[P].standing)
	assert_eq(r.active, O, "the other player keeps taking turns")
	r.deal()
	assert_eq(r.total(O), 17)
	r.stand()
	assert_eq(r.phase, "set_over")
	assert_eq(int(r.last_set()["winner"]), P, "18 beats 17")
	assert_eq(r.sides[P].sets, 1)
	# Tie: replayed, no set awarded, and the next set alternates the opener.
	var t := _rules([10, 10, 8, 8])
	t.deal()
	t.end_turn()
	t.deal()
	t.end_turn()
	t.deal()
	t.stand()
	t.deal()
	t.stand()
	assert_eq(t.phase, "set_over")
	assert_eq(String(t.last_set()["reason"]), "tie")
	assert_eq(t.sides[P].sets + t.sides[O].sets, 0, "a tie awards nothing")
	assert_true(t.next_set())
	assert_eq(t.set_index, 1)
	assert_eq(t.active, O, "sets alternate who opens")
	assert_eq(t.sides[P].table.size(), 0, "tables cleared")


func test_shards_nine_cards_win_outright() -> void:
	var r := _rules([1, 10, 1, 8, 2, 1, 2, 1, 2, 2, 2])
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	assert_eq(r.total(O), 18)
	r.stand()
	for i in 6:
		assert_eq(r.active, P, "player keeps drawing while Brann stands")
		r.deal()
		r.end_turn()
	r.deal()
	assert_eq(r.sides[P].table.size(), 9)
	assert_eq(r.total(P), 14)
	r.end_turn()
	assert_eq(r.phase, "set_over")
	assert_eq(int(r.last_set()["winner"]), P, "nine cards without busting beats Brann's 18")
	assert_eq(String(r.last_set()["reason"]), "nine")


func test_shards_match_is_best_of_three() -> void:
	# Set 1 (you open): you stand on 19, Brann draws past twenty.
	var r := _rules([10, 10, 9, 5, 10])
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	r.stand()
	r.deal()
	r.end_turn()
	assert_eq(r.active, O, "Brann keeps drawing against a standing 19")
	r.deal()
	r.end_turn()
	assert_eq(r.phase, "set_over")
	assert_eq(r.sides[P].sets, 1)
	assert_true(r.next_set())
	# Set 2 (Brann opens): same story.
	r.stack_deck([10, 10, 5, 9, 10])
	assert_eq(r.active, O)
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	r.end_turn()
	r.deal()
	r.stand()
	r.deal()
	r.end_turn()
	assert_eq(r.phase, "match_over", "first to two sets")
	assert_eq(r.match_winner, P)
	assert_eq(r.deal(), 0, "nothing is dealt after the match")
	assert_false(r.next_set())
	# Swing, echo and null values.
	var s2 := _rules([7], ["~2", "E", "N", "+1"])
	s2.deal()
	assert_eq(s2.shard_value(P, s2.sides[P].hand[0], -1), -2)
	assert_eq(s2.shard_value(P, s2.sides[P].hand[1]), 7, "echo repeats the last dealt card")
	assert_eq(s2.shard_value(P, s2.sides[P].hand[2]), -7, "null cancels it")
	assert_ne(s2.can_play(P, 3, -1), "", "plain shards have no sign choice")
	assert_eq(s2.play_shard(1), "")
	assert_eq(s2.total(P), 14)
	assert_eq(s2.sides[P].hand.size(), 3, "spent shards leave the hand")


func test_shards_ai_never_plays_illegally() -> void:
	var wins := [0, 0]
	var shards_played := 0
	for seed_ in 150:
		var r := ShardsRules.new(Dice.new(1000 + seed_))
		r.start_match()
		var guard := 0
		while not r.is_over() and guard < 3000:
			guard += 1
			if r.phase == "set_over":
				r.next_set()
				continue
			var who := r.active
			var hand_before := r.sides[who].hand.size()
			var table_before := r.sides[who].table.size()
			# The AI may not act out of turn.
			assert_ne(r.can_play(1 - who, 0), "", "out-of-turn play refused")
			var out := r.ai_turn()
			assert_eq(String(out["error"]), "", "AI shard legal (seed %d)" % seed_)
			var used := hand_before - r.sides[who].hand.size()
			assert_true(used == 0 or used == 1, "at most one shard per turn")
			if used == 1:
				shards_played += 1
			if r.phase == "deal" or r.phase == "act":
				assert_eq(r.sides[who].table.size(), table_before + 1 + used, "one deal plus the shard")
		assert_true(r.is_over(), "match finished (seed %d)" % seed_)
		wins[r.match_winner] += 1
	assert_true(shards_played > 100, "the AI uses its shards (%d)" % shards_played)
	assert_true(wins[0] > 20 and wins[1] > 20, "AI vs AI is roughly balanced: %s" % str(wins))


func test_shards_ai_heuristics() -> void:
	var opp := ["+2", "-1", "-4", "-6"]
	var mine := ["+1", "+2", "+3", "+4"]
	# Against your standing 19, Brann on 18 plays +2 for twenty and stands.
	var a := _rules([10, 10, 9, 8], mine, opp)
	a.deal()
	a.end_turn()
	a.deal()
	a.end_turn()
	a.deal()
	a.stand()
	a.deal()
	assert_eq(a.total(O), 18)
	var dec := a.ai_decide()
	assert_eq(int(dec["shard"]), 0)
	assert_true(bool(dec["stand"]))
	assert_eq(String(a.ai_turn()["error"]), "")
	assert_eq(a.phase, "set_over")
	assert_eq(int(a.last_set()["winner"]), O, "20 beats 19")
	# Stands on twenty without spending a shard.
	var c := _rules([10, 10, 5, 10], mine, opp)
	for i in 3:
		c.deal()
		c.end_turn()
	c.deal()
	assert_eq(c.total(O), 20)
	var dc := c.ai_decide()
	assert_true(bool(dc["stand"]))
	assert_eq(int(dc["shard"]), -1)
	# Over twenty: the shard that leaves the best legal total (−4 for 19,
	# not −1 for 22), then keeps drawing because 19 still loses to your 20.
	var d := _rules([10, 10, 5, 6, 5, 7], mine, opp)
	for i in 5:
		d.deal()
		d.end_turn()
	assert_true(d.sides[P].standing, "you reached twenty")
	d.deal()
	assert_eq(d.total(O), 23)
	var dd := d.ai_decide()
	assert_eq(int(dd["shard"]), 2)
	assert_false(bool(dd["stand"]))
	d.ai_turn()
	assert_eq(d.total(O), 19)
	assert_eq(d.phase, "deal", "no bust")
	# Holds on 18 when no shard makes exactly twenty.
	var e := _rules([10, 10, 3, 8], mine, ["+5", "-1", "-4", "-6"])
	for i in 3:
		e.deal()
		e.end_turn()
	e.deal()
	assert_eq(e.total(O), 18)
	var de := e.ai_decide()
	assert_true(bool(de["stand"]))
	assert_eq(int(de["shard"]), -1)
	# A legal ninth card wins outright, so Brann spends a shard to fill the table.
	var f := _rules([1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3], mine, ["+2", "-1", "-4", "-6"])
	for i in 15:
		f.deal()
		f.end_turn()
	f.deal()
	assert_eq(f.sides[O].table.size(), 8)
	var df := f.ai_decide()
	assert_true(int(df["shard"]) >= 0, "plays a shard as the ninth card")
	f.ai_turn()
	assert_eq(int(f.last_set()["winner"]), O)
	assert_eq(String(f.last_set()["reason"]), "nine")


# ------------------------------------------------------------ wagers
func test_shards_wager_settlement_is_atomic() -> void:
	var st := fresh_state("vanguard")
	st.inventory.credits = 30
	var expect: Array[int] = [0, 10, 25]
	assert_eq(MinigameRewards.shards_wager_options(st), expect)
	var r := MinigameRewards.shards_stake(st, 50)
	assert_false(bool(r["ok"]), "cannot wager more than you have")
	assert_eq(st.inventory.credits, 30)
	assert_false(bool(MinigameRewards.shards_stake(st, 7)["ok"]), "only the table's stakes")
	assert_eq(st.inventory.credits, 30)
	var xp0 := st.player().xp
	r = MinigameRewards.shards_stake(st, 25)
	assert_true(bool(r["ok"]))
	assert_eq(st.inventory.credits, 5, "stake held in escrow")
	var ticket: Dictionary = r["ticket"]
	var s := MinigameRewards.shards_settle(st, ticket, true)
	assert_true(bool(s["ok"]))
	assert_eq(st.inventory.credits, 55, "win pays the stake back plus the same again")
	assert_eq(int(s["xp"]), MinigameRewards.SHARDS_FIRST_WIN_XP)
	assert_eq(st.player().xp, xp0 + MinigameRewards.SHARDS_FIRST_WIN_XP)
	assert_true(st.has_flag("shards_won"))
	assert_false(bool(MinigameRewards.shards_settle(st, ticket, true)["ok"]), "a ticket pays once")
	assert_eq(st.inventory.credits, 55)
	# A loss deducts once (the stake), and settling again changes nothing.
	var t2: Dictionary = MinigameRewards.shards_stake(st, 10)["ticket"]
	assert_eq(st.inventory.credits, 45)
	assert_true(bool(MinigameRewards.shards_settle(st, t2, false)["ok"]))
	MinigameRewards.shards_settle(st, t2, false)
	MinigameRewards.shards_settle(st, t2, true)
	assert_eq(st.inventory.credits, 45, "loss deducted exactly once, no late payout")
	var rec: Dictionary = st.minigames["shards"]
	assert_eq(int(rec["wins"]), 1)
	assert_eq(int(rec["losses"]), 1)
	assert_eq(int(rec["matches"]), 2)
	assert_eq(int(rec["net"]), 15)
	# Broke: only the free table.
	st.inventory.credits = 0
	var only_free: Array[int] = [0]
	assert_eq(MinigameRewards.shards_wager_options(st), only_free)
	assert_true(bool(MinigameRewards.shards_stake(st, 0)["ok"]))
	assert_eq(st.inventory.credits, 0)
	# Save, reload, win again: the first-win XP is not granted twice.
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	Game.set_state(loaded)
	var xp1 := loaded.player().xp
	var t3: Dictionary = MinigameRewards.shards_stake(loaded, 0)["ticket"]
	var s3 := MinigameRewards.shards_settle(loaded, t3, true)
	assert_eq(int(s3["xp"]), 0)
	assert_eq(loaded.player().xp, xp1, "first-win XP survives a reload as claimed")
	assert_eq(int((loaded.minigames["shards"] as Dictionary)["wins"]), 2)


# ------------------------------------------------------------ Slipstream
func _drive(sim: SlipstreamSim, mode: String, cap: float = 400.0) -> void:
	var n := 0
	while not sim.finished and n < int(cap * 60.0):
		n += 1
		match mode:
			"auto":
				sim.step(1.0 / 60.0, {"accel": true, "steer": sim.auto_steer()})
			"accel":
				sim.step(1.0 / 60.0, {"accel": true})
			_:
				sim.step(1.0 / 60.0, {})


func test_slipstream_scripted_run_records_best() -> void:
	var st := fresh_state("vanguard")
	var sim := SlipstreamSim.new(false)
	_drive(sim, "auto")
	assert_true(sim.finished)
	assert_eq(sim.lap(), SlipstreamSim.LAPS)
	assert_lte(sim.finish_time, MinigameRewards.slipstream_par(false), "a clean line beats par")
	var again := SlipstreamSim.new(false)
	_drive(again, "auto")
	assert_eq(again.finish_time, sim.finish_time, "deterministic: same input, same time")
	var credits := st.inventory.credits
	var xp := st.player().xp
	var res := MinigameRewards.slipstream_finish(st, sim.finish_time, false, sim.ghost)
	var rec: Dictionary = st.minigames["slipstream"]
	assert_eq(float(rec["best"]), snappedf(sim.finish_time, 0.01), "best time saved")
	assert_true(bool(res["new_best"]))
	assert_true(bool(res["beat_par"]))
	assert_false((rec["ghost"] as Array).is_empty(), "ghost of the best run saved")
	assert_eq(st.inventory.credits, credits + MinigameRewards.SLIPSTREAM_PRIZE)
	assert_eq(st.player().xp, xp + MinigameRewards.SLIPSTREAM_XP)
	# A slower run keeps the record; another par run pays nothing more.
	var slow := MinigameRewards.slipstream_finish(st, sim.finish_time + 20.0, false)
	assert_false(bool(slow["new_best"]))
	assert_eq(float(rec["best"]), snappedf(sim.finish_time, 0.01))
	var par2 := MinigameRewards.slipstream_finish(st, sim.finish_time - 0.5, false, sim.ghost)
	assert_true(bool(par2["new_best"]))
	assert_eq(int(par2["prize"]), 0, "par prize only once")
	assert_eq(int(par2["xp"]), 0)
	assert_eq(st.inventory.credits, credits + MinigameRewards.SLIPSTREAM_PRIZE)
	assert_eq(int(rec["runs"]), 3)
	# Survives a save round trip, and still pays only once.
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	var p3 := MinigameRewards.slipstream_finish(loaded, 30.0, false)
	assert_eq(int(p3["prize"]), 0)
	assert_eq(float((loaded.minigames["slipstream"] as Dictionary)["best"]), 30.0)
	var g := SlipstreamSim.ghost_at(rec["ghost"], 10.0)
	assert_true(g.x > 0.0, "ghost replays a position")


func test_slipstream_collisions_slow_but_never_fail() -> void:
	var sim := SlipstreamSim.new(false)
	_drive(sim, "idle")
	assert_true(sim.finished, "an idle sled still finishes")
	assert_true(sim.hits > 0, "and hits things on the way")
	assert_true(sim.finish_time > MinigameRewards.slipstream_par(false), "collisions cost time: %.1f" % sim.finish_time)
	var acc := SlipstreamSim.new(false)
	_drive(acc, "accel")
	assert_true(acc.finish_time > MinigameRewards.slipstream_par(false), "throttle alone does not beat par")
	# Assisted: steers itself, lower top speed, its own par.
	var asim := SlipstreamSim.new(true)
	_drive(asim, "accel")
	assert_true(asim.finished)
	assert_eq(asim.hits, 0, "assisted driving avoids the obstacles")
	assert_lte(asim.finish_time, MinigameRewards.slipstream_par(true), "holding throttle beats the assisted par")
	assert_true(MinigameRewards.slipstream_par(true) > MinigameRewards.slipstream_par(false))
	var st := fresh_state("vanguard")
	var r := MinigameRewards.slipstream_finish(st, asim.finish_time, true, asim.ghost)
	assert_true(bool(r["beat_par"]))
	assert_true(bool((st.minigames["slipstream"] as Dictionary)["best_assisted"]))


# ------------------------------------------------------------ Turret
func _fight(sim: TurretSim, aim: bool, cap: float = 200.0) -> void:
	var n := 0
	while sim.result == "" and n < int(cap * 60.0):
		n += 1
		sim.step(1.0 / 60.0, {"aim": sim.aim_hint(), "fire": true} if aim else {})


func test_turret_perfect_aim_wins_and_sets_flag() -> void:
	var st := fresh_state("vanguard")
	for diff in ["story", "standard", "hard"]:
		var sim := TurretSim.new(11, diff)
		_fight(sim, true)
		assert_eq(sim.result, "player_win", diff)
		assert_eq(sim.alive_count(), 0)
		assert_true(sim.hull > TurretSim.HULL_FAIL)
	var sim2 := TurretSim.new(11, "standard")
	_fight(sim2, true)
	MinigameRewards.turret_finish(st, sim2.result, "manual", int(sim2.hull))
	assert_eq(st.flag("turret_result"), "player_win")
	assert_eq(String((st.minigames["turret"] as Dictionary)["method"]), "manual")
	assert_eq(TurretSim.new(3, "story").drones.size(), 2)
	assert_eq(TurretSim.new(3, "hard", false, 1).drones.size(), 4)


func test_turret_no_input_loses() -> void:
	for diff in ["story", "standard", "hard"]:
		var sim := TurretSim.new(5, diff)
		_fight(sim, false)
		assert_eq(sim.result, "player_loss", diff)
		assert_true(sim.reason == "hull" or sim.reason == "time")
	var st := fresh_state("vanguard")
	var sim2 := TurretSim.new(5, "standard")
	_fight(sim2, false)
	MinigameRewards.turret_finish(st, sim2.result, "manual")
	assert_eq(st.flag("turret_result"), "player_loss")
	# Story gives more time and softer hits than standard.
	assert_true(TurretSim.new(5, "story").time_limit > TurretSim.new(5, "standard").time_limit)


func test_turret_assisted_slow_motion_and_auto_aim() -> void:
	var a := TurretSim.new(9, "standard", true)
	var b := TurretSim.new(9, "standard", false)
	for i in 60:
		a.step(1.0 / 60.0, {})
		b.step(1.0 / 60.0, {})
	assert_eq(a.time, 0.5, "assisted runs at half speed")
	assert_eq(b.time, 1.0)
	# Bring a drone fully in, then fire just off its edge: auto-aim lands it.
	for i in 240:
		a.step(1.0 / 60.0, {})
	var dr: TurretSim.Drone = a.drones[0]
	var off := dr.pos + Vector2(dr.radius() + 40.0, 0)
	a.step(1.0 / 60.0, {"aim": off, "fire": true})
	assert_eq(a.hits, 1, "assisted shot pulled onto the drone")
	var c := TurretSim.new(9, "standard", false)
	for i in 120:
		c.step(1.0 / 60.0, {})
	var dc: TurretSim.Drone = c.drones[0]
	c.step(1.0 / 60.0, {"aim": dc.pos + Vector2(dc.radius() + 40.0, 0), "fire": true})
	assert_eq(c.hits, 0, "unassisted, the same shot misses")


func test_turret_autopilot_seeded_roll() -> void:
	var st := fresh_state("vanguard")
	var r1 := TurretSim.autopilot(st, Dice.new(77))
	var r2 := TurretSim.autopilot(st, Dice.new(77))
	assert_eq(r1, r2, "same seed, same outcome")
	var best := st.player().skill_total("awareness")
	assert_eq(int(r1["bonus"]), best)
	assert_eq(int(r1["dc"]), TurretSim.AUTOPILOT_DC)
	assert_eq(String(r1["result"]), "player_win" if int(r1["natural"]) + best >= TurretSim.AUTOPILOT_DC else "player_loss")
	var hi := Dice.new(1)
	hi.force([19])
	assert_eq(String(TurretSim.autopilot(st, hi)["result"]), "player_win" if 19 + best >= 12 else "player_loss")
	var lo := Dice.new(1)
	lo.force([1])
	assert_eq(String(TurretSim.autopilot(st, lo)["result"]), "player_loss" if 1 + best < 12 else "player_win")
	assert_eq(int(TurretSim.autopilot(st, Dice.new(2), "story")["dc"]), TurretSim.AUTOPILOT_DC - 2)
	# No party (main-menu practice): a plain d20.
	var empty := GameState.new()
	var r3 := TurretSim.autopilot(empty, Dice.new(4))
	assert_eq(int(r3["bonus"]), 0)
	MinigameRewards.turret_finish(st, String(r1["result"]), "autopilot")
	assert_eq(st.flag("turret_result"), String(r1["result"]))


# ------------------------------------------------------------ practice & panels
func test_practice_changes_no_state() -> void:
	var st := fresh_state("vanguard")
	Game.world = null
	var before := _snap(st)
	var finished0 := Events.count("minigame_finished")
	var parent := Control.new()
	_tree().root.add_child(parent)
	# Shards: play a whole match through the panel's rules.
	Minigames.open_practice(parent, "shards")
	var sp: ShardsPanel = parent.get_child(parent.get_child_count() - 1)
	assert_true(sp.practice)
	await _frames(2)
	sp._start_match()
	assert_eq(sp.stage, "play")
	await _frames(3)
	var guard := 0
	while not sp.rules.is_over() and guard < 3000:
		guard += 1
		if sp.rules.phase == "set_over":
			sp.rules.next_set()
		else:
			sp.rules.ai_turn()
	sp._refresh()
	sp._on_match_over()
	await _frames(2)
	sp.close_now()
	# Slipstream: assisted race to the finish, drawn for a few frames.
	Minigames.open_practice(parent, "slipstream")
	var lp: SlipstreamPanel = parent.get_child(parent.get_child_count() - 1)
	await _frames(2)
	lp.assisted = true
	lp._start_race()
	var drawn := [0]
	lp.view.draw.connect(func() -> void: drawn[0] += 1)
	lp.countdown = 0.01
	await _frames(4)
	assert_true(int(drawn[0]) > 0, "the track view draws")
	while not lp.sim.finished:
		lp.sim.step(1.0 / 60.0, {"accel": true})
	await _frames(3)
	assert_eq(lp.stage, "done")
	lp.close_now()
	# Turret: a drill fight and the autopilot.
	Minigames.open_practice(parent, "turret_practice")
	var tp: TurretPanel = parent.get_child(parent.get_child_count() - 1)
	await _frames(2)
	assert_eq(tp.sim, null)
	tp._start_fight()
	var tdrawn := [0]
	tp.view.draw.connect(func() -> void: tdrawn[0] += 1)
	await _frames(3)
	assert_true(int(tdrawn[0]) > 0, "the turret view draws")
	while tp.sim.result == "":
		tp.sim.step(1.0 / 60.0, {"aim": tp.sim.aim_hint(), "fire": true})
	await _frames(3)
	assert_eq(tp.stage, "done")
	tp._show_setup()
	tp._autopilot()
	tp._resolve("player_win", "manual")
	await _frames(1)
	tp.close_now()
	await _frames(2)
	assert_eq(parent.get_child_count(), 0, "closed practice panels are freed")
	parent.queue_free()
	assert_eq(_snap(st), before, "practice changed nothing in the game state")
	assert_eq(st.flag("turret_result"), null)
	assert_true(Events.count("minigame_finished") > finished0)
	for h in Events.history:
		if String(h["name"]) == "minigame_finished":
			assert_true(bool(h["data"]["practice"]), "finished events are marked practice")


func test_open_holds_and_releases_modal() -> void:
	var st := fresh_state("vanguard")
	st.inventory.credits = 100
	var w := StubWorld.new()
	var m := StubMain.new()
	_tree().root.add_child(w)
	_tree().root.add_child(m)
	Game.world = w
	# Turret practice from the dialogue: practice rules, no flags, no follow-up.
	Minigames.open(m, "turret_practice")
	assert_eq(m.panels.size(), 1)
	var tp: TurretPanel = m.panels[0]
	await _frames(1)
	assert_true(tp.practice)
	assert_true(w.modal.has("minigame"), "modal held while open")
	tp._autopilot()
	tp._resolve("player_win", "autopilot")
	tp.on_escape()
	tp.close_now()
	await _frames(1)
	assert_false(w.modal.has("minigame"), "modal released on close")
	assert_eq(m.panels.size(), 0)
	assert_eq(st.flag("turret_result"), null, "practice sets no flag")
	assert_true(w.started.is_empty(), "practice never starts launch_after")
	# Shards: Esc before the deal costs nothing; folding a started match
	# loses the stake once and releases the modal.
	Minigames.open(m, "shards")
	var sp: ShardsPanel = m.panels[0]
	await _frames(1)
	sp.on_escape()
	await _frames(1)
	assert_eq(st.inventory.credits, 100, "leaving before the deal is free")
	assert_false(w.modal.has("minigame"))
	Minigames.open(m, "shards")
	sp = m.panels[0]
	await _frames(1)
	sp.wager = 25
	sp._start_match()
	assert_eq(st.inventory.credits, 75)
	sp.on_escape()
	assert_true(sp.is_paused(), "Esc asks before folding")
	assert_true(w.modal.has("minigame"))
	sp._fold()
	await _frames(1)
	assert_eq(st.inventory.credits, 75, "fold forfeits the stake, nothing more")
	assert_eq(int((st.minigames["shards"] as Dictionary)["losses"]), 1)
	assert_false(w.modal.has("minigame"), "modal released after the fold")
	# The real turret: the autopilot result is recorded and launch_after runs.
	Minigames.open(m, "turret")
	var rt: TurretPanel = m.panels[0]
	await _frames(1)
	assert_false(rt.practice)
	rt._autopilot()
	var res := String(rt.outcome["result"])
	rt._resolve(res, "autopilot")
	rt._resolve(res, "autopilot")
	await _frames(1)
	assert_eq(st.flag("turret_result"), res)
	assert_eq(w.started.size(), 1, "launch_after started exactly once")
	assert_eq(w.started[0], "launch_after")
	assert_false(w.modal.has("minigame"))
	assert_eq(int((st.minigames["turret"] as Dictionary)["attempts"]), 1)
	# Breaking off from the pause menu resolves as a loss.
	Minigames.open(m, "turret")
	var bt: TurretPanel = m.panels[0]
	await _frames(1)
	bt._start_fight()
	bt.on_escape()
	assert_true(bt.is_paused())
	bt._break_off()
	var cont: Callable = bt.overlay.get_meta("esc")
	cont.call()
	await _frames(1)
	assert_eq(st.flag("turret_result"), "player_loss")
	assert_eq(w.started.size(), 2)
	Game.world = null
	w.queue_free()
	m.queue_free()
	await _frames(1)


func test_dialogue_launch_timing() -> void:
	# Brann's "deal" line closes the conversation: the table waits for it.
	var st := fresh_state("vanguard")
	var eng := DialogueEngine.new(st)
	assert_true(eng.start("ketterick"))
	for c in eng.choices():
		if String(c["text"]).begins_with("Deal me in"):
			eng.choose(int(c["index"]))
			break
	assert_eq(eng.node_id, "deal")
	assert_true(Minigames._closing_line(eng), "the line is read before the table opens")
	# The launch's turret choice opens the turret at once (mid-conversation).
	st.set_flag("warden_neutralized", false)
	var launch := DialogueEngine.new(st)
	assert_true(launch.start("launch"))
	launch.advance()
	assert_eq(launch.node_id, "turret")
	assert_false(Minigames._closing_line(launch))
