class_name ScreenLayout
extends RefCounted
## Раскладка экранов из контента: ui/screens/<экран>.json (схема screen_layout.schema.json).
## Экран = фон + элементы на холсте 720×1280: надписи, картинки, кнопки, панели и «места» (slot) —
## туда код экрана кладёт живое содержимое (списки героев, кошелёк, поле боя).
## Нет файла в контенте — берётся встроенный res://layouts/<экран>.json (тот же формат).
## Конструктор экранов в админке рисует экран этим же кодом (ctx.edit = true).

const W := 720.0
const H := 1280.0
const SCENES := {"hub": "res://scenes/main.tscn", "campaign": "res://scenes/campaign.tscn",
		"heroes": "res://scenes/heroes.tscn", "summon": "res://scenes/summon.tscn",
		"test_battle": "res://scenes/team_select.tscn", "inventory": "res://scenes/inventory.tscn"}
const OUTLINE := Color(0.06, 0.03, 0.1)

## Правка в игре (админка): изменённые, ещё не сохранённые раскладки и последний построенный экран
static var overrides: Dictionary = {}
static var current: Dictionary = {}       # {"screen", "layout", "nodes", "root", "view", "insets"}


## Размер экрана в единицах игры: ширина 720, высота под пропорции телефона (у вытянутых больше 1280)
static func view_size() -> Vector2:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var r: Vector2 = (loop as SceneTree).root.get_visible_rect().size
		if r.x > 0 and r.y > 0:
			return r
	return Vector2(W, H)


## Безопасная зона (вырез камеры, системные панели) в единицах игры: Vector2(сверху, снизу)
static func safe_insets(view: Vector2) -> Vector2:
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var k := view.y / float(win.y)
	return Vector2(maxf(0, safe.position.y * k), maxf(0, (win.y - safe.end.y) * k))


## Где элемент окажется на реальном экране. Привязка (anchor): auto | top | center | bottom | stretch.
## auto: высокие элементы растягиваются, нижние держатся у низа, средние — по центру, верхние — у верха.
static func place(el: Dictionary, view: Vector2, insets: Vector2 = Vector2.ZERO) -> Rect2:
	var x := float(el.get("x", 0))
	var y := float(el.get("y", 0))
	var w := float(el.get("w", 100))
	var h := float(el.get("h", 50))
	var ex := view.x - W
	var ey := view.y - H
	var anchor := str(el.get("anchor", "auto"))
	if anchor == "auto":
		var cy := y + h / 2.0
		anchor = "stretch" if h >= 900 else ("bottom" if cy >= 820 else ("center" if cy >= 460 else "top"))
	match anchor:
		"top":
			if y <= 4:
				h += insets.x  # прижат к самому верху (затемнение) — растёт под вырез
			else:
				y += insets.x
		"center":
			y += ey / 2.0 + (insets.x - insets.y) / 2.0
		"bottom":
			y += ey - insets.y
		"stretch":
			if y > 4:
				y += insets.x
				h += ey - insets.x - insets.y
			else:
				h += ey  # во весь экран (фон города и т. п.)
	if w >= W - 24:
		w += ex  # во всю ширину — растягиваем
	else:
		x += ex / 2.0  # остальное — по центру широких экранов
	return Rect2(x, y, w, h)


static func load_layout(screen: String) -> Dictionary:
	if overrides.has(screen):
		return overrides[screen]
	var d: Variant = Content.load_json("ui/screens/%s.json" % screen)
	if d is Dictionary and d.has("elements"):
		return d
	var f := FileAccess.open("res://layouts/%s.json" % screen, FileAccess.READ)
	if f:
		var b: Variant = JSON.parse_string(f.get_as_text())
		if b is Dictionary:
			return b
	return {"elements": []}


## Обычный экран меню: строит раскладку и возвращает колонку внутри места «content».
## actions: {"back": Callable, ...} — для кнопок с действием {"call": "..."}.
static func screen(root: Control, name: String, actions: Dictionary = {}, widgets: Dictionary = {}) -> VBoxContainer:
	root.theme = Ui.make_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var old := root.get_node_or_null("Layout")
	if old:
		root.remove_child(old)
		old.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	var w := widgets.duplicate()
	w["content"] = func(box: Control, _el: Dictionary): box.add_child(col)
	var built := build(load_layout(name), {"actions": actions, "widgets": w, "screen": name})
	built["root"].name = "Layout"
	root.add_child(built["root"])
	root.move_child(built["root"], 0)
	if col.get_parent() == null:  # в раскладке нет места content — колонка на весь экран
		built["root"].add_child(col)
	return col


