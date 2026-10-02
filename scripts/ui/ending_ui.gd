class_name EndingUI
extends Control
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
var main: Node


static func compute_outcome() -> Dictionary:
	return {}
