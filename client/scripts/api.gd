extends Node
## Связь с сервером: JSON-запросы, токены, вход гостем / по почте.
## Сервер — источник истины: клиент ничего не меняет сам, только просит сервер.

signal player_changed(player: Dictionary)

const AUTH_FILE := "user://auth.cfg"
const DEVICE_FILE := "user://device.cfg"

var access_token := ""
var refresh_token := ""
var device_id := ""
var player: Dictionary = {}

# Разобранный адрес сервера
var scheme := "https"
var host := ""
var port := 443
var base_path := ""  # например /games/server


func _ready() -> void:
	_parse_server_url(Config.server_url)
	_load_device_id()
	_load_tokens()


func _parse_server_url(url: String) -> void:
	var rest := url
	if rest.begins_with("https://"):
		scheme = "https"
		rest = rest.substr(8)
	elif rest.begins_with("http://"):
		scheme = "http"
		rest = rest.substr(7)
	var slash := rest.find("/")
	var hostport := rest if slash == -1 else rest.substr(0, slash)
	base_path = "" if slash == -1 else rest.substr(slash).trim_suffix("/")
	port = 443 if scheme == "https" else 80
	var colon := hostport.rfind(":")
	if colon != -1:
		port = int(hostport.substr(colon + 1))
		hostport = hostport.substr(0, colon)
	host = hostport


func origin() -> String:
	var default_port := 443 if scheme == "https" else 80
	return "%s://%s%s" % [scheme, host, "" if port == default_port else ":%d" % port]


func api_url(path: String) -> String:
	return origin() + base_path + path


# --- Хранение ---------------------------------------------------------------

func _load_device_id() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(DEVICE_FILE) == OK:
		device_id = str(cfg.get_value("device", "id", ""))
	if device_id.length() < 16:
		device_id = Crypto.new().generate_random_bytes(16).hex_encode()
		cfg.set_value("device", "id", device_id)
		cfg.save(DEVICE_FILE)


func _load_tokens() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(AUTH_FILE) == OK:
		refresh_token = str(cfg.get_value("auth", "refresh_token", ""))
		player = cfg.get_value("auth", "player", {})


func _save_tokens() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("auth", "refresh_token", refresh_token)
	cfg.set_value("auth", "player", player)
	cfg.save(AUTH_FILE)


func _apply_tokens(data: Dictionary) -> void:
	access_token = str(data.get("access_token", ""))
	refresh_token = str(data.get("refresh_token", refresh_token))
	if data.has("player"):
		player = data["player"]
		player_changed.emit(player)
	_save_tokens()


# --- Запросы ----------------------------------------------------------------

## Результат: { ok: bool, code: int, data: Variant, error: String, headers: Dictionary }
func request_json(method: int, path: String, body: Variant = null, use_auth := true,
		extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var res := await _do_request(method, path, body, use_auth, extra_headers)
	if res.code == 401 and use_auth and refresh_token != "" and path != "/api/v1/auth/refresh":
		if await refresh():
			res = await _do_request(method, path, body, use_auth, extra_headers)
	return res


func _do_request(method: int, path: String, body: Variant, use_auth: bool,
		extra_headers: PackedStringArray) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 25.0
	add_child(req)
	var headers := PackedStringArray([
		"Accept: application/json",
		"User-Agent: UfaGame/%s (%s)" % [Config.client_version, OS.get_name()],
	])
	headers.append_array(extra_headers)
	var payload := ""
	if body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	if use_auth and access_token != "":
		headers.append("Authorization: Bearer " + access_token)
	var err := req.request(api_url(path), headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "data": {}, "error": "Нет связи с сервером", "headers": {}}
	var r: Array = await req.request_completed
	req.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	var resp_headers := {}
	for h in r[2]:
		var i := str(h).find(":")
		if i > 0:
			resp_headers[str(h).substr(0, i).strip_edges().to_lower()] = str(h).substr(i + 1).strip_edges()
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": 0, "data": {}, "headers": {},
				"error": "Нет связи с сервером. Проверьте интернет (ошибка %d)" % result}
	var raw: PackedByteArray = r[3]
	var data: Variant = {}
	if raw.size() > 0:
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed != null:
			data = parsed
	var ok := code >= 200 and code < 300
	var message := ""
	if not ok and code != 304:
		message = _error_text(code, data)
	return {"ok": ok, "code": code, "data": data, "error": message, "headers": resp_headers}


func _error_text(code: int, data: Variant) -> String:
	if data is Dictionary and data.has("detail"):
		var d: Variant = data["detail"]
		if d is String:
			return d
		return "Проверьте правильность введённых данных"
	if code >= 500:
		return "Сервер временно недоступен (%d). Попробуйте позже" % code
	return "Ошибка сервера (%d)" % code


func _device_body() -> Dictionary:
	return {"device_id": device_id, "client_version": Config.client_version}


# --- Аккаунт ----------------------------------------------------------------

## Войти: обновить сохранённую сессию, а если её нет — войти гостем.
func ensure_session() -> Dictionary:
	if refresh_token != "" and await refresh():
		return {"ok": true, "error": ""}
	var had_email := player.get("email") != null and str(player.get("email", "")) != ""
	var res := await request_json(HTTPClient.METHOD_POST, "/api/v1/auth/guest", _device_body(), false)
	if not res.ok:
		return {"ok": false, "error": res.error}
	_apply_tokens(res.data)
	if had_email:
		return {"ok": true, "error": "", "notice": "Сессия истекла. Войдите по почте, чтобы вернуться к своему аккаунту."}
	return {"ok": true, "error": ""}


func refresh() -> bool:
	if refresh_token == "":
		return false
	var res := await _do_request(HTTPClient.METHOD_POST, "/api/v1/auth/refresh",
			{"refresh_token": refresh_token}, false, PackedStringArray())
	if res.ok:
		_apply_tokens(res.data)
		return true
	if res.code == 401 or res.code == 403:
		refresh_token = ""
		access_token = ""
		_save_tokens()
	return false


func link_email(email: String, password: String) -> Dictionary:
	var res := await request_json(HTTPClient.METHOD_POST, "/api/v1/auth/link-email",
			{"email": email, "password": password})
	if res.ok:
		player = res.data["player"]
		_save_tokens()
		player_changed.emit(player)
	return res


func login_email(email: String, password: String) -> Dictionary:
	var body := _device_body()
	body["email"] = email
	body["password"] = password
	var res := await request_json(HTTPClient.METHOD_POST, "/api/v1/auth/login", body, false)
	if res.ok:
		_apply_tokens(res.data)
	return res


func is_guest() -> bool:
	return bool(player.get("is_guest", true))
