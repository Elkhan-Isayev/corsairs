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
	# Rum: base 20, an export. Weapons: base 60, an import.
	assert_lt(rum_buy, 20, "export goods sell below base price")
	assert_gt(weapons_buy, 60, "import goods cost above base price")


func test_sell_price_below_buy_price() -> void:
	var m := _market()
	for g in ["rum", "weapons", "coffee", "provisions"]:
		assert_lt(m.sell_price(g, 0), m.buy_price(g, 0), "%s: market spread" % g)


func test_import_sells_high() -> void:
	var m := _market()
	assert_gt(m.sell_price("silk", 0), 90, "silk (import, base 90) fetches a premium")


func test_trade_skill_improves_prices() -> void:
	var m := _market()
	assert_lt(m.buy_price("coffee", 10), m.buy_price("coffee", 0), "a trader buys cheaper")
	assert_gt(m.sell_price("coffee", 10), m.sell_price("coffee", 0), "a trader sells dearer")


func test_player_buy_full_flow() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	var stock_before: int = m.stock["rum"]
	var price: int = m.buy_price("rum", 1)
	var spent: int = m.player_buy("rum", 10, c, ship, 1)
	assert_eq(spent, price * 10)
	assert_eq(c.gold, 900000 - spent)
	assert_eq(ship.cargo["rum"], 10)
	assert_eq(m.stock["rum"], stock_before - 10)


func test_player_buy_rejects_bad_orders() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("tartane")
	assert_eq(m.player_buy("rum", 0, c, ship, 1), -1, "zero volume")
	assert_eq(m.player_buy("rum", 99999, c, ship, 1), -1, "more than the warehouse holds")
	c.gold = 1
	assert_eq(m.player_buy("rum", 10, c, ship, 1), -1, "not enough gold")
	assert_eq(ship.cargo_used(), 0, "a failed deal leaves the hold untouched")


func test_player_sell_full_flow() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	ship.add_cargo("silk", 20)
	var price: int = m.sell_price("silk", 1)
	var income: int = m.player_sell("silk", 20, c, ship, 1)
	assert_eq(income, price * 20)
	assert_eq(c.gold, 900000 + income)
	assert_false(ship.cargo.has("silk"))
	assert_gt(m.stock["silk"], 0, "sold goods land in the warehouse")


func test_player_sell_without_cargo_fails() -> void:
	var m := _market()
	var c = Character.create()
	var ship = Ship.create("lugger")
	assert_eq(m.player_sell("silk", 5, c, ship, 1), -1)
	assert_eq(c.gold, 900000)


func test_scarcity_raises_price() -> void:
	var m := _market()
	m.stock["coffee"] = 0
	var scarce: int = m.buy_price("coffee", 0)
	m.stock["coffee"] = 400
	var plenty: int = m.buy_price("coffee", 0)
	assert_gt(scarce, plenty, "scarcity beats plenty")


func test_daily_tick_replenishes_exports() -> void:
	var m := _market()
	var rng := seeded_rng(7)
	m.stock["rum"] = 10
	for i in 10:
		m.daily_tick(rng)
	assert_gt(m.stock["rum"], 10, "export goods replenish")
	for g in m.stock:
		assert_between(m.stock[g], 0, 400)


func test_trade_profit_loop_exists() -> void:
	# The classic route: buy an export cheap, sell where it is an import.
	var producer := Market.create(["rum"], [], seeded_rng(1))
	var consumer := Market.create([], ["rum"], seeded_rng(2))
	var buy: int = producer.buy_price("rum", 0)
	var sell: int = consumer.sell_price("rum", 0)
	assert_gt(sell, buy, "the trade route is profitable: buy at %d, sell at %d" % [buy, sell])


func test_serialization_round_trip() -> void:
	var m := _market()
	m.stock["rum"] = 123
	var r = Market.from_dict(m.to_dict())
	assert_eq(r.stock["rum"], 123)
	assert_eq(r.exports, m.exports)
	assert_eq(r.imports, m.imports)
