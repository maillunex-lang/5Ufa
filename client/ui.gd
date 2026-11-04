class_name Ui
extends RefCounted
## Мелкие помощники для построения интерфейса кодом.

static func label(text: String, size: int = 30, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size: int = 30, min_h: int = 96) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	return b


static func box(color: Color, radius: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


static func panel(color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(color))
	return p


## Всплывающее сообщение поверх экрана с кнопкой «ОК».
static func alert(parent: Control, text: String) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := panel(Color(0.16, 0.18, 0.24))
	p.custom_minimum_size = Vector2(560, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	p.add_child(v)
	v.add_child(label(text, 30))
	var ok := button("ОК", 30, 80)
	ok.pressed.connect(overlay.queue_free)
	v.add_child(ok)
	parent.add_child(overlay)


static func line_edit(placeholder: String, secret: bool = false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 90)
	e.add_theme_font_size_override("font_size", 30)
	return e


## Окно с резервным кодом: он показывается один раз. on_continue вызывается после «Я сохранил».
static func recovery_code_dialog(parent: Control, code: String, on_continue: Callable) -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.85)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := panel(Color(0.14, 0.16, 0.22))
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	p.add_child(v)
	v.add_child(label("Резервный код", 40))
	v.add_child(label("Он нужен, чтобы восстановить доступ, если забудете пароль. Показывается один раз: запишите или скопируйте его сейчас.", 26, Color(1, 1, 1, 0.8)))
	var code_l := label(code, 38, Color(1, 0.85, 0.4))
	code_l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(code_l)
	var copy := button("Скопировать", 30, 84)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		copy.text = "Скопировано")
	v.add_child(copy)
	var ok := button("Я сохранил код", 32, 96)
	ok.pressed.connect(func():
		overlay.queue_free()
		on_continue.call())
	v.add_child(ok)
	parent.add_child(overlay)
