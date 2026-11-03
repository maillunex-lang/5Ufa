extends Control
## Главный экран (этап 2): название и логотип из контента, аккаунт, фоновая загрузка.
## На следующих этапах здесь появится город/кампания.

var _player_label: Label
var _bg_label: Label
var _account_box: VBoxContainer
var _dialog: PanelContainer
var _dialog_error: Label


func _ready() -> void:
	var settings: Variant = Content.load_json("config/game_settings.json")
	Ui.apply_settings(settings)
	var col := Ui.screen(self)

	var logo := TextureRect.new()
	logo.texture = Content.load_texture("ui/logo.png")
	logo.custom_minimum_size = Vector2(0, 220)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	col.add_child(logo)
	var title := str(settings.get("game_name", "")) if settings is Dictionary else ""
	col.add_child(Ui.label(title, 52, "accent"))

	_player_label = Ui.label("", 28)
	col.add_child(_player_label)
	col.add_child(Ui.spacer())
	col.add_child(Ui.button("Тестовый бой", _on_play))
	_account_box = VBoxContainer.new()
	_account_box.add_theme_constant_override("separation", 20)
	col.add_child(_account_box)
	col.add_child(Ui.button("Проверить файлы игры", _on_verify))
	_bg_label = Ui.label("", 22)
	col.add_child(_bg_label)
	col.add_child(Ui.label("Версия %s (сборка %d)" % [Config.client_version, Updater.current_code()], 20))

	Api.player_changed.connect(func(_p): _refresh_account())
	Content.background_progress.connect(_on_bg_progress)
	Content.background_finished.connect(_on_bg_finished)
	_refresh_account()
	if get_tree().has_meta("notice"):
		_show_message(str(get_tree().get_meta("notice")))
		get_tree().remove_meta("notice")
	elif get_tree().has_meta("update_offer") and not Config.autotest:
		_offer_update(get_tree().get_meta("update_offer"))
		get_tree().remove_meta("update_offer")
	Content.sync_background()
	if Config.autotest:
		_autotest()


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
