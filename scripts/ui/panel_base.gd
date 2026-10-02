class_name PanelBase
extends Control
## Base for modal panels: full-screen dim + centred window, Esc closes.

var main: Node
var win: Dictionary = {}
var body: VBoxContainer


func _ready() -> void:
	theme = UIKit.theme()
	UIKit.full_rect(self)
	mouse_filter = Control.MOUSE_FILTER_STOP
	build()


func make_window(title: String, size: Vector2, closable: bool = true) -> VBoxContainer:
	win = UIKit.window(title, size, request_close if closable else Callable())
	add_child(win["root"])
	body = win["body"]
	return body


func build() -> void:
	pass


func request_close() -> void:
	if main != null:
		main.close_panel(self)
	else:
		queue_free()


func world() -> World:
	return Game.world as World