## Построить экран. ctx: actions {имя: Callable}, widgets {имя: Callable(контейнер, элемент)},
## badges Callable(вид, кнопка, позиция), on_action Callable(действие), edit bool, settings Dictionary.
## Результат: {"root": Control, "nodes": {id: Control}}
static func build(layout: Dictionary, ctx: Dictionary) -> Dictionary:
	var view: Vector2 = ctx.get("view", Vector2(W, H) if ctx.get("edit", false) else view_size())
	var insets: Vector2 = ctx.get("insets", Vector2.ZERO if ctx.get("edit", false) else safe_insets(view))
	var root := Control.new()
	root.size = view
	root.custom_minimum_size = view
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE if ctx.get("edit", false) else Control.MOUSE_FILTER_PASS
	var bg: Dictionary = layout.get("background", {})
	if bg.has("color") or not bg.has("image"):
		var cr := ColorRect.new()
		cr.color = _color(str(bg.get("color", "background")))
		cr.size = view
		cr.set_anchors_preset(Control.PRESET_FULL_RECT)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(cr)
	if bg.has("image"):
		var tr := TextureRect.new()
		tr.texture = Content.load_texture(str(bg["image"]))
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.size = view
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.modulate.a = float(bg.get("alpha", 1.0))
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
	var nodes := {}
	for el in layout.get("elements", []):
		if not bool(el.get("visible", true)) and not ctx.get("edit", false):
			continue
		var node := make_element(el, ctx)
		if node == null:
			continue
		var rect := place(el, view, insets)
		node.position = rect.position
		node.size = rect.size
		if ctx.get("edit", false):
			_ignore_mouse(node)
			if not bool(el.get("visible", true)):
				node.modulate.a = 0.35
		root.add_child(node)
		nodes[str(el.get("id", ""))] = node
	if ctx.has("screen") and not ctx.get("edit", false):
		current = {"screen": str(ctx["screen"]), "layout": layout, "nodes": nodes, "root": root, "view": view, "insets": insets}
	return {"root": root, "nodes": nodes}


static func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


static func _color(v: String) -> Color:
	if Ui.colors.has(v):
		return Ui.colors[v]
	return Color.from_string(v, Color.WHITE)


static func text_of(el: Dictionary, ctx: Dictionary) -> String:
	var t := str(el.get("text", ""))
	var settings: Variant = ctx.get("settings", Content.load_json("config/game_settings.json"))
	if settings is Dictionary:
		t = t.replace("{game_name}", str(settings.get("game_name", "")))
	return t.replace("{version}", Config.client_version)


