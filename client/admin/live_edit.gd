extends CanvasLayer
## Правка экрана прямо в игре (предпросмотр из админки). Долгое нажатие на элемент — меню:
## передвинуть, размер, изменить свойства, слои, копия, удалить, добавить; «Сохранить экран» — в черновик.
## Изменения сразу видны: экран пересобирается из изменённой раскладки (ScreenLayout.overrides).

const HOLD_SEC := 0.6
const TYPES := {"label": "Надпись", "image": "Картинка", "button": "Кнопка", "panel": "Панель", "slot": "Место"}

var ui: Control                 # всё, что рисует режим правки
var _press := {}                # долгое нажатие: {pos, t, consumed}
var _mode := ""                 # "" | "move" | "resize"
var _target := -1               # индекс элемента в раскладке
var _drag := {}
var _menu: Control
var _bar: Control
var _toast: Label
var _undo: Dictionary = {}      # экран -> [JSON]
var _images: Array = []


func _ready() -> void:
	layer = 110
	name = "LiveEdit"
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = Ui.make_theme()
	add_child(ui)
	_toast = Ui.label("Правка: долгое нажатие на элемент", 17)
	_toast.position = Vector2(8, 2)
	_toast.size = Vector2(540, 44)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_toast)
	for p in Content.state.get("files", {}).keys():
		var ps := str(p)
		if (ps.begins_with("ui/") or ps.ends_with("/portrait.png")) and ps.get_extension() in ["png", "webp", "jpg"]:
			_images.append(ps)
	_images.sort()
	if "--live-selftest" in OS.get_cmdline_user_args():
		_selftest()


func _selftest() -> void:
	## Проверка: долгое нажатие на «События» → передвинуть на 40 вниз → экран пересобран → сохранить
	await get_tree().create_timer(5.0).timeout
	var els: Array = _layout()["elements"]
	var idx := -1
	for i in range(els.size()):
		if els[i]["id"] == "events":
			idx = i
	var y0 := float(els[idx]["y"])
	var node := _node(idx)
	var center := node.get_global_rect().get_center()
	_press = {"pos": center, "t": Time.get_ticks_msec() - 1000, "consumed": false}
	await get_tree().process_frame
	await get_tree().process_frame
	var menu_ok := is_instance_valid(_menu) and _target == idx
	if "--live-menu-shot" in OS.get_cmdline_user_args():
		return  # для снимка экрана: меню открыто
	_start("move")
	(_drag["node"] as Control).position += Vector2(0, 40)
	_finish_drag()
	await get_tree().create_timer(3.0).timeout
	var y1 := float(_layout()["elements"][idx]["y"])
	await save()
	var api: Node = get_node("/root/AdminApi")
	var f: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=ui/screens/hub.json", null, true)
	var saved: Variant = JSON.parse_string(f.bytes.get_string_from_utf8())
	var sy := -1.0
	for e in saved["elements"]:
		if e["id"] == "events":
			sy = float(e["y"])
	var ok := menu_ok and absf(y1 - (y0 + 40)) < 1 and absf(sy - y1) < 1
	print("AUTOTEST LIVE: ", JSON.stringify({"ok": ok, "menu": menu_ok, "y0": y0, "y1": y1, "saved": sy}))
	await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {})
	get_tree().quit(0 if ok else 1)


func say(text: String) -> void:
	_toast.text = text


# Совместимость с LayoutEditor (окна подтверждения, сообщения)
func _say(text: String) -> void:
	say(text)


func _confirm(text: String, on_yes: Callable, ok_text := "Да") -> void:
	_dialog(text, [[ok_text, on_yes]])


func add_child_ui(n: Node) -> void:
	ui.add_child(n)


# --- Нажатия ------------------------------------------------------------------------------

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton or ev is InputEventMouseMotion):
		return
	if _mode != "":
		_handle_drag(ev)
		return
	if is_instance_valid(_menu):
		return  # меню открыто — нажатия получает само меню
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press = {"pos": ev.position, "t": Time.get_ticks_msec(), "consumed": false}
		else:
			if _press.get("consumed", false):
				get_viewport().set_input_as_handled()  # долгое нажатие не должно нажать кнопку игры
			_press = {}
	elif ev is InputEventMouseMotion and not _press.is_empty():
		if ev.position.distance_to(_press["pos"]) > 14:
			_press = {}


func _process(_d: float) -> void:
	if _press.is_empty() or _press.get("consumed", false):
		return
	if Time.get_ticks_msec() - int(_press["t"]) >= HOLD_SEC * 1000:
		_press["consumed"] = true
		_open_menu(_press["pos"])


func _canvas_pos(screen_pos: Vector2) -> Vector2:
	## Позиция нажатия в координатах игры (холст 720 × высота экрана)
	return get_viewport().get_canvas_transform().affine_inverse() * screen_pos


func _hit(pos: Vector2) -> int:
	var cur: Dictionary = ScreenLayout.current
	if cur.is_empty():
		return -1
	var els: Array = cur["layout"].get("elements", [])
	for i in range(els.size() - 1, -1, -1):
		var n: Variant = cur["nodes"].get(str(els[i].get("id", "")))
		if n is Control and is_instance_valid(n) and (n as Control).is_visible_in_tree() \
				and (n as Control).get_global_rect().has_point(pos):
			return i
	return -1


