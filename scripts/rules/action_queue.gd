class_name ActionQueue
extends RefCounted
## Per-character queue of up to four pending actions. Actions are
## Dictionaries: {qid, type: attack|feat|power|item|swap|form|interact, id,
## target (uid) or point [x,z], manual: bool}. Queue operations work the same
## whether the simulation is paused or running.

const MAX := 4

var items: Array = []
var _next := 1


func size() -> int:
	return items.size()


func is_empty() -> bool:
	return items.is_empty()


func is_full() -> bool:
	return items.size() >= MAX


func push(action: Dictionary) -> Dictionary:
	if is_full():
		return {}
	var a := action.duplicate(true)
	a["qid"] = _next
	_next += 1
	items.append(a)
	return a


func front() -> Dictionary:
	return items[0] if not items.is_empty() else {}


func pop_front() -> Dictionary:
	if items.is_empty():
		return {}
	return items.pop_front()


func cancel(qid: int) -> bool:
	for i in items.size():
		if int(items[i]["qid"]) == qid:
			items.remove_at(i)
			return true
	return false


func cancel_index(i: int) -> bool:
	if i < 0 or i >= items.size():
		return false
	items.remove_at(i)
	return true


## Moves the entry at index i by delta (-1 = earlier). Returns success.
func move(i: int, delta: int) -> bool:
	var j := i + delta
	if i < 0 or i >= items.size() or j < 0 or j >= items.size():
		return false
	var tmp: Variant = items[i]
	items[i] = items[j]
	items[j] = tmp
	return true


func clear() -> void:
	items.clear()


## Removes the basic attacks the game queued on its own (auto_queued), e.g.
## because the player chose an action or a move of their own.
func remove_auto() -> int:
	var n := 0
	for i in range(items.size() - 1, -1, -1):
		if bool(items[i].get("auto_queued", false)):
			items.remove_at(i)
			n += 1
	return n


## Points auto-queued attacks at a new target (the player re-selected).
func retarget_auto(uid: String) -> void:
	for it in items:
		if bool(it.get("auto_queued", false)):
			it["target"] = uid


## Removes actions that target the given uid (e.g. the target died).
func purge_target(uid: String) -> int:
	var n := 0
	for i in range(items.size() - 1, -1, -1):
		if String(items[i].get("target", "")) == uid:
			items.remove_at(i)
			n += 1
	return n


func to_array() -> Array:
	return items.duplicate(true)


func from_array(arr: Array) -> void:
	items = []
	for a in arr:
		var d: Dictionary = (a as Dictionary).duplicate(true)
		d["qid"] = int(d.get("qid", _next))
		items.append(d)
		_next = maxi(_next, int(d["qid"]) + 1)
