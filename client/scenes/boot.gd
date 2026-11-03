extends Control
## Экран загрузки: вход → манифест → обязательные пакеты → главный экран.

var _status: Label
var _bar: ProgressBar
var _size_label: Label
var _retry: Button
var _started_ms := 0


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
	col.add_child(Ui.label("Версия %s" % Config.client_version, 22))
	Content.progress.connect(_on_progress)
	_run()


func _run() -> void:
	_retry.visible = false
	_bar.value = 0
	_size_label.text = ""
	_status.text = "Подключение к серверу…"
	var auth: Dictionary = await Api.ensure_session()
	if not auth.ok:
		return _fail(auth.error)

	_status.text = "Проверка обновлений…"
	var m: Dictionary = await Content.fetch_manifest()
	if not m.ok:
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


func _fail(message: String, can_retry := true) -> void:
	_status.text = message
	_retry.visible = can_retry
	if Config.autotest:
		print("AUTOTEST FAIL: ", message)
		get_tree().quit(1)
