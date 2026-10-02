class_name SystemMenu
extends PanelBase
## Escape menu: resume, save/load, settings, main menu, quit.


func build() -> void:
	var v := make_window("Paused", Vector2(460, 560))
	v.add_child(UIKit.button("Resume", request_close))
	var reason := Saves.block_reason()
	var sb := UIKit.button("Save game", func() -> void: main.open_saveload("save"))
	if reason != "":
		sb.disabled = true
		sb.text = "Save game — " + reason
		sb.tooltip_text = reason
	v.add_child(sb)
	v.add_child(UIKit.button("Load game", func() -> void: main.open_saveload("load")))
	v.add_child(UIKit.button("Settings", func() -> void: main.open_settings()))
	v.add_child(UIKit.button("Journal & tutorials", func() -> void:
		main.close_panel(self)
		main.open_game_menu("journal")))
	v.add_child(UIKit.button("Controls", func() -> void:
		main.close_panel(self)
		main.open_game_menu("controls")))
	if Game.state.dev_mode or bool(Settings.get_v("dev_mode")):
		v.add_child(UIKit.button("Developer menu (F12)", func() -> void:
			main.close_panel(self)
			main.open_dev_menu()))
	v.add_child(UIKit.sep())
	v.add_child(UIKit.button("Quit to main menu", func() -> void: main.show_main_menu()))
	v.add_child(UIKit.button("Quit to desktop", func() -> void: get_tree().quit()))
