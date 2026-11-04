extends MarginContainer
## Город. Здания с постоянными подписями. Рисованный фон — позже (нужна графика из трека D),
## сейчас плитки. Условия открытия ТЕСТОВЫЕ; сами системы (призыв, арена, подземелья, магазин) ещё не реализованы.

const BUILDINGS := [
	{"name": "Портал призыва", "need": 2, "color": Color(0.35, 0.25, 0.55)},
	{"name": "Арена", "need": 5, "color": Color(0.55, 0.28, 0.25)},
	{"name": "Подземелья", "need": 3, "color": Color(0.25, 0.42, 0.35)},
	{"name": "Магазин", "need": 4, "color": Color(0.5, 0.4, 0.2)},
]


func _ready() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 24)
	add_theme_constant_override("margin_bottom", 24)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	add_child(v)
	v.add_child(Ui.label("Город", 44))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	v.add_child(grid)
	var done := State.max_cleared()
	for b in BUILDINGS:
		var open: bool = done >= int(b["need"]) - 1
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(320, 260)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.text = "%s\n%s" % [b["name"], "" if open else "Откроется после этапа %d" % (int(b["need"]) - 1)]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 30)
		btn.add_theme_stylebox_override("normal", Ui.box(b["color"] if open else Color(0.2, 0.2, 0.24)))
		btn.add_theme_stylebox_override("hover", Ui.box((b["color"] as Color).lightened(0.15)))
		btn.add_theme_stylebox_override("pressed", Ui.box((b["color"] as Color).lightened(0.3)))
		var name: String = b["name"]
		btn.pressed.connect(func():
			if open:
				Ui.alert(self, "%s: эта система будет добавлена на следующих этапах разработки." % name)
			else:
				Ui.alert(self, "%s закрыт. Условие: пройти этап %d (тестовое значение)." % [name, int(b["need"]) - 1]))
		grid.add_child(btn)
