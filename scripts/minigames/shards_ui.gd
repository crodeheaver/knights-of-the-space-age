class_name ShardsPanel
extends MinigamePanel
## The Shards table in the crew commons: wager selection, the two tables,
## your hand of shards, Brann's turns paced so they can be followed, and the
## settlement screen. Rules: ShardsRules. Money and XP: MinigameRewards.

const DEAL_DELAY := 0.45
const AI_THINK := 0.8
const AI_AFTER_SHARD := 0.75
const CARD := Vector2(74, 104)
const SMALL := Vector2(46, 64)
const COL_MAIN := Color("#7f9dbd")

const RULES_TEXT := "[b]Goal.[/b] End each set closer to 20 than Brann without going over.\n\n[b]Your turn.[/b] The shared deck (four each of 1 to 10) deals you one card. You may then play [i]one[/i] shard from your hand, and either [b]end your turn[/b] (you will be dealt another card next turn) or [b]stand[/b] (your total is locked for the set).\n\n[b]Bust.[/b] Over 20 when your turn ends loses the set, so play a minus shard first if you can.\n[b]Exactly 20[/b] stands you automatically. [b]Nine cards[/b] on your table without busting wins the set outright.\n[b]Both standing:[/b] the higher total wins. A tie is replayed.\n\n[b]Match.[/b] First to two sets. Your four shards are drawn from your side deck when the match starts and last the whole match, so spend them well.\n\n[b]Shards.[/b] [color=#3fb6b0]+n[/color] adds, [color=#ff6a5a]−n[/color] subtracts. [color=#f2c26b]±n[/color] (swing) can be played either way. [color=#7fd0ff]Echo[/color] repeats the last card the deck dealt you. [color=#d06aff]Null[/color] cancels it.\n\n[b]Keys.[/b] 1–4 play a shard (Shift+number plays a swing shard as minus), E ends your turn, S stands, R shows these rules, Esc folds."

var rules: ShardsRules
var ticket: Dictionary = {}
var wager := 10
var stage := "setup"
var settle: Dictionary = {}
var _wait := 0.0
var _ai_pending: Dictionary = {}
var _settled := false
var _shown: Array[int] = [0, 0]
var _ui: Dictionary = {}


func build() -> void:
	make_window("Shards: Brann Ketterick's table" + ("  (practice)" if practice else ""), Vector2(1300, 900))
	if practice or Game.state == null:
		wager = 0
	else:
		var opts := MinigameRewards.shards_wager_options(Game.state)
		wager = 10 if opts.has(10) else 0
	_show_setup()


