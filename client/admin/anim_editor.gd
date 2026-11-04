class_name AnimEditor
extends VBoxContainer
## Визуальный редактор анимации героя (формат ufa-skeleton, docs/skeleton-format.md).
## Выбор анимации и кости, шкала времени, ключевые кадры поворота / сдвига / масштаба,
## поворот и сдвиг кости пальцем прямо по герою, события удара/снаряда, части героя (скачать, заменить, добавить).
## Сохраняет skeleton.json и картинки частей в черновик.

const Previews := preload("res://admin/previews.gd")
const STANDARD := ["idle", "walk", "attack", "skill", "ultimate", "hit", "death", "victory", "skill2", "run"]
const REQUIRED := ["idle", "attack", "hit", "death"]
const EVENTS := ["hit", "projectile", "sound", "effect"]

var host: Node                 # экран админки: api, _say, _fail
var hero_id := ""
var skel_path := ""
var skin_target := "default"   # в какой скин идут замены частей
var skel: Dictionary = {}
var rig: SkeletonRig
var anim := "idle"
var bone := ""
var t := 0.0
var mode := "rotate"           # rotate | move
var playing := false
var dirty := false

var _stage: ColorRect
var _holder: Node2D
var _marker: Line2D
var _time_slider: HSlider
var _time_label: Label
var _keys_row: HFlowContainer
var _rot: HSlider
var _mx: HSlider
var _my: HSlider
var _sc: HSlider
var _anim_pick: OptionButton
var _bone_pick: OptionButton
var _dur: LineEdit
var _loop: CheckBox
var _events_box: VBoxContainer
var _parts_box: VBoxContainer
var _syncing := false
var _drag := {}


func setup(p_host: Node, p_hero_id: String, p_skel_path: String, p_skel: Dictionary) -> void:
	host = p_host
	hero_id = p_hero_id
	skel_path = p_skel_path
	skel = p_skel.duplicate(true)
	add_theme_constant_override("separation", 8)
	_build()
	var names: Array = skel.get("animations", {}).keys()
	anim = "idle" if names.has("idle") else (str(names[0]) if not names.is_empty() else "idle")
	_select_anim(anim)


# --- Построение -------------------------------------------------------------------------

func _label(text: String, size := 18) -> Label:
	var l := Ui.label(text, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _button(text: String, cb: Callable, size := 18) -> Button:
	var b := Ui.button(text, cb)
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 60)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	return b


