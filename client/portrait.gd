class_name Portrait
extends RefCounted
## Портрет героя для карточки: один раз рисуется из его же 3D-модели (голова и плечи) в отдельной сцене.
## Никакой дополнительной графики не нужно: меняется модель — меняется портрет.

static func make(host: Node, model_path: String, yaw_deg: float = 0.0) -> Texture2D:
	if not ResourceLoader.exists(model_path):
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 300)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)

	var model: Node3D = (load(model_path) as PackedScene).instantiate()
	vp.add_child(model)
	model.rotation.y = deg_to_rad(yaw_deg)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.size() > 0:
		var p: AnimationPlayer = found[0]
		for n in ["Idle", "Idle_11", "Idle_Combat"]:
			if p.has_animation(n):
				p.play(n)
				p.seek(0.4, true)
				p.pause()
				break

	var box := _bounds(model)
	var h: float = maxf(box.size.y, 0.1)
	# окно кадра считаем от размера головы: у моделей с большой головой (KayKit) и нормальными пропорциями (Meshy) лицо целиком
	var head_y := _head_y(model)
	var top := box.end.y
	var center_y := top - h * 0.2
	var window := h * 0.52
	if not is_nan(head_y) and top > head_y:
		var head_h := top - head_y
		window = clampf(head_h * 1.35, h * 0.3, h * 0.7)
		center_y = head_y + head_h * 0.45
	var focus := Vector3(box.get_center().x, center_y, box.get_center().z)
	var cam := Camera3D.new()
	cam.fov = 28.0   # вертикальный угол
	vp.add_child(cam)
	var dist := (window * 0.5) / tan(deg_to_rad(14.0))
	cam.position = focus + Vector3(0, window * 0.05, dist)
	cam.look_at(focus, Vector3.UP)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 20, 0)
	vp.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 0.8
	env.environment = e
	vp.add_child(env)
	return vp.get_texture()


## Габариты персонажа по скелету (сетка включает мечи, щиты и другие предметы и искажает рамку).
## Верх головы: кость макушки, если она есть (Mixamo/Meshy), иначе голова + 1,3 расстояния от таза до головы (KayKit).
static func _bounds(root: Node3D) -> AABB:
	var bone := _bone_box(root)
	return bone if bone.size.y > 0.01 else _mesh_box(root)


static func _head_y(root: Node3D) -> float:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return NAN
	var sk := skeletons[0] as Skeleton3D
	for i in sk.get_bone_count():
		var nm := sk.get_bone_name(i).to_lower()
		if nm.ends_with("head"):
			return (sk.global_transform * sk.get_bone_global_pose(i)).origin.y
	return NAN


static func _mesh_box(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var a: AABB = mi.global_transform * mi.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


static func _bone_box(root: Node3D) -> AABB:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return AABB()
	var sk := skeletons[0] as Skeleton3D
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	var has_top := false
	var head_y := NAN
	var hips_y := NAN
	for i in sk.get_bone_count():
		var pos := (sk.global_transform * sk.get_bone_global_pose(i)).origin
		var nm := sk.get_bone_name(i).to_lower()
		lo = lo.min(pos)
		hi = hi.max(pos)
		if nm.contains("top"):
			has_top = true
		elif nm.ends_with("head"):
			head_y = pos.y
		elif nm.ends_with("hips") or nm.ends_with("pelvis"):
			hips_y = pos.y
	if not has_top and not is_nan(head_y) and not is_nan(hips_y) and head_y > hips_y:
		hi.y = maxf(hi.y, head_y + (head_y - hips_y) * 1.3)
	elif not has_top:
		hi.y += (hi.y - lo.y) * 0.14
	return AABB(lo, hi - lo)
