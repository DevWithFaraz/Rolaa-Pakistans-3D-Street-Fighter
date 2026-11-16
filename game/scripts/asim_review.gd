extends Node3D

const MODEL_SCENE := preload("res://assets/characters/asim_model1.glb")
const REQUIRED_CLIPS := ["Idle", "Idle2", "Punch", "MmaKick"]
const EXTRA_CLIPS := ["Walk", "QuadPunch", "RoundhouseKick", "Headbutt"]

var model: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var camera: Camera3D
var status: Label
var orbit: float = 0.55
var distance: float = 3.25
var paused: bool = false
var current_clip: String = "Idle"
var testing: bool = false
var capture_dir: String = ""


func _ready() -> void:
	_environment()
	model = MODEL_SCENE.instantiate()
	add_child(model)
	skeleton = _find_type(model, "Skeleton3D") as Skeleton3D
	player = _find_type(model, "AnimationPlayer") as AnimationPlayer
	assert(skeleton != null, "Missing Skeleton3D in asim_model1.glb")
	assert(player != null, "Missing AnimationPlayer in asim_model1.glb")

	for c in ["Idle", "Idle2", "Walk"]:
		if player.has_animation(c):
			player.get_animation(c).loop_mode = Animation.LOOP_LINEAR

	_ui()

	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg == "--garment-test" or arg == "--asim-test":
			testing = true
		elif arg.begins_with("--capture-dir="):
			capture_dir = arg.split("=", false, 1)[1]

	if testing:
		call_deferred("_run_review")
	else:
		_play("Idle")


func _find_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_type(child, type_name)
		if found != null:
			return found
	return null


func _environment() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("242b32")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b9c8d3")
	world.environment.ambient_light_energy = 0.35
	world.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -32, 0)
	sun.light_color = Color("fff2e0")
	sun.light_energy = 0.95
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_color = Color("bdd9ff")
	fill.light_energy = 0.28
	add_child(fill)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.08)
	mat.roughness = 0.9
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	camera = Camera3D.new()
	camera.fov = 36.0
	add_child(camera)
	_camera_position()


func _camera_position() -> void:
	camera.position = Vector3(sin(orbit) * distance, 1.24, cos(orbit) * distance)
	camera.look_at(Vector3(0, 0.92, 0))


func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 18)
	var box := VBoxContainer.new()
	panel.add_child(box)
	layer.add_child(panel)

	var title := Label.new()
	title.text = "  ASIM JANI MODEL 1  /  ISOLATED GL_COMPATIBILITY REVIEW  "
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)

	status = Label.new()
	box.add_child(status)

	var controls := Label.new()
	controls.text = "  1 Idle  2 Idle2  3 Punch  4 MmaKick  5 Walk  6 QuadPunch  7 Roundhouse  8 Headbutt\n  Q / E Turn view   Wheel Zoom   Space Pause   Esc Exit  "
	controls.add_theme_font_size_override("font_size", 14)
	box.add_child(controls)


func _play(clip: String) -> void:
	if not player.has_animation(clip):
		return
	current_clip = clip
	player.play(clip, 0.0)
	player.seek(0.0, true)
	paused = false
	player.speed_scale = 1.0
	_update_status()


func _update_status() -> void:
	if status != null:
		status.text = "  %s  |  %s  " % [current_clip, "paused" if paused else "playing"]


func _unhandled_input(event: InputEvent) -> void:
	if testing:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(1.8, distance - 0.25)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(8.0, distance + 0.25)
		_camera_position()
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_1: _play("Idle")
		KEY_2: _play("Idle2")
		KEY_3: _play("Punch")
		KEY_4: _play("MmaKick")
		KEY_5: _play("Walk")
		KEY_6: _play("QuadPunch")
		KEY_7: _play("RoundhouseKick")
		KEY_8: _play("Headbutt")
		KEY_SPACE:
			paused = not paused
			player.speed_scale = 0.0 if paused else 1.0
		KEY_Q:
			orbit -= 0.3
			_camera_position()
		KEY_E:
			orbit += 0.3
			_camera_position()
		KEY_ESCAPE:
			get_tree().quit()
	_update_status()


func _all_bones_finite() -> bool:
	for i in range(skeleton.get_bone_count()):
		if not skeleton.get_bone_global_pose(i).is_finite():
			return false
	return true


func _pose_bounds_metrics() -> Dictionary:
	var min_y := 999.0
	var max_y := -999.0
	for i in range(skeleton.get_bone_count()):
		var p: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
		min_y = minf(min_y, p.y)
		max_y = maxf(max_y, p.y)
	var hips := skeleton.find_bone("mixamorig_Hips")
	var hip_y := (skeleton.global_transform * skeleton.get_bone_global_pose(hips).origin).y
	return {"min_bone_y": min_y, "max_bone_y": max_y, "hips_y": hip_y}


func _capture_views(prefix: String) -> void:
	if capture_dir.is_empty():
		return
	var views := [
		["front", 0.45],
		["side", 1.57],
		["back", 3.14],
	]
	for v in views:
		orbit = v[1]
		_camera_position()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("%s_%s.png" % [prefix, v[0]]))


func _run_review() -> void:
	if not capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(capture_dir)

	var anim_list := Array(player.get_animation_list())
	var clips_to_test: Array[String] = []
	for c in REQUIRED_CLIPS + EXTRA_CLIPS:
		if player.has_animation(c):
			clips_to_test.append(c)

	var report := {
		"model": "res://assets/characters/asim_model1.glb",
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info().string,
		"bone_count": skeleton.get_bone_count(),
		"available_animations": anim_list,
		"missing_required_clips": REQUIRED_CLIPS.filter(func(c): return not player.has_animation(c)),
		"finite_bone_transforms": true,
		"clips": [],
	}

	var peak_times := {
		"Idle": 5.0,
		"Idle2": 0.95,
		"Punch": 0.567,
		"MmaKick": 0.933,
		"Walk": 0.50,
		"QuadPunch": 0.50,
		"RoundhouseKick": 0.933,
		"Headbutt": 0.85,
	}

	for clip in clips_to_test:
		var anim := player.get_animation(clip)
		var length := anim.length
		var steps := int(ceil(length * 30.0)) + 1
		var clip_finite := true
		var min_y_all := 999.0
		var max_y_all := -999.0

		player.stop()
		player.play(clip)
		player.speed_scale = 0.0

		for s in range(steps):
			var t := minf(length, float(s) / 30.0)
			player.seek(t, true)
			await get_tree().process_frame
			var ok := _all_bones_finite()
			clip_finite = clip_finite and ok
			report.finite_bone_transforms = report.finite_bone_transforms and ok
			var m := _pose_bounds_metrics()
			min_y_all = minf(min_y_all, m.min_bone_y)
			max_y_all = maxf(max_y_all, m.max_bone_y)

		var peek_t := clampf(peak_times.get(clip, length * 0.5), 0.0, length)
		player.seek(peek_t, true)
		await _capture_views(clip)

		report.clips.append({
			"name": clip,
			"length_s": snappedf(length, 0.001),
			"steps_checked": steps,
			"finite_bones": clip_finite,
			"min_bone_y": snappedf(min_y_all, 0.001),
			"max_bone_y": snappedf(max_y_all, 0.001),
		})

	var ok_all: bool = report.finite_bone_transforms and report.bone_count == 65 and report.missing_required_clips.is_empty()
	report["passed"] = ok_all

	if not capture_dir.is_empty():
		var file := FileAccess.open(capture_dir.path_join("runtime-check.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))

	print("ASIM_REVIEW " + JSON.stringify(report))
	get_tree().quit(0 if ok_all else 1)
