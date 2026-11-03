class_name UnitView
extends Node2D
## Боец на поле: герой (SkeletonRig) + полоски здоровья/энергии/щита + значки состояний.

const BAR_W := 70.0

var uid := 0
var side := 0
var info: Dictionary = {}
var rig: SkeletonRig
var x_units := 0.0
var vx := 0.0
var hp := 0
var max_hp := 1
var energy := 0
var energy_max := 1000
var shield := 0
var stunned_until := -1
var dead := false

var _hp_fill: ColorRect
var _hp_back: ColorRect
var _shield_fill: ColorRect
var _en_fill: ColorRect
var _bars: Node2D
var _status: Label
var _floats := 0  # сколько цифр сейчас висит — раскладываем их лесенкой


func setup(u: Dictionary, e_max: int) -> void:
	info = u
	uid = int(u["uid"])
	side = int(u["side"])
	max_hp = int(u["max_hp"])
	hp = max_hp
	energy = int(u.get("energy", 0))
	energy_max = e_max
	x_units = float(u["x"])
	var hero_dir := "heroes/" + str(u["hero"])
	var hero: Variant = Content.load_json(hero_dir + "/hero.json")
	var skel_path := str(hero["art"]["skeleton"]) if hero is Dictionary else hero_dir + "/skeleton.json"
	rig = SkeletonRig.new()
	add_child(rig)
	rig.setup(hero_dir, Content.load_json(skel_path))
	if side == 1:
		rig.scale.x = -1  # враги смотрят влево
	_bars = Node2D.new()
	_bars.position = Vector2(-BAR_W / 2, -150)
	add_child(_bars)
	_hp_back = _rect(Vector2(BAR_W, 9), Color(0, 0, 0, 0.75), Vector2.ZERO)
	_hp_fill = _rect(Vector2(BAR_W - 2, 7), Color("#5BD15B") if side == 0 else Color("#E2504A"), Vector2(1, 1))
	_shield_fill = _rect(Vector2(0, 3), Color("#8FD3FF"), Vector2(1, 1))
	_rect(Vector2(BAR_W, 5), Color(0, 0, 0, 0.75), Vector2(0, 10))
	_en_fill = _rect(Vector2(0, 3), Color("#F2B544"), Vector2(1, 11))
	_status = Label.new()
	_status.position = Vector2(0, -26)
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Color("#FFE27A"))
	_bars.add_child(_status)
	_refresh()


func _rect(size: Vector2, color: Color, pos: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.size = size
	r.color = color
	r.position = pos
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(r)
	return r


func _refresh() -> void:
	_hp_fill.size.x = (BAR_W - 2) * clampf(float(hp) / max_hp, 0, 1)
	_shield_fill.size.x = (BAR_W - 2) * clampf(float(shield) / max_hp, 0, 1)
	_en_fill.size.x = (BAR_W - 2) * clampf(float(energy) / energy_max, 0, 1)
	_bars.visible = not dead


func set_hp(v: int) -> void:
	hp = v
	_refresh()


func set_energy(v: int) -> void:
	energy = v
	_refresh()


func set_shield(v: int) -> void:
	shield = v
	_refresh()


func set_status(text: String) -> void:
	_status.text = text


func die() -> void:
	dead = true
	vx = 0
	rig.play("death", "")
	_refresh()


## Всплывающая цифра (урон, лечение) над героем
func float_text(text: String, color: Color, big := false, speed := 1.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 34 if big else 24)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.12))
	l.add_theme_constant_override("outline_size", 6)
	var lane := _floats % 4
	_floats += 1
	l.position = Vector2(-34 + (lane % 2) * 30 + randf_range(-6, 6), -175 - lane * 26)
	l.z_index = 100
	add_child(l)
	var tw := create_tween().set_speed_scale(speed)
	tw.tween_property(l, "position:y", l.position.y - 46, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8).set_delay(0.3)
	tw.tween_callback(func():
		l.queue_free()
		_floats = max(0, _floats - 1))


func flash(color: Color, speed := 1.0) -> void:
	var tw := create_tween().set_speed_scale(speed)
	rig.modulate = color
	tw.tween_property(rig, "modulate", Color(1, 1, 1, rig.modulate.a), 0.25)
