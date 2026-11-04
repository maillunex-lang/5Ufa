extends MarginContainer
## Кампания: 10 этапов, расстановка 2+3 перед боем. Награда только за первую победу (решает сервер).

var _list: VBoxContainer
var _season_id := ""
var _place_id := ""


func _ready() -> void:
	add_theme_constant_override("margin_left", 24)
	add_theme_constant_override("margin_right", 24)
	add_theme_constant_override("margin_top", 24)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)
	State.changed.connect(_build)
	_build()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	var world: Dictionary = State.content.get("world", {})
	if world.is_empty():
		_list.add_child(Ui.label("Кампания", 36, Ui.token_color("gold", Color.html("#c6a15a"))))
		_stage_list()
		return
	_list.add_child(Ui.label("Карта", 36, Ui.token_color("gold", Color.html("#c6a15a"))))
	var demo := "Демонстрация, не полная карта." if world.get("_demo", false) else ""
	_list.add_child(Ui.label(State.loc(world.get("republic", {}).get("name", "")) + ". " + demo, 22, Ui.token_color("muted", Color.html("#b7aa96"))))
	_list.add_child(Ui.label(State.loc(world.get("republic", {}).get("fact", "")), 20, Ui.token_color("text", Color.html("#f4ecdf"))))
	var proposals: Dictionary = world.get("proposals", {})
	if str(proposals.get("status", "")) != "approved":
		_list.add_child(Ui.label("Имя духа, виновник и стартовый район не утверждены. В игре они только варианты.", 20, Ui.token_color("magic", Color.html("#3ecfc4"))))
	var seasons_arr: Array = world.get("seasons", [])
	if _season_id == "" and seasons_arr.size() > 0:
		_season_id = str(seasons_arr[0].get("id", ""))
	var seasons := VBoxContainer.new()
	seasons.add_theme_constant_override("separation", 8)
	_list.add_child(seasons)
	for s in world.get("seasons", []):
		var sid := str(s.get("id", ""))
		var open := _unlocked(str(s.get("unlock", "always")))
		var label := State.loc(s.get("name", sid))
		if str(s.get("kind", "")) != "story":
			label += " · пусто"
		if not open:
			label += " · закрыт"
		var b := Ui.button(label, 20, 72)
		b.disabled = not open
		if sid == _season_id:
			b.add_theme_stylebox_override("normal", Ui.box(Ui.token_color("panel", Color(0.11, 0.09, 0.08)), 12, Ui.token_color("magic", Color.html("#3ecfc4")), 2))
		var pick := sid
		b.pressed.connect(func():
			_season_id = pick
			call_deferred("_build"))
		seasons.add_child(b)
	var season := _by_id(world.get("seasons", []), _season_id)
	if not season.is_empty():
		_list.add_child(Ui.label(State.loc(season.get("summary", "")), 20, Ui.token_color("muted", Color.html("#b7aa96"))))
		if str(season.get("kind", "")) != "story":
			_list.add_child(Ui.label("Этот сезон отдельный. Заданий и боёв в нём нет: режим ещё не сделан.", 22, Ui.token_color("danger", Color.html("#d46558"))))
	for d in world.get("districts", []):
		var did := str(d.get("id", ""))
		var places: Array = []
		for p in world.get("places", []):
			if str(p.get("districtId", "")) == did:
				places.append(p)
		var card := Ui.panel()
		_list.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		card.add_child(box)
		var kind := "район" if str(d.get("kind", "")) == "district" else "город"
		box.add_child(Ui.label("%s · %s" % [State.loc(d.get("name", did)), kind], 26, Ui.token_color("gold", Color.html("#c6a15a"))))
		box.add_child(Ui.label("Факт. " + State.loc(d.get("fact", "")), 18, Ui.token_color("text", Color.html("#f4ecdf"))))
		if State.loc(d.get("fiction", "")) != "":
			box.add_child(Ui.label("Вымысел. " + State.loc(d.get("fiction", "")), 18, Ui.token_color("muted", Color.html("#b7aa96"))))
		if places.is_empty():
			box.add_child(Ui.label("Мест пока нет. Это не спрятанный уровень.", 18, Ui.token_color("muted", Color.html("#b7aa96"))))
		for p in places:
			var pid := str(p.get("id", ""))
			var pb := Ui.button(State.loc(p.get("name", pid)), 24, 84)
			var choose := pid
			pb.pressed.connect(func():
				_place_id = choose
				call_deferred("_build"))
			box.add_child(pb)
	if _place_id != "":
		_place_block(world)
	_list.add_child(Ui.label("Прежние этапы 1–10", 28, Ui.token_color("text", Color.html("#f4ecdf"))))
	_list.add_child(Ui.label("Старый порядок кампании на месте. Награды и прогресс те же.", 18, Ui.token_color("muted", Color.html("#b7aa96"))))
	_stage_list()


