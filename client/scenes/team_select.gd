extends Control
## Выбор отряда для тестового боя: 5 из 15 героев, расстановка 2 спереди + 3 сзади, противник.

const ROLE_NAMES := {"tank": "танк", "warrior": "воин", "archer": "стрелок", "mage": "маг",
		"support": "поддержка", "assassin": "убийца"}
const TEAM_FILE := "user://team.cfg"

var heroes: Dictionary = {}       # id -> hero.json
var factions: Dictionary = {}
var slots: Array = [null, null, null, null, null]   # id героя в слоте 0..4
var teams: Array = []
var _slot_buttons: Array = []
var _info: Label
var _enemy: OptionButton
var _status: Label
var _fight: Button
var _hero_buttons: Dictionary = {}
var _auto_start: CheckButton


func _ready() -> void:
	var settings: Variant = Content.load_json("config/game_settings.json")
	Ui.apply_settings(settings)
	var col := Ui.screen(self)
	col.add_theme_constant_override("separation", 10)
	var margin: MarginContainer = col.get_parent()
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	_load_data()
	col.add_child(Ui.label("Тестовый бой", 40, "accent"))
	col.add_child(Ui.label("Выберите до 5 героев. Нажмите на место в отряде, чтобы убрать.", 20))

	col.add_child(_row_title("Передний ряд"))
	col.add_child(_slot_row([0, 1]))
	col.add_child(_row_title("Задний ряд"))
	col.add_child(_slot_row([2, 3, 4]))

	_info = Ui.label("Нажмите на героя, чтобы добавить его в отряд", 20)
	_info.custom_minimum_size = Vector2(0, 64)
	col.add_child(_info)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	var ids := heroes.keys()
	ids.sort_custom(func(a, b): return [heroes[a]["faction"], heroes[a]["name"]] < [heroes[b]["faction"], heroes[b]["name"]])
	for hid in ids:
		var b := _portrait_button(hid, 110)
		b.pressed.connect(_on_hero.bind(hid))
		grid.add_child(b)
		_hero_buttons[hid] = b

	var enemy_row := HBoxContainer.new()
	var enemy_label := Ui.label("Противник:", 26)
	enemy_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	enemy_row.add_child(enemy_label)
	_enemy = OptionButton.new()
	_enemy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy.custom_minimum_size = Vector2(0, 72)
	enemy_row.add_child(_enemy)
	col.add_child(enemy_row)
	_auto_start = CheckButton.new()
	_auto_start.text = "Авто с начала боя"
	_auto_start.button_pressed = true
	col.add_child(_auto_start)
	_status = Ui.label("", 22)
	col.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	var back := Ui.button("Назад", func(): get_tree().change_scene_to_file("res://scenes/main.tscn"))
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(back)
	_fight = Ui.button("В бой!", _start_battle)
	_fight.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(_fight)
	col.add_child(buttons)

	_load_team()
	_refresh()
	_load_enemies()


func _load_data() -> void:
	var f: Variant = Content.load_json("factions/factions.json")
	if f is Dictionary:
		for x in f["factions"]:
			factions[x["id"]] = x
	for rel in Content.state["files"].keys():
		if str(rel).begins_with("heroes/") and str(rel).ends_with("/hero.json"):
			var h: Variant = Content.load_json(rel)
			if h is Dictionary:
				heroes[h["id"]] = h


func _row_title(text: String) -> Label:
	var l := Ui.label(text, 22, "accent")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _slot_row(idx: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for i in idx:
		var b := Button.new()
		b.custom_minimum_size = Vector2(108, 108)
		b.expand_icon = true
		b.pressed.connect(_on_slot.bind(i))
		row.add_child(b)
		while _slot_buttons.size() <= i:
			_slot_buttons.append(null)
		_slot_buttons[i] = b
	return row


func _portrait_button(hid: String, size: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size, size)
	b.icon = Content.load_texture(str(heroes[hid]["art"]["portrait"]))
	b.expand_icon = true
	b.tooltip_text = heroes[hid]["name"]
	return b


func _on_hero(hid: String) -> void:
	var h: Dictionary = heroes[hid]
	var ult: Dictionary = {}
	for s in h["skills"]:
		if s["type"] == "ultimate":
			ult = s
	_info.text = "%s — %s, %s\nУльт «%s»: %s" % [h["name"], ROLE_NAMES.get(h["role"], h["role"]),
			factions.get(h["faction"], {}).get("name", h["faction"]), ult.get("name", ""), ult.get("description", "")]
	if hid in slots:
		return
	# Танки и воины — вперёд, остальные — назад, если там есть место
	var prefer_front := str(h["role"]) in ["tank", "warrior"]
	var order := [0, 1, 2, 3, 4] if prefer_front else [2, 3, 4, 0, 1]
	for i in order:
		if slots[i] == null:
			slots[i] = hid
			break
	_refresh()


func _on_slot(i: int) -> void:
	slots[i] = null
	_refresh()


func _refresh() -> void:
	for i in range(5):
		var b: Button = _slot_buttons[i]
		var hid: Variant = slots[i]
		b.icon = Content.load_texture(str(heroes[hid]["art"]["portrait"])) if hid != null else null
		b.text = "" if hid != null else "+"
	for hid in _hero_buttons:
		_hero_buttons[hid].modulate = Color(0.45, 0.45, 0.45) if hid in slots else Color.WHITE
	_fight.disabled = _team().is_empty()


func _team() -> Array:
	var out := []
	for i in range(5):
		if slots[i] != null:
			out.append({"hero": slots[i], "slot": i})
	return out


func _load_team() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(TEAM_FILE) == OK:
		var saved: Array = cfg.get_value("team", "slots", [])
		for i in range(min(5, saved.size())):
			if saved[i] != null and heroes.has(saved[i]):
				slots[i] = saved[i]
	if _team().is_empty():
		slots = ["alpamysha", "ural_batyr", "zayatulyak", "humai", "hyuhylu"]
		for i in range(5):
			if not heroes.has(slots[i]):
				slots[i] = null


func _save_team() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("team", "slots", slots)
	cfg.save(TEAM_FILE)


func _load_enemies() -> void:
	_status.text = "Загрузка отрядов противника…"
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/battle/test-teams")
	if not res.ok:
		_status.text = res.error
		return
	teams = res.data.get("teams", [])
	for t in teams:
		_enemy.add_item(str(t["name"]))
	_status.text = ""


func _start_battle() -> void:
	if teams.is_empty():
		_status.text = "Нет отрядов противника"
		return
	_fight.disabled = true
	_status.text = "Бой…"
	_save_team()
	var enemy: Dictionary = teams[max(0, _enemy.selected)]
	if not _auto_start.button_pressed:
		if not await Api.refresh():
			_status.text = "Не удалось обновить сессию. Проверьте связь и попробуйте снова."
			_fight.disabled = false
			return
		get_tree().set_meta("battle_live", {"team": _team(), "enemy": enemy["id"]})
		get_tree().set_meta("battle_enemy_name", enemy["name"])
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
		return
	get_tree().remove_meta("battle_live")
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, "/api/v1/battle/test",
			{"team": _team(), "enemy": enemy["id"]})
	if not res.ok:
		_status.text = res.error
		_fight.disabled = false
		return
	get_tree().set_meta("battle_log", res.data["log"])
	get_tree().set_meta("battle_enemy_name", enemy["name"])
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
