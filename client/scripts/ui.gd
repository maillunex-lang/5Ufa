class_name Ui
extends RefCounted
## Простые элементы интерфейса загрузчика в едином стиле (до скачивания контента).
## После загрузки цвета берутся из config/game_settings.json (theme).

static var colors := {
	"primary": Color("#3B1F5C"),
	"accent": Color("#F2B544"),
	"background": Color("#160E24"),
	"text": Color("#F4ECDD"),
}


static func apply_settings(settings: Variant) -> void:
	if settings is Dictionary and settings.get("theme") is Dictionary:
		for k in settings["theme"].keys():
			if colors.has(k):
				colors[k] = Color(str(settings["theme"][k]))


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 30
	var btn := StyleBoxFlat.new()
	btn.bg_color = colors["primary"]
	btn.border_color = colors["accent"]
	btn.set_border_width_all(3)
	btn.set_corner_radius_all(16)
	btn.content_margin_left = 24
	btn.content_margin_right = 24
	btn.content_margin_top = 18
	btn.content_margin_bottom = 18
	var btn_hover := btn.duplicate()
	btn_hover.bg_color = colors["primary"].lightened(0.15)
	var btn_pressed := btn.duplicate()
	btn_pressed.bg_color = colors["primary"].darkened(0.2)
	var btn_disabled := btn.duplicate()
	btn_disabled.bg_color = colors["primary"].darkened(0.4)
	btn_disabled.border_color = colors["accent"].darkened(0.5)
	th.set_stylebox("normal", "Button", btn)
	th.set_stylebox("hover", "Button", btn_hover)
	th.set_stylebox("pressed", "Button", btn_pressed)
	th.set_stylebox("disabled", "Button", btn_disabled)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", colors["text"])
	th.set_color("font_color", "Label", colors["text"])

	var edit := StyleBoxFlat.new()
	edit.bg_color = colors["background"].lightened(0.08)
	edit.border_color = colors["accent"].darkened(0.3)
	edit.set_border_width_all(2)
	edit.set_corner_radius_all(10)
	edit.content_margin_left = 16
	edit.content_margin_right = 16
	edit.content_margin_top = 14
	edit.content_margin_bottom = 14
	th.set_stylebox("normal", "LineEdit", edit)
	var edit_focus := edit.duplicate()
	edit_focus.border_color = colors["accent"]
	th.set_stylebox("focus", "LineEdit", edit_focus)
	th.set_color("font_color", "LineEdit", colors["text"])

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = colors["primary"].darkened(0.3)
	bar_bg.set_corner_radius_all(14)
	bar_bg.border_color = colors["accent"].darkened(0.4)
	bar_bg.set_border_width_all(2)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = colors["accent"]
	bar_fill.set_corner_radius_all(14)
	th.set_stylebox("background", "ProgressBar", bar_bg)
	th.set_stylebox("fill", "ProgressBar", bar_fill)
	th.set_color("font_color", "ProgressBar", colors["background"])

	var panel := StyleBoxFlat.new()
	panel.bg_color = colors["background"].lightened(0.04)
	panel.border_color = colors["accent"]
	panel.set_border_width_all(3)
	panel.set_corner_radius_all(20)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 28
	panel.content_margin_bottom = 28
	th.set_stylebox("panel", "PanelContainer", panel)
	return th


## Корневой экран: фон + вертикальная колонка по центру с отступами
static func screen(root: Control) -> VBoxContainer:
	root.theme = make_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = colors["background"]
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	margin.add_theme_constant_override("margin_top", 96)
	margin.add_theme_constant_override("margin_bottom", 64)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 24)
	margin.add_child(col)
	return col


static func label(text: String, size := 30, color_key := "text") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colors[color_key])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 96)
	b.pressed.connect(on_press)
	return b


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func line_edit(placeholder: String, secret := false) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.custom_minimum_size = Vector2(0, 88)
	return e


const CURRENCY_LABELS := {"gold": "золото", "hero_xp": "опыт", "essence": "эссенция",
		"crystals": "кристаллы", "scrolls": "свитки"}


## Строка с балансом валют: «золото 1 200 · опыт 300 · …»
static func wallet_text(w: Dictionary) -> String:
	var parts: Array = []
	for code in ["gold", "hero_xp", "essence", "crystals", "scrolls"]:
		parts.append("%s: %d" % [CURRENCY_LABELS[code], int(w.get(code, 0))])
	var faction_scrolls := 0
	for code in w.keys():
		if str(code).begins_with("faction_scroll_"):
			faction_scrolls += int(w[code])
	if faction_scrolls > 0:
		parts.append("свитки фракций: %d" % faction_scrolls)
	return " · ".join(parts)


## Стоимость: {"gold": 30, "hero_xp": 20} -> «30 золото, 20 опыт»
static func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for code in cost.keys():
		if int(cost[code]) == 0:
			continue
		var name: String = "свитки фракции" if str(code).begins_with("faction_scroll_") else CURRENCY_LABELS.get(code, code)
		parts.append("%s: %d" % [name, int(cost[code])])
	return ", ".join(parts) if not parts.is_empty() else "ничего"
