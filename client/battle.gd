extends Node3D
## Воспроизведение боя, посчитанного сервером (State.battle_result.events). Клиент ничего не считает:
## двигает бойцов, играет анимации и эффекты, показывает полосы здоровья/энергии.
##
## Вид: низкая камера почти сбоку, два отряда друг напротив друга, рисованный фон, нижняя панель героев.
## Модели и анимации: KayKit (CC0), эффекты: Kenney Particle Pack (CC0), фон: OpenGameArt (CC0). См. docs/licenses.md.
## Фон и портреты — ВРЕМЕННЫЕ. Скорость только x1 (x2 по прогрессу, x4 VIP — условия не утверждены).
##
## Стиль атаки задаётся данными: ability.vfx.style ("fire_comet", "magic_bolt"), иначе hero.visual.attack_style
## ("magic" | "melee" | "ranged"), иначе по роли: маги и целитель бьют магией, а не руками.

const SPEED := 1.0
const TIME_LIMIT := 90.0
const DEPTH := 1.8   # растяжение арены по глубине для экрана (на сервере координаты не меняются)
const CAM_POS := Vector3(0, 8.0, 11.2)    # угол около 35° над землёй, вид сбоку
const CAM_LOOK := Vector3(0, 0.9, 0.6)
const CAM_FOV := 54.0
## Логические анимации -> названия внутри модели. Эти — для KayKit. Для другой модели (например из Meshy) в данных героя:
##   visual.anims      {"idle": "<название в модели>", ...}  — переопределить названия
##   visual.anim_files {"run": "res://assets/models/X_run.glb", ...} — взять анимацию из отдельного файла с тем же скелетом
const DEFAULT_ANIMS := {
	"idle": "Idle", "idle_alt": "Idle_Combat", "run": "Running_A",
	"attack_melee": "1H_Melee_Attack_Slice_Horizontal", "attack_melee_strong": "2H_Melee_Attack_Spin",
	"attack_ranged": "1H_Ranged_Shoot", "cast": "Spellcast_Shoot", "cast_strong": "Spellcast_Long",
	"hit": "Hit_A", "death": "Death_A",
}
## Если нужной анимации нет в модели, пробуем эти (по порядку).
const ANIM_FALLBACKS := {
	"idle": ["idle_alt"], "cast_strong": ["cast", "attack_melee"], "cast": ["attack_ranged", "attack_melee"],
	"attack_melee_strong": ["attack_melee"], "attack_ranged": ["cast", "attack_melee"],
}
const KIND_BY_KEY := {"e_fighter": "melee", "e_shooter": "ranged", "e_mage": "caster", "e_boss": "melee"}
const KIND_BY_ROLE := {"tank": "melee", "melee": "melee", "ranged": "ranged", "mage": "caster", "healer": "caster"}

var _events: Array = []
var _i := 0
var _t := 0.0
var _units := {}          # id -> запись бойца
var _cards := {}          # id -> элементы карточки внизу
var _pending: Array = []  # отложенные действия: {due, fn}
var _max_due := 0.0
var _delay_map := {}      # "t|src|dst" -> задержка попадания (полёт снаряда)
var _dst_delay := {}      # "t|dst" -> задержка для смерти
var _abilities := {}      # id умения -> описание из контента
var _cam: Camera3D
var _hud: CanvasLayer
var _timer_label: Label
var _cards_box: HBoxContainer
var _banner_layer: Control
var _result_shown := false
var _result: Dictionary = {}
var _toast: Label
var _cam_tween: Tween


func _ready() -> void:
	_result = State.battle_result
	_events = _result.get("events", [])
	for d in State.content.get("heroes", []) + State.content.get("enemies", []):
		for a in d.get("abilities", []):
			_abilities[a["id"]] = a
	_build_scene()
	_build_hud()


# ---------------------------------------------------------------- сцена

func _build_scene() -> void:
	_cam = Camera3D.new()
	_cam.keep_aspect = Camera3D.KEEP_WIDTH   # ширина сцены постоянна в вертикальной ориентации
	_cam.fov = CAM_FOV
	_cam.position = CAM_POS
	add_child(_cam)
	_cam.look_at(CAM_LOOK, Vector3.UP)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CANVAS   # рисованный фон лежит на слое под 3D
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)

	# Фон: картина на всю высоту экрана под 3D-сценой
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)
	var tex_path := "res://assets/backgrounds/arena_wizardtower.png"
	if ResourceLoader.exists(tex_path):
		var tr := TextureRect.new()
		tr.texture = load(tex_path)
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_layer.add_child(tr)
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.2, 0.3, 0.2)
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg_layer.add_child(cr)

	# Земля: прозрачная, показывает только тени бойцов на картине
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0, 0, 0, 1)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.shadow_to_opacity = true
	floor.material_override = fm
	add_child(floor)


