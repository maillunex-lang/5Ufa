extends Node
## Посох крепится к правой кисти. Маленький тестовый GLB открывается как боец.
## Это не модель Meshy и не проверка на телефоне.

func _ready() -> void:
	call_deferred("_test")


func _test() -> void:
	var skeleton := Skeleton3D.new()
	add_child(skeleton)
	skeleton.add_bone("Hips")
	skeleton.add_bone("LeftHand")
	skeleton.add_bone("RightHand")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 0)
	var staff := UnitModel3D.new()
	add_child(staff)
	var bone := staff.attach_staff(skeleton, 1.7)
	if bone != "RightHand" or skeleton.find_child("TemporaryStaff", true, false) == null:
		printerr("BATTLE3D FAIL: посох не на правой кисти (%s)" % bone)
		get_tree().quit(1)
		return
	var bytes := FileAccess.get_file_as_bytes("res://tests/fixtures/model3d.glb")
	var view := UnitModel3D.new()
	add_child(view)
	var model := {"file": "heroes/hyuhylu/models3d/test.glb", "scale": 1.0,
			"animations": {"idle": {"file": "heroes/hyuhylu/models3d/test.glb", "clip": "idle"}}}
	if not view.load_bytes(bytes, model, "hyuhylu") or view.current != "idle":
		printerr("BATTLE3D FAIL: тестовый GLB не открылся")
		get_tree().quit(1)
		return
	if view.load_bytes(PackedByteArray([1, 2, 3]), model, "hyuhylu"):
		printerr("BATTLE3D FAIL: битый GLB принят")
		get_tree().quit(1)
		return
	print('AUTOTEST BATTLE3D: {"ok":true}')
	get_tree().quit(0)
