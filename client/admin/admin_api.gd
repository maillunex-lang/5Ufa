extends Node
## Связь админки с сервером (/api/v1/admin/...). Токен админки хранится в user://admin_session.cfg
## (у APK админки своя папка данных, отдельная от игры). Пароль нигде не сохраняется.

signal logged_out

const SESSION_FILE := "user://admin_session.cfg"

var token := ""
var login := ""
var role := ""


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_FILE) == OK:
		token = str(cfg.get_value("admin", "token", ""))
		login = str(cfg.get_value("admin", "login", ""))
		role = str(cfg.get_value("admin", "role", ""))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("admin", "token", token)
	cfg.set_value("admin", "login", login)
	cfg.set_value("admin", "role", role)
	cfg.save(SESSION_FILE)


func forget() -> void:
	token = ""
	_save()
	logged_out.emit()


## Результат: {ok, code, data, bytes, error, errors: Array}
## body: Dictionary (JSON) или PackedByteArray (файл/ZIP) или null.
func call_api(method: int, path: String, body: Variant = null, raw := false) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 120.0
	req.body_size_limit = 300 * 1024 * 1024
	add_child(req)
	var headers := PackedStringArray(["Accept: application/json",
			"User-Agent: UfaGameAdmin/%s (%s)" % [Config.client_version, OS.get_name()]])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err: int
	var url := Api.api_url("/api/v1/admin" + path)
	if body is PackedByteArray:
		headers.append("Content-Type: application/octet-stream")
		err = req.request_raw(url, headers, method, body)
	else:
		var payload := ""
		if body != null:
			headers.append("Content-Type: application/json")
			payload = JSON.stringify(body)
		err = req.request(url, headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": {}, "bytes": PackedByteArray(), "error": "Нет связи с сервером", "errors": []}
	var r: Array = await req.request_completed
	req.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": 0, "data": {}, "bytes": PackedByteArray(),
				"error": "Нет связи с сервером (ошибка %d)" % r[0], "errors": []}
	var code: int = r[1]
	var bytes: PackedByteArray = r[3]
	var data: Variant = {}
	if not raw or code >= 300:
		var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8()) if bytes.size() > 0 else {}
		data = parsed if parsed != null else {}
	var ok := code >= 200 and code < 300
	var error := ""
	var errors: Array = []
	if not ok:
		var d: Variant = data.get("detail", "") if data is Dictionary else ""
		if d is Dictionary:
			error = str(d.get("message", "Ошибка"))
			errors = d.get("errors", [])
		elif d is String and d != "":
			error = d
		else:
			error = "Ошибка сервера (%d)" % code
		if code == 401 and path != "/auth/login":
			token = ""
			_save()
			logged_out.emit()
	return {"ok": ok, "code": code, "data": data, "bytes": bytes, "error": error, "errors": errors}


func do_login(user: String, password: String, code: String) -> Dictionary:
	var res := await call_api(HTTPClient.METHOD_POST, "/auth/login", {"login": user, "password": password, "code": code})
	if res.ok:
		token = str(res.data["token"])
		login = str(res.data["admin"]["login"])
		role = str(res.data["admin"]["role"])
		_save()
	elif res.code == 401 and res.data is Dictionary and bool(res.data.get("totp_required", false)):
		res["totp_required"] = true
		res["error"] = "Введите код из приложения-аутентификатора"
	return res


func do_logout() -> void:
	await call_api(HTTPClient.METHOD_POST, "/auth/logout", {})
	forget()
