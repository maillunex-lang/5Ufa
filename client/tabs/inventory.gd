extends MarginContainer
## Инвентарь. Предметов и экипировки в этой версии нет — честно показываем пустой экран.

func _ready() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 24)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	add_child(v)
	v.add_child(Ui.label("Инвентарь", 44))
	v.add_child(Ui.label("Здесь пока ничего нет: экипировка и предметы появятся на следующих этапах разработки.", 30, Color(1, 1, 1, 0.6)))
