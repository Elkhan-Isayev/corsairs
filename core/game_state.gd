## Aggregate of the whole game state: character, ship, world, quests, time.
## Voyages, random encounters, wages, port services (shipyard/hiring), saves.
extends RefCounted

const Character := preload("res://core/character.gd")
const Ship := preload("res://core/ship.gd")
const ShipTypes := preload("res://core/ship_types.gd")
const World := preload("res://core/world.gd")
const Quests := preload("res://core/quests.gd")
const Sailing := preload("res://core/sailing.gd")

const SAVE_PATH := "user://savegame.json"
const CREW_HIRE_COST := 20      # gold per sailor
const CREW_WAGE_PER_DAY := 1    # daily wage per sailor

var character: RefCounted
var ship: RefCounted
var world: RefCounted
var quests: RefCounted
var day: int = 1
var current_island: String = "oxbay"   # "" — at sea
var wind := {"from": 90.0, "strength": 8.0}
var rng := RandomNumberGenerator.new()


static func new_game(captain_name: String, nation: String, seed_value: int = -1) -> RefCounted:
	var g = load("res://core/game_state.gd").new()
	if seed_value >= 0:
		g.rng.seed = seed_value
	else:
		g.rng.randomize()
	g.character = Character.create(captain_name, nation)
	g.ship = Ship.create("lugger", "Fortune")
	g.ship.ammo_stock = {"balls": 120, "knippels": 40, "grapeshot": 40, "bombs": 0}
	g.ship.add_cargo("provisions", 30)
	g.ship.add_cargo("planks", 15)
	g.ship.add_cargo("sailcloth", 10)
	g.world = World.create(g.rng)
	g.quests = Quests.new()
	g.current_island = "oxbay" if nation != "pirates" else "quebradas"
	return g


## Voyage to an island. Returns a log: days at sea, encounters, events.
func sail_to(island_id: String) -> Dictionary:
	assert(current_island != "", "Already at sea")
	assert(island_id != current_island, "Already here")
	var dist := World.distance(current_island, island_id)
	var days := maxi(int(ceil(dist / 120.0)), 1)
	var log := {"days": days, "encounter": null, "arrived": island_id, "wages_paid": 0, "starved": 0, "completed_quests": []}

	for d in days:
		_advance_day(log)

	# Random encounter en route.
	var encounter_chance := 0.35
	if rng.randf() < encounter_chance:
		log["encounter"] = _roll_encounter(island_id)

	log["completed_quests"] = arrive(island_id)["completed_quests"]
	return log


# --- Open sea (the sailable world map) ---

## Cast off: the ship is at sea until arrive() is called.
func depart() -> void:
	current_island = ""


## One day passing on the open sea: wages, provisions, markets, wind.
func sea_day() -> Dictionary:
	var log := {"days": 1, "wages_paid": 0, "starved": 0}
	_advance_day(log)
	return log


## Dock at an island reached on the open sea; completes delivery quests.
func arrive(island_id: String) -> Dictionary:
	current_island = island_id
	var done: Array = quests.check_completion({"type": "arrived", "island": island_id}, day, ship)
	for q in done:
		character.earn(int(q["reward"]))
		character.add_xp(int(q["reward"] / 4.0))
		world.change_reputation(World.island(q["from"])["nation"], 5)
	return {"completed_quests": done}


## A sail on the horizon: what ship cruises these waters.
func roll_sea_encounter(near_island: String) -> Dictionary:
	return _roll_encounter(near_island)


func _advance_day(log: Dictionary) -> void:
	day += 1
	# Crew wages.
	var wages: int = ship.crew * CREW_WAGE_PER_DAY
	if character.gold >= wages:
		character.gold -= wages
		log["wages_paid"] = int(log["wages_paid"]) + wages
	else:
		# No pay — sailors desert.
		var deserters := maxi(int(ship.crew * 0.05), 1)
		ship.crew = maxi(ship.crew - deserters, 0)
	# Provisions: 1 unit per 10 crew per day.
	var need := maxi(int(ceil(ship.crew / 10.0)), 1)
	if not ship.remove_cargo("provisions", need):
		var starved := maxi(int(ship.crew * 0.03), 1)
		ship.crew = maxi(ship.crew - starved, 0)
		log["starved"] = int(log["starved"]) + starved
	# Markets live their own life, the wind shifts.
	for island_id in world.markets:
		world.market(island_id).daily_tick(rng)
	wind = Sailing.drift_wind(wind["from"], wind["strength"], rng)
	# Overdue quests hurt reputation.
	for q in quests.expire(day):
		world.change_reputation(World.island(q["from"])["nation"], -10)


