extends "res://tests/test_case.gd"

const GameState := preload("res://core/game_state.gd")


func _game(seed_value := 42) -> RefCounted:
	return GameState.new_game("Тест", "england", seed_value)


func test_new_game_setup() -> void:
	var g := _game()
	assert_eq(g.day, 1)
	assert_eq(g.current_island, "oxbay")
	assert_eq(g.ship.type_id, "lugger")
	assert_gt(g.ship.ammo_stock["balls"], 0)
	assert_gt(int(g.ship.cargo.get("provisions", 0)), 0, "стартовая провизия")
	assert_eq(g.character.nation, "england")


func test_pirate_starts_at_pirate_island() -> void:
	var g = GameState.new_game("Флибустьер", "pirates", 1)
	assert_eq(g.current_island, "quebradas")


func test_sail_advances_time_and_arrives() -> void:
	var g := _game()
	var gold_before: int = g.character.gold
	var log: Dictionary = g.sail_to("redmond")
	assert_eq(g.current_island, "redmond")
	assert_gt(g.day, 1, "время идёт")
	assert_eq(log["days"], g.day - 1)
	assert_lt(g.character.gold, gold_before, "жалование уплачено")


func test_sail_consumes_provisions() -> void:
	var g := _game()
	var prov_before: int = g.ship.cargo["provisions"]
	g.sail_to("douwesen")  # дальний переход
	assert_lt(int(g.ship.cargo.get("provisions", 0)), prov_before)


func test_starvation_kills_crew() -> void:
	var g := _game()
	g.ship.remove_cargo("provisions", int(g.ship.cargo["provisions"]))
	var crew_before: int = g.ship.crew
	g.sail_to("douwesen")
	assert_lt(g.ship.crew, crew_before, "без провизии команда мрёт")


func test_no_gold_causes_desertion() -> void:
	var g := _game()
	g.character.gold = 0
	var crew_before: int = g.ship.crew
	g.sail_to("redmond")
	assert_lt(g.ship.crew, crew_before, "без жалования команда дезертирует")


func test_encounters_are_reproducible_and_valid() -> void:
	var g := _game(777)
	var found := false
	for i in 20:
		var dest: String = "redmond" if g.current_island != "redmond" else "oxbay"
		var log: Dictionary = g.sail_to(dest)
		if log["encounter"] != null:
			found = true
			var e: Dictionary = log["encounter"]
			assert_true(e.has("nation") and e.has("ship_type") and e.has("hostile"))
			var enemy = g.spawn_encounter_ship(e)
			assert_gt(enemy.crew, 0)
			assert_gt(enemy.ammo_stock["balls"], 0)
	assert_true(found, "за 20 переходов хоть одна встреча")


func test_pirates_always_hostile() -> void:
	var g := _game()
	for i in 50:
		var e: Dictionary = g._roll_encounter("redmond")
		if e["nation"] == "pirates":
			assert_true(e["hostile"], "пираты всегда враждебны")


func test_sunk_enemy_gives_xp_and_reputation_hit() -> void:
	var g := _game()
	var enemy = g.spawn_encounter_ship({"nation": "spain", "ship_type": "barque", "hostile": true})
	var xp_before: int = g.character.xp
	g.on_enemy_sunk(enemy, "spain")
	assert_gt(g.character.xp + g.character.level * 0, xp_before, "опыт получен")
	assert_lt(g.world.reputation("spain"), 0, "Испания в ярости")
	assert_gt(g.world.reputation("england"), 0, "Англия довольна")


func test_hire_crew() -> void:
	var g := _game()
	g.ship.crew = 10
	var gold_before: int = g.character.gold
	assert_true(g.hire_crew(20))
	assert_eq(g.ship.crew, 30)
	assert_eq(g.character.gold, gold_before - 20 * GameState.CREW_HIRE_COST)
	assert_false(g.hire_crew(9999), "больше максимума не нанять")
	g.character.gold = 0
	assert_false(g.hire_crew(1), "нет денег — нет матросов")


