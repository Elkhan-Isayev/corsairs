## Port: "Port", "Market", "Shipyard" and "Captain" tabs.
extends Control

const World := preload("res://core/world.gd")
const Goods := preload("res://core/goods.gd")
const ShipTypes := preload("res://core/ship_types.gd")
const Ammo := preload("res://core/ammo.gd")
const Character := preload("res://core/character.gd")

var _tabs: TabContainer
var _header: Label
var _quest_offers: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1b2a38")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 10
	root.offset_bottom = -10
	add_child(root)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", 22)
	_header.add_theme_color_override("font_color", Color("e8c872"))
	root.add_child(_header)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	_generate_quest_offers()
	_rebuild()


func _island() -> Dictionary:
	return World.island(Game.state.current_island)


func _generate_quest_offers() -> void:
	_quest_offers = []
	var s = Game.state
	for i in 3:
		_quest_offers.append(s.quests.generate_offer(s.current_island, s.day, s.rng))


func _rebuild() -> void:
	var s = Game.state
	var isl := _island()
	_header.text = "%s — %s colony | Day %d | %d gold | %s: hull %d%%, crew %d/%d" % [
		isl["name"], World.NATIONS[isl["nation"]]["name"], s.day, s.character.gold,
		s.ship.custom_name, int(s.ship.hull_frac() * 100), s.ship.crew, s.ship.spec()["max_crew"]]

	var current_tab := _tabs.current_tab
	for c in _tabs.get_children():
		c.queue_free()
	_tabs.add_child(_build_port_tab())
	_tabs.add_child(_build_market_tab())
	_tabs.add_child(_build_shipyard_tab())
	_tabs.add_child(_build_captain_tab())
	if current_tab >= 0 and current_tab < 4:
		_tabs.current_tab = maxi(current_tab, 0)


func _scroll_tab(title: String) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	return sc


func _label(text: String, color := "cfe3f5") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(color))
	return l


# --- Port tab ---

