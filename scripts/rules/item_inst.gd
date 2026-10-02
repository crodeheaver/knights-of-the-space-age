class_name ItemInst
extends RefCounted
## Helpers for unique (non-stackable) item instances: {uid, id, upgrades}.
## The uid counter is saved with the game so instance ids stay unique and
## deterministic across save/load.

static var counter: int = 0


static func new_uid() -> String:
	counter += 1
	return "it%d" % counter


static func make(id: String) -> Dictionary:
	return {"uid": new_uid(), "id": id, "upgrades": []}


static func normalize(v: Variant) -> Dictionary:
	var d: Dictionary = (v as Dictionary).duplicate(true)
	d["uid"] = String(d.get("uid", new_uid()))
	d["id"] = String(d.get("id", ""))
	var ups: Array = []
	for u in d.get("upgrades", []):
		ups.append(String(u))
	d["upgrades"] = ups
	return d


static func display_name(inst: Dictionary) -> String:
	var n := DB.item_name(String(inst.get("id", "")))
	var ups: Array = inst.get("upgrades", [])
	if not ups.is_empty():
		n += " +" + str(ups.size())
	return n


static func upgrade_slots(inst: Dictionary) -> int:
	return int(DB.item(String(inst.get("id", ""))).get("upgrade_slots", 0))
