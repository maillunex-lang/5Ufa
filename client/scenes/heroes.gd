extends Control
## Коллекция героев: уровни, вознесение, Кристалл резонанса, роспуск простых героев.
## Все изменения делает сервер; экран только показывает ответ.

const ROLE_NAMES := {"tank": "танк", "warrior": "воин", "archer": "стрелок", "mage": "маг",
		"support": "поддержка", "assassin": "убийца"}

const Inv := preload("res://scenes/inventory.gd")
const SLOT_ORDER := ["weapon", "armor", "helmet", "boots"]
const SLOT_NAMES := {"weapon": "Оружие", "armor": "Доспех", "helmet": "Шлем", "boots": "Сапоги"}

var data: Dictionary = {}
var selected_id := -1
var _picker: Control
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
	_root = ScreenLayout.screen(self, "heroes", {"back": _back})
	_root.add_theme_constant_override("separation", 10)
	if data.is_empty():
		_root.add_child(Ui.label(_message, 24))
		_root.add_child(Ui.button("Повторить", _load))
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
	if h.has("equipment"):
		box.add_child(_equipment_row(h))
		box.add_child(_signature_row(h))
	return panel


func _equipment_row(h: Dictionary) -> Control:
	var slots_row := HBoxContainer.new()
	slots_row.add_theme_constant_override("separation", 8)
	var eq: Dictionary = h["equipment"]
	for slot in SLOT_ORDER:
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 88)
		var style := StyleBoxFlat.new()
		style.bg_color = Ui.colors["primary"].darkened(0.3)
		style.set_corner_radius_all(12)
		style.set_border_width_all(4)
		if eq.has(slot):
			b.icon = Inv.item_icon(eq[slot])
			b.expand_icon = true
			style.border_color = Color(str(eq[slot]["quality_color"]))
		else:
			b.text = SLOT_NAMES[slot]
			b.clip_text = true
			style.border_color = Ui.colors["accent"].darkened(0.5)
		b.add_theme_font_size_override("font_size", 15)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, style)
		b.pressed.connect(_open_picker.bind(h, slot))
		if eq.has(slot):
			var lvl := Ui.label("+%d" % int(eq[slot]["level"]), 16)
			lvl.position = Vector2(4, 62)
			lvl.size = Vector2(80, 22)
			lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			b.add_child(lvl)
		slots_row.add_child(b)
	var id := int(h["id"])
	var best := Ui.button("Надеть\nлучшее", func(): _post("/api/v1/heroes/%d/auto-equip" % id))
	best.add_theme_font_size_override("font_size", 18)
	best.custom_minimum_size = Vector2(0, 88)
	best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_row.add_child(best)
	var off := Ui.button("Снять\nвсё", func(): _post("/api/v1/heroes/%d/unequip" % id, {}))
	off.add_theme_font_size_override("font_size", 18)
	off.custom_minimum_size = Vector2(0, 88)
	off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	off.disabled = eq.is_empty()
	slots_row.add_child(off)
	return slots_row


func _signature_row(h: Dictionary) -> Control:
	var sig: Dictionary = h["signature"]
	if not bool(sig["unlocked"]):
		return Ui.label("Уникальный предмет откроется на ступени «%s»" % sig["unlock_tier_name"], 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var txt := "Уникальный предмет: ур. %d / %d · характеристики +%s%%" % [int(sig["level"]), int(sig["max_level"]), str(sig["stat_percent"])]
	if float(sig["ult_percent"]) > 0:
		txt += " · ультимейт +%s%%" % str(sig["ult_percent"])
	elif sig["next_ult"] != null:
		txt += " · на ур. %d ультимейт +%s%%" % [int(sig["next_ult"]["level"]), str(sig["next_ult"]["percent"])]
	var l := Ui.label(txt, 18, "accent")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(l)
	if sig["cost"] != null:
		var id := int(h["id"])
		var up := Ui.button("Улучшить\n%s" % Ui.cost_text(sig["cost"]), func(): _post("/api/v1/heroes/%d/signature" % id))
		up.add_theme_font_size_override("font_size", 16)
		up.custom_minimum_size = Vector2(220, 80)
		up.clip_text = true
		row.add_child(up)
	return row


## Выбор предмета для слота: подходящие по типу предметы, лучшие сверху
func _open_picker(h: Dictionary, slot: String) -> void:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/inventory")
	if not res.ok:
		_message = res.error
		_render()
		return
	var items: Array = res.data["items"].filter(func(i): return i["slot"] == slot and i["kind"] == h.get("equipment_kind"))
	items.sort_custom(func(a, b): return int(a["power"]) > int(b["power"]))
	_close_picker()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_picker = dim
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 160)
	panel.size = Vector2(660, 960)
	dim.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(Ui.label("%s · %s" % [h["name"], SLOT_NAMES[slot]], 30, "accent"))
	if items.is_empty():
		col.add_child(Ui.label("Подходящих предметов нет. Их дают за этапы кампании и в AFK-сундуке.", 22))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var hid := int(h["id"])
	for i in items:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(Inv.item_card(i, false, func(): pass))
		var worn: Variant = i["worn_by"]
		var info := Ui.label("%s +%d · %s\n%s%s" % [i["name"], int(i["level"]), i["quality_name"], Inv.stats_text(i["stats"]),
				("\nсейчас у: %s" % worn["name"]) if worn is Dictionary else ""], 19)
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(info)
		var on_me: bool = worn is Dictionary and int(worn["id"]) == hid
		var put := Ui.button("Надет" if on_me else "Надеть", func():
			_close_picker()
			_post("/api/v1/heroes/%d/equip" % hid, {"item_id": int(i["id"])}))
		put.disabled = on_me
		put.add_theme_font_size_override("font_size", 20)
		put.custom_minimum_size = Vector2(140, 80)
		line.add_child(put)
		list.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	if h["equipment"].has(slot):
		var off := Ui.button("Снять", func():
			_close_picker()
			_post("/api/v1/heroes/%d/unequip" % hid, {"slot": slot}))
		off.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(off)
	var close := Ui.button("Закрыть", _close_picker)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(close)
	col.add_child(row)


func _close_picker() -> void:
	if is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


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
	await _post("/api/v1/heroes/%d/auto-equip" % int(first["id"]))
	var equipped := 0
	for h in data["heroes"]:
		if int(h["id"]) == int(first["id"]):
			equipped = h.get("equipment", {}).size()
	var summary := {"ok": before >= 5 and res.ok and data["heroes"].size() == before + 10 and equipped == 4,
			"equipped": equipped,
			"heroes_before": before, "heroes_after": data["heroes"].size(), "level_message": level_msg,
			"first_result": res.data["results"][0]["tier"] if res.ok else res.error}
	print("AUTOTEST HEROES: ", JSON.stringify(summary))
	if "--screenshot-after=" not in str(OS.get_cmdline_user_args()):
		get_tree().quit(0 if summary["ok"] else 1)
