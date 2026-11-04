class_name UnitModel3D
extends Node2D
## Боец с GLB вместо 2D-скелета. Вид сбоку, без тун-шейдера и теней.
## Временный посох Хыухылу крепится к кости кисти и едет вместе с ней.

const VIEW_H := 220.0

var speed := 1.0
var current := ""
var staff_bone := ""

var _model: Dictionary = {}
var _clips: Dictionary = {}
var _after := ""
var _viewport: SubViewport
var _sprite: Sprite2D
var _camera: Camera3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _model_root: Node3D


func setup(model: Dictionary, hero_id: String) -> bool:
	var path := str(model.get("file", ""))
	if path == "" or not Content.has_file(path):
		return false
	var bytes := FileAccess.get_file_as_bytes(Content.local_path(path))
	return load_bytes(bytes, model, hero_id)


func load_bytes(bytes: PackedByteArray, model: Dictionary, hero_id: String) -> bool:
	if bytes.size() < 20 or bytes.slice(0, 4).get_string_from_utf8() != "glTF":
		return false
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes, "", state) != OK:
		return false
	var scene := document.generate_scene(state)
	if scene == null or not scene is Node3D:
		if scene:
			scene.free()
		return false
	_model = model
	_build_view()
	_model_root = scene
	_viewport.get_child(0).add_child(_model_root)
	_apply_author_transform()
	_player = _find_player(_model_root)
	_skeleton = _find_skeleton(_model_root)
	if _player and not _player.animation_finished.is_connected(_on_finished):
		_player.animation_finished.connect(_on_finished)
	_map_clips(str(model.get("file", "")))
	var bounds := _bounds(_model_root)
	if hero_id == "hyuhylu" and _skeleton:
		staff_bone = attach_staff(_skeleton, maxf(bounds.size.y, 0.2))
	_frame(bounds, float(model.get("scale", 1.0)))
	play("idle")
	return true


func play(anim: String, after := "idle") -> void:
	current = anim
	if _player == null:
		return
	var clip := str(_clips.get(anim, _clips.get("idle", "")))
	if clip == "":
		return
	var looping := anim == "idle" or anim == "walk"
	var animation := _player.get_animation(clip)
	if animation:
		animation.loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	_after = "" if looping else after
	_player.speed_scale = speed
	_player.play(clip)


func anchor_position(anchor: String) -> Vector2:
	var local := Vector2(0, -120)
	var spec: Dictionary = _model.get("anchors", {}).get(anchor, {})
	if not spec.is_empty() and _camera and is_instance_valid(_model_root):
		var point := _model_root.global_position
		var bone_name := str(spec.get("bone", ""))
		if _skeleton and bone_name != "" and bone_name != "@root":
			var idx := _skeleton.find_bone(bone_name)
			if idx >= 0:
				point = _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin
		var off: Variant = spec.get("offset", [])
		if off is Array and off.size() == 3:
			point += Vector3(float(off[0]), float(off[1]), float(off[2]))
		local = _viewport_to_local(_camera.unproject_position(point))
	return transform * local


func attach_staff(skeleton: Skeleton3D, model_height: float) -> String:
	var bone := _pick_hand(skeleton)
	if bone == "":
		return ""
	var attachment := BoneAttachment3D.new()
	attachment.name = "StaffAttachment"
	attachment.bone_name = bone
	skeleton.add_child(attachment)
	var length := maxf(0.35, model_height * 0.9)
	var shaft := MeshInstance3D.new()
	shaft.name = "TemporaryStaff"
	var mesh := CylinderMesh.new()
	mesh.top_radius = length * 0.015
	mesh.bottom_radius = length * 0.022
	mesh.height = length
	shaft.mesh = mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6B3E26")
	shaft.material_override = wood
	shaft.position = Vector3(0, length * 0.28, 0)
	attachment.add_child(shaft)
	var head := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = length * 0.055
	ball.height = length * 0.11
	head.mesh = ball
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color("D4A24C")
	head.material_override = gold
	head.position = Vector3(0, length * 0.52, 0)
	shaft.add_child(head)
	return bone


func _process(_delta: float) -> void:
	if _player:
		_player.speed_scale = speed


func _on_finished(_anim: StringName) -> void:
	if _after != "":
		var next := _after
		_after = ""
		play(next)