static func make_element(el: Dictionary, ctx: Dictionary) -> Control:
	var type := str(el.get("type", "label"))
	match type:
		"label":
			var l := Label.new()
			l.text = text_of(el, ctx)
			l.add_theme_font_size_override("font_size", int(el.get("size", 26)))
			l.add_theme_color_override("font_color", _color(str(el.get("color", "text"))))
			l.horizontal_alignment = {"left": HORIZONTAL_ALIGNMENT_LEFT, "right": HORIZONTAL_ALIGNMENT_RIGHT}.get(
					str(el.get("align", "center")), HORIZONTAL_ALIGNMENT_CENTER)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			if int(el.get("outline", 0)) > 0:
				l.add_theme_color_override("font_outline_color", OUTLINE)
				l.add_theme_constant_override("outline_size", int(el["outline"]))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return l
		"image":
			var tr := TextureRect.new()
			tr.texture = Content.load_texture(str(el.get("image", "")))
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = {"cover": TextureRect.STRETCH_KEEP_ASPECT_COVERED, "stretch": TextureRect.STRETCH_SCALE}.get(
					str(el.get("fit", "contain")), TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
			tr.modulate.a = float(el.get("alpha", 1.0))
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return tr
		"panel":
			var p := Panel.new()
			var st := StyleBoxFlat.new()
			st.bg_color = _color(str(el.get("color", "#120C22E0")))
			st.border_color = _color(str(el.get("border", "#00000000")))
			st.set_border_width_all(int(el.get("border_width", 0)))
			st.set_corner_radius_all(int(el.get("radius", 0)))
			p.add_theme_stylebox_override("panel", st)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if str(el.get("gradient", "")) == "down":  # затемнение сверху вниз (под верхней панелью)
				var g := Gradient.new()
				g.set_color(0, st.bg_color)
				g.set_color(1, Color(st.bg_color, 0.0))
				var gt := GradientTexture2D.new()
				gt.gradient = g
				gt.fill_from = Vector2(0, 0)
				gt.fill_to = Vector2(0, 1)
				var tr2 := TextureRect.new()
				tr2.texture = gt
				tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr2.stretch_mode = TextureRect.STRETCH_SCALE
				tr2.set_anchors_preset(Control.PRESET_FULL_RECT)
				tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
				p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
				p.add_child(tr2)
			return p
		"button":
			return _make_button(el, ctx)
		"slot":
			var box := Control.new()
			box.mouse_filter = Control.MOUSE_FILTER_PASS
			box.clip_contents = bool(el.get("clip", false))
			if ctx.get("edit", false):
				var ph := ColorRect.new()
				ph.color = Color(0.3, 0.6, 1.0, 0.18)
				ph.set_anchors_preset(Control.PRESET_FULL_RECT)
				box.add_child(ph)
				var l2 := Ui.label("место: " + str(el.get("widget", el.get("id", ""))), 18)
				l2.set_anchors_preset(Control.PRESET_FULL_RECT)
				box.add_child(l2)
			var key := str(el.get("widget", el.get("id", "")))
			var widgets: Dictionary = ctx.get("edit_widgets", {}) if ctx.get("edit", false) else ctx.get("widgets", {})
			if widgets.has(key):
				var r := place(el, ctx.get("view", Vector2(W, H) if ctx.get("edit", false) else view_size()),
						ctx.get("insets", Vector2.ZERO if ctx.get("edit", false) else safe_insets(view_size())))
				box.size = r.size
				widgets[key].call(box, el)
			return box
	return null


static func _button_style(style: String) -> StyleBox:
	match style:
		"tile":
			var st := StyleBoxFlat.new()
			st.bg_color = Color(0.08, 0.06, 0.16, 0.85)
			st.border_color = Ui.colors["accent"].darkened(0.3)
			st.set_border_width_all(2)
			st.set_corner_radius_all(18)
			return st
		"nav_big":
			var st2 := StyleBoxFlat.new()
			st2.bg_color = Ui.colors["primary"]
			st2.border_color = Ui.colors["accent"]
			st2.set_border_width_all(4)
			st2.set_corner_radius_all(24)
			st2.shadow_color = Color(Ui.colors["accent"], 0.55)
			st2.shadow_size = 14
			return st2
		"nav", "icon":
			return StyleBoxEmpty.new()
	return null


static func _make_button(el: Dictionary, ctx: Dictionary) -> Control:
	var style := str(el.get("style", "default"))
	var b := Button.new()
	var w := float(el.get("w", 100))
	var h := float(el.get("h", 60))
	var text := text_of(el, ctx)
	var sb := _button_style(style)
	if sb != null:
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(state, sb)
	var icon_path := str(el.get("icon", ""))
	var font := int(el.get("size", 22 if style in ["nav", "nav_big"] else (16 if style == "tile" else 26)))
	if icon_path != "":
		var label_h := 0.0 if text == "" else font * 1.9
		var isz := minf(w * 0.86, h - label_h - 6) if text != "" else minf(w, h)
		var ic := TextureRect.new()
		ic.texture = Content.load_texture(icon_path)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size = Vector2(isz, isz)
		ic.position = Vector2((w - isz) / 2.0, 4 if text != "" else (h - isz) / 2.0)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(ic)
		if text != "":
			var l := Label.new()
			l.text = text
			l.add_theme_font_size_override("font_size", font)
			l.add_theme_color_override("font_color", Ui.colors["accent"] if style == "nav_big" else Ui.colors["text"])
			l.add_theme_color_override("font_outline_color", OUTLINE)
			l.add_theme_constant_override("outline_size", 5)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			l.position = Vector2(0, h - label_h - 2)
			l.size = Vector2(w, label_h)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(l)
	else:
		b.text = text
		b.add_theme_font_size_override("font_size", font)
		b.clip_text = true
	if el.has("action"):
		var action: Dictionary = el["action"]
		b.pressed.connect(func(): run_action(action, ctx))
	if el.has("badge") and ctx.has("badges"):
		ctx["badges"].call(str(el["badge"]), b, Vector2(w - 30, -4))
	return b


static func run_action(action: Dictionary, ctx: Dictionary) -> void:
	if ctx.has("on_action"):
		ctx["on_action"].call(action)
		return
	var actions: Dictionary = ctx.get("actions", {})
	if action.has("call"):
		var name := str(action["call"])
		if actions.has(name):
			actions[name].call()
	elif action.has("scene"):
		var key := str(action["scene"])
		if actions.has("scene:" + key):
			actions["scene:" + key].call()
		elif SCENES.has(key):
			Engine.get_main_loop().change_scene_to_file(SCENES[key])
	elif action.has("soon") and actions.has("soon"):
		actions["soon"].call(str(action["soon"]))
