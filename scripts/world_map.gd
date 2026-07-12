## Глобальная карта архипелага: острова, ветер, переходы между колониями.
extends Control

const World := preload("res://core/world.gd")

const MAP_W := 1000.0
const MAP_H := 800.0

var _status: Label
var _log_label: RichTextLabel
var _map_area: Control


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("123a5c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 40
	top.add_theme_constant_override("separation", 24)
	add_child(top)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color("e8c872"))
	top.add_child(_status)

	var back := Button.new()
	back.text = "В порт"
	back.pressed.connect(func(): Game.goto_port())
	top.add_child(back)

	var menu_btn := Button.new()
	menu_btn.text = "Меню"
	menu_btn.pressed.connect(func(): Game.save_game(); Game.goto_menu())
	top.add_child(menu_btn)

	_map_area = Control.new()
	_map_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_area.offset_top = 48
	_map_area.offset_bottom = -140
	add_child(_map_area)

	_log_label = RichTextLabel.new()
	_log_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_log_label.offset_top = -132
	_log_label.bbcode_enabled = true
	_log_label.add_theme_color_override("default_color", Color("cfe3f5"))
	add_child(_log_label)

	_build_islands()
	_refresh_status()
	_show_last_log()


func _map_to_screen(pos: Array) -> Vector2:
	var size := _map_area.size
	if size.x < 10:
		size = Vector2(1280, 530)
	return Vector2(pos[0] / MAP_W * size.x, pos[1] / MAP_H * size.y)


func _build_islands() -> void:
	await get_tree().process_frame  # дождаться раскладки, чтобы знать размер
	for id in World.island_ids():
		var isl := World.island(id)
		var btn := Button.new()
		var here: bool = Game.state.current_island == id
		var closed: bool = Game.state.world.is_port_hostile(id)
		var nation_name: String = World.NATIONS[isl["nation"]]["name"]
		btn.text = "%s%s\n(%s)%s" % ["⚓ " if here else "", isl["name"], nation_name, "  ✖" if closed else ""]
		btn.position = _map_to_screen(isl["pos"]) - Vector2(60, 20)
		btn.custom_minimum_size = Vector2(120, 48)
		btn.add_theme_color_override("font_color", Color(World.NATIONS[isl["nation"]]["color"]))
		btn.disabled = here
		btn.pressed.connect(_on_island_clicked.bind(id))
		_map_area.add_child(btn)


func _refresh_status() -> void:
	var s = Game.state
	var isl_name: String = World.island(s.current_island)["name"] if s.current_island != "" else "в море"
	_status.text = "День %d  |  %s  |  %s: %d зол.  |  Корабль: %s (команда %d)  |  Ветер: %d° / %.0f узл." % [
		s.day, isl_name, s.character.char_name, s.character.gold,
		s.ship.custom_name, s.ship.crew, int(s.wind["from"]), s.wind["strength"]]


func _show_last_log() -> void:
	var log: Dictionary = Game.last_sail_log
	if log.is_empty():
		_log_label.text = "Выберите остров, чтобы поднять паруса."
		return
	var lines: Array = ["Переход занял %d дн. Жалование: %d зол." % [log["days"], log["wages_paid"]]]
	if int(log.get("starved", 0)) > 0:
		lines.append("[color=#e57373]От голода умерло %d человек![/color]" % log["starved"])
	for q in log.get("completed_quests", []):
		lines.append("[color=#81c784]Задание выполнено: %s (+%d зол.)[/color]" % [q["title"], q["reward"]])
	var enc = log.get("encounter")
	if enc != null and not enc["hostile"]:
		lines.append("Встречен %s корабль (%s) — разошлись мирно." % [
			World.NATIONS[enc["nation"]]["name"], enc["ship_type"]])
	_log_label.text = "\n".join(lines)
	Game.last_sail_log = {}


func _on_island_clicked(id: String) -> void:
	if Game.state.world.is_port_hostile(id):
		_log_label.text = "[color=#e57373]Порт %s закрыт для вас: колония враждебна. Но встать на рейд можно...[/color]" % World.island(id)["name"]
	var battle: bool = Game.sail_to(id)
	if not battle:
		# Перерисовать карту по прибытии.
		get_tree().reload_current_scene()
