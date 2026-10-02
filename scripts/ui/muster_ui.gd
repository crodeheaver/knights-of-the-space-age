class_name MusterUI
extends PanelBase
## Muster points: a safe spot to regroup. Shows the party, lets you rest (same
## rule as the Rest key: no hostiles near), talk to companions, and set
## who leads.


func build() -> void:
	var v := make_window("Muster Point", Vector2(1200, 760))
	v.add_child(UIKit.label("Evacuation muster point. Crew stencilled the evac routes on the deck; someone left a thermos.", 16, UIKit.DIM, true))
	var body := UIKit.vbox(8)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(body)
	_fill(body)


func _fill(body: VBoxContainer) -> void:
	UIKit.clear(body)
	var w := world()
	var st := Game.state
	var row := UIKit.hbox(12)
	body.add_child(row)
	for uid in st.roster:
		var s := st.get_char(uid)
		var c := UIKit.vbox(4)
		var p := UIKit.panel(c)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(p)
		c.add_child(UIKit.label(s.display_name, 22, UIKit.ACCENT2))
		c.add_child(UIKit.label("Level %d · %s" % [s.level, "in party" if st.party.has(uid) else "waiting"], 15, UIKit.DIM))
		c.add_child(UIKit.label("Health %d/%d" % [s.hp, s.max_hp()], 15))
		c.add_child(UIKit.bar(s.hp, s.max_hp(), UIKit.GOOD, 10))
		c.add_child(UIKit.label("Energy %d/%d" % [s.energy, s.max_energy()], 15))
		c.add_child(UIKit.bar(s.energy, s.max_energy(), UIKit.MERCY, 10))
		if st.influence.has(uid):
			c.add_child(UIKit.label("Influence %d" % int(st.influence[uid]), 15, UIKit.TEAL))
		if s.levels_available() > 0 and main != null:
			c.add_child(UIKit.button("Level up", func() -> void: main.open_levelup(uid)))
		if uid != "player" and w != null:
			var tb := UIKit.button("Talk", func() -> void:
				main.close_panel(self)
				w.talk_companion(uid))
			tb.disabled = DB.dialogue(String(DB.companions.get(uid, {}).get("dialogue", uid + "_talk"))).is_empty() or w.combat.active
			c.add_child(tb)
		if w != null and st.party.has(uid):
			var lb := UIKit.button("Lead", func() -> void:
				w.switch_control(uid)
				_fill(body))
			lb.disabled = st.controlled == uid or s.is_downed()
			c.add_child(lb)
	body.add_child(UIKit.sep())
	var why := w.rest_block_reason(true) if w != null else "No ship loaded."
	var rb := UIKit.button("Rest (restore health and energy, clear harmful effects)", func() -> void:
		if w != null:
			w.rest(true)
		_fill(body))
	rb.disabled = why != ""
	rb.tooltip_text = why
	body.add_child(rb)
	if why != "":
		body.add_child(UIKit.label(why, 15, UIKit.WARN))
	var party_full := st.party.size() >= 3
	body.add_child(UIKit.label("Party: %d/3%s. Companions join as you find them; everyone with you fights at your side." % [st.party.size(), " (full)" if party_full else ""], 15, UIKit.DIM, true))
	body.add_child(UIKit.label("Tip: you can also rest anywhere safe with %s." % Settings.key_label("rest"), 15, UIKit.DIM))