func _build_view() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(256, 340)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.8, 0.84)
	env.ambient_light_energy = 1.0
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	var weather := WorldEnvironment.new()
	weather.environment = env
	world.add_child(weather)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	world.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.add_child(_camera)
	_sprite = Sprite2D.new()
	_sprite.texture = _viewport.get_texture()
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.scale = Vector2.ONE * (VIEW_H / float(_viewport.size.y))
	add_child(_sprite)


func _apply_author_transform() -> void:
	var factor := float(_model.get("scale", 1.0))
	_model_root.scale = Vector3.ONE * factor
	_model_root.position.y = float(_model.get("height", 0.0))
	var rotation: Variant = _model.get("rotation_degrees", [0, 0, 0])
	if rotation is Array and rotation.size() == 3:
		_model_root.rotation_degrees = Vector3(float(rotation[0]), float(rotation[1]), float(rotation[2]))


func _map_clips(main_file: String) -> void:
	var animations: Dictionary = _model.get("animations", {})
	for role in ["idle", "walk", "attack", "skill", "ultimate", "hit", "death", "victory"]:
		var spec: Variant = animations.get(role, {})
		if not spec is Dictionary or spec.is_empty():
			continue
		var clip := _pull_clip(str(spec.get("file", main_file)), str(spec.get("clip", "")), main_file)
		if clip != "":
			_clips[role] = clip
	if not _clips.has("idle") and _player and _player.get_animation_list().size() == 1:
		_clips["idle"] = _player.get_animation_list()[0]


func _pull_clip(file: String, wanted: String, main_file: String) -> String:
	if file == "" or file == main_file or not Content.has_file(file):
		return _match_clip(_player, wanted)
	var bytes := FileAccess.get_file_as_bytes(Content.local_path(file))
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes, "", state) != OK:
		return ""
	var scene := document.generate_scene(state)
	if scene == null:
		return ""
	var source := _find_player(scene)
	var clip := _match_clip(source, wanted)
	if clip == "" or source == null:
		scene.free()
		return ""
	if _player == null:
		_player = AnimationPlayer.new()
		_model_root.add_child(_player)
		_player.animation_finished.connect(_on_finished)
	var unique := "ext_%s" % wanted
	_player.add_animation(unique, source.get_animation(clip).duplicate(true))
	scene.free()
	return unique


func _frame(bounds: AABB, scale_factor: float) -> void:
	if bounds.size.y <= 0.001:
		_sprite.position = Vector2(0, -VIEW_H * 0.5)
		return
	var center := bounds.get_center()
	var natural_h := bounds.size.y / maxf(scale_factor, 0.001)
	_camera.size = maxf(0.2, natural_h * 1.35 / maxf(scale_factor, 0.001))
	_camera.global_position = center + Vector3(maxf(bounds.size.x, natural_h), 0, 0)
	_camera.look_at(center, Vector3.UP)
	var feet := _camera.unproject_position(Vector3(center.x, bounds.position.y, center.z))
	var feet_local := (feet - Vector2(_viewport.size) * 0.5) * _sprite.scale
	_sprite.position = Vector2(-feet_local.x, -feet_local.y)


func _viewport_to_local(px: Vector2) -> Vector2:
	return _sprite.position + (px - Vector2(_viewport.size) * 0.5) * _sprite.scale


func _bounds(node: Node) -> AABB:
	var found := false
	var bounds := AABB()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(node, meshes)
	for mesh in meshes:
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	return bounds


func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh:
		result.append(node)
	for child in node.get_children():
		_collect_meshes(child, result)


func _pick_hand(skeleton: Skeleton3D) -> String:
	var best := ""
	var best_score := 0
	for idx in skeleton.get_bone_count():
		var raw := skeleton.get_bone_name(idx)
		var name := raw.to_lower().replace(" ", "").replace("_", "").replace("-", "").replace(":", "")
		if name.begins_with("mixamorig"):
			name = name.trim_prefix("mixamorig")
		var score := 0
		if "hand" in name or "wrist" in name:
			score = 1
		if "right" in name or name.ends_with("r") or ".r" in raw.to_lower():
			score += 2
		if "left" in name:
			score = 1
		if score > best_score:
			best_score = score
			best = raw
	return best


func _match_clip(player: AnimationPlayer, wanted: String) -> String:
	if player == null or wanted == "":
		return ""
	if player.has_animation(wanted):
		return wanted
	for name in player.get_animation_list():
		if str(name).to_lower() == wanted.to_lower():
			return name
	return ""


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null
