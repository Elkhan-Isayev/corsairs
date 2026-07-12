extends "res://tests/test_case.gd"

const Ship := preload("res://core/ship.gd")
const Sailing := preload("res://core/sailing.gd")


func test_wind_profile_arcade_never_stalls() -> void:
	# Arcade model: even dead upwind the ship keeps at least 75% speed.
	assert_almost_eq(Sailing.wind_profile(0.0), 0.75, 0.01, "mild upwind penalty")
	for a in range(0, 181, 10):
		assert_between(Sailing.wind_profile(a), 0.75, 1.0, "angle %d" % a)


func test_wind_profile_best_at_broad_reach() -> void:
	var broad_reach := Sailing.wind_profile(135.0)
	assert_almost_eq(broad_reach, 1.0, 0.01, "broad reach is the maximum")
	assert_gt(broad_reach, Sailing.wind_profile(90.0), "broad reach beats beam reach")
	assert_gt(broad_reach, Sailing.wind_profile(180.0), "broad reach beats running")


func test_wind_profile_symmetric() -> void:
	assert_almost_eq(Sailing.wind_profile(120.0), Sailing.wind_profile(-120.0), 0.001, "port and starboard tacks are equal")


func test_speed_zero_with_furled_sails() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 0.0
	s.heading = 135.0
	assert_eq(Sailing.ship_speed(s, 0.0, 10.0, 5), 0.0)


func test_speed_full_sails_downwind() -> void:
	var s = Ship.create("lugger")  # base 12.5
	s.sail_setting = 1.0
	s.heading = 135.0  # wind from the north, sailing on a broad reach
	var v := Sailing.ship_speed(s, 0.0, 10.0, 0)
	assert_almost_eq(v, 12.5, 0.1, "full speed on a broad reach in a 10-knot wind")


func test_wind_strength_barely_matters() -> void:
	# Arcade: a near-calm and a gale differ by no more than ~20%.
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 135.0
	var calm := Sailing.ship_speed(s, 0.0, 2.0, 0)
	var gale := Sailing.ship_speed(s, 0.0, 15.0, 0)
	assert_gt(calm, gale * 0.8, "calm keeps at least 80%% of gale speed")


func test_upwind_still_sails_fast() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 0.0  # dead upwind
	var v := Sailing.ship_speed(s, 0.0, 10.0, 0)
	assert_gt(v, 12.5 * 0.7, "upwind course keeps a normal arcade speed")


func test_speed_drops_with_torn_sails() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 135.0
	var full := Sailing.ship_speed(s, 0.0, 10.0, 0)
	s.sails = s.spec()["sails"] / 2.0
	var torn := Sailing.ship_speed(s, 0.0, 10.0, 0)
	assert_almost_eq(torn, full / 2.0, 0.1, "torn sails cut the speed")


func test_navigation_skill_bonus() -> void:
	var s = Ship.create("lugger")
	s.sail_setting = 1.0
	s.heading = 135.0
	var novice := Sailing.ship_speed(s, 0.0, 10.0, 0)
	var master := Sailing.ship_speed(s, 0.0, 10.0, 10)
	assert_almost_eq(master / novice, 1.2, 0.01, "+20% at maximum navigation")


func test_no_speed_without_crew() -> void:
	var s = Ship.create("frigate")
	s.sail_setting = 1.0
	s.heading = 135.0
	s.crew = 5  # below min_crew=60
	assert_eq(Sailing.ship_speed(s, 0.0, 10.0, 5), 0.0, "no crew — dead in the water")


func test_turn_needs_speed() -> void:
	var s = Ship.create("brig")
	assert_eq(Sailing.turn_speed(s, 0.0, 0), 0.0, "the rudder is useless without way")
	assert_gt(Sailing.turn_speed(s, 6.0, 0), Sailing.turn_speed(s, 2.0, 0))


func test_wind_drift_bounded() -> void:
	var rng := seeded_rng()
	var wind := {"from": 90.0, "strength": 8.0}
	for i in 200:
		wind = Sailing.drift_wind(wind["from"], wind["strength"], rng)
		assert_between(wind["from"], 0.0, 360.0)
		assert_between(wind["strength"], 2.0, 15.0)
