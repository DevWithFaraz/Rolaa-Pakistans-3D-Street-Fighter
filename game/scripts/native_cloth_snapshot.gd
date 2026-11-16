extends "res://scripts/garment_review.gd"

func _ready() -> void:
	testing = true
	model = load("res://assets/characters/khan_native_cloth_idle_static.glb").instantiate()
	add_child(model)
	_environment()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	if capture_dir.is_empty(): get_tree().quit(1); return
	DirAccess.make_dir_recursive_absolute(capture_dir)
	for view in [["front",0.45],["back",PI],["side",PI/2]]:
		orbit=view[1]
		_camera_position()
		for frame in range(5):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(capture_dir.path_join(view[0]+".png"))
	get_tree().quit()
