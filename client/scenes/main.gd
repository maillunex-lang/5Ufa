extends Control
## Главный экран «Город»: карта-город со зданиями, верхняя панель (профиль, валюты, почта, настройки),
## боковые действия слева и нижняя навигация. Расположение, подписи, картинки и действия — в контенте
## ui/hub.json (меняются без обновления APK). Аккаунт, проверка файлов и версия — в «Настройках».

const SCENES := ScreenLayout.SCENES
const OUTLINE := Color(0.06, 0.03, 0.1)

var hub: Dictionary = {}
var _player_label: Label
var _bg_label: Label
var _account_box: VBoxContainer
var _dialog: PanelContainer
var _dialog_error: Label
var _gold_label: Label
var _crystal_label: Label
var _power_label: Label
var _name_label: Label
var _stage_label: Label
var _stage_bar: ProgressBar
var _avatar: TextureRect
var _badges: Dictionary = {}     # вид точки -> красные точки
var _city_scroll: ScrollContainer


func _ready() -> void:
	var settings: Variant = Content.load_json("config/game_settings.json")
	Ui.apply_settings(settings)
	theme = Ui.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var loaded: Variant = Content.load_json("ui/hub.json")
	hub = loaded if loaded is Dictionary else {}
	_build_layout(settings)
	# Служебные элементы (видны в «Настройках»)
	_player_label = Ui.label("", 26)
	_bg_label = Ui.label("", 22)
	_account_box = VBoxContainer.new()
	_account_box.add_theme_constant_override("separation", 16)

	Api.player_changed.connect(func(_p): _refresh_account())
	Content.background_progress.connect(_on_bg_progress)
	Content.background_finished.connect(_on_bg_finished)
	_refresh_account()
	AfkNotifications.refresh()
	_refresh_resources()
	if get_tree().has_meta("notice"):
		_show_message(str(get_tree().get_meta("notice")))
		get_tree().remove_meta("notice")
	elif get_tree().has_meta("update_offer") and not Config.autotest:
		_offer_update(get_tree().get_meta("update_offer"))
		get_tree().remove_meta("update_offer")
	Content.sync_background()
	if Config.autotest:
		_autotest()


# --- Общие элементы оформления ---------------------------------------------------------

func _style(bg: Color, border: Color, width: int, radius: int, margin := 0) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(width)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(margin)
	return st


