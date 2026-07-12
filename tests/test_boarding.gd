extends "res://tests/test_case.gd"

const Ship := preload("res://core/ship.gd")
const Boarding := preload("res://core/boarding.gd")


func test_fight_round_losses_bounded() -> void:
	var rng := seeded_rng()
	for i in 50:
		var r: Dictionary = Boarding.fight_round(100, 3, 3, 80, 2, 2, rng)
		assert_between(r["att_losses"], 1, 100)
		assert_between(r["def_losses"], 1, 80)


func test_overwhelming_force_wins() -> void:
	var rng := seeded_rng()
	var att = Ship.create("frigate")   # 400 men
	var def = Ship.create("tartane")   # 15 men
	var res: Dictionary = Boarding.resolve(att, {"boarding": 8, "fencing": 8}, def, {}, rng)
	assert_eq(res["winner"], "attacker", "400 fighters must beat 15")
	assert_lt(res["att_losses"], 60, "losses are small with an overwhelming edge")


func test_tiny_crew_loses_to_big() -> void:
	var rng := seeded_rng()
	var att = Ship.create("tartane")
	var def = Ship.create("frigate")
	var res: Dictionary = Boarding.resolve(att, {}, def, {"boarding": 5}, rng)
	assert_eq(res["winner"], "defender")


func test_skills_matter_in_even_fight() -> void:
	# With equal numbers, the side with maxed boarding wins more often.
	var wins := 0
	var trials := 30
	for i in trials:
		var rng := seeded_rng(1000 + i)
		var att = Ship.create("brig")
		var def = Ship.create("brig")
		var res: Dictionary = Boarding.resolve(att, {"boarding": 10, "fencing": 10}, def, {"boarding": 0, "fencing": 0}, rng)
		if res["winner"] == "attacker":
			wins += 1
	assert_gt(wins, trials * 0.7, "a boarding master wins most even fights (wins: %d/%d)" % [wins, trials])


func test_resolve_terminates() -> void:
	var rng := seeded_rng()
	var att = Ship.create("manowar")
	var def = Ship.create("manowar")
	var res: Dictionary = Boarding.resolve(att, {}, def, {}, rng)
	assert_between(res["rounds"], 1, 50, "the fight always ends")


func test_loot_contains_cargo_and_gold() -> void:
	var rng := seeded_rng()
	var prize = Ship.create("galleon")
	prize.add_cargo("silk", 40)
	var l: Dictionary = Boarding.loot(prize, rng)
	assert_gt(l["gold"], 0)
	assert_eq(l["cargo"]["silk"], 40)