# ---------------------------------------------------------------- интерфейс

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_hud)

	_timer_label = Ui.label("1:30", 38)
	_timer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_timer_label.custom_minimum_size = Vector2(720, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.position = Vector2(0, 28)
	_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_timer_label.add_theme_constant_override("outline_size", 8)
	_hud.add_child(_timer_label)
	var stage := Ui.label("Глава 1 · Этап %d" % int(_result.get("stage", 0)), 26, Color(1, 1, 1, 0.85))
	stage.autowrap_mode = TextServer.AUTOWRAP_OFF
	stage.custom_minimum_size = Vector2(720, 0)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.position = Vector2(0, 76)
	stage.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	stage.add_theme_constant_override("outline_size", 6)
	_hud.add_child(stage)

	# Кнопки: пауза и скорость (x2/x4 пока закрыты)
	var pause := Ui.button("II", 34, 84)
	pause.custom_minimum_size = Vector2(96, 84)
	pause.position = Vector2(20, 1030)
	pause.pressed.connect(_toggle_pause)
	_hud.add_child(pause)
	var speed := Ui.button("x1", 34, 84)
	speed.custom_minimum_size = Vector2(110, 84)
	speed.position = Vector2(590, 1030)
	speed.pressed.connect(func(): _show_toast("Скорость x2 откроется по прогрессу, x4 — VIP (условия пока не утверждены)"))
	_hud.add_child(speed)

	# Нижняя панель героев
	var bar := Ui.panel(Color(0.09, 0.08, 0.12, 0.92))
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -170
	_hud.add_child(bar)
	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	bar.add_child(_cards_box)

	_banner_layer = Control.new()
	_banner_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_banner_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_banner_layer)

	_toast = Ui.label("", 26)
	_toast.visible = false
	_toast.position = Vector2(40, 940)
	_toast.custom_minimum_size = Vector2(640, 0)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_toast.add_theme_constant_override("outline_size", 8)
	_hud.add_child(_toast)


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused


func _show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.8)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func(): _toast.visible = false)


func _make_card(u: Dictionary, rec: Dictionary) -> void:
	var p := Ui.panel(Color(0.2, 0.22, 0.3))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cards_box.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	# ВРЕМЕННО: вместо портрета — цветная плашка с именем
	var name_l := Ui.label(str(rec["name"]), 19)
	name_l.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_l.clip_text = true
	v.add_child(name_l)
	var portrait := ColorRect.new()
	portrait.color = rec["color"]
	portrait.custom_minimum_size = Vector2(0, 54)
	v.add_child(portrait)
	var hp := ProgressBar.new()
	hp.custom_minimum_size = Vector2(0, 14)
	hp.show_percentage = false
	hp.max_value = float(rec["max_hp"])
	hp.value = float(rec["max_hp"])
	hp.add_theme_stylebox_override("fill", Ui.box(Color(0.3, 0.8, 0.35), 4))
	v.add_child(hp)
	var en := ProgressBar.new()
	en.custom_minimum_size = Vector2(0, 10)
	en.show_percentage = false
	en.max_value = 100.0
	en.value = 0.0
	en.visible = rec["has_main"]
	en.add_theme_stylebox_override("fill", Ui.box(Color(1.0, 0.8, 0.2), 4))
	v.add_child(en)
	_cards[u["id"]] = {"panel": p, "hp": hp, "en": en}


# ---------------------------------------------------------------- бойцы

func _kind(def: Dictionary, key: String) -> String:
	if def.has("role"):
		return KIND_BY_ROLE.get(def["role"], "melee")
	return KIND_BY_KEY.get(key, "melee")


