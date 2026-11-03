extends Control
## Призыв героев: баннеры, шансы, гарант, призыв ×1/×10 и результаты. Результат считает сервер.

var data: Dictionary = {}
var banner_index := 0
var results: Array = []
var _message := ""
var _busy := false
var _root: VBoxContainer


func _ready() -> void:
	Ui.apply_settings(Content.load_json("config/game_settings.json"))
	await _load()


func _load() -> void:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/summon")
	if res.ok:
		data = res.data
	else:
		_message = res.error
	_render()


func _render() -> void:
	if is_instance_valid(_root):
		_root.get_parent().queue_free()
	_root = Ui.screen(self)
	var margin: MarginContainer = _root.get_parent()
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_theme_constant_override("separation", 10)
	_root.add_child(Ui.label("Призыв героев", 40, "accent"))
	if data.is_empty():
		_root.add_child(Ui.label(_message, 24))
		_root.add_child(Ui.button("Повторить", _load))
		_root.add_child(Ui.button("На главный экран", _back))
		return
	_root.add_child(Ui.label(Ui.wallet_text(data["wallet"]), 20))
	var banners: Array = data["banners"]
	banner_index = clampi(banner_index, 0, banners.size() - 1)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 72)
	for b in banners:
		pick.add_item(str(b["name"]))
	pick.selected = banner_index
	pick.item_selected.connect(func(i):
		banner_index = i
		results = []
		_message = ""
		_render())
	_root.add_child(pick)
	var b: Dictionary = banners[banner_index]
	_root.add_child(Ui.label(str(b.get("description", "")), 21))
	var rates := "Шансы: " + " · ".join(b["rates"].map(func(r): return "%s %s%%" % [r["name"], str(r["percent"])]))
	_root.add_child(Ui.label(rates, 19))
	var pity_left: int = int(b["pity_cap"]) - int(b["pity"])
	var pity_text := "Первый призыв — гарантированно легенда!" if bool(b["first_legendary"]) \
			else "Легенда гарантирована не позже чем через %d призыв(ов)" % pity_left
	_root.add_child(Ui.label(pity_text, 21, "accent"))
	var costs: Array = b["costs"]
	_root.add_child(Ui.label("Цена одного призыва: " + " или ".join(costs.map(func(c): return Ui.cost_text(c))), 20))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var one := Ui.button("Призвать ×1", _summon.bind(1))
	one.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(one)
	var ten := Ui.button("Призвать ×10", _summon.bind(10))
	ten.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ten)
	_root.add_child(row)
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
	for r in results:
		grid.add_child(_result_card(r))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 14)
	var to_heroes := Ui.button("К героям", func(): get_tree().change_scene_to_file("res://scenes/heroes.tscn"))
	to_heroes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(to_heroes)
	var back := Ui.button("На главный экран", _back)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(back)
	_root.add_child(nav)


const TIER_COLORS := {"rare": "#5AA9E6", "elite": "#B06CE0", "legendary": "#F2B544"}
const TIER_NAMES := {"rare": "Редкий", "elite": "Элита", "legendary": "Легенда"}


func _result_card(r: Dictionary) -> Control:
	var box := VBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = Content.load_texture("heroes/%s/portrait.png" % r["hero"])
	icon.custom_minimum_size = Vector2(112, 112)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var lab := Ui.label(TIER_NAMES.get(r["tier"], r["tier"]) + (" · новый" if bool(r["new"]) else ""), 17)
	lab.add_theme_color_override("font_color", Color(TIER_COLORS.get(r["tier"], "#FFFFFF")))
	box.add_child(lab)
	return box


func _summon(count: int) -> void:
	if _busy:
		return
	_busy = true
	var b: Dictionary = data["banners"][banner_index]
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_POST, "/api/v1/summon", {"banner": b["id"], "count": count})
	_busy = false
	if res.ok:
		results = res.data["results"]
		var legends: int = results.filter(func(x): return x["tier"] == "legendary").size()
		_message = "Призвано героев: %d%s" % [results.size(), (", из них легенд: %d" % legends) if legends > 0 else ""]
	else:
		_message = res.error
	var keep := banner_index
	await _load()
	banner_index = keep
	_render()


func _back() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")
