extends "res://scripts/textured_seam_review.gd"
## Isolated baked clearance candidate, never loaded by the main game.
var asset_path := "res://assets/characters/khan_surface_fit_trial.glb"

func _ready() -> void:
	testing = "--garment-test" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir = arg.trim_prefix("--capture-dir=")
	model = load(asset_path).instantiate()
	add_child(model)
	skeleton = _find_type(model,"Skeleton3D") as Skeleton3D
	player = _find_type(model,"AnimationPlayer") as AnimationPlayer
	for clip in CLIPS: player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_environment()
	_ui()
	_play(current_clip)
	if testing: call_deferred("_run_review")

func _ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.position = Vector2(20,18)
	layer.add_child(status)
	var help := Label.new()
	help.text = "TEXTURED CLEARANCE TRIAL • clip-specific correction\n1/2 idle   3 punch   4 kick   Space pause   Q/E orbit   Wheel zoom\nHands unchanged. Garment still under inspection."
	help.position = Vector2(20,600)
	layer.add_child(help)

func _play(clip: String) -> void:
	current_clip = clip
	player.play(clip,0.15)
	player.advance(0)
	paused = false
	player.speed_scale = 1.0
	_update_status()

func _update_status() -> void:
	status.text = "%s | %s" % [current_clip,"paused" if paused else "playing"]

func _unhandled_input(event: InputEvent) -> void:
	if testing: return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(2,distance-.25)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(8,distance+.25)
		_camera_position()
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.physical_keycode:
		KEY_1: _play("Idle")
		KEY_2: _play("Idle2")
		KEY_3: _play("Punch")
		KEY_4: _play("MmaKick")
		KEY_SPACE:
			paused = not paused
			player.speed_scale = 0.0 if paused else 1.0
		KEY_Q: orbit -= .3; _camera_position()
		KEY_E: orbit += .3; _camera_position()
		KEY_ESCAPE: get_tree().quit()
	_update_status()

func _run_review() -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var report := {"clips":[],"bone_count":skeleton.get_bone_count(),"visual_acceptance":false,"finite_bone_transforms":true}
	for clip in CLIPS:
		player.play(clip,0)
		player.speed_scale = 0
		var length := player.get_animation(clip).length
		var frames := int(ceil(length*30))
		for f in range(frames+1):
			player.seek(minf(f/30.0,length-.001),true)
			await get_tree().process_frame
			for bone in range(skeleton.get_bone_count()):
				report.finite_bone_transforms = report.finite_bone_transforms and skeleton.get_bone_global_pose(bone).is_finite()
			if f % maxi(1,frames/8) == 0 or f==frames:
				for view in [["front",0.15],["back",PI],["side",PI/2]]:
					orbit = view[1]; _camera_position()
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
					get_viewport().get_texture().get_image().save_png(capture_dir.path_join("%s_%s_%03d.png" % [clip,view[0],f]))
		report.clips.append({"clip":clip,"frames_checked":frames+1,"length":length})
	var file := FileAccess.open(capture_dir.path_join("runtime-check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("SURFACE_REVIEW ",JSON.stringify(report))
	get_tree().quit()
