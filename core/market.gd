## Colony market: prices depend on what the colony produces (cheap)
## and what it imports (expensive), and on current stock. Player
## purchases push prices up, sales push them down. The Trade skill
## improves the exchange rate for the player.
extends RefCounted

const Goods := preload("res://core/goods.gd")

var exports: Array = []   # produced locally — cheap, plentiful
var imports: Array = []   # brought in — expensive, bought eagerly
var stock := {}           # goods_id -> units in the warehouse


static func create(p_exports: Array, p_imports: Array, rng: RandomNumberGenerator) -> RefCounted:
	var m = load("res://core/market.gd").new()
	m.exports = p_exports.duplicate()
	m.imports = p_imports.duplicate()
	for g in Goods.all_ids():
		var base := 60
		if g in m.exports:
			base = 250
		elif g in m.imports:
			base = 15
		m.stock[g] = base + rng.randi_range(-10, 30)
	return m


## Price at which the colony SELLS one unit to the player.
func buy_price(goods_id: String, trade_skill: int) -> int:
	var base: int = Goods.get_type(goods_id)["base_price"]
	var mult := 1.0
	if goods_id in exports:
		mult = 0.55
	elif goods_id in imports:
		mult = 1.9
	# Warehouse scarcity drives the price up.
	var s := int(stock.get(goods_id, 0))
	var scarcity := clampf(1.6 - s / 200.0, 0.8, 1.6)
	var skill_discount := 1.0 - trade_skill * 0.015
	return maxi(int(round(base * mult * scarcity * skill_discount)), 1)


## Price at which the colony BUYS from the player (always below its ask).
func sell_price(goods_id: String, trade_skill: int) -> int:
	var base: int = Goods.get_type(goods_id)["base_price"]
	var mult := 0.8
	if goods_id in exports:
		mult = 0.35   # selling a colony its own produce is a bad deal
	elif goods_id in imports:
		mult = 1.5    # imported goods fetch a premium
	var s := int(stock.get(goods_id, 0))
	var scarcity := clampf(1.5 - s / 200.0, 0.7, 1.5)
	var skill_bonus := 1.0 + trade_skill * 0.015
	return maxi(int(round(base * mult * scarcity * skill_bonus)), 1)


## Player buys from the colony. Returns gold spent, or -1 on failure.
func player_buy(goods_id: String, units: int, character, ship, trade_skill: int) -> int:
	if units <= 0 or int(stock.get(goods_id, 0)) < units:
		return -1
	var cost := buy_price(goods_id, trade_skill) * units
	if not character.can_afford(cost):
		return -1
	if ship.cargo_free() < units:
		return -1
	character.spend(cost)
	ship.add_cargo(goods_id, units)
	stock[goods_id] = int(stock[goods_id]) - units
	return cost


## Player sells to the colony. Returns gold earned, or -1 on failure.
func player_sell(goods_id: String, units: int, character, ship, trade_skill: int) -> int:
	if units <= 0 or not ship.remove_cargo(goods_id, units):
		return -1
	var income := sell_price(goods_id, trade_skill) * units
	character.earn(income)
	stock[goods_id] = int(stock.get(goods_id, 0)) + units
	return income


## Daily market tick: exports replenish, imports get consumed.
func daily_tick(rng: RandomNumberGenerator) -> void:
	for g in stock:
		if g in exports:
			stock[g] = mini(int(stock[g]) + rng.randi_range(5, 15), 400)
		elif g in imports:
			stock[g] = maxi(int(stock[g]) - rng.randi_range(2, 8), 0)
		else:
			stock[g] = clampi(int(stock[g]) + rng.randi_range(-3, 3), 0, 200)


func to_dict() -> Dictionary:
	return {"exports": exports, "imports": imports, "stock": stock.duplicate()}


static func from_dict(d: Dictionary) -> RefCounted:
	var m = load("res://core/market.gd").new()
	m.exports = d["exports"].duplicate()
	m.imports = d["imports"].duplicate()
	m.stock = {}
	for k in d["stock"]:
		m.stock[k] = int(d["stock"][k])
	return m
