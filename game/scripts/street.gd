extends Node3D
## A camera-test set, assembled from instanced primitives. No external assets.

const INK = Color("233e42")
const TEAL = Color("207f79")
const GOLD = Color("e4ae58")
const CORAL = Color("ba6651")
const CREAM = Color("ead7ae")
var batches: Dictionary = {}
var palette: Dictionary = {}

func _ready() -> void:
	name = "LahoreStreetBlockout"
	_make_ground()
	_make_buildings()
	_make_bus(Vector3(-6.0, 0.0, -5.4))
	_make_stall(Vector3(10.3, 0.0, -5.0))
	for x in [-20.0, -11.0, 0.0, 11.0, 21.0]:
		_make_lamp(x, -3.9)
	for x in [-24.0, -15.0, 4.5, 17.0, 26.0]:
		_make_tree(x, -7.0)
	for x in range(-15, 16, 5):
		_box(Vector3(x, 0.72, -2.85), Vector3(4.6, 1.1, 0.13), INK)
		_box(Vector3(x, 1.3, -2.85), Vector3(4.7, 0.075, 0.16), GOLD)
		_sign("LAHORE  /  MALL ROAD", Vector3(x, 0.82, -2.755), 24, CREAM, 0.0038)
	_flush_batches()

func _make_ground() -> void:
	_box(Vector3(0, -0.4, 0), Vector3(130, 0.44, 70), Color("8d8b75"))
	_box(Vector3(0, -0.075, 1.5), Vector3(110, 0.15, 9), Color("65686a"))
	_box(Vector3(0, 0.05, -4.8), Vector3(110, 0.3, 3.8), Color("b6a78a"))
	for i in range(-55, 56):
		_box(Vector3(i, 0.15, -2.55), Vector3(0.95, 0.38, 0.4), GOLD if i % 2 == 0 else INK)
	for i in range(-18, 19):
		_box(Vector3(i * 3.0, 0.011, 3.65), Vector3(1.5, 0.012, 0.12), Color("c5b995"))
	# Small deterministic asphalt marks, batched into one draw group.
	var rng = RandomNumberGenerator.new()
	rng.seed = 7301
	for i in range(180):
		_box(Vector3(rng.randf_range(-40, 40), 0.008, rng.randf_range(-2.2, 6)), Vector3(rng.randf_range(0.03, 0.15), 0.005, 0.025), Color("747677"))
	var ground = StaticBody3D.new()
	ground.name = "RoadCollision"
	var shape_node = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(110, 0.5, 10)
	shape_node.shape = shape
	shape_node.position = Vector3(0, -0.25, 1)
	ground.add_child(shape_node)
	add_child(ground)
	# Boundary markers are outside the walkable arena, not invisible obstacles.
	for x in [-15.2, 15.2]:
		_box(Vector3(x, 0.18, -0.4), Vector3(0.25, 0.36, 0.25), GOLD)

func _make_buildings() -> void:
	var colors = [Color("b57b61"), Color("d0ad83"), Color("9f6759"), Color("c39773"), Color("c8b598")]
	for i in range(11):
		var x = float(i - 5) * 6.8
		var height = 6.0 + float(i % 3) * 1.1
		var tint: Color = colors[i % colors.size()]
		_box(Vector3(x, height * 0.5, -11), Vector3(6.5, height, 5), tint)
		_box(Vector3(x, height + 0.15, -11), Vector3(6.8, 0.3, 5.3), CREAM)
		for floor_index in range(2):
			var y = 3.3 + float(floor_index) * 2.0
			_box(Vector3(x, y - 0.85, -8.4), Vector3(6.5, 0.12, 0.26), CREAM)
			for column in range(4):
				var wx = x - 2.3 + column * 1.5
				_box(Vector3(wx, y, -8.42), Vector3(0.95, 1.35, 0.18), CREAM)
				_box(Vector3(wx, y, -8.29), Vector3(0.72, 1.14, 0.10), INK)
				_box(Vector3(wx, y, -8.21), Vector3(0.04, 1.13, 0.04), GOLD)
		_box(Vector3(x, 1.1, -8.3), Vector3(2.9, 2.1, 0.15), INK)
		_box(Vector3(x, 2.3, -8.04), Vector3(5.7, 0.55, 0.22), TEAL if i % 2 else CORAL)
		var names = ["MALL ROAD BOOKS", "LAHORE TEXTILES", "RADIO & REPAIR", "OLD CITY STORES", "CHAI CORNER"]
		_sign(names[i % names.size()], Vector3(x, 2.31, -7.89), 32, CREAM, 0.004)
	# A stylized clock tower, built as a landmark rather than an exact replica.
	_box(Vector3(3, 5.0, -19), Vector3(2.8, 10, 2.8), CORAL)
	for y in [2.5, 5.0, 8.0, 10.0]:
		_box(Vector3(3, y, -19), Vector3(3.05, 0.22, 3.05), CREAM)
	_sphere(Vector3(3, 8.8, -17.56), Vector3(1.55, 1.55, 0.13), CREAM)
	_box(Vector3(3, 9.0, -17.43), Vector3(0.055, 0.6, 0.04), INK)
	_box(Vector3(3.2, 8.81, -17.42), Vector3(0.45, 0.055, 0.04), INK)
	_cone(Vector3(3, 10.8, -19), Vector3(3.8, 1.4, 3.8), TEAL)
	for i in range(16):
		_box(Vector3((i - 8) * 5.5, 3.5, -29), Vector3(4.8, 6 + i % 4, 5), Color("b6b6a5"))

