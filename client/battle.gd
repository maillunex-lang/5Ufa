extends Node3D
## C-3: воспроизведение боя, посчитанного сервером (State.battle_result.events).
## Клиент ничего не считает: двигает фигуры, показывает числа урона и полосы здоровья.
## Модели и анимации: KayKit (CC0), см. docs/licenses.md. Сопоставление ролей и моделей — в content/game.json (visual). Фон пока плоская арена.
## Скорость сейчас только x1; x2 откроется по прогрессу, x4 — VIP (условия не утверждены).

const SPEED := 1.0

var _events: Array = []
var _i := 0
var _t := 0.0
var _units := {}      # id -> {node, hp_label, name_label, max_hp, target, speed, alive}
var _ui: CanvasLayer
var _timer_label: Label
var _result_shown := false
var _result: Dictionary = {}


func _ready() -> void:
	_result = State.battle_result
	_events = _result.get("events", [])
	_build_scene()
	_build_ui()


func _build_scene() -> void:
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH   # ширина арены постоянна в вертикальной ориентации
	cam.fov = 52.0
	cam.position = Vector3(0, 8.5, 11.5)
	add_child(cam)
	cam.look_at(Vector3(0, 0.6, 0.4), Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.36, 0.42, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.environment = e
	add_child(env)
	var floor := MeshInstance3D.new()   # временная площадка арены
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.22, 0.26, 0.2)
	floor.material_override = fm
	add_child(floor)


func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_timer_label = Ui.label("0.0 с  ·  Этап %d  ·  x1" % int(_result.get("stage", 0)), 30)
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer_label.position = Vector2(24, 40)
	_ui.add_child(_timer_label)


const KIND_BY_KEY := {"e_fighter": "melee", "e_shooter": "ranged", "e_mage": "caster", "e_boss": "melee"}
const KIND_BY_ROLE := {"tank": "melee", "melee": "melee", "ranged": "ranged", "mage": "caster", "healer": "caster"}


func _kind(def: Dictionary, key: String) -> String:
	if def.has("role"):
		return KIND_BY_ROLE.get(def["role"], "melee")
	return KIND_BY_KEY.get(key, "melee")


func _spawn(u: Dictionary) -> void:
	var node := Node3D.new()
	node.position = Vector3(float(u["x"]), 0, float(u["y"]))
	var def := State.hero_def(u["key"])
	if def.is_empty():
		def = State.enemy_def(u["key"])
	var vis: Dictionary = def.get("visual", {})
	var model_path := "res://assets/models/%s.glb" % str(vis.get("model", ""))
	var player: AnimationPlayer = null
	var body: Node3D
	if vis.has("model") and ResourceLoader.exists(model_path):
		body = (load(model_path) as PackedScene).instantiate()
		body.scale = Vector3.ONE * float(vis.get("scale", 1.0))
		var found := body.find_children("*", "AnimationPlayer", true, false)
		if found.size() > 0:
			player = found[0]
			for nm in ["Idle", "Idle_Combat", "Running_A"]:
				if player.has_animation(nm):
					player.get_animation(nm).loop_mode = Animation.LOOP_LINEAR
	else:
		# запасной вариант, если модели нет в сборке: капсула
		var m := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.45
		cap.height = 1.5
		m.mesh = cap
		m.position.y = 0.75
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.5, 0.95) if u["side"] == "a" else Color(0.9, 0.3, 0.3)
		m.material_override = mat
		body = m
	var pivot := Node3D.new()   # поворот к противнику: игрок слева смотрит вправо
	pivot.rotation.y = PI / 2.0 if u["side"] == "a" else -PI / 2.0
	pivot.add_child(body)
	node.add_child(pivot)
	var l := Label3D.new()
	l.text = "%d" % int(u["hp"])
	l.modulate = Color(0.6, 0.85, 1.0) if u["side"] == "a" else Color(1.0, 0.65, 0.6)
	l.outline_size = 12
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 40
	l.pixel_size = 0.009
	l.position.y = 2.7 * float(vis.get("scale", 1.0))
	l.no_depth_test = true
	node.add_child(l)
	add_child(node)
	var rec := {"node": node, "pivot": pivot, "anim": player, "label": l, "name": def.get("name", u["key"]), "max_hp": int(u["hp"]),
		"target": null, "speed": 0.0, "alive": true, "busy": 0.0, "kind": _kind(def, u["key"]), "running": false}
	_units[u["id"]] = rec
	_play(rec, "Idle")


## Проигрывает анимацию, если она есть в модели (разные наборы называют их немного по-разному).
func _play(u: Dictionary, anim: String) -> float:
	var p: AnimationPlayer = u["anim"]
	if p == null:
		return 0.0
	if not p.has_animation(anim):
		if anim == "Idle" and p.has_animation("Idle_Combat"):
			anim = "Idle_Combat"
		else:
			return 0.0
	p.play(anim, 0.1)
	return p.get_animation(anim).length


func _face(u: Dictionary, to: Vector3) -> void:
	var d: Vector3 = to - (u["node"] as Node3D).position
	if d.length() > 0.05:
		(u["pivot"] as Node3D).rotation.y = atan2(d.x, d.z)


