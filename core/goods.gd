## Colonial trade goods catalog.
extends RefCounted

const TYPES := {
	"provisions": {"name": "Provisions", "base_price": 5},
	"rum": {"name": "Rum", "base_price": 20},
	"wine": {"name": "Wine", "base_price": 28},
	"sailcloth": {"name": "Sailcloth", "base_price": 15},
	"planks": {"name": "Planks", "base_price": 10},
	"gunpowder": {"name": "Gunpowder", "base_price": 25},
	"weapons": {"name": "Weapons", "base_price": 60},
	"medicines": {"name": "Medicines", "base_price": 45},
	"silk": {"name": "Silk", "base_price": 90},
	"coffee": {"name": "Coffee", "base_price": 50},
	"tobacco": {"name": "Tobacco", "base_price": 40},
	"sugar": {"name": "Sugar", "base_price": 18},
	"cocoa": {"name": "Cocoa", "base_price": 55},
	"cotton": {"name": "Cotton", "base_price": 22},
	"ebony": {"name": "Ebony", "base_price": 75},
	"spices": {"name": "Spices", "base_price": 85},
}

static func get_type(id: String) -> Dictionary:
	assert(TYPES.has(id), "Unknown goods: %s" % id)
	return TYPES[id]

static func all_ids() -> Array:
	return TYPES.keys()