# --- Меню ---------------------------------------------------------------------------------

func _button(text: String, cb: Callable) -> Button:
	var b := Ui.button(text, cb)
	b.add_theme_font_size_override("font_size", 20)
	b.custom_minimum_size = Vector2(0, 62)
	return b


func _panel(title: String) -> VBoxContainer:
	_close_menu()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(dim)
	_menu = dim
	var panel := PanelContainer.new()
	var vw := ui.get_viewport_rect().size
	panel.position = Vector2(30, 120)
	panel.custom_minimum_size = Vector2(vw.x - 60, 0)
	dim.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(vw.x - 100, minf(vw.y - 300, 1100))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	box.add_child(Ui.label(title, 24, "accent"))
	return box


func _close_menu() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


func _dialog(text: String, options: Array) -> void:
	var box := _panel(text)
	for o in options:
		box.add_child(_button(str(o[0]), func():
			_close_menu()
			o[1].call()))
	box.add_child(_button("Отмена", _close_menu))


func _open_menu(screen_pos: Vector2) -> void:
	var cur: Dictionary = ScreenLayout.current
	if cur.is_empty():
		say("Этот экран нельзя править (у него нет раскладки)")
		return
	var pos := _canvas_pos(screen_pos)
	_target = _hit(pos)
	var els: Array = cur["layout"]["elements"]
	var title := "Экран «%s»" % cur["screen"]
	if _target >= 0:
		var e: Dictionary = els[_target]
		title = "%s «%s»" % [TYPES.get(e.get("type"), e.get("type")), e.get("id", "")]
	var box := _panel(title)
	if _target >= 0:
		box.add_child(_button("Передвинуть", func(): _start("move")))
		box.add_child(_button("Изменить размер", func(): _start("resize")))
		box.add_child(_button("Изменить…", _edit_props))
		var row := HBoxContainer.new()
		row.add_child(_button("Выше", func(): _layer(1)))
		row.add_child(_button("Ниже", func(): _layer(-1)))
		row.add_child(_button("Копия", _duplicate))
		for c in row.get_children():
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(row)
		box.add_child(_button("Удалить", func(): _confirm("Удалить «%s»?" % els[_target].get("id", ""), _delete, "Удалить")))
	var add := HBoxContainer.new()
	for t in ["label", "button", "image", "panel"]:
		var tt: String = t
		var b := _button("+ " + TYPES[t], func(): _add(tt, pos))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add.add_child(b)
	box.add_child(add)
	box.add_child(_button("Отменить последнее", _undo_last))
	box.add_child(_button("Сохранить экран в черновик", save))
	box.add_child(_button("Закрыть", _close_menu))


# --- Правки -------------------------------------------------------------------------------

func _layout() -> Dictionary:
	return ScreenLayout.current["layout"]


func _remember() -> void:
	var scr := str(ScreenLayout.current["screen"])
	var stack: Array = _undo.get_or_add(scr, [])
	stack.append(JSON.stringify(_layout()))
	if stack.size() > 50:
		stack.pop_front()


func _apply(layout: Dictionary) -> void:
	## Новая раскладка сразу на экране: пересобрать текущую сцену игры
	var scr := str(ScreenLayout.current["screen"])
	ScreenLayout.overrides[scr] = layout
	say("Изменено (не сохранено). Долгое нажатие → «Сохранить экран»")
	get_tree().reload_current_scene()


func _start(mode: String) -> void:
	_close_menu()
	_remember()
	_mode = mode
	var node: Control = _node(_target)
	_drag = {"node": node, "pos0": node.position, "size0": node.size, "from": Vector2.INF}
	_show_bar("Тяните пальцем: " + ("двигать" if mode == "move" else "менять размер") + ". Готово — сохранить в раскладке.")


func _node(i: int) -> Control:
	var e: Dictionary = _layout()["elements"][i]
	return ScreenLayout.current["nodes"].get(str(e.get("id", "")))


func _show_bar(text: String) -> void:
	if is_instance_valid(_bar):
		_bar.queue_free()
	var vw := ui.get_viewport_rect().size
	var p := PanelContainer.new()
	p.position = Vector2(10, vw.y - 170)
	p.custom_minimum_size = Vector2(vw.x - 20, 0)
	ui.add_child(p)
	_bar = p
	var box := VBoxContainer.new()
	p.add_child(box)
	box.add_child(Ui.label(text, 18))
	var row := HBoxContainer.new()
	var done := _button("Готово", _finish_drag)
	done.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(done)
	var cancel := _button("Отмена", func():
		var n: Control = _drag.get("node")
		if is_instance_valid(n):
			n.position = _drag["pos0"]
			n.size = _drag["size0"]
		_mode = ""
		_bar.queue_free())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	box.add_child(row)


