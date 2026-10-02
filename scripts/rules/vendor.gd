class_name Vendor
extends RefCounted
## Finite-stock vendor. Buying costs value x buy_mult; selling returns
## value x sell_mult (always lower), so trading cannot generate credits.
## Sold items join the vendor's stock (and can be bought back at full price).


static func def(vendor_id: String) -> Dictionary:
	return DB.vendors.get(vendor_id, {})


static func stock(st: GameState, vendor_id: String) -> Dictionary:
	if not st.vendor_stock.has(vendor_id):
		var s := {}
		var d: Dictionary = DB.dict(def(vendor_id), "stock")
		for k in d.keys():
			s[String(k)] = int(d[k])
		st.vendor_stock[vendor_id] = s
	return st.vendor_stock[vendor_id]


static func buy_price(vendor_id: String, item_id: String) -> int:
	return maxi(1, int(ceil(int(DB.item(item_id).get("value", 0)) * float(def(vendor_id).get("buy_mult", 1.0)))))


static func sell_price(vendor_id: String, item_id: String) -> int:
	return int(floor(int(DB.item(item_id).get("value", 0)) * float(def(vendor_id).get("sell_mult", 0.4))))


static func can_sell(item_id: String) -> String:
	var it: Dictionary = DB.item(item_id)
	if bool(it.get("quest", false)):
		return "Quest items cannot be sold."
	if bool(it.get("bound", false)):
		return "%s is bound to you and cannot be sold." % it.get("name", item_id)
	if int(it.get("value", 0)) <= 0:
		return "Worthless."
	return ""


static func buy(st: GameState, vendor_id: String, item_id: String, qty: int = 1) -> Dictionary:
	var s := stock(st, vendor_id)
	if qty <= 0:
		return {"ok": false, "reason": "Invalid quantity."}
	if int(s.get(item_id, 0)) < qty:
		return {"ok": false, "reason": "Out of stock."}
	var price := buy_price(vendor_id, item_id) * qty
	var tx := st.inventory.tx()
	tx.credits_delta(-price).stock_delta(s, item_id, -qty).add_items(item_id, qty)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	Events.post("vendor_trade", {"vendor": vendor_id, "item": item_id, "qty": qty, "credits": -price})
	return {"ok": true, "reason": "", "price": price}


static func sell(st: GameState, vendor_id: String, item_id: String, qty: int = 1, inst_uid: String = "") -> Dictionary:
	var reason := can_sell(item_id)
	if reason != "":
		return {"ok": false, "reason": reason}
	var s := stock(st, vendor_id)
	var price := sell_price(vendor_id, item_id) * qty
	var tx := st.inventory.tx()
	if inst_uid != "":
		if qty != 1:
			return {"ok": false, "reason": "Invalid quantity."}
		var inst := st.inventory.find_instance(inst_uid)
		if inst.is_empty():
			return {"ok": false, "reason": "Unequip it first."}
		tx.remove_instance(inst_uid)
		for up in inst.get("upgrades", []):
			tx.add_items(String(up), 1)
	else:
		if st.inventory.stack_count(item_id) < qty:
			return {"ok": false, "reason": "Not enough to sell."}
		tx.remove_items(item_id, qty)
	tx.credits_delta(price).stock_delta(s, item_id, qty)
	if not tx.commit():
		return {"ok": false, "reason": tx.error}
	Events.post("vendor_trade", {"vendor": vendor_id, "item": item_id, "qty": -qty, "credits": price})
	return {"ok": true, "reason": "", "price": price}
