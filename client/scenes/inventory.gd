extends Control
## Инвентарь снаряжения: фильтры по слоту и редкости, улучшение рудой, разбор.
## Все изменения делает сервер; экран только показывает ответ.

const STAT_NAMES := {"hp": "здоровье", "atk": "атака", "def": "защита"}

var data: Dictionary = {}
var selected_id := -1
var slot_filter := ""
var quality_filter := ""
var _message := ""
var _busy := false
var _root: VBoxContainer
var _faction_names: Dictionary = {}


func _ready() -> void:
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	var f: Variant = Content.load_json("factions/factions.json")
	if f is Dictionary:
		for x in f.get("factions", []):
			_faction_names[x["id"]] = x["name"]
	await _load()
	if Config.autotest and "--autotest-inventory" in OS.get_cmdline_user_args():
		await _autotest()


static func item_icon(item: Dictionary) -> Texture2D:
	var slot := str(item["slot"])
	var path := "ui/items/weapon_%s.png" % item["kind"] if slot == "weapon" else "ui/items/%s.png" % slot
	return Content.load_texture(path)


static func stats_text(stats: Dictionary) -> String:
	var parts: Array = []
	for k in ["hp", "atk", "def"]:
		if stats.has(k):
			parts.append("%s +%d" % [STAT_NAMES[k], int(stats[k])])
	return ", ".join(parts)


func _load() -> void:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/inventory")
	if res.ok:
		data = res.data
	else:
		_message = res.error
	_render()


func _post(path: String, body: Dictionary) -> void:
	if _busy:
		return
	_busy = true
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, path, body)
	_busy = false
	if res.ok:
		data = res.data
		_message = str(res.data.get("message", ""))
	else:
		_message = res.error
	_render()


func _visible_items() -> Array:
	return data.get("items", []).filter(func(i):
		return (slot_filter == "" or i["slot"] == slot_filter) and (quality_filter == "" or i["quality"] == quality_filter))


func _render() -> void:
	if is_instance_valid(_root):
		_root.get_parent().queue_free()
	_root = Ui.screen(self)
	var margin: MarginContainer = _root.get_parent()
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_theme_constant_override("separation", 10)
	_root.add_child(Ui.label("Инвентарь", 40, "accent"))
	if data.is_empty():
		_root.add_child(Ui.label(_message, 24))
		_root.add_child(Ui.button("Повторить", _load))
		_root.add_child(Ui.button("На главный экран", _back))
		return
	var w: Dictionary = data["wallet"]
	_root.add_child(Ui.label("Золото: %d · Руда: %d · Осколки наследия: %d\nПредметов: %d из %d" % [
			int(w.get("gold", 0)), int(w.get("ore", 0)), int(w.get("legacy_shards", 0)),
			data["items"].size(), int(data["limit"])], 20))
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	filters.add_child(_filter_box(data["slots"], "Все слоты", slot_filter, func(v): slot_filter = v))
	filters.add_child(_filter_box(data["qualities"], "Любая редкость", quality_filter, func(v): quality_filter = v))
	_root.add_child(filters)

	var items := _visible_items()
	var sel: Dictionary = {}
	for i in data["items"]:
		if int(i["id"]) == selected_id:
			sel = i
	if sel.is_empty() and not items.is_empty():
		sel = items[0]
		selected_id = int(sel["id"])
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
	for i in items:
		grid.add_child(item_card(i, int(i["id"]) == selected_id, func():
			selected_id = int(i["id"])
			_message = ""
			_render()))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var free_common: Array = data["items"].filter(func(i): return i["quality"] == "common" and i["worn_by"] == null)
	var bulk := Ui.button("Разобрать обычные (%d)" % free_common.size(), func():
		_post("/api/v1/items/dismantle", {"ids": free_common.slice(0, 100).map(func(i): return int(i["id"]))}))
	bulk.disabled = free_common.is_empty()
	bulk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bulk.add_theme_font_size_override("font_size", 22)
	bulk.clip_text = true
	row.add_child(bulk)
	var back := Ui.button("На главный экран", _back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.add_theme_font_size_override("font_size", 22)
	back.clip_text = true
	row.add_child(back)
	_root.add_child(row)


func _filter_box(options: Array, all_text: String, current: String, apply: Callable) -> OptionButton:
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 64)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.clip_text = true
	pick.add_theme_font_size_override("font_size", 24)
	pick.add_item(all_text)
	var ids: Array = [""]
	for o in options:
		pick.add_item(str(o["name"]))
		ids.append(str(o["id"]))
	pick.selected = max(0, ids.find(current))
	pick.item_selected.connect(func(idx):
		apply.call(ids[idx])
		selected_id = -1
		_render())
	return pick


