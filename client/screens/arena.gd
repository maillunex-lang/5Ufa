extends ColorRect
## Экран арены по эскизу. Место, рейтинг и соперники не считаются и не показываются как настоящие.

func _ready() -> void:
	color = Color.html("#0c1c22")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell: Dictionary = Ui.shell().get("screens", {}).get("arena", {})
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Ui.button("←", 32, 80)
	back.custom_minimum_size = Vector2(90, 80)
	back.pressed.connect(queue_free)
	top.add_child(back)
	var title := Ui.label(State.loc(shell.get("title", {"ru": "Арена"})), 34, Ui.token_color("gold", Color.html("#e6c36a")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0, 280)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := Ui.art_texture(str(shell.get("art", "arena_terrace.jpg")))
	if tex != null:
		art.texture = tex
	root.add_child(art)

	var banner := Ui.panel()
	root.add_child(banner)
	var bv := VBoxContainer.new()
	banner.add_child(bv)
	bv.add_child(Ui.label("Сезон арены", 30, Ui.token_color("gold", Color.html("#e6c36a"))))
	bv.add_child(Ui.label("Асинхронные бои 5×5 в разработке", 24))

	root.add_child(Ui.label(State.loc(shell.get("note", {})), 22, Ui.token_color("muted", Color.html("#c5d4d2"))))
	root.add_child(Ui.label("Место и рейтинг не считаются.", 24))
	root.add_child(Ui.label("Защитный отряд — это ваша текущая расстановка:", 24))
	root.add_child(Ui.label(_formation_names(), 26))

	var change := Ui.button("Изменить расстановку", 26, 80)
	change.pressed.connect(func():
		var host := _hub()
		queue_free()
		if host.has_method("select_tab"):
			host.select_tab(1))
	root.add_child(change)

	root.add_child(Ui.label("Соперники в разработке. Вызов ничего не начинает.", 24))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	row.add_child(_dead("Рейтинг"))
	row.add_child(_dead("История боёв"))


func _dead(text: String) -> Button:
	var b := Ui.button(text, 24, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): Ui.alert(self, text + " в разработке. Цифры с эскиза не используются."))
	return b


func _formation_names() -> String:
	var lines: PackedStringArray = []
	for hid in State.me.get("formation", []):
		var key := ""
		for h in State.me.get("heroes", []):
			if int(h.get("id", -1)) == int(hid):
				key = str(h.get("key", ""))
		var d: Dictionary = State.hero_def(key)
		var name := State.loc(d.get("name", key))
		if name == "":
			name = "герой"
		lines.append(name)
	if lines.is_empty():
		return "Отряд пуст"
	return "\n".join(lines)


func _hub() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method("open_screen"):
			return n
		n = n.get_parent()
	return self
