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
		var p := Ui.panel()
		var rarity := str(d.get("rarity", ""))
		var border := Ui.token_color("gold", Color.html("#c6a15a"))
		if rarity == "uncommon":
			border = Ui.token_color("magic", Color.html("#3ecfc4"))
		elif rarity == "epic":
			border = Color.html("#b48cff")
		elif rarity == "legendary":
			border = Color.html("#e7c56a")
		elif rarity == "common" or rarity == "":
			border = Ui.token_color("muted", Color.html("#b7aa96"))
		p.add_theme_stylebox_override("panel", Ui.box(Ui.token_color("panel", Color(0.11, 0.094, 0.078, 0.94)), 12, border, 2))
		_list.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		p.add_child(v)
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(0, 420)
		portrait.color = Color(0.07, 0.06, 0.05)
		v.add_child(portrait)
		var mark := ColorRect.new()
		mark.custom_minimum_size = Vector2(28, 28)
		mark.color = border
		mark.position = Vector2(16, 16)
		portrait.add_child(mark)
		v.add_child(Ui.label("Портрет в полный рост ещё не нарисован. Квадрат — временная метка цвета рамки, не эмблема. В бою стоит временная модель: это не финальное лицо и не финальный костюм.", 18, Ui.token_color("muted", Color.html("#b7aa96"))))
		var faction := _faction_name(str(d.get("faction", "")))
		var kind := "крутой" if d.get("type", "") == "cool" else "обычный"
		var rarity_label := rarity if rarity != "" else "без рамки"
		v.add_child(Ui.label("%s · ур. %d/%d" % [d.get("name", h["key"]), lv, maxlv], 32, Ui.token_color("text", Color.html("#f4ecdf"))))
		v.add_child(Ui.label("%s · %s · рамка «%s» (предложение, не баланс)" % [faction, kind, rarity_label], 20, Ui.token_color("gold", Color.html("#c6a15a"))))
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


func _faction_name(id: String) -> String:
	if id == "":
		return "без фракции"
	for f in State.content.get("world", {}).get("factions", []):
		if str(f.get("id", "")) == id:
			return State.loc(f.get("name", id))
	return id


func _act(path: String, hero_id: int) -> void:
	var r: Dictionary = await Api.request("POST", path, {"heroId": hero_id})
	if not r["ok"]:
		Ui.alert(self, str(r["message"]))
		return
	if path == "/api/hero/upgrade":
		State.set_flag("tut_upgraded")
	await State.refresh_me()
