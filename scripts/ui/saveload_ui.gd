class_name SaveLoadUI
extends PanelBase
## Save and load screen. Lists quicksave, the rotating autosaves, manual slots
## and the end-of-intro save with their headers; corrupt or unreadable files
## are shown as such (and never crash the game). Overwrite and delete ask
## for confirmation.

var mode := "load"
var standalone := false
var _list: VBoxContainer
var _msg: Label
var _label_edit: LineEdit
var _confirm_slot := ""
var _confirm_kind := ""


func build() -> void:
	var v := make_window("Save Game" if mode == "save" else "Load Game", Vector2(1200, 840))
	if mode == "save":
		var why := Saves.block_reason()
		if why != "":
			v.add_child(UIKit.label("Saving is unavailable: " + why, 18, UIKit.WARN, true))
		var row := UIKit.hbox(8)
		row.add_child(UIKit.label("Label", 17))
		_label_edit = LineEdit.new()
		_label_edit.placeholder_text = "Optional description"
		_label_edit.max_length = 40
		_label_edit.custom_minimum_size = Vector2(420, 38)
		row.add_child(_label_edit)
		v.add_child(row)
	_list = UIKit.vbox(6)
	v.add_child(UIKit.scroll(_list))
	_msg = UIKit.label("", 16, UIKit.WARN, true)
	v.add_child(_msg)
	_render()


func _render() -> void:
	UIKit.clear(_list)
	for row in Saves.list_slots():
		var slot := String(row["slot"])
		if mode == "save" and not slot.begins_with("slot_"):
			continue
		if mode == "load" and bool(row.get("missing", false)):
			continue
		var h := UIKit.hbox(8)
		var p := UIKit.panel(h, UIKit.PANEL_LIGHT)
		_list.add_child(p)
		var info := UIKit.vbox(2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var title := slot.replace("_", " ").capitalize()
		if bool(row["ok"]):
			var hd: Dictionary = row["header"]
			info.add_child(UIKit.label("%s — %s%s" % [title, hd.get("label", ""), "  [DEV]" if bool(hd.get("dev", false)) else ""], 19, UIKit.ACCENT2))
			info.add_child(UIKit.label("%s · Level %d %s · %s · played %s · saved %s" % [hd.get("player", "?"), int(hd.get("level", 1)), hd.get("class", ""), hd.get("area_name", ""), _fmt_time(float(hd.get("play_time", 0))), String(hd.get("time", "")).replace("T", " ")], 15, UIKit.DIM))
			if String(row.get("reason", "")) != "":
				info.add_child(UIKit.label(String(row["reason"]), 14, UIKit.WARN))
		elif bool(row.get("missing", false)):
			info.add_child(UIKit.label("%s — empty" % title, 19, UIKit.DIM))
		else:
			info.add_child(UIKit.label("%s — unreadable" % title, 19, UIKit.BAD))
			info.add_child(UIKit.label(String(row.get("reason", "The file is damaged.")), 14, UIKit.BAD, true))
		if mode == "save":
			var sb := UIKit.button("Overwrite" if bool(row["ok"]) else "Save here", _save.bind(slot, bool(row["ok"])))
			sb.disabled = Saves.block_reason() != ""
			h.add_child(sb)
		else:
			var lb := UIKit.button("Load", _load.bind(slot))
			lb.disabled = not bool(row["ok"])
			h.add_child(lb)
		if not bool(row.get("missing", false)) and slot != "end_of_intro":
			h.add_child(UIKit.button("Delete", _delete.bind(slot)))
		if _confirm_slot == slot:
			var cb := UIKit.button("Confirm %s" % _confirm_kind, _confirmed.bind(slot))
			cb.add_theme_color_override("font_color", UIKit.WARN)
			h.add_child(cb)


func _save(slot: String, exists: bool) -> void:
	if exists and not (_confirm_slot == slot and _confirm_kind == "overwrite"):
		_confirm_slot = slot
		_confirm_kind = "overwrite"
		_msg.text = "Overwrite %s? Press Confirm." % slot.replace("_", " ")
		_render()
		return
	_do_save(slot)


func _do_save(slot: String) -> void:
	var r := Saves.save_game(slot, _label_edit.text.strip_edges() if _label_edit != null else "")
	_confirm_slot = ""
	if bool(r["ok"]):
		Events.toast("Game saved.", "save")
		request_close()
	else:
		_msg.text = "Save failed: " + String(r["reason"])
		_render()


func _load(slot: String) -> void:
	if main != null and main.has_method("load_from_slot"):
		main.load_from_slot(slot)
		if is_instance_valid(self) and is_inside_tree():
			request_close()


func _delete(slot: String) -> void:
	_confirm_slot = slot
	_confirm_kind = "delete"
	_msg.text = "Delete %s permanently? Press Confirm." % slot.replace("_", " ")
	_render()


func _confirmed(slot: String) -> void:
	if _confirm_kind == "delete":
		Saves.delete_slot(slot)
		_msg.text = "Deleted %s." % slot.replace("_", " ")
		_confirm_slot = ""
		_render()
	elif _confirm_kind == "overwrite":
		_do_save(slot)


func _fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 3600, (int(t) / 60) % 60] if t >= 3600 else "%d min" % (int(t) / 60)
