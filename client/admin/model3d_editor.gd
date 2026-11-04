class_name Model3DEditor
extends VBoxContainer
## Загрузка и настройка 3D-модели героя в общем черновике.

const Previews := preload("res://admin/previews.gd")
const EVENTS := ["idle", "walk", "attack", "skill", "ultimate", "hit", "death", "victory"]
const TITLES := {"idle": "Покой", "walk": "Ходьба", "attack": "Атака", "skill": "Навык",
	"ultimate": "Ультимейт", "hit": "Удар по герою", "death": "Поражение", "victory": "Победа"}
const HINTS := {"idle": ["idle", "stand"], "walk": ["walk", "run"], "attack": ["attack", "slash", "punch"],
	"skill": ["skill", "cast", "spell"], "ultimate": ["ultimate", "special"], "hit": ["hit", "hurt", "damage"],
	"death": ["death", "die", "dead"], "victory": ["victory", "win"]}

var host: Node
var hero_id := ""
var skin_id := ""
var model_data: Dictionary = {}
var reports: Array = []
var base_pick: OptionButton
var anim_picks: Dictionary = {}
var impacts: Dictionary = {}
var anchors: Dictionary = {}
var transform_fields: Dictionary = {}
var viewport: SubViewport
var stage: SubViewportContainer
var pivot: Node3D
var camera: Camera3D
var model_root: Node
var player: AnimationPlayer
var base_state: GLTFState
var info: Label
var file_reports: Label
var _dragging := false
var _load_id := 0


func setup(p_host: Node, p_hero_id: String, p_skin_id: String, p_model: Dictionary) -> void:
	host = p_host
	hero_id = p_hero_id
	skin_id = p_skin_id if p_skin_id != "default" else ""
	model_data = p_model.duplicate(true)
	add_theme_constant_override("separation", 10)
	_build()
	_restore()


