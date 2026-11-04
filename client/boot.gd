extends Control
## Загрузчик и вход: /api/config (техработы и обязательное обновление), гостевой вход, /api/me, контент -> главный экран (hub.tscn).
## VERSION_CODE — номер сборки Android. В исходниках 1; тестовый APK в Actions подставляет номер сборки.

const VERSION_CODE := 1

var _status: Label
var _info: Label
var _btn_retry: Button
var _form: VBoxContainer


func _ready() -> void:
	_build_ui()
	_start()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	margin.add_child(box)

	var title := Label.new()
	title.text = "5Ufa"
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	var ver := Label.new()
	ver.text = "тестовая сборка v" + str(ProjectSettings.get_setting("application/config/version", "?"))
	ver.modulate = Color(1, 1, 1, 0.5)
	box.add_child(ver)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 32)
	box.add_child(_status)

	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 30)
	box.add_child(_info)

	_btn_retry = Button.new()
	_btn_retry.text = "Повторить"
	_btn_retry.custom_minimum_size = Vector2(0, 110)
	_btn_retry.add_theme_font_size_override("font_size", 34)
	_btn_retry.visible = false
	_btn_retry.pressed.connect(_start)
	box.add_child(_btn_retry)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 18)
	box.add_child(_form)


func _fail(text: String) -> void:
	print("[boot] FAIL: ", text.replace("\n", " | "))
	_status.text = text
	_btn_retry.visible = true


func _clear_form() -> void:
	for c in _form.get_children():
		c.queue_free()


func _start() -> void:
	_btn_retry.visible = false
	_clear_form()
	_info.text = ""
	_status.text = "Подключение к серверу…"

	var cfg: Dictionary = await Api.request("GET", "/api/config")
	if not cfg["ok"]:
		_fail("Нет связи с сервером.\n" + str(cfg["message"]))
		return
	if cfg["data"].get("maintenance", false):
		_fail("Технические работы.\n" + str(cfg["data"].get("maintenanceMessage", "")))
		return
	if _offer_update(cfg["data"]):
		return

	if Api.token != "":
		var me: Dictionary = await Api.request("GET", "/api/me")
		if me["ok"]:
			_show_me(me["data"])
			return
		if me["status"] != 401:
			_fail("Ошибка: " + str(me["message"]))
			return
		Api.clear_token()

	_show_choice()


func _https_url(url: String) -> bool:
	if not url.begins_with("https://") or url.length() > 2000:
		return false
	for i in url.length():
		if url.unicode_at(i) <= 32:
			return false
	return true


## Обязательное обновление: экран до входа, без кнопки «позже». Ссылка только https.
func _offer_update(data: Dictionary) -> bool:
	var upd = data.get("update", null)
	if typeof(upd) != TYPE_DICTIONARY:
		return false
	if int(upd.get("versionCode", 0)) <= VERSION_CODE:
		return false
	var url := str(upd.get("url", ""))
	if not _https_url(url):
		return false
	_show_update(upd, url)
	return true


func _show_update(upd: Dictionary, url: String) -> void:
	_clear_form()
	_btn_retry.visible = false
	_status.text = "Нужно обновление"
	var name := str(upd.get("versionName", "")).replace("\n", " ")
	if name.length() > 40:
		name = name.substr(0, 40)
	if name == "":
		name = "новой версии"
	_info.text = "Вышла версия %s. Эта сборка устарела: пока не поставите новую, войти нельзя." % name
	var size := int(upd.get("size", 0))
	if size >= 1048576:
		_info.text += "\nРазмер около %d МБ." % int(round(float(size) / 1048576.0))
	elif size > 0:
		_info.text += "\nРазмер около %d КБ." % int(round(float(size) / 1024.0))
	var go := Ui.button("Скачать обновление", 32, 110)
	go.pressed.connect(func():
		if _https_url(url):
			OS.shell_open(url))
	_form.add_child(go)
	var again := Ui.button("Проверить снова", 26, 84)
	again.pressed.connect(_start)
	_form.add_child(again)


## Первый запуск на устройстве: играть сразу гостем или войти в существующий аккаунт.
func _show_choice() -> void:
	_clear_form()
	_status.text = "Добро пожаловать!"
	var g := Ui.button("Начать игру", 34, 110)
	g.pressed.connect(_guest)
	_form.add_child(g)
	var l := Ui.button("У меня уже есть аккаунт", 30, 100)
	l.pressed.connect(_show_login)
	_form.add_child(l)


