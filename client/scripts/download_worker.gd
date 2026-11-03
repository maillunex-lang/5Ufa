class_name DownloadWorker
extends RefCounted
## Скачивает файлы по одному через своё HTTP-соединение (keep-alive).
## Докачка: если частичный файл уже есть, запрашивает продолжение (Range: bytes=N-).

signal bytes_received(count: int)

const IDLE_TIMEOUT_MS := 30000

var _host: String
var _port: int
var _tls: bool
var _http := HTTPClient.new()
var last_error := ""


func _init(host: String, port: int, use_tls: bool) -> void:
	_host = host
	_port = port
	_tls = use_tls
	_http.read_chunk_size = 256 * 1024


func _tick() -> void:
	await (Engine.get_main_loop() as SceneTree).process_frame


func _ensure_connected() -> bool:
	_http.poll()
	if _http.get_status() == HTTPClient.STATUS_CONNECTED:
		return true
	_http.close()
	var err := _http.connect_to_host(_host, _port, TLSOptions.client() if _tls else null)
	if err != OK:
		last_error = "не удалось подключиться (%d)" % err
		return false
	var started := Time.get_ticks_msec()
	while _http.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
		_http.poll()
		if Time.get_ticks_msec() - started > IDLE_TIMEOUT_MS:
			last_error = "сервер не отвечает"
			return false
		await _tick()
	if _http.get_status() != HTTPClient.STATUS_CONNECTED:
		last_error = "нет соединения (статус %d)" % _http.get_status()
		return false
	return true


## Скачать url_path в файл partial_path (дописывая). Возвращает OK при успехе.
func download(url_path: String, partial_path: String, expected_size: int) -> int:
	last_error = ""
	var have := 0
	if FileAccess.file_exists(partial_path):
		var pf := FileAccess.open(partial_path, FileAccess.READ)
		if pf:
			have = pf.get_length()
			pf.close()
	if have == expected_size and expected_size > 0:
		return OK
	if have > expected_size:
		DirAccess.remove_absolute(partial_path)
		have = 0

	if not await _ensure_connected():
		return ERR_CANT_CONNECT
	var headers := PackedStringArray(["User-Agent: UfaGame/%s" % Config.client_version, "Accept-Encoding: identity"])
	if have > 0:
		headers.append("Range: bytes=%d-" % have)
	var err := _http.request(HTTPClient.METHOD_GET, url_path, headers)
	if err != OK:
		_http.close()
		last_error = "ошибка запроса (%d)" % err
		return err
	var started := Time.get_ticks_msec()
	while _http.get_status() == HTTPClient.STATUS_REQUESTING:
		_http.poll()
		if Time.get_ticks_msec() - started > IDLE_TIMEOUT_MS:
			_http.close()
			last_error = "сервер не отвечает"
			return ERR_TIMEOUT
		await _tick()
	if not _http.has_response():
		_http.close()
		last_error = "нет ответа сервера"
		return ERR_CONNECTION_ERROR

	var code := _http.get_response_code()
	var mode := FileAccess.WRITE
	if code == 206 and have > 0:
		mode = FileAccess.READ_WRITE
	elif code == 200:
		have = 0
	elif code == 416:
		_drain()
		DirAccess.remove_absolute(partial_path)
		last_error = "неверный диапазон, файл будет скачан заново"
		return ERR_FILE_CORRUPT
	else:
		_drain()
		last_error = "сервер вернул код %d" % code
		return FAILED

	var f := FileAccess.open(partial_path, mode)
	if f == null:
		_http.close()
		last_error = "не удаётся записать файл (%d)" % FileAccess.get_open_error()
		return ERR_FILE_CANT_WRITE
	if mode == FileAccess.READ_WRITE:
		f.seek_end()

	var last_data := Time.get_ticks_msec()
	while _http.get_status() == HTTPClient.STATUS_BODY:
		_http.poll()
		var got_any := false
		for _i in range(16):  # несколько кусков за кадр — быстрее
			if _http.get_status() != HTTPClient.STATUS_BODY:
				break
			var chunk := _http.read_response_body_chunk()
			if chunk.is_empty():
				break
			f.store_buffer(chunk)
			bytes_received.emit(chunk.size())
			got_any = true
		if got_any:
			last_data = Time.get_ticks_msec()
		else:
			if Time.get_ticks_msec() - last_data > IDLE_TIMEOUT_MS:
				f.close()
				_http.close()
				last_error = "загрузка прервалась"
				return ERR_TIMEOUT
			await _tick()
	f.close()
	if _http.get_status() not in [HTTPClient.STATUS_CONNECTED, HTTPClient.STATUS_DISCONNECTED]:
		_http.close()
		last_error = "соединение оборвалось"
		return ERR_CONNECTION_ERROR
	return OK


func _drain() -> void:
	# Ответ с ошибкой: просто закрываем соединение, следующий запрос откроет новое
	_http.close()


func close() -> void:
	_http.close()


## SHA-256 файла (по кускам, не замораживая игру)
static func sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var since_yield := 0
	while f.get_position() < f.get_length():
		var buf := f.get_buffer(1024 * 1024)
		ctx.update(buf)
		since_yield += buf.size()
		if since_yield >= 8 * 1024 * 1024:
			since_yield = 0
			await (Engine.get_main_loop() as SceneTree).process_frame
	f.close()
	return ctx.finish().hex_encode()
