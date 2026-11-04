class_name HeroCutter
extends VBoxContainer
## Нарезчик героя (этап 6в-3): рисунок → части тела → суставы скелета → герой или скин в черновике.
## Тяжёлая работа на сервере (/api/v1/admin/cutter/...): удаление фона, автонарезка, ИИ Gemini, сборка.
## Здесь — показ и правка: многоугольник, кисть «добавить/стереть», суставы пальцем, точные цифры.

const Previews := preload("res://admin/previews.gd")
const COLORS := [Color("#FF6B6B"), Color("#4ECDC4"), Color("#FFD93D"), Color("#6BCB77"), Color("#4D96FF"),
		Color("#C77DFF"), Color("#FF9F1C"), Color("#F15BB5"), Color("#00F5D4")]

var host: Node               # экран админки: api, _say, _fail, _open
var hero_id := ""
var target := "default"      # обычный вид или id скина
var templates: Array = []
var ai_ready := false
var tpl: Dictionary = {}
var sid := ""
var meta: Dictionary = {}
var parts: Array = []        # [{name, layer, polygons, strokes}]
var joints: Dictionary = {}  # кость -> [x, y] в пикселях рисунка
var part := ""               # выбранная часть
var tool := "pan"            # pan | poly | add | erase | joint | rect
var brush := 14.0
var history: Array = []

var _canvas: Control
var _src_tex: Texture2D
var _part_tex: Dictionary = {}   # часть -> {tex, x, y}
var _zoom := 1.0
var _offset := Vector2.ZERO
var _poly: Array = []            # точки текущего многоугольника
var _stroke: Dictionary = {}
var _drag := {}
var _rect := Rect2()
var _status: Label
var _parts_row: HFlowContainer
var _tools_row: HFlowContainer
var _layer_pick: OptionButton
var _tpl_pick: OptionButton
var _joint_x: SpinBox
var _joint_y: SpinBox
var _joint_name := ""
var _art: CheckBox
var _ai_btn: Button


func setup(p_host: Node, p_hero_id: String, p_target := "default") -> void:
	host = p_host
	hero_id = p_hero_id
	target = p_target
	add_theme_constant_override("separation", 8)
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/cutter/templates")
	if not r.ok:
		host._fail(r)
		return
	templates = r.data["templates"]
	ai_ready = bool(r.data.get("ai", false))
	tpl = templates[0]
	_build()


# --- Интерфейс ------------------------------------------------------------------------------

func _label(text: String, size := 17) -> Label:
	var l := Ui.label(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, cb: Callable, size := 17) -> Button:
	var b := Ui.button(text, cb)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 58)
	return b


func _flow() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 6)
	return f


