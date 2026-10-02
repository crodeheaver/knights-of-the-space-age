class_name CombatManager
extends RefCounted
## Real-time-with-pause scheduler. Each actor acts at most once per round
## (3 s by default): after executing an action its recovery is set to the
## round length. Actors approach targets until in range/line of sight, then
## the action is resolved exactly once by ActionResolver. Per-actor round
## clocks drive damage-over-time and in-combat energy regeneration. Nothing
## here advances while the simulation is paused.

var w: World
var active := false
var round_len := 3.0
var announced_empty := {}
var combat_time := 0.0


func _init(world: World) -> void:
	w = world
	round_len = float(DB.progression.get("round_seconds", 3.0))


func step(dt: float) -> void:
	var alert := w.alert_hostile_count()
	if not active and alert > 0:
		start()
	if active:
		combat_time += dt
	for a in w.sorted_actors():
		_tick(a, dt)
	if active and w.alert_hostile_count() == 0:
		end()


func start() -> void:
	active = true
	combat_time = 0.0
	announced_empty.clear()
	var dice: Dice = Game.state.dice
	for a in w.sorted_actors():
		if a.sheet.dead:
			continue
		a.in_combat = true
		# Stable initiative stagger: higher DEX acts sooner in the first round.
		var init: int = dice.d20() + int(a.sheet.amod("dex"))
		a.recovery = clampf(1.6 - init * 0.07, 0.0, 1.6)
		a.round_clock = fmod(float(a.uid.hash() % 1000) / 1000.0 * round_len, round_len)
	Events.post("combat_started", {})
	Events.log_combat("— Combat begins —", "", "system")
	# Auto-attack: the controlled character starts with a basic attack queued
	# (visible and cancelable while the combat-start pause is up).
	if w.controlled() != null and w.auto_queue_attack(w.controlled()):
		var aq: Dictionary = w.controlled().queue.front()
		Events.log_combat("%s readies a basic attack on %s (auto-attack; queue anything to replace it)." % [w.controlled().sheet.display_name, (w.actors[String(aq["target"])] as Actor).sheet.display_name], "", "system")
	if bool(Settings.get_v("autopause_combat_start")):
		w.set_paused(true, "Combat started")
	GameAudio.music("music_combat")


func end() -> void:
	active = false
	for a in w.sorted_actors():
		a.in_combat = false
		a.current = {}
		if a.role == "party":
			a.queue.clear()
	w.on_combat_ended()
	Events.post("combat_ended", {})
	Events.log_combat("— Combat ends —", "", "system")
	GameAudio.music(w.area_music())


func _tick(a: Actor, dt: float) -> void:
	var s := a.sheet
	if s.dead:
		return
	a.recovery = maxf(0.0, a.recovery - dt)
	a.round_clock += dt
	if a.round_clock >= round_len:
		a.round_clock -= round_len
		_round_boundary(a)
	if s.is_downed():
		a.current = {}
		return
	if not s.can_act():
		if not a.current.is_empty():
			a.current = {}
		return
	if s.has_status("feared"):
		_flee(a)
		return
	if a.interaction.size() > 0:
		return
	# AI-driven party members step out of known hazards before acting.
	if a.role == "party" and a.uid != Game.state.controlled and s.can_move() and not a.is_moving() \
			and w.grid.is_avoided(w.grid.cell_of(a.position)):
		var safe: Vector3 = w.safe_spot_near(a.position)
		if safe != a.position and a.move_to(safe):
			return
	if a.current.is_empty():
		if a.recovery > 0.0:
			return
		a.current = _next_action(a)
		if a.current.is_empty():
			return
	_pursue(a, dt)


func _next_action(a: Actor) -> Dictionary:
	if not a.queue.is_empty():
		return a.queue.pop_front()
	if a.role == "party":
		if a.uid == Game.state.controlled or a.sheet.behavior == "passive":
			# Never override the player steering this character.
			if a.uid == Game.state.controlled and w.player_moving(a):
				return {}
			if a.in_combat and w.valid_hostile_target(a, a.target_uid):
				return {"type": "attack", "target": a.target_uid, "auto": true}
			# Target fell and nothing is queued: keep fighting the nearest enemy
			# (unless the player asked to be paused when the queue runs dry).
			if active and a.uid == Game.state.controlled and a.in_combat and bool(Settings.get_v("auto_attack")) \
					and not bool(Settings.get_v("autopause_queue_empty")) and not a.stealth:
				var nt: Actor = w.auto_target(a)
				if nt != null:
					w.cmd_target(a, nt.uid)
					return {"type": "attack", "target": nt.uid, "auto": true}
			if active and a.uid == Game.state.controlled and bool(Settings.get_v("autopause_queue_empty")) and not announced_empty.has(a.uid):
				announced_empty[a.uid] = true
				w.set_paused(true, "%s has no queued actions" % a.sheet.display_name)
			return {}
		if not active:
			return {}
		return AIBrain.companion_action(a, w)
	if a.role == "enemy" and a.alert and active:
		return AIBrain.enemy_action(a, w)
	return {}


