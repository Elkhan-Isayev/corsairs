## Ship state: hull, sails, crew, cannons, cargo hold, ammo stock.
extends RefCounted

const ShipTypes := preload("res://core/ship_types.gd")
const Ammo := preload("res://core/ammo.gd")

var type_id: String
var custom_name: String = ""
var hull: float
var sails: float
var crew: int
var cannons: int
var caliber: int
var current_ammo: String = "balls"
var ammo_stock := {"balls": 0, "knippels": 0, "grapeshot": 0, "bombs": 0}
var cargo := {}  # goods_id -> units
var sail_setting: float = 0.0  # 0.0 furled, 0.5 half, 1.0 full
var heading: float = 0.0  # degrees, 0 = north
var reload_progress: float = 1.0  # 1.0 = ready to fire


static func create(p_type_id: String, name := "") -> RefCounted:
	var ship = load("res://core/ship.gd").new()
	var t := ShipTypes.get_type(p_type_id)
	ship.type_id = p_type_id
	ship.custom_name = name if name != "" else t["name"]
	ship.hull = t["hull"]
	ship.sails = t["sails"]
	ship.crew = t["max_crew"]
	ship.cannons = t["cannons"]
	ship.caliber = t["max_caliber"]
	return ship


func spec() -> Dictionary:
	return ShipTypes.get_type(type_id)


func hull_frac() -> float:
	return clampf(hull / float(spec()["hull"]), 0.0, 1.0)


func sails_frac() -> float:
	return clampf(sails / float(spec()["sails"]), 0.0, 1.0)


func crew_frac() -> float:
	return clampf(float(crew) / float(spec()["max_crew"]), 0.0, 1.0)


func is_sunk() -> bool:
	return hull <= 0.0


## Below minimum crew the ship cannot be handled.
func is_crew_critical() -> bool:
	return crew < int(spec()["min_crew"])


func cargo_used() -> int:
	var total := 0
	for g in cargo:
		total += int(cargo[g])
	return total


func cargo_free() -> int:
	return int(spec()["cargo"]) - cargo_used()


func add_cargo(goods_id: String, units: int) -> bool:
	if units <= 0:
		return false
	if cargo_free() < units:
		return false
	cargo[goods_id] = int(cargo.get(goods_id, 0)) + units
	return true


func remove_cargo(goods_id: String, units: int) -> bool:
	if units <= 0 or int(cargo.get(goods_id, 0)) < units:
		return false
	cargo[goods_id] = int(cargo[goods_id]) - units
	if cargo[goods_id] == 0:
		cargo.erase(goods_id)
	return true


## Guns on one side able to fire (depends on surviving cannons).
func broadside_guns() -> int:
	return int(floor(cannons / 2.0))


func has_ammo() -> bool:
	return int(ammo_stock.get(current_ammo, 0)) > 0


func apply_damage(hull_dmg: float, sail_dmg: float, crew_loss: int, cannons_lost: int) -> void:
	hull = maxf(hull - hull_dmg, 0.0)
	sails = maxf(sails - sail_dmg, 0.0)
	crew = maxi(crew - crew_loss, 0)
	cannons = maxi(cannons - cannons_lost, 0)


## Field repair at sea by the crew (planks/sailcloth from the hold).
func field_repair(planks: int, sailcloth: int) -> Dictionary:
	var used_planks := 0
	var used_cloth := 0
	var max_hull := float(spec()["hull"])
	var max_sails := float(spec()["sails"])
	while used_planks < planks and hull < max_hull * 0.85:
		hull = minf(hull + 12.0, max_hull * 0.85)
		used_planks += 1
	while used_cloth < sailcloth and sails < max_sails:
		sails = minf(sails + 10.0, max_sails)
		used_cloth += 1
	return {"planks": used_planks, "sailcloth": used_cloth}


func to_dict() -> Dictionary:
	return {
		"type_id": type_id, "custom_name": custom_name,
		"hull": hull, "sails": sails, "crew": crew,
		"cannons": cannons, "caliber": caliber,
		"current_ammo": current_ammo, "ammo_stock": ammo_stock.duplicate(),
		"cargo": cargo.duplicate(),
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var ship = load("res://core/ship.gd").new()
	ship.type_id = d["type_id"]
	ship.custom_name = d["custom_name"]
	ship.hull = d["hull"]
	ship.sails = d["sails"]
	ship.crew = int(d["crew"])
	ship.cannons = int(d["cannons"])
	ship.caliber = int(d["caliber"])
	ship.current_ammo = d["current_ammo"]
	ship.ammo_stock = {}
	for k in d["ammo_stock"]:
		ship.ammo_stock[k] = int(d["ammo_stock"][k])
	ship.cargo = {}
	for k in d["cargo"]:
		ship.cargo[k] = int(d["cargo"][k])
	return ship
