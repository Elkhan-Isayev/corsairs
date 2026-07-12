## Player character: level, XP, skills (Sea Dogs-style system),
## boarding health, gold.
extends RefCounted

const SKILLS := ["leadership", "fencing", "navigation", "accuracy", "cannons",
	"boarding", "defense", "repair", "trade", "luck"]

const SKILL_NAMES := {
	"leadership": "Leadership", "fencing": "Fencing", "navigation": "Navigation",
	"accuracy": "Accuracy", "cannons": "Cannons", "boarding": "Boarding",
	"defense": "Defense", "repair": "Repair", "trade": "Trade", "luck": "Luck",
}

const MAX_SKILL := 10
const SKILL_POINTS_PER_LEVEL := 2

var char_name: String = "Captain"
var nation: String = "england"
var level: int = 1
var xp: int = 0
var free_skill_points: int = 0
var skills := {}
var gold: int = 0
var max_hp: int = 80
var hp: int = 80


static func create(name := "Captain", p_nation := "england") -> RefCounted:
	var c = load("res://core/character.gd").new()
	c.char_name = name
	c.nation = p_nation
	for s in SKILLS:
		c.skills[s] = 1
	c.gold = 1000
	return c


## XP required for the next level grows quadratically.
static func xp_for_level(lvl: int) -> int:
	return 100 * lvl * lvl


func add_xp(amount: int) -> Dictionary:
	assert(amount >= 0)
	xp += amount
	var levels_gained := 0
	while xp >= xp_for_level(level):
		xp -= xp_for_level(level)
		level += 1
		levels_gained += 1
		free_skill_points += SKILL_POINTS_PER_LEVEL
		max_hp += 10
		hp = max_hp
	return {"levels_gained": levels_gained, "new_level": level}


func skill(id: String) -> int:
	return int(skills.get(id, 0))


func raise_skill(id: String) -> bool:
	if not skills.has(id) or free_skill_points <= 0 or skill(id) >= MAX_SKILL:
		return false
	skills[id] += 1
	free_skill_points -= 1
	return true


func can_afford(price: int) -> bool:
	return gold >= price


func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	gold -= price
	return true


func earn(amount: int) -> void:
	assert(amount >= 0)
	gold += amount


## Maximum squadron size depends on Leadership.
func max_squadron() -> int:
	return 1 + int(skill("leadership") / 3.0)


func to_dict() -> Dictionary:
	return {
		"char_name": char_name, "nation": nation, "level": level, "xp": xp,
		"free_skill_points": free_skill_points, "skills": skills.duplicate(),
		"gold": gold, "max_hp": max_hp, "hp": hp,
	}


static func from_dict(d: Dictionary) -> RefCounted:
	var c = load("res://core/character.gd").new()
	c.char_name = d["char_name"]
	c.nation = d["nation"]
	c.level = int(d["level"])
	c.xp = int(d["xp"])
	c.free_skill_points = int(d["free_skill_points"])
	c.skills = {}
	for k in d["skills"]:
		c.skills[k] = int(d["skills"][k])
	c.gold = int(d["gold"])
	c.max_hp = int(d["max_hp"])
	c.hp = int(d["hp"])
	return c
