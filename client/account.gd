extends ColorRect
## Окно аккаунта: статус, привязка логина и пароля (с показом резервного кода один раз), выход.

var _box: VBoxContainer
var _confirm_exit := false


func _ready() -> void:
	color = Color(0, 0, 0, 0.8)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var p := Ui.panel(Color(0.14, 0.16, 0.22))
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 16)
	p.add_child(_box)
	_build()


func _build() -> void:
	for c in _box.get_children():
		c.queue_free()
	var acc: Dictionary = State.me["account"]
	_box.add_child(Ui.label("Аккаунт №%d" % int(acc["id"]), 40))
	if acc["bound"]:
		_box.add_child(Ui.label("Логин: %s\nАккаунт защищён паролем и резервным кодом." % str(acc["login"]), 28))
	else:
		_box.add_child(Ui.label("Вы играете гостем. Если удалить игру или сменить телефон, прогресс пропадёт. Привяжите логин и пароль, чтобы его сохранить.", 26, Color(1, 0.85, 0.5)))
		var login := Ui.line_edit("Логин (3–32 символа: a-z, 0-9, _ . -)")
		var pw := Ui.line_edit("Пароль (не короче 8 символов)", true)
		var pw2 := Ui.line_edit("Повторите пароль", true)
		_box.add_child(login)
		_box.add_child(pw)
		_box.add_child(pw2)
		var err := Ui.label("", 26, Color(1, 0.5, 0.5))
		_box.add_child(err)
		var bind := Ui.button("Привязать", 32, 96)
		bind.pressed.connect(func():
			if pw.text != pw2.text:
				err.text = "Пароли не совпадают"
				return
			bind.disabled = true
			var r: Dictionary = await Api.request("POST", "/api/bind", {"login": login.text, "password": pw.text})
			if not r["ok"]:
				err.text = str(r["message"])
				bind.disabled = false
				return
			Ui.recovery_code_dialog(self, str(r["data"]["recoveryCode"]), func():
				await State.refresh_me()
				_build()))
		_box.add_child(bind)
	var out := Ui.button("Выйти из аккаунта", 28, 84)
	out.pressed.connect(func():
		if not acc["bound"] and not _confirm_exit:
			_confirm_exit = true
			out.text = "Гостевой прогресс будет потерян. Нажмите ещё раз"
			return
		Api.clear_token()
		State.clear_flags()
		get_tree().change_scene_to_file("res://main.tscn"))
	_box.add_child(out)
	var close := Ui.button("Закрыть", 28, 84)
	close.pressed.connect(queue_free)
	_box.add_child(close)
