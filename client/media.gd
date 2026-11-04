extends Node
## Модели, анимации и картинки.
## Вшитое: res://assets/models/<имя>.glb или res://assets/backgrounds/<имя>.png|jpg.
## Скачанное: user://media/<sha><ext>. Список приходит в /api/content (media).
## Замена в админке = новая активная версия: клиент докачает её при запуске, если она не вшита.

const DIR := "user://media"

var manifest: Dictionary = {}
var _cache := {}   # путь -> [GLTFDocument, GLTFState]
var _battle_manifest: Variant = null   # снимок на время одного боя; null = обычный манифест


func set_manifest(m: Dictionary) -> void:
	manifest = m


## На время боя подменяет список файлов снимком с сервера. null возвращает обычный манифест.
func set_battle_manifest(m: Variant) -> void:
	if m == null:
		_battle_manifest = null
	elif typeof(m) == TYPE_DICTIONARY:
		_battle_manifest = m


func _active() -> Dictionary:
	if typeof(_battle_manifest) == TYPE_DICTIONARY:
		return _battle_manifest
	return manifest


func _ext(e: Dictionary) -> String:
	var ext := str(e.get("ext", ""))
	if ext.begins_with("."):
		return ext
	var k := str(e.get("kind", ""))
	if k == "image" or k == "background":
		return ".png"
	return ".glb"


func _path(sha: String, ext: String = ".glb") -> String:
	return "%s/%s%s" % [DIR, sha, ext]


## Что нужно скачать: не вшито и ещё нет на устройстве. [{name, sha, size, ext}]
func missing() -> Array:
	var out: Array = []
	for n in _active():
		var e: Dictionary = _active()[n]
		if e.get("bundled", false):
			continue
		var ext := _ext(e)
		if not FileAccess.file_exists(_path(str(e["sha"]), ext)):
			out.append({"name": n, "sha": str(e["sha"]), "size": int(e.get("size", 0)), "ext": ext})
	return out


func missing_bytes() -> int:
	var total := 0
	for m in missing():
		total += int(m["size"])
	return total


## Скачивает недостающее. progress(готово, всего) вызывается после каждого файла. Возвращает true, если всё скачано.
func download_missing(progress: Callable = Callable()) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var todo := missing()
	var done := 0
	var ok_all := true
	for m in todo:
		var dest := _path(str(m["sha"]), str(m.get("ext", ".glb")))
		var ok: bool = await Api.download("/api/media/" + str(m["sha"]), dest)
		# целостность: хеш файла должен совпасть
		if ok and FileAccess.get_sha256(dest) != str(m["sha"]):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dest))
			ok = false
		if not ok:
			ok_all = false
			push_warning("не удалось скачать " + str(m["name"]))
		done += 1
		if progress.is_valid():
			progress.call(done, todo.size())
	return ok_all


func _load_glb(path: String) -> Node3D:
	if not _cache.has(path):
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(path, st) != OK:
			push_warning("не читается " + path)
			return null
		_cache[path] = [doc, st]
	var pair: Array = _cache[path]
	return (pair[0] as GLTFDocument).generate_scene(pair[1]) as Node3D


## Экземпляр модели или анимационного файла по логическому имени (или null).
func instance(name: String) -> Node3D:
	if name == "":
		return null
	var e: Dictionary = _active().get(name, {})
	var k := str(e.get("kind", "model"))
	if not e.is_empty() and not e.get("bundled", false) and k != "image" and k != "background":
		var p := _path(str(e["sha"]), _ext(e))
		if FileAccess.file_exists(p):
			var n := _load_glb(p)
			if n != null:
				return n
	var res := "res://assets/models/%s.glb" % name
	if ResourceLoader.exists(res):
		return (load(res) as PackedScene).instantiate() as Node3D
	return null


## Картинка из медиатеки, если активная версия не вшита и уже скачана. Иначе null: вызывающий берёт файл из приложения.
func texture(name: String) -> Texture2D:
	if name == "":
		return null
	var e: Dictionary = _active().get(name, {})
	if e.is_empty() or e.get("bundled", false):
		return null
	var k := str(e.get("kind", ""))
	if k != "image" and k != "background":
		return null
	var p := _path(str(e["sha"]), _ext(e))
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load(p) != OK:
		return null
	return ImageTexture.create_from_image(img)
