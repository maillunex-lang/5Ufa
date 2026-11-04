class_name Props
extends RefCounted
## Простые предметы, нарисованные кодом (тестовые). Меч: рукоять вдоль оси Y с центром в начале координат,
## гарда и клинок вверх по +Y. Длина около 1,3 условных метра. Размер/положение в руке задаёт visual.attachments героя.

static func make(kind: String) -> Node3D:
	match kind:
		"sword":
			return _sword()
	return Node3D.new()


static func _mat(color: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metal
	m.roughness = rough
	return m


static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	root.add_child(mi)
	return mi


static func _sword() -> Node3D:
	var root := Node3D.new()
	root.name = "ProcSword"
	var steel := _mat(Color(0.82, 0.85, 0.9), 0.9, 0.25)
	var gold := _mat(Color(0.9, 0.7, 0.25), 0.9, 0.35)
	var leather := _mat(Color(0.35, 0.2, 0.12), 0.0, 0.8)
	var grip := CylinderMesh.new()
	grip.top_radius = 0.032
	grip.bottom_radius = 0.032
	grip.height = 0.24
	_part(root, grip, leather, Vector3.ZERO)
	var pommel := SphereMesh.new()
	pommel.radius = 0.05
	pommel.height = 0.1
	_part(root, pommel, gold, Vector3(0, -0.145, 0))
	var guard := BoxMesh.new()
	guard.size = Vector3(0.34, 0.05, 0.07)
	_part(root, guard, gold, Vector3(0, 0.145, 0))
	var blade := BoxMesh.new()
	blade.size = Vector3(0.1, 0.78, 0.022)
	_part(root, blade, steel, Vector3(0, 0.56, 0))
	var tip := PrismMesh.new()
	tip.size = Vector3(0.1, 0.2, 0.022)
	_part(root, tip, steel, Vector3(0, 1.05, 0))
	var fuller := BoxMesh.new()
	fuller.size = Vector3(0.022, 0.7, 0.026)
	_part(root, fuller, _mat(Color(0.5, 0.53, 0.58), 0.9, 0.4), Vector3(0, 0.56, 0))
	return root
