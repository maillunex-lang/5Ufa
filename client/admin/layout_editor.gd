class_name LayoutEditor
extends VBoxContainer
## Конструктор экранов: экран в рамке телефона, элементы двигаются и растягиваются пальцем
## (угол-ручка внизу справа), привязка к сетке, панель свойств, добавить/копировать/удалить, слои,
## отмена и повтор. Сохраняет ui/screens/<экран>.json в черновик.

const TYPES := {"label": "Надпись", "image": "Картинка", "button": "Кнопка", "panel": "Панель", "slot": "Место"}
const STYLES := ["default", "tile", "icon", "nav", "nav_big"]
const STYLE_NAMES := {"default": "обычная", "tile": "плитка", "icon": "только иконка", "nav": "нижнее меню", "nav_big": "нижнее меню, крупная"}
const SCENES := ["hub", "campaign", "heroes", "summon", "inventory", "test_battle", "more"]
const BADGES := ["", "heroes", "summon", "campaign"]

var host: Node
var screen := ""
var path := ""
var layout: Dictionary = {}
var selected := -1
var grid := 8
var _undo: Array = []
var _redo: Array = []
var _canvas: Control
var _stage: Control
var _sel: Panel
var _handle: ColorRect
var _props: VBoxContainer
var _list: OptionButton
var _k := 0.9
var _drag := {}
var _images: Array = []


func setup(p_host: Node, p_screen: String, p_path: String, p_layout: Dictionary, images: Array) -> void:
	host = p_host
	screen = p_screen
	path = p_path
	layout = p_layout.duplicate(true)
	_images = images
	add_theme_constant_override("separation", 8)
	var avail: float = minf(680.0, host.get_viewport_rect().size.x - 40)
	_k = clampf(avail / ScreenLayout.W, 0.3, 1.0)
	_build_toolbar()
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(ScreenLayout.W, ScreenLayout.H) * _k
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.gui_input.connect(_on_canvas_input)
	add_child(_canvas)
	_stage = Control.new()
	_stage.scale = Vector2(_k, _k)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_stage)
	add_child(_hint("Нажмите на элемент — выделится; тяните — двигается; жёлтый квадрат в углу — размер. Листать страницу — пальцем вне экрана."))
	_list = OptionButton.new()
	_list.custom_minimum_size = Vector2(0, 60)
	_list.item_selected.connect(func(i): _select(i))
	add_child(_list)
	_props = VBoxContainer.new()
	_props.add_theme_constant_override("separation", 6)
	add_child(_props)
	_render()


# --- Отрисовка ----------------------------------------------------------------------------

func _hint(t: String) -> Label:
	var l := Ui.label(t, 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.modulate = Color(1, 1, 1, 0.7)
	return l


func _btn(text: String, cb: Callable, size := 18) -> Button:
	var b := Ui.button(text, cb)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 60)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	return b


func _row(items: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 6)
	for i in items:
		r.add_child(i)
	return r


func _build_toolbar() -> void:
	add_child(_row([_btn("+ Надпись", func(): _add("label")), _btn("+ Картинка", func(): _add("image")),
			_btn("+ Кнопка", func(): _add("button")), _btn("+ Панель", func(): _add("panel"))]))
	var snap := _btn("Сетка: 8", func(): pass)
	snap.pressed.connect(func():
		grid = {8: 4, 4: 1, 1: 16, 16: 8}[grid]
		snap.text = "Сетка: %d" % grid)
	add_child(_row([_btn("Отменить", undo), _btn("Вернуть", redo), snap,
			_btn("Сохранить", save, 20)]))


