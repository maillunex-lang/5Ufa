extends MarginContainer
## Герои: список, характеристики, прокачка за золото и опыт, бесплатный сброс уровня.

var _list: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 24)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 20)
	scroll.add_child(_list)
	State.changed.connect(_build)
	_build()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(Ui.label("Герои", 44))
	var maxlv: int = int(State.me["maxLevel"])
	var cost: Dictionary = State.content["progression"]["upgradeCost"]
	for h in State.me["heroes"]:
		var d := State.hero_def(h["key"])
		var lv: int = int(h["level"])
		var st := State.hero_stats(h["key"], lv)
		var p := Ui.panel(Color(0.16, 0.18, 0.24))
		_list.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		p.add_child(v)
		var kind := "крутой" if d.get("type", "") == "cool" else "обычный"
		v.add_child(Ui.label("%s · ур. %d/%d (%s)" % [d.get("name", h["key"]), lv, maxlv, kind], 34))
		v.add_child(Ui.label("Здоровье %d   Атака %d   Защита %d\nКрит %d%% (×%.1f)   Дальность %.1f" % [
			int(st["hp"]), int(st["atk"]), int(st["def"]), int(float(st["critChance"]) * 100), float(st["critPower"]), float(st["range"])], 26, Color(1, 1, 1, 0.8)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		v.add_child(row)
		var up := Ui.button("Улучшить\n%d зол. + %d оп." % [int(cost["gold"]) * lv, int(cost["hero_exp"]) * lv], 24, 90)
		up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		up.disabled = lv >= maxlv
		if h == State.me["heroes"][0]:
			up.add_to_group("upgrade_first")
		var hid: int = int(h["id"])
		up.pressed.connect(func(): _act("/api/hero/upgrade", hid))
		row.add_child(up)
		var rs := Ui.button("Сбросить уровень\n(бесплатно, возврат затрат)", 24, 90)
		rs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rs.disabled = lv <= 1
		rs.pressed.connect(func(): _act("/api/hero/reset", hid))
		row.add_child(rs)


func _act(path: String, hero_id: int) -> void:
	var r: Dictionary = await Api.request("POST", path, {"heroId": hero_id})
	if not r["ok"]:
		Ui.alert(self, str(r["message"]))
		return
	if path == "/api/hero/upgrade":
		State.set_flag("tut_upgraded")
	await State.refresh_me()