func _label(value: String, font_size := 18) -> Label:
	var label := Ui.label(value, font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _button(value: String, callback: Callable) -> Button:
	var button := Ui.button(value, callback)
	button.custom_minimum_size = Vector2(0, 65)
	button.add_theme_font_size_override("font_size", 20)
	return button


func _number(value: float, low: float, high: float, step: float) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = low
	field.max_value = high
	field.step = step
	field.value = value
	field.custom_minimum_size = Vector2(120, 55)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return field


func _build() -> void:
	add_child(_label("Загрузите GLB или ZIP с GLB. У нескольких файлов выберите основной; для каждого движения можно выбрать отдельный файл.", 19))
	add_child(_button("Загрузить GLB / ZIP", _choose_file))
	info = _label("Модель ещё не загружена", 17)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info)
	file_reports = _label("", 16)
	add_child(file_reports)
	add_child(_label("Основная модель", 21))
	base_pick = OptionButton.new()
	base_pick.custom_minimum_size = Vector2(0, 62)
	base_pick.fit_to_longest_item = false
	base_pick.clip_text = true
	base_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	base_pick.item_selected.connect(func(_idx): _load_selected())
	add_child(base_pick)
	stage = SubViewportContainer.new()
	stage.custom_minimum_size = Vector2(0, 400)
	stage.stretch = true
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.gui_input.connect(_stage_input)
	add_child(stage)
	viewport = SubViewport.new()
	viewport.size = Vector2i(640, 400)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	stage.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	pivot = Node3D.new()
	world.add_child(pivot)
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.position = Vector3(0, 1, 4)
	world.add_child(camera)
	camera.look_at(Vector3(0, 1, 0))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	world.add_child(light)
	add_child(_label("Проведите пальцем по модели, чтобы повернуть её", 17))
	add_child(_label("Преобразование", 22))
	var defaults: Array = model_data.get("rotation_degrees", [0, 0, 0])
	for spec in [["scale", "Размер", float(model_data.get("scale", 1.0)), 0.01, 100.0, 0.01],
			["height", "Высота", float(model_data.get("height", 0.0)), -100.0, 100.0, 0.05],
			["rx", "Поворот X", float(defaults[0]), -360.0, 360.0, 1.0],
			["ry", "Поворот Y", float(defaults[1]), -360.0, 360.0, 1.0],
			["rz", "Поворот Z", float(defaults[2]), -360.0, 360.0, 1.0]]:
		var row := HBoxContainer.new()
		var title := _label(str(spec[1]))
		title.custom_minimum_size = Vector2(170, 0)
		row.add_child(title)
		var field := _number(float(spec[2]), float(spec[3]), float(spec[4]), float(spec[5]))
		field.value_changed.connect(func(_v): _apply_transform())
		transform_fields[str(spec[0])] = field
		row.add_child(field)
		add_child(row)
	add_child(_label("Анимации и момент удара", 22))
	var role_help := _label("Танк/воин: удар мечом или щитом · стрелок: выстрел · маг/поддержка: заклинание · убийца: выпад. Для всех: стойка, ходьба, попадание, поражение и победа. Нажмите «Сейчас» в момент удара.", 17)
	role_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(role_help)
	for event in EVENTS:
		var row := VBoxContainer.new()
		row.add_child(_label(str(TITLES[event]), 18))
		var selector := OptionButton.new()
		selector.custom_minimum_size = Vector2(0, 55)
		selector.fit_to_longest_item = false
		selector.clip_text = true
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(selector)
		anim_picks[event] = selector
		var buttons := HBoxContainer.new()
		var play := _button("Смотреть", _play.bind(event))
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(play)
		var impact := _number(0, 0, 60000, 50)
		impact.suffix = " мс"
		impacts[event] = impact
		buttons.add_child(impact)
		var mark := _button("Сейчас", func():
			if is_instance_valid(player):
				impact.value = roundi(player.current_animation_position * 1000))
		buttons.add_child(mark)
		row.add_child(buttons)
		add_child(row)
	add_child(_label("Точки крепления", 22))
	for spec in [["projectile", "Откуда снаряд"], ["hit", "Попадание"], ["overhead", "Над головой"]]:
		var key: String = spec[0]
		add_child(_label(str(spec[1])))
		var row := HBoxContainer.new()
		var bones := OptionButton.new()
		bones.fit_to_longest_item = false
		bones.clip_text = true
		bones.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bones.custom_minimum_size = Vector2(180, 55)
		row.add_child(bones)
		var old: Dictionary = model_data.get("anchors", {}).get(key, {})
		var old_offset: Array = old.get("offset", [0, 0, 0])
		var fields := []
		for axis in range(3):
			var f := _number(float(old_offset[axis]), -1000, 1000, 0.05)
			f.prefix = ["X ", "Y ", "Z "][axis]
			row.add_child(f)
			fields.append(f)
		anchors[key] = {"bones": bones, "offset": fields}
		add_child(row)
	add_child(_button("Сохранить 3D-настройки в черновик", _save))


func _stage_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		pivot.rotation.y += event.relative.x * 0.01
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		pivot.rotation.y += event.relative.x * 0.01


func _choose_file() -> void:
	Previews.pick_file(self, ["*.glb", "*.zip"], func(bytes: PackedByteArray, _name: String): _upload(bytes))


func _upload(bytes: PackedByteArray) -> void:
	host._say("Проверка и загрузка модели…")
	var url := "/models3d/%s/upload" % hero_id
	if skin_id != "":
		url += "?skin=" + skin_id.uri_encode()
	var res: Dictionary = await host.api.call_api(HTTPClient.METHOD_POST, url, bytes)
	if not is_inside_tree():
		return
	if not res.ok:
		host._fail(res)
		return
	for report in res.data.get("files", []):
		_add_report(report)
	_refresh_options(true)
	host._say("Файлы загружены в черновик. Выберите основную модель и сохраните настройки.")


