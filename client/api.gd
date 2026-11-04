extends Node
## Сетевой слой клиента. Адрес сервера — единственная DEFAULT_SERVER_URL.
## Контракт методов: docs/api.md. Клиент ничего не считает сам: бой и награды приходят с сервера.

const DEFAULT_SERVER_URL := "https://tts-ufa.ru/games/server"
const SESSION_FILE := "user://session.cfg"

var token: String = ""
var server_url: String = DEFAULT_SERVER_URL  # для тестов можно переопределить переменной окружения FIVEUFA_SERVER


func _ready() -> void:
	var override := OS.get_environment("FIVEUFA_SERVER")
	if override != "":
		server_url = override
	var cf := ConfigFile.new()
	if cf.load(SESSION_FILE) == OK:
		token = str(cf.get_value("session", "token", ""))


func save_token(t: String) -> void:
	token = t
	var cf := ConfigFile.new()
	cf.set_value("session", "token", t)
	cf.save(SESSION_FILE)


func clear_token() -> void:
	token = ""
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_FILE))


## Возвращает {ok:bool, status:int, data:Variant, message:String}.
func request(method: String, path: String, body: Variant = null) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 20.0
	add_child(req)
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var verb := HTTPClient.METHOD_GET if method == "GET" else HTTPClient.METHOD_POST
	var payload := "" if body == null else JSON.stringify(body)
	var err := req.request(server_url + path, headers, verb, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "status": 0, "data": null, "message": "Не удалось отправить запрос (код %d)" % err}
	var res: Array = await req.request_completed
	req.queue_free()
	var result_code: int = res[0]
	var status: int = res[1]
	var raw: PackedByteArray = res[3]
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "data": null, "message": "Нет связи с сервером (код %d)" % result_code}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	var ok := status >= 200 and status < 300
	var msg := ""
	if not ok:
		msg = str(parsed.get("message", "Ошибка %d" % status)) if parsed is Dictionary else "Ошибка %d" % status
	return {"ok": ok, "status": status, "data": parsed, "message": msg}


## Скачивает файл (двоичный) на устройство. true, если ответ 200 и файл записан.
func download(path: String, dest: String) -> bool:
	var req := HTTPRequest.new()
	req.timeout = 180.0
	req.download_file = dest
	add_child(req)
	var err := req.request(server_url + path, ["Authorization: Bearer " + token] if token != "" else [])
	if err != OK:
		req.queue_free()
		return false
	var res: Array = await req.request_completed
	req.queue_free()
	return int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) == 200
