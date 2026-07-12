## Рынок колонии: цены зависят от того, что колония производит (дёшево)
## и что ввозит (дорого), и от текущего запаса. Покупка игрока поднимает
## цену, продажа — роняет. Навык торговли улучшает курс для игрока.
extends RefCounted

const Goods := preload("res://core/goods.gd")

var exports: Array = []   # производит — дёшево, много на складе
var imports: Array = []   # ввозит — дорого, охотно покупают
var stock := {}           # goods_id -> units на складе


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


## Цена, по которой колония ПРОДАЁТ игроку единицу товара.
func buy_price(goods_id: String, trade_skill: int) -> int:
	var base: int = Goods.get_type(goods_id)["base_price"]
	var mult := 1.0
	if goods_id in exports:
		mult = 0.55
	elif goods_id in imports:
		mult = 1.9
	# Дефицит на складе задирает цену.
	var s := int(stock.get(goods_id, 0))
	var scarcity := clampf(1.6 - s / 200.0, 0.8, 1.6)
	var skill_discount := 1.0 - trade_skill * 0.015
	return maxi(int(round(base * mult * scarcity * skill_discount)), 1)


## Цена, по которой колония ПОКУПАЕТ у игрока (всегда ниже своей продажной).
func sell_price(goods_id: String, trade_skill: int) -> int:
	var base: int = Goods.get_type(goods_id)["base_price"]
	var mult := 0.8
	if goods_id in exports:
		mult = 0.35   # продавать колонии её же товар невыгодно
	elif goods_id in imports:
		mult = 1.5    # то, что колония ввозит, берут дорого
	var s := int(stock.get(goods_id, 0))
	var scarcity := clampf(1.5 - s / 200.0, 0.7, 1.5)
	var skill_bonus := 1.0 + trade_skill * 0.015
	return maxi(int(round(base * mult * scarcity * skill_bonus)), 1)


## Игрок покупает у колонии. Возвращает потраченное золото или -1.
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


## Игрок продаёт колонии. Возвращает вырученное золото или -1.
func player_sell(goods_id: String, units: int, character, ship, trade_skill: int) -> int:
	if units <= 0 or not ship.remove_cargo(goods_id, units):
		return -1
	var income := sell_price(goods_id, trade_skill) * units
	character.earn(income)
	stock[goods_id] = int(stock.get(goods_id, 0)) + units
	return income


## Ежедневное восстановление рынка: экспорт прирастает, импорт потребляется.
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
