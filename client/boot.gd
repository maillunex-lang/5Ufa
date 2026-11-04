extends Control
## Загрузчик и вход: /api/config (техработы), гостевой вход, /api/me, контент -> главный экран (hub.tscn).

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
	print("[boot] OK me: account=", me["account"]["id"], " heroes=", (me["heroes"] as Array).size(), " cleared=", me["clearedStages"])
	get_tree().change_scene_to_file.call_deferred("res://hub.tscn")