func _city_preview(box: Control, _el: Dictionary) -> void:
	## В конструкторе вместо живого города — его фон и здания (двигаются в отдельном редакторе)
	var hub: Variant = Content.load_json("ui/hub.json")
	if not hub is Dictionary:
		return
	var bg := TextureRect.new()
	bg.texture = Content.load_texture(str(hub.get("background", "")))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = Vector2(720, float(hub.get("background_height", 1400)))
	box.add_child(bg)
	for b in hub.get("buildings", []):
		var t := Content.load_texture(str(b["image"]))
		if t == null:
			continue
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.size = t.get_size() * float(b.get("scale", 1.0))
		tr.position = Vector2(float(b["x"]), float(b["y"])) - tr.size / 2.0
		box.add_child(tr)


func _render() -> void:
	for c in _stage.get_children():
		c.queue_free()
	var built := ScreenLayout.build(layout, {"edit": true, "edit_widgets": {"city": _city_preview}})
	_stage.add_child(built["root"])
	_sel = Panel.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(1, 0.85, 0.2, 0.08)
	st.border_color = Color("#FFD24A")
	st.set_border_width_all(int(3 / _k))
	_sel.add_theme_stylebox_override("panel", st)
	_sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_sel)
	_handle = ColorRect.new()
	_handle.color = Color("#FFD24A")
	_handle.size = Vector2(34, 34) / _k
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_handle)
	_update_selection()
	_list.clear()
	var els: Array = layout.get("elements", [])
	for i in range(els.size()):
		var e: Dictionary = els[i]
		_list.add_item("%d. %s · %s %s" % [i + 1, TYPES.get(e.get("type"), e.get("type")), e.get("id", ""),
				("«%s»" % str(e.get("text", ""))) if str(e.get("text", "")) != "" else ""])
	if selected >= 0 and selected < els.size():
		_list.selected = selected
	_render_props()


func _update_selection() -> void:
	var els: Array = layout.get("elements", [])
	var on := selected >= 0 and selected < els.size()
	_sel.visible = on
	_handle.visible = on
	if on:
		var e: Dictionary = els[selected]
		_sel.position = Vector2(float(e["x"]), float(e["y"]))
		_sel.size = Vector2(float(e["w"]), float(e["h"]))
		_handle.position = _sel.position + _sel.size - _handle.size / 2.0


# --- Мышь и палец --------------------------------------------------------------------------

func _snap(v: float) -> float:
	return round(v / grid) * grid


func _hit(p: Vector2) -> int:
	var els: Array = layout.get("elements", [])
	for i in range(els.size() - 1, -1, -1):
		var e: Dictionary = els[i]
		if Rect2(float(e["x"]), float(e["y"]), float(e["w"]), float(e["h"])).has_point(p):
			return i
	return -1


func _on_canvas_input(ev: InputEvent) -> void:
	var p: Vector2 = _canvas.get_local_mouse_position() / _k
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var els: Array = layout.get("elements", [])
			var on_handle := selected >= 0 and _handle.visible and Rect2(_handle.position, _handle.size).grow(10).has_point(p)
			if not on_handle:
				var i := _hit(p)
				if i != selected:
					selected = i
					_render()
			if selected < 0:
				return
			var e: Dictionary = els[selected]
			_drag = {"mode": "resize" if on_handle else "move", "from": p, "x": float(e["x"]), "y": float(e["y"]),
					"w": float(e["w"]), "h": float(e["h"]), "before": JSON.stringify(layout), "moved": false}
		elif not _drag.is_empty():
			if _drag["moved"]:
				_push_undo(str(_drag["before"]))
				_render()
			_drag = {}
	elif ev is InputEventMouseMotion and not _drag.is_empty() and selected >= 0:
		var e: Dictionary = layout["elements"][selected]
		var d: Vector2 = p - _drag["from"]
		if d.length() < 3 and not _drag["moved"]:
			return
		_drag["moved"] = true
		if _drag["mode"] == "move":
			e["x"] = _snap(float(_drag["x"]) + d.x)
			e["y"] = _snap(float(_drag["y"]) + d.y)
		else:
			e["w"] = maxf(grid, _snap(float(_drag["w"]) + d.x))
			e["h"] = maxf(grid, _snap(float(_drag["h"]) + d.y))
		# двигаем уже нарисованный элемент, перерисовка — при отпускании
		var root: Control = _stage.get_child(0) if _stage.get_child_count() > 0 else null
		_update_selection()
		if root:
			var node := _node_for(root, selected)
			if node:
				node.position = Vector2(float(e["x"]), float(e["y"]))
				node.size = Vector2(float(e["w"]), float(e["h"]))


