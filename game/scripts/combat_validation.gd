extends RefCounted
## Exercises real input actions and physics ticks in the running scene.
var g: Node

func release_inputs() -> void:
	for player in [1, 2]:
		for action in ["left", "right", "jump", "guard", "punch", "kick"]:
			Input.action_release("p%d_%s" % [player, action])

func setup(distance: float = 1.6) -> void:
	release_inputs()
	g.dummy_guard = false
	g.reset()
	await g._tick(4)
	g.fighters[0].position.x = -distance * 0.5
	g.fighters[1].position.x = distance * 0.5
	await g._tick(4)

func tap(action: String) -> void:
	Input.action_press(action)
	await g._tick(2)
	Input.action_release(action)

func check(ok: bool, message: String) -> void:
	g._check(ok, message)

func run(game: Node) -> void:
	g = game
	await setup()
	var limb: MeshInstance3D = g.fighters[0].limbs[0]
	var start = Vector3(0.0, 1.0, 0.25)
	var end = Vector3(1.6, 1.5, 0.25)
	g.fighters[0]._segment(limb, start, end, 0.18)
	check((limb.transform * Vector3.UP).is_equal_approx(end) and (limb.transform * Vector3.DOWN).is_equal_approx(start), "Rotated limb geometry joins both intended endpoints")
	await setup()
	g.testing = false
	g.reset()
	Input.action_press("p1_punch")
	await g._tick(15)
	Input.action_release("p1_punch")
	check(g.round_state == "ready" and g.fighters[0].state == "idle", "Ready countdown rejects attacks")
	check(g.round_time_ticks == g.ROUND_DURATION, "Round timer waits for fight start")
	await g._tick(65)
	check(g.round_state == "fight", "Ready countdown enters fight")
	g.testing = true
	await setup()
	await tap("p1_punch")
	await g._tick(3)
	check(g.fighters[1].health == 100, "Punch startup does not damage")
	await g._tick(6)
	check(g.fighters[1].health == 90 and g.fighters[1].state == "hitstun", "Punch deals ten damage and causes hitstun")
	await g._save_capture("combat-punch")
	await g._tick(40)
	check(g.fighters[1].health == 90, "An attack only damages once across active frames")
	check(g.fighters[1].position.x > 0.9, "Hit knockback moves opponent away")
	check(g.fighters[0].state == "idle" and g.fighters[1].state == "idle", "Attack recovery and hitstun return to neutral")
	await setup()
	Input.action_press("p2_guard")
	await g._tick(3)
	await tap("p1_punch")
	await g._tick(7)
	check(g.fighters[1].health == 100 and g.fighters[1].state == "blockstun", "Guard blocks damage and enters blockstun")
	await g._save_capture("combat-block")
	Input.action_release("p2_guard")
	await tap("p2_kick")
	await g._tick(3)
	check(g.fighters[1].state == "blockstun", "Releasing guard and attacking cannot cancel blockstun")
	await setup(2.6)
	await tap("p1_punch")
	await g._tick(28)
	check(g.fighters[1].health == 100, "Out-of-range punch misses")
	await tap("p1_kick")
	await g._tick(13)
	check(g.fighters[1].health == 83, "Longer-range kick deals seventeen damage")
	await g._save_capture("combat-kick")
	await setup()
	Input.action_press("p1_punch")
	Input.action_press("p2_punch")
	await g._tick(12)
	release_inputs()
	check(g.fighters[0].health == 90 and g.fighters[1].health == 90, "Simultaneous attacks trade without player-order advantage")
	check(g.event_text == "TRADE", "Trade feedback is displayed")
	await setup()
	g.fighters[0].position.x = 0.8
	g.fighters[1].position.x = -0.8
	await g._tick(3)
	await tap("p2_punch")
	await g._tick(10)
	check(g.fighters[0].health == 90 and g.fighters[1].facing > 0, "Attack and auto-facing work after switching sides")
	await setup()
	g.dummy_guard = true
	await g._tick(3)
	await tap("p1_kick")
	await g._tick(16)
	check(g.fighters[1].health == 100 and g.event_text == "BLOCK", "Solo auto-guard blocks attacks")
	await setup()
	await tap("p1_jump")
	await g._tick(6)
	await tap("p1_punch")
	check(g.fighters[0].state != "attack", "Ground attacks cannot start while airborne")
	await setup()
	await tap("p1_kick")
	await g._tick(3)
	var age: int = g.fighters[0].attack_tick
	var timer: int = g.round_time_ticks
	g.paused = true
	await g._tick(12)
	check(g.fighters[0].attack_tick == age and g.round_time_ticks == timer, "Pause freezes attack frames and round timer")
	g.paused = false
	await setup()
	g.fighters[1].health = 10
	await tap("p1_punch")
	await g._tick(40)
	check(g.fighters[1].health == 0 and g.fighters[1].state == "ko", "Lethal hit clamps health at zero and knocks out")
	check(g.wins == [1, 0] and g.round_state == "round_over", "KO awards exactly one round")
	await g._save_capture("combat-round-over")
	await tap("p1_kick")
	await g._tick(30)
	check(g.wins == [1, 0] and g.fighters[0].state != "attack", "Round-over state rejects combat and duplicate scoring")
	g._advance_round()
	await g._tick(4)
	check(g.round_number == 2 and g.wins == [1, 0] and g.fighters[1].health == 100, "Next round restores health and retains score")
	g.fighters[0].position.x = -0.8
	g.fighters[1].position.x = 0.8
	g.fighters[1].health = 10
	await tap("p1_punch")
	await g._tick(40)
	check(g.wins == [2, 0] and g.round_state == "match_over", "Two round wins end the match")
	await g._save_capture("combat-match-over")
	g._advance_round()
	await g._tick(4)
	check(g.wins == [0, 0] and g.round_number == 1 and g.fighters[1].health == 100, "Rematch clears score and restores fighters")
	await setup()
	g.fighters[0].health = 10
	g.fighters[1].health = 10
	Input.action_press("p1_punch")
	Input.action_press("p2_punch")
	await g._tick(15)
	release_inputs()
	check(g.fighters[0].health == 0 and g.fighters[1].health == 0 and g.wins == [0, 0] and g.result_text == "DOUBLE K.O.", "Double KO is a draw with no round win")
	await setup()
	g.fighters[0].health = 70
	g.fighters[1].health = 40
	g.round_time_ticks = 1
	await g._tick(3)
	check(g.round_state == "round_over" and g.wins == [1, 0] and g.round_time_ticks == 0, "Timeout awards higher remaining health and stops clock")
	await setup()
	g.round_time_ticks = 1
	await g._tick(3)
	check(g.wins == [0, 0] and g.result_text == "TIME UP — DRAW", "Equal-health timeout draws")
	await setup()
	g.demo = true
	var demo_timer: int = g.round_time_ticks
	await tap("p1_punch")
	await g._tick(25)
	check(g.fighters[0].state == "idle" and g.round_time_ticks == demo_timer, "Camera tour disables combat and freezes round timer")
	g.demo = false
	release_inputs()
	g.reset()
	await g._tick(5)
	await g._save_capture("combat-ready")
	var report = {"passed": g.checks, "failed": g.failures, "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "note": "Actual physics/input integration checks; not a sustained performance benchmark. Controller hardware and final character assets not tested."}
	if not g.capture_dir.is_empty():
		var file = FileAccess.open(g.capture_dir.path_join("combat-validation.json"), FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  "))
	print("COMBAT_VALIDATION " + JSON.stringify(report))
	g.get_tree().quit(0 if g.failures.is_empty() else 1)