func _build() -> void:
	add_child(_label("Куда: %s" % ("обычный вид героя (новый скелет по шаблону)" if target == "default"
			else "скин «%s» (скелет и анимации героя прежние, у частей — свои картинки)" % target), 18))
	var r1 := HBoxContainer.new()
	var tl := Ui.label("Шаблон скелета:", 18)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	r1.add_child(tl)
	_tpl_pick = OptionButton.new()
	_tpl_pick.add_theme_font_size_override("font_size", 18)
	_tpl_pick.custom_minimum_size = Vector2(240, 58)
	for t in templates:
		_tpl_pick.add_item(str(t["name"]))
	_tpl_pick.item_selected.connect(func(i):
		tpl = templates[i]
		if sid != "":
			_say("Шаблон «%s»: нажмите «Авто» или «ИИ», чтобы нарезать заново" % tpl["name"]))
	r1.add_child(_tpl_pick)
	add_child(r1)
	var r2 := _flow()
	r2.add_child(_button("1. Рисунок / лист персонажа", func(): _pick(false)))
	r2.add_child(_button("Слои (ZIP)", func(): _pick(true)))
	add_child(r2)
	add_child(_label("Рисунок — PNG/JPG, лучше на сплошном фоне (белый или пурпурный #FF00FF), герой смотрит вправо. "
			+ "Лист персонажа — после загрузки выделите одну позу рамкой. Слои — ZIP с PNG на общем холсте "
			+ "(имена как у частей: head, torso, arm_front…).", 15))

	add_child(Ui.label("2. Нарезка", 22, "accent"))
	var r3 := _flow()
	r3.add_child(_button("Авто (без ИИ)", _auto))
	_ai_btn = _button("ИИ (Gemini): части + дорисовка", _ai)
	_ai_btn.disabled = not ai_ready
	r3.add_child(_ai_btn)
	r3.add_child(_button("Лист: выбрать позу рамкой", func(): _set_tool("rect")))
	r3.add_child(_button("Обрезать по рамке", _crop))
	add_child(r3)
	if not ai_ready:
		add_child(_label("ИИ выключен: на сервере нет ключа Gemini (GEMINI_API_KEY в .env).", 15))

	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(680, 640)
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_canvas)
	_canvas.gui_input.connect(_on_input)
	add_child(_canvas)
	_status = _label("Загрузите рисунок героя", 17)
	add_child(_status)

	var zoom := _flow()
	zoom.add_child(_button("+", func(): _zoom_at(1.25, _canvas.size / 2)))
	zoom.add_child(_button("−", func(): _zoom_at(0.8, _canvas.size / 2)))
	zoom.add_child(_button("Вписать", _fit))
	zoom.add_child(_button("Отменить", _undo))
	add_child(zoom)

	add_child(Ui.label("3. Части: нажмите часть, потом инструмент", 20, "accent"))
	_parts_row = _flow()
	add_child(_parts_row)
	_tools_row = _flow()
	for t in [["pan", "Двигать"], ["poly", "Многоугольник"], ["add", "Кисть +"], ["erase", "Кисть −"]]:
		_tools_row.add_child(_button(t[1], _set_tool.bind(t[0])))
	_tools_row.add_child(_button("Замкнуть", _close_poly))
	_tools_row.add_child(_button("Очистить часть", _clear_part))
	add_child(_tools_row)
	var br := HBoxContainer.new()
	var bl := Ui.label("Кисть", 17)
	bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	br.add_child(bl)
	var s := HSlider.new()
	s.min_value = 2
	s.max_value = 80
	s.value = brush
	s.custom_minimum_size = Vector2(0, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v): brush = v)
	br.add_child(s)
	var ll := Ui.label("Слой:", 17)
	ll.autowrap_mode = TextServer.AUTOWRAP_OFF
	br.add_child(ll)
	_layer_pick = OptionButton.new()
	_layer_pick.add_theme_font_size_override("font_size", 16)
	_layer_pick.custom_minimum_size = Vector2(200, 54)
	_layer_pick.item_selected.connect(_on_layer_pick)
	br.add_child(_layer_pick)
	add_child(br)
	add_child(_label("Многоугольник — точки по контуру части, потом «Замкнуть». Кисть + / − добавляет и стирает. "
			+ "На ПК колесо мыши — масштаб.", 15))

	add_child(Ui.label("4. Скелет", 22, "accent"))
	var jr := _flow()
	jr.add_child(_button("Двигать суставы", func(): _set_tool("joint")))
	_joint_x = _spin("x")
	_joint_y = _spin("y")
	jr.add_child(_joint_x)
	jr.add_child(_joint_y)
	add_child(jr)
	add_child(_label("Сустав — место, вокруг которого крутится часть: плечо, бедро, шея, рукоять оружия. "
			+ "Перетащите кружки на рисунке или введите точные цифры.", 15))

	add_child(Ui.label("5. Сохранить", 22, "accent"))
	_art = CheckBox.new()
	_art.text = "Обновить портрет и полный арт из рисунка"
	_art.add_theme_font_size_override("font_size", 17)
	add_child(_art)
	add_child(_button("Сохранить в героя (черновик)", _build_hero, 20))
	_refresh_parts()


func _spin(axis: String) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = -10000
	sp.max_value = 10000
	sp.step = 0.5
	sp.prefix = axis
	sp.custom_minimum_size = Vector2(170, 54)
	sp.value_changed.connect(func(v):
		if _joint_name != "" and joints.has(_joint_name):
			var j: Array = joints[_joint_name]
			j[0 if axis == "x" else 1] = v
			_canvas.queue_redraw())
	return sp


func _say(t: String) -> void:
	_status.text = t
	host._say(t)


func _set_tool(t: String) -> void:
	tool = t
	_poly.clear()
	var names := {"pan": "двигать рисунок", "poly": "многоугольник", "add": "кисть +", "erase": "кисть −",
			"joint": "суставы", "rect": "рамка позы"}
	_status.text = "Инструмент: %s%s" % [names.get(t, t), ("; часть: " + _part_title(part)) if part != "" and t in ["poly", "add", "erase"] else ""]
	_canvas.queue_redraw()