# ------------------------------------------------------------ setup
func _show_setup() -> void:
	stage = "setup"
	_settled = false
	ticket = {}
	settle = {}
	rules = null
	close_overlay()
	UIKit.clear(body)
	var cols := UIKit.hbox(24)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(cols)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UIKit.label("Brann riffles a deck worn soft at the corners and lays out two shard pouches. \"House rules: closest to twenty, nobody cries, and the purser's nephew's cousin is not allowed at this table.\"", 18, UIKit.DIM, true))
	left.add_child(UIKit.header("How Shards works"))
	var r := UIKit.rich(RULES_TEXT, 17)
	left.add_child(UIKit.scroll(r, 420))
	left.add_child(UIKit.header("Shard types"))
	var sample := UIKit.hbox(10)
	for code in ["+3", "-3", "~2", "E", "N"]:
		var sh := ShardsRules.parse(code)
		var c := UIKit.vbox(2)
		c.add_child(_card(ShardsRules.label(sh), _kind_name(sh), shard_color(String(sh["kind"])), SMALL + Vector2(10, 10), ShardsRules.describe(sh)))
		sample.add_child(c)
	left.add_child(sample)

	var right := UIKit.vbox(10)
	right.custom_minimum_size = Vector2(400, 0)
	cols.add_child(right)
	right.add_child(UIKit.header("Your stake"))
	if practice or Game.state == null:
		right.add_child(UIKit.label("Practice table: nothing is wagered, won or recorded.", 18, UIKit.TEAL, true))
	else:
		var st := Game.state
		right.add_child(UIKit.label("Credits on hand: %d" % st.inventory.credits, 18))
		var row := UIKit.hbox(8)
		var group := ButtonGroup.new()
		var opts := MinigameRewards.shards_wager_options(st)
		# After a loss the last stake may no longer be affordable.
		while not opts.has(wager) and wager > 0:
			var lower := 0
			for o in opts:
				if o < wager:
					lower = maxi(lower, o)
			wager = lower
		for w in MinigameRewards.SHARDS_WAGERS:
			var amount := int(w)
			var b := UIKit.button("%d cr" % amount if amount > 0 else "No stake", func() -> void: wager = amount, "Win: +%d credits. Lose or fold: −%d." % [amount, amount] if amount > 0 else "Play for the fun of it.")
			b.toggle_mode = true
			b.button_group = group
			b.disabled = not opts.has(amount)
			b.button_pressed = amount == wager
			b.custom_minimum_size = Vector2(88, 40)
			row.add_child(b)
		right.add_child(row)
		right.add_child(UIKit.label("A win pays your stake back plus the same again. Losing or folding a started match leaves the stake with Brann.", 15, UIKit.DIM, true))
		var rec := MinigameRewards.record(st, "shards") if st.minigames.has("shards") else {"wins": 0, "losses": 0, "net": 0}
		right.add_child(UIKit.label("Record against Brann: %d won, %d lost (net %s cr)" % [int(rec["wins"]), int(rec["losses"]), Rules.signed(int(rec["net"]))], 16, UIKit.TEXT, true))
		if not st.claimed("xp:shards_first_win"):
			right.add_child(UIKit.label("First match you win: +%d XP." % MinigameRewards.SHARDS_FIRST_WIN_XP, 16, UIKit.GOOD, true))
	right.add_child(UIKit.spacer(0, 20))
	var deal := UIKit.button("Deal the cards  (Enter)", _start_match)
	deal.custom_minimum_size = Vector2(0, 54)
	deal.add_theme_font_size_override("font_size", 22)
	right.add_child(deal)
	right.add_child(UIKit.button("Leave the table", close_now))
	MinigamePanel.focus_later(deal)


func _start_match() -> void:
	if stage != "setup":
		return
	if not practice and Game.state != null:
		var res := MinigameRewards.shards_stake(Game.state, wager)
		if not bool(res["ok"]):
			Events.toast(String(res["reason"]), "warn")
			GameAudio.play("ui_error", -6.0)
			return
		ticket = res["ticket"]
	rules = ShardsRules.new(Minigames.dice_for(practice))
	rules.start_match()
	stage = "play"
	_shown = [0, 0]
	_wait = DEAL_DELAY
	_ai_pending = {}
	_build_table()
	_refresh()


