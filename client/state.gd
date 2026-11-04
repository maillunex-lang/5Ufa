extends Node
## Состояние игрока и контент, полученные с сервера. Клиент их только показывает.

signal changed

var me: Dictionary = {}
var content: Dictionary = {}
var battle_result: Dictionary = {}
var start_tab: int = 0
var flags: Dictionary = {}   # локальные отметки клиента (например, обучение), хранятся на устройстве
const FLAGS_FILE := "user://flags.cfg"


func _ready() -> void:
	var cf := ConfigFile.new()
	if cf.load(FLAGS_FILE) == OK:
		for k in cf.get_section_keys("flags"):
			flags[k] = cf.get_value("flags", k)


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value
	var cf := ConfigFile.new()
	for k in flags:
		cf.set_value("flags", k, flags[k])
	cf.save(FLAGS_FILE)


func clear_flags() -> void:
	flags.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(FLAGS_FILE))


func refresh_me() -> bool:
	var r: Dictionary = await Api.request("GET", "/api/me")
	if r["ok"]:
		me = r["data"]
		changed.emit()
	return r["ok"]


func load_content() -> bool:
	var r: Dictionary = await Api.request("GET", "/api/content")
	if r["ok"]:
		content = r["data"]
	return r["ok"]


func hero_def(key: String) -> Dictionary:
	for h in content.get("heroes", []):
		if h["key"] == key:
			return h
	return {}


func enemy_def(key: String) -> Dictionary:
	for h in content.get("enemies", []):
		if h["key"] == key:
			return h
	return {}


func owned_hero(id: int) -> Dictionary:
	for h in me.get("heroes", []):
		if int(h["id"]) == id:
			return h
	return {}


func max_cleared() -> int:
	var best := 0
	for s in me.get("clearedStages", []):
		best = maxi(best, int(s))
	return best


func loc(v: Variant) -> String:
	if typeof(v) == TYPE_STRING:
		return str(v)
	if typeof(v) == TYPE_DICTIONARY:
		return str((v as Dictionary).get("ru", ""))
	return ""


func story_done(id: String) -> bool:
	for q in me.get("storyDone", []):
		if str(q) == id:
			return true
	return false


## Характеристики героя на уровне (по тем же формулам, что на сервере; для показа игроку).
func hero_stats(key: String, level: int) -> Dictionary:
	var d := hero_def(key)
	if d.is_empty():
		return {}
	var g: float = 1.0 + float(content["progression"]["growth"]) * (level - 1)
	var st: Dictionary = (d["stats"] as Dictionary).duplicate()
	for k in ["hp", "atk", "def"]:
		st[k] = float(st[k]) * g
	for a in d["abilities"]:
		var ab: Variant = a
		if typeof(a) == TYPE_STRING:
			ab = {}
			for lib in content.get("abilities", []):
				if str(lib.get("id", "")) == str(a):
					ab = lib
					break
		if typeof(ab) != TYPE_DICTIONARY or ab.is_empty():
			continue
		if str(ab.get("kind", "")) == "passive":
			for k in ab.get("mods", {}):
				if st.has(k):
					st[k] = float(st[k]) * float(ab["mods"][k])
	return st
