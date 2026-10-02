class_name VendorUI
extends PanelBase
## Buy and sell with a finite-stock vendor. Prices and the atomic trade come
## from Vendor (rules); this screen only displays them and asks for intent.

var vendor_id := ""
var _pick: Dictionary = {}
var _cols: Array = []
var _credits: Label
var _msg: Label


func build() -> void:
	var vd := Vendor.def(vendor_id)
	var v := make_window(String(vd.get("name", "Vendor")), Vector2(1500, 860))
	v.add_child(UIKit.label(String(vd.get("desc", "")), 16, UIKit.DIM, true))
	_credits = UIKit.label("", 22, UIKit.ACCENT2)
	v.add_child(_credits)
	var h := UIKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	for i in 3:
		var c := UIKit.vbox(6)
		var p := UIKit.panel(UIKit.scroll(c))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		h.add_child(p)
		_cols.append(c)
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	v.add_child(_msg)
	_render()


func _render() -> void:
	var st := Game.state
	_credits.text = "Your credits: %d" % st.inventory.credits
	for c in _cols:
		UIKit.clear(c)
	var c0: VBoxContainer = _cols[0]
	c0.add_child(UIKit.header("For sale"))
	var stock := Vendor.stock(st, vendor_id)
	var ids: Array = stock.keys().filter(func(k: Variant) -> bool: return int(stock[k]) > 0)
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return DB.item_name(String(a)) < DB.item_name(String(b)))
	if ids.is_empty():
		c0.add_child(UIKit.label("Sold out.", 16, UIKit.DIM))
	for id in ids:
		var iid := String(id)
		var price := Vendor.buy_price(vendor_id, iid)
		var b := UIKit.button("%s  ×%d   %d cr" % [DB.item_name(iid), int(stock[id]), price], func() -> void:
			_pick = {"side": "buy", "id": iid}
			_render())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = ItemText.plain(iid)
		if price > st.inventory.credits:
			b.add_theme_color_override("font_color", UIKit.DIM)
		c0.add_child(b)
	var c1: VBoxContainer = _cols[1]
	c1.add_child(UIKit.header("Your items"))
	for r in st.inventory.rows("all"):
		var rid := String(r["id"])
		var rinst: Dictionary = r["inst"]
		var why := Vendor.can_sell(rid)
		var nm := (ItemInst.display_name(rinst) if not rinst.is_empty() else DB.item_name(rid)) + ("  ×%d" % int(r["count"]) if int(r["count"]) > 1 else "")
		var b2 := UIKit.button("%s   %s" % [nm, ("%d cr" % Vendor.sell_price(vendor_id, rid)) if why == "" else "—"], func() -> void:
			_pick = {"side": "sell", "id": rid, "inst": rinst}
			_render())
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.tooltip_text = ItemText.plain(rid, rinst) + ("\n" + why if why != "" else "")
		if why != "":
			b2.add_theme_color_override("font_color", UIKit.DIM)
		c1.add_child(b2)
	var c2: VBoxContainer = _cols[2]
	if _pick.is_empty():
		c2.add_child(UIKit.label("Select an item to buy or sell. Equipped items must be unequipped before selling. Selling returns less than buying costs.", 16, UIKit.DIM, true))
		return
	var pid := String(_pick["id"])
	var pinst: Dictionary = _pick.get("inst", {})
	c2.add_child(UIKit.rich(ItemText.describe(pid, pinst), 17))
	_compare(c2, pid)
	if String(_pick["side"]) == "buy":
		var price2 := Vendor.buy_price(vendor_id, pid)
		var have := int(stock.get(pid, 0))
		for q in [1, 5]:
			if q > have or (q > 1 and not st.inventory.is_stackable(pid)):
				continue
			var qq: int = q
			var bb := UIKit.button("Buy %d for %d cr" % [qq, price2 * qq], func() -> void: _result(Vendor.buy(Game.state, vendor_id, pid, qq)))
			bb.disabled = price2 * qq > st.inventory.credits
			if bb.disabled:
				bb.tooltip_text = "Not enough credits."
			c2.add_child(bb)
	else:
		var why2 := Vendor.can_sell(pid)
		if why2 != "":
			c2.add_child(UIKit.label(why2, 16, UIKit.BAD, true))
			return
		var sp := Vendor.sell_price(vendor_id, pid)
		if not pinst.is_empty():
			c2.add_child(UIKit.button("Sell for %d cr" % sp, func() -> void: _result(Vendor.sell(Game.state, vendor_id, pid, 1, String(pinst["uid"])))))
			if not (pinst.get("upgrades", []) as Array).is_empty():
				c2.add_child(UIKit.label("Installed upgrades are returned to your inventory.", 14, UIKit.DIM, true))
		else:
			var n := st.inventory.stack_count(pid)
			c2.add_child(UIKit.button("Sell 1 for %d cr" % sp, func() -> void: _result(Vendor.sell(Game.state, vendor_id, pid, 1))))
			if n > 1:
				c2.add_child(UIKit.button("Sell all %d for %d cr" % [n, sp * n], func() -> void: _result(Vendor.sell(Game.state, vendor_id, pid, n))))


func _compare(c: VBoxContainer, id: String) -> void:
	var t := String(DB.item(id).get("type", ""))
	if not t in ["weapon", "armor", "gear"]:
		return
	for uid in Game.state.party:
		var s := Game.state.get_char(uid)
		var slot := "main" if t == "weapon" else String(DB.item(id).get("slot", ""))
		var why := EquipmentRules.can_equip(s, id, slot)
		if why != "":
			c.add_child(UIKit.label("%s: %s" % [s.display_name, why], 14, UIKit.DIM, true))
			continue
		var d: Dictionary = EquipmentRules.compare(s, id, slot)["delta"]
		var parts: PackedStringArray = []
		for k in ["Defense", "Attack", "Avg damage", "Max health", "Max energy"]:
			if d.has(k):
				parts.append("%s %+.1f" % [k, float(d[k])] if k == "Avg damage" else "%s %+d" % [k, int(d[k])])
		c.add_child(UIKit.label("%s: %s" % [s.display_name, ", ".join(parts) if not parts.is_empty() else "no change"], 14, UIKit.TEXT, true))


func _result(r: Dictionary) -> void:
	if bool(r.get("ok", false)):
		GameAudio.play("loot", -6.0)
		_msg.text = ""
		var still := false
		if String(_pick.get("side", "")) == "buy":
			still = int(Vendor.stock(Game.state, vendor_id).get(String(_pick["id"]), 0)) > 0
		else:
			still = _pick.get("inst", {}).is_empty() and Game.state.inventory.stack_count(String(_pick["id"])) > 0
		if not still:
			_pick = {}
	else:
		_msg.text = String(r.get("reason", "Trade failed."))
		GameAudio.play("ui_error", -6.0)
	_render()