func _part_title(n: String) -> String:
	for p in tpl.get("parts", []):
		if p["name"] == n:
			return str(p["title"])
	return n


func _refresh_parts() -> void:
	for c in _parts_row.get_children():
		c.queue_free()
	var i := 0
	for p in tpl.get("parts", []):
		var n := str(p["name"])
		var btn := _button(("● " if n == part else "") + str(p["title"]), _select_part.bind(n), 16)
		btn.add_theme_color_override("font_color", COLORS[i % COLORS.size()])
		_parts_row.add_child(btn)
		i += 1
	_layer_pick.clear()
	_layer_pick.add_item("Рисунок")
	for l in meta.get("layers", []):
		_layer_pick.add_item(str(l))
	var cur := _part_data(part)
	if not cur.is_empty():
		var lname := str(cur.get("layer", "source"))
		var idx: int = 0 if lname == "source" else meta.get("layers", []).find(lname) + 1
		_layer_pick.select(maxi(idx, 0))


func _part_data(n: String) -> Dictionary:
	for p in parts:
		if p["name"] == n:
			return p
	return {}


func _select_part(n: String) -> void:
	part = n
	_refresh_parts()
	if tool in ["pan", "joint", "rect"]:
		tool = "poly"
	_set_tool(tool)
	await _load_preview(n)


func _on_layer_pick(i: int) -> void:
	var p := _part_data(part)
	if p.is_empty():
		return
	_push()
	p["layer"] = "source" if i == 0 else str(meta["layers"][i - 1])
	await _load_preview(part)


func _push() -> void:
	history.append({"parts": parts.duplicate(true), "joints": joints.duplicate(true)})
	if history.size() > 40:
		history.pop_front()


func _undo() -> void:
	if _poly.size() > 0:
		_poly.pop_back()
		_canvas.queue_redraw()
		return
	if history.is_empty():
		return
	var h: Dictionary = history.pop_back()
	parts = h["parts"]
	joints = h["joints"]
	await _load_all_previews()


# --- Сервер ---------------------------------------------------------------------------------

func _pick(zip: bool) -> void:
	Previews.pick_file(host, ["*.zip"] if zip else ["*.png", "*.jpg", "*.jpeg", "*.webp"], func(bytes: PackedByteArray, name: String):
		upload(bytes, name))


func upload(bytes: PackedByteArray, name: String) -> bool:
	_say("Загрузка рисунка и удаление фона…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter?name=" + name.uri_encode(), bytes)
	if not r.ok:
		host._fail(r)
		return false
	meta = r.data
	sid = str(meta["id"])
	parts.clear()
	joints.clear()
	history.clear()
	_part_tex.clear()
	await _load_source()
	_say("Рисунок %d×%d загружен. %s" % [int(meta["w"]), int(meta["h"]),
			"Слои: %d. Нажмите «Авто» — части разложатся по слоям." % meta["layers"].size() if meta["mode"] == "layers"
			else "Лист персонажа — выделите позу рамкой и «Обрезать». Цельный рисунок — сразу «Авто» или «ИИ»."])
	return true


func _load_source() -> void:
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/cutter/%s/image?which=source" % sid, null, true)
	if r.ok:
		_src_tex = Previews.texture_from_bytes(r.bytes, "x.png")
	_fit()


func _crop() -> void:
	if sid == "" or _rect.size.x < 8:
		_say("Сначала выберите «Лист: выбрать позу рамкой» и обведите одну позу")
		return
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter/%s/crop" % sid,
			{"x": int(_rect.position.x), "y": int(_rect.position.y), "w": int(_rect.size.x), "h": int(_rect.size.y)})
	if not r.ok:
		host._fail(r)
		return
	meta = r.data
	_rect = Rect2()
	parts.clear()
	_part_tex.clear()
	await _load_source()
	_set_tool("pan")
	_say("Поза выбрана (%d×%d). Теперь «Авто» или «ИИ»." % [int(meta["w"]), int(meta["h"])])


func _apply_cut(res: Dictionary) -> void:
	_push()
	parts = res["parts"]
	joints = res["joints"]
	part = str(parts[0]["name"]) if not parts.is_empty() else ""
	_refresh_parts()
	await _load_all_previews()


