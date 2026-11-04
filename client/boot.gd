extends Control
## C-1: загрузчик и вход. Проверка /api/config, гостевой вход, /api/me, пробный бой этапа.
## Отображение боя, город и остальные экраны — задачи C-2…C-4 (docs/ROADMAP.md).

const MAX_STAGE := 10

var _status: Label
var _info: Label
var _btn_battle: Button
var _btn_retry: Button
var _me: Dictionary = {}


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

	_btn_battle = Button.new()
	_btn_battle.custom_minimum_size = Vector2(0, 110)
	_btn_battle.add_theme_font_size_override("font_size", 34)
	_btn_battle.visible = false
	_btn_battle.pressed.connect(_on_battle)
	box.add_child(_btn_battle)

	_btn_retry = Button.new()
	_btn_retry.text = "Повторить"
	_btn_retry.custom_minimum_size = Vector2(0, 110)
	_btn_retry.add_theme_font_size_override("font_size", 34)
	_btn_retry.visible = false
	_btn_retry.pressed.connect(_start)
	box.add_child(_btn_retry)


func _fail(text: String) -> void:
	_status.text = text
	_btn_retry.visible = true


func _start() -> void:
	_btn_retry.visible = false
	_btn_battle.visible = false
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


func _next_stage() -> int:
	var cleared: Array = _me.get("clearedStages", [])
	var best := 0
	for s in cleared:
		best = maxi(best, int(s))
	return mini(best + 1, MAX_STAGE)


func _show_me(me: Dictionary) -> void:
	_me = me
	var acc: Dictionary = me["account"]
	var bal: Dictionary = me["balances"]
	_status.text = "Вход выполнен"
	_info.text = "Аккаунт №%d (%s)\nГероев: %d\nЗолото: %d   Опыт героев: %d\nПройдено этапов: %d" % [
		int(acc["id"]),
		"привязан" if acc["bound"] else "гость",
		(me["heroes"] as Array).size(),
		int(bal.get("gold", 0)),
		int(bal.get("hero_exp", 0)),
		(me["clearedStages"] as Array).size(),
	]
	_btn_battle.text = "Пробный бой: этап %d" % _next_stage()
	_btn_battle.disabled = false
	_btn_battle.visible = true


func _on_battle() -> void:
	_btn_battle.disabled = true
	_status.text = "Бой идёт на сервере…"
	var stage := _next_stage()
	var r: Dictionary = await Api.request("POST", "/api/battle/start", {"stage": stage})
	if not r["ok"]:
		_status.text = "Бой не начался: " + str(r["message"])
		_btn_battle.disabled = false
		return
	var d: Dictionary = r["data"]
	var won: bool = d["winner"] == "attacker"
	var text := "%s, этап %d, %.1f с" % ["Победа" if won else "Поражение", stage, float(d["duration"])]
	if d.get("timeout", false):
		text += " (время вышло)"
	if d["reward"] != null:
		text += "\nНаграда: золото %d, опыт %d" % [int(d["reward"].get("gold", 0)), int(d["reward"].get("hero_exp", 0))]
	text += "\n(анимация боя — следующий этап разработки)"
	var me: Dictionary = await Api.request("GET", "/api/me")
	if me["ok"]:
		_show_me(me["data"])
	_status.text = text
