extends Control
## Админка (отдельный APK lunex.ufa.admin, тот же проект, что игра; главная сцена — эта).
## Экраны: вход → разделы → объекты (формы по схеме / JSON) → черновик → тест → публикация → откат,
## версии, журнал, ZIP-патчи, выгрузка, промпт для ИИ, предпросмотр на данных черновика.

const Previews := preload("res://admin/previews.gd")

var api: Node
var _history: Array = []        # стек экранов для «Назад»: Callable
var _current: Callable
var _body: VBoxContainer
var _status: Label
var _draft_count := 0


func _ready() -> void:
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	theme = Ui.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	api = get_node_or_null("/root/AdminApi")
	if api == null:
		api = preload("res://admin/admin_api.gd").new()
		api.name = "AdminApi"
		get_tree().root.add_child.call_deferred(api)
		await get_tree().process_frame
	api.logged_out.connect(func(): _open(_show_login, false))
	for extra in ["/root/AdminBack", "/root/LiveEdit"]:
		var remove := get_node_or_null(extra)
		if remove:
			remove.queue_free()
	if api.token == "":
		_open(_show_login, false)
	else:
		_open(_show_home, false)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--admin-autotest="):
			_autotest(arg.get_slice("=", 1))


# --- Каркас экрана -------------------------------------------------------------------

func _open(builder: Callable, remember := true) -> void:
	if remember and _current.is_valid():
		_history.append(_current)
	_current = builder
	builder.call()


func _back() -> void:
	if _history.is_empty():
		_open(_show_home, false)
		return
	_current = _history.pop_back()
	_current.call()


func _frame(title: String, with_back := true) -> VBoxContainer:
	for c in get_children():
		c.queue_free()
	var col := Ui.screen(self)
	var margin: MarginContainer = col.get_parent()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 20)
	col.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	if with_back:
		var b := Ui.button("<", _back)
		b.custom_minimum_size = Vector2(80, 72)
		head.add_child(b)
	var t := Ui.label(title, 30, "accent")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(t)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	_status = Ui.label("", 19)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	col.add_child(_status)
	return _body


func _btn(text: String, cb: Callable, size := 24) -> Button:
	var b := Ui.button(text, cb)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 76)
	b.clip_text = true
	return b


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for b in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	return row


func _text(t: String, size := 20) -> Label:
	var l := Ui.label(t, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


static func _num(v: Variant) -> String:
	return "—" if v == null else str(int(v))


func _say(t: String, errors: Array = []) -> void:
	if not is_instance_valid(_status):
		return
	var lines := [t]
	for e in errors.slice(0, 12):
		lines.append("• " + str(e))
	if errors.size() > 12:
		lines.append("… и ещё %d" % (errors.size() - 12))
	_status.text = "\n".join(lines)
	_status.add_theme_color_override("font_color", Color("#FF8A7A") if not errors.is_empty() or t.begins_with("Ошибка") else Ui.colors["text"])


func _fail(res: Dictionary) -> void:
	_say("Ошибка: " + str(res.error), res.get("errors", []))


func _confirm(text: String, on_yes: Callable, ok_text := "Да") -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 400)
	panel.custom_minimum_size = Vector2(640, 0)
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(Ui.label(text, 26))
	box.add_child(_row([_btn(ok_text, func():
		dim.queue_free()
		on_yes.call()), _btn("Отмена", func(): dim.queue_free())]))


func _ask(text: String, placeholder: String, on_ok: Callable) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 360)
	panel.custom_minimum_size = Vector2(640, 0)
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(Ui.label(text, 26))
	var e := Ui.line_edit(placeholder)
	box.add_child(e)
	box.add_child(_row([_btn("Готово", func():
		dim.queue_free()
		on_ok.call(e.text.strip_edges())), _btn("Отмена", func(): dim.queue_free())]))


# --- Вход -----------------------------------------------------------------------

func _show_login() -> void:
	_history.clear()
	var b := _frame("Админка · вход", false)
	b.add_child(_text("Сервер: " + Config.server_url, 18))
	var user := Ui.line_edit("Логин")
	var pw := Ui.line_edit("Пароль", true)
	var code := Ui.line_edit("Код 2FA (если включена)")
	code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code.visible = false
	b.add_child(user)
	b.add_child(pw)
	b.add_child(code)
	var go := func():
		_say("Вход…")
		var res: Dictionary = await api.do_login(user.text.strip_edges(), pw.text, code.text.strip_edges())
		if res.ok:
			_say("")
			_open(_show_home, false)
		elif res.get("totp_required", false):
			code.visible = true
			_say(res.error)
		else:
			_fail(res)
	b.add_child(_btn("Войти", go))
	b.add_child(_text("Админ создаётся командой на сервере (см. docs/admin.md). После 5 неудачных попыток вход блокируется на 15 минут.", 17))


# --- Главная --------------------------------------------------------------------

