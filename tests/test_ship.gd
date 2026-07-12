extends "res://tests/test_case.gd"

const Ship := preload("res://core/ship.gd")
const ShipTypes := preload("res://core/ship_types.gd")


func test_create_ship_has_full_stats() -> void:
	var s = Ship.create("lugger")
	assert_eq(s.hull, 450.0, "lugger hull")
	assert_eq(s.crew, 40, "full crew")
	assert_eq(s.cannons, 8)
	assert_almost_eq(s.hull_frac(), 1.0)
	assert_false(s.is_sunk())
	assert_false(s.is_crew_critical())


func test_all_ship_types_valid() -> void:
	for id in ShipTypes.all_ids():
		var t := ShipTypes.get_type(id)
		assert_gt(t["hull"], 0, id)
		assert_gt(t["max_crew"], t["min_crew"], id)
		assert_gt(t["price"], 0, id)
		assert_between(t["rank"], 1, 7, id)


func test_shipyard_tiers() -> void:
	var small: Array = ShipTypes.available_for_shipyard(1)
	var big: Array = ShipTypes.available_for_shipyard(3)
	assert_true(small.has("lugger"), "small shipyard sells luggers")
	assert_false(small.has("frigate"), "small shipyard has no frigates")
	assert_true(big.has("manowar"), "capital shipyard sells everything")
	assert_gt(big.size(), small.size())


func test_cargo_limits() -> void:
	var s = Ship.create("tartane")  # hold 250
	assert_true(s.add_cargo("rum", 200))
	assert_eq(s.cargo_free(), 50)
	assert_false(s.add_cargo("sugar", 51), "hold overflow")
	assert_true(s.add_cargo("sugar", 50))
	assert_eq(s.cargo_free(), 0)
	assert_false(s.remove_cargo("coffee", 1), "no such goods aboard")
	assert_true(s.remove_cargo("rum", 200))
	assert_false(s.cargo.has("rum"), "empty entry is removed")


func test_damage_and_sinking() -> void:
	var s = Ship.create("sloop")
	s.apply_damage(100.0, 50.0, 10, 2)
	assert_eq(s.hull, 600.0)
	assert_eq(s.sails, 150.0)
	assert_eq(s.crew, 60)
	assert_eq(s.cannons, 10)
	s.apply_damage(9999.0, 0.0, 0, 0)
	assert_true(s.is_sunk())
	assert_eq(s.hull, 0.0, "hull never goes negative")


func test_crew_critical() -> void:
	var s = Ship.create("frigate")  # min_crew 60
	s.crew = 59
	assert_true(s.is_crew_critical())
	s.crew = 60
	assert_false(s.is_crew_critical())


func test_field_repair_caps_at_85_percent() -> void:
	var s = Ship.create("brig")  # hull 1400
	s.hull = 100.0
	s.sails = 0.0
	var used: Dictionary = s.field_repair(1000, 1000)
	assert_almost_eq(s.hull, 1400.0 * 0.85, 0.01, "field hull repair caps at 85%")
	assert_eq(s.sails, 350.0, "sails repair fully")
	assert_gt(used["planks"], 0)
	assert_gt(used["sailcloth"], 0)


func test_broadside_guns_halved() -> void:
	var s = Ship.create("galleon")  # 32 cannons
	assert_eq(s.broadside_guns(), 16)
	s.cannons = 7
	assert_eq(s.broadside_guns(), 3)


func test_serialization_round_trip() -> void:
	var s = Ship.create("schooner", "Swallow")
	s.apply_damage(123.0, 45.0, 7, 1)
	s.add_cargo("silk", 33)
	s.ammo_stock["bombs"] = 17
	var restored = Ship.from_dict(s.to_dict())
	assert_eq(restored.custom_name, "Swallow")
	assert_eq(restored.hull, s.hull)
	assert_eq(restored.crew, s.crew)
	assert_eq(restored.cargo["silk"], 33)
	assert_eq(restored.ammo_stock["bombs"], 17)
