extends Control
## Загрузчик и вход: /api/config (техработы), гостевой вход, /api/me, контент -> главный экран (hub.tscn).

var _status: Label
var _info: Label
var _btn_retry: Button


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


func _fail(text: String) -> void:
	print("[boot] FAIL: ", text.replace("\n", " | "))
	_status.text = text
	print("[boot] BATTLE: ", text.replace("\n", " | "))
	_btn_retry.visible = true


func _start() -> void:
	_btn_retry.visible = false
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

	_status.text = "Создаём гостевой аккаунт…"
	var g: Dictionary = await Api.request("POST", "/api/guest", {})
	if not g["ok"]:
		_fail("Не удалось войти.\n" + str(g["message"]))
		return
	Api.save_token(str(g["data"]["token"]))
	var me2: Dictionary = await Api.request("GET", "/api/me")
	if not me2["ok"]:
		_fail("Ошибка: " + str(me2["message"]))
		return
	_show_me(me2["data"])


func _show_me(me: Dictionary) -> void:
	State.me = me
	_status.text = "Загружаем данные…"
	if not await State.load_content():
		_fail("Не удалось загрузить данные игры.")
		return
	print("[boot] OK me: account=", me["account"]["id"], " heroes=", (me["heroes"] as Array).size(), " cleared=", me["clearedStages"])
	get_tree().change_scene_to_file.call_deferred("res://hub.tscn")
