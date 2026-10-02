class_name PrestigeUI
extends PanelBase
## Prestige specialization: three families (Warden, Weaver, Shade), each with
## a Mercy and a Dominion variant. Shows every requirement and why a variant
## is unavailable; adoption is permanent and asks for confirmation. Rules live
## in Prestige (eligibility, features); this screen only presents them.

var uid := "player"
var _confirm := ""
var _body: VBoxContainer
var _msg: Label


func build() -> void:
	var v := make_window("Specialization", Vector2(1400, 860))
	v.add_child(UIKit.label("At level %d an operator can commit to a specialization. Each family has a Mercy and a Dominion path; your alignment decides which doors are open. The choice is permanent." % int(Prestige.data().get("min_level", 6)), 16, UIKit.DIM, true))
	_body = UIKit.vbox(10)
	v.add_child(UIKit.scroll(_body))
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	v.add_child(_msg)
	_render()


func _render() -> void:
	UIKit.clear(_body)
	var s := Game.state.get_char(uid)
	var al := Game.state.alignment
	_body.add_child(UIKit.label("%s — level %d %s · alignment %s (%+d)%s" % [s.display_name, s.level, DB.klass(s.class_id).get("name", ""), GameState.alignment_label(al), al, ("  · specialized: " + String(Prestige.variant(s.prestige).get("name", ""))) if s.prestige != "" else ""], 19, UIKit.ACCENT2))
	var fams: Dictionary = DB.dict(Prestige.data(), "families")
	for fid in fams.keys():
		var fd: Dictionary = fams[fid]
		var box := UIKit.vbox(6)
		_body.add_child(UIKit.panel(box))
		box.add_child(UIKit.label(String(fd.get("name", fid)), 24, UIKit.ACCENT2))
		box.add_child(UIKit.label(String(fd.get("desc", "")), 15, UIKit.DIM, true))
		var row := UIKit.hbox(12)
		box.add_child(row)
		for vid in DB.dict(Prestige.data(), "variants").keys():
			var vd: Dictionary = Prestige.variant(String(vid))
			if String(vd.get("family", "")) != String(fid):
				continue
			var vb := UIKit.vbox(4)
			var vp := UIKit.panel(vb, UIKit.PANEL_LIGHT)
			vp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(vp)
			var mercy := vd.has("alignment_min")
			vb.add_child(UIKit.label("%s  [%s]" % [vd.get("name", vid), "Mercy" if mercy else "Dominion"], 20, UIKit.MERCY if mercy else UIKit.DOMINION))
			vb.add_child(UIKit.label(String(vd.get("desc", "")), 15, UIKit.TEXT, true))
			var errs := Prestige.eligibility_errors(s, String(vid), al)
			if s.prestige == String(vid):
				vb.add_child(UIKit.label("Your specialization.", 16, UIKit.GOOD))
				continue
			if errs.is_empty():
				vb.add_child(UIKit.label("All requirements met.", 15, UIKit.GOOD))
				var v2 := String(vid)
				var b := UIKit.button("Confirm: become %s" % vd.get("name", vid) if _confirm == v2 else "Specialize as %s" % vd.get("name", vid), func() -> void: _adopt(v2))
				vb.add_child(b)
			else:
				for e in errs:
					vb.add_child(UIKit.label("✕ " + e, 14, UIKit.BAD, true))


func _adopt(vid: String) -> void:
	if _confirm != vid:
		_confirm = vid
		_msg.text = "This is permanent. Press the button again to confirm."
		_render()
		return
	var r := Prestige.adopt(Game.state.get_char(uid), vid, Game.state.alignment)
	_confirm = ""
	if bool(r["ok"]):
		Events.toast("%s is now a %s." % [Game.state.get_char(uid).display_name, Prestige.variant(vid).get("name", vid)], "quest")
		GameAudio.play("level_up", -4.0)
		_msg.text = ""
	else:
		_msg.text = "; ".join(r["errors"])
	_render()
