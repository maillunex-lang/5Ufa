extends Control
## Главный экран: город на весь фон, сверху профиль, VIP и валюты, снизу вкладки
## Город · Кампания · Герои · Инвентарь. Почта и настройки — в меню справа.

const TAB_SCRIPTS := [
	preload("res://tabs/city.gd"), preload("res://tabs/campaign.gd"),
	preload("res://tabs/heroes.gd"), preload("res://tabs/inventory.gd"),
]

var _content: Control
var _tab_buttons: Array = []
var _menu: PanelContainer
var _city_layer: Control
var _tut: Control
var _gold: Label
var _gem: Label


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.token_color("bg", Color.html("#0c1c22"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_city_layer = preload("res://tabs/city.gd").new()
	_city_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_city_layer)

	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)

	col.add_child(_top_bar())

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_content)

	col.add_child(_bottom_bar())

	_build_menu()
	State.changed.connect(_update_top)
	_update_top()
	_select(State.start_tab)
	State.start_tab = 0
	_tut = preload("res://tutorial.gd").new()
	add_child(_tut)
	_tut.setup(self)


func _top_bar() -> PanelContainer:
	var top := Ui.panel(Color(0.07, 0.16, 0.18, 0.92))
	top.custom_minimum_size = Vector2(0, 132)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 10)
	top.add_child(th)

	var profile := Button.new()
	profile.custom_minimum_size = Vector2(86, 86)
	profile.clip_contents = true
	var face := Ui.art_texture(str(Ui.shell().get("profileArt", "profile_temp.jpg")))
	if face != null:
		profile.icon = face
		profile.expand_icon = true
		profile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		profile.text = "П"
	profile.pressed.connect(func(): open_overlay(preload("res://account.gd").new()))
	th.add_child(profile)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 6)
	th.add_child(mid)
	var prof := Ui.button("Профиль", 26, 56)
	prof.pressed.connect(func(): open_overlay(preload("res://account.gd").new()))
	mid.add_child(prof)
	var vip := Ui.button("VIP 0", 20, 44)
	vip.pressed.connect(func(): Ui.alert(self, "VIP в разработке. Уровень не считается и ничего не даёт."))
	mid.add_child(vip)

	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 8)
	th.add_child(money)
	money.add_child(_money_chip("icon_gold.png", true))
	money.add_child(_money_chip("icon_diamond.png", false))

	var mb := Ui.button("☰", 36, 86)
	mb.custom_minimum_size = Vector2(86, 86)
	mb.pressed.connect(func(): _menu.visible = not _menu.visible)
	th.add_child(mb)
	return top


func _money_chip(art: String, gold: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := Ui.art_texture(art)
	if tex != null:
		icon.texture = tex
	row.add_child(icon)
	var lab := Ui.label("0", 28, Ui.token_color("gold", Color.html("#e6c36a")))
	row.add_child(lab)
	if gold:
		_gold = lab
	else:
		_gem = lab
	return row


func _bottom_bar() -> HBoxContainer:
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 128)
	bottom.add_theme_constant_override("separation", 0)
	var shell := Ui.shell()
	var nav: Array = shell.get("nav", [])
	var icons := ["icon_nav_city.png", "icon_nav_campaign.png", "icon_nav_heroes.png", "icon_nav_inventory.png"]
	var fallback := ["Город", "Кампания", "Герои", "Инвентарь"]
	for i in fallback.size():
		var title := fallback[i]
		if i < nav.size():
			var got := State.loc(nav[i].get("label", ""))
			if got != "":
				title = got
		var b := Button.new()
		b.text = title
		b.clip_text = true
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 128)
		b.add_theme_font_size_override("font_size", 22)
		var tex := Ui.art_texture(icons[i])
		if tex != null:
			b.icon = tex
			b.expand_icon = true
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		var idx := i
		b.pressed.connect(func(): select_tab(idx))
		bottom.add_child(b)
		_tab_buttons.append(b)
	return bottom


func _build_menu() -> void:
	_menu = Ui.panel(Color(0.07, 0.16, 0.18, 0.96))
	_menu.visible = false
	_menu.custom_minimum_size = Vector2(420, 0)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	_menu.add_child(mv)
	var items: Array = Ui.shell().get("menu", [])
	if items.is_empty():
		items = [
			{"label": {"ru": "Почта"}, "unlock": "always", "status": "unbuilt"},
			{"label": {"ru": "Настройки"}, "unlock": "always", "status": "ready", "action": "settings"},
		]
	for it in items:
		var item: Dictionary = it
		var b := Ui.button(State.loc(item.get("label", "")), 26, 76)
		b.pressed.connect(func():
			_menu.visible = false
			Ui.shell_press(self, item, self))
		mv.add_child(b)
	add_child(_menu)
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.offset_left = -440
	_menu.offset_right = -12
	_menu.offset_top = 140


func _update_top() -> void:
	var bal: Dictionary = State.me.get("balances", {})
	if _gold != null:
		_gold.text = Ui.grouped(int(bal.get("gold", 0)))
	if _gem != null:
		_gem.text = Ui.grouped(int(bal.get("diamond", 0)))


func select_tab(i: int) -> void:
	_select(i)


func open_overlay(node: Control) -> void:
	_menu.visible = false
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)


func open_screen(id: String) -> void:
	_menu.visible = false
	if id == "summon":
		open_overlay(preload("res://screens/summon.gd").new())
	elif id == "arena":
		open_overlay(preload("res://screens/arena.gd").new())
	else:
		Ui.alert(self, "В разработке")


func _select(i: int) -> void:
	_menu.visible = false
	for c in _content.get_children():
		c.queue_free()
	_city_layer.visible = i == 0
	_content.visible = i != 0
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE if i == 0 else Control.MOUSE_FILTER_STOP
	for k in _tab_buttons.size():
		var b := _tab_buttons[k] as Button
		b.button_pressed = k == i
		b.modulate = Color(0.75, 1, 0.95) if k == i else Color.WHITE
	if i != 0:
		var tab: Control = TAB_SCRIPTS[i].new()
		tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_content.add_child(tab)
	if _tut != null:
		_tut.refresh()
