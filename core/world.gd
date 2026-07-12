## World: the Caribbean archipelago, colonies, nations and diplomacy.
extends RefCounted

const Market := preload("res://core/market.gd")

const NATIONS := {
	"england": {"name": "England", "color": "c62828"},
	"france": {"name": "France", "color": "1565c0"},
	"spain": {"name": "Spain", "color": "f9a825"},
	"holland": {"name": "Holland", "color": "ef6c00"},
	"pirates": {"name": "Pirates", "color": "212121"},
}

## Starting diplomacy: -1 war, 0 neutral, 1 peace.
const DEFAULT_RELATIONS := {
	"england": {"france": -1, "spain": -1, "holland": 1, "pirates": -1},
	"france": {"england": -1, "spain": 0, "holland": 0, "pirates": -1},
	"spain": {"england": -1, "france": 0, "holland": -1, "pirates": -1},
	"holland": {"england": 1, "france": 0, "spain": -1, "pirates": -1},
	"pirates": {"england": -1, "france": -1, "spain": -1, "holland": -1},
}

## The archipelago. Coordinates in nautical miles on a 1000x800 map.
const ISLANDS := {
	"oxbay": {
		"name": "Oxbay", "nation": "england", "pos": [220, 300], "tier": 1,
		"exports": ["rum", "sugar"], "imports": ["weapons", "silk"],
	},
	"redmond": {
		"name": "Redmond", "nation": "england", "pos": [400, 480], "tier": 3,
		"exports": ["tobacco", "cotton"], "imports": ["medicines", "wine"],
	},
	"isla_muelle": {
		"name": "Isla Muelle", "nation": "spain", "pos": [640, 220], "tier": 3,
		"exports": ["coffee", "cocoa"], "imports": ["gunpowder", "planks"],
	},
	"conceicao": {
		"name": "Conceicao", "nation": "spain", "pos": [780, 420], "tier": 2,
		"exports": ["ebony", "spices"], "imports": ["provisions", "sailcloth"],
	},
	"falaise_de_fleur": {
		"name": "Falaise de Fleur", "nation": "france", "pos": [520, 640], "tier": 3,
		"exports": ["wine", "silk"], "imports": ["sugar", "tobacco"],
	},
	"douwesen": {
		"name": "Douwesen", "nation": "holland", "pos": [840, 620], "tier": 2,
		"exports": ["cotton", "provisions"], "imports": ["rum", "coffee"],
	},
	"quebradas": {
		"name": "Quebradas Costillas", "nation": "pirates", "pos": [150, 620], "tier": 1,
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


## Player reputation with a nation, -100..100.
func reputation(nation: String) -> int:
	return int(player_reputation.get(nation, 0))


func change_reputation(nation: String, delta: int) -> void:
	player_reputation[nation] = clampi(reputation(nation) + delta, -100, 100)


## Sinking/capturing a nation's ship: its opinion drops,
## its enemies approve.
func on_player_attacked(victim_nation: String) -> void:
	change_reputation(victim_nation, -15)
	for n in NATIONS:
		if n != victim_nation and are_at_war(n, victim_nation):
			change_reputation(n, 6)


## Whether the port turns the player away: below -30 the port is closed.
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