func _auto() -> bool:
	if sid == "":
		_say("Сначала загрузите рисунок")
		return false
	_say("Автонарезка…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter/%s/auto" % sid, {"template": tpl["id"]})
	if not r.ok:
		host._fail(r)
		return false
	await _apply_cut(r.data)
	_say("Готово: части разложены грубо по шаблону «%s». Поправьте кистью и многоугольником, проверьте суставы." % tpl["name"])
	return true


func _ai() -> void:
	if sid == "":
		_say("Сначала загрузите рисунок")
		return
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter/%s/ai" % sid, {"template": tpl["id"]})
	if not r.ok:
		host._fail(r)
		return
	_ai_btn.disabled = true
	var started := Time.get_ticks_msec()
	while true:
		_say("ИИ рисует части героя… %d с (обычно до 1–2 минут)" % ((Time.get_ticks_msec() - started) / 1000))
		await get_tree().create_timer(3.0).timeout
		if not is_inside_tree():
			return
		var st: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/cutter/%s/ai" % sid)
		if not st.ok:
			host._fail(st)
			break
		var status := str(st.data.get("status", ""))
		if status == "done":
			var res: Dictionary = st.data["result"]
			var m: Dictionary = res.get("ai", {})
			var layers: Array = meta.get("layers", []).filter(func(l): return not str(l).begins_with("ai_"))
			for n in m.get("parts", []):
				layers.append("ai_" + str(n))
			meta["layers"] = layers
			await _apply_cut(res)
			_say("ИИ: частей на листе %d, совмещено %d, не нашли место %d. Части без ИИ — из рисунка, поправьте их."
					% [int(m.get("pieces", 0)), int(m.get("placed", 0)), int(m.get("unplaced", 0))])
			break
		if status != "running":
			_say("ИИ: " + str(st.data.get("error", "ошибка")))
			break
	_ai_btn.disabled = not ai_ready


func _load_preview(n: String) -> void:
	var p := _part_data(n)
	if p.is_empty() or sid == "":
		return
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter/%s/preview" % sid, {"part": p})
	if not r.ok:
		host._fail(r)
		return
	if bool(r.data.get("empty", true)):
		_part_tex.erase(n)
	else:
		var tex := Previews.texture_from_bytes(Marshalls.base64_to_raw(str(r.data["png"])), "p.png")
		_part_tex[n] = {"tex": tex, "x": float(r.data["x"]), "y": float(r.data["y"])}
	_canvas.queue_redraw()


func _load_all_previews() -> void:
	_part_tex.clear()
	for p in parts:
		await _load_preview(str(p["name"]))


func build_hero() -> Dictionary:
	if sid == "" or parts.is_empty():
		_say("Сначала нарежьте героя («Авто» или «ИИ»)")
		return {"ok": false}
	_say("Сборка героя…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, "/cutter/%s/build" % sid, {"hero": hero_id,
			"skin": target, "template": tpl["id"], "parts": parts, "joints": joints, "art": _art.button_pressed})
	if not r.ok:
		host._fail(r)
		return r
	var rep: Dictionary = r.data["report"]
	_say("Сохранено в черновик: частей %d%s, анимации: %s. Откройте «Предпросмотр героя» и проверьте." % [
			rep["parts"].size(), (", пустые: " + ", ".join(rep["empty"])) if not rep["empty"].is_empty() else "",
			str(rep.get("animations", "прежние"))])
	return r


func _build_hero() -> void:
	var r := await build_hero()
	if r.ok:
		await host._with_draft(func(): pass)


# --- Холст ----------------------------------------------------------------------------------

func _fit() -> void:
	if _src_tex == null:
		return
	var sz := _src_tex.get_size()
	_zoom = minf(_canvas.size.x / sz.x, _canvas.size.y / sz.y) * 0.95 if _canvas.size.x > 0 else 0.4
	if _zoom <= 0:
		_zoom = minf(680 / sz.x, 640 / sz.y) * 0.95
	var view := _canvas.size if _canvas.size.x > 0 else Vector2(680, 640)
	_offset = (view - sz * _zoom) / 2
	_canvas.queue_redraw()


func _zoom_at(k: float, at: Vector2) -> void:
	var before := (at - _offset) / _zoom
	_zoom = clampf(_zoom * k, 0.05, 20.0)
	_offset = at - before * _zoom
	_canvas.queue_redraw()