func _restore() -> void:
	var paths: Array = []
	if model_data.has("file"):
		paths.append(model_data["file"])
	for anim in model_data.get("animations", {}).values():
		if anim.get("file", "") not in paths:
			paths.append(anim["file"])
	for path in paths:
		var result: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET,
				"/models3d/%s/inspect?path=%s" % [hero_id, str(path).uri_encode()])
		if not is_inside_tree():
			return
		if result.ok:
			_add_report(result.data)
	_refresh_options(false)


func _add_report(report: Dictionary) -> void:
	for i in range(reports.size()):
		if reports[i].get("path") == report.get("path"):
			reports[i] = report
			return
	reports.append(report)


func _refresh_options(guess: bool) -> void:
	var previous_base := ""
	if base_pick.selected >= 0:
		previous_base = str(base_pick.get_item_metadata(base_pick.selected))
	base_pick.clear()
	for report in reports:
		var path := str(report["path"])
		base_pick.add_item(str(report.get("name", path.get_file())) + " · треугольников: %d" % int(report.get("triangles", 0)))
		base_pick.set_item_metadata(base_pick.item_count - 1, path)
	var lines := []
	for report in reports:
		var name := str(report.get("name", str(report["path"]).get_file()))
		var text := "%s: треугольников %d, текстур %d, костей %d, анимаций %d" % [name,
				int(report.get("triangles", 0)), report.get("textures", []).size(), report.get("bones", []).size(), report.get("animations", []).size()]
		for warning in report.get("warnings", []):
			text += "\n  • " + str(warning)
		lines.append(text)
	file_reports.text = "\n".join(lines)
	if reports.is_empty():
		return
	var selected := 0
	for i in range(base_pick.item_count):
		if str(base_pick.get_item_metadata(i)) == (previous_base if previous_base != "" else str(model_data.get("file", ""))):
			selected = i
	if guess and reports.size() > 1 and previous_base == "" and not model_data.has("file"):
		# Пустой выбор не скрывает необходимость явно выбрать основной файл архива.
		base_pick.select(-1)
		info.text = "Выберите основной файл модели из списка."
	else:
		base_pick.select(selected)
		_load_selected()
	_refresh_animations(guess)


func _refresh_animations(guess: bool) -> void:
	for event in EVENTS:
		var pick: OptionButton = anim_picks[event]
		var was_initialized := pick.item_count > 0
		var saved: Dictionary = model_data.get("animations", {}).get(event, {}).duplicate(true)
		if was_initialized and pick.selected > 0:
			saved = pick.get_item_metadata(pick.selected).duplicate(true)
			saved["impact_ms"] = int(impacts[event].value)
		pick.clear()
		pick.add_item("Не выбрано")
		pick.set_item_metadata(0, {})
		var chosen := 0
		for report in reports:
			for clip in report.get("animations", []):
				var path := str(report["path"])
				pick.add_item("%s · %s" % [str(report.get("name", path.get_file())), str(clip)])
				var idx := pick.item_count - 1
				pick.set_item_metadata(idx, {"file": path, "clip": str(clip)})
				if path == str(saved.get("file", "")) and str(clip) == str(saved.get("clip", "")):
					chosen = idx
				elif guess and chosen == 0 and (not was_initialized or not saved.is_empty()):
					var label := (str(clip) + " " + str(report.get("name", ""))).to_lower()
					for hint in HINTS[event]:
						if label.contains(hint):
							chosen = idx
							break
		pick.select(chosen)
		impacts[event].value = int(saved.get("impact_ms", 0))


