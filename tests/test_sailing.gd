extends "res://tests/test_case.gd"

const Ship := preload("res://core/ship.gd")
const Sailing := preload("res://core/sailing.gd")


func test_wind_profile_dead_zone() -> void:
	assert_almost_eq(Sailing.wind_profile(0.0), 0.1, 0.01, "против ветра почти стоим")
	assert_almost_eq(Sailing.wind_profile(20.0), 0.1, 0.01)


func test_wind_profile_best_at_backstay() -> void:
	var backstay := Sailing.wind_profile(135.0)
	assert_almost_eq(backstay, 1.0, 0.01, "бакштаг — максимум")
	assert_gt(backstay, Sailing.wind_profile(90.0), "бакштаг быстрее галфвинда")
	assert_gt(backstay, Sailing.wind_profile(180.0), "бакштаг быстрее фордевинда")


func test_wind_profile_symmetric() -> void:
	assert_almost_eq(Sailing.wind_profile(120.0), Sailing.wind_profile(-120.0), 0.001, "левый и правый галс равны")


func test_speed_zero_with_furled_sails() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 0.0
	s.heading = 135.0
	assert_eq(Sailing.ship_speed(s, 0.0, 10.0, 5), 0.0)


func test_speed_full_sails_downwind() -> void:
	var s = Ship.create("lugger")  # base 12.5
	s.sail_setting = 1.0
	s.heading = 135.0  # ветер с севера, идём в бакштаг
	var v := Sailing.ship_speed(s, 0.0, 10.0, 0)
	assert_almost_eq(v, 12.5, 0.1, "полный ход в бакштаг при ветре 10")


func test_speed_drops_with_torn_sails() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 135.0
	var full := Sailing.ship_speed(s, 0.0, 10.0, 0)
	s.sails = s.spec()["sails"] / 2.0
	var torn := Sailing.ship_speed(s, 0.0, 10.0, 0)
	assert_almost_eq(torn, full / 2.0, 0.1, "порванные паруса режут скорость")


func test_navigation_skill_bonus() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 135.0
	var novice := Sailing.ship_speed(s, 0.0, 10.0, 0)
	var master := Sailing.ship_speed(s, 0.0, 10.0, 10)
	assert_almost_eq(master / novice, 1.2, 0.01, "+20% на максимуме навигации")


func test_no_speed_without_crew() -> void:
	var s = Ship.create("frigate")
	s.sail_setting = 1.0
	s.heading = 135.0
	s.crew = 5  # меньше min_crew=60
	assert_eq(Sailing.ship_speed(s, 0.0, 10.0, 5), 0.0, "без команды корабль стоит")


func test_turn_needs_speed() -> void:
	var s = Ship.create("brig")
	assert_eq(Sailing.turn_speed(s, 0.0, 0), 0.0, "без хода руль не работает")
	assert_gt(Sailing.turn_speed(s, 6.0, 0), Sailing.turn_speed(s, 2.0, 0))


func test_wind_drift_bounded() -> void:
	var rng := seeded_rng()
	var wind := {"from": 90.0, "strength": 8.0}
	for i in 200:
		wind = Sailing.drift_wind(wind["from"], wind["strength"], rng)
		assert_between(wind["from"], 0.0, 360.0)
		assert_between(wind["strength"], 2.0, 15.0)