func _to_img(p: Vector2) -> Vector2:
	return (p - _offset) / _zoom


func _to_screen(p: Vector2) -> Vector2:
	return _offset + p * _zoom


func _part_color(n: String) -> Color:
	var i := 0
	for p in tpl.get("parts", []):
		if p["name"] == n:
			return COLORS[i % COLORS.size()]
		i += 1
	return Color.WHITE


func _draw_canvas() -> void:
	var c := _canvas
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color(0.06, 0.05, 0.1))
	if _src_tex == null:
		return
	var sz := _src_tex.get_size()
	var dim := part != "" and tool in ["poly", "add", "erase"]
	c.draw_texture_rect(_src_tex, Rect2(_offset, sz * _zoom), false, Color(1, 1, 1, 0.3 if dim else 1.0))
	if dim and _part_tex.has(part):
		var pt: Dictionary = _part_tex[part]
		var t: Texture2D = pt["tex"]
		c.draw_texture_rect(t, Rect2(_to_screen(Vector2(pt["x"], pt["y"])), t.get_size() * _zoom), false)
	for p in parts:
		var n := str(p["name"])
		var col := _part_color(n)
		col.a = 1.0 if n == part else 0.35
		for poly in p.get("polygons", []):
			var pts := PackedVector2Array()
			for q in poly:
				pts.append(_to_screen(Vector2(float(q[0]), float(q[1]))))
			if pts.size() >= 2:
				pts.append(pts[0])
				c.draw_polyline(pts, col, 2.0 if n == part else 1.0)
		if n == part:
			for st in p.get("strokes", []):
				var sc := Color(0.3, 1, 0.4, 0.25) if st.get("mode", "add") == "add" else Color(1, 0.3, 0.3, 0.25)
				for q in st.get("pts", []):
					c.draw_circle(_to_screen(Vector2(float(q[0]), float(q[1]))), float(st.get("r", 10)) * _zoom, sc)
	if not _stroke.is_empty():
		var sc2 := Color(0.3, 1, 0.4, 0.4) if _stroke["mode"] == "add" else Color(1, 0.3, 0.3, 0.4)
		for q in _stroke["pts"]:
			c.draw_circle(_to_screen(Vector2(q[0], q[1])), float(_stroke["r"]) * _zoom, sc2)
	if _poly.size() > 0:
		var pts2 := PackedVector2Array()
		for q in _poly:
			pts2.append(_to_screen(q))
		if pts2.size() >= 2:
			c.draw_polyline(pts2, Color.WHITE, 2.0)
		for q in pts2:
			c.draw_circle(q, 5, Color.WHITE)
	if _rect.size.x > 0:
		c.draw_rect(Rect2(_to_screen(_rect.position), _rect.size * _zoom), Color("#FFD24A"), false, 3.0)
	# Скелет: линии к родителю и суставы
	var bones: Array = tpl.get("bones", [])
	var show_j := tool == "joint" or not dim
	if show_j:
		for b in bones:
			var bn := str(b["name"])
			var par := str(b["parent"])
			if joints.has(bn) and joints.has(par):
				c.draw_line(_to_screen(_jv(par)), _to_screen(_jv(bn)), Color(1, 0.85, 0.3, 0.8), 2.0)
		for bn in joints.keys():
			var on := str(bn) == _joint_name
			var p2 := _to_screen(_jv(str(bn)))
			c.draw_circle(p2, 9 if tool == "joint" else 5, Color("#FFD24A") if on else Color(1, 1, 1, 0.9))
			c.draw_circle(p2, 4 if tool == "joint" else 2, Color(0.1, 0.1, 0.1))
			if tool == "joint":
				c.draw_string(ThemeDB.fallback_font, p2 + Vector2(10, -8), str(bn), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _jv(n: String) -> Vector2:
	var j: Array = joints[n]
	return Vector2(float(j[0]), float(j[1]))


func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.1, mb.position)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(0.9, mb.position)
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(mb.position)
		else:
			_release(mb.position)
		_canvas.accept_event()
	elif ev is InputEventMouseMotion and not _drag.is_empty():
		_motion((ev as InputEventMouseMotion).position, (ev as InputEventMouseMotion).relative)
		_canvas.accept_event()
	elif ev is InputEventMagnifyGesture:
		_zoom_at((ev as InputEventMagnifyGesture).factor, (ev as InputEventMagnifyGesture).position)
	elif ev is InputEventPanGesture:
		_offset -= (ev as InputEventPanGesture).delta * 8
		_canvas.queue_redraw()


