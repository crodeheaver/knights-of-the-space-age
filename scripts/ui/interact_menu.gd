class_name InteractMenu
extends PanelBase
## Context options for a world object, showing the acting character, skill,
## DC and success chance, and why unavailable options are disabled.

var data: Dictionary = {}


func build() -> void:
	var w := world()
	var wo: WorldObject = w.objects.get(String(data["object"]), null)
	var actor: Actor = w.actors.get(String(data["actor"]), null)
	if wo == null or actor == null:
		call_deferred("request_close")
		return
	var v := make_window(String(data.get("title", wo.display_name())), Vector2(760, 520))
	v.add_child(UIKit.label("Acting character: %s" % actor.sheet.display_name, 18, UIKit.TEAL))
	var lt := String(wo.st().get("lock_text", wo.def.get("lock_text", "")))
	if wo.kind == "door" and wo.is_locked() and lt != "":
		v.add_child(UIKit.label(Game.fmt(lt), 16, UIKit.DIM, true))
	v.add_child(UIKit.sep())
	var list := UIKit.vbox(6)
	for o in wo.options(actor):
		var od: Dictionary = o
		if String(od["id"]) == "_info":
			continue
		var txt := String(od["label"])
		if od.has("tag"):
			txt += "   [%s]" % od["tag"]
		var b := UIKit.button(txt, func() -> void:
			main.close_panel(self)
			w.perform_option(actor, wo, String(od["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not bool(od.get("enabled", true)):
			b.disabled = true
			b.text = txt + "   — " + String(od.get("reason", "unavailable"))
		list.add_child(b)
	if list.get_child_count() == 0:
		list.add_child(UIKit.label("No actions available here right now.", 16, UIKit.DIM))
	v.add_child(UIKit.scroll(list, 220))
	v.add_child(UIKit.sep())
	# Other party members can act instead (they walk over and use their own skills).
	var alt := UIKit.hbox(6)
	alt.add_child(UIKit.label("Act as:", 15, UIKit.DIM))
	for uid in Game.state.party:
		if uid == actor.uid or not w.actors.has(uid):
			continue
		var s := Game.state.get_char(uid)
		var best := ""
		for o in wo.options(w.actors[uid]):
			if (o as Dictionary).has("skill"):
				best = " (%s %s)" % [DB.skill(String(o["skill"]))["name"], Rules.signed(int(o["bonus"]))]
				break
		alt.add_child(UIKit.button(s.display_name + best, func() -> void:
			main.close_panel(self)
			w.switch_control(uid)
			w.cmd_interact(w.actors[uid], wo, "")))
	v.add_child(alt)
