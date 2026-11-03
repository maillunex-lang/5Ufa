extends Control
## Проигрывание боя по журналу сервера (вид сбоку 5 на 5).
## Скорость x1/x2/x4, «Пропустить», экран результата. Журнал: docs/battle.md

const CENTER_X := 360.0
const PX_PER_UNIT := 54.0
const FIELD_TOP := 430.0
const FIELD_H := 380.0
const ULT_COLORS := [Color("#FFE27A"), Color("#FF9F5A")]

var log_data: Dictionary = {}
var enemy_name := ""
var tick_rate := 20
var events: Array = []
var idx := 0
var game_time := 0.0
var speed := 1.0
var units: Dictionary = {}       # uid -> UnitView
var projectiles: Array = []      # {node, src, dst_uid, t0, t1}
var finished := false
var _field: Node2D
var _timer_label: Label
var _speed_btn: Button
var _banner: Label
var _portraits: Dictionary = {}  # uid -> {bar, icon}
var _result_shown := false
var _skill_names: Dictionary = {}
var live := false
var socket: WebSocketPeer
var live_until := 0
var live_ended := false
var live_auto := false
var _auto_btn: Button
var _skip_requested := false


func _ready() -> void:
	live = get_tree().has_meta("battle_live")
	if live:
		if not await _connect_live():
			return
	else:
		log_data = get_tree().get_meta("battle_log", {})
	enemy_name = str(get_tree().get_meta("battle_enemy_name", "Противник"))
	if log_data.is_empty():
		get_tree().change_scene_to_file("res://scenes/main.tscn")
		return
	tick_rate = int(log_data["tick_rate"])
	events = log_data["events"]
	speed = 1.0 if live else float(_load_setting("speed", 1.0))
	theme = Ui.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_field = Node2D.new()
	add_child(_field)
	for u in log_data["units"]:
		var v := UnitView.new()
		_field.add_child(v)
		v.setup(u, int(log_data["energy_max"]))
		v.rig.speed = speed
		v.position = _to_screen(float(u["x"]), float(u["lane"]))
		units[int(u["uid"])] = v
		for s in u.get("skills", []):
			_skill_names[str(s["id"])] = str(s["name"])
	_sort_depth()
	_build_hud()
	if Config.autotest:
		_autotest()


func _connect_live() -> bool:
	socket = WebSocketPeer.new()
	socket.inbound_buffer_size = 2 * 1024 * 1024
	socket.handshake_headers = PackedStringArray(["Authorization: Bearer " + Api.access_token])
	var url: String = Api.api_url("/ws/battle/campaign" if get_tree().has_meta("campaign_stage") else "/ws/battle/test")
	url = ("wss://" + url.substr(8)) if url.begins_with("https://") else ("ws://" + url.substr(7))
	if socket.connect_to_url(url) != OK:
		_live_error("Не удалось подключиться к бою")
		return false
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		socket.poll()
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and socket.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
			if msg is Dictionary and msg.get("type") == "start":
				log_data = msg["log"]
				return true
			_live_error(str(msg.get("message", "Не удалось начать бой")) if msg is Dictionary else "Ошибка ответа сервера")
			return false
		if socket.get_ready_state() == WebSocketPeer.STATE_OPEN and not socket.has_meta("sent"):
			socket.send_text(JSON.stringify(get_tree().get_meta("battle_live")))
			socket.set_meta("sent", true)
		if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			break
		await get_tree().process_frame
	_live_error("Нет связи с сервером боя")
	return false


func _live_error(message: String) -> void:
	finished = true
	if Config.autotest:
		print("AUTOTEST FAIL: ", message)
		get_tree().quit(1)
		return
	var col := Ui.screen(self)
	col.add_child(Ui.label(message + "\nЕсли бой начался, он будет досчитан автоматически.", 26))
	col.add_child(Ui.button("Назад", func(): get_tree().change_scene_to_file("res://scenes/team_select.tscn")))