func _show_home() -> void:
	var b := _frame("Админка", false)
	_say("Загрузка…")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections")
	if not res.ok:
		_fail(res)
		b.add_child(_btn("Повторить", func(): _open(_show_home, false)))
		b.add_child(_btn("Выйти", func(): api.do_logout()))
		return
	_say("")
	var d: Dictionary = res.data["draft"]
	_draft_count = int(d["count"])
	b.add_child(_text("Вы вошли как %s · версия игры №%s%s" % [api.login, _num(d.get("live_release")),
			"  · черновик начат от старой версии!" if bool(d.get("outdated", false)) else ""], 18))
	b.add_child(_row([_btn("Черновик (%d)" % _draft_count, func(): _open(_show_draft)),
			_btn("Версии", func(): _open(_show_releases)), _btn("Журнал", func(): _open(_show_audit.bind(0)))]))
	b.add_child(_row([_btn("ZIP-патч", func(): _open(_show_patch)), _btn("Предпросмотр", func(): _open(_show_previews))]))
	b.add_child(_row([_btn("Конструктор экранов", func(): _with_draft(func(): _open(_show_screens)), 22),
			_btn("Картинки игры", func(): _open(_show_assets), 22)]))
	b.add_child(_row([_btn("Игроки", func(): _open(_show_players.bind(""))), _btn("Бэкапы", func(): _open(_show_backups)),
			_btn("Версии APK", func(): _open(_show_apk))]))
	b.add_child(Ui.label("Разделы", 26, "accent"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	b.add_child(grid)
	for s in res.data["sections"]:
		var mark := "  (правок: %d)" % int(s["draft_changes"]) if int(s["draft_changes"]) > 0 else ""
		var btn := _btn("%s%s\n%d объект., %d файл." % [s["title"], mark, int(s["objects"]), int(s["assets"])],
				func(): _open(_show_section.bind(str(s["id"]))), 20)
		btn.custom_minimum_size = Vector2(330, 96)
		grid.add_child(btn)
	b.add_child(_btn("Выйти из админки", func(): _confirm("Выйти из админки?", func(): api.do_logout())))


# --- Раздел ------------------------------------------------------------------------

func _show_section(section_id: String) -> void:
	var b := _frame("Раздел")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/" + section_id)
	if not res.ok:
		_fail(res)
		return
	var s: Dictionary = res.data
	b.add_child(Ui.label(str(s["title"]), 28, "accent"))
	b.add_child(_row([_btn("Промпт для ИИ", func(): _copy_prompt(section_id), 20),
			_btn("Выгрузить ZIP", func(): _export(section_id), 20)]))
	if str(s["preview"]) != "none":
		b.add_child(_btn("Предпросмотр", func(): _open(_show_previews), 20))
	var kind: String = str(s["objects_kind"]["kind"])
	b.add_child(Ui.label("Объекты", 24, "accent"))
	for o in s["objects"]:
		b.add_child(_btn("%s  ·  %s" % [o["title"], o["id"]], func(): _open(_show_object.bind(section_id, str(o["id"]), false)), 21))
	if kind != "single":
		b.add_child(_btn("+ Новый объект", func():
			_ask("id нового объекта (латиница, цифры, _)", "например new_hero", func(oid):
				if oid != "":
					_open(_show_object.bind(section_id, oid, true))), 21))
	var obj_files := {}
	for o in s["objects"]:
		obj_files[str(o["file"])] = true
	var extra: Array = s["files"].filter(func(f): return not obj_files.has(str(f["path"])))
	if not extra.is_empty():
		b.add_child(Ui.label("Файлы настроек раздела", 24, "accent"))
		for f in extra:
			b.add_child(_btn(str(f["path"]), func(): _open(_show_json_file.bind(str(f["path"]))), 20))
	b.add_child(Ui.label("Картинки и файлы (%d)" % s["assets"].size(), 24, "accent"))
	b.add_child(_btn("+ Загрузить новый файл", func():
		_ask("Путь нового файла в контенте", "например ui/hub/icon_new.png", func(p):
			if p != "":
				_pick_and_upload(p)), 20))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	b.add_child(grid)
	for a in s["assets"].slice(0, 120):
		grid.add_child(_asset_tile(str(a["path"])))
	if s["assets"].size() > 120:
		b.add_child(_text("Показаны первые 120 файлов. Остальные — через ZIP-выгрузку.", 17))


func _asset_tile(path: String) -> Control:
	var box := VBoxContainer.new()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(212, 160)
	btn.expand_icon = true
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.pressed.connect(func(): _asset_actions(path))
	box.add_child(btn)
	var l := Ui.label(path.get_file(), 14)
	l.clip_text = true
	l.custom_minimum_size = Vector2(212, 0)
	box.add_child(l)
	if path.get_extension() in ["png", "webp", "jpg", "jpeg"]:
		_load_thumb(path, btn)
	return box


func _load_thumb(path: String, btn: Button) -> void:
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not res.ok or not is_instance_valid(btn):
		return
	var tex := Previews.texture_from_bytes(res.bytes, path)
	if tex:
		btn.icon = tex


func _asset_actions(path: String) -> void:
	_choose(path, [["Заменить", func(): _pick_and_upload(path)], ["Скачать", func(): _download(path)],
			["Удалить", func(): _confirm("Удалить %s в черновике?" % path, func():
				var r: Dictionary = await api.call_api(HTTPClient.METHOD_DELETE, "/files?path=" + path.uri_encode())
				_say("Файл удалён в черновике" if r.ok else "Ошибка: " + str(r.error), r.get("errors", [])), "Удалить")]])


func _download(path: String) -> void:
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not r.ok:
		_fail(r)
		return
	Previews.save_file(self, path.get_file(), r.bytes, func(where: String): _say("Сохранено: " + where))


## Окно с несколькими действиями: options = [[текст, Callable], ...]
func _choose(text: String, options: Array) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 360)
	panel.custom_minimum_size = Vector2(640, 0)
	dim.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	box.add_child(Ui.label(text, 22))
	for o in options:
		box.add_child(_btn(str(o[0]), func():
			dim.queue_free()
			o[1].call()))
	box.add_child(_btn("Отмена", func(): dim.queue_free()))


func _show_json_file(path: String) -> void:
	var b := _frame(path.get_file())
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not res.ok:
		_fail(res)
		return
	b.add_child(_text(path, 17))
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 900)
	te.text = res.bytes.get_string_from_utf8()
	b.add_child(te)
	b.add_child(_btn("Сохранить в черновик", func():
		if JSON.parse_string(te.text) == null:
			_say("Ошибка: это не правильный JSON")
			return
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + path.uri_encode(), te.text.to_utf8_buffer())
		if r.ok:
			_say("Сохранено в черновик" if r.data.get("changed", true) else "Без изменений")
		else:
			_fail(r)))


# --- Объект: форма по схеме -------------------------------------------------------------

func _load_schemas(root: String) -> Dictionary:
	var out := {}
	var queue := [root]
	while not queue.is_empty():
		var name: String = queue.pop_front()
		if out.has(name):
			continue
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/schemas/" + name)
		if not r.ok:
			continue
		out[name] = r.data
		var refs := {}
		SchemaForm.refs_of(r.data, refs)
		for k in refs.keys():
			if not out.has(k):
				queue.append(k)
	return out