func _spawn(u: Dictionary) -> void:
	var node := Node3D.new()
	node.position = Vector3(float(u["x"]), 0, float(u["y"]) * DEPTH)
	var def := State.hero_def(u["key"])
	if def.is_empty():
		def = State.enemy_def(u["key"])
	var vis: Dictionary = def.get("visual", {})
	var scale_f := float(vis.get("scale", 1.0))
	var model_path := "res://assets/models/%s.glb" % str(vis.get("model", ""))
	var player: AnimationPlayer = null
	var body: Node3D
	var anim_names: Dictionary = DEFAULT_ANIMS.duplicate()
	anim_names.merge(vis.get("anims", {}), true)
	if vis.has("model") and ResourceLoader.exists(model_path):
		body = (load(model_path) as PackedScene).instantiate()
		body.scale = Vector3.ONE * scale_f
		body.rotation.y = deg_to_rad(float(vis.get("yaw", 0.0)))     # поправка, если модель смотрит не туда
		body.position.y = float(vis.get("y_offset", 0.0))            # поправка высоты над землёй
		var found := body.find_children("*", "AnimationPlayer", true, false)
		if found.size() > 0:
			player = found[0]
			_load_extra_anims(player, vis, anim_names)
	else:
		var m := MeshInstance3D.new()   # запасной вариант: капсула
		var cap := CapsuleMesh.new()
		cap.radius = 0.45
		cap.height = 1.5
		m.mesh = cap
		m.position.y = 0.75
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.5, 0.95) if u["side"] == "a" else Color(0.9, 0.3, 0.3)
		m.material_override = mat
		body = m
	var pivot := Node3D.new()   # игрок слева смотрит вправо, враги влево
	pivot.rotation.y = PI / 2.0 if u["side"] == "a" else -PI / 2.0
	pivot.add_child(body)
	node.add_child(pivot)

	# Полоса здоровья над головой
	var bar_root := Node3D.new()
	bar_root.position.y = 2.35 * scale_f
	node.add_child(bar_root)
	var bg := Vfx.sprite(bar_root, "", Color(0, 0, 0, 0.7), 1.0, Vector3.ZERO, false)
	bg.scale = Vector3(1.5, 0.17, 1)
	var fg := Vfx.sprite(bar_root, "", Color(0.35, 0.85, 0.4) if u["side"] == "a" else Color(0.9, 0.3, 0.3), 1.0, Vector3(0, 0, 0.01), false)
	fg.scale = Vector3(1.44, 0.11, 1)
	add_child(node)

	var has_main := false
	for a in def.get("abilities", []):
		if a["kind"] == "main":
			has_main = true
	var rec := {
		"node": node, "pivot": pivot, "anim": player, "anim_names": anim_names, "bar_fg": fg, "name": def.get("name", u["key"]),
		"max_hp": int(u["hp"]), "hp": int(u["hp"]), "target": null, "speed": 0.0, "alive": true, "busy": 0.0,
		"kind": _kind(def, u["key"]), "running": false, "vis": vis, "side": u["side"], "has_main": has_main, "id": u["id"],
		"color": Color(0.3, 0.5, 0.9) if u["side"] == "a" else Color(0.85, 0.3, 0.3),
	}
	_units[u["id"]] = rec
	if u["side"] == "a":
		_make_card(u, rec)
	for lg in ["idle", "run"]:
		var an := _resolve(rec, lg)
		if an != "":
			player.get_animation(an).loop_mode = Animation.LOOP_LINEAR
	if OS.get_environment("FIVEUFA_DEBUG") != "":
		var res := {}
		for lg in DEFAULT_ANIMS:
			res[lg] = _resolve(rec, lg)
		print("[anim] ", u["key"], " ", res)
	_play(rec, "idle")


func _load_extra_anims(player: AnimationPlayer, vis: Dictionary, anim_names: Dictionary) -> void:
	# Анимации из отдельных файлов (у Meshy каждая анимация обычно идёт своим файлом с тем же скелетом).
	var files: Dictionary = vis.get("anim_files", {})
	if files.is_empty():
		return
	var lib: AnimationLibrary = player.get_animation_library("")
	for lg in files:
		var path := str(files[lg])
		if not ResourceLoader.exists(path):
			push_warning("нет файла анимации " + path)
			continue
		var holder: Node = (load(path) as PackedScene).instantiate()
		var ps := holder.find_children("*", "AnimationPlayer", true, false)
		if ps.size() > 0:
			var src: AnimationPlayer = ps[0]
			var wanted := str(vis.get("anims", {}).get(lg, ""))
			var list := src.get_animation_list()
			var pick := wanted if wanted != "" and src.has_animation(wanted) else ""
			if pick == "":
				for n in list:
					if n != "RESET":
						pick = n
						break
			if pick != "":
				var key := "ext_" + str(lg)
				lib.add_animation(key, src.get_animation(pick).duplicate())
				anim_names[lg] = key
		holder.queue_free()


