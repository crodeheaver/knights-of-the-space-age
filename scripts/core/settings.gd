extends Node
## Player settings and rebindable input. Stored in user://settings.cfg.

signal changed(key: String)

const PATH := "user://settings.cfg"

const DEFAULT_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"interact": [KEY_E], "pause": [KEY_SPACE], "switch_character": [KEY_TAB], "cycle_target": [KEY_R], "attack_target": [KEY_F],
	"toggle_stealth": [KEY_X], "swap_weapons": [KEY_Z], "clear_queue": [KEY_BACKSPACE], "party_hold": [KEY_G], "solo_mode": [KEY_H],
	"menu_character": [KEY_C], "menu_inventory": [KEY_I], "menu_journal": [KEY_J], "menu_map": [KEY_M], "menu_abilities": [KEY_K],
	"menu_party": [KEY_P], "toggle_log": [KEY_L], "quicksave": [KEY_F5], "quickload": [KEY_F9], "help": [KEY_F1], "dev_menu": [KEY_F12],
	"camera_left": [KEY_Q], "camera_right": [KEY_T], "menu": [KEY_ESCAPE], "rest": [KEY_V],
	"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4], "slot_5": [KEY_5],
	"slot_6": [KEY_6], "slot_7": [KEY_7], "slot_8": [KEY_8], "slot_9": [KEY_9], "slot_10": [KEY_0],
}
const ACTION_LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Strafe left", "move_right": "Strafe right",
	"interact": "Interact / talk", "pause": "Tactical pause", "switch_character": "Switch character", "cycle_target": "Cycle target",
	"attack_target": "Attack target", "toggle_stealth": "Toggle stealth", "swap_weapons": "Swap weapon set", "clear_queue": "Clear action queue",
	"party_hold": "Party: follow / hold", "solo_mode": "Solo mode", "menu_character": "Character sheet", "menu_inventory": "Inventory",
	"menu_journal": "Journal", "menu_map": "Map", "menu_abilities": "Abilities", "menu_party": "Party", "toggle_log": "Combat log",
	"quicksave": "Quicksave", "quickload": "Quickload", "help": "Controls help", "dev_menu": "Developer menu",
	"camera_left": "Rotate camera left", "camera_right": "Rotate camera right", "menu": "Menu / back", "rest": "Rest (out of combat)",
	"slot_1": "Action slot 1", "slot_2": "Action slot 2", "slot_3": "Action slot 3", "slot_4": "Action slot 4", "slot_5": "Action slot 5",
	"slot_6": "Action slot 6", "slot_7": "Action slot 7", "slot_8": "Action slot 8", "slot_9": "Action slot 9", "slot_10": "Action slot 10",
}

var values := {
	"master_volume": 0.8, "music_volume": 0.5, "sfx_volume": 0.8, "ambience_volume": 0.6, "ui_volume": 0.7,
	"mouse_sensitivity": 1.0, "invert_y": false, "ui_scale": 1.0, "subtitles": true, "reduce_shake": false,
	"reduce_flash": false, "difficulty": "standard", "autopause_combat_start": true, "autopause_member_down": true,
	"autopause_queue_empty": false, "autopause_target_dead": false, "tutorials": true, "hold_on_stealth": true,
	"fullscreen": false, "damage_numbers": true, "dev_mode": false, "edge_pan": false, "auto_attack": true,
	"voice_volume": 0.8, "text_speed": 45.0, "banter": "normal", "camera_mode": "follow", "camera_swing": true,
	"overhead_health": "combat",
}
var bindings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in DEFAULT_BINDINGS.keys():
		bindings[a] = (DEFAULT_BINDINGS[a] as Array).duplicate()
	load_settings()
	apply_bindings()
	apply_all()
	if OS.get_cmdline_user_args().has("--dev") or OS.get_cmdline_args().has("--dev"):
		values["dev_mode"] = true


func get_v(key: String) -> Variant:
	return values.get(key)


func set_v(key: String, v: Variant, save_now: bool = true) -> void:
	values[key] = v
	apply_one(key)
	changed.emit(key)
	if save_now:
		save_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in values.keys():
		if cf.has_section_key("settings", k):
			values[k] = cf.get_value("settings", k)
	for a in bindings.keys():
		if cf.has_section_key("bindings", a):
			var v: Variant = cf.get_value("bindings", a)
			if typeof(v) == TYPE_ARRAY:
				bindings[a] = v


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values.keys():
		cf.set_value("settings", k, values[k])
	for a in bindings.keys():
		cf.set_value("bindings", a, bindings[a])
	cf.save(PATH)


func apply_bindings() -> void:
	for a in bindings.keys():
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		for k in bindings[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(a, ev)


func rebind(action: String, keycode: int) -> String:
	## Returns the action that previously owned this key (it is unbound there).
	var stolen := ""
	for a in bindings.keys():
		if a != action and (bindings[a] as Array).has(keycode):
			(bindings[a] as Array).erase(keycode)
			stolen = a
	bindings[action] = [keycode]
	apply_bindings()
	save_settings()
	changed.emit("bindings")
	return stolen


func reset_bindings() -> void:
	for a in DEFAULT_BINDINGS.keys():
		bindings[a] = (DEFAULT_BINDINGS[a] as Array).duplicate()
	apply_bindings()
	save_settings()
	changed.emit("bindings")


func key_label(action: String) -> String:
	var ks: Array = bindings.get(action, [])
	if ks.is_empty():
		return "—"
	return OS.get_keycode_string(int(ks[0]))


func apply_all() -> void:
	for k in values.keys():
		apply_one(k)


func apply_one(key: String) -> void:
	match key:
		"ui_scale":
			if get_tree() and get_tree().root:
				get_tree().root.content_scale_factor = clampf(float(values["ui_scale"]), 0.6, 2.0)
		"fullscreen":
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if values["fullscreen"] else DisplayServer.WINDOW_MODE_WINDOWED)
		"master_volume", "music_volume", "sfx_volume", "ambience_volume", "ui_volume", "voice_volume":
			if has_node("/root/GameAudio"):
				get_node("/root/GameAudio").apply_volumes()