func _handle_drag(ev: InputEvent) -> void:
	if is_instance_valid(_bar) and _bar.get_global_rect().has_point(ev.position):
		return  # нажатия по кнопкам «Готово/Отмена»
	var node: Control = _drag.get("node")
	if not is_instance_valid(node):
		return
	var pos := _canvas_pos(ev.position)
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag["from"] = pos if ev.pressed else Vector2.INF
		if ev.pressed:
			_drag["start_pos"] = node.position
			_drag["start_size"] = node.size
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion and _drag["from"] != Vector2.INF:
		var d: Vector2 = pos - _drag["from"]
		if _mode == "move":
			node.position = (_drag["start_pos"] + d).snapped(Vector2(4, 4))
		else:
			node.size = (_drag["start_size"] + d).snapped(Vector2(4, 4)).max(Vector2(8, 8))
		get_viewport().set_input_as_handled()


func _finish_drag() -> void:
	var node: Control = _drag.get("node")
	var e: Dictionary = _layout()["elements"][_target]
	var cur: Dictionary = ScreenLayout.current
	# Обратный пересчёт: позиция на экране -> координаты холста с учётом привязки
	var placed := ScreenLayout.place(e, cur["view"], cur["insets"])
	var shift := placed.position - Vector2(float(e["x"]), float(e["y"]))
	var grow := placed.size - Vector2(float(e["w"]), float(e["h"]))
	e["x"] = round(node.position.x - shift.x)
	e["y"] = round(node.position.y - shift.y)
	e["w"] = round(node.size.x - grow.x)
	e["h"] = round(node.size.y - grow.y)
	_mode = ""
	if is_instance_valid(_bar):
		_bar.queue_free()
	_apply(_layout())


func _edit_props() -> void:
	var box := _panel("Изменить «%s»" % _layout()["elements"][_target].get("id", ""))
	var copy: Dictionary = _layout().duplicate(true)
	var ed := LayoutEditor.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(ed)
	ed.setup_props(self, copy, _images, _target)
	ed.changed.connect(func(_l): pass)
	var row := HBoxContainer.new()
	var ok := _button("Применить", func():
		_close_menu()
		_remember()
		_apply(copy))
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ok)
	var cancel := _button("Отмена", _close_menu)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cancel)
	box.add_child(row)


func _layer(d: int) -> void:
	var els: Array = _layout()["elements"]
	var j := _target + d
	_close_menu()
	if j < 0 or j >= els.size():
		return
	_remember()
	var tmp: Variant = els[_target]
	els[_target] = els[j]
	els[j] = tmp
	_apply(_layout())


func _new_id(base: String) -> String:
	var ids := {}
	for e in _layout()["elements"]:
		ids[str(e.get("id", ""))] = true
	var n := 1
	while ids.has("%s_%d" % [base, n]):
		n += 1
	return "%s_%d" % [base, n]


func _duplicate() -> void:
	_close_menu()
	_remember()
	var els: Array = _layout()["elements"]
	var e: Dictionary = (els[_target] as Dictionary).duplicate(true)
	e["id"] = _new_id(str(e["id"]).get_slice("_", 0))
	e["x"] = float(e["x"]) + 24
	e["y"] = float(e["y"]) + 24
	els.insert(_target + 1, e)
	_apply(_layout())


func _delete() -> void:
	_remember()
	_layout()["elements"].remove_at(_target)
	_apply(_layout())


func _add(type: String, at: Vector2) -> void:
	_close_menu()
	_remember()
	var cur: Dictionary = ScreenLayout.current
	var e := {"id": _new_id(type), "type": type, "w": 300, "h": 80}
	var placed := ScreenLayout.place({"x": at.x, "y": at.y, "w": 300, "h": 80}, cur["view"], cur["insets"])
	e["x"] = round(at.x - (placed.position.x - at.x) - 150)
	e["y"] = round(at.y - (placed.position.y - at.y) - 40)
	match type:
		"label":
			e.merge({"text": "Новая надпись", "size": 28})
		"image":
			e.merge({"image": "ui/logo.png", "w": 200, "h": 200})
		"button":
			e.merge({"text": "Кнопка", "action": {"soon": "Скоро"}})
		"panel":
			e.merge({"color": "#120C22E0", "border": "accent", "border_width": 2, "radius": 16})
	_layout()["elements"].append(e)
	_apply(_layout())


func _undo_last() -> void:
	_close_menu()
	var scr := str(ScreenLayout.current.get("screen", ""))
	var stack: Array = _undo.get(scr, [])
	if stack.is_empty():
		say("Нечего отменять")
		return
	_apply(JSON.parse_string(stack.pop_back()))


func save() -> void:
	_close_menu()
	var cur: Dictionary = ScreenLayout.current
	var api: Node = get_node_or_null("/root/AdminApi")
	if cur.is_empty() or api == null:
		return
	var path := "ui/screens/%s.json" % cur["screen"]
	say("Сохранение…")
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + path.uri_encode(),
			JSON.stringify(cur["layout"], "  ").to_utf8_buffer())
	if r.ok:
		say("Экран «%s» сохранён в черновик" % cur["screen"])
	else:
		say("Ошибка: %s %s" % [r.error, str(r.get("errors", []))])
