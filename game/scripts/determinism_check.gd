class_name DeterminismCheck
extends RefCounted
## Verifies NFR-3 (input-to-state latency <= 3 frames) and NFR-4 (fixed-tick replay & snapshot determinism).

const SEQUENCE_TICKS := 180
const SNAPSHOT_TICK := 75


func _release_all() -> void:
	for player in [1, 2]:
		for suffix in ["left", "right", "jump", "guard", "punch", "kick"]:
			Input.action_release("p%d_%s" % [player, suffix])


func _setup_pair(g: Node, dist: float = 1.6) -> void:
	_release_all()
	g.testing = true
	g.dummy_guard = false
	g.paused = false
	g.demo = false
	g.reset()
	await g._tick(4)
	g.fighters[0].position.x = -dist * 0.5
	g.fighters[1].position.x = dist * 0.5
	await g._tick(2)


func _scripted_inputs_for_tick(t: int) -> void:
	_release_all()
	# Ensure clean input edges around SNAPSHOT_TICK (74..75) so snapshot restore resumes with no held edges.
	if t >= 0 and t < 18:
		Input.action_press("p1_right")
		Input.action_press("p2_left")
	elif t == 20:
		Input.action_press("p1_punch")
	elif t >= 35 and t < 44:
		Input.action_press("p2_guard")
		if t == 38:
			Input.action_press("p1_kick")
	elif t == 58:
		Input.action_press("p2_punch")
	elif t == 74 or t == 75:
		pass
	elif t >= 78 and t < 94:
		Input.action_press("p1_left")
		Input.action_press("p2_right")
	elif t == 98:
		Input.action_press("p1_jump")
	elif t == 112:
		Input.action_press("p2_kick")
	elif t >= 135 and t < 148:
		Input.action_press("p1_right")
		Input.action_press("p2_left")
	elif t == 152:
		Input.action_press("p1_punch")
		Input.action_press("p2_punch")


func _fmt_mm(v: float) -> String:
	var clean := 0.0 if absf(v) < 0.0005 else snappedf(v, 0.001)
	return "%.3f" % (0.0 if absf(clean) < 0.0005 else clean)


func _state_digest(snap: Dictionary) -> String:
	var f0: Dictionary = snap.fighters[0]
	var f1: Dictionary = snap.fighters[1]
	return "%s|%d|%d|%s,%s,%d,%s,%d,%s,%d|%s,%s,%d,%s,%d,%s,%d|%s" % [
		snap.round_state,
		int(snap.round_time_ticks),
		int(snap.hitstop_ticks),
		_fmt_mm(float(f0.px)),
		_fmt_mm(float(f0.py)),
		int(f0.health),
		String(f0.state),
		int(f0.state_ticks),
		String(f0.attack_kind),
		int(f0.attack_tick),
		_fmt_mm(float(f1.px)),
		_fmt_mm(float(f1.py)),
		int(f1.health),
		String(f1.state),
		int(f1.state_ticks),
		String(f1.attack_kind),
		int(f1.attack_tick),
		_fmt_mm(float(snap.camera_x)),
	]


func _snapshots_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	if a is Dictionary:
		if a.size() != b.size():
			return false
		for k in a:
			if not b.has(k) or not _snapshots_equal(a[k], b[k]):
				return false
		return true
	if a is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _snapshots_equal(a[i], b[i]):
				return false
		return true
	if a is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _measure_latency(g: Node, action: String, condition: Callable) -> int:
	Input.action_press(action)
	var ticks := -1
	for i in range(1, 8):
		await g._tick(1)
		if condition.call():
			ticks = i
			break
	Input.action_release(action)
	return ticks


