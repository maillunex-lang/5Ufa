extends MarginContainer
## Кампания: 10 этапов, расстановка 2+3 перед боем. Награда только за первую победу (решает сервер).

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
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)
	State.changed.connect(_build)
	_build()


func _build() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(Ui.label("Кампания · Глава 1", 44))
	var done := State.max_cleared()
	for s in State.content["stages"]:
		var n: int = int(s["n"])
		var cleared := n <= done
		var open := n <= done + 1
		var rw: Dictionary = s["reward"]
		var status := "✓ пройден" if cleared else ("доступен" if open else "закрыт")
		var b := Ui.button("%s\n%s · первая награда: золото %d, опыт %d" % [s["name"], status, int(rw["gold"]), int(rw["hero_exp"])], 26, 110)
		b.disabled = not open
		var sn := n
		b.pressed.connect(func(): _formation(sn))
		_list.add_child(b)


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
