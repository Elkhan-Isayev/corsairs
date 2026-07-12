## Абордаж: раунды рукопашной между командами. Сила стороны зависит от
## численности, навыка абордажа и фехтования капитана.
extends RefCounted

## Один раунд схватки. Возвращает потери сторон.
static func fight_round(att_crew: int, att_boarding: int, att_fencing: int,
		def_crew: int, def_boarding: int, def_fencing: int,
		rng: RandomNumberGenerator) -> Dictionary:
	var att_power := att_crew * (1.0 + att_boarding * 0.06 + att_fencing * 0.03) * rng.randf_range(0.8, 1.2)
	var def_power := def_crew * (1.0 + def_boarding * 0.06 + def_fencing * 0.03) * rng.randf_range(0.8, 1.2)
	# Потери пропорциональны силе противника; ~12% команды за раунд при равенстве.
	var att_losses := int(ceil(def_power * 0.12 * att_crew / maxf(att_power, 1.0)))
	var def_losses := int(ceil(att_power * 0.12 * def_crew / maxf(def_power, 1.0)))
	att_losses = clampi(att_losses, 1, att_crew)
	def_losses = clampi(def_losses, 1, def_crew)
	return {"att_losses": att_losses, "def_losses": def_losses}


## Полный абордаж до победы. Защитники сдаются, потеряв 70% начальной команды.
## Возвращает: winner ("attacker"/"defender"), потери, число раундов.
static func resolve(attacker, att_skills: Dictionary, defender, def_skills: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var att_start: int = attacker.crew
	var def_start: int = defender.crew
	var rounds := 0
	while rounds < 50:
		rounds += 1
		var r := fight_round(
			attacker.crew, att_skills.get("boarding", 0), att_skills.get("fencing", 0),
			defender.crew, def_skills.get("boarding", 0), def_skills.get("fencing", 0), rng)
		attacker.crew = maxi(attacker.crew - r["att_losses"], 0)
		defender.crew = maxi(defender.crew - r["def_losses"], 0)
		if defender.crew <= int(def_start * 0.3) or defender.crew <= 0:
			return {"winner": "attacker", "rounds": rounds,
				"att_losses": att_start - attacker.crew, "def_losses": def_start - defender.crew}
		if attacker.crew <= int(att_start * 0.3) or attacker.crew <= 0:
			return {"winner": "defender", "rounds": rounds,
				"att_losses": att_start - attacker.crew, "def_losses": def_start - defender.crew}
	return {"winner": "defender", "rounds": rounds,
		"att_losses": att_start - attacker.crew, "def_losses": def_start - defender.crew}


## Трофеи с захваченного корабля: груз, боезапас и корабельная казна.
static func loot(captured, rng: RandomNumberGenerator) -> Dictionary:
	var gold := rng.randi_range(50, 400) * int(captured.spec()["rank"] <= 4) * 3 + rng.randi_range(50, 300)
	return {"gold": gold, "cargo": captured.cargo.duplicate(), "ammo": captured.ammo_stock.duplicate()}