func _press(pos: Vector2) -> void:
	var ip := _to_img(pos)
	match tool:
		"pan":
			_drag = {"kind": "pan"}
		"poly":
			if part == "":
				_say("Сначала выберите часть")
				return
			_poly.append(ip)
			_drag = {"kind": "none"}
		"add", "erase":
			if part == "":
				_say("Сначала выберите часть")
				return
			_stroke = {"mode": tool, "r": brush / _zoom, "pts": [[ip.x, ip.y]]}
			_drag = {"kind": "stroke"}
		"joint":
			var best := ""
			var bd := 40.0
			for bn in joints.keys():
				var d := _to_screen(_jv(str(bn))).distance_to(pos)
				if d < bd:
					bd = d
					best = str(bn)
			if best != "":
				_push()
				_joint_name = best
				_sync_joint_fields()
				_drag = {"kind": "joint"}
			else:
				_drag = {"kind": "pan"}
		"rect":
			_rect = Rect2(ip, Vector2.ZERO)
			_drag = {"kind": "rect", "from": ip}
	_canvas.queue_redraw()


func _motion(pos: Vector2, rel: Vector2) -> void:
	match str(_drag.get("kind", "")):
		"pan":
			_offset += rel
		"stroke":
			var ip := _to_img(pos)
			var pts: Array = _stroke["pts"]
			var last: Array = pts[pts.size() - 1]
			if Vector2(last[0], last[1]).distance_to(ip) >= maxf(1.0, float(_stroke["r"]) * 0.4):
				pts.append([ip.x, ip.y])
		"joint":
			var ip2 := _to_img(pos)
			joints[_joint_name] = [snappedf(ip2.x, 0.5), snappedf(ip2.y, 0.5)]
			_same_as()
			_sync_joint_fields()
		"rect":
			var a: Vector2 = _drag["from"]
			var b := _to_img(pos)
			_rect = Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	_canvas.queue_redraw()


func _release(_pos: Vector2) -> void:
	var kind := str(_drag.get("kind", ""))
	_drag = {}
	if kind == "stroke" and not _stroke.is_empty():
		_push()
		var p := _part_data(part)
		var st: Array = p.get("strokes", [])
		var done := _stroke.duplicate(true)
		done["r"] = snappedf(float(done["r"]), 0.5)
		st.append(done)
		p["strokes"] = st
		_stroke = {}
		await _load_preview(part)
	_canvas.queue_redraw()


func _same_as() -> void:
	var same: Dictionary = tpl.get("same_as", {})
	for a in same.keys():
		if joints.has(str(same[a])):
			joints[a] = (joints[str(same[a])] as Array).duplicate()


func _sync_joint_fields() -> void:
	if _joint_name == "" or not joints.has(_joint_name):
		return
	var j: Array = joints[_joint_name]
	_joint_x.set_value_no_signal(float(j[0]))
	_joint_y.set_value_no_signal(float(j[1]))
	_status.text = "Сустав «%s»: x %.1f, y %.1f" % [_joint_name, float(j[0]), float(j[1])]


func _close_poly() -> void:
	if _poly.size() < 3:
		_say("Нужно минимум 3 точки")
		return
	_push()
	var p := _part_data(part)
	var arr: Array = []
	for q in _poly:
		arr.append([snappedf(q.x, 0.5), snappedf(q.y, 0.5)])
	var polys: Array = p.get("polygons", [])
	polys.append(arr)
	p["polygons"] = polys
	_poly.clear()
	await _load_preview(part)


func _clear_part() -> void:
	var p := _part_data(part)
	if p.is_empty():
		return
	_push()
	p["polygons"] = []
	p["strokes"] = []
	await _load_preview(part)


## Автопроверка: мазок кистью по части (как пальцем)
func test_stroke(n: String, mode: String, at: Vector2, r: float) -> void:
	part = n
	var p := _part_data(n)
	var st: Array = p.get("strokes", [])
	st.append({"mode": mode, "r": r, "pts": [[at.x, at.y]]})
	p["strokes"] = st
	await _load_preview(n)
