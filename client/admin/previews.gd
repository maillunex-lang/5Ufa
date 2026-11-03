extends RefCounted
## Предпросмотр в админке и работа с файлами устройства (выбор ZIP/картинки, сохранение выгрузки).


static func texture_from_bytes(bytes: PackedByteArray, path: String) -> Texture2D:
	var img := Image.new()
	var ext := path.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	if ext == "png":
		err = img.load_png_from_buffer(bytes)
	elif ext == "webp":
		err = img.load_webp_from_buffer(bytes)
	elif ext in ["jpg", "jpeg"]:
		err = img.load_jpg_from_buffer(bytes)
	return ImageTexture.create_from_image(img) if err == OK else null


## Выбрать файл на устройстве. on_picked(bytes: PackedByteArray, name: String)
static func pick_file(owner: Node, filters: Array, on_picked: Callable) -> void:
	var done := func(paths: PackedStringArray):
		if paths.is_empty():
			return
		var bytes := FileAccess.get_file_as_bytes(paths[0])
		if bytes.is_empty():
			push_warning("Не удалось прочитать файл " + paths[0])
			return
		on_picked.call(bytes, paths[0].get_file())
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Выберите файл", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
				PackedStringArray(filters), func(status: bool, paths: PackedStringArray, _f: int):
					if status:
						done.call(paths))
		return
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.filters = PackedStringArray(filters)
	dlg.size = Vector2i(700, 1000)
	owner.add_child(dlg)
	dlg.file_selected.connect(func(p: String):
		done.call(PackedStringArray([p]))
		dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())
	dlg.popup_centered()


## Сохранить файл (выгрузка ZIP). on_saved(где: String)
static func save_file(owner: Node, name: String, bytes: PackedByteArray, on_saved: Callable) -> void:
	var write := func(path: String) -> bool:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			return false
		f.store_buffer(bytes)
		f.close()
		return true
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Сохранить", "", name, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
				PackedStringArray(["*.zip"]), func(status: bool, paths: PackedStringArray, _f: int):
					if status and not paths.is_empty() and write.call(paths[0]):
						on_saved.call(paths[0]))
		return
	var path := OS.get_user_data_dir().path_join(name)
	if write.call(path):
		on_saved.call(path)


## Кнопка «← Админка» поверх экранов игры в предпросмотре
static func add_back_button(tree: SceneTree) -> void:
	if tree.root.has_node("AdminBack"):
		return
	var layer := CanvasLayer.new()
	layer.name = "AdminBack"
	layer.layer = 100
	var b := Button.new()
	b.text = "← Админка"
	b.add_theme_font_size_override("font_size", 18)
	b.position = Vector2(566, 2)
	b.size = Vector2(150, 44)
	b.modulate = Color(1, 1, 1, 0.9)
	b.pressed.connect(func(): tree.change_scene_to_file("res://admin/admin_main.tscn"))
	layer.add_child(b)
	tree.root.add_child(layer)


## Редактор главного экрана: фон и здания, здания перетаскиваются пальцем; координаты пишутся в hub
static func hub_editor(hub: Dictionary) -> Control:
	var k := 680.0 / 720.0
	var h := float(hub.get("background_height", 1400))
	var root := Control.new()
	root.custom_minimum_size = Vector2(680, h * k)
	root.clip_contents = true
	var bg := TextureRect.new()
	bg.texture = Content.load_texture(str(hub.get("background", "")))
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.size = Vector2(680, h * k)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	for b in hub.get("buildings", []):
		var tex := Content.load_texture(str(b["image"]))
		var sz: Vector2 = (tex.get_size() if tex else Vector2(150, 150)) * float(b.get("scale", 1.0)) * k
		var node := TextureRect.new()
		node.texture = tex
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		node.size = sz
		node.position = Vector2(float(b["x"]), float(b["y"])) * k - sz / 2.0
		node.mouse_filter = Control.MOUSE_FILTER_STOP
		var label := Ui.label(str(b.get("title", b["id"])), 18)
		label.position = Vector2(0, sz.y - 24)
		label.size = Vector2(sz.x, 24)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		node.add_child(label)
		var drag := {"on": false, "from": Vector2.ZERO, "start": Vector2.ZERO}
		node.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				drag["on"] = ev.pressed
				drag["from"] = node.get_global_mouse_position()
				drag["start"] = node.position
				node.modulate = Color(1, 1, 0.6) if ev.pressed else Color.WHITE
				if not ev.pressed:
					var center: Vector2 = (node.position + node.size / 2.0) / k
					b["x"] = int(round(clampf(center.x, 0, 720)))
					b["y"] = int(round(maxf(center.y, 0)))
			elif ev is InputEventMouseMotion and drag["on"]:
				node.position = drag["start"] + node.get_global_mouse_position() - drag["from"])
		root.add_child(node)
	return root


static func hero_card(hero: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = Content.load_texture(str(hero.get("art", {}).get("portrait", "")))
	icon.custom_minimum_size = Vector2(150, 150)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var st: Dictionary = hero.get("stats", {})
	var l := Ui.label("%s — %s\n%s · %s · %s\nЗдоровье %d · Атака %d · Защита %d\nНавыков: %d" % [
			hero.get("name", ""), hero.get("title", ""), hero.get("faction", ""), hero.get("role", ""), hero.get("rarity", ""),
			int(st.get("hp", 0)), int(st.get("atk", 0)), int(st.get("def", 0)), hero.get("skills", []).size()], 19)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


## Сцена с героем: тёмный фон, герой стоит по центру. Сам риг — в meta "rig".
static func rig_stage(hero_id: String) -> Control:
	var stage := ColorRect.new()
	stage.color = Color(0.05, 0.04, 0.09)
	stage.custom_minimum_size = Vector2(680, 420)
	var holder := Node2D.new()
	holder.position = Vector2(340, 380)
	stage.add_child(holder)
	var rig := SkeletonRig.new()
	rig.scale = Vector2(1.8, 1.8)
	holder.add_child(rig)
	var hero: Variant = Content.load_json("heroes/%s/hero.json" % hero_id)
	var skel_path := str(hero["art"]["skeleton"]) if hero is Dictionary else "heroes/%s/skeleton.json" % hero_id
	var skel: Variant = Content.load_json(skel_path)
	if skel is Dictionary:
		rig.setup("heroes/" + hero_id, skel)
	stage.set_meta("rig", rig)
	return stage


static func chapter_card(ch: Dictionary, n: int) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	box.add_child(Ui.label("Глава %d. %s — %s" % [n, ch.get("title", ""), ch.get("subtitle", "")], 24, "accent"))
	var map := TextureRect.new()
	map.texture = Content.load_texture("campaign/chapter_%d/map.png" % n)
	if map.texture == null:
		map.texture = Content.load_texture("campaign/chapter_1/map.png")
	map.custom_minimum_size = Vector2(0, 240)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(map)
	var lines := ["Начало: " + str(ch.get("dialogue_start", "")), "Конец: " + str(ch.get("dialogue_end", ""))]
	for s in ch.get("stages", []):
		lines.append("Этап %s: враг %s ×%s · награда %s" % [s.get("id", ""), s.get("enemy", ""), str(s.get("enemy_multiplier", 1)),
				Ui.cost_text(s.get("reward", {}))])
	var l := Ui.label("\n".join(lines), 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(l)
	return panel
