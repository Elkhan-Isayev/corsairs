## Naval combat: broadside volleys, hits, damage split by ammo type.
extends RefCounted

const Ammo := preload("res://core/ammo.gd")

const BASE_RANGE := 500.0  # meters for 16-pounders firing cannonballs


static func max_range(caliber: int, ammo_id: String) -> float:
	var ammo := Ammo.get_type(ammo_id)
	var caliber_mult := 0.7 + caliber / 32.0 * 0.6
	return BASE_RANGE * ammo["range_mult"] * caliber_mult


## Hit chance of a single gun.
static func hit_chance(distance: float, range_limit: float, accuracy_skill: int, cannons_skill: int) -> float:
	if distance > range_limit:
		return 0.0
	var closeness := 1.0 - distance / range_limit   # 0 at max range, 1 point-blank
	var base := 0.15 + 0.65 * closeness
	var skill := 1.0 + (accuracy_skill * 0.03) + (cannons_skill * 0.015)
	return clampf(base * skill, 0.0, 0.95)


## Full broadside. Returns a report and applies damage to the target.
## attacker_skills: {"accuracy": int, "cannons": int}
static func fire_broadside(attacker, target, distance: float, attacker_skills: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var report := {"fired": 0, "hits": 0, "hull_dmg": 0.0, "sail_dmg": 0.0, "crew_loss": 0, "cannons_lost": 0, "out_of_range": false, "no_ammo": false}
	if attacker.reload_progress < 1.0:
		return report
	var guns: int = attacker.broadside_guns()
	if guns <= 0:
		return report
	var stock: int = attacker.ammo_stock.get(attacker.current_ammo, 0)
	if stock <= 0:
		report["no_ammo"] = true
		return report
	var shots: int = mini(guns, stock)
	var range_limit := max_range(attacker.caliber, attacker.current_ammo)
	if distance > range_limit:
		report["out_of_range"] = true
		return report

	attacker.ammo_stock[attacker.current_ammo] = stock - shots
	attacker.reload_progress = 0.0
	report["fired"] = shots

	var ammo := Ammo.get_type(attacker.current_ammo)
	var chance := hit_chance(distance, range_limit, attacker_skills.get("accuracy", 0), attacker_skills.get("cannons", 0))
	var dmg_per_hit: float = attacker.caliber * 1.1

	for i in shots:
		if rng.randf() > chance:
			continue
		report["hits"] += 1
		report["hull_dmg"] += dmg_per_hit * ammo["hull_dmg"]
		report["sail_dmg"] += dmg_per_hit * ammo["sail_dmg"] * 0.6
		if rng.randf() < ammo["crew_dmg"] * 0.35:
			report["crew_loss"] += 1 + rng.randi_range(0, int(ammo["crew_dmg"] * 3.0))
		if rng.randf() < ammo["cannon_dmg"] * 0.20:
			report["cannons_lost"] += 1

	target.apply_damage(report["hull_dmg"], report["sail_dmg"], report["crew_loss"], report["cannons_lost"])
	return report


## Reload time in seconds: bigger caliber is slower; skill and crew speed it up.
static func reload_time(ship, cannons_skill: int) -> float:
	var base: float = 18.0 + ship.caliber * 0.5
	var crew_factor := clampf(ship.crew_frac(), 0.3, 1.0)
	var skill_factor := 1.0 - cannons_skill * 0.04
	return maxf(base * skill_factor / crew_factor, 5.0)


static func tick_reload(ship, delta: float, cannons_skill: int) -> void:
	if ship.reload_progress >= 1.0:
		return
	ship.reload_progress = minf(ship.reload_progress + delta / reload_time(ship, cannons_skill), 1.0)


## Boarding is possible when the hulls are close and the target still floats.
static func can_board(distance: float, target) -> bool:
	return distance <= 60.0 and not target.is_sunk()
