class_name Inventory
extends RefCounted
## Shared party inventory: stackable items by count, unique equipment as
## instances, and credits. All multi-step changes (trade, craft, dismantle,
## equip) go through Inventory.Tx, which validates every step before
## committing any of them, so quantities never go negative and nothing is
## duplicated or lost on failure.

var stacks: Dictionary = {}
var instances: Array = []
var credits: int = 0


func count(id: String) -> int:
	var n := int(stacks.get(id, 0))
	for inst in instances:
		if inst["id"] == id:
			n += 1
	return n


func stack_count(id: String) -> int:
	return int(stacks.get(id, 0))


func is_stackable(id: String) -> bool:
	return bool(DB.item(id).get("stack", false))


## Adds `n` of an item. Non-stackables become new instances.
func add(id: String, n: int = 1) -> Array:
	var made: Array = []
	if n <= 0 or DB.item(id).is_empty():
		return made
	if is_stackable(id):
		stacks[id] = int(stacks.get(id, 0)) + n
	else:
		for i in n:
			var inst := ItemInst.make(id)
			instances.append(inst)
			made.append(inst)
	Events.post("inventory_changed", {"id": id, "delta": n})
	return made


func remove(id: String, n: int = 1) -> bool:
	if n <= 0:
		return true
	if is_stackable(id):
		var have := int(stacks.get(id, 0))
		if have < n:
			return false
		have -= n
		if have == 0:
			stacks.erase(id)
		else:
			stacks[id] = have
	else:
		var uids: Array = []
		for inst in instances:
			if inst["id"] == id and inst.get("upgrades", []).is_empty():
				uids.append(inst["uid"])
		if uids.size() < n:
			for inst in instances:
				if inst["id"] == id and not uids.has(inst["uid"]):
					uids.append(inst["uid"])
		if uids.size() < n:
			return false
		for i in n:
			remove_instance(String(uids[i]))
	Events.post("inventory_changed", {"id": id, "delta": -n})
	return true


func add_instance(inst: Dictionary) -> void:
	instances.append(inst)
	Events.post("inventory_changed", {"id": inst["id"], "delta": 1})


func find_instance(uid: String) -> Dictionary:
	for inst in instances:
		if inst["uid"] == uid:
			return inst
	return {}


func remove_instance(uid: String) -> Dictionary:
	for i in instances.size():
		if instances[i]["uid"] == uid:
			var inst: Dictionary = instances[i]
			instances.remove_at(i)
			return inst
	return {}


## Rows for UI: [{id, count, inst (or {}), category}]
func rows(filter: String = "all") -> Array:
	var out: Array = []
	for id in stacks.keys():
		var it: Dictionary = DB.item(String(id))
		if _matches(it, filter):
			out.append({"id": String(id), "count": int(stacks[id]), "inst": {}, "type": it.get("type", "")})
	for inst in instances:
		var it2: Dictionary = DB.item(String(inst["id"]))
		if _matches(it2, filter):
			out.append({"id": String(inst["id"]), "count": 1, "inst": inst, "type": it2.get("type", "")})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["type"] != b["type"]:
			return String(a["type"]) < String(b["type"])
		return DB.item_name(a["id"]) < DB.item_name(b["id"]))
	return out


static func _matches(it: Dictionary, filter: String) -> bool:
	var t := String(it.get("type", ""))
	match filter:
		"all":
			return true
		"weapons":
			return t == "weapon"
		"armor":
			return t == "armor" or t == "gear"
		"consumables":
			return t == "consumable" or t == "grenade" or t == "mine"
		"resources":
			return t == "resource" or t == "upgrade"
		"quest":
			return t == "quest"
	return true


func to_dict() -> Dictionary:
	return {"stacks": stacks.duplicate(), "instances": instances.duplicate(true), "credits": credits}


func from_dict(d: Dictionary) -> void:
	stacks = {}
	var st: Dictionary = d.get("stacks", {})
	for k in st.keys():
		if int(st[k]) > 0:
			stacks[String(k)] = int(st[k])
	instances = []
	for inst in d.get("instances", []):
		instances.append(ItemInst.normalize(inst))
	credits = maxi(0, int(d.get("credits", 0)))


## Total worth for conservation tests (credits + item values).
func total_value() -> int:
	var v := credits
	for id in stacks.keys():
		v += int(DB.item(String(id)).get("value", 0)) * int(stacks[id])
	for inst in instances:
		v += int(DB.item(String(inst["id"])).get("value", 0))
	return v


func tx() -> Tx:
	return Tx.new(self)


class Tx:
	extends RefCounted
	## Atomic transaction over an Inventory (and optionally a vendor stock dict).
	var inv: Inventory
	var ops: Array = []
	var error: String = ""

	func _init(i: Inventory) -> void:
		inv = i

	func remove_items(id: String, n: int) -> Tx:
		ops.append({"op": "remove", "id": id, "n": n})
		return self

	func add_items(id: String, n: int) -> Tx:
		ops.append({"op": "add", "id": id, "n": n})
		return self

	func remove_instance(uid: String) -> Tx:
		ops.append({"op": "remove_inst", "uid": uid})
		return self

	func add_instance(inst: Dictionary) -> Tx:
		ops.append({"op": "add_inst", "inst": inst})
		return self

	func credits_delta(n: int) -> Tx:
		ops.append({"op": "credits", "n": n})
		return self

	func stock_delta(stock: Dictionary, id: String, n: int) -> Tx:
		ops.append({"op": "stock", "stock": stock, "id": id, "n": n})
		return self

	func validate() -> String:
		var counts := {}
		var cred := inv.credits
		var removed_uids := {}
		var stock_view := {}
		for o in ops:
			match String(o["op"]):
				"remove":
					var id := String(o["id"])
					if int(o["n"]) < 0:
						return "Invalid quantity."
					if not counts.has(id):
						counts[id] = inv.count(id)
					counts[id] = int(counts[id]) - int(o["n"])
					if int(counts[id]) < 0:
						return "Not enough %s." % DB.item_name(id)
				"add":
					var id2 := String(o["id"])
					if int(o["n"]) < 0 or DB.item(id2).is_empty():
						return "Invalid item."
					if not counts.has(id2):
						counts[id2] = inv.count(id2)
					counts[id2] = int(counts[id2]) + int(o["n"])
				"remove_inst":
					var uid := String(o["uid"])
					if inv.find_instance(uid).is_empty() or removed_uids.has(uid):
						return "Item is no longer in the inventory."
					removed_uids[uid] = true
				"add_inst":
					pass
				"credits":
					cred += int(o["n"])
					if cred < 0:
						return "Not enough credits."
				"stock":
					var key := String(o["id"])
					var cur := int(stock_view.get(key, int(o["stock"].get(o["id"], 0))))
					cur += int(o["n"])
					if cur < 0:
						return "Out of stock."
					stock_view[key] = cur
		return ""

	func commit() -> bool:
		error = validate()
		if error != "":
			return false
		var muted := Events.muted
		for o in ops:
			match String(o["op"]):
				"remove":
					inv.remove(String(o["id"]), int(o["n"]))
				"add":
					inv.add(String(o["id"]), int(o["n"]))
				"remove_inst":
					inv.remove_instance(String(o["uid"]))
				"add_inst":
					inv.add_instance(o["inst"])
				"credits":
					inv.credits += int(o["n"])
				"stock":
					var st: Dictionary = o["stock"]
					st[o["id"]] = int(st.get(o["id"], 0)) + int(o["n"])
					if int(st[o["id"]]) <= 0:
						st.erase(o["id"])
		Events.muted = muted
		return true
