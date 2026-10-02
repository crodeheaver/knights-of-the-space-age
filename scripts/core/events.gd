extends Node
## Central event interface. Every gameplay system posts named events here; quests,
## tutorials, audio, UI and tests subscribe. Payloads are plain Dictionaries so
## they can be logged and replayed in tests.

signal event(name: String, data: Dictionary)
signal notify(text: String, kind: String)
signal combat_log(entry: Dictionary)
signal state_changed(what: String)

const HISTORY_MAX := 400
var history: Array = []
var muted := false


func post(name: String, data: Dictionary = {}) -> void:
	history.append({"name": name, "data": data})
	if history.size() > HISTORY_MAX:
		history.pop_front()
	if muted:
		return
	event.emit(name, data)


func toast(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)


func log_combat(text: String, detail: String = "", kind: String = "info") -> void:
	combat_log.emit({"text": text, "detail": detail, "kind": kind})


func changed(what: String) -> void:
	state_changed.emit(what)


func count(name: String) -> int:
	var n := 0
	for h in history:
		if h["name"] == name:
			n += 1
	return n


func clear_history() -> void:
	history.clear()
