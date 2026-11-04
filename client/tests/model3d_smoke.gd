extends Node
## Настоящий GLB импортируется Godot; редактор создаёт соответствия и сохраняет модель.

class FakeApi extends Node:
	var bytes: PackedByteArray
	var animation_bytes: PackedByteArray
	var clip_name := "idle"
	var saved: Dictionary = {}
	func call_api(_method: int, path: String, body: Variant = null, _raw := false) -> Dictionary:
		if path.contains("/upload"):
			return {"ok": true, "data": {"files": [{"path": "heroes/ural_batyr/models3d/test.glb", "name": "test.glb", "meshes": 1, "triangles": 1, "textures": [], "bones": [], "animations": [clip_name], "warnings": []}]}}
		if path.contains("/config"):
			saved = body["model"]
			return {"ok": true, "data": {}}
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
	print("AUTOTEST MODEL3D: ", JSON.stringify({"ok": valid, "message": host.message}))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--3d-shot="):
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			host.get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--3d-shot="))
	get_tree().quit(0 if valid else 1)
