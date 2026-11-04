extends ColorRect
## Настройки, которые уже есть. Звук, уведомления и прочий несделанный функционал сюда не рисуются.

var _box: VBoxContainer


func _ready() -> void:
	color = Color(0, 0, 0, 0.72)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := Ui.panel()
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	p.add_child(_box)
	_box.add_child(Ui.label("Настройки", 40, Ui.token_color("gold", Color.html("#e6c36a"))))
	_box.add_child(Ui.label("Сборка v" + str(ProjectSettings.get_setting("application/config/version", "?")), 28))
	_box.add_child(Ui.label("Отдельных переключателей звука и уведомлений в этой сборке нет.", 24, Ui.token_color("muted", Color.html("#c5d4d2"))))
	var acc := Ui.button("Аккаунт", 30, 90)
	acc.pressed.connect(func():
		var host := _hub()
		if host.has_method("open_overlay"):
			host.open_overlay(preload("res://account.gd").new())
		queue_free())
	_box.add_child(acc)
	var close := Ui.button("Закрыть", 28, 84)
	close.pressed.connect(queue_free)
	_box.add_child(close)


func _hub() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method("open_screen"):
			return n
		n = n.get_parent()
	return self