func _outlined(text: String, font_size: int, color_key := "text", outline := 6) -> Label:
	var l := Ui.label(text, font_size, color_key)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_color_override("font_outline_color", OUTLINE)
	l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _icon(path: String, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Content.load_texture(path)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## Табличка с подписью здания (тёмная, с золотой рамкой)
func _plate(text: String, font_size: int) -> PanelContainer:
	var p := PanelContainer.new()
	var st := _style(Color(0.1, 0.07, 0.16, 0.92), Ui.colors["accent"], 3, 20)
	st.content_margin_left = 22
	st.content_margin_right = 22
	st.content_margin_top = 4
	st.content_margin_bottom = 6
	p.add_theme_stylebox_override("panel", st)
	p.add_child(_outlined(text, font_size, "text", 4))
	return p


func _add_badge(kind: String, parent: Control, pos: Vector2) -> void:
	var dot := Label.new()
	dot.text = "!"
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dot.add_theme_font_size_override("font_size", 18)
	dot.add_theme_color_override("font_color", Color.WHITE)
	dot.add_theme_stylebox_override("normal", _style(Color("#E2504A"), Color.WHITE, 2, 14))
	dot.size = Vector2(28, 28)
	dot.position = pos
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.visible = false
	parent.add_child(dot)
	if not _badges.has(kind):
		_badges[kind] = []
	_badges[kind].append(dot)


func _set_badge(kind: String, on: bool) -> void:
	for dot in _badges.get(kind, []):
		dot.visible = on


# --- Город -------------------------------------------------------------------------------

## Раскладка экрана — ui/screens/hub.json (конструктор экранов в админке); город и здания — ui/hub.json
func _build_layout(settings: Variant) -> void:
	var widgets := {
		"city": func(box: Control, _el: Dictionary): _build_city(settings, box),
		"avatar": _w_avatar, "player_name": _w_name, "stage": _w_stage,
		"power": func(box: Control, _el: Dictionary): _power_label = _pill_box(box, "ui/hub/icon_power.png", false),
		"gold": func(box: Control, _el: Dictionary): _gold_label = _pill_box(box, "ui/hub/icon_coin.png", true),
		"crystals": func(box: Control, _el: Dictionary): _crystal_label = _pill_box(box, "ui/hub/icon_crystal.png", true),
	}
	var built := ScreenLayout.build(ScreenLayout.load_layout("hub"), {"widgets": widgets, "settings": settings, "screen": "hub",
			"badges": _add_badge, "on_action": func(a: Dictionary): _do_action({"action": a})})
	built["root"].name = "Layout"
	add_child(built["root"])
	if _gold_label == null:  # в раскладке убрали плашку — подписи всё равно нужны коду
		_gold_label = Label.new()
	if _crystal_label == null:
		_crystal_label = Label.new()
	if _power_label == null:
		_power_label = Label.new()
	if _avatar == null:
		_avatar = TextureRect.new()
	if _stage_label == null:
		_stage_label = Label.new()
		_stage_bar = ProgressBar.new()


func _build_city(settings: Variant, parent: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size = parent.size
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.name = "City"
	parent.add_child(scroll)
	_city_scroll = scroll
	var city := Control.new()
	var h: float = float(hub.get("background_height", 1400))
	city.custom_minimum_size = Vector2(720, h)
	# Вытянутый экран выше фона — город целиком увеличивается (без полос), по ширине — по центру
	var k := maxf(1.0, maxf(parent.size.y / h, parent.size.x / 720.0))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(parent.size.x, h * k)
	holder.clip_contents = true
	scroll.add_child(holder)
	city.scale = Vector2(k, k)
	city.position.x = (parent.size.x - 720.0 * k) / 2.0
	holder.add_child(city)
	var bg := _icon(str(hub.get("background", "")), 0)
	bg.size = Vector2(720, h)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	city.add_child(bg)
	# Эмблема с названием игры
	if hub.has("emblem"):
		var em := _icon(str(hub["emblem"]), 0)
		em.position = Vector2(110, 150)
		em.size = Vector2(500, 192)
		city.add_child(em)
	var title := _outlined(str(settings.get("game_name", "")) if settings is Dictionary else "", 64, "accent", 12)
	title.position = Vector2(0, 196)
	title.size = Vector2(720, 80)
	city.add_child(title)
	var sub := _outlined(str(hub.get("subtitle", "")), 26, "text", 6)
	sub.position = Vector2(0, 272)
	sub.size = Vector2(720, 36)
	city.add_child(sub)
	for b in hub.get("buildings", []):
		_add_building(city, b)
	scroll.scroll_vertical = int(hub.get("start_scroll", 0))


func _add_building(city: Control, b: Dictionary) -> void:
	var tex := Content.load_texture(str(b["image"]))
	var btn := TextureButton.new()
	btn.texture_normal = tex
	var sz: Vector2 = tex.get_size() if tex else Vector2(160, 160)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.size = sz * float(b.get("scale", 1.0))
	var center := Vector2(float(b["x"]), float(b["y"]))
	btn.position = center - btn.size / 2.0
	btn.pressed.connect(_do_action.bind(b))
	city.add_child(btn)
	if b.has("badge"):
		_add_badge(str(b["badge"]), btn, Vector2(btn.size.x * 0.75, btn.size.y * 0.15))
	if str(b.get("title", "")) == "":
		return
	var plate := _plate(str(b["title"]), 28)
	city.add_child(plate)
	plate.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_do_action(b))
	# Табличку центрируем после расчёта её размера
	plate.resized.connect(func():
		plate.position = Vector2(center.x - plate.size.x / 2.0, center.y + btn.size.y / 2.0 - plate.size.y * 0.8))
	plate.position = Vector2(center.x - 90, center.y + btn.size.y / 2.0 - 40)


# --- Верхняя панель ----------------------------------------------------------------------

# --- Верхняя панель (места в раскладке) -----------------------------------------------------

func _w_avatar(box: Control, _el: Dictionary) -> void:
	# Аватар: круг с золотым кольцом (нажатие — настройки и аккаунт)
	var r := int(minf(box.size.x, box.size.y) / 2.0)
	var av := Panel.new()
	av.add_theme_stylebox_override("panel", _style(Ui.colors["primary"], Color.TRANSPARENT, 0, r))
	av.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	av.size = box.size
	box.add_child(av)
	_avatar = _icon("", 0)
	_avatar.size = box.size
	_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	av.add_child(_avatar)
	var ring := Button.new()
	var ring_st := _style(Color.TRANSPARENT, Ui.colors["accent"], 5, r)
	ring_st.draw_center = false
	for state in ["normal", "hover", "pressed", "focus"]:
		ring.add_theme_stylebox_override(state, ring_st)
	ring.size = box.size
	ring.pressed.connect(_open_more)
	box.add_child(ring)


func _w_name(box: Control, _el: Dictionary) -> void:
	_name_label = _outlined(str(Api.player.get("display_name", "Игрок")), 28)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_name_label.size = box.size
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(_name_label)


func _w_stage(box: Control, _el: Dictionary) -> void:
	_stage_label = _outlined("Этап —", 20, "accent", 4)
	_stage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_stage_label.size = Vector2(box.size.x, box.size.y - 16)
	box.add_child(_stage_label)
	_stage_bar = ProgressBar.new()
	_stage_bar.show_percentage = false
	_stage_bar.max_value = 25
	_stage_bar.position = Vector2(0, box.size.y - 18)
	_stage_bar.size = Vector2(box.size.x - 20, 12)
	_stage_bar.add_theme_stylebox_override("background", _style(Color(0, 0, 0, 0.6), Color.TRANSPARENT, 0, 6))
	_stage_bar.add_theme_stylebox_override("fill", _style(Ui.colors["accent"], Color.TRANSPARENT, 0, 6))
	box.add_child(_stage_bar)


func _pill_box(box: Control, icon_path: String, plus: bool) -> Label:
	var sz := box.size
	var pill := PanelContainer.new()
	var st := _style(Color(0.05, 0.04, 0.1, 0.82), Ui.colors["accent"].darkened(0.35), 2, int(sz.y / 2))
	st.content_margin_right = 6
	pill.add_theme_stylebox_override("panel", st)
	pill.custom_minimum_size = sz
	pill.size = sz
	box.add_child(pill)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	pill.add_child(row)
	row.add_child(_icon(icon_path, sz.y))
	var l := _outlined("—", 26, "accent" if not plus else "text", 4)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	if plus:
		var p := TextureButton.new()
		p.texture_normal = Content.load_texture("ui/hub/icon_plus.png")
		p.ignore_texture_size = true
		p.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		p.custom_minimum_size = Vector2(sz.y - 12, sz.y - 12)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.pressed.connect(func(): _show_message(str(hub.get("shop_soon", "Магазин появится на этапе 9."))))
		row.add_child(p)
	return l


static func short_number(n: int) -> String:
	if n >= 1_000_000:
		return "%.1fM" % (n / 1_000_000.0)
	if n >= 100_000:
		return "%dK" % (n / 1000)
	if n >= 10_000:
		return "%.1fK" % (n / 1000.0)
	return str(n)


func _refresh_resources() -> void:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/heroes")
	if not is_inside_tree() or not res.ok:
		return
	var w: Dictionary = res.data["wallet"]
	_gold_label.text = short_number(int(w.get("gold", 0)))
	_crystal_label.text = short_number(int(w.get("crystals", 0)))
	var heroes: Array = res.data["heroes"]
	var power := 0
	for i in range(min(5, heroes.size())):
		power += int(heroes[i]["power"])
	_power_label.text = short_number(power)
	if not heroes.is_empty():
		_avatar.texture = Content.load_texture("heroes/%s/portrait.png" % heroes[0]["hero"])
	var can_level := false
	for h in heroes:
		var cost: Variant = h.get("level_cost")
		if cost is Dictionary and int(w.get("gold", 0)) >= int(cost.get("gold", 0)) \
				and int(w.get("hero_xp", 0)) >= int(cost.get("hero_xp", 0)) and int(w.get("essence", 0)) >= int(cost.get("essence", 0)):
			can_level = true
			break
	_set_badge("heroes", can_level)
	_set_badge("summon", int(w.get("scrolls", 0)) > 0)
	var camp: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/campaign")
	if is_inside_tree() and camp.ok:
		var pend: Dictionary = camp.data.get("pending", {})
		_set_badge("campaign", int(pend.get("gold", 0)) > 0 or bool(camp.data.get("quick_available", false)))
		var cleared: int = int(camp.data.get("cleared", 0))
		_stage_label.text = "Этап %d из 25" % mini(cleared + 1, 25) if cleared < 25 else "Кампания пройдена"
		_stage_bar.value = cleared


# --- Действия ------------------------------------------------------------------------

func _do_action(item: Dictionary) -> void:
	var action: Dictionary = item.get("action", {})
	if action.has("scene"):
		var key := str(action["scene"])
		if key == "hub":
			if is_instance_valid(_city_scroll):
				_city_scroll.scroll_vertical = 0
			return
		if key == "more":
			_open_more()
			return
		get_tree().remove_meta("campaign_stage")
		if SCENES.has(key):
			get_tree().change_scene_to_file(SCENES[key])
		return
	if action.has("soon"):
		_show_message(str(action["soon"]))


func _open_more() -> void:
	var box := _make_dialog("Настройки")
	for n in [_player_label, _account_box, _bg_label]:
		if n.get_parent():
			n.get_parent().remove_child(n)
		box.add_child(n)
	box.add_child(Ui.button("Тестовый бой", _on_play))
	box.add_child(Ui.button("Проверить файлы игры", _on_verify))
	box.add_child(Ui.label("Версия %s (сборка %d)" % [Config.client_version, Updater.current_code()], 20))
	box.add_child(Ui.button("Закрыть", _close_dialog))
	_center_dialog()


func _refresh_account() -> void:
	var p := Api.player
	var kind := "гость" if Api.is_guest() else str(p.get("email", ""))
	var test := "  ·  ТЕСТОВЫЙ" if bool(p.get("is_test", false)) else ""
	_player_label.text = "%s  ·  #%d\n%s%s" % [p.get("display_name", "?"), int(p.get("number", 0)), kind, test]
	for c in _account_box.get_children():
		c.queue_free()
	if Api.is_guest():
		_account_box.add_child(Ui.button("Привязать почту (сохранить прогресс)", _open_link_dialog))
	_account_box.add_child(Ui.button("Войти в другой аккаунт", _open_login_dialog))


func _on_play() -> void:
	get_tree().remove_meta("campaign_stage")
	get_tree().change_scene_to_file("res://scenes/team_select.tscn")


func _on_bg_progress(done: int, total: int) -> void:
	if total > 0:
		_bg_label.text = "Фоновая загрузка: %d%% (%s)" % [int(100.0 * done / total), Content.format_mb(total)]


func _on_bg_finished() -> void:
	_bg_label.text = "Все материалы игры загружены"


func _on_verify() -> void:
	_bg_label.text = "Проверка файлов…"
	var broken: int = await Content.verify_all()
	if broken == 0:
		_bg_label.text = "Все файлы в порядке"
		return
	_bg_label.text = "Повреждено файлов: %d — скачиваю заново…" % broken
	get_tree().change_scene_to_file("res://scenes/boot.tscn")


# --- Диалоги аккаунта ---------------------------------------------------------

func _make_dialog(title: String) -> VBoxContainer:
	_close_dialog()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.name = "Dim"
	add_child(dim)
	_dialog = PanelContainer.new()
	_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_dialog.custom_minimum_size = Vector2(620, 0)
	add_child(_dialog)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	_dialog.add_child(box)
	box.add_child(Ui.label(title, 34, "accent"))
	_dialog_error = Ui.label("", 24)
	_dialog_error.add_theme_color_override("font_color", Color("#FF7A6E"))
	return box


func _center_dialog() -> void:
	await get_tree().process_frame
	if is_instance_valid(_dialog):
		_dialog.position = (size - _dialog.size) / 2.0


func _close_dialog() -> void:
	if has_node("Dim"):
		get_node("Dim").queue_free()
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null


func _show_message(text: String) -> void:
	var box := _make_dialog("Сообщение")
	box.add_child(Ui.label(text, 28))
	box.add_child(Ui.button("Понятно", _close_dialog))
	_center_dialog()


func _offer_update(info: Dictionary) -> void:
	var box := _make_dialog("Новая версия %s" % info.get("version_name", ""))
	var notes := str(info.get("notes", ""))
	box.add_child(Ui.label((notes + "\n\n" if notes != "" else "") +
			"Размер: %s" % Content.format_mb(int(info.get("size", 0))), 26))
	box.add_child(Ui.button("Обновить", func():
		get_tree().set_meta("do_update", info)
		get_tree().change_scene_to_file("res://scenes/boot.tscn")))
	box.add_child(Ui.button("Позже", _close_dialog))
	_center_dialog()


func _open_link_dialog() -> void:
	var box := _make_dialog("Привязать почту")
	box.add_child(Ui.label("После привязки вы сможете войти в свой аккаунт на другом телефоне.", 24))
	var email := Ui.line_edit("Почта")
	email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	var pw := Ui.line_edit("Пароль (от 8 символов, буквы и цифры)", true)
	var pw2 := Ui.line_edit("Повторите пароль", true)
	box.add_child(email)
	box.add_child(pw)
	box.add_child(pw2)
	box.add_child(_dialog_error)
	var ok := Ui.button("Привязать", func():
		if pw.text != pw2.text:
			_dialog_error.text = "Пароли не совпадают"
			return
		_dialog_error.text = "Отправка…"
		var res: Dictionary = await Api.link_email(email.text.strip_edges(), pw.text)
		if res.ok:
			_close_dialog()
			_show_message("Почта привязана. Теперь прогресс сохранён за вашим аккаунтом.")
		else:
			_dialog_error.text = res.error)
	box.add_child(ok)
	box.add_child(Ui.button("Отмена", _close_dialog))
	_center_dialog()


func _open_login_dialog() -> void:
	var box := _make_dialog("Вход по почте")
	if Api.is_guest():
		box.add_child(Ui.label("Внимание: текущий гостевой аккаунт без привязанной почты будет потерян.", 24))
	var email := Ui.line_edit("Почта")
	email.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
	var pw := Ui.line_edit("Пароль", true)
	box.add_child(email)
	box.add_child(pw)
	box.add_child(_dialog_error)
	box.add_child(Ui.button("Войти", func():
		_dialog_error.text = "Вход…"
		var res: Dictionary = await Api.login_email(email.text.strip_edges(), pw.text)
		if res.ok:
			# У другого аккаунта может быть другой канал контента (тестовый) — перезагружаемся
			get_tree().change_scene_to_file("res://scenes/boot.tscn")
		else:
			_dialog_error.text = res.error))
	box.add_child(Ui.button("Отмена", _close_dialog))
	_center_dialog()


# --- Автопроверка (godot --headless ... -- --autotest) ------------------------

func _autotest() -> void:
	if Content.background_running:
		await Content.background_finished
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--autotest-link=") or arg.begins_with("--autotest-login="):
			var creds := arg.get_slice("=", 1).split(":")
			var res: Dictionary
			if arg.begins_with("--autotest-link="):
				res = await Api.link_email(creds[0], creds[1])
			else:
				res = await Api.login_email(creds[0], creds[1])
			print("AUTOTEST ACCOUNT: ", JSON.stringify({"ok": res.ok, "error": res.error, "player": Api.player}))
	var files: Dictionary = Content.state["files"]
	var expected := 0
	for pkg in Content.manifest.get("packages", []):
		expected += pkg.get("files", []).size()
	var bad := 0
	for rel in files.keys():
		if await DownloadWorker.sha256_file(Content.local_path(rel)) != files[rel]:
			bad += 1
	var summary := {
		"player": Api.player.get("display_name"), "number": Api.player.get("number"),
		"is_test": Api.player.get("is_test"), "release": Content.manifest.get("release"),
		"channel": Content.manifest.get("channel"), "files": files.size(), "expected": expected,
		"bad_sha": bad, "logo_loaded": Content.load_texture("ui/logo.png") != null,
		"game_name": str(Content.load_json("config/game_settings.json").get("game_name", "")),
		"play_text": Content.t("ui.button.play"),
	}
	print("AUTOTEST RESULT: ", JSON.stringify(summary))
	if "--autotest-campaign-battle" in OS.get_cmdline_user_args() or "--autotest-campaign-live" in OS.get_cmdline_user_args() or "--autotest-campaign-select" in OS.get_cmdline_user_args():
		get_tree().set_meta("campaign_stage", 1)
		get_tree().change_scene_to_file("res://scenes/team_select.tscn")
		return
	if "--autotest-inventory" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file("res://scenes/inventory.tscn")
		return
	if "--autotest-heroes" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file("res://scenes/heroes.tscn")
		return
	if "--autotest-campaign" in OS.get_cmdline_user_args():
		get_tree().change_scene_to_file("res://scenes/campaign.tscn")
		return
	if "--autotest-live-battle" in OS.get_cmdline_user_args():
		get_tree().set_meta("battle_live", {"team": [
			{"hero": "alpamysha", "slot": 0}, {"hero": "ural_batyr", "slot": 1}, {"hero": "zayatulyak", "slot": 2},
			{"hero": "humai", "slot": 3}, {"hero": "hyuhylu", "slot": 4}], "enemy": "test_evil"})
		get_tree().set_meta("battle_enemy_name", "Отряд Шульгена")
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
		return
	if "--autotest-battle" in OS.get_cmdline_user_args():
		var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, "/api/v1/battle/test", {"team": [
			{"hero": "alpamysha", "slot": 0}, {"hero": "ural_batyr", "slot": 1}, {"hero": "zayatulyak", "slot": 2},
			{"hero": "humai", "slot": 3}, {"hero": "hyuhylu", "slot": 4}], "enemy": "test_evil"})
		if not res.ok:
			print("AUTOTEST FAIL: ", res.error)
			get_tree().quit(1)
			return
		get_tree().set_meta("battle_log", res.data["log"])
		get_tree().set_meta("battle_enemy_name", "Отряд Шульгена")
		get_tree().change_scene_to_file("res://scenes/battle.tscn")
		return
	get_tree().quit(0 if bad == 0 and files.size() == expected else 1)
