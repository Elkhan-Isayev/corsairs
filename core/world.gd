## Мир: Карибский архипелаг, колонии, нации и дипломатия.
extends RefCounted

const Market := preload("res://core/market.gd")

const NATIONS := {
	"england": {"name": "Англия", "color": "c62828"},
	"france": {"name": "Франция", "color": "1565c0"},
	"spain": {"name": "Испания", "color": "f9a825"},
	"holland": {"name": "Голландия", "color": "ef6c00"},
	"pirates": {"name": "Пираты", "color": "212121"},
}

## Стартовая дипломатия: -1 война, 0 нейтралитет, 1 мир.
const DEFAULT_RELATIONS := {
	"england": {"france": -1, "spain": -1, "holland": 1, "pirates": -1},
	"france": {"england": -1, "spain": 0, "holland": 0, "pirates": -1},
	"spain": {"england": -1, "france": 0, "holland": -1, "pirates": -1},
	"holland": {"england": 1, "france": 0, "spain": -1, "pirates": -1},
	"pirates": {"england": -1, "france": -1, "spain": -1, "holland": -1},
}

## Архипелаг. Координаты в условных морских милях на карте 1000x800.
const ISLANDS := {
	"oxbay": {
		"name": "Оксбей", "nation": "england", "pos": [220, 300], "tier": 1,
		"exports": ["rum", "sugar"], "imports": ["weapons", "silk"],
	},
	"redmond": {
		"name": "Редмонд", "nation": "england", "pos": [400, 480], "tier": 3,
		"exports": ["tobacco", "cotton"], "imports": ["medicines", "wine"],
	},
	"isla_muelle": {
		"name": "Исла Муэлле", "nation": "spain", "pos": [640, 220], "tier": 3,
		"exports": ["coffee", "cocoa"], "imports": ["gunpowder", "planks"],
	},
	"conceicao": {
		"name": "Консейсао", "nation": "spain", "pos": [780, 420], "tier": 2,
		"exports": ["ebony", "spices"], "imports": ["provisions", "sailcloth"],
	},
	"falaise_de_fleur": {
		"name": "Фалез-де-Флёр", "nation": "france", "pos": [520, 640], "tier": 3,
		"exports": ["wine", "silk"], "imports": ["sugar", "tobacco"],
	},
	"douwesen": {
		"name": "Дувесен", "nation": "holland", "pos": [840, 620], "tier": 2,
		"exports": ["cotton", "provisions"], "imports": ["rum", "coffee"],
	},
	"quebradas": {
		"name": "Кебрадас-Костильяс", "nation": "pirates", "pos": [150, 620], "tier": 1,
		"exports": ["weapons", "gunpowder"], "imports": ["medicines", "provisions"],
	},
}

var relations := {}
var markets := {}          # island_id -> Market
var player_reputation := {}  # nation -> -100..100


static func create(rng: RandomNumberGenerator) -> RefCounted:
	var w = load("res://core/world.gd").new()
	for n in DEFAULT_RELATIONS:
		w.relations[n] = DEFAULT_RELATIONS[n].duplicate()
		w.player_reputation[n] = 0
	for island_id in ISLANDS:
		var isl: Dictionary = ISLANDS[island_id]
		w.markets[island_id] = Market.create(isl["exports"], isl["imports"], rng)
	return w


static func island(id: String) -> Dictionary:
	assert(ISLANDS.has(id), "Unknown island: %s" % id)
	return ISLANDS[id]


static func island_ids() -> Array:
	return ISLANDS.keys()


static func distance(a_id: String, b_id: String) -> float:
	var a: Array = ISLANDS[a_id]["pos"]
	var b: Array = ISLANDS[b_id]["pos"]
	return Vector2(a[0], a[1]).distance_to(Vector2(b[0], b[1]))


func market(island_id: String) -> RefCounted:
	return markets[island_id]


func are_at_war(nation_a: String, nation_b: String) -> bool:
	if nation_a == nation_b:
		return false
	return int(relations[nation_a].get(nation_b, 0)) < 0


## Репутация игрока у нации, -100..100.
func reputation(nation: String) -> int:
	return int(player_reputation.get(nation, 0))


func change_reputation(nation: String, delta: int) -> void:
	player_reputation[nation] = clampi(reputation(nation) + delta, -100, 100)


## Потопление/захват корабля нации: её отношение падает,
## отношение её врагов растёт.
func on_player_attacked(victim_nation: String) -> void:
	change_reputation(victim_nation, -15)
	for n in NATIONS:
		if n != victim_nation and are_at_war(n, victim_nation):
			change_reputation(n, 6)


## Пустят ли игрока в порт: репутация ниже -30 — порт закрыт.
func is_port_hostile(island_id: String) -> bool:
	var nation: String = ISLANDS[island_id]["nation"]
	return reputation(nation) < -30


func to_dict() -> Dictionary:
	var m := {}
	for k in markets:
		m[k] = markets[k].to_dict()
	return {"relations": relations.duplicate(true), "player_reputation": player_reputation.duplicate(), "markets": m}


static func from_dict(d: Dictionary) -> RefCounted:
	var w = load("res://core/world.gd").new()
	w.relations = {}
	for n in d["relations"]:
		w.relations[n] = {}
		for m in d["relations"][n]:
			w.relations[n][m] = int(d["relations"][n][m])
	w.player_reputation = {}
	for n in d["player_reputation"]:
		w.player_reputation[n] = int(d["player_reputation"][n])
	w.markets = {}
	for k in d["markets"]:
		w.markets[k] = Market.from_dict(d["markets"][k])
	return w
