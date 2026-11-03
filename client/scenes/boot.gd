extends Control
## Экран загрузки: вход → манифест → обязательные пакеты → главный экран.

var _status: Label
var _bar: ProgressBar
var _size_label: Label
var _retry: Button
var _later: Button
var _started_ms := 0
var _update_info: Dictionary = {}
var _updater := Updater.new()


func _ready() -> void:
	var col := Ui.screen(self)
	col.add_child(Ui.spacer())
	col.add_child(Ui.label("[НАЗВАНИЕ]", 56, "accent"))
	col.add_child(Ui.label("Легенды Урала оживают…", 28))
	col.add_child(Ui.spacer())
	_status = Ui.label("Подключение к серверу…", 30)
	col.add_child(_status)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 44)
	_bar.max_value = 1.0
	_bar.step = 0.0001
	_bar.show_percentage = false
	col.add_child(_bar)
	_size_label = Ui.label("", 26)
	col.add_child(_size_label)
	_retry = Ui.button("Повторить", _run)
	_retry.visible = false
	col.add_child(_retry)
	_later = Ui.button("Позже", _continue_without_update)
	_later.visible = false
	col.add_child(_later)
	col.add_child(Ui.label("Версия %s" % Config.client_version, 22))
	Content.progress.connect(_on_progress)
	_updater.progress.connect(_on_progress)
	if get_tree().has_meta("do_update"):
		_update_info = get_tree().get_meta("do_update")
		get_tree().remove_meta("do_update")
		_show_update(false)
		return
	_run()


func _run() -> void:
	_retry.visible = false
	_retry.text = "Повторить"
	_later.visible = false
	if _retry.pressed.is_connected(_install_update):
		_retry.pressed.disconnect(_install_update)
		_retry.pressed.connect(_run)
	_bar.value = 0
	_size_label.text = ""
	_status.text = "Подключение к серверу…"
	var auth: Dictionary = await Api.ensure_session()
	if not auth.ok:
		return _fail(auth.error)

	_status.text = "Проверка обновлений…"
	var upd: Dictionary = await Updater.check()
	if upd.ok and upd.update_available:
		_update_info = upd.latest
		if upd.required or _autotest_update():
			return _show_update(upd.required)
		get_tree().set_meta("update_offer", upd.latest)
	elif upd.ok:
		Updater.cleanup()
	var m: Dictionary = await Content.fetch_manifest()
	if not m.ok:
		if m.update_required and not _update_info.is_empty():
			return _show_update(true)
		return _fail(m.error, not m.update_required)

	var need: Array = Content.plan(true)
	if need.is_empty():
		_status.text = "Проверка файлов…"
	else:
		_status.text = "Загрузка обновлений"
		_started_ms = Time.get_ticks_msec()
	var res: Dictionary = await Content.sync_required()
	if not res.ok:
		return _fail(res.error)
	_status.text = "Готово!"
	_bar.value = 1.0
	if auth.has("notice"):
		get_tree().set_meta("notice", auth["notice"])
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_progress(done: int, total: int) -> void:
	if total <= 0:
		return
	_bar.value = float(done) / float(total)
	var text := "%s из %s" % [Content.format_mb(done), Content.format_mb(total)]
	var secs := (Time.get_ticks_msec() - _started_ms) / 1000.0
	if secs > 2.0 and done > 0:
		text += "  ·  %.1f МБ/с" % (done / 1048576.0 / secs)
	_size_label.text = text


# --- Обновление приложения ----------------------------------------------------

func _autotest_update() -> bool:
	return Config.autotest and "--autotest-update" in OS.get_cmdline_user_args()


func _show_update(required: bool) -> void:
	var vname := str(_update_info.get("version_name", ""))
	var notes := str(_update_info.get("notes", ""))
	_status.text = ("Нужно обновить приложение до версии %s" if required else "Доступна новая версия %s") % vname
	if notes != "":
		_status.text += "\n" + notes
	_bar.value = 0
	_size_label.text = "Размер: %s" % Content.format_mb(int(_update_info.get("size", 0)))
	if _retry.pressed.is_connected(_run):
		_retry.pressed.disconnect(_run)
	if not _retry.pressed.is_connected(_install_update):
		_retry.pressed.connect(_install_update)
	_retry.text = "Обновить"
	_retry.visible = true
	_later.visible = not required
	if _autotest_update():
		_install_update()
	elif Config.autotest:
		print("AUTOTEST REQUIRED_UPDATE: ", vname)
		get_tree().quit(2)


func _install_update() -> void:
	_retry.visible = false
	_later.visible = false
	_status.text = "Загрузка обновления…"
	_started_ms = Time.get_ticks_msec()
	var res: Dictionary = await _updater.download_and_install(_update_info)
	if _autotest_update():
		var ok_sha: bool = res.ok and await DownloadWorker.sha256_file(res.path) == str(_update_info["sha256"])
		print("AUTOTEST UPDATE: ", JSON.stringify({"ok": res.ok and ok_sha, "error": res.error,
				"version": _update_info.get("version_name")}))
		get_tree().quit(0 if res.ok and ok_sha else 1)
		return
	if not res.ok:
		_status.text = res.error
	else:
		_status.text = "Откроется установщик Android — нажмите «Установить».\nЕсли Android попросит разрешение на установку — разрешите и нажмите «Обновить» ещё раз."
	_retry.visible = true
	_later.visible = not bool(_update_info.get("mandatory", false))


func _continue_without_update() -> void:
	get_tree().set_meta("update_offer", _update_info)
	_run()


func _fail(message: String, can_retry := true) -> void:
	_status.text = message
	_retry.visible = can_retry
	if Config.autotest:
		print("AUTOTEST FAIL: ", message)
		get_tree().quit(1)