## Реальное название анимации в модели для логического имени (с запасными вариантами) или "".
func _resolve(u: Dictionary, logical: String) -> String:
	var p: AnimationPlayer = u["anim"]
	if p == null:
		return ""
	var names: Dictionary = u["anim_names"]
	var tries: Array = [names.get(logical, logical)]
	for fb in ANIM_FALLBACKS.get(logical, []):
		tries.append(names.get(fb, fb))
	for n in tries:
		if p.has_animation(n):
			return n
	return ""


func _play(u: Dictionary, logical: String) -> float:
	var n := _resolve(u, logical)
	if n == "":
		return 0.0
	var p: AnimationPlayer = u["anim"]
	p.play(n, 0.1)
	return p.get_animation(n).length


func _is_idle(u: Dictionary) -> bool:
	var p: AnimationPlayer = u["anim"]
	return p == null or p.current_animation == _resolve(u, "idle")


func _face(u: Dictionary, to: Vector3) -> void:
	var d: Vector3 = to - (u["node"] as Node3D).position
	if d.length() > 0.05:
		(u["pivot"] as Node3D).rotation.y = atan2(d.x, d.z)


func _update_hp(u: Dictionary) -> void:
	var ratio := clampf(float(u["hp"]) / float(u["max_hp"]), 0.0, 1.0)
	var fg: MeshInstance3D = u["bar_fg"]
	fg.scale.x = maxf(0.001, 1.44 * ratio)
	fg.position.x = -(1.44 * (1.0 - ratio)) / 2.0
	if _cards.has(u["id"]):
		(_cards[u["id"]]["hp"] as ProgressBar).value = float(u["hp"])


# ---------------------------------------------------------------- стили атак и эффекты

func _ability(id: String) -> Dictionary:
	return _abilities.get(id, {})


## "fire_comet" | "magic_bolt" | "none"
func _style_of(u: Dictionary, ability_id: String) -> String:
	var a := _ability(ability_id)
	if a.has("vfx"):
		return str(a["vfx"].get("style", "none"))
	match str(u["vis"].get("attack_style", "")):
		"magic":
			return "magic_bolt"
		"melee", "ranged":
			return "none"
	return "magic_bolt" if u["kind"] == "caster" else "none"


func _color_of(u: Dictionary, ability_id: String) -> Color:
	var a := _ability(ability_id)
	if a.has("vfx") and a["vfx"].has("color"):
		return Color.html(str(a["vfx"]["color"]))
	if u["vis"].has("magic_color"):
		return Color.html(str(u["vis"]["magic_color"]))
	return Color(0.6, 0.7, 1.0) if u["side"] == "a" else Color(1.0, 0.5, 0.5)


func _hand(u: Dictionary, toward: Vector3) -> Vector3:
	var p: Vector3 = (u["node"] as Node3D).position
	var dir := (toward - p)
	dir.y = 0
	return p + dir.normalized() * 0.5 + Vector3(0, 1.5, 0)


func _chest(u: Dictionary) -> Vector3:
	return (u["node"] as Node3D).position + Vector3(0, 1.1, 0)


func _later(delay: float, fn: Callable) -> void:
	var due := _t + maxf(0.0, delay)
	_max_due = maxf(_max_due, due)
	if delay <= 0.0:
		fn.call()
	else:
		_pending.append({"due": due, "fn": fn})


func _attack_anim(kind: String, strong: bool) -> String:
	match kind:
		"ranged":
			return "attack_ranged"
		"caster":
			return "cast_strong" if strong else "cast"
		_:
			return "attack_melee_strong" if strong else "attack_melee"