func _show_object(section_id: String, oid: String, create: bool) -> void:
	var b := _frame(("Новый: " if create else "") + oid)
	var data: Variant = {}
	var schema_name := ""
	if create:
		var sres: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/" + section_id)
		if not sres.ok:
			_fail(sres)
			return
		for f in sres.data["files"]:
			if f["schema"] != null and schema_name == "":
				schema_name = str(f["schema"])
		var kind: String = str(sres.data["objects_kind"]["kind"])
		if kind == "file_per_object":
			var pattern: String = str(sres.data["objects_kind"]["path"])
			for f in sres.data["files"]:
				if f["schema"] != null and _matches(pattern, str(f["path"])):
					schema_name = str(f["schema"])
					break
	else:
		var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/%s/objects/%s" % [section_id, oid])
		if not res.ok:
			_fail(res)
			return
		data = res.data["data"]
		schema_name = str(res.data["schema"]) if res.data["schema"] != null else ""
	var schemas: Dictionary = await _load_schemas(schema_name) if schema_name != "" else {}
	var item_schema: Dictionary = schemas.get(schema_name, {})
	# Для объектов в массиве (фракции, баннеры) форма строится по схеме элемента
	var sec: Dictionary = (await api.call_api(HTTPClient.METHOD_GET, "/sections/" + section_id)).data
	var okind: Dictionary = sec.get("objects_kind", {})
	if str(okind.get("kind", "")) == "array_in_file":
		var key := str(okind["key"])
		var arr: Variant = item_schema.get("properties", {}).get(key, {})
		if arr is Dictionary and arr.has("items"):
			schemas["__item__"] = arr["items"]
			for k in item_schema.keys():
				if k == "$defs":
					schemas["__item__"]["$defs"] = item_schema["$defs"]
			schema_name = "__item__"
	if create:
		var form0 := SchemaForm.new()
		form0.schemas = schemas
		data = form0.default_for(schemas.get(schema_name, {}), schema_name)
		if data is Dictionary and str(okind.get("kind", "")) != "file_per_object":
			data["id"] = oid
		elif data is Dictionary and (data as Dictionary).has("id") == false and schemas.get(schema_name, {}).get("properties", {}).has("id"):
			data["id"] = oid
	b.add_child(_text("Схема: %s · поля со * обязательны. Изменения попадают в черновик." % (schema_name if schema_name != "__item__" else "элемент списка"), 17))
	var form := SchemaForm.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(form)
	form.build(data, schema_name, schemas)
	var json_box := TextEdit.new()
	json_box.custom_minimum_size = Vector2(0, 900)
	json_box.visible = false
	b.add_child(json_box)
	var mode := {"json": false}
	var toggle := _btn("Как JSON", func(): pass, 20)
	toggle.pressed.connect(func():
		if mode["json"]:
			var parsed: Variant = JSON.parse_string(json_box.text)
			if parsed == null:
				_say("Ошибка: это не правильный JSON")
				return
			form.build(parsed, schema_name, schemas)
		else:
			json_box.text = JSON.stringify(form.get_value(), "  ")
		mode["json"] = not mode["json"]
		form.visible = not mode["json"]
		json_box.visible = mode["json"]
		toggle.text = "Как форма" if mode["json"] else "Как JSON")
	var save := _btn("Сохранить в черновик", func():
		var value: Variant = JSON.parse_string(json_box.text) if mode["json"] else form.get_value()
		if value == null:
			_say("Ошибка: это не правильный JSON")
			return
		_say("Сохранение…")
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/sections/%s/objects/%s" % [section_id, oid],
				{"data": value, "create": create})
		if r.ok:
			_say("Сохранено в черновик. Опубликовать — в разделе «Черновик».")
			create = false
		else:
			_fail(r), 22)
	var actions := [toggle, save]
	if not create:
		actions.append(_btn("Удалить", func():
			_confirm("Удалить «%s» в черновике?" % oid, func():
				var r: Dictionary = await api.call_api(HTTPClient.METHOD_DELETE, "/sections/%s/objects/%s" % [section_id, oid])
				if r.ok:
					_back()
				else:
					_fail(r)), 20))
	b.add_child(_row(actions))
	if section_id == "heroes" and not create:
		b.add_child(_btn("Предпросмотр героя", func(): _open(_preview_hero.bind(oid)), 20))


static func _matches(pattern: String, path: String) -> bool:
	var parts := pattern.split("{id}")
	return parts.size() == 2 and path.begins_with(parts[0]) and path.ends_with(parts[1])


# --- Черновик, версии, журнал ----------------------------------------------------------

const CHANGE_NAMES := {"add": "добавлен", "update": "изменён", "delete": "удалён"}


func _show_draft() -> void:
	var b := _frame("Черновик")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/draft")
	if not res.ok:
		_fail(res)
		return
	var d: Dictionary = res.data
	var changes: Array = d["changes"]
	b.add_child(_text("Начат от версии №%s, сейчас у игроков №%s." % [_num(d["base_release"]), _num(d["live_release"])], 19))
	if bool(d["outdated"]):
		b.add_child(_text("Версия игры изменилась (откат или публикация) — перенесите черновик на текущую версию.", 19))
		b.add_child(_btn("Перенести черновик на текущую версию", func():
			var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/draft/rebase", {})
			if r.ok:
				_show_draft()
			else:
				_fail(r), 20))
	if changes.is_empty():
		b.add_child(Ui.label("Черновик пуст — изменений нет", 24))
		return
	b.add_child(Ui.label("Изменения (%d)" % changes.size(), 24, "accent"))
	for c in changes:
		var line := HBoxContainer.new()
		var t := _text("%s — %s" % [c["path"], CHANGE_NAMES.get(c["change"], c["change"])], 18)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(t)
		var undo := _btn("Отменить", func():
			var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {"path": c["path"]})
			if r.ok:
				_show_draft()
			else:
				_fail(r), 18)
		undo.custom_minimum_size = Vector2(170, 64)
		line.add_child(undo)
		b.add_child(line)
	var comment := Ui.line_edit("Комментарий к версии (что изменилось)")
	b.add_child(comment)
	b.add_child(_btn("Отправить на тест (видят только тестовые аккаунты)", func():
		_say("Сборка и проверка версии…")
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/draft/test", {"comment": comment.text})
		if r.ok:
			_say("Версия №%d на тесте. Проверьте на тестовом аккаунте, затем «Версии» → «Для всех»." % int(r.data["release"]))
		else:
			_fail(r), 20))
	b.add_child(_btn("Опубликовать сразу для всех", func():
		_confirm("Опубликовать черновик сразу для ВСЕХ игроков, без теста?", func():
			_say("Сборка и публикация…")
			var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/draft/publish", {"comment": comment.text, "confirm": true})
			if r.ok:
				_say("Опубликована версия №%d" % int(r.data["release"]))
				_show_draft()
			else:
				_fail(r), "Опубликовать"), 20))
	b.add_child(_btn("Сбросить весь черновик", func():
		_confirm("Отменить ВСЕ правки черновика?", func():
			var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {})
			if r.ok:
				_show_draft()
			else:
				_fail(r), "Сбросить"), 20))


func _show_releases() -> void:
	var b := _frame("Версии игры")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/releases?limit=50")
	if not res.ok:
		_fail(res)
		return
	var ch: Dictionary = res.data["channels"]
	b.add_child(_text("У игроков: №%s · на тесте: №%s" % [_num(ch.get("live")), _num(ch.get("test"))], 20))
	var live_id := int(ch.get("live", 0))
	for r in res.data["items"]:
		var rid := int(r["id"])
		var tags: Array = r["channels"]
		var src: String = {"base": "из репозитория", "admin": "из админки", "patch": "патч", "merge": "репозиторий + правки админки"}.get(str(r["source"]), str(r["source"]))
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(_text("№%d · %s · %s%s\n%s" % [rid, str(r["at"]).substr(0, 16).replace("T", " "), src,
				("  [" + ", ".join(tags.map(func(x): return "у игроков" if x == "live" else "тест")) + "]") if not tags.is_empty() else "",
				str(r["comment"])], 18))
		var btns := []
		if not tags.has("test"):
			btns.append(_btn("На тест", func(): _release_publish(rid, "test"), 18))
		if not tags.has("live"):
			btns.append(_btn("Откатить сюда" if rid < live_id else "Для всех", func():
				_confirm("%s версию №%d для ВСЕХ игроков?" % ["Откатить на" if rid < live_id else "Опубликовать", rid],
						func(): _release_publish(rid, "live"), "Да"), 18))
		if not btns.is_empty():
			box.add_child(_row(btns))
		b.add_child(panel)


