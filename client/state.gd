extends Node
## Состояние игрока и контент, полученные с сервера. Клиент их только показывает.

signal changed

var me: Dictionary = {}
var content: Dictionary = {}
var battle_result: Dictionary = {}
var start_tab: int = 0


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
		if a["kind"] == "passive":
			for k in a.get("mods", {}):
				if st.has(k):
					st[k] = float(st[k]) * float(a["mods"][k])
	return st
