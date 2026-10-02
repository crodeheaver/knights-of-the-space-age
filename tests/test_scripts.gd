extends TestCase
## Every script in the project compiles. (A parse error in a screen that no
## other test touches would otherwise only show up when the game launches.)


func _gd_files(dir: String, out: Array[String]) -> void:
	for f in DirAccess.get_files_at(dir):
		if String(f).ends_with(".gd"):
			out.append(dir.path_join(String(f)))
	for d in DirAccess.get_directories_at(dir):
		_gd_files(dir.path_join(String(d)), out)


func test_all_scripts_compile() -> void:
	var files: Array[String] = []
	for root in ["res://scripts", "res://tests", "res://tools/godot"]:
		_gd_files(root, files)
	assert_true(files.size() > 40, "found %d scripts" % files.size())
	for p in files:
		var sc: Script = load(p)
		assert_true(sc != null and sc.can_instantiate(), "compiles: " + p)


func test_main_scene_instantiates() -> void:
	var ps: PackedScene = load(String(ProjectSettings.get_setting("application/run/main_scene")))
	assert_true(ps != null and ps.can_instantiate(), "main scene loads")
