class_name GameOverUI
extends PanelBase
## Entire active party is down: reload routes.


func build() -> void:
	var v := make_window("The party has fallen", Vector2(560, 420), false)
	v.add_child(UIKit.label("Every active party member is incapacitated. The Cinder Wake's corridors fall quiet.", 17, UIKit.TEXT, true))
	var latest := Saves.latest_slot()
	var b1 := UIKit.button("Load most recent save (%s)" % latest.replace("_", " ") if latest != "" else "No saves available", func() -> void: main.load_from_slot(latest))
	b1.disabled = latest == ""
	v.add_child(b1)
	v.add_child(UIKit.button("Choose a save to load", func() -> void: main.open_saveload("load")))
	v.add_child(UIKit.button("Main menu", func() -> void: main.show_main_menu()))
	v.add_child(UIKit.label("Tip: Story difficulty reduces incoming damage without removing tactics (Settings → Gameplay).", 14, UIKit.DIM, true))


func request_close() -> void:
	pass