func _build_port_tab() -> Control:
	var sc := _scroll_tab("Port")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	var s = Game.state
	var isl := _island()

	var rep: int = s.world.reputation(isl["nation"])
	box.add_child(_label("%s's attitude toward you: %d" % [World.NATIONS[isl["nation"]]["name"], rep],
		"81c784" if rep >= 0 else "e57373"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	var sail := Button.new()
	sail.text = "⚓ Set sail (map)"
	sail.pressed.connect(func(): Game.goto_map())
	row.add_child(sail)

	var hire := Button.new()
	hire.text = "Hire 10 sailors (%d gold)" % (10 * 20)
	hire.pressed.connect(func():
		if not Game.state.hire_crew(10):
			OS.alert("Not enough gold or berths.", "Tavern")
		_rebuild())
	row.add_child(hire)

	var repair := Button.new()
	repair.text = "Repair ship"
	repair.pressed.connect(func():
		var cost: int = Game.state.repair_ship_at_shipyard()
		if cost < 0:
			OS.alert("Not enough gold for repairs.", "Shipyard")
		elif cost == 0:
			OS.alert("The ship is in perfect shape.", "Shipyard")
		_rebuild())
	row.add_child(repair)

	var save_btn := Button.new()
	save_btn.text = "Save game"
	save_btn.pressed.connect(func(): Game.save_game(); OS.alert("Game saved.", "Corsairs"))
	row.add_child(save_btn)

	box.add_child(HSeparator.new())
	box.add_child(_label("— The governor offers —", "e8c872"))
	for offer in _quest_offers:
		var qrow := HBoxContainer.new()
		qrow.add_theme_constant_override("separation", 10)
		box.add_child(qrow)
		var desc := "%s | reward %d gold | due: day %d" % [offer["title"], offer["reward"], offer["deadline_day"]]
		if offer["kind"] == "deliver":
			desc += " | cargo: %s ×%d" % [Goods.get_type(offer["goods"])["name"], offer["units"]]
		qrow.add_child(_label(desc))
		var take := Button.new()
		take.text = "Accept"
		take.pressed.connect(func():
			if Game.state.quests.accept(offer, Game.state.ship):
				_quest_offers.erase(offer)
			else:
				OS.alert("Not enough cargo space!", "Governor")
			_rebuild())
		qrow.add_child(take)

	box.add_child(HSeparator.new())
	box.add_child(_label("— Active quests —", "e8c872"))
	if s.quests.active.is_empty():
		box.add_child(_label("No active quests."))
	for q in s.quests.active:
		box.add_child(_label("• %s (by day %d, %d gold)" % [q["title"], q["deadline_day"], q["reward"]]))
	return sc


# --- Market tab ---

func _build_market_tab() -> Control:
	var sc := _scroll_tab("Market")
	var grid := GridContainer.new()
	grid.columns = 7
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(grid)

	var s = Game.state
	var m = s.world.market(s.current_island)
	var trade: int = s.character.skill("trade")

	for h in ["Goods", "Stock", "Buy at", "Sell at", "In hold", "", ""]:
		grid.add_child(_label(h, "e8c872"))

	for g in Goods.all_ids():
		var info := Goods.get_type(g)
		var in_hold: int = int(s.ship.cargo.get(g, 0))
		var is_export: bool = g in m.exports
		var is_import: bool = g in m.imports
		var name_color := "81c784" if is_export else ("e57373" if is_import else "cfe3f5")
		grid.add_child(_label(info["name"] + ("  ↓" if is_export else ("  ↑" if is_import else "")), name_color))
		grid.add_child(_label(str(m.stock.get(g, 0))))
		grid.add_child(_label("%d g" % m.buy_price(g, trade)))
		grid.add_child(_label("%d g" % m.sell_price(g, trade)))
		grid.add_child(_label(str(in_hold)))

		var buy := Button.new()
		buy.text = "Buy 10"
		buy.pressed.connect(func():
			if m.player_buy(g, 10, s.character, s.ship, trade) < 0:
				OS.alert("Deal impossible: no gold, stock or space.", "Market")
			_rebuild())
		grid.add_child(buy)

		var sell := Button.new()
		sell.text = "Sell 10"
		sell.disabled = in_hold < 10
		sell.pressed.connect(func():
			if m.player_sell(g, 10, s.character, s.ship, trade) < 0:
				OS.alert("You don't have that much cargo.", "Market")
			_rebuild())
		grid.add_child(sell)

	return sc


# --- Shipyard tab ---

func _build_shipyard_tab() -> Control:
	var sc := _scroll_tab("Shipyard")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	var s = Game.state
	var isl := _island()

	box.add_child(_label("— Ammunition (hold space: %d) —" % s.ship.cargo_free(), "e8c872"))
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 10)
	box.add_child(arow)
	for a in Ammo.ORDER:
		var t := Ammo.get_type(a)
		var b := Button.new()
		b.text = "%s ×50 (%d g) [have %d]" % [t["name"], t["price"] * 50, s.ship.ammo_stock.get(a, 0)]
		b.pressed.connect(func():
			if not Game.state.buy_ammo(a, 50, t["price"]):
				OS.alert("Not enough gold.", "Shipyard")
			_rebuild())
		arow.add_child(b)

	box.add_child(HSeparator.new())
	box.add_child(_label("— Ships for sale (yours is traded in) —", "e8c872"))
	var trade_in := int(s.ship.spec()["price"] * 0.5 * s.ship.hull_frac())
	box.add_child(_label("Your %s trades in for: %d gold" % [s.ship.spec()["name"], trade_in]))

	for id in ShipTypes.available_for_shipyard(int(isl["tier"])):
		if id == s.ship.type_id:
			continue
		var t := ShipTypes.get_type(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		row.add_child(_label("%s (rank %d): hull %d, guns %d, hold %d, speed %.1f — %d gold" % [
			t["name"], t["rank"], t["hull"], t["cannons"], t["cargo"], t["base_speed"], t["price"]]))
		var buy := Button.new()
		var to_pay := maxi(int(t["price"]) - trade_in, 0)
		buy.text = "Buy (pay %d)" % to_pay
		buy.disabled = not s.character.can_afford(to_pay)
		buy.pressed.connect(func():
			if Game.state.buy_ship(id):
				OS.alert("Congratulations on your new %s!" % t["name"], "Shipyard")
			_rebuild())
		row.add_child(buy)
	return sc


# --- Captain tab ---

func _build_captain_tab() -> Control:
	var sc := _scroll_tab("Captain")
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	sc.add_child(box)
	var c = Game.state.character

	box.add_child(_label("%s, level %d (%s)" % [c.char_name, c.level, World.NATIONS[c.nation]["name"]], "e8c872"))
	box.add_child(_label("XP: %d / %d | Free skill points: %d" % [c.xp, Character.xp_for_level(c.level), c.free_skill_points]))
	box.add_child(HSeparator.new())

	for skill_id in Character.SKILLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		box.add_child(row)
		var bar := "█".repeat(c.skill(skill_id)) + "░".repeat(Character.MAX_SKILL - c.skill(skill_id))
		row.add_child(_label("%-12s %s %d" % [Character.SKILL_NAMES[skill_id], bar, c.skill(skill_id)]))
		if c.free_skill_points > 0 and c.skill(skill_id) < Character.MAX_SKILL:
			var plus := Button.new()
			plus.text = "+"
			plus.pressed.connect(func(): c.raise_skill(skill_id); _rebuild())
			row.add_child(plus)

	box.add_child(HSeparator.new())
	box.add_child(_label("— Standing with the nations —", "e8c872"))
	for n in World.NATIONS:
		var rep: int = Game.state.world.reputation(n)
		box.add_child(_label("%s: %d" % [World.NATIONS[n]["name"], rep],
			"81c784" if rep >= 0 else "e57373"))
	return sc