## Encounter at sea: nation and ship depend on whose waters we sail.
func _roll_encounter(dest_island: String) -> Dictionary:
	var dest_nation: String = World.island(dest_island)["nation"]
	var nations := ["pirates", dest_nation, dest_nation]
	var enc_nation: String = nations[rng.randi_range(0, nations.size() - 1)]
	var pool := ["lugger", "sloop", "schooner", "barque", "brig"]
	# Bigger ships appear as the player levels up.
	if character.level >= 8:
		pool += ["galleon", "corvette", "frigate"]
	elif character.level >= 4:
		pool += ["galleon"]
	var type_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var hostile: bool = enc_nation == "pirates" \
		or world.are_at_war(enc_nation, character.nation) \
		or world.reputation(enc_nation) < -30
	# Any sail may travel in company — squadrons of up to four hulls.
	var count := 1
	var roll := rng.randf()
	if roll > 0.92:
		count = 4
	elif roll > 0.78:
		count = 3
	elif roll > 0.55:
		count = 2
	return {"nation": enc_nation, "ship_type": type_id, "hostile": hostile, "count": count}


## Create the encounter's enemy ship (with crew and ammo aboard).
func spawn_encounter_ship(encounter: Dictionary) -> RefCounted:
	var e = Ship.create(encounter["ship_type"])
	e.crew = int(e.spec()["max_crew"] * rng.randf_range(0.6, 1.0))
	e.ammo_stock = {"balls": 200, "knippels": 60, "grapeshot": 60, "bombs": 20}
	var goods_pool := ["rum", "sugar", "coffee", "tobacco", "silk", "spices"]
	e.add_cargo(goods_pool[rng.randi_range(0, goods_pool.size() - 1)], rng.randi_range(10, 60))
	return e


## Battle won: XP, reputation, possible "hunt" quest completion.
func on_enemy_sunk(enemy, enemy_nation: String) -> Dictionary:
	var xp := 30 * int(enemy.spec()["rank"] <= 4) * 3 + 40 + int(enemy.spec()["price"] / 1000.0)
	var res: Dictionary = character.add_xp(xp)
	world.on_player_attacked(enemy_nation)
	var done: Array = quests.check_completion({"type": "sunk_pirate", "ship_type": enemy.type_id}, day, ship) \
		if enemy_nation == "pirates" else []
	for q in done:
		character.earn(int(q["reward"]))
	return {"xp": xp, "level_up": res["levels_gained"] > 0, "completed_quests": done}


# --- Port ---

func hire_crew(count: int) -> bool:
	var space: int = int(ship.spec()["max_crew"]) - ship.crew
	if count <= 0 or count > space:
		return false
	if not character.spend(count * CREW_HIRE_COST):
		return false
	ship.crew += count
	return true


func repair_ship_at_shipyard() -> int:
	var spec: Dictionary = ship.spec()
	var hull_missing: float = spec["hull"] - ship.hull
	var sails_missing: float = spec["sails"] - ship.sails
	var cannons_missing: int = int(spec["cannons"]) - ship.cannons
	var cost := int(hull_missing * 2.0 + sails_missing * 1.5 + cannons_missing * 150)
	if cost == 0:
		return 0
	if not character.spend(cost):
		return -1
	ship.hull = spec["hull"]
	ship.sails = spec["sails"]
	ship.cannons = int(spec["cannons"])
	return cost


## Buying a new ship: the old one is traded in at half price.
func buy_ship(type_id: String) -> bool:
	var price: int = ShipTypes.get_type(type_id)["price"]
	var trade_in := int(ship.spec()["price"] * 0.5 * ship.hull_frac())
	var to_pay := maxi(price - trade_in, 0)
	if not character.spend(to_pay):
		return false
	var old = ship
	ship = Ship.create(type_id)
	ship.crew = mini(old.crew, int(ship.spec()["max_crew"]))
	ship.ammo_stock = old.ammo_stock.duplicate()
	# Move as much cargo as fits.
	for g in old.cargo:
		ship.add_cargo(g, mini(int(old.cargo[g]), ship.cargo_free()))
	return true


func buy_ammo(ammo_id: String, units: int, price_per_unit: int) -> bool:
	if units <= 0 or not character.spend(units * price_per_unit):
		return false
	ship.ammo_stock[ammo_id] = int(ship.ammo_stock.get(ammo_id, 0)) + units
	return true


# --- Persistence ---

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"character": character.to_dict(),
		"ship": ship.to_dict(),
		"world": world.to_dict(),
		"quests": quests.to_dict(),
		"day": day,
		"current_island": current_island,
		"wind": wind.duplicate(),
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var g = load("res://core/game_state.gd").new()
	g.rng.randomize()
	g.character = Character.from_dict(d["character"])
	g.ship = Ship.from_dict(d["ship"])
	g.world = World.from_dict(d["world"])
	g.quests = Quests.from_dict(d["quests"])
	g.day = int(d["day"])
	g.current_island = d["current_island"]
	g.wind = {"from": float(d["wind"]["from"]), "strength": float(d["wind"]["strength"])}
	return g


func save_to_file(path := SAVE_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


static func load_from_file(path := SAVE_PATH) -> RefCounted:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return null
	return from_dict(parsed)


static func has_save(path := SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)
