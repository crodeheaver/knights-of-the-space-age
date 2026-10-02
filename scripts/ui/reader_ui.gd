class_name ReaderUI
extends PanelBase
## Readable logs and discoveries (also listed in Journal → Discoveries).

var data: Dictionary = {}


func build() -> void:
	var v := make_window(String(data.get("title", "Log")), Vector2(820, 600))
	if bool(data.get("first", false)):
		v.add_child(UIKit.label("New discovery recorded in your journal.", 15, UIKit.GOOD))
	var r := UIKit.rich(String(data.get("text", "")), 18, false)
	r.custom_minimum_size = Vector2(760, 440)
	v.add_child(r)