func _node_for(root: Control, index: int) -> Control:
	## Элементы идут после фоновых узлов; считаем с конца
	var count: int = layout["elements"].size()
	var shift := root.get_child_count() - count
	var i := shift + index
	return root.get_child(i) as Control if i >= 0 and i < root.get_child_count() else null


# --- Правка ---------------------------------------------------------------------------------

func _push_undo(before: String) -> void:
	_undo.append(before)
	if _undo.size() > 60:
		_undo.pop_front()
	_redo.clear()


func _change(cb: Callable) -> void:
	var before := JSON.stringify(layout)
	cb.call()
	_push_undo(before)
	_render()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(JSON.stringify(layout))
	layout = JSON.parse_string(_undo.pop_back())
	_render()


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(JSON.stringify(layout))
	layout = JSON.parse_string(_redo.pop_back())
	_render()


func _select(i: int) -> void:
	selected = i
	_render()


func _new_id(base: String) -> String:
	var ids := {}
	for e in layout.get("elements", []):
		ids[str(e.get("id", ""))] = true
	var n := 1
	while ids.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


func _add(type: String) -> void:
	var e := {"id": _new_id(type), "type": type, "x": 200, "y": 560, "w": 320, "h": 80}
	match type:
		"label":
			e.merge({"text": "Новая надпись", "size": 28, "color": "text"})
		"image":
			e.merge({"image": "ui/logo.png", "fit": "contain", "w": 200, "h": 200})
		"button":
			e.merge({"text": "Кнопка", "style": "default", "action": {"soon": "Скоро"}})
		"panel":
			e.merge({"color": "#120C22E0", "border": "accent", "border_width": 2, "radius": 16})
	_change(func():
		layout.get_or_add("elements", []).append(e)
		selected = layout["elements"].size() - 1)


func _duplicate() -> void:
	if selected < 0:
		return
	var e: Dictionary = (layout["elements"][selected] as Dictionary).duplicate(true)
	e["id"] = _new_id(str(e["id"]).get_slice("_", 0))
	e["x"] = float(e["x"]) + 24
	e["y"] = float(e["y"]) + 24
	_change(func():
		layout["elements"].insert(selected + 1, e)
		selected += 1)


func _delete() -> void:
	if selected < 0:
		return
	var e: Dictionary = layout["elements"][selected]
	var do_it := func(): _change(func():
		layout["elements"].remove_at(selected)
		selected = -1)
	if str(e.get("type")) == "slot":
		host._confirm("Это место для живого содержимого экрана («%s»). Без него содержимое займёт весь экран. Удалить?" % e.get("widget", e["id"]), do_it, "Удалить")
	else:
		do_it.call()


func _move_layer(d: int) -> void:
	var n: int = layout["elements"].size()
	var j := selected + d
	if selected < 0 or j < 0 or j >= n:
		return
	_change(func():
		var e: Variant = layout["elements"][selected]
		layout["elements"][selected] = layout["elements"][j]
		layout["elements"][j] = e
		selected = j)


# --- Свойства -------------------------------------------------------------------------------