func _make_bus(p: Vector3) -> void:
	_box(p + Vector3(0, 1.6, 0), Vector3(7.9, 2.5, 2.05), TEAL)
	_box(p + Vector3(0, 2.83, 0), Vector3(8.05, 0.2, 2.2), GOLD)
	_box(p + Vector3(0, 1.22, 1.055), Vector3(7.95, 0.42, 0.06), CREAM)
	_box(p + Vector3(0, 0.6, 1.06), Vector3(7.95, 0.19, 0.08), CORAL)
	for i in range(7):
		var x = -3.15 + i * 1.05
		_box(p + Vector3(x, 2.17, 1.06), Vector3(0.87, 0.93, 0.05), INK)
		_box(p + Vector3(x, 2.17, 1.095), Vector3(0.06, 0.94, 0.03), GOLD)
		_sphere(p + Vector3(x, 0.94, 1.105), Vector3(0.31, 0.25, 0.04), GOLD)
		_sphere(p + Vector3(x, 0.94, 1.14), Vector3(0.11, 0.11, 0.02), CORAL)
	for x in [-2.65, 2.65]:
		_cylinder(p + Vector3(x, 0.5, 1.05), Vector3(1.03, 0.3, 1.03), Color("293739"), Vector3(PI / 2, 0, 0))
		_cylinder(p + Vector3(x, 0.5, 1.23), Vector3(0.49, 0.03, 0.49), CREAM, Vector3(PI / 2, 0, 0))
	for x in [-3.6, 3.6]:
		_box(p + Vector3(x, 3.12, 0), Vector3(0.075, 0.42, 2.0), CORAL)
	_box(p + Vector3(0, 3.3, 0.95), Vector3(7.35, 0.065, 0.07), CORAL)
	_sign("LAHORE EXPRESS", p + Vector3(0, 1.23, 1.105), 32, TEAL, 0.0036)

func _make_stall(p: Vector3) -> void:
	_box(p + Vector3(0, 0.6, 0), Vector3(3.7, 1.2, 1.4), TEAL)
	for x in [-1.7, 1.7]:
		_box(p + Vector3(x, 1.9, 0), Vector3(0.08, 2.6, 0.08), INK)
	_box(p + Vector3(0, 3.15, 0), Vector3(4.2, 0.2, 2.2), CORAL)
	_box(p + Vector3(0, 2.65, 0.75), Vector3(3.7, 0.7, 0.12), INK)
	_sign("CHAI  •  PAKISTAN", p + Vector3(0, 2.65, 0.83), 36, CREAM, 0.004)
	for x in [-0.9, -0.4, 0.1, 0.6, 1.1]:
		_cylinder(p + Vector3(x, 1.3, 0.3), Vector3(0.2, 0.22, 0.2), CREAM)
	_cylinder(p + Vector3(-1.2, 1.55, -0.1), Vector3(0.5, 0.65, 0.5), GOLD)

func _make_lamp(x: float, z: float) -> void:
	_cylinder(Vector3(x, 2.45, z), Vector3(0.1, 4.9, 0.1), INK)
	_cylinder(Vector3(x, 0.3, z), Vector3(0.27, 0.6, 0.27), INK)
	_box(Vector3(x + 0.37, 4.8, z), Vector3(0.8, 0.07, 0.07), INK)
	_box(Vector3(x + 0.72, 4.55, z), Vector3(0.37, 0.43, 0.37), GOLD)
	_cone(Vector3(x + 0.72, 4.86, z), Vector3(0.65, 0.25, 0.65), INK)

func _make_tree(x: float, z: float) -> void:
	_cylinder(Vector3(x, 2.25, z), Vector3(0.35, 4.5, 0.35), Color("776451"))
	_sphere(Vector3(x, 4.95, z), Vector3(4.3, 3.4, 3.8), Color("74876a"))
	_sphere(Vector3(x - 1.2, 4.7, z + 0.4), Vector3(2.7, 2.7, 2.6), Color("889269"))

func _sign(text: String, at: Vector3, font_size: int, color: Color, pixel_size: float) -> void:
	var label = Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	label.position = at
	add_child(label)

func _box(at: Vector3, size: Vector3, color: Color) -> void:
	_queue("box", at, size, color)

func _sphere(at: Vector3, size: Vector3, color: Color) -> void:
	_queue("sphere", at, size, color)

func _cylinder(at: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	_queue("cylinder", at, size, color, rot)

func _cone(at: Vector3, size: Vector3, color: Color) -> void:
	_queue("cone", at, size, color)

func _queue(kind: String, at: Vector3, size: Vector3, color: Color, rot: Vector3 = Vector3.ZERO) -> void:
	var key = kind + color.to_html()
	if not batches.has(key):
		batches[key] = {"kind": kind, "color": color, "transforms": []}
	batches[key]["transforms"].append(Transform3D(Basis.from_euler(rot).scaled(size), at))

func _flush_batches() -> void:
	for key in batches:
		var data: Dictionary = batches[key]
		var mesh: PrimitiveMesh
		if data.kind == "box":
			mesh = BoxMesh.new()
		elif data.kind == "sphere":
			var sphere = SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		else:
			var cylinder = CylinderMesh.new()
			cylinder.top_radius = 0.0 if data.kind == "cone" else 0.5
			cylinder.bottom_radius = 0.5
			cylinder.height = 1.0
			cylinder.radial_segments = 12
			mesh = cylinder
		var material = StandardMaterial3D.new()
		material.albedo_color = data.color
		material.roughness = 0.95
		mesh.material = material
		var multi = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = data.transforms.size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i, data.transforms[i])
		var instance = MultiMeshInstance3D.new()
		instance.multimesh = multi
		add_child(instance)
	batches.clear()
