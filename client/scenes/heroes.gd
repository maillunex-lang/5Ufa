extends Control
## Коллекция героев: уровни, вознесение, Кристалл резонанса, роспуск простых героев.
## Все изменения делает сервер; экран только показывает ответ.

const ROLE_NAMES := {"tank": "танк", "warrior": "воин", "archer": "стрелок", "mage": "маг",
		"support": "поддержка", "assassin": "убийца"}

var data: Dictionary = {}
var selected_id := -1
var _message := ""
var _busy := false
var _root: VBoxContainer


func _ready() -> void:
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	await _load()
	if Config.autotest and "--autotest-heroes" in OS.get_cmdline_user_args():
		await _autotest()


func _load() -> void:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/heroes")
	if res.ok:
		data = res.data
	else:
		_message = res.error
	_render()


func _apply(res: Dictionary) -> void:
	if res.ok:
		data = res.data
		_message = str(res.data.get("message", ""))
	else:
		_message = res.error
	_render()


func _post(path: String, body: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, path, body)
	_busy = false
	_apply(res)


func _render() -> void:
	if is_instance_valid(_root):
		_root.get_parent().queue_free()
	_root = Ui.screen(self)
	var margin: MarginContainer = _root.get_parent()
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_theme_constant_override("separation", 10)
	_root.add_child(Ui.label("Герои", 40, "accent"))
	if data.is_empty():
		_root.add_child(Ui.label(_message, 24))
		_root.add_child(Ui.button("Повторить", _load))
		_root.add_child(Ui.button("На главный экран", _back))
		return
	_root.add_child(Ui.label(Ui.wallet_text(data["wallet"]), 20))
	var cr: Dictionary = data["crystal"]
	var crystal_text := "Кристалл резонанса: " + (("уровень %d · мест занято %d / %d" % [int(cr["level"]), int(cr["used"]), int(cr["slots"])])
			if cr["level"] != null else "заработает, когда у вас будет больше %d героев" % int(cr["top"]))
	_root.add_child(Ui.label(crystal_text, 20, "accent"))

	var heroes: Array = data["heroes"]
	if selected_id < 0 and not heroes.is_empty():
		selected_id = int(heroes[0]["id"])
	var sel: Dictionary = {}
	for h in heroes:
		if int(h["id"]) == selected_id:
			sel = h
	if not sel.is_empty():
		_root.add_child(_detail(sel))
	if _message != "":
		_root.add_child(Ui.label(_message, 22))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for h in heroes:
		grid.add_child(_card(h))
	_root.add_child(Ui.button("На главный экран", _back))


func _card(h: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 112)
	b.icon = Content.load_texture("heroes/%s/portrait.png" % h["hero"])
	b.expand_icon = true
	var style := StyleBoxFlat.new()
	style.bg_color = Ui.colors["primary"]
	style.border_color = Color(str(h["tier_color"]))
	style.set_border_width_all(6 if int(h["id"]) == selected_id else 4)
	style.set_corner_radius_all(14)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, style)
	b.pressed.connect(func():
		selected_id = int(h["id"])
		_message = ""
		_render())
	box.add_child(b)
	var lab := Ui.label("ур. %d%s" % [int(h["level"]), " ◆" if h["crystal_slot"] != null else ""], 18)
	lab.add_theme_color_override("font_color", Color(str(h["tier_color"])))
	box.add_child(lab)
	return box


func _detail(h: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = Content.load_texture("heroes/%s/portrait.png" % h["hero"])
	icon.custom_minimum_size = Vector2(110, 110)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var info := Ui.label("%s\n%s · %s\nУровень %d / %d%s\nЗдоровье %d · Атака %d · Защита %d" % [
			h["name"], h["tier_name"], ROLE_NAMES.get(h["role"], h["role"]), int(h["level"]), int(h["level_cap"]),
			"  (в кристалле)" if h["crystal_slot"] != null else "",
			int(h["stats"]["hp"]), int(h["stats"]["atk"]), int(h["stats"]["def"])], 21)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	box.add_child(head)
	var id := int(h["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if h["level_cost"] != null:
		var up := Ui.button("Уровень +1\n%s" % Ui.cost_text(h["level_cost"]), func(): _post("/api/v1/heroes/%d/level-up" % id, {"times": 1}))
		up.add_theme_font_size_override("font_size", 20)
		up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(up)
		var up10 := Ui.button("+10", func(): _post("/api/v1/heroes/%d/level-up" % id, {"times": 10}))
		row.add_child(up10)
	box.add_child(row)
	if h["next_tier"] != null:
		var asc := Ui.button("Вознести → %s" % h["next_tier_name"], func(): _post("/api/v1/heroes/%d/ascend" % id))
		box.add_child(asc)
		box.add_child(Ui.label("Нужно: " + "; ".join(h["ascension_requires"]), 18))
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	var cr := Ui.button("Из кристалла" if h["crystal_slot"] != null else "В кристалл",
			func(): _post("/api/v1/heroes/%d/crystal" % id, {"put": h["crystal_slot"] == null}))
	cr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(cr)
	if int(h["dismiss_essence"]) > 0:
		var dis := Ui.button("Распустить (+%d эссенции)" % int(h["dismiss_essence"]), func():
			selected_id = -1
			_post("/api/v1/heroes/%d/dismiss" % id))
		dis.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(dis)
	box.add_child(row2)
	return panel


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _autotest() -> void:
	var before: int = data["heroes"].size()
	var first: Dictionary = data["heroes"][0]
	# Без золота — понятная ошибка, а не падение
	await _post("/api/v1/heroes/%d/level-up" % int(first["id"]), {"times": 1})
	var level_msg := _message
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, "/api/v1/summon", {"banner": "normal", "count": 10})
	await _load()
	var summary := {"ok": before >= 5 and res.ok and data["heroes"].size() == before + 10,
			"heroes_before": before, "heroes_after": data["heroes"].size(), "level_message": level_msg,
			"first_result": res.data["results"][0]["tier"] if res.ok else res.error}
	print("AUTOTEST HEROES: ", JSON.stringify(summary))
	if "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
		get_tree().quit(0 if summary["ok"] else 1)
