## Main menu: new game (name + nation), continue, quit.
extends Control

const GameState := preload("res://core/game_state.gd")
const World := preload("res://core/world.gd")

var _name_edit: LineEdit
var _nation_option: OptionButton
var _nation_ids: Array = []


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("0a1a2f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)

	var title := Label.new()
	title.text = "CORSAIRS"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("e8c872"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Wind of Freedom — an open remake in the spirit of Sea Dogs II"
	subtitle.add_theme_color_override("font_color", Color("9db4c8"))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)

	box.add_child(HSeparator.new())

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Captain's name"
	_name_edit.text = "Nathaniel"
	box.add_child(_name_edit)

	_nation_option = OptionButton.new()
	for n in ["england", "france", "spain", "holland", "pirates"]:
		_nation_ids.append(n)
		_nation_option.add_item("Serve: %s" % World.NATIONS[n]["name"])
	box.add_child(_nation_option)

	var new_btn := Button.new()
	new_btn.text = "New Game"
	new_btn.pressed.connect(_on_new_game)
	box.add_child(new_btn)

	var cont_btn := Button.new()
	cont_btn.text = "Continue"
	cont_btn.disabled = not GameState.has_save()
	cont_btn.pressed.connect(func(): Game.continue_game())
	box.add_child(cont_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.pressed.connect(func(): get_tree().quit())
	box.add_child(quit_btn)

	var hint := Label.new()
	hint.text = "At sea: WASD — sails and rudder, Q/E — broadsides,\nR — ammo type, B — board"
	hint.add_theme_color_override("font_color", Color("5c7a94"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _on_new_game() -> void:
	var captain := _name_edit.text.strip_edges()
	if captain.is_empty():
		captain = "Captain"
	Game.new_game(captain, _nation_ids[_nation_option.selected])
