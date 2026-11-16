class_name PerfBenchmark
extends RefCounted
## Automated 2-fighter rendered performance benchmark logging frame times, draw calls, primitives, and memory.

const WARMUP_FRAMES := 30
const SAMPLE_FRAMES := 240


func _percentile(sorted_vals: Array[float], pct: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var idx := int(ceilf(clampf(pct, 0.0, 1.0) * float(sorted_vals.size() - 1)))
	return sorted_vals[idx]


func _release_all() -> void:
	for player in [1, 2]:
		for suffix in ["left", "right", "jump", "guard", "punch", "kick"]:
			Input.action_release("p%d_%s" % [player, suffix])


func _drive_choreography(frame: int, g: Node) -> void:
	_release_all()
	var phase := frame % 120
	if phase < 25:
		Input.action_press("p1_right")
		Input.action_press("p2_left")
	elif phase >= 26 and phase <= 28:
		Input.action_press("p1_punch")
	elif phase >= 40 and phase <= 55:
		Input.action_press("p1_guard")
		if phase >= 45 and phase <= 47:
			Input.action_press("p2_kick")
	elif phase >= 70 and phase <= 72:
		Input.action_press("p1_jump")
		Input.action_press("p2_right")
	elif phase >= 92 and phase <= 94:
		Input.action_press("p2_punch")
	# Keep both fighters alive during the benchmark loop.
	if g.fighters[0].health < 40:
		g.fighters[0].health = 100
	if g.fighters[1].health < 40:
		g.fighters[1].health = 100


func run(g: Node, out_path: String, capture_path: String = "") -> void:
	var preset := "medium"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			preset = arg.trim_prefix("--preset=")
	preset = GraphicsPresets.apply(g, preset)

	g.testing = true
	g.reset()
	g.round_state = "fight"
	g.fighters[0].position.x = -1.3
	g.fighters[1].position.x = 1.3

	for _w in range(WARMUP_FRAMES):
		await g.get_tree().process_frame

	var frame_times_ms: Array[float] = []
	var cpu_process_ms: Array[float] = []
	var draw_calls: Array[int] = []
	var primitives: Array[int] = []
	var objects_in_frame: Array[int] = []

	var prev_us := Time.get_ticks_usec()
	for f in range(SAMPLE_FRAMES):
		_drive_choreography(f, g)
		await g.get_tree().process_frame
		var now_us := Time.get_ticks_usec()
		frame_times_ms.append(float(now_us - prev_us) / 1000.0)
		prev_us = now_us

		cpu_process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draw_calls.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		objects_in_frame.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))

		if f == 150 and not capture_path.is_empty() and DisplayServer.get_name() != "headless":
			DirAccess.make_dir_recursive_absolute(capture_path.get_base_dir())
			await RenderingServer.frame_post_draw
			g.get_viewport().get_texture().get_image().save_png(capture_path)
			prev_us = Time.get_ticks_usec()

	_release_all()

	var sorted_ms := frame_times_ms.duplicate()
	sorted_ms.sort()
	var sorted_cpu := cpu_process_ms.duplicate()
	sorted_cpu.sort()

	var sum_ms := 0.0
	for v in frame_times_ms:
		sum_ms += v
	var avg_ms := sum_ms / float(maxi(1, frame_times_ms.size()))
	var avg_fps := 1000.0 / avg_ms if avg_ms > 0.0 else 0.0

	var sum_cpu := 0.0
	for v in cpu_process_ms:
		sum_cpu += v
	var avg_cpu_ms := sum_cpu / float(maxi(1, cpu_process_ms.size()))

	var sum_dc := 0
	var max_dc := 0
	for dc in draw_calls:
		sum_dc += dc
		max_dc = maxi(max_dc, dc)

	var sum_prim := 0
	var max_prim := 0
	for pr in primitives:
		sum_prim += pr
		max_prim = maxi(max_prim, pr)

	var sum_obj := 0
	for ob in objects_in_frame:
		sum_obj += ob

	var p50_ms: float = _percentile(sorted_ms, 0.50)
	var p95_ms: float = _percentile(sorted_ms, 0.95)
	var p99_ms: float = _percentile(sorted_ms, 0.99)
	var max_ms: float = sorted_ms[sorted_ms.size() - 1] if not sorted_ms.is_empty() else 0.0

	var vram_bytes := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	var ram_bytes := float(OS.get_static_memory_usage())

	var report := {
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter_name": RenderingServer.get_video_adapter_name(),
		"adapter_api": RenderingServer.get_video_adapter_api_version(),
		"preset": preset,
		"resolution": [int(g.get_viewport().get_visible_rect().size.x), int(g.get_viewport().get_visible_rect().size.y)],
		"vsync_mode": DisplayServer.window_get_vsync_mode() if DisplayServer.get_name() != "headless" else -1,
		"warmup_frames": WARMUP_FRAMES,
		"sample_frames": SAMPLE_FRAMES,
		"avg_frame_time_ms": snappedf(avg_ms, 0.01),
		"avg_fps": snappedf(avg_fps, 0.1),
		"p50_frame_time_ms": snappedf(p50_ms, 0.01),
		"p95_frame_time_ms": snappedf(p95_ms, 0.01),
		"p99_frame_time_ms": snappedf(p99_ms, 0.01),
		"max_frame_time_ms": snappedf(max_ms, 0.01),
		"cpu_process_avg_ms": snappedf(avg_cpu_ms, 0.01),
		"cpu_process_p99_ms": snappedf(_percentile(sorted_cpu, 0.99), 0.01),
		"avg_draw_calls": int(round(float(sum_dc) / float(maxi(1, draw_calls.size())))),
		"max_draw_calls": max_dc,
		"avg_primitives": int(round(float(sum_prim) / float(maxi(1, primitives.size())))),
		"max_primitives": max_prim,
		"avg_objects_in_frame": int(round(float(sum_obj) / float(maxi(1, objects_in_frame.size())))),
		"vram_mb": snappedf(vram_bytes / (1024.0 * 1024.0), 0.2),
		"ram_mb": snappedf(ram_bytes / (1024.0 * 1024.0), 0.2),
		"meets_60fps_avg": avg_ms <= 16.9,
		"meets_p99_20ms": p99_ms <= 20.0,
		"engine": Engine.get_version_info().string,
	}

	if not out_path.is_empty():
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))

	print("PERF_BENCHMARK " + JSON.stringify(report))
	g.get_tree().quit(0)