## Карточка предмета: иконка, рамка цвета редкости, уровень улучшения, ◆ — надет
static func item_card(i: Dictionary, selected: bool, on_press: Callable) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var b := Button.new()
	b.custom_minimum_size = Vector2(112, 112)
	b.icon = item_icon(i)
	b.expand_icon = true
	var style := StyleBoxFlat.new()
	style.bg_color = Ui.colors["primary"]
	style.border_color = Color(str(i["quality_color"]))
	style.set_border_width_all(7 if selected else 4)
	style.set_corner_radius_all(14)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, style)
	b.pressed.connect(on_press)
	box.add_child(b)
	var lab := Ui.label("+%d%s" % [int(i["level"]), " ◆" if i["worn_by"] != null else ""], 18)
	lab.add_theme_color_override("font_color", Color(str(i["quality_color"])))
	box.add_child(lab)
	return box


func _detail(i: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = item_icon(i)
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var faction := str(_faction_names.get(i["faction"], "")) if i["faction"] != null else ""
	var worn: Variant = i["worn_by"]
	var info := Ui.label("%s +%d\n%s · %s · %s\n%s%s%s" % [
			i["name"], int(i["level"]), i["quality_name"], i["slot_name"], i["kind_name"], stats_text(i["stats"]),
			("\nФракция: %s (+15%% герою этой фракции)" % faction) if faction != "" else "",
			("\nНадет: %s" % worn["name"]) if worn is Dictionary else ""], 20)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_color_override("font_color", Color(str(i["quality_color"])).lerp(Color.WHITE, 0.5))
	head.add_child(info)
	box.add_child(head)
	var id := int(i["id"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if i["upgrade_cost"] != null:
		var up := Ui.button("Улучшить +1\n%s" % Ui.cost_text(i["upgrade_cost"]), func(): _post("/api/v1/items/%d/upgrade" % id, {"times": 1}))
		up.add_theme_font_size_override("font_size", 19)
		up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up.clip_text = true
		row.add_child(up)
		var five := Ui.button("+5", func(): _post("/api/v1/items/%d/upgrade" % id, {"times": 5}))
		five.custom_minimum_size = Vector2(80, 96)
		row.add_child(five)
	else:
		row.add_child(Ui.label("Улучшен до предела", 20))
	var dis := Ui.button("Разобрать\n+%d руды" % int(i["dismantle_ore"]), func():
		selected_id = -1
		_post("/api/v1/items/dismantle", {"ids": [id]}))
	dis.add_theme_font_size_override("font_size", 19)
	dis.custom_minimum_size = Vector2(150, 96)
	dis.clip_text = true
	dis.disabled = worn is Dictionary
	row.add_child(dis)
	box.add_child(row)
	return panel


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _autotest() -> void:
	var before: int = data.get("items", []).size()
	var first: Dictionary = data["items"][0]
	await _post("/api/v1/items/%d/upgrade" % int(first["id"]), {"times": 1})
	var up_msg := _message
	var ore_before := int(data["wallet"].get("ore", 0))
	var free: Array = data["items"].filter(func(i): return i["worn_by"] == null)
	await _post("/api/v1/items/dismantle", {"ids": [int(free[0]["id"])]})
	var summary := {"ok": before >= 12 and data["items"].size() == before - 1 and int(data["wallet"].get("ore", 0)) > ore_before,
			"items_before": before, "items_after": data["items"].size(), "upgrade_message": up_msg,
			"ore": int(data["wallet"].get("ore", 0))}
	print("AUTOTEST INVENTORY: ", JSON.stringify(summary))
	if "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
		get_tree().quit(0 if summary["ok"] else 1)