func _release_publish(rid: int, channel: String) -> void:
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/releases/%d/publish" % rid, {"channel": channel, "confirm": true})
	if r.ok:
		_show_releases()
		_say("Готово: %s → №%d%s" % ["у игроков" if channel == "live" else "тест", rid,
				". В черновике есть правки от прошлой версии — перенесите его" if bool(r.data.get("draft_outdated", false)) else ""])
	else:
		_fail(r)


const ACTION_NAMES := {"login": "вход", "login_failed": "неудачный вход", "logout": "выход", "object_update": "изменение",
		"object_create": "добавление", "object_delete": "удаление", "file_put": "файл", "file_delete": "удалён файл",
		"draft_revert": "отмена правок", "draft_rebase": "перенос черновика", "draft_test": "на тест",
		"publish": "публикация", "rollback": "откат", "test": "на тест", "patch_apply": "ZIP-патч", "export": "выгрузка",
		"player_wallet": "ресурсы игрока", "player_test": "тестовый аккаунт", "player_ban": "бан",
		"backup_request": "бэкап", "client_release": "версия APK", "skin_create": "новый скин",
		"skin_delete": "удалён скин", "player_skin": "скин игрока"}


func _show_audit(before_id: int) -> void:
	var b := _frame("Журнал действий")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/audit?limit=50" + ("&before_id=%d" % before_id if before_id > 0 else ""))
	if not res.ok:
		_fail(res)
		return
	var last := 0
	for x in res.data["items"]:
		last = int(x["id"])
		b.add_child(_text("%s · %s · %s\n%s  (%s)" % [str(x["at"]).substr(0, 19).replace("T", " "), x["login"],
				ACTION_NAMES.get(x["action"], x["action"]), x["summary"], x["ip"]], 17))
	if res.data["items"].size() == 50:
		b.add_child(_btn("Ещё", func(): _open(_show_audit.bind(last)), 20))


# --- ZIP-патчи, выгрузка, промпт ---------------------------------------------------------

func _show_patch() -> void:
	var b := _frame("ZIP-патч")
	b.add_child(_text("Загрузите ZIP по формату docs/patch-format.md. Сначала покажем список изменений и ошибки, применение — в черновик.", 19))
	b.add_child(_btn("Выбрать ZIP-файл", func():
		Previews.pick_file(self, ["*.zip"], func(bytes: PackedByteArray, name: String): _patch_preview(bytes, name)), 22))


func _patch_preview(bytes: PackedByteArray, name: String) -> void:
	var b := _frame("Патч: " + name)
	_say("Проверка…")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/patches/preview", bytes)
	if not res.ok:
		_fail(res)
		return
	var p: Dictionary = res.data
	b.add_child(_text("«%s» · раздел %s\n%s" % [str(p["patch"].get("id")), str(p["patch"].get("section")), str(p["patch"].get("description"))], 20))
	for c in p["changes"]:
		b.add_child(_text("%s  %s%s" % [{"add": "+", "update": "*", "delete": "-"}.get(c["op"], "•"), c["path"],
				("  (" + str(c["object"]) + ")") if c.get("object") != null else ""], 18))
	for w in p["warnings"]:
		b.add_child(_text("Внимание: " + str(w), 18))
	if not bool(p["ok"]):
		_say("Патч не прошёл проверку:", p["errors"])
		return
	_say("Ошибок нет: %d изменений" % p["changes"].size())
	b.add_child(_btn("Применить в черновик", func():
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/patches/apply", bytes)
		if r.ok:
			_say("Патч применён в черновик. Дальше — «Черновик» → тест или публикация.")
		else:
			_fail(r), 22))


func _copy_prompt(section_id: String) -> void:
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/%s/prompt" % section_id)
	if not r.ok:
		_fail(r)
		return
	DisplayServer.clipboard_set(str(r.data["prompt"]))
	_say("Промпт скопирован (%d символов). Пример данных — кнопка «Выгрузить ZIP»." % str(r.data["prompt"]).length())


func _export(section_id: String) -> void:
	_say("Выгрузка…")
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/%s/export" % section_id, null, true)
	if not r.ok:
		_fail(r)
		return
	Previews.save_file(self, section_id + ".zip", r.bytes, func(where: String): _say("Сохранено: " + where))


func _pick_and_upload(path: String) -> void:
	Previews.pick_file(self, ["*.png", "*.webp", "*.jpg", "*.ogg", "*.json", "*.ttf"], func(bytes: PackedByteArray, _name: String):
		_say("Загрузка…")
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + path.uri_encode(), bytes)
		if r.ok:
			_say("Файл %s в черновике" % path)
		else:
			_fail(r))


# --- Картинки игры по местам использования -------------------------------------------------

var _asset_groups: Array = []


func _show_assets() -> void:
	var b := _frame("Картинки игры")
	_say("Загрузка…")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/assets")
	if not res.ok:
		_fail(res)
		return
	_say("")
	_asset_groups = res.data["groups"]
	b.add_child(_text("Картинки сгруппированы по тому, где они используются в игре. Нажмите группу — увидите её картинки; нажмите картинку — заменить, скачать или удалить.", 18))
	for g in _asset_groups:
		var name := str(g["name"])
		b.add_child(_btn("%s  (%d)" % [name, int(g["count"])], func(): _open(_show_asset_group.bind(name)), 21))


func _show_asset_group(name: String) -> void:
	var b := _frame(name)
	var group: Dictionary = {}
	for g in _asset_groups:
		if g["name"] == name:
			group = g
	if group.is_empty():
		return
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 10)
	b.add_child(grid)
	for it in group["items"]:
		var box := _asset_tile(str(it["path"]))
		var where := Ui.label(str(it["where"]), 13)
		where.custom_minimum_size = Vector2(212, 0)
		where.modulate = Color(1, 1, 1, 0.7)
		box.add_child(where)
		grid.add_child(box)
	b.add_child(_btn("+ Загрузить новый файл", func():
		_ask("Путь нового файла в контенте", "например ui/hub/icon_new.png", func(p):
			if p != "":
				_pick_and_upload(p)), 20))


# --- Конструктор экранов ------------------------------------------------------------------

const SCREEN_SCENES := {"hub": "res://scenes/main.tscn", "heroes": "res://scenes/heroes.tscn",
		"inventory": "res://scenes/inventory.tscn", "summon": "res://scenes/summon.tscn",
		"campaign": "res://scenes/campaign.tscn", "team_select": "res://scenes/team_select.tscn",
		"boot": "res://scenes/boot.tscn", "battle": "res://scenes/team_select.tscn"}


func _show_screens() -> void:
	var b := _frame("Конструктор экранов")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/screens")
	if not res.ok:
		_fail(res)
		return
	b.add_child(_text("Расстановка элементов каждого экрана игры: кнопки, иконки, надписи, панели, места под списки. Здания города — «Предпросмотр» → «Главный экран: двигать здания».", 18))
	for o in res.data["objects"]:
		b.add_child(_btn(str(o["title"]) + "  ·  " + str(o["id"]), func(): _open(_screen_editor.bind(str(o["id"]))), 22))