# --- Построение экрана ------------------------------------------------------------

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Ui.colors["background"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var tex := Content.load_texture("campaign/chapter_1/background.png")
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.modulate = Color(1, 1, 1, 0.55)
		add_child(tr)
	var ground := ColorRect.new()
	ground.color = Color(0.1, 0.16, 0.12, 0.55)
	ground.position = Vector2(0, FIELD_TOP - 40)
	ground.size = Vector2(720, FIELD_H + 120)
	add_child(ground)


func _build_hud() -> void:
	var top := Ui.label("Тестовый бой  ·  против: %s" % enemy_name, 26, "accent")
	top.position = Vector2(0, 40)
	top.size = Vector2(720, 40)
	add_child(top)
	_timer_label = Ui.label("1:30", 30)
	_timer_label.position = Vector2(0, 84)
	_timer_label.size = Vector2(720, 40)
	add_child(_timer_label)
	_banner = Ui.label("", 34, "accent")
	_banner.position = Vector2(0, 240)
	_banner.size = Vector2(720, 60)
	_banner.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.12))
	_banner.add_theme_constant_override("outline_size", 8)
	var banner_layer := CanvasLayer.new()
	banner_layer.layer = 5
	add_child(banner_layer)
	banner_layer.add_child(_banner)

	# Портреты своих героев с энергией (кнопки ультимейтов)
	var row := HBoxContainer.new()
	row.position = Vector2(20, 960)
	row.size = Vector2(680, 140)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	for u in log_data["units"]:
		if int(u["side"]) != 0:
			continue
		var box := VBoxContainer.new()
		var icon := Button.new()
		icon.icon = Content.load_texture("heroes/%s/portrait.png" % u["hero"])
		icon.custom_minimum_size = Vector2(118, 118)
		icon.expand_icon = true
		icon.pressed.connect(_request_ult.bind(int(u["uid"])))
		box.add_child(icon)
		var bar := ProgressBar.new()
		bar.max_value = float(log_data["energy_max"])
		bar.value = float(u.get("energy", 0))
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(118, 14)
		box.add_child(bar)
		row.add_child(box)
		_portraits[int(u["uid"])] = {"bar": bar, "icon": icon}

	var controls := HBoxContainer.new()
	controls.position = Vector2(20, 1130)
	controls.size = Vector2(680, 100)
	controls.add_theme_constant_override("separation", 16)
	add_child(controls)
	_auto_btn = Ui.button("Авто: ВЫКЛ" if live else "Авто: ВКЛ", _toggle_auto)
	_auto_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_btn.disabled = not live
	controls.add_child(_auto_btn)
	_speed_btn = Ui.button("x%d" % speed, _toggle_speed)
	_speed_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_speed_btn.disabled = live
	controls.add_child(_speed_btn)
	var skip := Ui.button("Пропустить", _skip)
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(skip)


func _to_screen(x: float, lane: float) -> Vector2:
	return Vector2(CENTER_X + x * PX_PER_UNIT, FIELD_TOP + lane * FIELD_H)


func _sort_depth() -> void:
	for v in units.values():
		v.z_index = int(v.position.y)


# --- Воспроизведение ----------------------------------------------------------------

func _process(delta: float) -> void:
	if finished or log_data.is_empty():
		return
	if live:
		_poll_live()
		if finished:
			return
	var dt := delta * speed
	if live and not live_ended:
		dt = minf(dt, maxf(0.0, float(live_until) / tick_rate - game_time))
	game_time += dt
	var tick := game_time * tick_rate
	while idx < events.size() and float(events[idx]["t"]) <= tick:
		_apply(events[idx], false)
		idx += 1
	for v in units.values():
		if v.vx != 0.0 and not v.dead:
			v.x_units += v.vx * dt
			v.position.x = CENTER_X + v.x_units * PX_PER_UNIT
	_update_projectiles(tick)
	var left := maxf(0.0, float(log_data["max_ticks"]) / tick_rate - game_time)
	_timer_label.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	if idx >= events.size() and projectiles.is_empty() and (not live or live_ended):
		_finish()


func _poll_live() -> void:
	socket.poll()
	while socket.get_available_packet_count() > 0:
		var msg: Variant = JSON.parse_string(socket.get_packet().get_string_from_utf8())
		if not msg is Dictionary:
			continue
		match str(msg.get("type", "")):
			"events":
				events.append_array(msg.get("events", []))
				live_until = int(msg.get("until", live_until))
			"end":
				events.append_array(msg.get("events", []))
				log_data["result"] = msg["result"]
				if get_tree().has_meta("campaign_stage") and msg.get("campaign_reward") is Dictionary:
					get_tree().set_meta("campaign_reward", msg["campaign_reward"])
				live_ended = true
				socket.send_text(JSON.stringify({"type": "ack"}))
				if _skip_requested:
					_skip()
			"error":
				_live_error(str(msg.get("message", "Ошибка боя")))
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED and not live_ended and not finished:
		_live_error("Связь с боем потеряна")


func _request_ult(uid: int) -> void:
	if live and not live_auto and not live_ended and not finished and _portraits[uid]["bar"].value >= float(log_data["energy_max"]):
		socket.send_text(JSON.stringify({"type": "ult", "uid": uid}))


func _toggle_auto() -> void:
	if live and not live_ended:
		live_auto = not live_auto
		_auto_btn.text = "Авто: ВКЛ" if live_auto else "Авто: ВЫКЛ"
		socket.send_text(JSON.stringify({"type": "auto", "on": live_auto}))


