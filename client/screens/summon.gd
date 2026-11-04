extends ColorRect
## Экран призыва по эскизу. Кнопки ничего не списывают и героя не выдают.

func _ready() -> void:
	color = Color.html("#0c1c22")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell: Dictionary = Ui.shell().get("screens", {}).get("summon", {})
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	top.custom_minimum_size = Vector2(0, 90)
	root.add_child(top)
	var back := Ui.button("←", 32, 80)
	back.custom_minimum_size = Vector2(90, 80)
	back.pressed.connect(queue_free)
	top.add_child(back)
	var title := Ui.label(State.loc(shell.get("title", {"ru": "Призыв героев"})), 32, Ui.token_color("gold", Color.html("#e6c36a")))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(title)
	var bal: Dictionary = State.me.get("balances", {})
	top.add_child(Ui.label("Свитки 0", 22))
	top.add_child(Ui.label("Алмазы " + Ui.grouped(int(bal.get("diamond", 0))), 22, Ui.token_color("magic", Color.html("#3ecfc4"))))

	var art := TextureRect.new()
	art.custom_minimum_size = Vector2(0, 520)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := Ui.art_texture(str(shell.get("art", "summon_hero.jpg")))
	if tex != null:
		art.texture = tex
	root.add_child(art)

	var note := Ui.label(State.loc(shell.get("note", {})), 22, Ui.token_color("muted", Color.html("#c5d4d2")))
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(note)
	root.add_child(Ui.label("Герой на иллюстрации. Это не ваш герой и не результат призыва.", 20, Ui.token_color("muted", Color.html("#c5d4d2"))))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)
	row.add_child(_summon_button("Призвать ×1"))
	row.add_child(_summon_button("Призвать ×10"))

	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 12)
	root.add_child(links)
	var list := Ui.button("Список героев", 24, 72)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.pressed.connect(func():
		var host := _hub()
		queue_free()
		if host.has_method("select_tab"):
			host.select_tab(2))
	links.add_child(list)
	var rules := Ui.button("Правила призыва", 24, 72)
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rules.pressed.connect(func(): Ui.alert(self, "Правил призыва ещё нет: шансы, свитки и цена в алмазах не действуют."))
	links.add_child(rules)


func _summon_button(text: String) -> Button:
	var b := Ui.button(text, 28, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func(): Ui.alert(self, "Призыв в разработке. Ничего не списывается и герой не выдаётся."))
	return b


func _hub() -> Node:
	var n: Node = get_parent()
	while n:
		if n.has_method("open_screen"):
			return n
		n = n.get_parent()
	return self
