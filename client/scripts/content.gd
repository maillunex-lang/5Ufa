extends Node
## Контент игры: манифест, загрузка пакетов, проверка SHA-256, хранение в user://content.
##
## user://content/files/<путь>   — готовые файлы (например files/ui/logo.png)
## user://content/.partial/<sha> — недокачанные файлы (продолжаются после обрыва)
## user://content/state.json     — что уже скачано: путь -> sha256
## user://content/manifest.json  — последний полученный манифест (для ETag)

signal progress(done_bytes: int, total_bytes: int)
signal background_progress(done_bytes: int, total_bytes: int)
signal background_finished

const ROOT := "user://content"
const FILES := ROOT + "/files"
const PARTIAL := ROOT + "/.partial"
const STATE_FILE := ROOT + "/state.json"
const MANIFEST_FILE := ROOT + "/manifest.json"
const WORKERS := 3
const RETRIES := 3

var manifest: Dictionary = {}
var state: Dictionary = {"release": 0, "files": {}}
var background_running := false
var _state_dirty := false
var _last_state_save := 0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(FILES)
	DirAccess.make_dir_recursive_absolute(PARTIAL)
	var s: Variant = _read_json(STATE_FILE)
	if s is Dictionary and s.has("files"):
		state = s
	var m: Variant = _read_json(MANIFEST_FILE)
	if m is Dictionary:
		manifest = m


# --- Доступ к файлам для игры ------------------------------------------------

func local_path(rel: String) -> String:
	return FILES + "/" + rel


func has_file(rel: String) -> bool:
	return state["files"].has(rel) and FileAccess.file_exists(local_path(rel))


func load_json(rel: String) -> Variant:
	return _read_json(local_path(rel)) if has_file(rel) else null


func load_texture(rel: String) -> Texture2D:
	if not has_file(rel):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(local_path(rel)))
	return ImageTexture.create_from_image(img) if img else null


## Текст из локализации (localization/ru.json), с подстановкой {name}
func t(key: String, params: Dictionary = {}) -> String:
	var loc: Variant = load_json("localization/ru.json")
	var text := key
	if loc is Dictionary and loc.get("strings", {}).has(key):
		text = str(loc["strings"][key])
	return text.format(params)


# --- Манифест ----------------------------------------------------------------

## Получить манифест. Результат: {ok, error, update_required}
func fetch_manifest() -> Dictionary:
	var headers := PackedStringArray()
	if manifest.has("_etag"):
		headers.append("If-None-Match: " + str(manifest["_etag"]))
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/content/manifest", null, true, headers)
	if res.code == 304 and not manifest.is_empty():
		pass
	elif res.ok and res.data is Dictionary:
		manifest = res.data
		manifest["_etag"] = res.headers.get("etag", "")
		_write_json(MANIFEST_FILE, manifest)
	else:
		return {"ok": false, "error": res.error if res.error != "" else "Не удалось получить список обновлений", "update_required": false}
	var need := str(manifest.get("min_client_version", "0.0.0"))
	if Config.compare_versions(Config.client_version, need) < 0:
		return {"ok": false, "update_required": true,
				"error": "Нужна новая версия приложения (%s или новее). Установите обновление." % need}
	return {"ok": true, "error": "", "update_required": false}


## Что нужно скачать: [{path, sha256, size}], отдельно для обязательных и фоновых пакетов
func plan(required_only: bool) -> Array:
	var out: Array = []
	for pkg in manifest.get("packages", []):
		if bool(pkg.get("required", false)) != required_only:
			continue
		for f in pkg.get("files", []):
			var rel: String = str(f["path"])
			if state["files"].get(rel, "") == f["sha256"] and FileAccess.file_exists(local_path(rel)):
				continue
			out.append({"path": rel, "sha256": str(f["sha256"]), "size": int(f["size"])})
	return out


static func total_size(entries: Array) -> int:
	var n := 0
	for e in entries:
		n += int(e["size"])
	return n


# --- Загрузка ------------------------------------------------------------------

## Скачать обязательные пакеты (интерфейс, обучение, 1-я глава). {ok, error}
func sync_required() -> Dictionary:
	var entries := plan(true)
	var res: Dictionary = await _download_all(entries, func(done, all): progress.emit(done, all))
	if res.ok:
		state["release"] = int(manifest.get("release", 0))
		_save_state(true)
	return res


