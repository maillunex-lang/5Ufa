extends Control
## Кампания и AFK-сундук; все начисления подтверждает сервер.

var data: Dictionary = {}
var _column: VBoxContainer
var _message: String = ""
var _busy := false

func _ready() -> void:
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	await _load()
	if Config.autotest:
		print("AUTOTEST CAMPAIGN: ", JSON.stringify({"ok": not data.is_empty(), "chapters": data.get("chapters", []).size()}))
		if not data.is_empty() and "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
			get_tree().quit(0)
		elif data.is_empty():
			get_tree().quit(1)

func _load() -> void:
	var response: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/campaign")
	if not response.ok:
		_message = response.error
	else:
		data = response.data
		AfkNotifications.update_status(data)
	_render()

func _render() -> void:
	if is_instance_valid(_column):
		_column.get_parent().queue_free()
	_column = Ui.screen(self)
	_column.add_child(Ui.label("Кампания", 40, "accent"))
	if data.is_empty():
		_column.add_child(Ui.label(_message, 24))
		_column.add_child(Ui.button("Повторить", _load))
		_column.add_child(Ui.button("Назад", _back))
		return
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	var cleared: int = int(data["cleared"])
	body.add_child(Ui.label("Пройдено этапов: %d / 25" % cleared, 25))
	var map := TextureRect.new()
	map.texture = Content.load_texture("campaign/chapter_1/map.png")
	map.custom_minimum_size = Vector2(0, 330)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(map)
	body.add_child(Ui.label("Данные границы: © OpenStreetMap · openstreetmap.org/copyright", 16))
	for chapter in data["chapters"]:
		var number: int = int(chapter["number"])
		var unlocked: bool = cleared >= (number - 1) * 5
		var title: String = "%d. %s%s" % [number, chapter["title"], "" if unlocked else " — закрыто"]
		body.add_child(Ui.label(title, 27, "accent"))
		if unlocked:
			var passed: int = clampi(cleared - (number - 1) * 5, 0, 5)
			body.add_child(Ui.label("%s · пройдено %d / 5" % [chapter["subtitle"], passed], 21))
			if passed < 5 and cleared < 25:
				if passed == 0:
					body.add_child(Ui.label(str(chapter["dialogue_start"]), 21))
				if passed == 4:
					body.add_child(Ui.label(str(chapter["dialogue_end"]), 21))
				var button := Ui.button("Этап %d-%d — в бой" % [number, passed + 1], _fight.bind(cleared + 1))
				body.add_child(button)
	if cleared > 0:
		var replay := OptionButton.new()
		replay.custom_minimum_size = Vector2(0, 64)
		for index in range(cleared):
			replay.add_item("Этап %d-%d" % [int(index / 5) + 1, index % 5 + 1])
		body.add_child(replay)
		body.add_child(Ui.button("Повторить выбранный этап", func(): _fight(replay.selected + 1)))
	var chest: Dictionary = data["pending"]
	body.add_child(Ui.label("AFK-сундук: %d / 12 ч\nЗолото: %d · Опыт: %d · Кристаллы: %d · Эссенция: %d\nРуда: %d · Предметы: %d" % [
			int(data["elapsed_seconds"]) / 3600, int(chest["gold"]), int(chest["hero_xp"]),
			int(chest.get("crystals", 0)), int(chest.get("essence", 0)), int(chest.get("ore", 0)),
			int(chest.get("equipment", 0))], 24, "accent"))
	body.add_child(Ui.label("Всего: " + Ui.wallet_text(data.get("wallet", {})), 20))
	body.add_child(Ui.button("Получить из сундука", _claim.bind("/api/v1/campaign/claim")))
	var fast := Ui.button("Быстрая награда — 2 часа", _claim.bind("/api/v1/campaign/quick"))
	fast.disabled = not bool(data["quick_available"])
	body.add_child(fast)
	if OS.get_name() == "Android" and not AfkNotifications.permission_enabled():
		body.add_child(Ui.button("Включить уведомления", AfkNotifications.request_permission))
	if _message != "":
		body.add_child(Ui.label(_message, 23))
	_column.add_child(Ui.button("На главный экран", _back))

func _claim(path: String) -> void:
	if _busy:
		return
	_busy = true
	var response: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, path, {})
	_busy = false
	if response.ok:
		var reward: Dictionary = response.data["reward"]
		_message = "Получено: " + Ui.cost_text(reward.duplicate()) + _items_text(response.data.get("items", []))
	else:
		_message = response.error
	await _load()

static func _items_text(items: Array) -> String:
	if items.is_empty():
		return ""
	return "\nПредметы: " + ", ".join(items.map(func(i): return "%s (%s)" % [i["name"], i["quality_name"]]))


func _fight(stage: int) -> void:
	get_tree().set_meta("campaign_stage", stage)
	get_tree().change_scene_to_file("res://scenes/team_select.tscn")

func _back() -> void:
	get_tree().remove_meta("campaign_stage")
	get_tree().change_scene_to_file("res://scenes/main.tscn")
