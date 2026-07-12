extends "res://tests/test_case.gd"

const World := preload("res://core/world.gd")


func _world() -> RefCounted:
	return World.create(seeded_rng())


func test_archipelago_layout() -> void:
	assert_eq(World.island_ids().size(), 7, "семь островов")
	for id in World.island_ids():
		var isl := World.island(id)
		assert_true(World.NATIONS.has(isl["nation"]), id)
		assert_between(isl["tier"], 1, 3, id)
	assert_gt(World.distance("oxbay", "douwesen"), World.distance("oxbay", "redmond"))


func test_every_island_has_market() -> void:
	var w := _world()
	for id in World.island_ids():
		assert_true(w.markets.has(id), id)


func test_default_wars() -> void:
	var w := _world()
	assert_true(w.are_at_war("england", "spain"))
	assert_true(w.are_at_war("england", "france"))
	assert_false(w.are_at_war("england", "holland"))
	assert_true(w.are_at_war("pirates", "england"), "пираты воюют со всеми")
	assert_false(w.are_at_war("england", "england"))


func test_reputation_changes_clamped() -> void:
	var w := _world()
	w.change_reputation("spain", -500)
	assert_eq(w.reputation("spain"), -100)
	w.change_reputation("spain", 1000)
	assert_eq(w.reputation("spain"), 100)


func test_attack_hurts_victim_pleases_enemies() -> void:
	var w := _world()
	w.on_player_attacked("spain")
	assert_eq(w.reputation("spain"), -15, "жертва злится")
	assert_gt(w.reputation("england"), 0, "враг Испании доволен")
	assert_eq(w.reputation("france"), 0, "нейтралу всё равно")


func test_hostile_port_closed() -> void:
	var w := _world()
	assert_false(w.is_port_hostile("isla_muelle"))
	w.player_reputation["spain"] = -31
	assert_true(w.is_port_hostile("isla_muelle"), "порт закрыт при репутации < -30")
	assert_false(w.is_port_hostile("oxbay"), "английский порт открыт")


func test_serialization_round_trip() -> void:
	var w := _world()
	w.change_reputation("france", 42)
	w.market("oxbay").stock["rum"] = 77
	var r = World.from_dict(w.to_dict())
	assert_eq(r.reputation("france"), 42)
	assert_eq(r.market("oxbay").stock["rum"], 77)
	assert_true(r.are_at_war("england", "spain"))
