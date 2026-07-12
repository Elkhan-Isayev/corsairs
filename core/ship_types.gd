## Ship class catalog — in the spirit of Sea Dogs II.
## Rank 7 is the weakest (tartane), rank 1 is the man-of-war.
extends RefCounted

const TYPES := {
	"tartane": {
		"name": "Tartane", "rank": 7, "hull": 250, "sails": 100,
		"max_crew": 15, "min_crew": 3, "cannons": 4, "max_caliber": 8,
		"cargo": 250, "base_speed": 11.0, "turn_rate": 30.0, "price": 1500,
	},
	"lugger": {
		"name": "Lugger", "rank": 7, "hull": 450, "sails": 150,
		"max_crew": 40, "min_crew": 8, "cannons": 8, "max_caliber": 12,
		"cargo": 600, "base_speed": 12.5, "turn_rate": 28.0, "price": 5000,
	},
	"sloop": {
		"name": "Sloop", "rank": 6, "hull": 700, "sails": 200,
		"max_crew": 70, "min_crew": 12, "cannons": 12, "max_caliber": 12,
		"cargo": 900, "base_speed": 13.0, "turn_rate": 26.0, "price": 9500,
	},
	"schooner": {
		"name": "Schooner", "rank": 6, "hull": 850, "sails": 240,
		"max_crew": 90, "min_crew": 15, "cannons": 16, "max_caliber": 16,
		"cargo": 1300, "base_speed": 13.5, "turn_rate": 24.0, "price": 14000,
	},
	"barque": {
		"name": "Barque", "rank": 5, "hull": 1100, "sails": 300,
		"max_crew": 110, "min_crew": 20, "cannons": 20, "max_caliber": 16,
		"cargo": 2000, "base_speed": 11.5, "turn_rate": 20.0, "price": 21000,
	},
	"brig": {
		"name": "Brig", "rank": 5, "hull": 1400, "sails": 350,
		"max_crew": 150, "min_crew": 25, "cannons": 24, "max_caliber": 20,
		"cargo": 2400, "base_speed": 12.0, "turn_rate": 19.0, "price": 32000,
	},
	"galleon": {
		"name": "Galleon", "rank": 4, "hull": 2200, "sails": 450,
		"max_crew": 250, "min_crew": 40, "cannons": 32, "max_caliber": 24,
		"cargo": 4500, "base_speed": 9.5, "turn_rate": 13.0, "price": 55000,
	},
	"corvette": {
		"name": "Corvette", "rank": 3, "hull": 2000, "sails": 480,
		"max_crew": 280, "min_crew": 45, "cannons": 40, "max_caliber": 24,
		"cargo": 3200, "base_speed": 12.8, "turn_rate": 17.0, "price": 75000,
	},
	"frigate": {
		"name": "Frigate", "rank": 2, "hull": 3000, "sails": 600,
		"max_crew": 400, "min_crew": 60, "cannons": 48, "max_caliber": 32,
		"cargo": 4000, "base_speed": 12.2, "turn_rate": 15.0, "price": 120000,
	},
	"battleship": {
		"name": "Ship of the Line", "rank": 1, "hull": 4200, "sails": 750,
		"max_crew": 550, "min_crew": 90, "cannons": 64, "max_caliber": 32,
		"cargo": 5000, "base_speed": 10.5, "turn_rate": 11.0, "price": 220000,
	},
	"manowar": {
		"name": "Man-of-War", "rank": 1, "hull": 5500, "sails": 900,
		"max_crew": 700, "min_crew": 120, "cannons": 92, "max_caliber": 36,
		"cargo": 6000, "base_speed": 9.8, "turn_rate": 9.0, "price": 400000,
	},
}

static func get_type(id: String) -> Dictionary:
	assert(TYPES.has(id), "Unknown ship type: %s" % id)
	return TYPES[id]

static func all_ids() -> Array:
	return TYPES.keys()

## Ships available at a shipyard of the given colony tier (1..3).
static func available_for_shipyard(tier: int) -> Array:
	var out: Array = []
	for id in TYPES:
		var rank: int = TYPES[id]["rank"]
		if tier == 1 and rank >= 6:
			out.append(id)
		elif tier == 2 and rank >= 4:
			out.append(id)
		elif tier == 3:
			out.append(id)
	return out
