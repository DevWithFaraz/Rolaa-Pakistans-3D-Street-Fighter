extends Node3D
## Isolated motion/garment review. Combat timing and the main scene are unchanged.
const CLIPS = ["Idle", "Idle2", "Punch", "MmaKick"]
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var spring: SkeletonModifier3D
var camera: Camera3D
var status: Label
var current_clip := "Idle2"
var paused := false
var cloth_enabled := true
var orbit := 0.45
var distance := 4.2
var sway := false
var elapsed := 0.0
var testing := false
var capture_dir := ""
var modified_tips: Array[Vector3] = []
var modified_world := {}
var solver_samples := 0

func _ready() -> void:
	testing = "--garment-test" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	model = load("res://assets/characters/khan_cloth_hands_v2.glb").instantiate()
	add_child(model)
	for mesh_name in ["Kameez_Front_Panel","Kameez_Back_Panel"]:
		var panel_mesh := model.find_child(mesh_name,true,false) as MeshInstance3D
		if panel_mesh:
			var fabric_material := panel_mesh.get_active_material(0).duplicate() as StandardMaterial3D
			fabric_material.cull_mode=BaseMaterial3D.CULL_DISABLED
			panel_mesh.material_override=fabric_material
	skeleton = _find_type(model,"Skeleton3D") as Skeleton3D
	player = _find_type(model,"AnimationPlayer") as AnimationPlayer
	for clip in CLIPS:
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_setup_springs()
	cloth_enabled = not "--cloth-disabled" in OS.get_cmdline_user_args()
	spring.modification_processed.connect(_sample_modified_cloth)
	_environment()
	_ui()
	_play(current_clip)
	if testing: call_deferred("_run_review")

func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name): return node
	for child in node.get_children():
		var found := _find_type(child,type_name)
		if found: return found
	return null

func _setup_springs() -> void:
	spring = load("res://scripts/kameez_fabric_grid.gd").new()
	spring.name = "KameezConnectedFabric"
	skeleton.add_child(spring)

func _environment() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b32")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b9c8d3")
	world.environment.ambient_light_energy = 0.30
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45,-35,0)
	sun.light_color = Color("fff0dd")
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20,140,0)
	fill.light_color = Color("bdd9ff")
	fill.light_energy = 0.18
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30,30)
	floor_mesh.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.055,0.065,0.075)
	material.roughness = 0.9
	floor_mesh.material_override = material
	add_child(floor_mesh)
	camera = Camera3D.new()
	camera.fov = 36.0
	add_child(camera)
	_camera_position()

func _camera_position() -> void:
	camera.position = Vector3(sin(orbit)*distance,1.30,cos(orbit)*distance)
	camera.look_at(Vector3(0,0.93,0))

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(22,18)
	var box := VBoxContainer.new()
	panel.add_child(box)
	layer.add_child(panel)
	var title := Label.new()
	title.text = "  KHAN SAHAB  /  GARMENT & HANDS / REVISION 2  "
	title.add_theme_font_size_override("font_size",22)
	box.add_child(title)
	status = Label.new()
	box.add_child(status)
	var controls := Label.new()
	controls.text = "  1 / 2  Idles     3  Punch     4  Kick     Space  Pause\n  C  Cloth on/off     T  Translation sway test     Q / E  Turn view\n  Mouse wheel  Zoom     Home  Reset cloth     Esc  Exit  "
	controls.add_theme_font_size_override("font_size",15)
	box.add_child(controls)
	var note := Label.new()
	note.position = Vector2(22,675)
	note.text = "GARMENT EXPERIMENT  •  Finger and garment finish still in progress"
	note.modulate = Color("d7be84")
	layer.add_child(note)

func _play(clip: String) -> void:
	current_clip = clip
	player.play(clip,0.15)
	player.advance(0)
	paused = false
	player.speed_scale = 1
	spring.active = cloth_enabled
	spring.reset()
	_update_status()

func _update_status() -> void:
	status.text = "  %s  |  cloth %s  |  %s  " % [current_clip,"ON" if cloth_enabled else "OFF","paused" if paused else "playing"]

func _process(delta: float) -> void:
	if not paused:
		elapsed += delta
		if sway: model.position.x = sin(elapsed*1.8)*0.18

func _unhandled_input(event: InputEvent) -> void:
	if testing: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(2.0,distance-0.25)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(8.0,distance+0.25)
		_camera_position()
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: _play("Idle")
		KEY_2: _play("Idle2")
		KEY_3: _play("Punch")
		KEY_4: _play("MmaKick")
		KEY_SPACE:
			paused = not paused
			player.speed_scale = 0 if paused else 1
			spring.active = cloth_enabled
		KEY_C:
			cloth_enabled = not cloth_enabled
			spring.active = cloth_enabled
		KEY_T:
			sway = not sway
			if not sway: model.position.x = 0.0; spring.reset()
		KEY_Q: orbit -= 0.3; _camera_position()
		KEY_E: orbit += 0.3; _camera_position()
		KEY_HOME: spring.reset()
		KEY_ESCAPE: get_tree().quit()
	_update_status()

func _run_review() -> void:
	var report := {"clips":[],"finite_poses":true,"performance_benchmark":false,"cloth_enabled":cloth_enabled,"control_grid":"two 5x6 panels","metric":"world point magnitude, not sway amplitude"}
	if not capture_dir.is_empty(): DirAccess.make_dir_recursive_absolute(capture_dir)
	for clip in CLIPS:
		_play(clip)
		var count := int(ceil(player.get_animation(clip).length*60.0))+30
		if "--quick-review" in OS.get_cmdline_user_args(): count = 100
		var maximum_offset := 0.0
		solver_samples = 0
		for f in range(count):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			for point in modified_tips:
				report.finite_poses = report.finite_poses and point.is_finite()
				maximum_offset = maxf(maximum_offset,point.length())
			var capture_frame := 42 if clip=="MmaKick" else 36 if clip=="Punch" else 90 if clip=="Idle" else 45
			if f == capture_frame and not capture_dir.is_empty():
				get_viewport().get_texture().get_image().save_png(capture_dir.path_join(clip+".png"))
				var pose_file := FileAccess.open(capture_dir.path_join(clip+"-pose.json"),FileAccess.WRITE)
				pose_file.store_string(JSON.stringify(modified_world,"  "))
		report.clips.append({"name":clip,"length":player.get_animation(clip).length,"frames_exercised":count,"solver_samples":solver_samples,"max_world_point_magnitude":maximum_offset})
	if not capture_dir.is_empty():
		var file := FileAccess.open(capture_dir.path_join("runtime-check.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	print("GARMENT_REVIEW ",JSON.stringify(report))
	get_tree().quit(0 if report.finite_poses else 1)

func _sample_modified_cloth() -> void:
	solver_samples += 1
	modified_tips.clear()
	modified_world.clear()
	for point in spring.points: modified_tips.append(point)
	modified_world["collision_envelope_penetration_m"] = spring.max_penetration