func _field(title: String, value: String, on_set: Callable, numeric := false) -> Control:
	var r := HBoxContainer.new()
	var l := Ui.label(title, 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(170, 0)
	r.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.custom_minimum_size = Vector2(0, 54)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if numeric:
		e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	var apply := func(_x = null):
		var v := e.text.strip_edges()
		if numeric:
			if not v.replace(",", ".").is_valid_float():
				return
			_change(func(): on_set.call(float(v.replace(",", "."))))
		else:
			_change(func(): on_set.call(v))
	e.text_submitted.connect(apply)
	e.focus_exited.connect(apply)
	r.add_child(e)
	return r


func _choice(title: String, options: Array, names: Array, current: String, on_set: Callable) -> Control:
	var r := HBoxContainer.new()
	var l := Ui.label(title, 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(170, 0)
	r.add_child(l)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(0, 54)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(options.size()):
		o.add_item(str(names[i]))
	o.selected = max(0, options.find(current))
	o.item_selected.connect(func(i): _change(func(): on_set.call(options[i])))
	r.add_child(o)
	return r


func _image_field(title: String, current: String, on_set: Callable) -> Control:
	var r := _field(title, current, on_set) as HBoxContainer
	var pick := Button.new()
	pick.text = "Выбрать"
	pick.custom_minimum_size = Vector2(130, 54)
	pick.pressed.connect(func(): _pick_image(on_set))
	r.add_child(pick)
	return r


func _pick_image(on_set: Callable) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(dim)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 100)
	scroll.size = Vector2(680, 1060)
	dim.add_child(scroll)
	var g := GridContainer.new()
	g.columns = 4
	scroll.add_child(g)
	for p in _images:
		var b := Button.new()
		b.custom_minimum_size = Vector2(162, 162)
		b.icon = Content.load_texture(str(p))
		b.expand_icon = true
		b.tooltip_text = str(p)
		b.pressed.connect(func():
			dim.queue_free()
			_change(func(): on_set.call(str(p))))
		g.add_child(b)
	var close := Button.new()
	close.text = "Закрыть"
	close.position = Vector2(20, 1180)
	close.size = Vector2(680, 70)
	close.pressed.connect(func(): dim.queue_free())
	dim.add_child(close)


func _render_props() -> void:
	for c in _props.get_children():
		c.queue_free()
	var els: Array = layout.get("elements", [])
	if selected < 0 or selected >= els.size():
		_props.add_child(Ui.label("Фон экрана", 22, "accent"))
		var bg: Dictionary = layout.get_or_add("background", {})
		_props.add_child(_field("Цвет фона", str(bg.get("color", "background")), func(v): bg["color"] = v))
		_props.add_child(_image_field("Картинка фона", str(bg.get("image", "")), func(v):
			if v == "":
				bg.erase("image")
			else:
				bg["image"] = v))
		_props.add_child(_hint("Выберите элемент на экране или в списке выше, чтобы изменить его."))
		return
	var e: Dictionary = els[selected]
	var t := str(e.get("type"))
	_props.add_child(Ui.label("%s «%s»" % [TYPES.get(t, t), e.get("id", "")], 22, "accent"))
	if e.has("note"):
		_props.add_child(_hint(str(e["note"])))
	_props.add_child(_row([_btn("Выше", func(): _move_layer(1)), _btn("Ниже", func(): _move_layer(-1)),
			_btn("Копия", _duplicate), _btn("Удалить", _delete)]))
	for k in ["x", "y", "w", "h"]:
		var key: String = k
		_props.add_child(_field({"x": "X", "y": "Y", "w": "Ширина", "h": "Высота"}[k], str(int(float(e.get(k, 0)))),
				func(v): e[key] = v, true))
	_props.add_child(_choice("Привязка", ["auto", "top", "center", "bottom", "stretch"],
			["сама (по положению)", "к верху", "по центру", "к низу", "растянуть по высоте"], str(e.get("anchor", "auto")),
			func(v):
				if v == "auto":
					e.erase("anchor")
				else:
					e["anchor"] = v))
	_props.add_child(_hint("Привязка решает, куда сдвигается элемент на вытянутых экранах (20:9 и длиннее)."))
	var vis := CheckBox.new()
	vis.text = "Показывать в игре"
	vis.button_pressed = bool(e.get("visible", true))
	vis.toggled.connect(func(on): _change(func(): e["visible"] = on))
	_props.add_child(vis)
	if t in ["label", "button"]:
		_props.add_child(_field("Текст", str(e.get("text", "")), func(v): e["text"] = v))
		_props.add_child(_field("Размер шрифта", str(int(e.get("size", 26))), func(v): e["size"] = int(v), true))
	if t == "label":
		_props.add_child(_field("Цвет", str(e.get("color", "text")), func(v): e["color"] = v))
		_props.add_child(_choice("Выравнивание", ["left", "center", "right"], ["слева", "по центру", "справа"],
				str(e.get("align", "center")), func(v): e["align"] = v))
		_props.add_child(_field("Обводка", str(int(e.get("outline", 0))), func(v): e["outline"] = int(v), true))
	if t == "image":
		_props.add_child(_image_field("Картинка", str(e.get("image", "")), func(v): e["image"] = v))
		_props.add_child(_choice("Вписать", ["contain", "cover", "stretch"], ["целиком", "заполнить", "растянуть"],
				str(e.get("fit", "contain")), func(v): e["fit"] = v))
	if t == "button":
		_props.add_child(_image_field("Иконка", str(e.get("icon", "")), func(v):
			if v == "":
				e.erase("icon")
			else:
				e["icon"] = v))
		_props.add_child(_choice("Вид", STYLES, STYLES.map(func(s): return STYLE_NAMES[s]), str(e.get("style", "default")),
				func(v): e["style"] = v))
		_props.add_child(_choice("Красная точка", BADGES, ["нет", "можно улучшить героя", "есть свитки", "AFK-награда"],
				str(e.get("badge", "")), func(v):
					if v == "":
						e.erase("badge")
					else:
						e["badge"] = v))
		var a: Dictionary = e.get("action", {})
		var kind := "scene" if a.has("scene") else ("call" if a.has("call") else ("soon" if a.has("soon") else ""))
		_props.add_child(_choice("Действие", ["", "scene", "soon", "call"], ["нет", "открыть экран", "сообщение «скоро»", "действие экрана"],
				kind, func(v):
					if v == "":
						e.erase("action")
					elif v == "scene":
						e["action"] = {"scene": "heroes"}
					elif v == "soon":
						e["action"] = {"soon": "Скоро"}
					else:
						e["action"] = {"call": "back"}))
		if kind == "scene":
			_props.add_child(_choice("Экран", SCENES, ["главный", "кампания", "герои", "призыв", "инвентарь", "тестовый бой", "настройки"],
					str(a["scene"]), func(v): e["action"] = {"scene": v}))
		elif kind == "soon":
			_props.add_child(_field("Текст сообщения", str(a["soon"]), func(v): e["action"] = {"soon": v}))
		elif kind == "call":
			_props.add_child(_field("Имя действия", str(a["call"]), func(v): e["action"] = {"call": v}))
			_props.add_child(_hint("back — назад; другие действия есть только у отдельных экранов."))
	if t == "panel":
		_props.add_child(_field("Цвет", str(e.get("color", "#120C22E0")), func(v): e["color"] = v))
		_props.add_child(_field("Цвет рамки", str(e.get("border", "")), func(v): e["border"] = v))
		_props.add_child(_field("Толщина рамки", str(int(e.get("border_width", 0))), func(v): e["border_width"] = int(v), true))
		_props.add_child(_field("Скругление", str(int(e.get("radius", 0))), func(v): e["radius"] = int(v), true))
	if t == "slot":
		_props.add_child(_hint("Место «%s»: сюда игра кладёт своё содержимое. Можно двигать и менять размер." % e.get("widget", e["id"])))


func save() -> void:
	host._say("Сохранение…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + path.uri_encode(),
			JSON.stringify(layout, "  ").to_utf8_buffer())
	if r.ok:
		host._say("Экран сохранён в черновик. «Открыть в игре» — посмотреть вживую; опубликовать — «Черновик».")
	else:
		host._fail(r)
