class_name SkeletonRig
extends Node2D
## Герой из частей по skeleton.json (формат ufa-skeleton v1, docs/skeleton-format.md).
## Кости считаются в коде, картинки частей — Sprite2D в порядке отрисовки (slots).

signal anim_event(name: String)
signal anim_finished(name: String)

var data: Dictionary = {}
var base_dir := ""            # например heroes/ural_batyr
var speed := 1.0              # ускорение x1/x2/x4
var current := ""
var _time := 0.0
var _loop := true
var _bones: Array = []        # [{name, parent_idx, x, y, rot}]
var _bone_index: Dictionary = {}
var _world: Array = []        # Transform2D для каждой кости
var _sprites: Array = []      # [{sprite, bone_idx, x, y, rot}]
var _fired: Dictionary = {}
var _queue_after := ""        # анимация после текущей (обычно idle)
var frozen := false           # редактор анимации: поза задаётся вручную (pose_at), время не идёт

static var _tex_cache: Dictionary = {}


static func load_texture(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = Content.load_texture(path)
	return _tex_cache[path]


var skin := ""                # скин героя: картинки из <герой>/skins/<скин>/, если они есть


## Путь картинки с учётом скина (нет файла в скине — картинка обычного вида)
static func skin_path(hero_dir: String, rel: String, skin_id: String) -> String:
	if skin_id != "" and skin_id != "default":
		var p := "%s/skins/%s/%s" % [hero_dir, skin_id, rel]
		if Content.has_file(p):
			return p
	return hero_dir + "/" + rel


func setup(hero_dir: String, skeleton: Dictionary, skin_id := "") -> void:
	base_dir = hero_dir
	data = skeleton
	if skin_id != "":
		skin = skin_id
	for b in data.get("bones", []):
		_bone_index[b["name"]] = _bones.size()
		_bones.append({"name": b["name"], "parent": b.get("parent", ""), "x": float(b.get("x", 0)),
				"y": float(b.get("y", 0)), "rot": float(b.get("rotation", 0)),
				"sx": float(b.get("scale_x", 1)), "sy": float(b.get("scale_y", 1))})
	for b in _bones:
		b["parent_idx"] = _bone_index.get(b["parent"], -1)
	_world.resize(_bones.size())
	for s in data.get("slots", []):
		var spr := Sprite2D.new()
		# Своя картинка и точка крепления части в скине (нарезчик админки): slots[].skins[<скин>]
		var own: Dictionary = s.get("skins", {}).get(skin, {}) if skin != "" else {}
		spr.texture = load_texture(skin_path(base_dir, str(own.get("image", s["image"])), skin))
		spr.centered = false
		var pivot: Array = own.get("pivot", s.get("pivot", [0, 0]))
		spr.offset = -Vector2(float(pivot[0]), float(pivot[1]))
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(spr)
		_sprites.append({"sprite": spr, "bone": _bone_index.get(s["bone"], 0),
				"x": float(s.get("x", 0)), "y": float(s.get("y", 0)), "rot": float(s.get("rotation", 0))})
	play("idle")


func has_anim(anim: String) -> bool:
	return data.get("animations", {}).has(anim)


## Проиграть анимацию. after — что включить после окончания (для разовых анимаций)
func play(anim: String, after := "idle") -> void:
	if not has_anim(anim):
		anim = "idle"
	current = anim
	_time = 0.0
	_fired.clear()
	var a: Dictionary = data["animations"][anim]
	_loop = bool(a.get("loop", false))
	_queue_after = "" if _loop else after
	_update_pose()


func anim_duration(anim: String) -> float:
	return float(data.get("animations", {}).get(anim, {}).get("duration", 0.0))


## Точка крепления (projectile, hit, overhead) в координатах родителя героя
func anchor_position(anchor: String) -> Vector2:
	var a: Dictionary = data.get("anchors", {}).get(anchor, {})
	if a.is_empty():
		return position
	var idx: int = _bone_index.get(str(a.get("bone", "root")), 0)
	return transform * (_world[idx] * Vector2(float(a.get("x", 0)), float(a.get("y", 0))))


## Редактор анимации: показать позу анимации anim в момент t и остановить время
func pose_at(anim: String, t: float) -> void:
	frozen = true
	current = anim
	_time = t
	_update_pose()


## Пересобрать героя по изменённому скелету (редактор: новые части, кости, ключи)
func rebuild(skeleton: Dictionary) -> void:
	for s in _sprites:
		s["sprite"].queue_free()
	_sprites.clear()
	_bones.clear()
	_bone_index.clear()
	_world.clear()
	var was := current
	var t := _time
	setup(base_dir, skeleton, skin)
	if frozen and was != "":
		pose_at(was, t)


func bone_names() -> Array:
	return _bones.map(func(b): return b["name"])


## Положение и поворот кости в координатах рига
func bone_world(bone: String) -> Transform2D:
	var i: int = _bone_index.get(bone, -1)
	return _world[i] if i >= 0 and i < _world.size() and _world[i] != null else Transform2D.IDENTITY


func _process(delta: float) -> void:
	if current == "" or frozen:
		return
	var a: Dictionary = data["animations"][current]
	var dur := float(a.get("duration", 1.0))
	_time += delta * speed
	for ev in a.get("events", []):
		var key := "%s@%s" % [ev["name"], ev["t"]]
		if not _fired.has(key) and _time >= float(ev["t"]):
			_fired[key] = true
			anim_event.emit(str(ev["name"]))
	if _time >= dur:
		if _loop:
			_time = fmod(_time, dur)
			_fired.clear()
		else:
			var finished := current
			_time = dur
			_update_pose()
			if _queue_after != "":
				play(_queue_after)
			else:
				current = ""
			anim_finished.emit(finished)
			return
	_update_pose()


static func _sample(keys: Array, t: float, dims: int) -> Array:
	# keys: [[t, v]] или [[t, x, y]] — линейная интерполяция между ключами
	if keys.is_empty():
		return []
	var prev: Array = keys[0]
	if t <= float(prev[0]):
		return prev.slice(1, 1 + dims)
	for k in keys:
		if t <= float(k[0]):
			var span := float(k[0]) - float(prev[0])
			var f := 0.0 if span <= 0.0 else (t - float(prev[0])) / span
			f = f * f * (3.0 - 2.0 * f)  # сглаживание
			var out := []
			for i in range(dims):
				out.append(lerpf(float(prev[1 + i]), float(k[1 + i]), f))
			return out
		prev = k
	return prev.slice(1, 1 + dims)


func _update_pose() -> void:
	var a: Dictionary = data["animations"].get(current, {}) if current != "" else {}
	var tracks: Dictionary = a.get("bones", {})
	for i in range(_bones.size()):
		var b: Dictionary = _bones[i]
		var rot: float = b["rot"]
		var pos := Vector2(b["x"], b["y"])
		var scl := Vector2(b["sx"], b["sy"])
		if tracks.has(b["name"]):
			var tr: Dictionary = tracks[b["name"]]
			if tr.has("rotate"):
				rot += float(_sample(tr["rotate"], _time, 1)[0])
			if tr.has("translate"):
				var v := _sample(tr["translate"], _time, 2)
				pos += Vector2(v[0], v[1])
			if tr.has("scale"):
				var s := _sample(tr["scale"], _time, 2)
				scl *= Vector2(s[0], s[1])
		var local := Transform2D(deg_to_rad(rot), scl, 0.0, pos)
		var p: int = b["parent_idx"]
		_world[i] = local if p < 0 else _world[p] * local
	for s in _sprites:
		var spr: Sprite2D = s["sprite"]
		spr.transform = _world[s["bone"]] * Transform2D(deg_to_rad(s["rot"]), Vector2(s["x"], s["y"]))
	if a.has("alpha"):
		modulate.a = float(_sample(a["alpha"], _time, 1)[0])
	elif current != "death":
		modulate.a = 1.0
