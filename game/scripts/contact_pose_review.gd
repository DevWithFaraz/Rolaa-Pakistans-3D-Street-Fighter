extends "res://scripts/surface_fit_review.gd"
func _ready() -> void:
	asset_path = "res://assets/characters/khan_contact_pose_trial.glb"
	super._ready()
func _run_review() -> void:
	DirAccess.make_dir_recursive_absolute(capture_dir)
	player.play("MmaKick",0)
	player.speed_scale = 0
	player.seek(17.0/30.0,true)
	await get_tree().process_frame
	for view in [["front",0.15],["back",PI],["side",PI/2]]:
		orbit = view[1]; _camera_position()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join("MmaKick_%s_018.png" % view[0]))
	get_tree().quit()