func _place_block(world: Dictionary) -> void:
	var place := _by_id(world.get("places", []), _place_id)
	if place.is_empty():
		return
	var card := Ui.panel()
	_list.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(Ui.label(State.loc(place.get("name", "")), 28, Ui.token_color("gold", Color.html("#c6a15a"))))
	var art: Dictionary = place.get("art", {})
	var file := str(art.get("background", ""))
	var tex: Texture2D = Media.texture(file.get_file().get_basename())
	if tex == null and file != "" and ResourceLoader.exists("res://assets/backgrounds/" + file):
		tex = load("res://assets/backgrounds/" + file)
	if tex != null:
		var rect := TextureRect.new()
		rect.custom_minimum_size = Vector2(0, 280)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.texture = tex
		box.add_child(rect)
	if str(art.get("status", "")) == "temporary":
		box.add_child(Ui.label("Картинка временная. Это не фотография места и не финальный фон.", 18, Ui.token_color("magic", Color.html("#3ecfc4"))))
	for need in art.get("need", []):
		box.add_child(Ui.label("Нужно: " + str(need), 16, Ui.token_color("muted", Color.html("#b7aa96"))))
	box.add_child(Ui.label("Факт. " + State.loc(place.get("fact", "")), 18))
	if State.loc(place.get("fiction", "")) != "":
		box.add_child(Ui.label("Вымысел. " + State.loc(place.get("fiction", "")), 18, Ui.token_color("muted", Color.html("#b7aa96"))))
	for st in world.get("placeStates", []):
		if str(st.get("placeId", "")) == _place_id and str(st.get("seasonId", "")) == _season_id:
			box.add_child(Ui.label("Состояние сезона. " + State.loc(st.get("name", "")) + ". " + State.loc(st.get("fiction", "")), 18, Ui.token_color("text", Color.html("#f4ecdf"))))
	var chain_ids: Array = []
	for ch in world.get("chains", []):
		if str(ch.get("placeId", "")) == _place_id and str(ch.get("seasonId", "")) == _season_id and _unlocked(str(ch.get("unlock", "always"))):
			chain_ids.append(str(ch.get("id", "")))
	var quests: Array = []
	for q in world.get("quests", []):
		if chain_ids.has(str(q.get("chainId", ""))):
			quests.append(q)
	quests.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	if quests.is_empty():
		box.add_child(Ui.label("В этом сезоне у места нет заданий.", 18, Ui.token_color("muted", Color.html("#b7aa96"))))
	for q in quests:
		var open := _unlocked(str(q.get("unlock", "always")))
		var title := State.loc(q.get("name", ""))
		if str(q.get("kind", "")) == "story":
			title += " · сцена"
		else:
			title += " · бой, этап %d" % int(q.get("stage", 0))
		if State.story_done(str(q.get("id", ""))):
			title += " · просмотрено"
		if not open:
			title += " · закрыто"
		var b := Ui.button(title, 22, 84)
		b.disabled = not open
		var quest: Dictionary = q
		b.pressed.connect(func():
			if str(quest.get("kind", "")) == "story":
				_story(quest)
			else:
				_formation(int(quest.get("stage", 0))))
		box.add_child(b)