func _screen_editor(screen_id: String) -> void:
	var b := _frame("Экран: " + screen_id)
	var path := "ui/screens/%s.json" % screen_id
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not res.ok:
		_fail(res)
		return
	var layout: Variant = JSON.parse_string(res.bytes.get_string_from_utf8())
	if not layout is Dictionary:
		_say("Ошибка: файл раскладки повреждён")
		return
	var images := []
	for p in Content.state["files"].keys():
		var ps := str(p)
		if (ps.begins_with("ui/") or ps.ends_with("/portrait.png")) and ps.get_extension() in ["png", "webp", "jpg"]:
			images.append(ps)
	images.sort()
	var ed := LayoutEditor.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(ed)
	ed.setup(self, screen_id, path, layout, images)
	b.add_child(_btn("Открыть в игре (после «Сохранить»)", func():
		await _with_draft(func(): pass)
		_open_game(str(SCREEN_SCENES.get(screen_id, "res://scenes/main.tscn"))), 20))


# --- Игроки ------------------------------------------------------------------------------

const CURRENCIES := [["gold", "золото"], ["hero_xp", "опыт"], ["essence", "эссенция"], ["crystals", "кристаллы"],
		["scrolls", "свитки призыва"], ["ore", "руда"], ["legacy_shards", "осколки наследия"]]


func _show_players(query: String) -> void:
	var b := _frame("Игроки")
	var q := Ui.line_edit("Номер (#1001), имя или почта")
	q.text = query
	b.add_child(q)
	b.add_child(_btn("Найти", func(): _show_players(q.text.strip_edges()), 22))
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/players?q=" + query.uri_encode())
	if not res.ok:
		_fail(res)
		return
	if res.data["items"].is_empty():
		b.add_child(_text("Никого не найдено", 20))
	for p in res.data["items"]:
		var flags := []
		if bool(p["is_test"]):
			flags.append("ТЕСТ")
		if p["banned_until"] != null:
			flags.append("БАН")
		b.add_child(_btn("#%d %s · %s %s" % [int(p["number"]), p["name"], p["email"] if p["email"] != null else "гость",
				" ".join(flags)], func(): _open(_show_player.bind(str(p["id"]))), 20))


func _show_player(pid: String) -> void:
	var b := _frame("Игрок")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/players/" + pid)
	if not res.ok:
		_fail(res)
		return
	var p: Dictionary = res.data
	b.add_child(Ui.label("#%d %s" % [int(p["number"]), p["name"]], 28, "accent"))
	b.add_child(_text("%s
Создан: %s · последний вход: %s
Кампания: пройдено этапов %d · предметов: %d · устройств: %d%s%s" % [
			p["email"] if p["email"] != null else "гость (без почты)", str(p["created_at"]).substr(0, 10),
			str(p["last_login_at"]).substr(0, 16).replace("T", " "), int(p["campaign_cleared"]), int(p["items"]), int(p["sessions"]),
			"\nТЕСТОВЫЙ аккаунт — видит канал test" if bool(p["is_test"]) else "",
			("\nЗАБАНЕН до %s: %s" % [str(p["banned_until"]).substr(0, 16).replace("T", " "), p["ban_reason"]]) if p["banned_until"] != null else ""], 19))
	b.add_child(Ui.label("Кошелёк", 24, "accent"))
	var w: Dictionary = p["wallet"]
	var lines := []
	for cur in CURRENCIES:
		lines.append("%s: %d" % [cur[1], int(w.get(cur[0], 0))])
	for k in w.keys():
		if str(k).begins_with("faction_scroll_"):
			lines.append("%s: %d" % [k, int(w[k])])
	b.add_child(_text(" · ".join(lines), 19))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 64)
	for cur in CURRENCIES:
		pick.add_item(cur[1])
	var amount := Ui.line_edit("Сколько: 500 — добавить, -500 — списать")
	amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	var reason := Ui.line_edit("Причина (обязательно, попадёт в журнал)")
	b.add_child(pick)
	b.add_child(amount)
	b.add_child(reason)
	b.add_child(_btn("Изменить ресурсы", func():
		if not amount.text.strip_edges().is_valid_int():
			_say("Ошибка: введите целое число")
			return
		var code: String = CURRENCIES[pick.selected][0]
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/players/%s/wallet" % pid,
				{"changes": {code: int(amount.text.strip_edges())}, "reason": reason.text.strip_edges()})
		if r.ok:
			_show_player(pid)
			_say("Готово")
		else:
			_fail(r), 22))
	b.add_child(_btn("Сделать обычным аккаунтом" if bool(p["is_test"]) else "Сделать тестовым (видит канал test)", func():
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/players/%s/test" % pid, {"on": not bool(p["is_test"])})
		if r.ok:
			_show_player(pid)
		else:
			_fail(r), 20))
	if p["banned_until"] != null:
		b.add_child(_btn("Снять бан", func():
			var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/players/%s/ban" % pid, {"days": 0})
			if r.ok:
				_show_player(pid)
			else:
				_fail(r), 20))
	else:
		var days := Ui.line_edit("Бан: сколько дней (36500 — навсегда)")
		days.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		var why := Ui.line_edit("Причина бана (игрок её увидит)")
		b.add_child(days)
		b.add_child(why)
		b.add_child(_btn("Забанить", func():
			if not days.text.strip_edges().is_valid_int():
				_say("Ошибка: введите число дней")
				return
			_confirm("Забанить игрока #%d на %s дн.?" % [int(p["number"]), days.text], func():
				var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/players/%s/ban" % pid,
						{"days": int(days.text.strip_edges()), "reason": why.text.strip_edges()})
				if r.ok:
					_show_player(pid)
				else:
					_fail(r), "Забанить"), 20))
	b.add_child(Ui.label("Скины", 24, "accent"))
	b.add_child(_text("Получены: " + (", ".join(p.get("skins", [])) if not p.get("skins", []).is_empty() else "нет (обычный вид и бесплатные скины есть у всех)"), 18))
	var sk_hero := Ui.line_edit("id героя, например humai")
	var sk_id := Ui.line_edit("id скина, например winter")
	var sk_why := Ui.line_edit("Причина (в журнал)")
	b.add_child(sk_hero)
	b.add_child(sk_id)
	b.add_child(sk_why)
	var grant := func(give: bool):
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/players/%s/skins" % pid,
				{"hero": sk_hero.text.strip_edges(), "skin": sk_id.text.strip_edges(), "give": give, "reason": sk_why.text.strip_edges()})
		if r.ok:
			_show_player(pid)
			_say("Готово")
		else:
			_fail(r)
	b.add_child(_row([_btn("Выдать скин", func(): grant.call(true), 20), _btn("Забрать скин", func(): grant.call(false), 20)]))
	b.add_child(Ui.label("Герои (%d)" % p["heroes"].size(), 24, "accent"))
	var hl := []
	for h in p["heroes"]:
		hl.append("%s — %s, ур. %d%s" % [h["hero"], h["tier"], int(h["level"]), " ◆" if bool(h["crystal"]) else ""])
	b.add_child(_text("\n".join(hl), 18))


