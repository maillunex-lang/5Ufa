extends MarginContainer
## Город. Здания подписаны. Системы за ними ещё не сделаны и не притворяются открытыми.
## Рисованного города нет: плитки временные. Условия «после этапа» тестовые и тоже не открывают экран.

const BUILDINGS := [
	{"name": "Портал призыва", "need": 2},
	{"name": "Арена", "need": 5},
	{"name": "Подземелья", "need": 3},
	{"name": "Магазин", "need": 4},
]


func _ready() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 24)
	add_theme_constant_override("margin_bottom", 24)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	add_child(v)
	v.add_child(Ui.label("Город", 36, Ui.token_color("gold", Color.html("#c6a15a"))))
	v.add_child(Ui.label("Рисованного города ещё нет. Здания подписаны, но внутрь не ведут: эти системы не сделаны.", 20, Ui.token_color("muted", Color.html("#b7aa96"))))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	v.add_child(grid)
	var done := State.max_cleared()
	for b in BUILDINGS:
		var reached: bool = done >= int(b["need"]) - 1
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 200)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hint := "система не сделана"
		if not reached:
			hint = "система не сделана · метка после этапа %d" % (int(b["need"]) - 1)
		btn.text = "%s\n%s" % [b["name"], hint]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 28)
		btn.add_theme_color_override("font_color", Ui.token_color("text", Color.html("#f4ecdf")))
		var panel := Ui.box(Ui.token_color("panel", Color(0.11, 0.094, 0.078)), 12, Ui.token_color("gold", Color.html("#c6a15a")), 2)
		btn.add_theme_stylebox_override("normal", panel)
		btn.add_theme_stylebox_override("hover", panel)
		btn.add_theme_stylebox_override("pressed", panel)
		var name: String = b["name"]
		btn.pressed.connect(func():
			Ui.alert(self, "%s ещё не сделан. Кнопка ничего не открывает и ничего не продаёт." % name))
		grid.add_child(btn)