func _attack_anim(kind: String, strong: bool) -> String:
	match kind:
		"ranged":
			return "1H_Ranged_Shoot"
		"caster":
			return "Spellcast_Long" if strong else "Spellcast_Shoot"
		_:
			return "2H_Melee_Attack_Spin" if strong else "1H_Melee_Attack_Slice_Horizontal"


func _float_text(pos: Vector3, text: String, color: Color, big: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 64 if big else 48
	l.pixel_size = 0.011
	l.no_depth_test = true
	l.position = pos + Vector3(0, 2.8, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 1.4, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _set_hp(id: String, hp: int) -> void:
	if not _units.has(id):
		return
	var u: Dictionary = _units[id]
	(u["label"] as Label3D).text = "%d" % hp


func _apply(e: Dictionary) -> void:
	match e["type"]:
		"start":
			for u in e["units"]:
				_spawn(u)
		"move":
			if _units.has(e["id"]):
				var u: Dictionary = _units[e["id"]]
				u["target"] = Vector3(float(e["to"][0]), 0, float(e["to"][1]))
				u["speed"] = float(e["speed"])
				_face(u, u["target"])
		"attack", "skill":
			if _units.has(e["src"]):
				var u: Dictionary = _units[e["src"]]
				if _units.has(e["dst"]):
					_face(u, (_units[e["dst"]]["node"] as Node3D).position)
				var anim := _attack_anim(u["kind"], e["type"] == "skill")
				var dur := _play(u, anim)
				u["busy"] = maxf(dur, 0.4)
				u["running"] = false
		"damage":
			_set_hp(e["dst"], int(e["hp"]))
			if _units.has(e["dst"]):
				var hu: Dictionary = _units[e["dst"]]
				if hu["alive"] and hu["busy"] <= 0.0 and int(e["hp"]) > 0:
					hu["busy"] = _play(hu, "Hit_A")
				var pos: Vector3 = (_units[e["dst"]]["node"] as Node3D).position
				_float_text(pos, ("%d!" if e.get("crit", false) else "%d") % int(e["amount"]), Color(1, 0.85, 0.2) if e.get("crit", false) else Color(1, 1, 1), e.get("crit", false))
		"heal":
			_set_hp(e["dst"], int(e["hp"]))
			if _units.has(e["dst"]):
				_float_text((_units[e["dst"]]["node"] as Node3D).position, "+%d" % int(e["amount"]), Color(0.4, 1, 0.5), false)
		"death":
			if _units.has(e["id"]):
				var u: Dictionary = _units[e["id"]]
				u["alive"] = false
				u["target"] = null
				u["busy"] = 999.0
				var p: AnimationPlayer = u["anim"]
				if p != null and p.has_animation("Death_A"):
					p.get_animation("Death_A").loop_mode = Animation.LOOP_NONE
					p.play("Death_A", 0.1)
				else:
					var tw := create_tween()
					tw.tween_property(u["node"], "scale", Vector3(1, 0.1, 1), 0.3)
		"end":
			_show_result()


func _process(delta: float) -> void:
	if _result_shown:
		return
	_t += delta * SPEED
	while _i < _events.size() and float(_events[_i]["t"]) <= _t:
		_apply(_events[_i])
		_i += 1
	for id in _units:
		var u: Dictionary = _units[id]
		if not u["alive"]:
			continue
		u["busy"] = maxf(0.0, float(u["busy"]) - delta * SPEED)
		var moving := false
		if u["target"] != null:
			var n: Node3D = u["node"]
			var tgt: Vector3 = u["target"]
			if n.position.distance_to(tgt) > 0.05:
				n.position = n.position.move_toward(tgt, float(u["speed"]) * delta * SPEED)
				moving = true
		if u["busy"] <= 0.0:
			if moving and not u["running"]:
				_play(u, "Running_A")
				u["running"] = true
			elif not moving and (u["running"] or (u["anim"] != null and (u["anim"] as AnimationPlayer).current_animation not in ["Idle", "Idle_Combat"])):
				_play(u, "Idle")
				u["running"] = false
	_timer_label.text = "%.1f с  ·  Этап %d  ·  x1" % [_t, int(_result.get("stage", 0))]


func _show_result() -> void:
	if _result_shown:
		return
	_result_shown = true
	var won: bool = _result.get("winner", "") == "attacker"
	var text := "Победа!" if won else "Поражение"
	if _result.get("timeout", false):
		text += "\nВремя вышло (90 с)"
	var rw: Variant = _result.get("reward")
	if rw != null:
		text += "\nНаграда за первую победу:\nзолото %d, опыт героев %d" % [int(rw.get("gold", 0)), int(rw.get("hero_exp", 0))]
	elif won:
		text += "\n(награда за этот этап уже получена)"
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var p := Ui.panel(Color(0.14, 0.16, 0.22))
	p.custom_minimum_size = Vector2(600, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 24)
	p.add_child(v)
	v.add_child(Ui.label(text, 40))
	var back := Ui.button("Вернуться в кампанию", 32, 100)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://hub.tscn"))
	v.add_child(back)
	_ui.add_child(overlay)
