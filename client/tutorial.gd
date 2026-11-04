extends Control
## Короткое обучение с пропуском. Шаги и тексты берутся из данных (content.tutorial.steps), логика условий —
## из каталога: stage_cleared:N, hero_upgraded, button_ack. Подсвечиваемые элементы: tab:N, stage:N, stage:next, upgrade:first.
## Отметку «пройдено» сервер хранит в аккаунте; промежуточные отметки — на устройстве (State.flags).

var _hub: Control
var _panel: PanelContainer
var _text: Label
var _ack: Button
var _tweens: Array = []
var _targets: Array = []
var _busy := false


func setup(hub: Control) -> void:
	_hub = hub
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = Ui.panel(Color(0.18, 0.2, 0.3, 0.97))
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN   # растёт вверх от нижней кромки
	_panel.offset_left = 16
	_panel.offset_right = -16
	_panel.offset_bottom = -130
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	_text = Ui.label("", 26)
	v.add_child(_text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	_ack = Ui.button("Понятно", 26, 72)
	_ack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_ack)
	var skip := Ui.button("Пропустить обучение", 24, 72)
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip.pressed.connect(_skip)
	row.add_child(skip)
	_panel.visible = false
	State.changed.connect(refresh)
	refresh()


func _steps() -> Array:
	return State.content.get("tutorial", {}).get("steps", [])


func _is_done(step: Dictionary) -> bool:
	var cond := str(step.get("done", ""))
	if cond.begins_with("stage_cleared:"):
		var want := int(cond.get_slice(":", 1))
		for c in State.me.get("clearedStages", []):   # с сервера приходят числа вида 1.0
			if int(c) == want:
				return true
		return false
	if cond == "hero_upgraded":
		if State.flags.has("tut_upgraded"):
			return true
		for h in State.me.get("heroes", []):
			if int(h["level"]) > 1:
				return true
		return false
	if cond == "button_ack":
		return State.flags.has("tut_ack_" + str(step.get("id", "")))
	return true


func refresh() -> void:
	# вкладки перестраиваются по тому же сигналу — даём им кадр
	await get_tree().process_frame
	await get_tree().process_frame
	_clear_highlight()
	if State.me.get("account", {}).get("tutorialDone", false) or State.flags.has("tut_skipped"):
		_panel.visible = false
		return
	var steps := _steps()
	var cur := -1
	for i in steps.size():
		if not _is_done(steps[i]):
			cur = i
			break
	if cur == -1:
		_panel.visible = false
		_finish()
		return
	var st: Dictionary = steps[cur]
	_text.text = "Обучение %d/%d\n%s" % [cur + 1, steps.size(), str(st.get("text", ""))]
	_ack.visible = str(st.get("done", "")) == "button_ack"
	for c in _ack.pressed.get_connections():
		_ack.pressed.disconnect(c["callable"])
	_ack.pressed.connect(func():
		State.set_flag("tut_ack_" + str(st.get("id", "")))
		refresh())
	_panel.visible = true
	for h in st.get("highlight", []):
		_highlight(str(h))


func _find(h: String) -> Control:
	var kind := h.get_slice(":", 0)
	var arg := h.get_slice(":", 1)
	if kind == "tab":
		var i := int(arg)
		var tabs: Array = _hub._tab_buttons
		return tabs[i] if i >= 0 and i < tabs.size() else null
	var group := ""
	if kind == "stage":
		group = "stage_next" if arg == "next" else "stage_" + arg
	elif kind == "upgrade" and arg == "first":
		group = "upgrade_first"
	if group != "":
		var nodes := get_tree().get_nodes_in_group(group)
		for n in nodes:
			if n is Control and (n as Control).is_visible_in_tree():
				return n
	return null


func _highlight(h: String) -> void:
	var c := _find(h)
	if c == null:
		return
	_targets.append(c)
	var tw := c.create_tween().set_loops()
	tw.tween_property(c, "modulate", Color(1.7, 1.45, 0.6), 0.5)
	tw.tween_property(c, "modulate", Color.WHITE, 0.5)
	_tweens.append(tw)


func _clear_highlight() -> void:
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for c in _targets:
		if is_instance_valid(c):
			(c as Control).modulate = Color.WHITE
	_targets.clear()


func _skip() -> void:
	State.set_flag("tut_skipped")
	await Api.request("POST", "/api/tutorial/done", {})
	State.me["account"]["tutorialDone"] = true
	refresh()


func _finish() -> void:
	if _busy:
		return
	_busy = true
	State.set_flag("tut_skipped")
	await Api.request("POST", "/api/tutorial/done", {})
	State.me["account"]["tutorialDone"] = true
