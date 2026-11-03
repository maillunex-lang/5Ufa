class_name Updater
extends RefCounted
## Обновление приложения: сервер сообщает о новой версии, APK скачивается
## (с докачкой и проверкой SHA-256) в user://updates и открывается установщик Android.

signal progress(done_bytes: int, total_bytes: int)

const DIR := "user://updates"


## Номер сборки установленного приложения (versionCode). Пишется скриптом сборки.
static func current_code() -> int:
	return int(ProjectSettings.get_setting("ufa/version_code", 0))


## {ok, update_available, required, latest:{version_name, size, url, sha256, notes}, error}
static func check() -> Dictionary:
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET,
			"/api/v1/client/latest?code=%d" % current_code(), null, false)
	if not res.ok or not (res.data is Dictionary):
		return {"ok": false, "update_available": false, "required": false, "error": res.error}
	var d: Dictionary = res.data
	return {"ok": true, "update_available": bool(d.get("update_available", false)),
			"required": bool(d.get("required", false)), "latest": d.get("latest"), "error": ""}


## Удалить старые скачанные APK (после успешного обновления они не нужны)
static func cleanup() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)


## Скачать и запустить установку. Возвращает {ok, error, path}
func download_and_install(latest: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(DIR)
	var sha: String = str(latest["sha256"])
	var size: int = int(latest["size"])
	var partial := "%s/%s.part" % [DIR, sha]
	var apk := "%s/ufa-%s.apk" % [DIR, str(latest["version_name"])]
	if not (FileAccess.file_exists(apk) and await DownloadWorker.sha256_file(apk) == sha):
		var w := DownloadWorker.new(Api.host, Api.port, Api.scheme == "https")
		var done := [_len(partial)]
		w.bytes_received.connect(func(n):
			done[0] += n
			progress.emit(done[0], size))
		progress.emit(done[0], size)
		var err := ERR_CANT_CONNECT
		for attempt in range(3):
			err = await w.download(str(latest["url"]), partial, size)
			if err == OK:
				break
			done[0] = _len(partial)
			await (Engine.get_main_loop() as SceneTree).create_timer(2.0 * (attempt + 1)).timeout
		w.close()
		if err != OK:
			return {"ok": false, "error": "Не удалось скачать обновление: " + w.last_error, "path": ""}
		if await DownloadWorker.sha256_file(partial) != sha:
			DirAccess.remove_absolute(partial)
			return {"ok": false, "error": "Файл обновления повреждён, попробуйте ещё раз", "path": ""}
		if FileAccess.file_exists(apk):
			DirAccess.remove_absolute(apk)
		DirAccess.rename_absolute(partial, apk)
	var path := ProjectSettings.globalize_path(apk)
	if OS.get_name() == "Android":
		# Открывает стандартный установщик Android (через FileProvider Godot)
		if OS.shell_open(path) != OK:
			return {"ok": false, "error": "Не удалось открыть установщик Android", "path": path}
	return {"ok": true, "error": "", "path": path}


static func _len(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	var n := f.get_length() if f else 0
	if f:
		f.close()
	return n
