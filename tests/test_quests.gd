extends "res://tests/test_case.gd"

const Quests := preload("res://core/quests.gd")
const Ship := preload("res://core/ship.gd")


func test_generate_offer_valid() -> void:
	var q = Quests.new()
	var rng := seeded_rng()
	for i in 30:
		var offer: Dictionary = q.generate_offer("oxbay", 1, rng)
		assert_ne(offer["to"], "oxbay", "the quest leads to another island")
		assert_gt(offer["reward"], 0)
		assert_gt(offer["deadline_day"], 1)
		assert_true(offer["kind"] in ["deliver", "hunt", "passenger"])


func test_deliver_quest_full_cycle() -> void:
	var q = Quests.new()
	var rng := seeded_rng(3)
	var ship = Ship.create("galleon")
	var offer: Dictionary
	# Roll the generator until we get a delivery quest.
	while true:
		offer = q.generate_offer("oxbay", 1, rng)
		if offer["kind"] == "deliver":
			break
	assert_true(q.accept(offer, ship))
	assert_eq(ship.cargo[offer["goods"]], offer["units"], "cargo loaded")
	assert_eq(q.active.size(), 1)
	# Arriving at the wrong island completes nothing.
	var wrong: Array = q.check_completion({"type": "arrived", "island": "nowhere"}, 2, ship)
	assert_eq(wrong.size(), 0)
	# Arriving at the destination completes the quest.
	var done: Array = q.check_completion({"type": "arrived", "island": offer["to"]}, 2, ship)
	assert_eq(done.size(), 1)
	assert_eq(q.active.size(), 0)
	assert_false(ship.cargo.has(offer["goods"]), "cargo unloaded")


func test_deliver_needs_cargo_space() -> void:
	var q = Quests.new()
	var rng := seeded_rng(3)
	var ship = Ship.create("tartane")
	ship.add_cargo("rum", 250)  # hold is full
	var offer: Dictionary
	while true:
		offer = q.generate_offer("oxbay", 1, rng)
		if offer["kind"] == "deliver":
			break
	assert_false(q.accept(offer, ship), "no space — cannot take the quest")


func test_hunt_quest_completion() -> void:
	var q = Quests.new()
	var rng := seeded_rng(5)
	var offer: Dictionary
	while true:
		offer = q.generate_offer("redmond", 1, rng)
		if offer["kind"] == "hunt":
			break
	q.accept(offer)
	var wrong: Array = q.check_completion({"type": "sunk_pirate", "ship_type": "manowar"}, 2)
	assert_eq(wrong.size(), 0, "not the target ship")
	var done: Array = q.check_completion({"type": "sunk_pirate", "ship_type": offer["target_ship"]}, 2)
	assert_eq(done.size(), 1)


func test_expired_quest_removed() -> void:
	var q = Quests.new()
	var rng := seeded_rng(9)
	var offer: Dictionary = q.generate_offer("oxbay", 1, rng)
	q.accept(offer)
	var expired: Array = q.expire(int(offer["deadline_day"]) + 1)
	assert_eq(expired.size(), 1)
	assert_eq(q.active.size(), 0)


func test_late_arrival_no_reward() -> void:
	var q = Quests.new()
	var rng := seeded_rng(11)
	var offer: Dictionary
	while true:
		offer = q.generate_offer("oxbay", 1, rng)
		if offer["kind"] == "passenger":
			break
	q.accept(offer)
	var done: Array = q.check_completion({"type": "arrived", "island": offer["to"]}, int(offer["deadline_day"]) + 5)
	assert_eq(done.size(), 0, "too late — no reward")


func test_serialization_round_trip() -> void:
	var q = Quests.new()
	var rng := seeded_rng(13)
	q.accept(q.generate_offer("oxbay", 1, rng))
	q.accept(q.generate_offer("redmond", 1, rng))
	var r = Quests.from_dict(q.to_dict())
	assert_eq(r.active.size(), 2)
	assert_eq(r.next_id, q.next_id)