# --- Бэкапы и версии APK ----------------------------------------------------------------------

func _show_backups() -> void:
	var b := _frame("Бэкапы")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/backups")
	if not res.ok:
		_fail(res)
		return
	var d: Dictionary = res.data
	b.add_child(_text("Каждый день в 05:00 по Уфе: база игроков + контент. Хранятся %d дней." % int(d["retention_days"]), 19))
	if str(d["last_result"]) != "":
		b.add_child(_text("Последний бэкап по запросу: " + str(d["last_result"]).replace("ok", "успешно").replace("error", "ОШИБКА"), 19))
	if bool(d["pending"]):
		b.add_child(_text("Бэкап запрошен и скоро начнётся…", 19))
	b.add_child(_btn("Сделать бэкап сейчас", func():
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/backups/run", {})
		if r.ok:
			_show_backups()
			_say(str(r.data["message"]))
		else:
			_fail(r), 22))
	b.add_child(_btn("Обновить список", _show_backups, 20))
	for x in d["items"]:
		b.add_child(_text("%s · %s%s" % [x["name"], Content.format_mb(int(x["size"])), "" if bool(x["complete"]) else " · НЕПОЛНЫЙ"], 19))
	if d["items"].is_empty():
		b.add_child(_text("Бэкапов пока нет", 19))
	b.add_child(_text("Восстановление (вся база вернётся к выбранному дню) — только на VPS, для безопасности:\n%s\nПеред восстановлением автоматически делается свежий бэкап." % d["restore_command"], 18))


func _show_apk() -> void:
	var b := _frame("Версии APK игры")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/client-releases")
	if not res.ok:
		_fail(res)
		return
	b.add_child(_text("Игроки получают предложение обновиться до последней включённой версии. «Обязательная» — старые версии не пустит в игру.", 18))
	for r in res.data["items"]:
		var code := int(r["code"])
		var panel := PanelContainer.new()
		var box := VBoxContainer.new()
		panel.add_child(box)
		box.add_child(_text("%s (код %d) · %s · %s%s%s" % [r["name"], code, Content.format_mb(int(r["size"])), str(r["at"]).substr(0, 10),
				"" if bool(r["active"]) else " · ВЫКЛЮЧЕНА", " · ОБЯЗАТЕЛЬНАЯ" if bool(r["mandatory"]) else ""], 18))
		var btns := [_btn("Выключить" if bool(r["active"]) else "Включить", func():
			_apk_set(code, {"active": not bool(r["active"])}), 18)]
		if bool(r["active"]):
			btns.append(_btn("Необязательная" if bool(r["mandatory"]) else "Обязательная", func():
				_confirm("Изменить обязательность версии %s?" % r["name"], func(): _apk_set(code, {"mandatory": not bool(r["mandatory"])})), 18))
		box.add_child(_row(btns))
		b.add_child(panel)


func _apk_set(code: int, body: Dictionary) -> void:
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/client-releases/%d" % code, body)
	if r.ok:
		_show_apk()
	else:
		_fail(r)


# --- Предпросмотр ------------------------------------------------------------------------

func _show_previews() -> void:
	var b := _frame("Предпросмотр черновика")
	b.add_child(_text("Сначала скачиваются файлы черновика (только изменённые), затем экраны показываются так, как их увидит игрок.", 19))
	b.add_child(_btn("Главный экран: двигать здания", func(): _with_draft(func(): _open(_preview_hub)), 22))
	b.add_child(_btn("Герои и анимации", func(): _with_draft(func(): _open(_preview_heroes)), 22))
	b.add_child(_btn("Карта кампании", func(): _with_draft(func(): _open(_preview_campaign)), 22))
	b.add_child(Ui.label("Экраны игры", 24, "accent"))
	for item in [["Главный экран", "res://scenes/main.tscn"], ["Герои", "res://scenes/heroes.tscn"],
			["Инвентарь", "res://scenes/inventory.tscn"], ["Призыв", "res://scenes/summon.tscn"],
			["Кампания", "res://scenes/campaign.tscn"], ["Тестовый бой", "res://scenes/team_select.tscn"]]:
		b.add_child(_btn(item[0], func(): _with_draft(func(): _open_game(str(item[1]))), 22))


func _with_draft(then: Callable) -> void:
	_say("Загрузка файлов черновика…")
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/draft")
	if not r.ok:
		_fail(r)
		return
	var files := []
	for p in r.data["files"].keys():
		var f: Dictionary = r.data["files"][p]
		files.append({"path": p, "sha256": f["sha256"], "size": int(f["size"])})
	var m := {"release": 0, "channel": "draft", "base_url": r.data["base_url"],
			"packages": [{"id": "draft", "required": true, "files": files}]}
	var on_progress := func(done, total): _say("Загрузка файлов черновика: %s из %s" % [Content.format_mb(done), Content.format_mb(total)])
	Content.progress.connect(on_progress)
	var res: Dictionary = await Content.use_manifest(m)
	Content.progress.disconnect(on_progress)
	if not res.ok:
		_say("Ошибка: " + str(res.error))
		return
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	_say("")
	then.call()


func _open_game(scene: String) -> void:
	var s: Dictionary = await Api.ensure_session()
	if not s.ok:
		_say("Ошибка входа игрока для предпросмотра: " + str(s.error))
		return
	Previews.add_back_button(get_tree())
	ScreenLayout.overrides.clear()
	if not get_tree().root.has_node("LiveEdit"):  # долгое нажатие в игре — правка экрана
		get_tree().root.add_child(preload("res://admin/live_edit.gd").new())
	get_tree().change_scene_to_file(scene)


func _preview_hub() -> void:
	var b := _frame("Главный экран")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/hub/objects/hub")
	if not res.ok:
		_fail(res)
		return
	var hub: Dictionary = res.data["data"]
	b.add_child(_text("Перетаскивайте здания пальцем; листать — пальцем по фону. Затем «Сохранить в черновик».", 19))
	b.add_child(_row([_btn("Сохранить в черновик", func():
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/sections/hub/objects/hub", {"data": hub})
		_say("Расположение сохранено в черновик" if r.ok else "Ошибка: " + str(r.error), r.get("errors", [])), 20),
		_btn("Как в игре", func(): _open_game("res://scenes/main.tscn"), 20)]))
	var editor: Control = Previews.hub_editor(hub)
	b.add_child(editor)


func _preview_heroes() -> void:
	var b := _frame("Герои")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/heroes")
	if not res.ok:
		_fail(res)
		return
	var grid := GridContainer.new()
	grid.columns = 4
	b.add_child(grid)
	for o in res.data["objects"]:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(160, 160)
		btn.icon = Content.load_texture("heroes/%s/portrait.png" % o["id"])
		btn.expand_icon = true
		btn.tooltip_text = str(o["title"])
		btn.pressed.connect(func(): _open(_preview_hero.bind(str(o["id"]))))
		grid.add_child(btn)


