extends Node
## Headless test runner: godot --headless --path . res://tests/test_runner.tscn
## Runs every tests/test_*.gd (methods named test_*), prints a report and exits
## with code 1 on any failure. Results also go to user://test_results.txt.

const TEST_DIR := "res://tests/"

var total := 0
var failed := 0
var lines: PackedStringArray = []


func _ready() -> void:
	# Watchdog: a script error inside a test aborts that frame; never hang CI.
	var t := Timer.new()
	t.wait_time = 240.0
	t.one_shot = true
	t.timeout.connect(func() -> void:
		print("WATCHDOG: test run did not finish (script error?)")
		get_tree().quit(2))
	add_child(t)
	t.start()
	await get_tree().process_frame
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	var files: Array[String] = []
	for f in DirAccess.get_files_at(TEST_DIR):
		var fs := String(f)
		if fs.begins_with("test_") and fs.ends_with(".gd") and fs != "test_case.gd" and fs != "test_runner.gd":
			files.append(fs)
	files.sort()
	_out("Ashes of the Concord test suite — Godot %s" % Engine.get_version_info()["string"])
	for f in files:
		if only != "" and not f.contains(only):
			continue
		var script: GDScript = load(TEST_DIR + f)
		if script == null or not script.can_instantiate():
			_out("LOAD FAIL %s" % f)
			failed += 1
			continue
		var inst: Object = script.new()
		var methods: Array = []
		for m in inst.get_method_list():
			var mn := String(m["name"])
			if mn.begins_with("test_"):
				methods.append(mn)
		methods.sort()
		for mn in methods:
			total += 1
			inst.failures.clear()
			inst.current = mn
			Events.clear_history()
			Events.muted = false
			inst.before_each()
			inst.call(mn)
			if inst.failures.is_empty():
				_out("  PASS %s::%s" % [f, mn])
			else:
				failed += 1
				_out("  FAIL %s::%s" % [f, mn])
				for x in inst.failures:
					_out("       " + x)
	_out("")
	_out("RESULT: %d tests, %d passed, %d failed" % [total, total - failed, failed])
	var fa := FileAccess.open("user://test_results.txt", FileAccess.WRITE)
	if fa:
		fa.store_string("\n".join(lines))
		fa.close()
	get_tree().quit(1 if failed > 0 else 0)


func _out(s: String) -> void:
	print(s)
	lines.append(s)
