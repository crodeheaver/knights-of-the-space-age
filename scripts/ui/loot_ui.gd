class_name LootUI
extends PanelBase
## Container / corpse loot window. Loot is persistent and claimable once.

var object_id := ""
var list: VBoxContainer


func build() -> void:
	var wo: WorldObject = world().objects.get(object_id, null)
	if wo == null:
		call_deferred("request_close")
		return
	var v := make_window(wo.display_name(), Vector2(620, 480))
	list = UIKit.vbox(4)
	v.add_child(UIKit.scroll(list, 300))
	var h := UIKit.hbox()
	h.add_child(UIKit.button("Take all", func() -> void:
		var got := world().loot_take(wo, "", true)
		if not got.is_empty():
			Events.toast("Took: " + ", ".join(PackedStringArray(got)), "reward")
		request_close()))
	v.add_child(h)
	_fill(wo)


func _fill(wo: WorldObject) -> void:
	UIKit.clear(list)
	var loot := wo.remaining_loot()
	if loot.is_empty():
		list.add_child(UIKit.label("Empty.", 16, UIKit.DIM))
	for k in loot.keys():
		var id := String(k)
		var n := int(loot[k])
		var row := UIKit.hbox()
		var nm := ("%d credits" % n) if id == "credits" else "%s%s" % [DB.item_name(id), " ×%d" % n if n > 1 else ""]
		var l := UIKit.label(nm, 17)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = String(DB.item(id).get("desc", ""))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(l)
		row.add_child(UIKit.button("Take", func() -> void:
			world().loot_take(wo, id)
			_fill(wo)))
		list.add_child(row)