func _apply(e: Dictionary, instant: bool) -> void:
	var u: UnitView = units.get(int(e.get("u", -1)))
	match str(e["e"]):
		"move":
			u.x_units = float(e["x"])
			u.vx = float(e["vx"])
			if not instant and u.rig.current in ["idle", "walk", ""]:
				u.rig.play("walk")
		"stop":
			u.x_units = float(e["x"])
			u.vx = 0.0
			u.position.x = CENTER_X + u.x_units * PX_PER_UNIT
			if not instant and u.rig.current == "walk":
				u.rig.play("idle")
		"attack":
			if instant:
				return
			u.rig.play("attack")
			if bool(e.get("projectile", false)):
				_spawn_projectile(u, int(e["target"]), float(e["t"]), float(e["hit_t"]))
		"cast":
			if instant:
				return
			u.rig.play(str(e.get("anim", "skill")))
			if str(e.get("kind", "")) == "ultimate":
				_flash_banner("%s: %s" % [u.info["name"], _skill_names.get(str(e["skill"]), "")])
				u.flash(ULT_COLORS[u.side], speed)
		"impact":
			if instant:
				return
			for tuid in e.get("targets", []):
				var tv: UnitView = units.get(int(tuid))
				if tv and not tv.dead:
					tv.flash(Color(1.6, 1.6, 1.6), speed)
		"damage":
			u.set_hp(int(e["hp"]))
			if e.has("shield"):
				u.set_shield(int(e["shield"]))
			if not instant:
				var crit := bool(e.get("crit", false))
				u.float_text(("%d!" if crit else "%d") % int(e["amount"]),
						Color("#FFD23F") if crit else Color("#FFFFFF"), crit, speed)
				if u.rig.current in ["idle", "walk"]:
					u.rig.play("hit")
		"heal":
			u.set_hp(int(e["hp"]))
			if not instant and int(e["amount"]) > 0:
				u.float_text("+%d" % int(e["amount"]), Color("#6CF07A"), false, speed)
		"shield":
			u.set_shield(int(e["value"]))
		"stun":
			u.stunned_until = int(e["until"])
			u.set_status("✦ оглушён")
		"buff":
			if not instant:
				var up := float(e.get("percent", 0)) >= 0
				u.float_text(("▲ " if up else "▼ ") + _stat_name(str(e.get("stat", ""))),
						Color("#8FD3FF") if up else Color("#C88FFF"), false, speed)
		"energy":
			u.set_energy(int(e["value"]))
			if _portraits.has(u.uid):
				_portraits[u.uid]["bar"].value = float(e["value"])
		"death":
			u.die()
			if instant:
				u.rig.speed = 100.0
			if _portraits.has(u.uid):
				_portraits[u.uid]["icon"].modulate = Color(0.35, 0.35, 0.35)
		"victory":
			u.rig.play("victory")
	# снять значок оглушения, когда истёк
	for v in units.values():
		if v.stunned_until >= 0 and float(e["t"]) >= v.stunned_until:
			v.stunned_until = -1
			v.set_status("")


func _stat_name(stat: String) -> String:
	return {"atk": "атака", "def": "защита", "crit_chance": "крит", "attack_speed": "скорость"}.get(stat, stat)


func _spawn_projectile(src: UnitView, dst_uid: int, t_attack: float, hit_t: float) -> void:
	var hero: Variant = Content.load_json("heroes/%s/hero.json" % src.info["hero"])
	var path := str(hero.get("art", {}).get("projectile", "")) if hero is Dictionary else ""
	var spr := Sprite2D.new()
	spr.texture = SkeletonRig.load_texture(path) if path != "" else null
	if spr.texture == null:
		spr.queue_free()
		return
	spr.visible = false
	spr.z_index = 2000
	_field.add_child(spr)
	var t0 := minf(t_attack + 0.4 * tick_rate, hit_t - 1.0)
	projectiles.append({"node": spr, "src": src, "dst": dst_uid, "t0": t0, "t1": hit_t})


func _update_projectiles(tick: float) -> void:
	for p in projectiles.duplicate():
		var spr: Sprite2D = p["node"]
		var dst: UnitView = units.get(p["dst"])
		if tick >= p["t1"] or dst == null:
			spr.queue_free()
			projectiles.erase(p)
			continue
		if tick < p["t0"]:
			continue
		var src: UnitView = p["src"]
		var a: Vector2 = src.position + src.rig.anchor_position("projectile")
		var b: Vector2 = dst.position + dst.rig.anchor_position("hit")
		var f: float = (tick - float(p["t0"])) / maxf(0.001, float(p["t1"]) - float(p["t0"]))
		spr.visible = true
		spr.position = a.lerp(b, f) + Vector2(0, -sin(f * PI) * 30)
		spr.rotation = (b - a).angle()


