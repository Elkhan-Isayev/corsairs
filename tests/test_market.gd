extends "res://tests/test_case.gd"

const Market := preload("res://core/market.gd")
const Ship := preload("res://core/ship.gd")
const Character := preload("res://core/character.gd")


func _market() -> RefCounted:
	return Market.create(["rum", "sugar"], ["weapons", "silk"], seeded_rng())


func test_export_cheap_import_expensive() -> void:
	var m := _market()
	var rum_buy: int = m.buy_price("rum", 0)
	var weapons_buy: int = m.buy_price("weapons", 0)
	# Ром: база 20, экспорт. Оружие: база 60, импорт.
	assert_lt(rum_buy, 20, "экспортный товар дешевле базы")
	assert_gt(weapons_buy, 60, "импортный товар дороже базы")


func test_sell_price_below_buy_price() -> void:
	var m := _market()
	for g in ["rum", "weapons", "coffee", "provisions"]:
		assert_lt(m.sell_price(g, 0), m.buy_price(g, 0), "%s: спред рынка" % g)


func test_import_sells_high() -> void:
	var m := _market()
	assert_gt(m.sell_price("silk", 0), 90, "шёлк (импорт, база 90) уходит с наценкой")


func test_trade_skill_improves_prices() -> void:
	var m := _market()
	assert_lt(m.buy_price("coffee", 10), m.buy_price("coffee", 0), "торговец покупает дешевле")
	assert_gt(m.sell_price("coffee", 10), m.sell_price("coffee", 0), "торговец продаёт дороже")


func test_player_buy_full_flow() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	var stock_before: int = m.stock["rum"]
	var price: int = m.buy_price("rum", 1)
	var spent: int = m.player_buy("rum", 10, c, ship, 1)
	assert_eq(spent, price * 10)
	assert_eq(c.gold, 1000 - spent)
	assert_eq(ship.cargo["rum"], 10)
	assert_eq(m.stock["rum"], stock_before - 10)


func test_player_buy_rejects_bad_orders() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("tartane")
	assert_eq(m.player_buy("rum", 0, c, ship, 1), -1, "нулевой объём")
	assert_eq(m.player_buy("rum", 99999, c, ship, 1), -1, "больше, чем на складе")
	c.gold = 1
	assert_eq(m.player_buy("rum", 10, c, ship, 1), -1, "не хватает золота")
	assert_eq(ship.cargo_used(), 0, "неудачная сделка не трогает трюм")


func test_player_sell_full_flow() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	ship.add_cargo("silk", 20)
	var price: int = m.sell_price("silk", 1)
	var income: int = m.player_sell("silk", 20, c, ship, 1)
	assert_eq(income, price * 20)
	assert_eq(c.gold, 1000 + income)
	assert_false(ship.cargo.has("silk"))
	assert_gt(m.stock["silk"], 0, "проданное попало на склад")


func test_player_sell_without_cargo_fails() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	assert_eq(m.player_sell("silk", 5, c, ship, 1), -1)
	assert_eq(c.gold, 1000)


func test_scarcity_raises_price() -> void:
	var m := _market()
	m.stock["coffee"] = 0
	var scarce: int = m.buy_price("coffee", 0)
	m.stock["coffee"] = 400
	var plenty: int = m.buy_price("coffee", 0)
	assert_gt(scarce, plenty, "дефицит дороже изобилия")


func test_daily_tick_replenishes_exports() -> void:
	var m := _market()
	var rng := seeded_rng(7)
	m.stock["rum"] = 10
	for i in 10:
		m.daily_tick(rng)
	assert_gt(m.stock["rum"], 10, "экспортный товар прирастает")
	for g in m.stock:
		assert_between(m.stock[g], 0, 400)


func test_trade_profit_loop_exists() -> void:
	# Классический маршрут: купить экспортное дёшево, продать туда, где это импорт.
	var producer := Market.create(["rum"], [], seeded_rng(1))
	var consumer := Market.create([], ["rum"], seeded_rng(2))
	var buy: int = producer.buy_price("rum", 0)
	var sell: int = consumer.sell_price("rum", 0)
	assert_gt(sell, buy, "торговый маршрут прибыльный: купить за %d, продать за %d" % [buy, sell])


func test_serialization_round_trip() -> void:
	var m := _market()
	m.stock["rum"] = 123
	var r = Market.from_dict(m.to_dict())
	assert_eq(r.stock["rum"], 123)
	assert_eq(r.exports, m.exports)
	assert_eq(r.imports, m.imports)
