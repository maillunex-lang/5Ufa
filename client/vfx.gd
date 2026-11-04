class_name Vfx
extends RefCounted
## Эффекты боя на спрайтах Kenney Particle Pack (CC0, assets/vfx): светящиеся плоскости, всегда повёрнутые к камере.
## Всё создаётся кодом и само удаляется; параметры стилей приходят из данных (ability.vfx, hero.visual).

static var _tex_cache := {}
static var _mesh: QuadMesh


static func _texture(tex_name: String) -> Texture2D:
	if not _tex_cache.has(tex_name):
		var path := "res://assets/vfx/%s.png" % tex_name
		_tex_cache[tex_name] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[tex_name]


static func sprite(parent: Node3D, tex_name: String, color: Color, size: float, pos: Vector3, additive: bool = true) -> MeshInstance3D:
	if _mesh == null:
		_mesh = QuadMesh.new()
	var m := MeshInstance3D.new()
	m.mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true   # иначе Godot сбрасывает пропорции (полосы здоровья становятся квадратами)
	mat.no_depth_test = true
	mat.albedo_texture = _texture(tex_name)
	mat.albedo_color = color
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.scale = Vector3.ONE * size
	m.position = pos
	parent.add_child(m)
	return m


## Плавно гасит спрайт (рост/подъём) и удаляет.
static func fade(m: MeshInstance3D, dur: float, grow: float = 1.0, rise: float = 0.0) -> void:
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "scale", m.scale * grow, dur)
	if rise != 0.0:
		tw.tween_property(m, "position:y", m.position.y + rise, dur)
	tw.tween_property(m.material_override, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(m.queue_free)


static func cast_glow(parent: Node3D, pos: Vector3, color: Color) -> void:
	fade(sprite(parent, "magic_05", color, 2.0, pos), 0.45, 1.5)
	fade(sprite(parent, "star_04", Color(1, 1, 1, 0.9), 1.0, pos), 0.35, 1.8)


## Магический снаряд (базовая атака магов и лечение): светящийся шар со следом.
static func bolt(parent: Node3D, from: Vector3, to: Vector3, color: Color, dur: float, on_hit: Callable = Callable()) -> void:
	var head := sprite(parent, "magic_05", color, 1.5, from)
	var core := sprite(parent, "magic_05", Color(1, 1, 1, 0.95), 0.7, from)
	var tw := head.create_tween()
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(to, t) + Vector3(0, sin(t * PI) * 0.5, 0)
		head.position = p
		core.position = p
		fade(sprite(parent, "magic_05", color, 0.6, p), 0.3, 0.2), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		head.queue_free()
		core.queue_free()
		bolt_hit(parent, to, color)
		if on_hit.is_valid():
			on_hit.call())


static func bolt_hit(parent: Node3D, pos: Vector3, color: Color) -> void:
	fade(sprite(parent, "star_04", color.lightened(0.4), 1.2, pos), 0.35, 1.7)
	fade(sprite(parent, "circle_02", color, 0.4, pos), 0.4, 4.0)
	for i in 4:
		var off := Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.5), randf_range(-0.2, 0.2))
		fade(sprite(parent, "star_04", color.lightened(0.3), 0.45, pos + off), 0.35, 0.3, 0.4)


## Огненная комета: летит дугой от мага к цели, оставляя огненный след, взрыв при ударе.
static func comet(parent: Node3D, from: Vector3, to: Vector3, color: Color, dur: float, start_delay: float = 0.0, on_hit: Callable = Callable()) -> void:
	var head := sprite(parent, "magic_05", color, 3.0, from)
	var core := sprite(parent, "fire_01", Color(1, 0.9, 0.55), 1.4, from)
	head.visible = false
	core.visible = false
	var tw := head.create_tween()
	if start_delay > 0.0:
		tw.tween_interval(start_delay)
	tw.tween_callback(func() -> void:
		head.visible = true
		core.visible = true)
	tw.tween_method(func(t: float) -> void:
		var p := from.lerp(to, t) + Vector3(0, sin(t * PI) * 3.2, 0)
		head.position = p
		core.position = p
		var flame := sprite(parent, "flame_05", color.lightened(0.15), 1.3, p)
		fade(flame, 0.4, 0.15, 0.25)
		if randf() < 0.55:
			fade(sprite(parent, "smoke_04", Color(0.3, 0.2, 0.18, 0.5), 0.9, p, false), 0.6, 1.8, 0.5)
		if randf() < 0.5:
			fade(sprite(parent, "magic_05", Color(1, 0.75, 0.35), 0.55, p + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), 0)), 0.3, 0.3), 0.0, 1.0, dur)
	tw.tween_callback(func() -> void:
		head.queue_free()
		core.queue_free()
		comet_impact(parent, to, color)
		if on_hit.is_valid():
			on_hit.call())


static func comet_impact(parent: Node3D, pos: Vector3, color: Color) -> void:
	fade(sprite(parent, "circle_02", color, 0.6, pos), 0.5, 8.0)
	fade(sprite(parent, "fire_02", Color(1, 0.65, 0.25), 2.2, pos + Vector3(0, 0.2, 0)), 0.55, 1.7)
	fade(sprite(parent, "flame_04", color, 2.4, pos + Vector3(0, 0.6, 0)), 0.7, 1.2, 0.9)
	fade(sprite(parent, "magic_05", Color(1, 0.8, 0.5, 0.95), 4.5, pos), 0.4, 1.4)
	for i in 8:
		var off := Vector3(randf_range(-0.7, 0.7), randf_range(0.0, 0.8), randf_range(-0.3, 0.3))
		fade(sprite(parent, "magic_05", Color(1, 0.8, 0.4), 0.5, pos + off), 0.5, 0.3, randf_range(0.4, 1.1))
	fade(sprite(parent, "smoke_06", Color(0.25, 0.2, 0.2, 0.65), 1.8, pos + Vector3(0, 0.5, 0), false), 1.0, 1.9, 1.3)


## Лечение: зелёные искры поднимаются над целью.
static func heal_hit(parent: Node3D, pos: Vector3, color: Color) -> void:
	fade(sprite(parent, "circle_02", color, 0.5, pos + Vector3(0, 0.1, 0)), 0.6, 4.0)
	for i in 6:
		var off := Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.6), randf_range(-0.2, 0.2))
		fade(sprite(parent, "star_04", color.lightened(0.35), 0.5, pos + off), 0.8, 0.5, randf_range(0.8, 1.6))