## Фоновые пакеты — во время игры. Можно вызывать повторно, параллельно не запустится.
func sync_background() -> void:
	if background_running:
		return
	background_running = true
	var entries := plan(false)
	if not entries.is_empty():
		var res: Dictionary = await _download_all(entries, func(done, all): background_progress.emit(done, all))
		if not res.ok:
			push_warning("Фоновая загрузка: " + str(res.error))
	_cleanup_removed()
	background_running = false
	background_finished.emit()


## Полная проверка всех файлов (кнопка «Проверить файлы»): битые удаляются и качаются заново.
func verify_all() -> int:
	var broken := 0
	for rel in state["files"].keys():
		var sha: String = await DownloadWorker.sha256_file(local_path(rel))
		if sha != state["files"][rel]:
			state["files"].erase(rel)
			DirAccess.remove_absolute(local_path(rel))
			broken += 1
	_save_state(true)
	return broken


func _download_all(entries: Array, on_progress: Callable) -> Dictionary:
	var total := total_size(entries)
	var counter := {"done": 0, "error": ""}
	# Уже скачанные части после обрыва считаем выполненными
	for e in entries:
		var p: String = PARTIAL + "/" + str(e["sha256"])
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f:
				counter["done"] += min(f.get_length(), int(e["size"]))
				f.close()
	on_progress.call(counter["done"], total)
	if entries.is_empty():
		return {"ok": true, "error": ""}

	var queue := entries.duplicate()
	var running := {"n": 0}
	var n_workers: int = min(WORKERS, queue.size())
	for i in range(n_workers):
		running["n"] += 1
		_worker_loop(queue, counter, total, on_progress, running)
	while running["n"] > 0:
		await get_tree().process_frame
	_save_state(true)
	if counter["error"] != "":
		return {"ok": false, "error": counter["error"]}
	return {"ok": true, "error": ""}


func _worker_loop(queue: Array, counter: Dictionary, total: int, on_progress: Callable, running: Dictionary) -> void:
	var w := DownloadWorker.new(Api.host, Api.port, Api.scheme == "https")
	w.bytes_received.connect(func(n):
		counter["done"] += n
		on_progress.call(counter["done"], total))
	while not queue.is_empty() and counter["error"] == "":
		var e: Dictionary = queue.pop_front()
		var ok := false
		for attempt in range(RETRIES):
			if await _fetch_one(w, e, counter):
				ok = true
				break
			await get_tree().create_timer(1.5 * (attempt + 1)).timeout
		if not ok:
			counter["error"] = "Не удалось скачать файл %s: %s" % [e["path"], w.last_error]
	w.close()
	running["n"] -= 1


func _fetch_one(w: DownloadWorker, e: Dictionary, counter: Dictionary) -> bool:
	var sha: String = e["sha256"]
	var partial := PARTIAL + "/" + sha
	var url_path: String = str(manifest.get("base_url", "/content/files/")) + sha.substr(0, 2) + "/" + sha
	var before := _file_len(partial)
	var err: int = await w.download(url_path, partial, int(e["size"]))
	if err != OK:
		# Если сервер начал файл заново (200 вместо 206) — убираем двойной счёт
		var after := _file_len(partial)
		if after < before:
			counter["done"] -= before - after
		return false
	var got: String = await DownloadWorker.sha256_file(partial)
	if got != sha:
		counter["done"] -= _file_len(partial)
		DirAccess.remove_absolute(partial)
		w.last_error = "файл повреждён при загрузке (не совпала контрольная сумма)"
		return false
	var dest: String = local_path(str(e["path"]))
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	if FileAccess.file_exists(dest):
		DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(partial, dest) != OK:
		w.last_error = "не удалось сохранить файл"
		return false
	state["files"][e["path"]] = sha
	_save_state(false)
	return true


func _cleanup_removed() -> void:
	var keep := {}
	for pkg in manifest.get("packages", []):
		for f in pkg.get("files", []):
			keep[str(f["path"])] = true
	for rel in state["files"].keys():
		if not keep.has(rel):
			DirAccess.remove_absolute(local_path(rel))
			state["files"].erase(rel)
	_save_state(true)


# --- Вспомогательное -----------------------------------------------------------

func _file_len(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _save_state(force: bool) -> void:
	_state_dirty = true
	var now := Time.get_ticks_msec()
	if force or now - _last_state_save > 500:
		_write_json(STATE_FILE, state)
		_last_state_save = now
		_state_dirty = false


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


func _write_json(path: String, data: Variant) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if _state_dirty:
			_write_json(STATE_FILE, state)


static func format_mb(bytes: int) -> String:
	return "%.1f МБ" % (bytes / 1048576.0)
