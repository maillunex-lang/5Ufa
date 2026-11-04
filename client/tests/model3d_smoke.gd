extends Node
## Настоящий GLB импортируется Godot; редактор создаёт соответствия и сохраняет модель.

class FakeApi extends Node:
	var bytes: PackedByteArray
	var animation_bytes: PackedByteArray
	var clip_name := "idle"
	var saved: Dictionary = {}
	var library: Dictionary = {}
	func call_api(_method: int, path: String, body: Variant = null, _raw := false) -> Dictionary:
		if path.contains("/upload"):
			return {"ok": true, "data": {"files": [{"path": "heroes/ural_batyr/models3d/test.glb", "name": "test.glb", "meshes": 1, "mesh_instances": 1, "triangles": 1, "textures": [], "bones": [], "animations": [clip_name], "warnings": []}]}}
		if path.contains("/config"):
			saved = body["model"]
			return {"ok": true, "data": {}}
		var query := path.get_slice("path=", 1).uri_decode()
		var keys: Array = library.keys()
		keys.sort_custom(func(a, b): return str(a).length() > str(b).length())
		for key in keys:
			if query.ends_with(str(key)):
				return {"ok": true, "bytes": library[key], "data": {}}
		return {"ok": true, "bytes": animation_bytes if path.contains("animation.glb") else bytes, "data": {}}

class FakeHost extends Control:
	var api: Node
	var message := ""
	func _say(value: String) -> void:
		message = value
	func _fail(value: Dictionary) -> void:
		message = str(value)

func _ready() -> void:
	call_deferred("_test")