func run(g: Node) -> void:
	# Test A: Input-to-state latency (NFR-3: <= 3 frames added).
	await _setup_pair(g, 1.6)
	var punch_lat := await _measure_latency(
		g,
		"p1_punch",
		func() -> bool: return g.fighters[0].state == "attack" and g.fighters[0].attack_kind == "punch"
	)
	g._check(punch_lat >= 1 and punch_lat <= 3, "P1 punch input-to-state latency <= 3 frames (got %d)" % punch_lat)

	await _setup_pair(g, 3.0)
	var kick_lat := await _measure_latency(
		g,
		"p2_kick",
		func() -> bool: return g.fighters[1].state == "attack" and g.fighters[1].attack_kind == "kick"
	)
	g._check(kick_lat >= 1 and kick_lat <= 3, "P2 kick input-to-state latency <= 3 frames (got %d)" % kick_lat)
	await g._tick(12)
	g._check(
		g.fighters[1].attack_tick == 12 and g.fighters[1].get_attack_box().has_area(),
		"Kick hitbox activates on exact startup tick 12"
	)

	await _setup_pair(g, 1.6)
	var guard_lat := await _measure_latency(
		g,
		"p1_guard",
		func() -> bool: return g.fighters[0].state == "guard"
	)
	g._check(guard_lat >= 1 and guard_lat <= 3, "P1 guard input-to-state latency <= 3 frames (got %d)" % guard_lat)

	await _setup_pair(g, 1.6)
	var jump_lat := await _measure_latency(
		g,
		"p1_jump",
		func() -> bool: return g.fighters[0].velocity.y > 0.0
	)
	g._check(jump_lat >= 1 and jump_lat <= 3, "P1 jump input-to-state latency <= 3 frames (got %d)" % jump_lat)

	# Test B: Full-sequence replay determinism (NFR-4).
	var digests_run1: Array[String] = []
	var mid_snap: Dictionary = {}
	await _setup_pair(g, 2.0)
	for t in range(SEQUENCE_TICKS):
		_scripted_inputs_for_tick(t)
		await g._tick(1)
		var snap: Dictionary = g.snapshot_match()
		digests_run1.append(_state_digest(snap))
		if t == SNAPSHOT_TICK:
			mid_snap = snap.duplicate(true)
	_release_all()
	var end_snap_run1: Dictionary = g.snapshot_match()

	var digests_run2: Array[String] = []
	await _setup_pair(g, 2.0)
	for t in range(SEQUENCE_TICKS):
		_scripted_inputs_for_tick(t)
		await g._tick(1)
		digests_run2.append(_state_digest(g.snapshot_match()))
	_release_all()
	var end_snap_run2: Dictionary = g.snapshot_match()

	g._check(digests_run1 == digests_run2, "180-tick two-fighter replay produces identical per-tick state digests")
	g._check(_snapshots_equal(end_snap_run1, end_snap_run2), "180-tick replay ends with identical full match snapshot")

	# Test C: Mid-match snapshot save/restore determinism (NFR-4).
	g.restore_match(mid_snap)
	var digests_restored: Array[String] = []
	for t in range(SNAPSHOT_TICK + 1, SEQUENCE_TICKS):
		_scripted_inputs_for_tick(t)
		await g._tick(1)
		digests_restored.append(_state_digest(g.snapshot_match()))
	_release_all()
	var end_snap_restored: Dictionary = g.snapshot_match()

	var expected_tail := digests_run1.slice(SNAPSHOT_TICK + 1)
	g._check(digests_restored == expected_tail, "Snapshot restore at tick %d replays remaining ticks identically" % SNAPSHOT_TICK)
	g._check(_snapshots_equal(end_snap_restored, end_snap_run1), "Snapshot restore ends with identical final state")

	var report := {
		"passed": g.checks,
		"failed": g.failures,
		"latencies_ticks": {
			"p1_punch": punch_lat,
			"p2_kick": kick_lat,
			"p1_guard": guard_lat,
			"p1_jump": jump_lat,
		},
		"sequence_ticks": SEQUENCE_TICKS,
		"snapshot_tick": SNAPSHOT_TICK,
		"end_digest": digests_run1[digests_run1.size() - 1],
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info().string,
	}
	if not g.capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(g.capture_dir)
		var file := FileAccess.open(g.capture_dir.path_join("determinism-validation.json"), FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))

	print("DETERMINISM_VALIDATION " + JSON.stringify(report))
	g.get_tree().quit(0 if g.failures.is_empty() else 1)