func _on_cast(e: Dictionary) -> void:
	if not _units.has(e["src"]):
		return
	var u: Dictionary = _units[e["src"]]
	var aid: String = e.get("ability", "")
	var strong: bool = e["type"] == "skill"
	if _units.has(e["dst"]):
		_face(u, (_units[e["dst"]]["node"] as Node3D).position)
	u["busy"] = maxf(_play(u, _attack_anim(u["kind"], strong)), 0.4)
	u["running"] = false

	# Цели того же умения в этот же момент (для групповых умений — все враги)
	var targets: Array = []
	for j in range(_i, _events.size()):
		var ev: Dictionary = _events[j]
		if float(ev["t"]) > float(e["t"]) + 0.001:
			break
		if ev["type"] == "damage" and ev["src"] == e["src"] and ev.get("ability", "") == aid:
			targets.append(ev["dst"])
	if targets.is_empty():
		targets.append(e["dst"])

	var a := _ability(aid)
	if a.get("kind", "") == "main":
		_banner(u, str(a.get("name", "Главное умение")))
		_ult_zoom(u, targets, 0.9)

	var style := _style_of(u, aid)
	if style == "none":
		return
	var color := _color_of(u, aid)
	Vfx.cast_glow(self, _hand(u, (_units[targets[0]]["node"] as Node3D).position if _units.has(targets[0]) else (u["node"] as Node3D).position), color)
	var k := 0
	for dst in targets:
		if not _units.has(dst):
			continue
		var from := _hand(u, (_units[dst]["node"] as Node3D).position)
		var to := _chest(_units[dst])
		var key := "%s|%s|%s" % [e["t"], e["src"], dst]
		if style == "fire_comet":
			var stagger := 0.1 * k
			var flight := 0.8
			_delay_map[key] = stagger + flight
			Vfx.comet(self, from, to, color, flight, stagger, _shake)
		else:
			var flight := clampf(from.distance_to(to) / 14.0, 0.25, 0.6)
			_delay_map[key] = flight
			Vfx.bolt(self, from, to, color, flight)
		k += 1


func _shake() -> void:
	var tw := create_tween()
	for i in 5:
		tw.tween_property(_cam, "h_offset", randf_range(-0.18, 0.18), 0.035)
		tw.parallel().tween_property(_cam, "v_offset", randf_range(-0.12, 0.12), 0.035)
	tw.tween_property(_cam, "h_offset", 0.0, 0.05)
	tw.parallel().tween_property(_cam, "v_offset", 0.0, 0.05)


## Подъезд камеры на главном умении: приближение к месту действия, пауза, возврат.
func _ult_zoom(caster: Dictionary, targets: Array, hold: float) -> void:
	var focus: Vector3 = (caster["node"] as Node3D).position
	var n := 1
	for dst in targets:
		if _units.has(dst):
			focus += (_units[dst]["node"] as Node3D).position
			n += 1
	focus /= float(n)
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_cam, "fov", CAM_FOV - 10.0, 0.3)
	_cam_tween.parallel().tween_property(_cam, "position", CAM_POS + Vector3(focus.x * 0.45, -1.2, -1.8), 0.3)
	_cam_tween.tween_interval(hold)
	_cam_tween.tween_property(_cam, "fov", CAM_FOV, 0.45)
	_cam_tween.parallel().tween_property(_cam, "position", CAM_POS, 0.45)


func _banner(u: Dictionary, ability_name: String) -> void:
	var left: bool = u["side"] == "a"
	var p := Ui.panel(Color(0.12, 0.1, 0.18, 0.88) if left else Color(0.2, 0.08, 0.1, 0.88))
	p.custom_minimum_size = Vector2(560, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var l1 := Ui.label(str(u["name"]), 30, Color(1, 0.85, 0.4))
	var l2 := Ui.label(ability_name, 40)
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	l2.autowrap_mode = TextServer.AUTOWRAP_OFF
	v.add_child(l1)
	v.add_child(l2)
	_banner_layer.add_child(p)
	p.size = Vector2(560, 120)
	p.position = Vector2(-600 if left else 760, 760)
	var tw := create_tween()
	tw.tween_property(p, "position:x", 20.0 if left else 140.0, 0.25)
	tw.tween_interval(0.9)
	tw.tween_property(p, "modulate:a", 0.0, 0.3)
	tw.tween_callback(p.queue_free)


func _float_text(pos: Vector3, text: String, color: Color, big: bool) -> void:
	var l := Label3D.new()
	l.text = text
	l.modulate = color
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = 72 if big else 52
	l.pixel_size = 0.011
	l.no_depth_test = true
	l.position = pos + Vector3(0, 2.2, 0)
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 1.4, 0.8)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


# ---------------------------------------------------------------- события