func _pursue(a: Actor, dt: float) -> void:
	var act := a.current
	var reason: String = w.validate_action(a, act)
	if reason != "":
		if not bool(act.get("auto", false)) and a.role == "party":
			Events.toast("%s: %s" % [a.sheet.display_name, reason], "warn")
			Events.log_combat("%s cancels %s: %s" % [a.sheet.display_name, w.action_label(act), reason], "", "warn")
		a.current = {}
		return
	var need: float = w.action_range(a, act)
	if need > 0.0:
		var tp: Vector3 = w.action_target_pos(a, act)
		var dist := a.position.distance_to(tp)
		var ranged := need > 3.0
		var los_ok := (not ranged) or w.grid.los(a.position, tp)
		if dist > need or not los_ok:
			if not a.sheet.can_move():
				if not bool(act.get("auto", false)) and a.role == "party":
					Events.toast("%s cannot reach the target." % a.sheet.display_name, "warn")
				a.current = {}
				return
			a.approach_repath -= dt
			if a.approach_repath <= 0.0 or not a.is_moving():
				a.approach_repath = 0.5
				var goal := tp
				if ranged and dist <= need:
					goal = tp
				if not a.move_to(goal):
					a.current = {}
			return
		a.stop()
		a.face_towards(tp)
	w.execute_action(a, act)
	a.current = {}
	a.recovery = round_len * (0.5 if String(act.get("type", "")) == "swap" else 1.0)


func _round_boundary(a: Actor) -> void:
	var s := a.sheet
	if s.dead or s.is_downed():
		return
	var dots := StatusRules.dot_rolls(s, Game.state.dice)
	for d in dots:
		var comp := {"amount": int(d["rolled"]), "dtype": String(d["dtype"])}
		if d["id"] == "shocked":
			comp["shock"] = true
		var res := CombatRules.apply_damage(s, [comp], {"difficulty": Game.state.difficulty})
		if int(res["dealt"]) > 0:
			w.fx.text(a.position, str(int(res["dealt"])), Color("#ff9a5a"))
			Events.log_combat("%s takes %d %s damage (%s)." % [s.display_name, int(res["dealt"]), d["dtype"], DB.status(String(d["id"])).get("name", d["id"])], "", "damage")
		if bool(res["downed"]):
			w.on_downed(a, "")
			return
	if active and a.in_combat and s.has_resonance():
		var regen := float(DB.dict(DB.progression, "regen").get("energy_per_round_in_combat", 1))
		if s.form != "":
			regen *= float(DB.forms.get(s.form, {}).get("combat_regen_mult", 1.0))
		a.set_meta("en_acc", float(a.get_meta("en_acc", 0.0)) + regen)
		var whole := floori(float(a.get_meta("en_acc", 0.0)))
		if whole > 0:
			s.energy = mini(s.max_energy(), s.energy + whole)
			a.set_meta("en_acc", float(a.get_meta("en_acc", 0.0)) - whole)
	if s.prestige != "":
		var aura := Prestige.aura(s)
		if not aura.is_empty():
			var allies: Array = []
			for o in w.party_actors():
				if o.position.distance_to(a.position) <= float(aura.get("radius", 5.0)):
					allies.append(o.sheet)
			Prestige.apply_aura(s, allies)


func _flee(a: Actor) -> void:
	a.current = {}
	if not a.sheet.can_move():
		return
	var threat: Actor = w.nearest_hostile(a)
	if threat == null:
		return
	if a.is_moving():
		return
	var away := (a.position - threat.position)
	away.y = 0
	if away.length() < 0.1:
		away = Vector3(1, 0, 0)
	var goal: Vector3 = w.grid.nearest_passable(a.position + away.normalized() * 6.0, 4)
	a.move_to(goal)
