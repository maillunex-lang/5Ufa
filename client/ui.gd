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


static func token_color(key: String, fallback: Color) -> Color:
	var colors: Dictionary = State.content.get("ui", {}).get("colors", {})
	var hex := str(colors.get(key, ""))
	if hex.begins_with("#") and hex.length() == 7:
		return Color.html(hex)
	return fallback


static func box(color: Color, radius: int = 16, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	return s


static func panel(color: Color = Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var c := color if color.a > 0.0 else token_color("panel", Color(0.11, 0.094, 0.078, 1))
	if color.a <= 0.0:
		c.a = 0.94
	p.add_theme_stylebox_override("panel", box(c, 12, token_color("gold", Color.html("#c6a15a")), 2))
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


static func grouped(n: int) -> String:
	var neg := n < 0
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3, 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if neg else "") + s + out


static func shell() -> Dictionary:
	var ui: Dictionary = State.content.get("ui", {})
	var s: Variant = ui.get("shell", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}


static func art_texture(file_name: String) -> Texture2D:
	if file_name == "":
		return null
	var stem := file_name.get_basename() if file_name.find(".") >= 0 else file_name
	var from_media := Media.texture(stem)
	if from_media != null:
		return from_media
	for folder in ["res://assets/backgrounds/", "res://assets/ui/"]:
		for ext in [".jpg", ".jpeg", ".png"]:
			var path: String = str(folder) + stem + str(ext)
			if ResourceLoader.exists(path):
				return load(path)
		if file_name.find(".") >= 0 and ResourceLoader.exists(folder + file_name):
			return load(folder + file_name)
	return null


static func unlocked(unlock: String) -> bool:
	if unlock == "" or unlock == "always":
		return true
	if unlock.begins_with("stage:"):
		var want := int(unlock.get_slice(":", 1))
		for cleared in State.me.get("clearedStages", []):
			if int(cleared) == want:
				return true
		return false
	if unlock.begins_with("quest:"):
		return State.story_done(unlock.get_slice(":", 1))
	return false


static func lock_text(unlock: String) -> String:
	if unlock.begins_with("stage:"):
		return "Откроется после этапа %d" % int(unlock.get_slice(":", 1))
	if unlock.begins_with("quest:"):
		return "Откроется после сюжетного задания"
	return "Пока закрыто"


## Неготовый раздел не притворяется рабочей системой. Готовый только переключает уже существующий экран.
static func shell_press(parent: Control, item: Dictionary, host: Node) -> void:
	var unlock := str(item.get("unlock", "always"))
	if not unlocked(unlock):
		alert(parent, lock_text(unlock))
		return
	var status := str(item.get("status", "unbuilt"))
	var title: String = State.loc(item.get("label", ""))
	if status == "unbuilt":
		alert(parent, title + " в разработке. Раздел ничего не открывает и ничего не выдаёт.")
		return
	if status == "screen" and host.has_method("open_screen"):
		host.open_screen(str(item.get("screen", "")))
		return
	var action := str(item.get("action", ""))
	if action == "settings" and host.has_method("open_overlay"):
		host.open_overlay(preload("res://settings.gd").new())
	elif action == "account" and host.has_method("open_overlay"):
		host.open_overlay(preload("res://account.gd").new())
	elif action.begins_with("tab:") and host.has_method("select_tab"):
		host.select_tab(int(action.get_slice(":", 1)))
	else:
		alert(parent, title + " в разработке.")


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