func _preview_hero(hero_id: String) -> void:
	var b := _frame("Предпросмотр героя")
	if not Content.has_file("heroes/%s/hero.json" % hero_id):
		await _with_draft(func(): pass)
	var hero: Variant = Content.load_json("heroes/%s/hero.json" % hero_id)
	if not hero is Dictionary:
		_say("Ошибка: герой не найден в черновике")
		return
	b.add_child(Previews.hero_card(hero))
	var stage := Previews.rig_stage(hero_id)
	b.add_child(stage)
	var rig: Node = stage.get_meta("rig")
	var anims: Array = rig.data.get("animations", {}).keys()
	var grid := GridContainer.new()
	grid.columns = 4
	for a in anims:
		var btn := _btn(str(a), func(): rig.play(str(a)), 18)
		btn.custom_minimum_size = Vector2(160, 64)
		grid.add_child(btn)
	b.add_child(grid)
	b.add_child(_row([_btn("Отразить (как враг)", func(): rig.scale.x = -rig.scale.x, 18),
			_btn("Скорость ×0.5 / ×1", func(): rig.speed = 0.5 if rig.speed == 1.0 else 1.0, 18)]))
	b.add_child(_btn("Редактор анимации и частей героя", func(): _open(_anim_editor.bind(hero_id)), 22))
	# Скины: примерить, добавить, удалить
	b.add_child(Ui.label("Скины", 24, "accent"))
	var skins: Array = [{"id": "default", "name": "Обычный"}] + hero.get("skins", [])
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 60)
	for sk in skins:
		pick.add_item("%s%s" % [sk["name"], "  (бесплатный)" if bool(sk.get("free", false)) else ""])
	pick.item_selected.connect(func(i):
		rig.skin = str(skins[i]["id"])
		rig.rebuild(rig.data)
		rig.play("idle"))
	b.add_child(pick)
	b.add_child(_row([_btn("+ Новый скин", func(): _new_skin(hero_id), 18),
			_btn("Удалить выбранный", func():
				var sid := str(skins[pick.selected]["id"])
				if sid == "default":
					_say("Обычный вид удалить нельзя")
					return
				_confirm("Удалить скин «%s»? Игроки, у которых он выбран, увидят обычный вид." % skins[pick.selected]["name"], func():
					var r: Dictionary = await api.call_api(HTTPClient.METHOD_DELETE, "/heroes/%s/skins/%s" % [hero_id, sid])
					if r.ok:
						await _with_draft(func(): pass)
						_preview_hero(hero_id)
						_say("Скин удалён в черновике")
					else:
						_fail(r), "Удалить"), 18)]))
	b.add_child(_text("Новый скин — копия картинок обычного вида. Замените их в «Редактор анимации и частей» (выберите скин) или через ZIP героя.", 16))
	b.add_child(_btn("Нарезать из рисунка (в выбранный вид)", func():
		_open(_cutter.bind(hero_id, str(skins[pick.selected]["id"]))), 20))
	b.add_child(_text("Загрузите рисунок, лист персонажа или слои — части и скелет сделаются автоматически или с ИИ, потом поправите пальцем.", 16))
	b.add_child(Ui.label("Герой целиком", 24, "accent"))
	b.add_child(_row([_btn("Выгрузить героя (ZIP)", func():
		_say("Выгрузка…")
		var r: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/heroes/%s/export" % hero_id, null, true)
		if r.ok:
			Previews.save_file(self, "hero_%s.zip" % hero_id, r.bytes, func(where: String): _say("Сохранено: " + where))
		else:
			_fail(r), 18),
		_btn("Загрузить ZIP героя", func(): _open(_show_patch), 18)]))
	b.add_child(_text("В ZIP: hero.json, скелет с анимациями, все картинки и скины. Замените картинки (те же имена) и загрузите — покажем список изменений.", 16))


func _new_skin(hero_id: String) -> void:
	_ask("id скина (латиница, например winter)", "winter", func(sid: String):
		if sid == "":
			return
		_ask("Название скина для игроков", "Зимний", func(name: String):
			_choose("Скин «%s»: кому доступен?" % name, [
				["Только тем, кому выдам", func(): _create_skin(hero_id, sid, name, false)],
				["Всем бесплатно", func(): _create_skin(hero_id, sid, name, true)]])))


func _create_skin(hero_id: String, sid: String, name: String, free: bool) -> void:
	_say("Создание скина…")
	var r: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/heroes/%s/skins" % hero_id, {"skin": sid, "name": name, "free": free})
	if not r.ok:
		_fail(r)
		return
	await _with_draft(func(): pass)
	_preview_hero(hero_id)
	_say("Скин «%s» создан в черновике (%d картинок). Замените картинки и опубликуйте." % [name, int(r.data["files"])])


func _cutter(hero_id: String, target := "default") -> void:
	var b := _frame("Нарезка героя: " + hero_id)
	var c := HeroCutter.new()
	b.add_child(c)
	await c.setup(self, hero_id, target)


func _cut_selftest() -> void:
	## Рисунок → авто → мазок → сборка в черновик → скелет героя обновлён
	await _cutter("shulgen")
	var c: HeroCutter = null
	for ch in _body.get_children():
		if ch is HeroCutter:
			c = ch
	var img := Image.create(400, 600, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1))
	var rects := [[Rect2i(165, 40, 70, 80), Color("#E6BE96")], [Rect2i(150, 120, 100, 210), Color("#287840")],
			[Rect2i(120, 140, 30, 190), Color("#C8A028")], [Rect2i(250, 140, 30, 190), Color("#D2AA32")],
			[Rect2i(155, 330, 40, 230), Color("#5A3C1E")], [Rect2i(205, 330, 40, 230), Color("#644628")]]
	for r in rects:
		img.fill_rect(r[0], r[1])
	var ok := await c.upload(img.save_png_to_buffer(), "test.png")
	ok = ok and await c._auto()
	var parts_ok := c.parts.size() == 7 and c._part_tex.has("head")
	await c.test_stroke("head", "erase", Vector2(200, 60), 6)
	var res: Dictionary = await c.build_hero()
	var f: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=heroes/shulgen/skeleton.json", null, true)
	var sk: Variant = JSON.parse_string(f.bytes.get_string_from_utf8())
	var slots: Array = sk.get("slots", []) if sk is Dictionary else []
	ok = ok and parts_ok and bool(res.get("ok", false)) and slots.any(func(s): return str(s["image"]) == "rig/head.png")
	print("AUTOTEST CUT: ", JSON.stringify({"ok": ok, "parts": c.parts.size(), "slots": slots.size(), "joints": c.joints.size()}))
	c.tool = "joint"
	c.part = ""
	c._canvas.queue_redraw()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cut-scroll="):  # снимки экрана нижней части нарезчика
			var sc := _body.get_parent() as ScrollContainer
			if sc:
				await get_tree().process_frame
				sc.scroll_vertical = int(arg.get_slice("=", 1))
		if arg == "--cut-preview":
			await _with_draft(func(): pass)
			_open(_preview_hero.bind("shulgen"))
		if arg == "--cut-part":
			c.part = "head"
			c._set_tool("erase")
			c._refresh_parts()
	if "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
		await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {})
		get_tree().quit(0 if ok else 1)