func _guest() -> void:
	_clear_form()
	_status.text = "Создаём гостевой аккаунт…"
	var g: Dictionary = await Api.request("POST", "/api/guest", {})
	if not g["ok"]:
		_fail("Не удалось войти.\n" + str(g["message"]))
		return
	State.clear_flags()
	await _enter_with_token(str(g["data"]["token"]))


func _enter_with_token(token: String) -> void:
	Api.save_token(token)
	var me: Dictionary = await Api.request("GET", "/api/me")
	if not me["ok"]:
		_fail("Ошибка: " + str(me["message"]))
		return
	_show_me(me["data"])


func _show_login() -> void:
	_clear_form()
	_status.text = "Вход в аккаунт"
	var login := Ui.line_edit("Логин")
	var pw := Ui.line_edit("Пароль", true)
	_form.add_child(login)
	_form.add_child(pw)
	var err := Ui.label("", 26, Color(1, 0.5, 0.5))
	_form.add_child(err)
	var go := Ui.button("Войти", 34, 100)
	go.pressed.connect(func():
		go.disabled = true
		var r: Dictionary = await Api.request("POST", "/api/login", {"login": login.text, "password": pw.text})
		if not r["ok"]:
			err.text = str(r["message"])
			go.disabled = false
			return
		State.clear_flags()
		_clear_form()
		await _enter_with_token(str(r["data"]["token"])))
	_form.add_child(go)
	var forgot := Ui.button("Забыл пароль (нужен резервный код)", 26, 84)
	forgot.pressed.connect(_show_recover)
	_form.add_child(forgot)
	var back := Ui.button("Назад", 26, 84)
	back.pressed.connect(_show_choice)
	_form.add_child(back)


func _show_recover() -> void:
	_clear_form()
	_status.text = "Восстановление доступа"
	var login := Ui.line_edit("Логин")
	var code := Ui.line_edit("Резервный код (XXXXX-XXXXX-…)")
	var pw := Ui.line_edit("Новый пароль (не короче 8 символов)", true)
	_form.add_child(login)
	_form.add_child(code)
	_form.add_child(pw)
	var err := Ui.label("", 26, Color(1, 0.5, 0.5))
	_form.add_child(err)
	var go := Ui.button("Восстановить", 34, 100)
	go.pressed.connect(func():
		go.disabled = true
		var r: Dictionary = await Api.request("POST", "/api/recover", {"login": login.text, "code": code.text, "newPassword": pw.text})
		if not r["ok"]:
			err.text = str(r["message"])
			go.disabled = false
			return
		State.clear_flags()
		var token := str(r["data"]["token"])
		_clear_form()
		# старый код сгорел, выдан новый — показываем его один раз
		Ui.recovery_code_dialog(self, str(r["data"]["recoveryCode"]), func(): _enter_with_token(token)))
	_form.add_child(go)
	var back := Ui.button("Назад", 26, 84)
	back.pressed.connect(_show_login)
	_form.add_child(back)


func _show_me(me: Dictionary) -> void:
	State.me = me
	_status.text = "Загружаем данные…"
	if not await State.load_content():
		_fail("Не удалось загрузить данные игры.")
		return
	Media.set_manifest(State.content.get("media", {}))
	if not await _sync_media():
		return
	print("[boot] OK me: account=", me["account"]["id"], " heroes=", (me["heroes"] as Array).size(), " cleared=", me["clearedStages"])
	get_tree().change_scene_to_file.call_deferred("res://hub.tscn")


## Докачка моделей, которых нет в приложении (заменённых или новых в админке). Крупную загрузку подтверждает игрок.
## Если не скачалось или игрок отказался, остаются вшитые модели, игра запускается.
func _sync_media() -> bool:
	var need := Media.missing()
	if need.is_empty():
		return true
	var mb := Media.missing_bytes() / 1048576.0
	if mb > 10.0:
		_clear_form()
		_status.text = "Нужно скачать новые ресурсы: %.0f МБ." % mb
		var go := Ui.button("Скачать", 32, 100)
		var skip := Ui.button("Позже (пока встроенные)", 28, 90)
		_form.add_child(go)
		_form.add_child(skip)
		var choice: String = await _wait_choice(go, skip)
		_clear_form()
		if choice == "skip":
			return true
	_status.text = "Скачиваем ресурсы…"
	await Media.download_missing(func(done: int, total: int): _status.text = "Скачиваем ресурсы… %d/%d" % [done, total])
	return true


func _wait_choice(a: Button, b: Button) -> String:
	var result := [""]
	a.pressed.connect(func(): result[0] = "go")
	b.pressed.connect(func(): result[0] = "skip")
	while result[0] == "":
		await get_tree().process_frame
	return result[0]
