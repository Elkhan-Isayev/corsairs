## Парусная модель: скорость корабля от угла к ветру, состояния парусов
## и навыка навигации. Против ветра парусник почти не идёт (левентик),
## быстрее всего — бакштаг.
extends RefCounted

## Множитель скорости от курсового угла к ветру (0° = идём прямо против ветра).
static func wind_profile(angle_to_wind_deg: float) -> float:
	var a := absf(wrapf(angle_to_wind_deg, -180.0, 180.0))
	if a < 30.0:      # левентик — мёртвая зона
		return 0.1
	elif a < 60.0:    # крутой бейдевинд
		return 0.45 + (a - 30.0) / 30.0 * 0.25   # 0.45..0.70
	elif a < 90.0:    # бейдевинд/галфвинд
		return 0.70 + (a - 60.0) / 30.0 * 0.20   # 0.70..0.90
	elif a < 135.0:   # бакштаг — лучший курс
		return 0.90 + (a - 90.0) / 45.0 * 0.10   # 0.90..1.00
	else:             # фордевинд — чуть медленнее бакштага
		return 1.0 - (a - 135.0) / 45.0 * 0.12   # 1.00..0.88


## Итоговая скорость в узлах.
static func ship_speed(ship, wind_from_deg: float, wind_strength: float, navigation_skill: int) -> float:
	if ship.is_crew_critical():
		return 0.0
	var base: float = ship.spec()["base_speed"]
	# Угол между курсом и направлением, ОТКУДА дует ветер.
	var angle := wrapf(ship.heading - wind_from_deg, -180.0, 180.0)
	var profile := wind_profile(angle)
	var sail_hp: float = ship.sails_frac()
	var skill_bonus := 1.0 + navigation_skill * 0.02   # +2% за очко навыка
	var wind_mult := clampf(wind_strength / 10.0, 0.2, 1.5)
	return base * ship.sail_setting * profile * sail_hp * wind_mult * skill_bonus


## Скорость поворота, градусов в секунду. Без хода руль не работает.
static func turn_speed(ship, current_speed: float, navigation_skill: int) -> float:
	var base: float = ship.spec()["turn_rate"]
	var speed_factor := clampf(current_speed / 6.0, 0.0, 1.0)
	return base * speed_factor * (1.0 + navigation_skill * 0.015)


## Смена ветра между боями/днями (детерминируемо через rng).
static func drift_wind(wind_from_deg: float, wind_strength: float, rng: RandomNumberGenerator) -> Dictionary:
	var new_dir := wrapf(wind_from_deg + rng.randf_range(-25.0, 25.0), 0.0, 360.0)
	var new_str := clampf(wind_strength + rng.randf_range(-2.0, 2.0), 2.0, 15.0)
	return {"from": new_dir, "strength": new_str}
