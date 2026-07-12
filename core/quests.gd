## Квесты губернаторов: доставка груза, охота на пирата, перевозка пассажира.
extends RefCounted

const World := preload("res://core/world.gd")
const Goods := preload("res://core/goods.gd")

var active: Array = []   # массив словарей-квестов
var next_id: int = 1


## Сгенерировать предложение квеста в колонии.
func generate_offer(from_island: String, day: int, rng: RandomNumberGenerator) -> Dictionary:
	var others := World.island_ids().filter(func(i): return i != from_island)
	var dest: String = others[rng.randi_range(0, others.size() - 1)]
	var dist := World.distance(from_island, dest)
	var kind: String = ["deliver", "hunt", "passenger"][rng.randi_range(0, 2)]
	var quest := {
		"id": next_id, "kind": kind, "from": from_island, "to": dest,
		"deadline_day": day + 6 + int(dist / 80.0),
		"reward": 300 + int(dist * 2.5) + rng.randi_range(0, 200),
	}
	match kind:
		"deliver":
			var goods: Array = Goods.all_ids()
			quest["goods"] = goods[rng.randi_range(0, goods.size() - 1)]
			quest["units"] = rng.randi_range(20, 80)
			quest["title"] = "Доставить груз в %s" % World.island(dest)["name"]
		"hunt":
			quest["target_ship"] = ["lugger", "sloop", "barque", "brig"][rng.randi_range(0, 3)]
			quest["reward"] += 400
			quest["title"] = "Потопить пирата у %s" % World.island(dest)["name"]
		"passenger":
			quest["title"] = "Доставить пассажира в %s" % World.island(dest)["name"]
	return quest


func accept(quest: Dictionary, ship = null) -> bool:
	if quest["kind"] == "deliver" and ship != null:
		if not ship.add_cargo(quest["goods"], quest["units"]):
			return false
	active.append(quest)
	next_id += 1
	return true


## Проверить выполнение при событии. event: {"type": "arrived"/"sunk_pirate", ...}
## Возвращает завершённые квесты (уже убраны из активных).
func check_completion(event: Dictionary, day: int, ship = null) -> Array:
	var done: Array = []
	var still: Array = []
	for q in active:
		var completed := false
		match q["kind"]:
			"deliver":
				if event.get("type") == "arrived" and event.get("island") == q["to"] and ship != null:
					completed = ship.remove_cargo(q["goods"], q["units"])
			"passenger":
				if event.get("type") == "arrived" and event.get("island") == q["to"]:
					completed = true
			"hunt":
				if event.get("type") == "sunk_pirate" and event.get("ship_type") == q["target_ship"]:
					completed = true
		if completed and day <= int(q["deadline_day"]):
			done.append(q)
		else:
			still.append(q)
	active = still
	return done


## Убрать просроченные. Возвращает их список (для штрафа репутации).
func expire(day: int) -> Array:
	var expired := active.filter(func(q): return day > int(q["deadline_day"]))
	active = active.filter(func(q): return day <= int(q["deadline_day"]))
	return expired


func to_dict() -> Dictionary:
	return {"active": active.duplicate(true), "next_id": next_id}


static func from_dict(d: Dictionary) -> RefCounted:
	var q = load("res://core/quests.gd").new()
	q.active = d["active"].duplicate(true)
	q.next_id = int(d["next_id"])
	return q