func _dispatch(e: Dictionary) -> void:
	match e["type"]:
		"start":
			for u in e["units"]:
				_spawn(u)
		"move":
			if _units.has(e["id"]):
				var u: Dictionary = _units[e["id"]]
				u["target"] = Vector3(float(e["to"][0]), 0, float(e["to"][1]) * DEPTH)
				u["speed"] = float(e["speed"])
				_face(u, u["target"])
		"attack", "skill":
			_on_cast(e)
		"damage":
			var delay := float(_delay_map.get("%s|%s|%s" % [e["t"], e["src"], e["dst"]], 0.0))
			_dst_delay["%s|%s" % [e["t"], e["dst"]]] = delay
			_later(delay, func(): _hit(e))
		"heal":
			_on_heal(e)
		"death":
			var d := float(_dst_delay.get("%s|%s" % [e["t"], e["id"]], 0.0))
			_later(d, func(): _die(e["id"]))
		"energy":
			if _cards.has(e["id"]):
				(_cards[e["id"]]["en"] as ProgressBar).value = float(e["value"])
		"end":
			_later(maxf(0.5, _max_due - _t + 0.5), _show_result)


func _hit(e: Dictionary) -> void:
	if not _units.has(e["dst"]):
		return
	var u: Dictionary = _units[e["dst"]]
	u["hp"] = int(e["hp"])
	_update_hp(u)
	var crit: bool = e.get("crit", false)
	if u["alive"] and u["busy"] <= 0.0 and int(e["hp"]) > 0:
		u["busy"] = _play(u, "hit")
	_float_text((u["node"] as Node3D).position, ("%d!" if crit else "%d") % int(e["amount"]), Color(1, 0.85, 0.2) if crit else Color(1, 1, 1), crit)


func _on_heal(e: Dictionary) -> void:
	if not _units.has(e["dst"]) or not _units.has(e["src"]):
		return
	var s: Dictionary = _units[e["src"]]
	var d: Dictionary = _units[e["dst"]]
	var color := _color_of(s, e.get("ability", ""))
	var from := _hand(s, (d["node"] as Node3D).position)
	var to := _chest(d)
	_face(s, (d["node"] as Node3D).position)
	s["busy"] = maxf(_play(s, "cast_strong"), 0.4)
	s["running"] = false
	var flight := 0.0 if e["src"] == e["dst"] else clampf(from.distance_to(to) / 14.0, 0.25, 0.6)
	if flight > 0.0:
		Vfx.bolt(self, from, to, color, flight)
	else:
		Vfx.cast_glow(self, from, color)
	_later(flight, func():
		d["hp"] = int(e["hp"])
		_update_hp(d)
		Vfx.heal_hit(self, (d["node"] as Node3D).position + Vector3(0, 0.6, 0), color)
		_float_text((d["node"] as Node3D).position, "+%d" % int(e["amount"]), Color(0.4, 1, 0.5), false))


func _die(id: String) -> void:
	if not _units.has(id):
		return
	var u: Dictionary = _units[id]
	u["alive"] = false
	u["target"] = null
	u["busy"] = 999.0
	u["hp"] = 0
	_update_hp(u)
	(u["bar_fg"] as MeshInstance3D).get_parent().visible = false
	if _cards.has(id):
		(_cards[id]["panel"] as Control).modulate = Color(0.45, 0.45, 0.45)
	var dn := _resolve(u, "death")
	if dn != "":
		var p: AnimationPlayer = u["anim"]
		p.get_animation(dn).loop_mode = Animation.LOOP_NONE
		p.play(dn, 0.1)
	else:
		var tw := create_tween()
		tw.tween_property(u["node"], "scale", Vector3(1, 0.1, 1), 0.3)


# ---------------------------------------------------------------- цикл

func _process(delta: float) -> void:
	if _result_shown:
		return
	_t += delta * SPEED
	while _i < _events.size() and float(_events[_i]["t"]) <= _t:
		var e: Dictionary = _events[_i]
		_i += 1
		_dispatch(e)
	var keep: Array = []
	for p in _pending:
		if _t >= float(p["due"]):
			(p["fn"] as Callable).call()
		else:
			keep.append(p)
	_pending = keep
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
				_play(u, "run")
				u["running"] = true
			elif not moving and (u["running"] or not _is_idle(u)):
				_play(u, "idle")
				u["running"] = false
	var left := maxf(0.0, TIME_LIMIT - _t)
	_timer_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]


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
	overlay.color = Color(0, 0, 0, 0.55)
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
	back.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://hub.tscn"))
	v.add_child(back)
	_hud.add_child(overlay)