func test_shipyard_repair() -> void:
	var g := _game()
	g.character.gold = 100000
	g.ship.apply_damage(200.0, 50.0, 0, 2)
	var cost: int = g.repair_ship_at_shipyard()
	assert_gt(cost, 0)
	assert_almost_eq(g.ship.hull_frac(), 1.0)
	assert_eq(g.ship.cannons, int(g.ship.spec()["cannons"]))
	assert_eq(g.repair_ship_at_shipyard(), 0, "чинить нечего")
	g.ship.apply_damage(500.0, 0.0, 0, 0)
	g.character.gold = 1
	assert_eq(g.repair_ship_at_shipyard(), -1, "нет денег на ремонт")


func test_buy_ship_with_trade_in() -> void:
	var g := _game()
	g.character.gold = 20000
	g.ship.add_cargo("rum", 50)
	assert_true(g.buy_ship("schooner"))
	assert_eq(g.ship.type_id, "schooner")
	assert_eq(int(g.ship.cargo.get("rum", 0)), 50, "груз переехал")
	assert_lt(g.character.gold, 20000, "заплатили разницу")
	g.character.gold = 0
	assert_false(g.buy_ship("manowar"), "мановар не по карману")


func test_buy_ammo() -> void:
	var g := _game()
	var before: int = g.ship.ammo_stock["bombs"]
	assert_true(g.buy_ammo("bombs", 30, 6))
	assert_eq(g.ship.ammo_stock["bombs"], before + 30)
	g.character.gold = 0
	assert_false(g.buy_ammo("bombs", 10, 6))


func test_save_load_round_trip() -> void:
	var g := _game()
	g.sail_to("redmond")
	g.character.add_xp(250)
	g.world.change_reputation("france", -20)
	var path := "user://test_save.json"
	assert_true(g.save_to_file(path))
	var loaded = GameState.load_from_file(path)
	assert_ne(loaded, null)
	assert_eq(loaded.day, g.day)
	assert_eq(loaded.current_island, "redmond")
	assert_eq(loaded.character.xp, g.character.xp)
	assert_eq(loaded.character.level, g.character.level)
	assert_eq(loaded.world.reputation("france"), -20)
	assert_eq(loaded.ship.crew, g.ship.crew)
	assert_almost_eq(loaded.wind["from"], g.wind["from"], 0.01)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_load_missing_save_returns_null() -> void:
	assert_eq(GameState.load_from_file("user://no_such_save.json"), null)


func test_full_playthrough_smoke() -> void:
	# Мини-прохождение: торговый рейс + бой + абордаж, всё на одном сиде.
	var Combat := preload("res://core/combat.gd")
	var Boarding := preload("res://core/boarding.gd")
	var g := _game(2026)
	var m = g.world.market("oxbay")
	# Закупаем ром в Оксбее (экспорт — дёшево).
	var spent: int = m.player_buy("rum", 40, g.character, g.ship, g.character.skill("trade"))
	assert_gt(spent, 0)
	# Везём в Дувесен (там ром — импорт).
	g.sail_to("douwesen")
	var m2 = g.world.market("douwesen")
	var income: int = m2.player_sell("rum", 40, g.character, g.ship, g.character.skill("trade"))
	assert_gt(income, spent, "торговый рейс прибыльный")
	# Бой с пиратом.
	var enemy = g.spawn_encounter_ship({"nation": "pirates", "ship_type": "sloop", "hostile": true})
	var rounds := 0
	while not enemy.is_sunk() and rounds < 100:
		rounds += 1
		g.ship.reload_progress = 1.0
		Combat.fire_broadside(g.ship, enemy, 120.0, {"accuracy": 3, "cannons": 3}, g.rng)
		if Combat.can_board(50.0, enemy) and enemy.crew > 0 and rounds > 3:
			var res: Dictionary = Boarding.resolve(g.ship, {"boarding": 3, "fencing": 3}, enemy, {}, g.rng)
			if res["winner"] == "attacker":
				break
	assert_true(enemy.is_sunk() or enemy.crew <= int(enemy.spec()["max_crew"] * 0.3) or rounds < 100, "враг побеждён")
