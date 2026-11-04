extends Control
## Город на фоне. Подписи зданий и боковые кнопки всегда видны.
## Неготовые системы по нажатию пишут условие или «в разработке» и ничего не выдают.

const RAIL_ART := {
	"quests": "icon_rail_quests.png",
	"offers": "icon_rail_offers.png",
	"deals": "icon_rail_deals.png",
	"afk": "icon_rail_afk.png",
}


func _ready() -> void:
	var shell := Ui.shell()
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := Ui.art_texture(str(shell.get("cityArt", "city_main.jpg")))
	if tex != null:
		bg.texture = tex
	else:
		var fill := ColorRect.new()
		fill.color = Ui.token_color("bg", Color.html("#0c1c22"))
		fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(fill)
	add_child(bg)

	var rail := VBoxContainer.new()
	rail.add_theme_constant_override("separation", 10)
	rail.anchor_left = 0.0
	rail.anchor_right = 0.0
	rail.offset_left = 12
	rail.offset_right = 132
	rail.offset_top = 150
	rail.offset_bottom = 620
	add_child(rail)
	for it in shell.get("rail", []):
		rail.add_child(_rail_button(it))

	for it in shell.get("buildings", []):
		add_child(_building(it))


func _hub() -> Node:
	var n: Node = self
	while n:
		if n.has_method("open_screen"):
			return n
		n = n.get_parent()
	return self


func _plaque(text: String, wide: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 22 if wide else 16)
	b.add_theme_color_override("font_color", Color.html("#f7f1e4"))
	b.add_theme_color_override("font_hover_color", Color.html("#ffffff"))
	b.add_theme_color_override("font_pressed_color", Color.html("#ffffff"))
	var box := Ui.box(Color(0.07, 0.18, 0.2, 0.92), 10, Color.html("#e6c36a"), 2)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	b.add_theme_stylebox_override("normal", box)
	b.add_theme_stylebox_override("hover", box)
	b.add_theme_stylebox_override("pressed", box)
	b.add_theme_stylebox_override("focus", box)
	return b


func _building(item: Dictionary) -> Button:
	var b := _plaque(State.loc(item.get("label", "")), true)
	var x := float(item.get("x", 50)) / 100.0
	var y := float(item.get("y", 50)) / 100.0
	b.anchor_left = x
	b.anchor_right = x
	b.anchor_top = y
	b.anchor_bottom = y
	b.offset_left = -130
	b.offset_right = 130
	b.offset_top = -26
	b.offset_bottom = 26
	b.pressed.connect(func(): Ui.shell_press(self, item, _hub()))
	return b


func _rail_button(item: Dictionary) -> Button:
	var b := _plaque(State.loc(item.get("label", "")), false)
	b.custom_minimum_size = Vector2(120, 108)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var art := str(RAIL_ART.get(str(item.get("id", "")), ""))
	var tex := Ui.art_texture(art)
	if tex != null:
		b.icon = tex
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.pressed.connect(func(): Ui.shell_press(self, item, _hub()))
	return b
