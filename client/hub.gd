extends Control
## Главный экран: сверху профиль и валюты + раскрывающееся меню, снизу вкладки строго
## Город · Кампания · Герои · Инвентарь.

const TAB_NAMES := ["Город", "Кампания", "Герои", "Инвентарь"]
const TAB_SCRIPTS := [
	preload("res://tabs/city.gd"), preload("res://tabs/campaign.gd"),
	preload("res://tabs/heroes.gd"), preload("res://tabs/inventory.gd"),
]

var _content: Control
var _tab_buttons: Array = []
var _info: Label
var _menu: PanelContainer
var _tut: Control


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.token_color("bg", Color.html("#12100e"))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 0)
	add_child(col)

	var top := Ui.panel()
	top.custom_minimum_size = Vector2(0, 150)
	col.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)
	_info = Ui.label("", 28)
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	th.add_child(_info)
	var mb := Ui.button("☰", 40, 90)
	mb.custom_minimum_size = Vector2(110, 90)
	mb.size_flags_vertical = Control.SIZE_SHRINK_END
	mb.pressed.connect(func(): _menu.visible = not _menu.visible)
	th.add_child(mb)

	_content = Control.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_content)

	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 120)
	bottom.add_theme_constant_override("separation", 0)
	col.add_child(bottom)
	for i in TAB_NAMES.size():
		var b := Ui.button(TAB_NAMES[i], 28, 120)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		var idx := i
		b.pressed.connect(func(): _select(idx))
		bottom.add_child(b)
		_tab_buttons.append(b)

	# Раскрывающееся меню. Пункты недоступных систем отключены и подписаны — не имитируют работу.
	_menu = Ui.panel(Color(0.16, 0.18, 0.24))
	_menu.visible = false
	_menu.custom_minimum_size = Vector2(400, 0)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 8)
	_menu.add_child(mv)
	var acc_btn := Ui.button("Аккаунт", 26, 76)
	acc_btn.pressed.connect(func():
		_menu.visible = false
		add_child(preload("res://account.gd").new()))
	mv.add_child(acc_btn)
	for it in ["Почта", "Задания", "Получить AFK-награды", "Настройки"]:
		var mi := Ui.button(it + " (скоро)", 26, 76)
		mi.disabled = true
		mv.add_child(mi)
	add_child(_menu)
	_menu.anchor_left = 1.0
	_menu.anchor_right = 1.0
	_menu.offset_left = -420
	_menu.offset_right = -20
	_menu.offset_top = 150

	State.changed.connect(_update_top)
	_update_top()
	_select(State.start_tab)
	State.start_tab = 0
	_tut = preload("res://tutorial.gd").new()
	add_child(_tut)
	_tut.setup(self)


func _update_top() -> void:
	var bal: Dictionary = State.me.get("balances", {})
	_info.text = "Аккаунт №%d\nЗолото %d · Опыт героев %d" % [int(State.me["account"]["id"]), int(bal.get("gold", 0)), int(bal.get("hero_exp", 0))]


func _select(i: int) -> void:
	_menu.visible = false
	for c in _content.get_children():
		c.queue_free()
	for k in _tab_buttons.size():
		(_tab_buttons[k] as Button).button_pressed = (k == i)
	var tab: Control = TAB_SCRIPTS[i].new()
	tab.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.add_child(tab)
	if _tut != null:
		_tut.refresh()
