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