func _load_selected() -> void:
	if base_pick.selected < 0:
		return
	_load_id += 1
	var current := _load_id
	var path := str(base_pick.get_item_metadata(base_pick.selected))
	var response: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not is_inside_tree() or current != _load_id:
		return
	if not response.ok:
		host._fail(response)
		return
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var err := document.append_from_buffer(response.bytes, "", state)
	if err != OK:
		info.text = "Godot не смог открыть модель (ошибка %d)." % err
		return
	var scene := document.generate_scene(state)
	if scene == null:
		info.text = "Godot не смог построить сцену модели."
		return
	if is_instance_valid(model_root):
		model_root.queue_free()
	model_root = scene
	base_state = state
	pivot.add_child(model_root)
	player = _find_player(model_root)
	_apply_transform()
	var report: Dictionary = reports[base_pick.selected]
	var tex := []
	for item in report.get("textures", []):
		tex.append("%d×%d" % [int(item["width"]), int(item["height"])])
	info.text = "Треугольников: %d · текстуры: %s · костей: %d\n%s" % [int(report.get("triangles", 0)), ", ".join(tex) if not tex.is_empty() else "нет", report.get("bones", []).size(), "\n".join(report.get("warnings", []))]
	_refresh_bones(report.get("bones", []))
	await get_tree().process_frame
	if is_instance_valid(model_root):
		_frame_model()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null


func _find_matches(node: Node, wanted: Node, matches: Array) -> void:
	if (wanted is Skeleton3D and node is Skeleton3D) or (not wanted is Skeleton3D and node.name == wanted.name and node.get_class() == wanted.get_class()):
		matches.append(node)
	for child in node.get_children():
		_find_matches(child, wanted, matches)


func _resolve_clip(target: AnimationPlayer, state: GLTFState, original: String) -> String:
	if target.has_animation(original):
		return original
	var animations: Array = state.get_animations()
	for index in range(animations.size()):
		var entry: GLTFAnimation = animations[index]
		if entry.original_name == original or (entry.original_name == "" and original == "animation_%d" % index):
			if entry.resource_name != "" and target.has_animation(entry.resource_name):
				return entry.resource_name
			var names: PackedStringArray = target.get_animation_list()
			if names.size() == 1:
				return names[0]
	return ""


func _apply_transform() -> void:
	if not is_instance_valid(model_root) or not model_root is Node3D or transform_fields.is_empty():
		return
	var n: Node3D = model_root
	var factor: float = transform_fields["scale"].value
	n.scale = Vector3.ONE * factor
	n.position.y = transform_fields["height"].value
	n.rotation_degrees = Vector3(transform_fields["rx"].value, transform_fields["ry"].value, transform_fields["rz"].value)


func _collect_meshes(node: Node, result: Array) -> void:
	if node is MeshInstance3D and node.mesh:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)


func _frame_model() -> void:
	var meshes := []
	_collect_meshes(model_root, meshes)
	if meshes.is_empty():
		return
	var bounds: AABB = meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes.slice(1):
		bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	var center: Vector3 = bounds.get_center()
	var distance: float = maxf(1.0, maxf(bounds.size.x, bounds.size.y) * 1.5)
	camera.global_position = center + Vector3(0, 0, distance)
	camera.look_at(center)


func _refresh_bones(names: Array) -> void:
	for key in anchors:
		var selector: OptionButton = anchors[key]["bones"]
		selector.clear()
		selector.add_item("Не выбрано")
		selector.add_item("Корень модели")
		selector.set_item_metadata(1, "@root")
		for name in names:
			selector.add_item(str(name))
			selector.set_item_metadata(selector.item_count - 1, str(name))
		var old: String = str(model_data.get("anchors", {}).get(key, {}).get("bone", ""))
		for i in range(1, selector.item_count):
			if str(selector.get_item_metadata(i)) == old:
				selector.select(i)


