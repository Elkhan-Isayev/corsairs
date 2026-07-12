## Типы боеприпасов и их профили урона — как в «Корсарах»:
## ядра бьют по корпусу, книппели рвут паруса, картечь косит команду,
## бомбы жгут корпус, но летят ближе.
extends RefCounted

const TYPES := {
	"balls": {
		"name": "Ядра",
		"hull_dmg": 1.0, "sail_dmg": 0.25, "crew_dmg": 0.15, "cannon_dmg": 0.10,
		"range_mult": 1.0, "price": 2,
	},
	"knippels": {
		"name": "Книппели",
		"hull_dmg": 0.15, "sail_dmg": 1.2, "crew_dmg": 0.10, "cannon_dmg": 0.05,
		"range_mult": 0.8, "price": 3,
	},
	"grapeshot": {
		"name": "Картечь",
		"hull_dmg": 0.05, "sail_dmg": 0.15, "crew_dmg": 1.5, "cannon_dmg": 0.05,
		"range_mult": 0.5, "price": 3,
	},
	"bombs": {
		"name": "Бомбы",
		"hull_dmg": 1.6, "sail_dmg": 0.20, "crew_dmg": 0.40, "cannon_dmg": 0.25,
		"range_mult": 0.65, "price": 6,
	},
}

const ORDER := ["balls", "knippels", "grapeshot", "bombs"]

static func get_type(id: String) -> Dictionary:
	assert(TYPES.has(id), "Unknown ammo type: %s" % id)
	return TYPES[id]

static func next_type(id: String) -> String:
	var i := ORDER.find(id)
	return ORDER[(i + 1) % ORDER.size()]