func _slider(title: String, lo: float, hi: float, step: float, on_change: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var l := _label(title, 17)
	l.custom_minimum_size = Vector2(150, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(0, 48)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var v := _label("0", 17)
	v.custom_minimum_size = Vector2(80, 0)
	row.add_child(v)
	s.value_changed.connect(func(x):
		v.text = str(snappedf(x, step))
		if not _syncing:
			on_change.call(x))
	add_child(row)
	return s


func _build() -> void:
	_stage = ColorRect.new()
	_stage.color = Color(0.05, 0.04, 0.09)
	_stage.custom_minimum_size = Vector2(680, 460)
	_stage.clip_contents = true
	_stage.gui_input.connect(_on_stage_input)
	add_child(_stage)
	_holder = Node2D.new()
	_holder.position = Vector2(340, 420)
	_stage.add_child(_holder)
	rig = SkeletonRig.new()
	rig.scale = Vector2(1.8, 1.8)
	_holder.add_child(rig)
	rig.setup("heroes/" + hero_id, skel)
	_marker = Line2D.new()
	_marker.width = 3
	_marker.default_color = Color("#FFD24A")
	_marker.points = PackedVector2Array([Vector2.ZERO, Vector2(28, 0)])
	_holder.add_child(_marker)
	add_child(_label("Палец по герою: «Поворот» — крутит выбранную кость, «Сдвиг» — двигает. Ключ ставится в текущий момент времени.", 16))

	var r1 := HBoxContainer.new()
	_anim_pick = OptionButton.new()
	_anim_pick.custom_minimum_size = Vector2(0, 60)
	_anim_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_pick.item_selected.connect(func(i): _select_anim(_anim_pick.get_item_text(i)))
	r1.add_child(_anim_pick)
	_dur = Ui.line_edit("длит., с")
	_dur.custom_minimum_size = Vector2(130, 60)
	_dur.text_submitted.connect(func(_x): _apply_duration())
	_dur.focus_exited.connect(_apply_duration)
	r1.add_child(_dur)
	_loop = CheckBox.new()
	_loop.text = "цикл"
	_loop.toggled.connect(func(on):
		if not _syncing:
			_anim_data()["loop"] = on
			_changed())
	r1.add_child(_loop)
	add_child(r1)

	var r2 := HBoxContainer.new()
	_bone_pick = OptionButton.new()
	_bone_pick.custom_minimum_size = Vector2(0, 60)
	_bone_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for bn in rig.bone_names():
		_bone_pick.add_item(str(bn))
	_bone_pick.item_selected.connect(func(i):
		bone = _bone_pick.get_item_text(i)
		_refresh())
	r2.add_child(_bone_pick)
	var rot_btn := _button("Поворот", func(): pass)
	var mov_btn := _button("Сдвиг", func(): pass)
	rot_btn.toggle_mode = true
	mov_btn.toggle_mode = true
	rot_btn.button_pressed = true
	rot_btn.pressed.connect(func():
		mode = "rotate"
		rot_btn.button_pressed = true
		mov_btn.button_pressed = false)
	mov_btn.pressed.connect(func():
		mode = "move"
		mov_btn.button_pressed = true
		rot_btn.button_pressed = false)
	r2.add_child(rot_btn)
	r2.add_child(mov_btn)
	add_child(r2)
	bone = _bone_pick.get_item_text(0) if _bone_pick.item_count > 0 else ""

	var tr := HBoxContainer.new()
	_time_label = _label("t = 0.00 с", 18)
	_time_label.custom_minimum_size = Vector2(150, 0)
	tr.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.step = 0.01
	_time_slider.custom_minimum_size = Vector2(0, 56)
	_time_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_slider.value_changed.connect(func(x):
		if not _syncing:
			_set_time(x))
	tr.add_child(_time_slider)
	add_child(tr)
	add_child(_label("Ключи выбранной кости (нажмите — перейти):", 16))
	_keys_row = HFlowContainer.new()
	add_child(_keys_row)

	_rot = _slider("Поворот, °", -180, 180, 1, func(v): _set_key("rotate", [v]))
	_mx = _slider("Сдвиг X", -150, 150, 1, func(v): _set_key("translate", [v, _my.value]))
	_my = _slider("Сдвиг Y", -150, 150, 1, func(v): _set_key("translate", [_mx.value, v]))
	_sc = _slider("Масштаб", 0.2, 3.0, 0.01, func(v): _set_key("scale", [v, v]))

	var r3 := HBoxContainer.new()
	r3.add_child(_button("Проиграть / стоп", _toggle_play))
	r3.add_child(_button("Удалить ключ здесь", _delete_key))
	r3.add_child(_button("Сбросить кость", _clear_bone))
	add_child(r3)
	var r4 := HBoxContainer.new()
	r4.add_child(_button("+ Анимация", _add_anim))
	r4.add_child(_button("Удалить анимацию", _delete_anim))
	r4.add_child(_button("Отразить", func(): rig.scale.x = -rig.scale.x))
	add_child(r4)

	add_child(Ui.label("События анимации", 22, "accent"))
	add_child(_label("hit — момент удара, projectile — вылет снаряда; время в секундах.", 16))
	_events_box = VBoxContainer.new()
	add_child(_events_box)
	add_child(_button("+ Событие", func():
		_anim_data().get_or_add("events", []).append({"t": snappedf(t, 0.01), "name": "hit"})
		_changed()
		_render_events()))

	add_child(Ui.label("Части героя", 22, "accent"))
	add_child(_skin_picker())
	_parts_box = VBoxContainer.new()
	add_child(_parts_box)
	_render_parts()
	add_child(_button("+ Добавить часть на выбранную кость", _add_part, 20))
	add_child(_button("Сохранить анимации в черновик", save, 22))


# --- Данные ---------------------------------------------------------------------------------

func _anim_data() -> Dictionary:
	var anims: Dictionary = skel.get_or_add("animations", {})
	if not anims.has(anim):
		anims[anim] = {"duration": 1.0, "bones": {}}
	return anims[anim]


func _tracks() -> Dictionary:
	return _anim_data().get_or_add("bones", {}).get_or_add(bone, {})


func _changed() -> void:
	dirty = true
	rig.data = skel
	rig.pose_at(anim, t)
	_update_marker()


func _select_anim(name: String) -> void:
	anim = name
	_anim_data()
	_syncing = true
	_anim_pick.clear()
	var names: Array = skel["animations"].keys()
	for i in range(names.size()):
		_anim_pick.add_item(str(names[i]))
		if names[i] == anim:
			_anim_pick.selected = i
	var a := _anim_data()
	_dur.text = str(a.get("duration", 1.0))
	_loop.button_pressed = bool(a.get("loop", false))
	_time_slider.max_value = float(a.get("duration", 1.0))
	_syncing = false
	rig.data = skel
	_set_time(0.0)
	_render_events()


func _apply_duration() -> void:
	var d := _dur.text.strip_edges().replace(",", ".")
	if not d.is_valid_float() or float(d) <= 0.05:
		_dur.text = str(_anim_data().get("duration", 1.0))
		return
	_anim_data()["duration"] = snappedf(float(d), 0.01)
	_time_slider.max_value = float(d)
	_changed()


func _set_time(x: float) -> void:
	t = clampf(x, 0.0, float(_anim_data().get("duration", 1.0)))
	rig.pose_at(anim, t)
	_refresh()


func _value(track: String, dims: int, neutral: Array) -> Array:
	var tr: Dictionary = _tracks()
	if not tr.has(track) or (tr[track] as Array).is_empty():
		return neutral
	return SkeletonRig._sample(tr[track], t, dims)


func _refresh() -> void:
	_syncing = true
	_time_slider.value = t
	_time_label.text = "t = %.2f с" % t
	_rot.value = _value("rotate", 1, [0.0])[0]
	var m := _value("translate", 2, [0.0, 0.0])
	_mx.value = m[0]
	_my.value = m[1]
	_sc.value = _value("scale", 2, [1.0, 1.0])[0]
	_syncing = false
	for c in _keys_row.get_children():
		c.queue_free()
	var times := {}
	for track in _tracks().values():
		for k in track:
			times[snappedf(float(k[0]), 0.01)] = true
	var sorted := times.keys()
	sorted.sort()
	for kt in sorted:
		var b := Button.new()
		b.text = "%.2f" % kt
		b.custom_minimum_size = Vector2(84, 48)
		if absf(kt - t) < 0.006:
			b.modulate = Color("#FFD24A")
		b.pressed.connect(func(): _set_time(kt))
		_keys_row.add_child(b)
	if sorted.is_empty():
		var none := _label("— нет ключей, кость в позе покоя", 16)
		none.autowrap_mode = TextServer.AUTOWRAP_OFF
		_keys_row.add_child(none)
	_update_marker()


func _update_marker() -> void:
	var w: Transform2D = rig.transform * rig.bone_world(bone)
	_marker.position = w.origin
	_marker.rotation = w.get_rotation()
	_marker.scale = Vector2(signf(rig.scale.x), 1)


func _set_key(track: String, values: Array) -> void:
	var tr: Dictionary = _tracks()
	var keys: Array = tr.get_or_add(track, [])
	if keys.is_empty() and t > 0.001:
		var neutral: Array = [0.0] if track == "rotate" else ([0.0, 0.0] if track == "translate" else [1.0, 1.0])
		keys.append([0.0] + neutral)  # анимация начинается из позы покоя
	var key: Array = [snappedf(t, 0.01)]
	for v in values:
		key.append(snappedf(float(v), 0.01))
	var idx := -1
	for i in range(keys.size()):
		if absf(float(keys[i][0]) - t) < 0.006:
			idx = i
	if idx >= 0:
		keys[idx] = key
	else:
		keys.append(key)
		keys.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	_changed()
	_refresh()


func _delete_key() -> void:
	var tr: Dictionary = _tracks()
	for track in tr.keys():
		tr[track] = (tr[track] as Array).filter(func(k): return absf(float(k[0]) - t) >= 0.006)
		if (tr[track] as Array).is_empty():
			tr.erase(track)
	_changed()
	_refresh()


func _clear_bone() -> void:
	_anim_data().get_or_add("bones", {}).erase(bone)
	_changed()
	_refresh()


func _toggle_play() -> void:
	playing = not playing
	if playing:
		rig.frozen = false
		rig.play(anim, anim)
	else:
		rig.pose_at(anim, t)


func _process(_delta: float) -> void:
	if playing and is_instance_valid(rig):
		_update_marker()


# --- Пальцем по герою -------------------------------------------------------------------------

func _on_stage_input(ev: InputEvent) -> void:
	if bone == "" or playing:
		return
	var pos: Vector2 = _stage.get_local_mouse_position() - _holder.position
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			var w: Transform2D = rig.transform * rig.bone_world(bone)
			_drag = {"on": true, "start": pos, "angle": (pos - w.origin).angle(), "rot": _rot.value,
					"mx": _mx.value, "my": _my.value, "origin": w.origin}
		else:
			_drag = {}
	elif ev is InputEventMouseMotion and _drag.get("on", false):
		if mode == "rotate":
			var a: float = (pos - _drag["origin"]).angle()
			var delta := rad_to_deg(wrapf(a - float(_drag["angle"]), -PI, PI)) * signf(rig.scale.x)
			_set_key("rotate", [clampf(float(_drag["rot"]) + delta, -180, 180)])
		else:
			# сдвиг в системе координат родителя кости
			var parent := _parent_of(bone)
			var pw: Transform2D = rig.transform * rig.bone_world(parent) if parent != "" else rig.transform
			var d: Vector2 = pw.basis_xform_inv(pos - _drag["start"])
			_set_key("translate", [clampf(float(_drag["mx"]) + d.x, -150, 150), clampf(float(_drag["my"]) + d.y, -150, 150)])


func _parent_of(name: String) -> String:
	for b in skel.get("bones", []):
		if b["name"] == name:
			return str(b.get("parent", ""))
	return ""


# --- Анимации и события ----------------------------------------------------------------------

func _add_anim() -> void:
	var have: Dictionary = skel.get("animations", {})
	for n in STANDARD:
		if not have.has(n):
			have[n] = {"duration": 1.0, "bones": {}}
			_changed()
			_select_anim(n)
			host._say("Добавлена анимация «%s» — поставьте ключи и сохраните" % n)
			return
	host._say("Все стандартные анимации уже есть")


func _delete_anim() -> void:
	if anim in REQUIRED:
		host._say("Ошибка: анимация «%s» обязательна для боя" % anim)
		return
	skel["animations"].erase(anim)
	_changed()
	_select_anim("idle")


func _render_events() -> void:
	for c in _events_box.get_children():
		c.queue_free()
	var evs: Array = _anim_data().get("events", [])
	for e in evs:
		var row := HBoxContainer.new()
		var pick := OptionButton.new()
		pick.custom_minimum_size = Vector2(200, 56)
		for n in EVENTS:
			pick.add_item(n)
		pick.selected = max(0, EVENTS.find(str(e["name"])))
		pick.item_selected.connect(func(i):
			e["name"] = EVENTS[i]
			_changed())
		row.add_child(pick)
		var te := Ui.line_edit("время, с")
		te.text = str(e["t"])
		te.custom_minimum_size = Vector2(140, 56)
		te.text_changed.connect(func(x):
			if x.replace(",", ".").is_valid_float():
				e["t"] = snappedf(float(x.replace(",", ".")), 0.01)
				dirty = true)
		row.add_child(te)
		row.add_child(_button("Сейчас", func():
			e["t"] = snappedf(t, 0.01)
			te.text = str(e["t"])
			dirty = true))
		row.add_child(_button("X", func():
			evs.erase(e)
			_changed()
			_render_events()))
		_events_box.add_child(row)
	if evs.is_empty():
		_events_box.add_child(_label("Событий нет", 16))


# --- Части героя -----------------------------------------------------------------------------

func _part_path(slot: Dictionary) -> String:
	## Куда загружать замену: обычный вид или папка выбранного скина
	if skin_target != "default":
		return "heroes/%s/skins/%s/%s" % [hero_id, skin_target, slot["image"]]
	return "heroes/%s/%s" % [hero_id, slot["image"]]


func _skin_picker() -> Control:
	var hero: Variant = Content.load_json("heroes/%s/hero.json" % hero_id)
	var skins: Array = [{"id": "default", "name": "Обычный вид"}] + (hero.get("skins", []) if hero is Dictionary else [])
	var row := HBoxContainer.new()
	row.add_child(_label("Скин:", 18))
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(0, 56)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(skins.size()):
		pick.add_item(str(skins[i]["name"]))
		if skins[i]["id"] == skin_target:
			pick.selected = i
	pick.item_selected.connect(func(i):
		skin_target = str(skins[i]["id"])
		rig.skin = skin_target
		rig.rebuild(skel)
		_render_parts())
	row.add_child(pick)
	return row


func _render_parts() -> void:
	for c in _parts_box.get_children():
		c.queue_free()
	for slot in skel.get("slots", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = SkeletonRig.load_texture(SkeletonRig.skin_path("heroes/" + hero_id, str(slot["image"]), skin_target))
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var l := _label("%s\nкость %s" % [slot["name"], slot["bone"]], 16)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var dl := _button("Скачать", func(): _download_part(slot), 16)
		dl.custom_minimum_size = Vector2(130, 60)
		dl.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(dl)
		var rp := _button("Заменить", func(): _replace_part(slot), 16)
		rp.custom_minimum_size = Vector2(130, 60)
		rp.size_flags_horizontal = Control.SIZE_FILL
		row.add_child(rp)
		_parts_box.add_child(row)


func _download_part(slot: Dictionary) -> void:
	var path := _part_path(slot)
	var res: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not res.ok:
		host._fail(res)
		return
	Previews.save_file(host, path.get_file(), res.bytes, func(where: String): host._say("Сохранено: " + where))


func _upload_texture(path: String, bytes: PackedByteArray) -> bool:
	host._say("Загрузка…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + path.uri_encode(), bytes)
	if not r.ok:
		host._fail(r)
		return false
	var tex := Previews.texture_from_bytes(bytes, path)
	if tex:
		SkeletonRig._tex_cache[path] = tex  # сразу видно новую картинку
	return true


func _replace_part(slot: Dictionary) -> void:
	Previews.pick_file(host, ["*.png", "*.webp"], func(bytes: PackedByteArray, _name: String):
		if await _upload_texture(_part_path(slot), bytes):
			rig.rebuild(skel)
			_render_parts()
			host._say("Часть «%s» заменена в черновике. Точка вращения та же — если размер другой, поправьте pivot в skeleton.json." % slot["name"]))


func _add_part() -> void:
	if bone == "":
		return
	host._ask("Имя новой части (латиница, например cape2)", "cape2", func(name: String):
		if not name.is_valid_identifier() or name != name.to_lower():
			host._say("Ошибка: имя — латиница в нижнем регистре, цифры и _")
			return
		Previews.pick_file(host, ["*.png", "*.webp"], func(bytes: PackedByteArray, fname: String):
			var image := "rig/%s.%s" % [name, fname.get_extension().to_lower()]
			if not await _upload_texture("heroes/%s/%s" % [hero_id, image], bytes):
				return
			var tex := Previews.texture_from_bytes(bytes, fname)
			var size: Vector2 = tex.get_size() if tex else Vector2(64, 64)
			skel.get_or_add("slots", []).append({"name": name, "bone": bone, "image": image,
					"pivot": [round(size.x / 2.0), round(size.y / 2.0)]})
			_changed()
			rig.rebuild(skel)
			_render_parts()
			host._say("Часть «%s» добавлена на кость %s (рисуется поверх остальных). Сохраните анимации." % [name, bone])))


func save() -> void:
	_apply_duration()
	var bytes := JSON.stringify(skel, "  ").to_utf8_buffer()
	host._say("Сохранение…")
	var r: Dictionary = await host.api.call_api(HTTPClient.METHOD_PUT, "/files?path=" + skel_path.uri_encode(), bytes)
	if r.ok:
		dirty = false
		host._say("Анимации сохранены в черновик. Опубликовать — «Черновик».")
	else:
		host._fail(r)
