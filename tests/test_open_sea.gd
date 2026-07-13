extends "res://tests/test_case.gd"

const OpenSea := preload("res://core/open_sea.gd")
const World := preload("res://core/world.gd")
const GameState := preload("res://core/game_state.gd")


func test_island_positions_scale_with_chart() -> void:
	for id in World.island_ids():
		var chart: Array = World.island(id)["pos"]
		var p := OpenSea.island_pos(id)
		assert_eq(p.x, float(chart[0]) * OpenSea.SCALE, id)
		assert_eq(p.z, float(chart[1]) * OpenSea.SCALE, id)
		assert_eq(p.y, 0.0, "%s sits on the water" % id)
		assert_true(OpenSea.BOUNDS.has_point(Vector2(p.x, p.z)), "%s inside bounds" % id)


func test_nearest_island() -> void:
	assert_eq(OpenSea.nearest_island(OpenSea.island_pos("oxbay")), "oxbay")
	var near_douwesen := OpenSea.island_pos("douwesen") + Vector3(30, 0, -20)
	assert_eq(OpenSea.nearest_island(near_douwesen), "douwesen")


func test_dockable_only_within_radius() -> void:
	var isl := OpenSea.island_pos("redmond")
	assert_eq(OpenSea.dockable_island(isl + Vector3(OpenSea.ARRIVAL_RADIUS - 5.0, 0, 0)), "redmond")
	assert_eq(OpenSea.dockable_island(isl + Vector3(OpenSea.ARRIVAL_RADIUS + 40.0, 0, 0)), "", "too far out")


func test_island_collision_radius() -> void:
	for id in World.island_ids():
		assert_lt(OpenSea.island_radius(id), OpenSea.ARRIVAL_RADIUS,
			"%s: docking prompt must appear before the hull touches sand" % id)


func test_push_out_of_islands() -> void:
	var isl := OpenSea.island_pos("oxbay")
	var r := OpenSea.island_radius("oxbay")
	# Dead center: pushed out to the beach line.
	var out := OpenSea.push_out_of_islands(isl)
	assert_almost_eq(out.distance_to(isl), r, 0.1, "center pushed to the shore")
	# Just inside: pushed to exactly the radius.
	var inside := isl + Vector3(r - 5.0, 0, 0)
	out = OpenSea.push_out_of_islands(inside)
	assert_almost_eq(out.distance_to(isl), r, 0.1)
	# Open water stays put.
	var free := isl + Vector3(r + 40.0, 0, 0)
	assert_eq(OpenSea.push_out_of_islands(free), free)
	# No departure point may sit inside land.
	for id in World.island_ids():
		var p := OpenSea.departure_pos(id)
		assert_eq(OpenSea.push_out_of_islands(p), p, "%s: departure point is open water" % id)


func test_clamp_to_bounds() -> void:
	var p := OpenSea.clamp_to_bounds(Vector3(-9999, 0, 9999))
	assert_between(p.x, OpenSea.BOUNDS.position.x, OpenSea.BOUNDS.end.x)
	assert_between(p.z, OpenSea.BOUNDS.position.y, OpenSea.BOUNDS.end.y)
	var inside := Vector3(500, 0, 500)
	assert_eq(OpenSea.clamp_to_bounds(inside), inside, "inner points untouched")


func test_departure_pos_is_open_water() -> void:
	for id in World.island_ids():
		var p := OpenSea.departure_pos(id)
		assert_gt(p.distance_to(OpenSea.island_pos(id)), OpenSea.ARRIVAL_RADIUS, "%s: outside dock radius" % id)
		assert_true(OpenSea.BOUNDS.has_point(Vector2(p.x, p.z)), "%s: inside bounds" % id)
		for other in World.island_ids():
			if other != id:
				assert_gt(p.distance_to(OpenSea.island_pos(other)), OpenSea.ARRIVAL_RADIUS,
					"%s: departure from %s must not dock elsewhere" % [other, id])


func test_departure_heading_points_away() -> void:
	for id in World.island_ids():
		var h := OpenSea.departure_heading(id)
		assert_between(h, 0.0, 360.0, id)
		var fwd := Vector3(sin(deg_to_rad(h)), 0, -cos(deg_to_rad(h)))
		var away := (OpenSea.departure_pos(id) - OpenSea.island_pos(id)).normalized()
		assert_gt(fwd.dot(away), 0.99, "%s: heading matches the offshore direction" % id)


func test_day_distance_matches_voyage_pace() -> void:
	# Crossing oxbay -> redmond took ceil(dist/120) days on the old map;
	# sailing the same stretch in units must cost the same number of days.
	var units := OpenSea.island_pos("oxbay").distance_to(OpenSea.island_pos("redmond"))
	var days := int(ceil(units / OpenSea.DAY_DISTANCE))
	assert_eq(days, maxi(int(ceil(World.distance("oxbay", "redmond") / 120.0)), 1))


func test_depart_and_arrive() -> void:
	var g := GameState.new_game("Tester", "england", 42)
	assert_eq(g.current_island, "oxbay")
	g.depart()
	assert_eq(g.current_island, "", "at sea after casting off")
	var res: Dictionary = g.arrive("redmond")
	assert_eq(g.current_island, "redmond")
	assert_true(res.has("completed_quests"))


func test_sea_day_pays_wages_and_eats_provisions() -> void:
	var g := GameState.new_game("Tester", "england", 42)
	g.depart()
	var day0: int = g.day
	var gold0: int = g.character.gold
	var prov0: int = int(g.ship.cargo.get("provisions", 0))
	var log: Dictionary = g.sea_day()
	assert_eq(g.day, day0 + 1, "a day passed")
	assert_eq(int(log["wages_paid"]), g.ship.crew * GameState.CREW_WAGE_PER_DAY)
	assert_eq(g.character.gold, gold0 - int(log["wages_paid"]))
	assert_lt(int(g.ship.cargo.get("provisions", 0)), prov0, "crew ate")


func test_sea_encounter_rolls_are_valid() -> void:
	var g := GameState.new_game("Tester", "england", 7)
	for i in 20:
		var enc: Dictionary = g.roll_sea_encounter("isla_muelle")
		assert_true(World.NATIONS.has(enc["nation"]), "nation exists")
		assert_true(enc.has("ship_type") and enc.has("hostile"))


func test_arrival_completes_passenger_quest() -> void:
	var g := GameState.new_game("Tester", "england", 11)
	g.quests.accept({
		"id": 900, "kind": "passenger", "from": "oxbay", "to": "redmond",
		"reward": 500, "deadline_day": g.day + 30, "title": "Carry a passenger to Redmond",
	}, g.ship)
	var gold0: int = g.character.gold
	var res: Dictionary = g.arrive("redmond")
	assert_eq(res["completed_quests"].size(), 1, "passenger delivered on docking")
	assert_eq(g.character.gold, gold0 + 500, "reward paid on arrival")
