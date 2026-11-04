class_name SchemaForm
extends VBoxContainer
## Форма редактирования по JSON Schema: строки, числа, флажки, списки выбора, вложенные объекты и массивы.
## Что форма не умеет показать полями (oneOf, словари и т. п.) — редактируется как JSON-текст.
## Проверку по схеме всё равно делает сервер; ошибки показываются списком.

var schemas: Dictionary = {}     # имя файла схемы -> схема
var _root_name := ""
var _getter: Callable


## schemas_by_name должен содержать root_name и всё, на что он ссылается ($ref)
func build(value: Variant, root_name: String, schemas_by_name: Dictionary) -> void:
	schemas = schemas_by_name
	_root_name = root_name
	for c in get_children():
		c.queue_free()
	var node := _make(value, schemas.get(root_name, {}), root_name, "", true)
	add_child(node["control"])
	_getter = node["get"]


func get_value() -> Variant:
	return _getter.call()


static func refs_of(schema: Variant, out: Dictionary) -> void:
	## Собрать имена файлов схем, на которые есть ссылки
	if schema is Dictionary:
		if schema.has("$ref"):
			var file := str(schema["$ref"]).get_slice("#", 0)
			if file != "":
				out[file] = true
		for v in schema.values():
			refs_of(v, out)
	elif schema is Array:
		for v in schema:
			refs_of(v, out)


# --- Разбор схемы -------------------------------------------------------------

func _resolve(schema: Dictionary, base: String) -> Array:
	## -> [схема, имя файла]
	var guard := 0
	while schema.has("$ref") and guard < 10:
		guard += 1
		var ref := str(schema["$ref"])
		var file := ref.get_slice("#", 0)
		var pointer := ref.get_slice("#", 1) if ref.contains("#") else ""
		if file != "":
			base = file
		var target: Variant = schemas.get(base, {})
		for part in pointer.split("/", false):
			if target is Dictionary:
				target = target.get(part, {})
		var merged: Dictionary = (target as Dictionary).duplicate() if target is Dictionary else {}
		for k in schema.keys():
			if k != "$ref":
				merged[k] = schema[k]
		schema = merged
	return [schema, base]


func _type_of(schema: Dictionary) -> String:
	if schema.has("enum"):
		return "enum"
	if schema.has("const"):
		return "const"
	var t: Variant = schema.get("type", "")
	if t is Array:
		return "json"
	if t == "" and schema.has("properties"):
		return "object"
	if schema.has("oneOf") or schema.has("anyOf"):
		return "json"
	if t == "object" and not schema.has("properties"):
		return "json"
	return str(t) if t != "" else "json"


func default_for(schema: Dictionary, base: String) -> Variant:
	var r := _resolve(schema, base)
	var s: Dictionary = r[0]
	if s.has("default"):
		return s["default"]
	match _type_of(s):
		"enum": return s["enum"][0]
		"const": return s["const"]
		"boolean": return false
		"integer": return int(s.get("minimum", 0))
		"number": return float(s.get("minimum", 0))
		"string": return ""
		"array": return []
		"object":
			var out := {}
			for k in s.get("required", []):
				if s.get("properties", {}).has(k):
					out[k] = default_for(s["properties"][k], r[1])
			return out
	return {}


# --- Построение полей ------------------------------------------------------------