# ------------------------------------------------------------ table
func _build_table() -> void:
	UIKit.clear(body)
	_ui = {}
	var top := UIKit.hbox(12)
	var stake := UIKit.label("Practice table" if practice else ("Stake: %d credits" % int(ticket.get("wager", 0)) if int(ticket.get("wager", 0)) > 0 else "No stake"), 17, UIKit.DIM)
	stake.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(stake)
	_ui["setno"] = UIKit.label("", 17, UIKit.ACCENT2)
	top.add_child(_ui["setno"])
	body.add_child(top)
	body.add_child(_side_row(ShardsRules.OPPONENT))
	var mid := UIKit.vbox(4)
	_ui["status"] = UIKit.label("", 22, UIKit.TEXT, true)
	(_ui["status"] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_ui["status"])
	_ui["hint"] = UIKit.label("", 16, UIKit.DIM, true)
	(_ui["hint"] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_ui["hint"])
	_ui["log"] = UIKit.label("", 14, UIKit.DIM, true)
	(_ui["log"] as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	(_ui["log"] as Label).custom_minimum_size = Vector2(0, 40)
	mid.add_child(_ui["log"])
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	body.add_child(_side_row(ShardsRules.PLAYER))
	var hand_panel := UIKit.panel(null, UIKit.PANEL_LIGHT)
	var hand_row := UIKit.hbox(14)
	hand_panel.add_child(hand_row)
	var hl := UIKit.vbox(2)
	hl.custom_minimum_size = Vector2(170, 0)
	hl.add_child(UIKit.header("Your shards"))
	hl.add_child(UIKit.label("One per turn. They last the whole match.", 14, UIKit.DIM, true))
	hand_row.add_child(hl)
	_ui["hand"] = UIKit.hbox(16)
	hand_row.add_child(_ui["hand"])
	body.add_child(hand_panel)
	var acts := UIKit.hbox(10)
	_ui["end"] = UIKit.button("End turn  (E)", _player_end, "Keep your total and take another card next turn.")
	_ui["stand"] = UIKit.button("Stand  (S)", _player_stand, "Lock your total for this set.")
	for k in ["end", "stand"]:
		(_ui[k] as Button).custom_minimum_size = Vector2(190, 48)
		(_ui[k] as Button).add_theme_font_size_override("font_size", 20)
		acts.add_child(_ui[k])
	acts.add_child(UIKit.expand(UIKit.spacer()))
	acts.add_child(UIKit.button("Rules  (R)", _show_rules))
	acts.add_child(UIKit.button("Fold  (Esc)", _confirm_fold, "Concede the match." + ("" if practice else " Brann keeps the stake.")))
	body.add_child(acts)


func _side_row(p: int) -> PanelContainer:
	var pc := UIKit.panel(null, UIKit.PANEL)
	var h := UIKit.hbox(14)
	pc.add_child(h)
	var info := UIKit.vbox(2)
	info.custom_minimum_size = Vector2(170, 0)
	info.add_child(UIKit.label("Brann Ketterick" if p == ShardsRules.OPPONENT else "You", 22, UIKit.ACCENT2))
	var sets := UIKit.label("", 18, UIKit.TEXT)
	info.add_child(sets)
	var tot := UIKit.label("0", 44, UIKit.TEXT)
	info.add_child(tot)
	var state := UIKit.label("", 16, UIKit.DIM)
	info.add_child(state)
	h.add_child(info)
	var table := UIKit.hbox(8)
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.custom_minimum_size = Vector2(0, CARD.y + 8)
	h.add_child(table)
	_ui["sets%d" % p] = sets
	_ui["total%d" % p] = tot
	_ui["state%d" % p] = state
	_ui["table%d" % p] = table
	if p == ShardsRules.OPPONENT:
		var hv := UIKit.vbox(2)
		hv.add_child(UIKit.label("Brann's shards", 14, UIKit.DIM))
		var backs := UIKit.hbox(6)
		hv.add_child(backs)
		_ui["backs"] = backs
		h.add_child(hv)
	return pc


func _refresh() -> void:
	if rules == null or _ui.is_empty():
		return
	for p in 2:
		var seat: ShardsRules.Seat = rules.sides[p]
		var t := seat.total()
		(_ui["sets%d" % p] as Label).text = "Sets  " + "● ".repeat(seat.sets) + "○ ".repeat(maxi(0, ShardsRules.SETS_TO_WIN - seat.sets))
		var tl: Label = _ui["total%d" % p]
		tl.text = str(t)
		tl.add_theme_color_override("font_color", UIKit.BAD if t > ShardsRules.TARGET else (UIKit.GOOD if t == ShardsRules.TARGET else UIKit.TEXT))
		var stl: Label = _ui["state%d" % p]
		if seat.standing:
			stl.text = "STANDING"
			stl.add_theme_color_override("font_color", UIKit.TEAL)
		elif rules.active == p and rules.phase in ["deal", "act"]:
			stl.text = "▶ TO PLAY"
			stl.add_theme_color_override("font_color", UIKit.ACCENT)
		else:
			stl.text = "%d / %d cards" % [seat.table.size(), ShardsRules.TABLE_MAX]
			stl.add_theme_color_override("font_color", UIKit.DIM)
		var table: HBoxContainer = _ui["table%d" % p]
		UIKit.clear(table)
		for i in ShardsRules.TABLE_MAX:
			if i < seat.table.size():
				var c: Dictionary = seat.table[i]
				var kind := String(c["kind"])
				var col := COL_MAIN if kind == "main" else shard_color(kind)
				var tip := "Dealt from the main deck." if kind == "main" else "Shard %s played for %s." % [String(c.get("shard", c["label"])), Rules.signed(int(c["value"]))]
				var card := _card(String(c["label"]), "deck" if kind == "main" else _kind_label(kind), col, CARD, tip)
				table.add_child(card)
				if i >= _shown[p]:
					card.modulate = Color(1, 1, 1, 0)
					create_tween().tween_property(card, "modulate:a", 1.0, 0.22)
			else:
				table.add_child(_slot(CARD))
		_shown[p] = seat.table.size()
	var backs: HBoxContainer = _ui["backs"]
	UIKit.clear(backs)
	for i in rules.sides[ShardsRules.OPPONENT].hand.size():
		backs.add_child(_card_back(SMALL))
	_refresh_hand()
	_refresh_status()


func _refresh_hand() -> void:
	var hand: HBoxContainer = _ui["hand"]
	UIKit.clear(hand)
	var me: ShardsRules.Seat = rules.sides[ShardsRules.PLAYER]
	var my_turn := _my_turn()
	for i in me.hand.size():
		var sh: Dictionary = me.hand[i]
		var col := UIKit.vbox(4)
		col.add_child(_card(ShardsRules.label(sh), _kind_name(sh), shard_color(String(sh["kind"])), CARD, "%s\nKey: %d%s" % [ShardsRules.describe(sh), i + 1, " (Shift+%d for minus)" % (i + 1) if String(sh["kind"]) == "swing" else ""]))
		var btns := UIKit.hbox(4)
		for sg in ShardsRules.signs_for(sh):
			var idx := i
			var sgn: int = sg
			var preview := me.total() + rules.shard_value(ShardsRules.PLAYER, sh, sgn)
			var txt := ("%s → %d" % ["+" if sgn > 0 else "−", preview]) if String(sh["kind"]) == "swing" else ("Play → %d" % preview if my_turn else "Play")
			var b := UIKit.button(txt, func() -> void: _player_play(idx, sgn))
			b.disabled = not my_turn or rules.can_play(ShardsRules.PLAYER, idx, sgn) != ""
			b.add_theme_font_size_override("font_size", 15)
			btns.add_child(b)
		col.add_child(btns)
		hand.add_child(col)
	if me.hand.is_empty():
		hand.add_child(UIKit.label("All four shards spent.", 16, UIKit.DIM))
	(_ui["end"] as Button).disabled = not my_turn
	(_ui["stand"] as Button).disabled = not my_turn


func _refresh_status() -> void:
	var st: Label = _ui["status"]
	var hint: Label = _ui["hint"]
	(_ui["setno"] as Label).text = "Set %d   ·   You %d – %d Brann" % [rules.set_index + 1, rules.sides[0].sets, rules.sides[1].sets]
	hint.text = ""
	var me: ShardsRules.Seat = rules.sides[ShardsRules.PLAYER]
	match rules.phase:
		"deal":
			st.text = "Dealing your card…" if rules.active == ShardsRules.PLAYER else "Brann's turn: the deck deals him a card…"
		"act":
			if rules.active == ShardsRules.PLAYER:
				var t := me.total()
				if t > ShardsRules.TARGET:
					st.text = "%d: over twenty! Play a shard to come back down, or you bust when the turn ends." % t
				else:
					st.text = "Your turn: %d. Play a shard, end your turn, or stand." % t
					var foe: ShardsRules.Seat = rules.sides[ShardsRules.OPPONENT]
					var tip := "Next card busts you %d%% of the time." % int(round(rules.bust_chance(ShardsRules.PLAYER) * 100.0))
					if foe.standing:
						tip += "  Brann stands on %d." % foe.total()
					hint.text = tip
			else:
				st.text = "Brann studies his shards…"
		"set_over", "match_over":
			st.text = String(rules.log_lines[rules.log_lines.size() - 1]) if not rules.log_lines.is_empty() else ""
	var n := rules.log_lines.size()
	var tail: Array[String] = []
	for i in range(maxi(0, n - 3), n):
		tail.append(rules.log_lines[i])
	(_ui["log"] as Label).text = "   ·   ".join(tail)


func _my_turn() -> bool:
	return rules != null and stage == "play" and rules.phase == "act" and rules.active == ShardsRules.PLAYER and not is_paused()


# ------------------------------------------------------------ pacing
func _process(delta: float) -> void:
	if stage != "play" or rules == null or is_paused() or is_closed():
		return
	match rules.phase:
		"deal":
			_wait -= delta
			if _wait <= 0.0:
				rules.deal()
				GameAudio.play("ui_click", -8.0)
				_wait = AI_THINK
				_refresh()
		"act":
			if rules.active == ShardsRules.OPPONENT:
				_wait -= delta
				if _wait <= 0.0:
					_ai_step()
		"set_over":
			_show_set_result()
		"match_over":
			_on_match_over()


func _ai_step() -> void:
	if _ai_pending.is_empty():
		_ai_pending = rules.ai_decide()
		if int(_ai_pending["shard"]) >= 0:
			var err := rules.play_shard(int(_ai_pending["shard"]), int(_ai_pending["sign"]))
			if err != "":
				push_warning("Shards AI: " + err)
			_wait = AI_AFTER_SHARD
			_refresh()
			return
	var stand := bool(_ai_pending["stand"])
	_ai_pending = {}
	if stand:
		rules.stand()
	else:
		rules.end_turn()
	_wait = DEAL_DELAY
	_refresh()


func _player_play(idx: int, sgn: int) -> void:
	if not _my_turn():
		return
	var err := rules.play_shard(idx, sgn)
	if err != "":
		Events.toast(err, "warn")
		return
	GameAudio.play("ui_confirm", -8.0)
	_refresh()


func _player_end() -> void:
	if not _my_turn():
		return
	rules.end_turn()
	_wait = DEAL_DELAY
	_refresh()


func _player_stand() -> void:
	if not _my_turn():
		return
	rules.stand()
	_wait = DEAL_DELAY
	_refresh()


func _show_set_result() -> void:
	var res := rules.last_set()
	var w := int(res.get("winner", -1))
	var totals: Array = res.get("totals", [0, 0])
	var title := "Tie: the set is replayed" if w < 0 else ("You take the set" if w == ShardsRules.PLAYER else "Brann takes the set")
	var why := ""
	match String(res.get("reason", "")):
		"bust":
			why = "%s went over twenty (%d)." % ["Brann" if w == ShardsRules.PLAYER else "You", int(totals[1 - w])]
		"nine":
			why = "Nine cards on the table without busting."
		"stand":
			why = "%d against %d." % [int(totals[0]), int(totals[1])]
		"tie":
			why = "Both stood on %d." % int(totals[0])
	show_overlay(title, "%s\n\nSets: You %d – %d Brann" % [why, rules.sides[0].sets, rules.sides[1].sets], [["Next set", _next_set], ["Fold", _confirm_fold]], 1, 520.0)
	GameAudio.play("ui_confirm" if w == ShardsRules.PLAYER else "ui_click", -6.0)


func _next_set() -> void:
	close_overlay()
	if rules.next_set():
		_shown = [0, 0]
		_wait = DEAL_DELAY
		_ai_pending = {}
		_refresh()


func _on_match_over() -> void:
	if _settled:
		return
	_settled = true
	stage = "done"
	var won := rules.match_winner == ShardsRules.PLAYER
	var text := "Sets: You %d – %d Brann." % [rules.sides[0].sets, rules.sides[1].sets]
	if not practice and Game.state != null:
		settle = MinigameRewards.shards_settle(Game.state, ticket, won)
		var w := int(ticket.get("wager", 0))
		if w > 0:
			text += ("\n[color=#5fd38a]Brann counts out %d credits (+%d).[/color]" % [int(settle["payout"]), w]) if won else ("\n[color=#ff6a5a]Brann keeps your %d credits.[/color]" % w)
		if int(settle.get("xp", 0)) > 0:
			text += "\n[color=#f2c26b]First win against Brann: +%d XP.[/color]" % int(settle["xp"])
	else:
		text += "\nPractice: nothing was wagered or recorded."
	text += "\n\n" + ("\"Beginner's luck. That's the official story.\"" if won else "\"Don't feel bad. I've been losing to myself for a week.\"")
	Minigames.post_finished("shards", "win" if won else "loss", practice)
	GameAudio.play("ui_confirm" if won else "ui_error", -4.0)
	_refresh()
	show_overlay("You win the match!" if won else "Brann takes the match", text, [["Play again", _show_setup], ["Leave", close_now]], 1)


# ------------------------------------------------------------ esc / keys
func on_escape() -> void:
	if stage == "play" and rules != null and not rules.is_over():
		_confirm_fold()
	else:
		close_now()


func _confirm_fold() -> void:
	if stage != "play" or rules == null or rules.is_over():
		close_now()
		return
	var w := int(ticket.get("wager", 0))
	var txt := "Folding ends the match as a loss" + (" and Brann keeps your %d-credit stake." % w if w > 0 else ".")
	show_overlay("Fold the match?", txt, [["Fold and leave", _fold], ["Keep playing", close_overlay]], 1, 520.0)


func _fold() -> void:
	close_overlay()
	if rules != null and not rules.is_over():
		rules.forfeit(ShardsRules.PLAYER)
		_settled = true
		stage = "done"
		if not practice and Game.state != null:
			settle = MinigameRewards.shards_settle(Game.state, ticket, false)
			var w := int(ticket.get("wager", 0))
			if w > 0:
				Events.toast("You fold. Brann pockets your %d credits." % w, "info")
		Minigames.post_finished("shards", "forfeit", practice)
	close_now()


func _show_rules() -> void:
	show_overlay("Shards: the rules", RULES_TEXT, [["Back to the table", close_overlay]], 0, 820.0)


func handle_key(ev: InputEventKey) -> void:
	var k := ev.keycode
	if stage == "setup":
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			_start_match()
		return
	if k == KEY_R or k == KEY_F1:
		_show_rules()
	elif k == KEY_E:
		_player_end()
	elif k == KEY_S:
		_player_stand()
	elif k >= KEY_1 and k <= KEY_4 and rules != null:
		var idx := k - KEY_1
		var me: ShardsRules.Seat = rules.sides[ShardsRules.PLAYER]
		if idx < me.hand.size():
			_player_play(idx, -1 if ev.shift_pressed and String(me.hand[idx]["kind"]) == "swing" else 1)


# ------------------------------------------------------------ widgets
static func shard_color(kind: String) -> Color:
	match kind:
		"plus":
			return UIKit.TEAL
		"minus":
			return UIKit.BAD
		"swing":
			return UIKit.ACCENT2
		"echo":
			return UIKit.MERCY
		"null":
			return UIKit.DOMINION
	return COL_MAIN


static func _kind_label(kind: String) -> String:
	match kind:
		"plus", "minus":
			return "shard"
		"swing":
			return "swing"
		"echo":
			return "echo"
		"null":
			return "null"
	return ""


static func _kind_name(sh: Dictionary) -> String:
	return _kind_label(String(sh.get("kind", "")))


func _card(text: String, sub: String, col: Color, sz: Vector2, tip: String = "") -> PanelContainer:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = sz
	pc.add_theme_stylebox_override("panel", MinigamePanel.card_style(col))
	pc.tooltip_text = tip
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(v)
	var l := UIKit.label(text, int(sz.y * (0.3 if text.length() > 3 else 0.38)), Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(l)
	if sub != "":
		var s := UIKit.label(sub, 12, col.lightened(0.25))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(s)
	return pc


func _slot(sz: Vector2) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = sz
	var s := MinigamePanel.card_style(Color(0.3, 0.3, 0.34), 0.85, 1)
	s.bg_color = Color(0.1, 0.1, 0.12, 0.5)
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _card_back(sz: Vector2) -> PanelContainer:
	var pc := _card("◆", "", UIKit.BORDER.lightened(0.2), sz, "A shard Brann has not played yet.")
	return pc
