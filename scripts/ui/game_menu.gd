class_name GameMenu
extends PanelBase
## (temporary minimal version — replaced in a later increment)

var main_ref: Node
var mode := ""
var standalone := false
var uid := ""
var vendor_id := ""
var station := ""
var crafter_uid := ""
var outcome: Dictionary = {}
var saved := false


func show_tab(_t: String) -> void:
	pass
