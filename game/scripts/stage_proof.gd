extends Node3D

const Street = preload("res://scripts/street.gd")
const Fighter = preload("res://scripts/proxy_fighter.gd")
const RiggedFighter = preload("res://scripts/fighter_view.gd")
const CharacterDefScript = preload("res://scripts/character_def.gd")
const Hud = preload("res://scripts/proof_hud.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
const CombatValidation = preload("res://scripts/combat_validation.gd")
const CAMERA_LIMIT = 9.0
const MAX_SEPARATION = 10.0
const MIN_SEPARATION = 1.15
const ROUND_DURATION = 60 * 60
const ROUNDS_TO_WIN = 2
var fighters: Array[CharacterBody3D] = []
var camera: Camera3D
var sun: DirectionalLight3D
var hud: Control
var paused := false
var demo := false
var demo_time := 0.0
var capture_dir := ""
var failures: Array[String] = []
var checks: Array[String] = []
var camera_extents := Vector2.ZERO
var round_state := "ready"
var round_ticks := 75
var round_time_ticks := ROUND_DURATION
var round_number := 1
var wins: Array[int] = [0, 0]
var result_text := ""
var dummy_guard := false
var event_text := ""
var event_ticks := 0
var hitstop_ticks := 0
var testing := false
var pending_attacks: Array[String] = ["", ""]
var pending_ticks: Array[int] = [0, 0]
var feedback: Node3D

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	testing = "--self-test" in user_args or "--combat-test" in user_args or "--khan-stage-test" in user_args
	var use_proxies := "--proxy-fighters" in user_args
	_bind_inputs()
	_make_environment()
	add_child(Street.new())
	if use_proxies:
		for i in range(2):
			var fighter = Fighter.new()
			fighter.name = "KhanProxy" if i == 0 else "AsimProxy"
			fighter.costume = i
			add_child(fighter)
			fighters.append(fighter)
	else:
		var configs := [
			{"id": "khan", "name": "KhanSahab", "costume": 0},
			{"id": "asim", "name": "AsimJani", "costume": 1},
		]
		for cfg in configs:
			var fighter := RiggedFighter.new()
			fighter.name = cfg.name
			fighter.costume = cfg.costume
			fighter.character_def = CharacterDefScript.load_or_default(cfg.id)
			add_child(fighter)
			fighters.append(fighter)
	camera = Camera3D.new()
	camera.name = "TrackingCamera"
	camera.fov = 39.0
	camera.near = 0.1
	camera.far = 100.0
	camera.position = Vector3(0, 4.8, 13.2)
	add_child(camera)
	camera.look_at(Vector3(0, 2.0, 0))
	camera.current = true
	var ui = CanvasLayer.new()
	hud = Hud.new()
	hud.proof = self
	ui.add_child(hud)
	add_child(ui)
	feedback = Feedback.new()
	add_child(feedback)
	reset()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("_validate")
	elif "--combat-test" in OS.get_cmdline_user_args():
		call_deferred("_validate_combat")
	elif "--tour" in OS.get_cmdline_user_args():
		demo = true

func _bind_inputs() -> void:
	var keys = {"p1_left": KEY_A, "p1_right": KEY_D, "p1_jump": KEY_W, "p1_guard": KEY_S, "p1_punch": KEY_F, "p1_kick": KEY_G, "p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_jump": KEY_UP, "p2_guard": KEY_DOWN, "p2_punch": KEY_J, "p2_kick": KEY_K}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event = InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	# Standard joypad layout: left stick/D-pad and bottom face button to jump.
	for player in range(2):
		for suffix in ["left", "right"]:
			var action = "p%d_%s" % [player + 1, suffix]
			var axis = InputEventJoypadMotion.new()
			axis.device = player
			axis.axis = JOY_AXIS_LEFT_X
			axis.axis_value = -1.0 if suffix == "left" else 1.0
			InputMap.action_add_event(action, axis)
			var button = InputEventJoypadButton.new()
			button.device = player
			button.button_index = JOY_BUTTON_DPAD_LEFT if suffix == "left" else JOY_BUTTON_DPAD_RIGHT
			InputMap.action_add_event(action, button)
		var jump = InputEventJoypadButton.new()
		jump.device = player
		jump.button_index = JOY_BUTTON_A
		InputMap.action_add_event("p%d_jump" % [player + 1], jump)
		for suffix in ["punch", "kick", "guard"]:
			var combat_button = InputEventJoypadButton.new()
			combat_button.device = player
			combat_button.button_index = {"punch": JOY_BUTTON_X, "kick": JOY_BUTTON_Y, "guard": JOY_BUTTON_RIGHT_SHOULDER}[suffix]
			InputMap.action_add_event("p%d_%s" % [player + 1, suffix], combat_button)

func _make_environment() -> void:
	var world = WorldEnvironment.new()
	var env = Environment.new()
	var sky = Sky.new()
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("7da5ae")
	sky_material.sky_horizon_color = Color("edd5ac")
	sky_material.ground_bottom_color = Color("7a7664")
	sky_material.ground_horizon_color = Color("edd5ac")
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d5d8c5")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.environment = env
	add_child(world)
	sun = DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff0db")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 38.0
	add_child(sun)

func reset() -> void:
	paused = false
	demo = false
	demo_time = 0.0
	wins = [0, 0]
	round_number = 1
	_start_round()

func _start_round() -> void:
	round_state = "fight" if testing else "ready"
	round_ticks = 75
	round_time_ticks = ROUND_DURATION
	result_text = ""
	event_text = ""
	event_ticks = 0
	hitstop_ticks = 0
	pending_attacks = ["", ""]
	pending_ticks = [0, 0]
	feedback.clear()
	for i in range(2):
		fighters[i].reset_combat()
		fighters[i].position = Vector3(-3.0 if i == 0 else 3.0, 0.025, 0)
		fighters[i].velocity = Vector3.ZERO
		fighters[i].facing = 1.0 if i == 0 else -1.0
	camera.position.x = 0.0

func _advance_round() -> void:
	if round_state == "match_over":
		reset()
	elif round_state == "round_over":
		round_number += 1
		_start_round()

func _finish_round(timeout: bool = false) -> void:
	if round_state != "fight":
		return
	var winner := -1
	if fighters[0].health > fighters[1].health:
		winner = 0
	elif fighters[1].health > fighters[0].health:
		winner = 1
	if winner < 0:
		result_text = "TIME UP — DRAW" if timeout else "DOUBLE K.O."
		round_state = "round_over"
	else:
		wins[winner] += 1
		var who: String = fighters[winner].get_display_name()
		round_state = "match_over" if wins[winner] >= ROUNDS_TO_WIN else "round_over"
		result_text = who + (" WINS THE MATCH" if round_state == "match_over" else " WINS ROUND")
		if timeout:
			result_text = "TIME UP / " + result_text
	pending_attacks = ["", ""]
	pending_ticks = [0, 0]
	feedback.play_cue("round")

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			paused = not paused
		KEY_R:
			reset()
		KEY_ENTER, KEY_KP_ENTER:
			if not paused and not demo:
				_advance_round()
		KEY_F2:
			var enable_tour = not demo
			reset()
			demo = enable_tour
		KEY_T:
			dummy_guard = not dummy_guard
		KEY_M:
			feedback.muted = not feedback.muted
		KEY_H:
			hud.show_help = not hud.show_help
		KEY_F3:
			hud.show_debug = not hud.show_debug
		KEY_F4:
			sun.shadow_enabled = not sun.shadow_enabled

func _physics_process(delta: float) -> void:
	if paused:
		return
	# Save short taps during hitstop; expire the buffer on simulation ticks.
	if round_state == "fight" and not demo:
		for i in range(2):
			for kind in ["punch", "kick"]:
				if Input.is_action_just_pressed("p%d_%s" % [i + 1, kind]):
					pending_attacks[i] = kind
					pending_ticks[i] = 5
	if hitstop_ticks > 0:
		hitstop_ticks -= 1
		return
	feedback.step(delta)
	event_ticks = maxi(0, event_ticks - 1)
	demo_time += delta
	var axes = [Input.get_axis("p1_left", "p1_right"), Input.get_axis("p2_left", "p2_right")]
	var jumps = [Input.is_action_just_pressed("p1_jump"), Input.is_action_just_pressed("p2_jump")]
	if demo:
		var middle = sin(demo_time * 0.38) * 10.5
		for i in range(2):
			var goal = middle + (-2.0 if i == 0 else 2.0)
			axes[i] = clampf((goal - fighters[i].position.x) * 2.0, -1.0, 1.0)
			jumps[i] = false
	elif round_state != "fight":
		axes = [0.0, 0.0]
		jumps = [false, false]
	_update_facing()
	for i in range(2):
		var guard = not demo and round_state == "fight" and (Input.is_action_pressed("p%d_guard" % [i + 1]) or (i == 1 and dummy_guard))
		var attack = ""
		if not demo and round_state == "fight" and pending_ticks[i] > 0:
			if fighters[i].state in ["idle", "guard"] and fighters[i].is_on_floor() and not guard:
				attack = pending_attacks[i]
				pending_ticks[i] = 0
			else:
				pending_ticks[i] -= 1
		fighters[i].step(delta, axes[i], jumps[i], guard, attack)
	_resolve_spacing()
	if not demo:
		if round_state == "ready":
			round_ticks -= 1
			if round_ticks <= 0:
				round_state = "fight"
				event_text = "FIGHT"
				event_ticks = 40
		elif round_state == "fight":
			_resolve_hits()
			round_time_ticks = maxi(0, round_time_ticks - 1)
			if fighters[0].health <= 0 or fighters[1].health <= 0:
				_finish_round()
			elif round_time_ticks == 0:
				_finish_round(true)
	_track_camera(delta)

func _update_facing() -> void:
	var direction = signf(fighters[1].position.x - fighters[0].position.x)
	if direction != 0:
		for i in range(2):
			if fighters[i].state in ["idle", "guard"]:
				fighters[i].facing = direction if i == 0 else -direction

func _track_camera(delta: float) -> void:
	var midpoint = (fighters[0].position.x + fighters[1].position.x) * 0.5
	var target = clampf(midpoint, -CAMERA_LIMIT, CAMERA_LIMIT)
	camera.position.x = lerpf(camera.position.x, target, 1.0 - exp(-7.0 * delta))
	camera_extents.x = minf(camera_extents.x, camera.position.x)
	camera_extents.y = maxf(camera_extents.y, camera.position.x)

func _resolve_hits() -> void:
	# Snapshot both contacts first so a simultaneous hit can trade fairly.
	var contacts: Array[Dictionary] = []
	for i in range(2):
		var attacker = fighters[i]
		var defender = fighters[1 - i]
		var hitbox: Rect2 = attacker.get_attack_box()
		if attacker.health <= 0 or defender.health <= 0 or not hitbox.has_area():
			continue
		var hurtbox: Rect2 = defender.get_hurt_box()
		if hitbox.intersects(hurtbox):
			contacts.append({"attacker": i, "blocked": defender.can_block(attacker.position.x), "direction": attacker.facing, "kind": attacker.attack_kind, "data": attacker.attack_data().duplicate(), "point": hitbox.intersection(hurtbox).get_center()})
	for contact in contacts:
		fighters[contact.attacker].mark_connected()
	for contact in contacts:
		var target = fighters[1 - contact.attacker]
		target.receive_hit(contact.data.damage, contact.direction, contact.blocked, contact.kind)
		hitstop_ticks = maxi(hitstop_ticks, 3 if contact.blocked else int(contact.data.hitstop))
		event_text = "BLOCK" if contact.blocked else contact.kind.to_upper() + " HIT"
		event_ticks = 28
		feedback.impact(Vector3(contact.point.x, contact.point.y, 0.48), contact.blocked, contact.kind)
	if contacts.size() == 2:
		event_text = "TRADE"

func _resolve_spacing() -> void:
	var separation = fighters[1].position.x - fighters[0].position.x
	var direction = 1.0 if separation >= 0 else -1.0
	var center = (fighters[0].position.x + fighters[1].position.x) * 0.5
	var distance = absf(separation)
	if distance > MAX_SEPARATION:
		fighters[0].position.x = center - direction * MAX_SEPARATION * 0.5
		fighters[1].position.x = center + direction * MAX_SEPARATION * 0.5
	elif distance < MIN_SEPARATION and absf(fighters[0].position.y - fighters[1].position.y) < 1.05:
		# Preserve contact separation even when the pair reaches a stage edge.
		center = clampf(center, -Fighter.STAGE_LIMIT + MIN_SEPARATION * 0.5, Fighter.STAGE_LIMIT - MIN_SEPARATION * 0.5)
		fighters[0].position.x = center - direction * MIN_SEPARATION * 0.5
		fighters[1].position.x = center + direction * MIN_SEPARATION * 0.5

func _tick(count: int) -> void:
	for i in range(count):
		await get_tree().physics_frame

func _check(ok: bool, message: String) -> void:
	if ok:
		checks.append(message)
	else:
		failures.append(message)
		push_error("VALIDATION: " + message)

func _save_capture(filename: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var error = get_viewport().get_texture().get_image().save_png(capture_dir.path_join(filename + ".png"))
	_check(error == OK, "Screenshot saved: " + filename)

func _visible_fighters() -> bool:
	var viewport_size = get_viewport().get_visible_rect().size
	for fighter in fighters:
		for height in [0.1, 3.6]:
			var point = fighter.position + Vector3(0, height, 0)
			if camera.is_position_behind(point):
				return false
			var screen = camera.unproject_position(point)
			if screen.x < 20 or screen.x > viewport_size.x - 20 or screen.y < 110 or screen.y > viewport_size.y - 100:
				return false
	return true

func _validate() -> void:
	await _tick(20)
	_check(fighters[0].is_on_floor() and fighters[1].is_on_floor(), "Both fighters stand on real road collision")
	_check(_visible_fighters(), "Both fighters framed at spawn")
	await _save_capture("stage-center")
	var initial_rotation = camera.rotation
	Input.action_press("p1_left")
	Input.action_press("p2_left")
	await _tick(240)
	Input.action_release("p1_left")
	Input.action_release("p2_left")
	await _tick(25)
	_check(camera.position.x < -8.9, "Camera tracks to left bound")
	_check(fighters[0].position.x >= -14.01 and fighters[1].position.x >= -14.01, "Left stage boundary holds")
	_check(_visible_fighters(), "Both fighters framed at left edge")
	await _save_capture("stage-left")
	Input.action_press("p1_right")
	Input.action_press("p2_right")
	await _tick(410)
	Input.action_release("p1_right")
	Input.action_release("p2_right")
	await _tick(25)
	_check(camera.position.x > 8.9, "Camera tracks to right bound")
	_check(fighters[0].position.x <= 14.01 and fighters[1].position.x <= 14.01, "Right stage boundary holds")
	_check(_visible_fighters(), "Both fighters framed at right edge")
	_check(camera.rotation.is_equal_approx(initial_rotation), "Tracking preserves the chosen camera angle")
	await _save_capture("stage-right")
	reset()
	await _tick(10)
	Input.action_press("p1_jump")
	await _tick(1)
	Input.action_release("p1_jump")
	await _tick(20)
	_check(fighters[0].position.y > 0.9, "Jump leaves the ground")
	_check(_visible_fighters(), "Jump remains in frame")
	await _save_capture("stage-jump")
	await _tick(50)
	_check(fighters[0].is_on_floor(), "Jump lands back on road")
	paused = true
	var paused_x = fighters[0].position.x
	Input.action_press("p1_right")
	await _tick(15)
	Input.action_release("p1_right")
	_check(is_equal_approx(fighters[0].position.x, paused_x), "Pause freezes movement")
	reset()
	await _tick(10)
	Input.action_press("p1_left")
	Input.action_press("p2_right")
	await _tick(150)
	Input.action_release("p1_left")
	Input.action_release("p2_right")
	await _tick(15)
	_check(absf(fighters[1].position.x - fighters[0].position.x) <= MAX_SEPARATION + 0.01, "Maximum spacing keeps both fighters on screen")
	_check(_visible_fighters(), "Maximum separation fits camera")
	_check(absf(fighters[0].position.z) < 0.001 and absf(fighters[1].position.z) < 0.001, "Movement stays on the fighting plane")
	reset()
	await _tick(10)
	_check(absf(fighters[0].position.x + 3.0) < 0.01 and absf(fighters[1].position.x - 3.0) < 0.01, "Reset restores start positions")
	var report = {"passed": checks, "failed": failures, "camera_min_x": camera_extents.x, "camera_max_x": camera_extents.y, "renderer": RenderingServer.get_current_rendering_method(), "engine": Engine.get_version_info().string, "note": "Integration checks; not a performance benchmark."}
	if not capture_dir.is_empty():
		var file = FileAccess.open(capture_dir.path_join("validation.json"), FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(report, "  "))
	print("STAGE_PROOF_VALIDATION " + JSON.stringify(report))
	get_tree().quit(0 if failures.is_empty() else 1)

func _validate_combat() -> void:
	var suite = CombatValidation.new()
	await suite.run(self)
