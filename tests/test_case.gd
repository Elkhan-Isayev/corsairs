## Минимальный тестовый фреймворк: базовый класс теста с ассертами.
extends RefCounted

var failures: Array = []
var checks: int = 0
var _current: String = ""


func run() -> Dictionary:
	for m in get_method_list():
		var name: String = m["name"]
		if name.begins_with("test_"):
			_current = name
			call(name)
	return {"checks": checks, "failures": failures}


func _fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg := "") -> void:
	checks += 1
	if not cond:
		_fail("expected true. %s" % msg)


func assert_false(cond: bool, msg := "") -> void:
	checks += 1
	if cond:
		_fail("expected false. %s" % msg)


func assert_eq(got, expected, msg := "") -> void:
	checks += 1
	if got != expected:
		_fail("expected %s, got %s. %s" % [str(expected), str(got), msg])


func assert_ne(got, not_expected, msg := "") -> void:
	checks += 1
	if got == not_expected:
		_fail("expected != %s. %s" % [str(not_expected), msg])


func assert_gt(got, threshold, msg := "") -> void:
	checks += 1
	if not (got > threshold):
		_fail("expected %s > %s. %s" % [str(got), str(threshold), msg])


func assert_lt(got, threshold, msg := "") -> void:
	checks += 1
	if not (got < threshold):
		_fail("expected %s < %s. %s" % [str(got), str(threshold), msg])


func assert_between(got, lo, hi, msg := "") -> void:
	checks += 1
	if got < lo or got > hi:
		_fail("expected %s in [%s, %s]. %s" % [str(got), str(lo), str(hi), msg])


func assert_almost_eq(got: float, expected: float, tolerance := 0.001, msg := "") -> void:
	checks += 1
	if absf(got - expected) > tolerance:
		_fail("expected ~%s (±%s), got %s. %s" % [expected, tolerance, got, msg])


## Детерминированный RNG для воспроизводимых тестов.
func seeded_rng(seed_value: int = 12345) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng
