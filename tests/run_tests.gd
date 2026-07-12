## Headless-раннер: godot --headless --path . -s tests/run_tests.gd
extends SceneTree

const TEST_DIR := "res://tests/"


func _initialize() -> void:
	var total_checks := 0
	var total_failures: Array = []
	var suites := 0

	var dir := DirAccess.open(TEST_DIR)
	var files := []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd":
			files.append(f)
		f = dir.get_next()
	files.sort()

	for file in files:
		var script = load(TEST_DIR + file)
		var suite = script.new()
		var result: Dictionary = suite.run()
		suites += 1
		total_checks += result["checks"]
		if result["checks"] == 0:
			result["failures"].append("suite ran 0 checks (compile error?)")
		var mark := "✓" if result["failures"].is_empty() else "✗"
		print("%s %s — %d checks, %d failures" % [mark, file, result["checks"], result["failures"].size()])
		for failure in result["failures"]:
			print("    FAIL %s" % failure)
			total_failures.append("%s :: %s" % [file, failure])

	print("")
	print("Suites: %d | Checks: %d | Failures: %d" % [suites, total_checks, total_failures.size()])
	if total_failures.is_empty():
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("TESTS FAILED")
		quit(1)
