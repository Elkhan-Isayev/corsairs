extends "res://tests/test_case.gd"

const Ship := preload("res://core/ship.gd")
const Combat := preload("res://core/combat.gd")
const Ammo := preload("res://core/ammo.gd")


func _armed(type_id := "brig") -> RefCounted:
	var s = Ship.create(type_id)
	s.ammo_stock = {"balls": 500, "knippels": 500, "grapeshot": 500, "bombs": 500}
	return s


func test_range_depends_on_ammo() -> void:
	var balls := Combat.max_range(20, "balls")
	var grape := Combat.max_range(20, "grapeshot")
	var bombs := Combat.max_range(20, "bombs")
	assert_gt(balls, bombs, "cannonballs outrange bombs")
	assert_gt(bombs, grape, "bombs outrange grapeshot")


func test_range_depends_on_caliber() -> void:
	assert_gt(Combat.max_range(32, "balls"), Combat.max_range(12, "balls"))


func test_hit_chance_bounds() -> void:
	var range_limit := Combat.max_range(20, "balls")
	assert_eq(Combat.hit_chance(range_limit + 1.0, range_limit, 10, 10), 0.0, "out of range")
	var close := Combat.hit_chance(10.0, range_limit, 0, 0)
	var far := Combat.hit_chance(range_limit * 0.9, range_limit, 0, 0)
	assert_gt(close, far, "closer is more accurate")
	assert_lt(Combat.hit_chance(1.0, range_limit, 10, 10), 0.951, "chance is capped at 95%")


func test_broadside_deals_damage() -> void:
	var rng := seeded_rng()
	var att := _armed("brig")
	var def := _armed("brig")
	var hull_before: float = def.hull
	var report: Dictionary = Combat.fire_broadside(att, def, 100.0, {"accuracy": 5, "cannons": 5}, rng)
	assert_eq(report["fired"], 12, "full broadside (24/2)")
	assert_gt(report["hits"], 0, "point-blank shots must land")
	assert_lt(def.hull, hull_before, "hull damaged")
	assert_eq(att.reload_progress, 0.0, "reload starts after the volley")


func test_broadside_consumes_ammo() -> void:
	var rng := seeded_rng()
	var att := _armed("brig")
	att.ammo_stock["balls"] = 5
	var def := _armed("brig")
	var report: Dictionary = Combat.fire_broadside(att, def, 100.0, {}, rng)
	assert_eq(report["fired"], 5, "cannot fire more than the shot we carry")
	assert_eq(att.ammo_stock["balls"], 0)
	var report2: Dictionary = Combat.fire_broadside(att, def, 100.0, {}, rng)
	assert_eq(report2["fired"], 0)


func test_no_fire_while_reloading() -> void:
	var rng := seeded_rng()
	var att := _armed("brig")
	var def := _armed("brig")
	Combat.fire_broadside(att, def, 100.0, {}, rng)
	var second: Dictionary = Combat.fire_broadside(att, def, 100.0, {}, rng)
	assert_eq(second["fired"], 0, "no volley while reloading")


func test_no_fire_out_of_range() -> void:
	var rng := seeded_rng()
	var att := _armed("brig")
	var def := _armed("brig")
	var report: Dictionary = Combat.fire_broadside(att, def, 99999.0, {}, rng)
	assert_true(report["out_of_range"])
	assert_eq(report["fired"], 0)
	assert_eq(att.ammo_stock["balls"], 500, "no ammo wasted out of range")


func test_knippels_shred_sails_not_hull() -> void:
	var rng := seeded_rng()
	var att := _armed("frigate")
	att.current_ammo = "knippels"
	var def := _armed("frigate")
	# Several volleys for statistical weight.
	for i in 6:
		att.reload_progress = 1.0
		Combat.fire_broadside(att, def, 80.0, {"accuracy": 5}, rng)
	var hull_lost: float = def.spec()["hull"] - def.hull
	var sails_lost: float = def.spec()["sails"] - def.sails
	assert_gt(sails_lost, hull_lost * 0.5, "chain shot tears sails far more than hull")


func test_grapeshot_kills_crew() -> void:
	var rng := seeded_rng()
	var att := _armed("frigate")
	att.current_ammo = "grapeshot"
	var def := _armed("frigate")
	var crew_before: int = def.crew
	for i in 6:
		att.reload_progress = 1.0
		Combat.fire_broadside(att, def, 60.0, {"accuracy": 5}, rng)
	assert_lt(def.crew, crew_before, "grapeshot mows down the crew")


func test_reload_tick() -> void:
	var s := _armed("brig")
	s.reload_progress = 0.0
	var t := Combat.reload_time(s, 0)
	Combat.tick_reload(s, t / 2.0, 0)
	assert_almost_eq(s.reload_progress, 0.5, 0.01)
	Combat.tick_reload(s, t, 0)
	assert_eq(s.reload_progress, 1.0)


func test_reload_faster_with_skill_and_crew() -> void:
	var s := _armed("brig")
	var slow := Combat.reload_time(s, 0)
	var fast := Combat.reload_time(s, 10)
	assert_lt(fast, slow, "skill speeds up reloading")
	s.crew = int(s.spec()["max_crew"] * 0.3)
	assert_gt(Combat.reload_time(s, 0), slow, "a short-handed crew reloads slower")


func test_boarding_range() -> void:
	var def := _armed("brig")
	assert_true(Combat.can_board(50.0, def))
	assert_false(Combat.can_board(100.0, def))
	def.hull = 0.0
	assert_false(Combat.can_board(50.0, def), "cannot board a sinking ship")


func test_ammo_cycle() -> void:
	assert_eq(Ammo.next_type("balls"), "knippels")
	assert_eq(Ammo.next_type("bombs"), "balls", "the cycle wraps around")
