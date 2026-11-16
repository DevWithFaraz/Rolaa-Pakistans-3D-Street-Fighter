extends Node3D
## Isolated motion/garment review. Combat timing and the main scene are unchanged.
const CLIPS = ["Idle", "Idle2", "Punch", "MmaKick"]
var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var spring: SpringBoneSimulator3D
var clearance: SkeletonModifier3D
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
	model = load("res://assets/characters/khan_garment_trial.glb").instantiate()
	add_child(model)
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
	clearance = load("res://scripts/kameez_clearance.gd").new()
	clearance.name = "KameezThighClearance"
	skeleton.add_child(clearance)
	spring = SpringBoneSimulator3D.new()
	spring.name = "KameezGravityAndSway"
	skeleton.add_child(spring)
	spring.influence = 0.22
	spring.setting_count = 2
	var index := 0
	for side in ["front", "back"]:
		for column in ["C"]:
			var prefix: String = "cloth_"+side+"_"+column+"_"
			spring.set_root_bone_name(index,prefix+"0")
			spring.set_end_bone_name(index,prefix+"2")
			spring.set_extend_end_bone(index,true)
			spring.set_end_bone_direction(index,SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
			spring.set_end_bone_length(index,0.155)
			spring.set_center_from(index,SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
			spring.set_stiffness(index,1.3)
			spring.set_drag(index,0.75)
			spring.set_gravity(index,0.6)
			spring.set_gravity_direction(index,Vector3.DOWN)
			spring.set_radius(index,0.025)
			spring.set_enable_all_child_collisions(index,true)
			index += 1
	for side in ["Left", "Right"]:
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = side+"ThighClothCollision"
		spring.add_child(capsule)
		capsule.bone_name = "mixamorig_"+side+"UpLeg"
		capsule.height = 0.59
		capsule.radius = 0.12
		capsule.position_offset = Vector3(0,0.19,0)
	var pelvis := SpringBoneCollisionCapsule3D.new()
	pelvis.name = "HipClothCollision"
	spring.add_child(pelvis)
	pelvis.bone_name = "mixamorig_Hips"
	pelvis.height = 0.30
	pelvis.radius = 0.12
	pelvis.position_offset = Vector3(0,0.025,0)

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
	title.text = "  KHAN SAHAB  /  GARMENT & MOTION REVIEW  "
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
	clearance.active = cloth_enabled
	clearance.reset()
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
			clearance.active = cloth_enabled
			clearance.reset()
		KEY_T:
			sway = not sway
			if not sway: model.position.x = 0.0; spring.reset()
		KEY_Q: orbit -= 0.3; _camera_position()
		KEY_E: orbit += 0.3; _camera_position()
		KEY_HOME: clearance.reset(); spring.reset()
		KEY_ESCAPE: get_tree().quit()
	_update_status()

func _run_review() -> void:
	var report := {"clips": [], "spring_settings": spring.setting_count, "spring_influence":spring.influence, "cloth_enabled":cloth_enabled, "bone_count": skeleton.get_bone_count(), "finite_poses": true, "sample_stage":"modifier result before influence blending; displacement includes pose clearance", "performance_benchmark":false}
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
				pose_file.store_string(JSON.stringify({"points":modified_world,"front_lift":clearance.front_angle,"back_lift":clearance.back_angle},"  "))
		report.clips.append({"name":clip,"length":player.get_animation(clip).length,"frames_exercised":count,"solver_samples":solver_samples,"max_solver_tip_displacement_from_animated_rest":maximum_offset})
	if not capture_dir.is_empty():
		var file := FileAccess.open(capture_dir.path_join("runtime-check.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"  "))
	print("GARMENT_REVIEW ",JSON.stringify(report))
	get_tree().quit(0 if report.finite_poses else 1)

func _sample_modified_cloth() -> void:
	solver_samples += 1
	modified_tips.clear()
	modified_world.clear()
	var hips := skeleton.find_bone("mixamorig_Hips")
	var body_delta := skeleton.get_bone_global_pose(hips) * skeleton.get_bone_global_rest(hips).affine_inverse()
	for side in ["front", "back"]:
		var idx := skeleton.find_bone("cloth_"+side+"_C_2")
		var reference := body_delta * skeleton.get_bone_global_rest(idx).origin
		modified_tips.append(skeleton.get_bone_global_pose(idx).origin-reference)
	for name in ["mixamorig_Hips","mixamorig_LeftLeg","mixamorig_RightLeg","cloth_front_C_0","cloth_front_C_2","cloth_back_C_0","cloth_back_C_2"]:
		var index := skeleton.find_bone(name)
		var point := skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
		modified_world[name] = [point.x,point.y,point.z]