func _flash_banner(text: String) -> void:
	_banner.text = text
	_banner.modulate.a = 1.0
	var tw := create_tween().set_speed_scale(speed)
	tw.tween_interval(1.0)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func _toggle_speed() -> void:
	speed = {1.0: 2.0, 2.0: 4.0, 4.0: 1.0}.get(speed, 1.0)
	_speed_btn.text = "x%d" % speed
	_save_setting("speed", speed)
	for v in units.values():
		v.rig.speed = speed


func _skip() -> void:
	if live and not live_ended:
		_skip_requested = true
		socket.send_text(JSON.stringify({"type": "skip"}))
		return
	while idx < events.size():
		_apply(events[idx], true)
		idx += 1
	for p in projectiles:
		p["node"].queue_free()
	projectiles.clear()
	for v in units.values():
		v.vx = 0
		v.position.x = CENTER_X + v.x_units * PX_PER_UNIT
	game_time = float(log_data["result"]["ticks"]) / tick_rate
	_finish()


func _finish() -> void:
	if _result_shown:
		return
	_result_shown = true
	finished = true
	var win := int(log_data["result"]["winner"]) == 0
	await get_tree().create_timer(0.8 / speed).timeout
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.size = Vector2(720, 1280)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.theme = theme
	panel.position = Vector2(60, 300)
	panel.custom_minimum_size = Vector2(600, 0)
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(Ui.label("ПОБЕДА!" if win else "Поражение", 56, "accent"))
	if get_tree().has_meta("campaign_stage"):
		var reward: Dictionary = get_tree().get_meta("campaign_reward", {})
		box.add_child(Ui.label("Награда: " + Ui.cost_text(reward), 22))
	var secs := float(log_data["result"]["ticks"]) / tick_rate
	box.add_child(Ui.label("Время боя: %d:%02d" % [int(secs) / 60, int(secs) % 60], 24))
	var stats: Array = log_data["result"]["stats"]
	var best := 1
	for s in stats:
		best = max(best, int(s["damage"]))
	for s in stats:
		var u: Dictionary = log_data["units"][int(s["uid"])]
		if int(u["side"]) != 0:
			continue
		var line := HBoxContainer.new()
		var name := Label.new()
		name.text = str(u["name"])
		name.custom_minimum_size = Vector2(170, 0)
		line.add_child(name)
		var bar := ProgressBar.new()
		bar.max_value = best
		bar.value = int(s["damage"])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(260, 22)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(bar)
		var num := Label.new()
		num.text = "  %d" % int(s["damage"])
		line.add_child(num)
		box.add_child(line)
	box.add_child(Ui.button("К кампании" if get_tree().has_meta("campaign_stage") else "Ещё раз", func(): get_tree().change_scene_to_file("res://scenes/campaign.tscn" if get_tree().has_meta("campaign_stage") else "res://scenes/team_select.tscn")))
	box.add_child(Ui.button("На главный экран", func():
		get_tree().remove_meta("campaign_stage")
		get_tree().change_scene_to_file("res://scenes/main.tscn")))
	if Config.autotest:
		get_tree().set_meta("autotest_result_shown", true)


func _load_setting(key: String, def: Variant) -> Variant:
	var cfg := ConfigFile.new()
	return cfg.get_value("battle", key, def) if cfg.load("user://settings.cfg") == OK else def


func _save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value("battle", key, value)
	cfg.save("user://settings.cfg")


# --- Автопроверка ----------------------------------------------------------------------

func _autotest() -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			shot = arg.get_slice("=", 1)
	speed = 1.0 if live else 4.0
	for v in units.values():
		v.rig.speed = speed
	await get_tree().create_timer(1.6).timeout   # ~6 с боя на x4
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_fight.png"))
	_skip()
	var deadline: int = Time.get_ticks_msec() + 10000
	while not _result_shown and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not _result_shown:
		print("AUTOTEST FAIL: Нет результата боя")
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.5).timeout
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_result.png"))
	var dead_views := 0
	for v in units.values():
		if v.dead:
			dead_views += 1
	var expected_dead: int = units.size() - int(log_data["result"]["survivors"].size())
	var ok: bool = _result_shown and dead_views == expected_dead and units.size() == log_data["units"].size()
	print("AUTOTEST BATTLE: ", JSON.stringify({"ok": ok, "units": units.size(), "events": events.size(),
			"winner": log_data["result"]["winner"], "dead": dead_views, "expected_dead": expected_dead}))
	get_tree().quit(0 if ok else 1)