func _story(quest: Dictionary) -> void:
	var scene: Dictionary = _by_id(State.content.get("world", {}).get("scenes", []), str(quest.get("sceneId", "")))
	var lines := ""
	for ln in scene.get("lines", []):
		lines += str(ln.get("who", "")) + ": " + State.loc(ln.get("text", "")) + "\n\n"
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.72)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := Ui.panel()
	p.custom_minimum_size = Vector2(640, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	v.add_child(Ui.label(State.loc(scene.get("name", "Сцена")), 32, Ui.token_color("gold", Color.html("#c6a15a"))))
	v.add_child(Ui.label(lines.strip_edges(), 22))
	var ok := Ui.button("Запомнить и закрыть", 26, 84)
	ok.pressed.connect(func():
		ok.disabled = true
		var r: Dictionary = await Api.request("POST", "/api/story/complete", {"questId": str(quest.get("id", ""))})
		if not r["ok"]:
			ok.disabled = false
			Ui.alert(self, str(r["message"]))
			return
		await State.refresh_me()
		overlay.queue_free())
	v.add_child(ok)
	var cancel := Ui.button("Закрыть без отметки", 22, 72)
	cancel.pressed.connect(overlay.queue_free)
	v.add_child(cancel)


func _stage_list() -> void:
	var done := State.max_cleared()
	for s in State.content["stages"]:
		var n: int = int(s["n"])
		var cleared := n <= done
		var open := n <= done + 1
		var rw: Dictionary = s["reward"]
		var status := "✓ пройден" if cleared else ("доступен" if open else "закрыт")
		var b := Ui.button("%s\n%s · первая награда: золото %d, опыт %d" % [s["name"], status, int(rw["gold"]), int(rw["hero_exp"])], 26, 110)
		b.disabled = not open
		b.add_to_group("stage_%d" % n)
		if n == done + 1:
			b.add_to_group("stage_next")
		var sn := n
		b.pressed.connect(func(): _formation(sn))
		_list.add_child(b)


func _unlocked(unlock: String) -> bool:
	if unlock == "" or unlock == "always":
		return true
	if unlock.begins_with("stage:"):
		var want := int(unlock.get_slice(":", 1))
		for s in State.me.get("clearedStages", []):
			if int(s) == want:
				return true
		return false
	if unlock.begins_with("quest:"):
		return State.story_done(unlock.get_slice(":", 1))
	return false


func _by_id(list: Array, id: String) -> Dictionary:
	for x in list:
		if str(x.get("id", "")) == id:
			return x
	return {}


func _formation(stage: int) -> void:
	var slots: Array = (State.me["formation"] as Array).duplicate()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.75)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := Ui.panel(Color(0.14, 0.16, 0.22))
	p.custom_minimum_size = Vector2(620, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	v.add_child(Ui.label("Этап %d · расстановка" % stage, 36))
	v.add_child(Ui.label("Нажмите двух героев, чтобы поменять их местами.", 24, Color(1, 1, 1, 0.7)))
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 10)
	v.add_child(holder)
	var sel := [-1]

	var redraw := func() -> void: pass
	redraw = func() -> void:
		for c in holder.get_children():
			c.queue_free()
		for i in 5:
			var h := State.owned_hero(int(slots[i]))
			var d := State.hero_def(h.get("key", ""))
			var row := "Перед" if i < 2 else "Зад"
			var b := Ui.button("%s %d: %s (ур. %d)" % [row, i + 1 if i < 2 else i - 1, d.get("name", "?"), int(h.get("level", 1))], 28, 84)
			if sel[0] == i:
				b.add_theme_stylebox_override("normal", Ui.box(Color(0.6, 0.45, 0.1)))
			var idx := i
			b.pressed.connect(func():
				if sel[0] == -1:
					sel[0] = idx
				else:
					var t = slots[sel[0]]
					slots[sel[0]] = slots[idx]
					slots[idx] = t
					sel[0] = -1
				redraw.call())
			holder.add_child(b)
	redraw.call()

	var go := Ui.button("В бой", 34, 100)
	v.add_child(go)
	var cancel := Ui.button("Отмена", 28, 80)
	cancel.pressed.connect(overlay.queue_free)
	v.add_child(cancel)
	go.pressed.connect(func():
		go.disabled = true
		if slots != State.me["formation"]:
			var f: Dictionary = await Api.request("POST", "/api/formation", {"slots": slots})
			if not f["ok"]:
				go.disabled = false
				Ui.alert(self, str(f["message"]))
				return
		var r: Dictionary = await Api.request("POST", "/api/battle/start", {"stage": stage})
		if not r["ok"]:
			go.disabled = false
			Ui.alert(self, str(r["message"]))
			return
		await State.refresh_me()
		State.battle_result = r["data"]
		State.start_tab = 1
		get_tree().change_scene_to_file("res://battle.tscn"))