func _play(event: String) -> void:
	var pick: OptionButton = anim_picks[event]
	if pick.selected <= 0 or not is_instance_valid(model_root):
		return
	var choice: Dictionary = pick.get_item_metadata(pick.selected)
	var path: String = choice["file"]
	if path == str(base_pick.get_item_metadata(base_pick.selected)):
		var resolved := _resolve_clip(player, base_state, str(choice["clip"])) if is_instance_valid(player) else ""
		if resolved != "":
			player.play(resolved)
		else:
			host._say("Анимация не найдена в модели Godot")
		return
	var response: Dictionary = await host.api.call_api(HTTPClient.METHOD_GET, "/files?path=" + path.uri_encode(), null, true)
	if not is_inside_tree() or not response.ok:
		if is_inside_tree():
			host._fail(response)
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(response.bytes, "", state) != OK:
		host._say("Не удалось открыть GLB анимации")
		return
	var source := doc.generate_scene(state)
	if source == null:
		host._say("Не удалось открыть сцену анимации")
		return
	add_child(source)
	var from_player := _find_player(source)
	var clip := _resolve_clip(from_player, state, str(choice["clip"])) if from_player else ""
	if clip == "":
		source.queue_free()
		host._say("Анимация не найдена в отдельном GLB")
		return
	if not is_instance_valid(player):
		player = AnimationPlayer.new()
		model_root.add_child(player)
		player.root_node = NodePath("..")
	var animation: Animation = from_player.get_animation(clip).duplicate(true)
	var root: Node = player.get_node_or_null(player.root_node)
	var source_root: Node = from_player.get_node_or_null(from_player.root_node)
	for i in range(animation.get_track_count()):
		var track: NodePath = animation.track_get_path(i)
		var node_path := NodePath(str(track.get_concatenated_names()))
		var source_node: Node = source_root.get_node_or_null(node_path) if source_root != null else null
		var target_node: Node = root.get_node_or_null(node_path) if root != null else null
		if target_node == null and source_node != null and root != null:
			var matches := []
			_find_matches(root, source_node, matches)
			if matches.size() == 1:
				target_node = matches[0]
		if target_node is Skeleton3D and track.get_subname_count() > 0 and animation.track_get_type(i) in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
			if target_node.find_bone(str(track.get_subname(0))) < 0:
				target_node = null
		if target_node == null:
			source.queue_free()
			host._say("Скелет или пути отдельной анимации не совпадают с моделью. Выберите совместимый GLB.")
			return
		var remapped := str(root.get_path_to(target_node))
		if track.get_subname_count() > 0:
			remapped += ":" + str(track.get_concatenated_subnames())
		animation.track_set_path(i, NodePath(remapped))
	var library := AnimationLibrary.new()
	library.add_animation("preview", animation)
	if player.has_animation_library("ufa_preview"):
		player.remove_animation_library("ufa_preview")
	player.add_animation_library("ufa_preview", library)
	player.play("ufa_preview/preview")
	source.queue_free()


func _save() -> void:
	if base_pick.selected < 0:
		host._say("Сначала выберите основную модель")
		return
	var model := {"file": str(base_pick.get_item_metadata(base_pick.selected)),
		"scale": transform_fields["scale"].value, "height": transform_fields["height"].value,
		"rotation_degrees": [transform_fields["rx"].value, transform_fields["ry"].value, transform_fields["rz"].value],
		"animations": {}, "anchors": {}}
	for event in EVENTS:
		var pick: OptionButton = anim_picks[event]
		if pick.selected > 0:
			var value: Dictionary = pick.get_item_metadata(pick.selected).duplicate(true)
			value["impact_ms"] = int(impacts[event].value)
			model["animations"][event] = value
	for key in anchors:
		var selector: OptionButton = anchors[key]["bones"]
		if selector.selected > 0:
			var fields: Array = anchors[key]["offset"]
			model["anchors"][key] = {"bone": str(selector.get_item_metadata(selector.selected)),
					"offset": [fields[0].value, fields[1].value, fields[2].value]}
	var result: Dictionary = await host.api.call_api(HTTPClient.METHOD_PUT, "/models3d/%s/config" % hero_id, {"skin": skin_id, "model": model})
	if not is_inside_tree():
		return
	if result.ok:
		model_data = model
		host._say("3D-настройки сохранены в черновик. Отправьте черновик на тест.")
	else:
		host._fail(result)