func _test() -> void:
	var fixture := "res://tests/fixtures/model3d.glb"
	var clip_name := "idle"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--3d-fixture="):
			fixture = arg.trim_prefix("--3d-fixture=")
			clip_name = "animation_0"
	var data := FileAccess.get_file_as_bytes(fixture)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(data, "", state) != OK:
		printerr("MODEL3D FAIL: GLB не импортирован")
		get_tree().quit(1)
		return
	var host := FakeHost.new()
	get_tree().root.add_child(host)
	host.size = Vector2(720, 1280)
	var api := FakeApi.new()
	host.add_child(api)
	host.api = api
	api.bytes = data
	api.clip_name = clip_name
	api.animation_bytes = data.duplicate()
	var needle := '"idle"'.to_utf8_buffer()
	for index in range(data.size() - needle.size()):
		if data.slice(index, index + needle.size()) == needle:
			api.animation_bytes[index + 2] = 47 # имя i/le требует нормализации в Godot
			break
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	host.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var editor := Model3DEditor.new()
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(editor)
	editor.setup(host, "ural_batyr", "default", {})
	await get_tree().process_frame
	await editor._upload(data)
	await get_tree().process_frame
	await get_tree().process_frame
	var valid: bool = is_instance_valid(editor.model_root) and editor.base_pick.item_count == 1
	if valid:
		editor.anim_picks["idle"].select(1)
		await editor._play("idle")
		valid = is_instance_valid(editor.player) and editor.player.is_playing()
	if valid:
		var external_name := "animation_0" if clip_name == "animation_0" else "i/le"
		editor._add_report({"path": "heroes/ural_batyr/models3d/animation.glb", "name": "animation.glb", "meshes": 1,
				"triangles": 1, "textures": [], "bones": [], "animations": [external_name], "warnings": []})
		editor._refresh_animations(false)
		var pick: OptionButton = editor.anim_picks["walk"]
		pick.select(2)
		await editor._play("walk")
		valid = editor.player.current_animation == "ufa_preview/preview" and editor.player.is_playing()
		editor.anim_picks["idle"].select(1)
	await editor._save()
	valid = valid and api.saved.get("file", "") == "heroes/ural_batyr/models3d/test.glb"
	valid = valid and api.saved.get("animations", {}).get("idle", {}).get("clip", "") == clip_name
	if valid:
		valid = await _skinned(editor, api, host)
	print("AUTOTEST MODEL3D: ", JSON.stringify({"ok": valid, "message": host.message}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--3d-shot="):
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			host.get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--3d-shot="))
	get_tree().quit(0 if valid else 1)


func _select_base(editor: Model3DEditor, suffix: String) -> void:
	for i in editor.base_pick.item_count:
		if str(editor.base_pick.get_item_metadata(i)).ends_with(suffix):
			editor.base_pick.select(i)
			return


func _select_clip(editor: Model3DEditor, event: String, suffix: String, clip: String) -> bool:
	var pick: OptionButton = editor.anim_picks[event]
	for i in pick.item_count:
		var meta: Variant = pick.get_item_metadata(i)
		if meta is Dictionary and str(meta.get("file", "")).ends_with(suffix) and str(meta.get("clip", "")) == clip:
			pick.select(i)
			return true
	return false


func _report(path: String, bone: String, clip: String) -> Dictionary:
	return {"path": path, "name": path.get_file(), "meshes": 1, "mesh_instances": 1, "triangles": 1,
			"textures": [], "bones": [bone], "animations": [clip], "warnings": []}


func _skinned(editor: Model3DEditor, api: FakeApi, host: FakeHost) -> bool:
	## Синтетический скелет, не файл Meshy: тот же путь, другой путь, чужая кость, имя со слэшем и @root.
	# Синтетические GLB, не экспорт Meshy. Лежат в тексте, чтобы не тащить бинарник в APK и в репозиторий отдельно.
	var skinned := Marshalls.base64_to_raw("Z2xURgIAAABMBgAAYAUAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibm9kZXMiOlswXX1dLCJub2RlcyI6W3sibmFtZSI6IkFybWF0dXJlIiwiY2hpbGRyZW4iOlsxLDJdfSx7Im5hbWUiOiJIaXBzIn0seyJuYW1lIjoiTWVzaCIsIm1lc2giOjAsInNraW4iOjB9XSwibWVzaGVzIjpbeyJuYW1lIjoiQm9keSIsInByaW1pdGl2ZXMiOlt7ImF0dHJpYnV0ZXMiOnsiUE9TSVRJT04iOjAsIkpPSU5UU18wIjoyLCJXRUlHSFRTXzAiOjN9LCJpbmRpY2VzIjoxfV19XSwic2tpbnMiOlt7Im5hbWUiOiJBcm1hdHVyZSIsInNrZWxldG9uIjowLCJqb2ludHMiOlsxXSwiaW52ZXJzZUJpbmRNYXRyaWNlcyI6Nn1dLCJhbmltYXRpb25zIjpbeyJuYW1lIjoiV2FsayIsInNhbXBsZXJzIjpbeyJpbnB1dCI6NCwib3V0cHV0Ijo1LCJpbnRlcnBvbGF0aW9uIjoiTElORUFSIn1dLCJjaGFubmVscyI6W3sic2FtcGxlciI6MCwidGFyZ2V0Ijp7Im5vZGUiOjEsInBhdGgiOiJyb3RhdGlvbiJ9fV19XSwiYnVmZmVycyI6W3siYnl0ZUxlbmd0aCI6MjA4fV0sImJ1ZmZlclZpZXdzIjpbeyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjAsImJ5dGVMZW5ndGgiOjM2fSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MzYsImJ5dGVMZW5ndGgiOjZ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0Ijo0NCwiYnl0ZUxlbmd0aCI6MTJ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0Ijo1NiwiYnl0ZUxlbmd0aCI6NDh9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxMDQsImJ5dGVMZW5ndGgiOjh9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxMTIsImJ5dGVMZW5ndGgiOjMyfSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MTQ0LCJieXRlTGVuZ3RoIjo2NH1dLCJhY2Nlc3NvcnMiOlt7ImJ1ZmZlclZpZXciOjAsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjozLCJ0eXBlIjoiVkVDMyIsIm1pbiI6Wy0wLjUsMCwwXSwibWF4IjpbMC41LDEsMF19LHsiYnVmZmVyVmlldyI6MSwiY29tcG9uZW50VHlwZSI6NTEyMywiY291bnQiOjMsInR5cGUiOiJTQ0FMQVIifSx7ImJ1ZmZlclZpZXciOjIsImNvbXBvbmVudFR5cGUiOjUxMjEsImNvdW50IjozLCJ0eXBlIjoiVkVDNCJ9LHsiYnVmZmVyVmlldyI6MywiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjMsInR5cGUiOiJWRUM0In0seyJidWZmZXJWaWV3Ijo0LCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MiwidHlwZSI6IlNDQUxBUiIsIm1pbiI6WzBdLCJtYXgiOlsxXX0seyJidWZmZXJWaWV3Ijo1LCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MiwidHlwZSI6IlZFQzQifSx7ImJ1ZmZlclZpZXciOjYsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjoxLCJ0eXBlIjoiTUFUNCJ9XX0gINAAAABCSU4AAAAAvwAAAAAAAAAAAAAAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAABAAIAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA8wQ1PwAAAADzBDU/AACAPwAAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPw==")
	var repath := Marshalls.base64_to_raw("Z2xURgIAAABsBgAAgAUAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibm9kZXMiOlswXX1dLCJub2RlcyI6W3sibmFtZSI6IkV4dHJhIiwiY2hpbGRyZW4iOlsxXX0seyJuYW1lIjoiQXJtYXR1cmUiLCJjaGlsZHJlbiI6WzIsM119LHsibmFtZSI6IkhpcHMifSx7Im5hbWUiOiJNZXNoIiwibWVzaCI6MCwic2tpbiI6MH1dLCJtZXNoZXMiOlt7Im5hbWUiOiJCb2R5IiwicHJpbWl0aXZlcyI6W3siYXR0cmlidXRlcyI6eyJQT1NJVElPTiI6MCwiSk9JTlRTXzAiOjIsIldFSUdIVFNfMCI6M30sImluZGljZXMiOjF9XX1dLCJza2lucyI6W3sibmFtZSI6IkFybWF0dXJlIiwic2tlbGV0b24iOjEsImpvaW50cyI6WzJdLCJpbnZlcnNlQmluZE1hdHJpY2VzIjo2fV0sImFuaW1hdGlvbnMiOlt7Im5hbWUiOiJXYWxrIiwic2FtcGxlcnMiOlt7ImlucHV0Ijo0LCJvdXRwdXQiOjUsImludGVycG9sYXRpb24iOiJMSU5FQVIifV0sImNoYW5uZWxzIjpbeyJzYW1wbGVyIjowLCJ0YXJnZXQiOnsibm9kZSI6MiwicGF0aCI6InJvdGF0aW9uIn19XX1dLCJidWZmZXJzIjpbeyJieXRlTGVuZ3RoIjoyMDh9XSwiYnVmZmVyVmlld3MiOlt7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MCwiYnl0ZUxlbmd0aCI6MzZ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjozNiwiYnl0ZUxlbmd0aCI6Nn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjQ0LCJieXRlTGVuZ3RoIjoxMn0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjU2LCJieXRlTGVuZ3RoIjo0OH0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjEwNCwiYnl0ZUxlbmd0aCI6OH0seyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjExMiwiYnl0ZUxlbmd0aCI6MzJ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxNDQsImJ5dGVMZW5ndGgiOjY0fV0sImFjY2Vzc29ycyI6W3siYnVmZmVyVmlldyI6MCwiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjMsInR5cGUiOiJWRUMzIiwibWluIjpbLTAuNSwwLDBdLCJtYXgiOlswLjUsMSwwXX0seyJidWZmZXJWaWV3IjoxLCJjb21wb25lbnRUeXBlIjo1MTIzLCJjb3VudCI6MywidHlwZSI6IlNDQUxBUiJ9LHsiYnVmZmVyVmlldyI6MiwiY29tcG9uZW50VHlwZSI6NTEyMSwiY291bnQiOjMsInR5cGUiOiJWRUM0In0seyJidWZmZXJWaWV3IjozLCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MywidHlwZSI6IlZFQzQifSx7ImJ1ZmZlclZpZXciOjQsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjoyLCJ0eXBlIjoiU0NBTEFSIiwibWluIjpbMF0sIm1heCI6WzFdfSx7ImJ1ZmZlclZpZXciOjUsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjoyLCJ0eXBlIjoiVkVDNCJ9LHsiYnVmZmVyVmlldyI6NiwiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjEsInR5cGUiOiJNQVQ0In1dfSAg0AAAAEJJTgAAAAC/AAAAAAAAAAAAAAA/AAAAAAAAAAAAAAAAAACAPwAAAAAAAAEAAgAAAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAAADzBDU/AAAAAPMENT8AAIA/AAAAAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAAAAAAIA/")
	var mismatch := Marshalls.base64_to_raw("Z2xURgIAAABMBgAAYAUAAEpTT057ImFzc2V0Ijp7InZlcnNpb24iOiIyLjAifSwic2NlbmUiOjAsInNjZW5lcyI6W3sibm9kZXMiOlswXX1dLCJub2RlcyI6W3sibmFtZSI6IkFybWF0dXJlIiwiY2hpbGRyZW4iOlsxLDJdfSx7Im5hbWUiOiJTcGluIn0seyJuYW1lIjoiTWVzaCIsIm1lc2giOjAsInNraW4iOjB9XSwibWVzaGVzIjpbeyJuYW1lIjoiQm9keSIsInByaW1pdGl2ZXMiOlt7ImF0dHJpYnV0ZXMiOnsiUE9TSVRJT04iOjAsIkpPSU5UU18wIjoyLCJXRUlHSFRTXzAiOjN9LCJpbmRpY2VzIjoxfV19XSwic2tpbnMiOlt7Im5hbWUiOiJBcm1hdHVyZSIsInNrZWxldG9uIjowLCJqb2ludHMiOlsxXSwiaW52ZXJzZUJpbmRNYXRyaWNlcyI6Nn1dLCJhbmltYXRpb25zIjpbeyJuYW1lIjoiV2FsayIsInNhbXBsZXJzIjpbeyJpbnB1dCI6NCwib3V0cHV0Ijo1LCJpbnRlcnBvbGF0aW9uIjoiTElORUFSIn1dLCJjaGFubmVscyI6W3sic2FtcGxlciI6MCwidGFyZ2V0Ijp7Im5vZGUiOjEsInBhdGgiOiJyb3RhdGlvbiJ9fV19XSwiYnVmZmVycyI6W3siYnl0ZUxlbmd0aCI6MjA4fV0sImJ1ZmZlclZpZXdzIjpbeyJidWZmZXIiOjAsImJ5dGVPZmZzZXQiOjAsImJ5dGVMZW5ndGgiOjM2fSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MzYsImJ5dGVMZW5ndGgiOjZ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0Ijo0NCwiYnl0ZUxlbmd0aCI6MTJ9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0Ijo1NiwiYnl0ZUxlbmd0aCI6NDh9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxMDQsImJ5dGVMZW5ndGgiOjh9LHsiYnVmZmVyIjowLCJieXRlT2Zmc2V0IjoxMTIsImJ5dGVMZW5ndGgiOjMyfSx7ImJ1ZmZlciI6MCwiYnl0ZU9mZnNldCI6MTQ0LCJieXRlTGVuZ3RoIjo2NH1dLCJhY2Nlc3NvcnMiOlt7ImJ1ZmZlclZpZXciOjAsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjozLCJ0eXBlIjoiVkVDMyIsIm1pbiI6Wy0wLjUsMCwwXSwibWF4IjpbMC41LDEsMF19LHsiYnVmZmVyVmlldyI6MSwiY29tcG9uZW50VHlwZSI6NTEyMywiY291bnQiOjMsInR5cGUiOiJTQ0FMQVIifSx7ImJ1ZmZlclZpZXciOjIsImNvbXBvbmVudFR5cGUiOjUxMjEsImNvdW50IjozLCJ0eXBlIjoiVkVDNCJ9LHsiYnVmZmVyVmlldyI6MywiY29tcG9uZW50VHlwZSI6NTEyNiwiY291bnQiOjMsInR5cGUiOiJWRUM0In0seyJidWZmZXJWaWV3Ijo0LCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MiwidHlwZSI6IlNDQUxBUiIsIm1pbiI6WzBdLCJtYXgiOlsxXX0seyJidWZmZXJWaWV3Ijo1LCJjb21wb25lbnRUeXBlIjo1MTI2LCJjb3VudCI6MiwidHlwZSI6IlZFQzQifSx7ImJ1ZmZlclZpZXciOjYsImNvbXBvbmVudFR5cGUiOjUxMjYsImNvdW50IjoxLCJ0eXBlIjoiTUFUNCJ9XX0gINAAAABCSU4AAAAAvwAAAAAAAAAAAAAAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAABAAIAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA8wQ1PwAAAADzBDU/AACAPwAAAAAAAAAAAAAAAAAAAAAAAIA/AAAAAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAACAPw==")
	if skinned.is_empty() or repath.is_empty() or mismatch.is_empty():
		host.message = "нет тестового скелета"
		return false
	var normalized := skinned.duplicate()
	var needle := '"Walk"'.to_utf8_buffer()
	var renamed := false
	for index in range(normalized.size() - needle.size()):
		if normalized.slice(index, index + needle.size()) == needle:
			normalized[index + 2] = 47
			renamed = true
			break
	if not renamed:
		host.message = "в тестовом GLB нет клипа Walk"
		return false
	api.library["skinned_repath.glb"] = repath
	api.library["skinned_mismatch.glb"] = mismatch
	api.library["skinned_norm.glb"] = normalized
	api.library["skinned.glb"] = skinned
	var base := "heroes/ural_batyr/models3d/skinned.glb"
	editor._add_report(_report(base, "Hips", "Walk"))
	editor._add_report(_report("heroes/ural_batyr/models3d/skinned_repath.glb", "Hips", "Walk"))
	editor._add_report(_report("heroes/ural_batyr/models3d/skinned_mismatch.glb", "Spin", "Walk"))
	editor._add_report(_report("heroes/ural_batyr/models3d/skinned_norm.glb", "Hips", "W/lk"))
	editor._refresh_options(false)
	_select_base(editor, "skinned.glb")
	await editor._load_selected()
	if not is_instance_valid(editor.model_root) or not _select_clip(editor, "walk", "skinned.glb", "Walk"):
		host.message = "скелетная модель не открылась"
		return false
	await editor._play("walk")
	if not is_instance_valid(editor.player) or not editor.player.is_playing():
		host.message = "встроенная костная анимация не играется"
		return false
	if not _select_clip(editor, "attack", "skinned_repath.glb", "Walk"):
		return false
	host.message = ""
	await editor._play("attack")
	if editor.player.current_animation != "ufa_preview/preview" or not editor.player.is_playing():
		host.message = "совместимый скелет с другим путём не перенёсся: " + host.message
		return false
	if not _select_clip(editor, "skill", "skinned_mismatch.glb", "Walk"):
		return false
	host.message = ""
	await editor._play("skill")
	if not str(host.message).contains("не совпадают"):
		host.message = "чужой скелет ошибочно принят: " + host.message
		return false
	if not _select_clip(editor, "hit", "skinned_norm.glb", "W/lk"):
		return false
	await editor._play("hit")
	if editor.player.current_animation != "ufa_preview/preview" or not editor.player.is_playing():
		host.message = "нормализованное имя анимации не сопоставилось"
		return false
	editor._refresh_bones([])
	editor.anchors["hit"]["bones"].select(1)
	await editor._save()
	return str(api.saved.get("anchors", {}).get("hit", {}).get("bone", "")) == "@root"
