extends "res://tests/test_case.gd"

const Character := preload("res://core/character.gd")


func test_new_character() -> void:
	var c = Character.create("Nicholas", "france")
	assert_eq(c.level, 1)
	assert_eq(c.gold, 900000, "arcade starting purse")
	assert_eq(c.skill("navigation"), 1, "all skills start at 1")
	assert_eq(c.free_skill_points, 0)
	assert_eq(Character.SKILLS.size(), 10, "ten skills like the original")


func test_level_up() -> void:
	var c = Character.create()
	var res: Dictionary = c.add_xp(99)
	assert_eq(res["levels_gained"], 0, "level 2 takes 100 XP")
	res = c.add_xp(1)
	assert_eq(res["levels_gained"], 1)
	assert_eq(c.level, 2)
	assert_eq(c.free_skill_points, 2)
	assert_eq(c.max_hp, 90, "+10 HP per level")


func test_multi_level_up() -> void:
	var c = Character.create()
	# 100 (to 2) + 400 (to 3) = 500
	var res: Dictionary = c.add_xp(500)
	assert_eq(res["new_level"], 3)
	assert_eq(c.free_skill_points, 4)


func test_raise_skill_requires_points() -> void:
	var c = Character.create()
	assert_false(c.raise_skill("fencing"), "no free points yet")
	c.add_xp(100)
	assert_true(c.raise_skill("fencing"))
	assert_eq(c.skill("fencing"), 2)
	assert_eq(c.free_skill_points, 1)
	assert_false(c.raise_skill("nonsense"), "unknown skill")


func test_skill_cap() -> void:
	var c = Character.create()
	c.free_skill_points = 100
	for i in 20:
		c.raise_skill("luck")
	assert_eq(c.skill("luck"), Character.MAX_SKILL, "skills cap at 10")


func test_gold_operations() -> void:
	var c = Character.create()
	assert_true(c.spend(600))
	assert_eq(c.gold, 899400)
	assert_false(c.spend(899401), "cannot go negative")
	assert_eq(c.gold, 899400)
	c.earn(100)
	assert_eq(c.gold, 899500)


func test_squadron_grows_with_leadership() -> void:
	var c = Character.create()
	assert_eq(c.max_squadron(), 1)
	c.skills["leadership"] = 9
	assert_eq(c.max_squadron(), 4)


func test_serialization_round_trip() -> void:
	var c = Character.create("Jan", "holland")
	c.add_xp(777)
	c.raise_skill("trade")
	c.spend(300)
	var r = Character.from_dict(c.to_dict())
	assert_eq(r.char_name, "Jan")
	assert_eq(r.nation, "holland")
	assert_eq(r.level, c.level)
	assert_eq(r.xp, c.xp)
	assert_eq(r.skill("trade"), c.skill("trade"))
	assert_eq(r.gold, c.gold)
