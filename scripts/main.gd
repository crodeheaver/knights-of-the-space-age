extends Node
## Root of the application: switches between the main menu, character
## creator, the ship (World) and the ending screen.

func _ready() -> void:
	Game.main = self
	var errs := DB.validate()
	for e in errs:
		push_warning("DATA: " + e)
	print("Ashes of the Concord: data validated, %d issue(s)." % errs.size())
