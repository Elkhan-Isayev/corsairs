## Справочник товаров колониальной торговли.
extends RefCounted

const TYPES := {
	"provisions": {"name": "Провизия", "base_price": 5},
	"rum": {"name": "Ром", "base_price": 20},
	"wine": {"name": "Вино", "base_price": 28},
	"sailcloth": {"name": "Парусина", "base_price": 15},
	"planks": {"name": "Доски", "base_price": 10},
	"gunpowder": {"name": "Порох", "base_price": 25},
	"weapons": {"name": "Оружие", "base_price": 60},
	"medicines": {"name": "Лекарства", "base_price": 45},
	"silk": {"name": "Шёлк", "base_price": 90},
	"coffee": {"name": "Кофе", "base_price": 50},
	"tobacco": {"name": "Табак", "base_price": 40},
	"sugar": {"name": "Сахар", "base_price": 18},
	"cocoa": {"name": "Какао", "base_price": 55},
	"cotton": {"name": "Хлопок", "base_price": 22},
	"ebony": {"name": "Чёрное дерево", "base_price": 75},
	"spices": {"name": "Пряности", "base_price": 85},
}

static func get_type(id: String) -> Dictionary:
	assert(TYPES.has(id), "Unknown goods: %s" % id)
	return TYPES[id]

static func all_ids() -> Array:
	return TYPES.keys()
