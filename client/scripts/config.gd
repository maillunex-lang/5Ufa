extends Node
## Настройки клиента. Адрес сервера можно переопределить при запуске:
##   godot --path client -- --server=http://127.0.0.1:8085
## Флаг --autotest: пройти загрузку и вход автоматически и закрыть игру (для проверок в CI).

const DEFAULT_SERVER_URL := "https://tts-ufa.ru/games/server"

var server_url: String = DEFAULT_SERVER_URL
var client_version: String = "0.0.0"
var autotest := false


func _ready() -> void:
	client_version = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="):
			server_url = arg.substr("--server=".length()).strip_edges().trim_suffix("/")
		elif arg == "--autotest":
			autotest = true


## Сравнение версий вида 1.2.3: -1, 0 или 1
static func compare_versions(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(max(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return -1 if x < y else 1
	return 0