func _label(key: String, schema: Dictionary, required: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var l := Ui.label(key + (" *" if required else ""), 19, "accent")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(l)
	var desc := str(schema.get("description", schema.get("title", "")))
	if desc != "":
		var d := Ui.label(desc, 15)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		d.modulate = Color(1, 1, 1, 0.65)
		box.add_child(d)
	return box


func _make(value: Variant, schema: Dictionary, base: String, key: String, required: bool) -> Dictionary:
	var r := _resolve(schema, base)
	var s: Dictionary = r[0]
	base = r[1]
	var t := _type_of(s)
	match t:
		"object":
			return _make_object(value if value is Dictionary else {}, s, base, key)
		"array":
			return _make_array(value if value is Array else [], s, base, key)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	if key != "":
		row.add_child(_label(key, s, required))
	var getter: Callable
	match t:
		"enum":
			var pick := OptionButton.new()
			pick.custom_minimum_size = Vector2(0, 56)
			var opts: Array = s["enum"]
			for o in opts:
				pick.add_item(str(o))
			pick.selected = max(0, opts.find(value))
			row.add_child(pick)
			getter = func(): return opts[pick.selected]
		"const":
			row.add_child(Ui.label(str(s["const"]), 18))
			getter = func(): return s["const"]
		"boolean":
			var cb := CheckBox.new()
			cb.text = "да"
			cb.button_pressed = bool(value) if value != null else false
			row.add_child(cb)
			getter = func(): return cb.button_pressed
		"integer", "number":
			var e := LineEdit.new()
			e.custom_minimum_size = Vector2(0, 56)
			e.text = "" if value == null else (str(int(value)) if t == "integer" else str(value))
			e.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
			var hint := []
			if s.has("minimum"):
				hint.append("от %s" % str(s["minimum"]))
			if s.has("maximum"):
				hint.append("до %s" % str(s["maximum"]))
			e.placeholder_text = " ".join(hint)
			row.add_child(e)
			getter = func():
				var txt := e.text.strip_edges().replace(",", ".")
				if txt == "":
					return null
				if t == "integer" and txt.is_valid_int():
					return int(txt)
				if txt.is_valid_float():
					return float(txt) if t == "number" else txt
				return txt  # пусть сервер покажет понятную ошибку
		"string":
			var long := key in ["description", "lore", "text", "dialogue_start", "dialogue_end", "notes"] \
					or (value is String and (value as String).length() > 60)
			if long:
				var te := TextEdit.new()
				te.custom_minimum_size = Vector2(0, 140)
				te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
				te.text = "" if value == null else str(value)
				row.add_child(te)
				getter = func(): return te.text
			else:
				var le := LineEdit.new()
				le.custom_minimum_size = Vector2(0, 56)
				le.text = "" if value == null else str(value)
				row.add_child(le)
				if str(s.get("pattern", "")).contains("[0-9a-fA-F]{6}"):
					var sw := ColorRect.new()  # образец цвета
					sw.custom_minimum_size = Vector2(0, 14)
					sw.color = Color.from_string(le.text, Color.TRANSPARENT)
					le.text_changed.connect(func(tx): sw.color = Color.from_string(tx, Color.TRANSPARENT))
					row.add_child(sw)
				getter = func(): return le.text
		_:
			return _make_json(value, s, key, required)
	return {"control": row, "get": getter}


func _make_json(value: Variant, s: Dictionary, key: String, required: bool) -> Dictionary:
	var row := VBoxContainer.new()
	if key != "":
		row.add_child(_label(key + " (JSON)", s, required))
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(0, 160)
	te.text = JSON.stringify(value, "  ") if value != null else ""
	row.add_child(te)
	var getter := func():
		var txt := te.text.strip_edges()
		if txt == "":
			return null
		var parsed: Variant = JSON.parse_string(txt)
		return parsed if parsed != null else txt
	return {"control": row, "get": getter}


func _section(title: String, s: Dictionary) -> Array:
	## Сворачиваемый блок: [корень, содержимое]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := Button.new()
	head.text = "[-] " + title
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.custom_minimum_size = Vector2(0, 56)
	head.add_theme_font_size_override("font_size", 21)
	box.add_child(head)
	var desc := str(s.get("description", ""))
	if desc != "":
		var d := Ui.label(desc, 15)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		d.modulate = Color(1, 1, 1, 0.65)
		box.add_child(d)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	margin.add_child(inner)
	box.add_child(margin)
	head.pressed.connect(func():
		margin.visible = not margin.visible
		head.text = ("[-] " if margin.visible else "[+] ") + title)
	return [box, inner]


func _make_object(value: Dictionary, s: Dictionary, base: String, key: String) -> Dictionary:
	var props: Dictionary = s.get("properties", {})
	var required: Array = s.get("required", [])
	var parts := _section(key, s) if key != "" else [VBoxContainer.new(), null]
	var root: Control = parts[0]
	var inner: VBoxContainer = parts[1] if parts[1] != null else root
	inner.add_theme_constant_override("separation", 10)
	var getters := {}
	var present := {}
	for k in props.keys():
		if k == "$schema":
			continue
		var holder := VBoxContainer.new()
		inner.add_child(holder)
		var req: bool = required.has(k)
		if value.has(k) or req:
			var n := _make(value.get(k), props[k], base, k, req)
			holder.add_child(n["control"])
			getters[k] = n["get"]
			present[k] = true
		else:
			_add_optional_button(holder, k, props[k], base, getters, present)
	# Поля, которых нет в схеме (если схема их разрешает) — как есть
	for k in value.keys():
		if not props.has(k) and k != "$schema":
			var n := _make_json(value[k], {}, k, false)
			inner.add_child(n["control"])
			getters[k] = n["get"]
			present[k] = true
	var keep_schema: Variant = value.get("$schema")
	var getter := func():
		var out := {}
		if keep_schema != null:
			out["$schema"] = keep_schema
		for k in getters.keys():
			if not present.get(k, false):
				continue
			var v: Variant = getters[k].call()
			if v == null and not required.has(k):
				continue
			if v is String and v == "" and not required.has(k):
				continue
			out[k] = v
		return out
	return {"control": root, "get": getter}


func _add_optional_button(holder: VBoxContainer, k: String, schema: Dictionary, base: String,
		getters: Dictionary, present: Dictionary) -> void:
	var b := Button.new()
	b.text = "+ " + k
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.modulate = Color(1, 1, 1, 0.7)
	holder.add_child(b)
	b.pressed.connect(func():
		b.queue_free()
		var n := _make(default_for(schema, base), schema, base, k, false)
		holder.add_child(n["control"])
		getters[k] = n["get"]
		present[k] = true)


func _make_array(value: Array, s: Dictionary, base: String, key: String) -> Dictionary:
	var item_schema: Dictionary = s.get("items", {})
	var parts := _section("%s (%d)" % [key, value.size()], s)
	var inner: VBoxContainer = parts[1]
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	inner.add_child(list)
	var getters: Array = []
	var add_item := func(v: Variant):
		var line := HBoxContainer.new()
		var n := _make(v, item_schema, base, "", true)
		n["control"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(n["control"])
		var del := Button.new()
		del.text = "X"
		del.custom_minimum_size = Vector2(56, 56)
		line.add_child(del)
		list.add_child(line)
		var entry := {"get": n["get"], "alive": true}
		getters.append(entry)
		del.pressed.connect(func():
			entry["alive"] = false
			line.queue_free())
	for v in value:
		add_item.call(v)
	var add := Button.new()
	add.text = "+ Добавить элемент"
	add.custom_minimum_size = Vector2(0, 52)
	add.pressed.connect(func(): add_item.call(default_for(item_schema, base)))
	inner.add_child(add)
	var getter := func():
		var out := []
		for e in getters:
			if e["alive"]:
				out.append(e["get"].call())
		return out
	return {"control": parts[0], "get": getter}