func _anim_editor(hero_id: String) -> void:
	var b := _frame("Анимация: " + hero_id)
	if not Content.has_file("heroes/%s/hero.json" % hero_id):
		await _with_draft(func(): pass)
	var hero: Variant = Content.load_json("heroes/%s/hero.json" % hero_id)
	if not hero is Dictionary:
		_say("Ошибка: герой не найден")
		return
	var path := str(hero["art"]["skeleton"])
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not res.ok:
		_fail(res)
		return
	var skel: Variant = JSON.parse_string(res.bytes.get_string_from_utf8())
	if not skel is Dictionary:
		_say("Ошибка: skeleton.json повреждён")
		return
	var ed := AnimEditor.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_child(ed)
	ed.setup(self, hero_id, path, skel)


func _preview_campaign() -> void:
	var b := _frame("Кампания")
	for i in range(1, 30):
		var ch: Variant = Content.load_json("campaign/chapter_%d/chapter.json" % i)
		if not ch is Dictionary:
			break
		b.add_child(Previews.chapter_card(ch, i))


func _assets_shot() -> void:
	await _show_assets()
	await _show_asset_group("Главный экран")


func _skin_shot() -> void:
	## Для снимка: предпросмотр Хумай в скине «winter»
	await _with_draft(func(): pass)
	await _preview_hero("humai")
	for c in _body.get_children():
		if c is ColorRect and c.has_meta("rig"):
			var rig: Node = c.get_meta("rig")
			rig.skin = "winter"
			rig.rebuild(rig.data)
			rig.play("idle")


func _screen_selftest() -> void:
	## Перенос кнопки в конструкторе сохраняется в ui/screens/hub.json черновика
	await _with_draft(func(): pass)
	await _screen_editor("hub")
	var ed: LayoutEditor = null
	for c in _body.get_children():
		if c is LayoutEditor:
			ed = c
	var els: Array = ed.layout["elements"]
	var idx := -1
	for i in range(els.size()):
		if els[i]["id"] == "events":
			idx = i
	var n0 := els.size()
	ed.selected = idx
	ed._change(func(): els[idx]["x"] = 40.0)
	ed._add("label")
	ed.undo()
	await ed.save()
	var f: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=ui/screens/hub.json", null, true)
	var saved: Variant = JSON.parse_string(f.bytes.get_string_from_utf8())
	var moved := false
	var count := 0
	if saved is Dictionary:
		count = saved["elements"].size()
		for e in saved["elements"]:
			if e["id"] == "events" and int(e["x"]) == 40:
				moved = true
	var ok: bool = moved and count == n0  # добавленная надпись отменена «Отменить»
	print("AUTOTEST SCREENS: ", JSON.stringify({"ok": ok, "moved": moved, "elements": count}))
	await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {})
	get_tree().quit(0 if ok else 1)


func _anim_selftest() -> void:
	## Ключ, поставленный в редакторе, сохраняется в skeleton.json черновика
	await _anim_editor("ural_batyr")
	var ed: AnimEditor = null
	for c in _body.get_children():
		if c is AnimEditor:
			ed = c
	ed.bone = "arm_front"
	ed._select_anim("attack")
	ed._set_time(0.3)
	ed._set_key("rotate", [-60])
	await ed.save()
	var d: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/draft")
	var f: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/files?path=heroes/ural_batyr/skeleton.json", null, true)
	var sk: Variant = JSON.parse_string(f.bytes.get_string_from_utf8())
	var keys: Array = sk["animations"]["attack"]["bones"]["arm_front"]["rotate"] if sk is Dictionary else []
	var ok: bool = d.ok and d.data["changes"].size() == 1 and keys.any(func(k): return absf(float(k[0]) - 0.3) < 0.01 and int(k[1]) == -60)
	print("AUTOTEST ANIM: ", JSON.stringify({"ok": ok, "changes": d.data.get("changes", []).size(), "keys": keys}))
	await api.call_api(HTTPClient.METHOD_POST, "/draft/revert", {})
	get_tree().quit(0 if ok else 1)


# --- Автопроверка: godot --path client res://admin/admin_main.tscn -- --server=... --admin-autotest=login:pass

func _autotest(creds: String) -> void:
	await get_tree().process_frame
	var res: Dictionary = await api.do_login(creds.get_slice(":", 0), creds.get_slice(":", 1), "")
	var summary := {"login": res.ok}
	var secs: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections")
	summary["sections"] = secs.data.get("sections", []).size() if secs.ok else 0
	var obj: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/heroes/objects/humai")
	var schemas: Dictionary = await _load_schemas(str(obj.data.get("schema", "")))
	var form := SchemaForm.new()
	add_child(form)
	form.build(obj.data.get("data", {}), str(obj.data.get("schema", "")), schemas)
	var back: Variant = form.get_value()
	# Форма без правок должна вернуть те же данные: сохранение не создаёт правку в черновике
	var put: Dictionary = await api.call_api(HTTPClient.METHOD_PUT, "/sections/heroes/objects/humai", {"data": back})
	var draft: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/draft")
	summary["form_roundtrip"] = put.ok and draft.ok and draft.data["changes"].is_empty()
	if not put.ok:
		summary["put_error"] = str(put.error) + " " + str(put.get("errors", []))
	var prompt: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/sections/heroes/prompt")
	summary["prompt"] = prompt.ok and str(prompt.data.get("prompt", "")).contains("hero.schema.json")
	await _with_draft(func(): pass)
	summary["draft_files"] = Content.state["files"].size()
	summary["ok"] = res.ok and summary["sections"] >= 10 and summary["form_roundtrip"] and summary["prompt"] and summary["draft_files"] > 100
	print("AUTOTEST ADMIN: ", JSON.stringify(summary))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--admin-show="):  # для снимков экрана
			var what := arg.get_slice("=", 1)
			match what:
				"home": _open(_show_home)
				"object": _open(_show_object.bind("heroes", "humai", false))
				"draft": _open(_show_draft)
				"releases": _open(_show_releases)
				"hero": _open(_preview_hero.bind("ural_batyr"))
				"hub": _open(_preview_hub)
				"section": _open(_show_section.bind("hub"))
				"game": _open_game("res://scenes/inventory.tscn")
				"anim": _open(_anim_editor.bind("ural_batyr"))
				"animtest": await _anim_selftest()
				"cuttest": await _cut_selftest()
				"screens": await _with_draft(func(): _open(_screen_editor.bind("hub")))
				"screentest": await _screen_selftest()
				"skinshot": await _skin_shot()
				"assets": await _assets_shot()
				"livetest": await _with_draft(func(): _open_game("res://scenes/main.tscn"))
				"players": _open(_show_players.bind(""))
				"backups": _open(_show_backups)
	if "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
		get_tree().quit(0 if summary["ok"] else 1)
