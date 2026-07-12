## Sailing model: ship speed from the angle to the wind, sail setting
## and the navigation skill. A square-rigged ship barely moves upwind
## (in irons) and is fastest on a broad reach.
extends RefCounted

## Speed multiplier from the course angle to the wind (0° = dead upwind).
## Arcade model: the wind flavors the speed but never stalls the ship —
## the multiplier stays in a narrow 0.75..1.0 band.
static func wind_profile(angle_to_wind_deg: float) -> float:
	var a := absf(wrapf(angle_to_wind_deg, -180.0, 180.0))
	if a < 30.0:      # upwind — mildest penalty instead of a dead zone
		return 0.75
	elif a < 90.0:    # close-hauled to beam reach
		return 0.75 + (a - 30.0) / 60.0 * 0.17   # 0.75..0.92
	elif a < 135.0:   # broad reach — the best point of sail
		return 0.92 + (a - 90.0) / 45.0 * 0.08   # 0.92..1.00
	else:             # running — barely slower than a broad reach
		return 1.0 - (a - 135.0) / 45.0 * 0.04   # 1.00..0.96


## Resulting speed in knots.
static func ship_speed(ship, wind_from_deg: float, wind_strength: float, navigation_skill: int) -> float:
	if ship.is_crew_critical():
		return 0.0
	var base: float = ship.spec()["base_speed"]
	# Angle between our course and the direction the wind blows FROM.
	var angle := wrapf(ship.heading - wind_from_deg, -180.0, 180.0)
	var profile := wind_profile(angle)
	var sail_hp: float = ship.sails_frac()
	var skill_bonus := 1.0 + navigation_skill * 0.02   # +2% per skill point
	# Arcade: wind strength nudges speed by ±10% at most.
	var wind_mult := clampf(1.0 + (wind_strength - 10.0) * 0.01, 0.9, 1.1)
	return base * ship.sail_setting * profile * sail_hp * wind_mult * skill_bonus


## Turn rate in degrees per second. The rudder is useless without way.
static func turn_speed(ship, current_speed: float, navigation_skill: int) -> float:
	var base: float = ship.spec()["turn_rate"]
	var speed_factor := clampf(current_speed / 6.0, 0.0, 1.0)
	return base * speed_factor * (1.0 + navigation_skill * 0.015)


## Wind shift between battles/days (deterministic through rng).
static func drift_wind(wind_from_deg: float, wind_strength: float, rng: RandomNumberGenerator) -> Dictionary:
	var new_dir := wrapf(wind_from_deg + rng.randf_range(-25.0, 25.0), 0.0, 360.0)
	var new_str := clampf(wind_strength + rng.randf_range(-2.0, 2.0), 2.0, 15.0)
	return {"from": new_dir, "strength": new_str}
