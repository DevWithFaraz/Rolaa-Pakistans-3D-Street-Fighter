extends Node3D

const Street = preload("res://scripts/street.gd")
const Fighter = preload("res://scripts/proxy_fighter.gd")
const RiggedFighter = preload("res://scripts/fighter_view.gd")
const CharacterDefScript = preload("res://scripts/character_def.gd")
const Hud = preload("res://scripts/proof_hud.gd")
const Feedback = preload("res://scripts/combat_feedback.gd")
const CombatValidation = preload("res://scripts/combat_validation.gd")
const CombatV2Validation = preload("res://scripts/combat_v2_validation.gd")
const InputBufferScript = preload("res://scripts/input_buffer.gd")
const CommandParserScript = preload("res://scripts/command_parser.gd")
const GraphicsPresetsScript = preload("res://scripts/graphics_presets.gd")
const PerfBenchmarkScript = preload("res://scripts/perf_benchmark.gd")
const DeterminismCheckScript = preload("res://scripts/determinism_check.gd")
const AsimDemoScript = preload("res://scripts/asim_demo.gd")
const CAMERA_LIMIT = 9.0
const MAX_SEPARATION = 10.0
const MIN_SEPARATION = 1.15
const ROUND_DURATION = 60 * 60
const ROUNDS_TO_WIN = 2
const COMBO_SCALING = [1.0, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3]
var fighters: Array[CharacterBody3D] = []
var camera: Camera3D
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var quality_preset := "medium"
var hud: Control
var paused := false
var demo := false
var demo_time := 0.0
var capture_dir := ""
var failures: Array[String] = []
var checks: Array[String] = []
var camera_extents := Vector2.ZERO
var round_state := "ready"
var round_ready_total := 75
var round_ticks := 75
var ko_winner: int = -1
var round_time_ticks := ROUND_DURATION
var round_number := 1
var wins: Array[int] = [0, 0]
var result_text := ""
var dummy_guard := false
var dummy_mode := "stand"
var event_text := ""
var event_ticks := 0
var hitstop_ticks := 0
var testing := false
var legacy_testing := false
var pending_attacks: Array[String] = ["", ""]
var pending_ticks: Array[int] = [0, 0]
var active_throw: Dictionary = {}
var rock_proj: Dictionary = {}
var bullet_proj: Dictionary = {}
var _prev_actions: Dictionary = {}
var _prev_junoon: Array[bool] = [false, false]
var _prev_attack_kind: Array[String] = ["", ""]
var _prev_states: Array[String] = ["", ""]
var _last_sky_dim := -1.0
var feedback: Node3D
var asim_demo = AsimDemoScript.new()

func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	legacy_testing = "--self-test" in user_args or "--combat-test" in user_args or "--khan-stage-test" in user_args or "--perf-bench" in user_args or "--determinism-test" in user_args
	testing = legacy_testing or "--combat-v2-test" in user_args
	if DisplayServer.get_name() != "headless" and not ("--perf-bench" in user_args):
		# Intel Iris Xe OpenGL VSync halves 60 Hz to ~30 fps even when frames render in 5 ms; DWM already composites windowed tear-free.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 60
	dummy_mode = "stand" if testing else "tekken_auto"
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
	var preset_arg := "medium"
	for argument in user_args:
		if argument.begins_with("--capture-dir="):
			capture_dir = argument.trim_prefix("--capture-dir=")
		elif argument.begins_with("--preset="):
			preset_arg = argument.trim_prefix("--preset=")
	GraphicsPresetsScript.apply(self, preset_arg)
	if "--save-resources" in user_args:
		preload("res://scripts/frame_data_tool.gd").save_default_resources()
		print("RESOURCES_SAVED")
		call_deferred("_quit_zero")
		return
	if "--self-test" in user_args:
		call_deferred("_validate")
	elif "--combat-test" in user_args:
		call_deferred("_validate_combat")
	elif "--combat-v2-test" in user_args:
		call_deferred("_validate_combat_v2")
	elif "--perf-bench" in user_args:
		call_deferred("_run_perf_benchmark")
	elif "--determinism-test" in user_args:
		call_deferred("_run_determinism_test")
	elif "--asim-demo" in user_args:
		call_deferred("toggle_asim_demo", 1)
	elif "--tour" in user_args:
		demo = true

func _add_key_action(action: String, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	if not InputMap.action_has_event(action, ev):
		InputMap.action_add_event(action, ev)

func _bind_inputs() -> void:
	var keys := {
		# P1 movement & Tekken 4-limb buttons + legacy aliases + direct attack hotkey
		"p1_left": KEY_A, "p1_right": KEY_D, "p1_jump": KEY_SPACE, "p1_up": KEY_W, "p1_down": KEY_S,
		"p1_lp": KEY_U, "p1_rp": KEY_I, "p1_lk": KEY_J, "p1_rk": KEY_K, "p1_josh": KEY_O,
		"p1_guard": KEY_V, "p1_punch": KEY_F, "p1_kick": KEY_G,
		"p1_shoot": KEY_BRACKETLEFT,
		# P2 movement & Tekken 4-limb buttons + legacy aliases + direct attack hotkey
		"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT, "p2_jump": KEY_UP, "p2_up": KEY_UP, "p2_down": KEY_DOWN,
		"p2_lp": KEY_KP_4, "p2_rp": KEY_KP_5, "p2_lk": KEY_KP_1, "p2_rk": KEY_KP_2, "p2_josh": KEY_KP_6,
		"p2_guard": KEY_KP_0, "p2_punch": KEY_KP_7, "p2_kick": KEY_KP_8,
		"p2_shoot": KEY_BRACKETRIGHT,
	}
	for action in keys:
		_add_key_action(action, keys[action])

	# Standard Xbox-style gamepad bindings per Scope §6.3
	for player in range(2):
		var p := player + 1
		for suffix in ["left", "right"]:
			var action := "p%d_%s" % [p, suffix]
			var axis := InputEventJoypadMotion.new()
			axis.device = player
			axis.axis = JOY_AXIS_LEFT_X
			axis.axis_value = -1.0 if suffix == "left" else 1.0
			if not InputMap.action_has_event(action, axis):
				InputMap.action_add_event(action, axis)
			var dpad := InputEventJoypadButton.new()
			dpad.device = player
			dpad.button_index = JOY_BUTTON_DPAD_LEFT if suffix == "left" else JOY_BUTTON_DPAD_RIGHT
			if not InputMap.action_has_event(action, dpad):
				InputMap.action_add_event(action, dpad)

		var up_axis := InputEventJoypadMotion.new()
		up_axis.device = player
		up_axis.axis = JOY_AXIS_LEFT_Y
		up_axis.axis_value = -1.0
		var up_dpad := InputEventJoypadButton.new()
		up_dpad.device = player
		up_dpad.button_index = JOY_BUTTON_DPAD_UP
		for up_action in ["p%d_jump" % p, "p%d_up" % p]:
			if not InputMap.action_has_event(up_action, up_axis):
				InputMap.action_add_event(up_action, up_axis)
			if not InputMap.action_has_event(up_action, up_dpad):
				InputMap.action_add_event(up_action, up_dpad)

		var down_axis := InputEventJoypadMotion.new()
		down_axis.device = player
		down_axis.axis = JOY_AXIS_LEFT_Y
		down_axis.axis_value = 1.0
		if not InputMap.action_has_event("p%d_down" % p, down_axis):
			InputMap.action_add_event("p%d_down" % p, down_axis)
		var down_dpad := InputEventJoypadButton.new()
		down_dpad.device = player
		down_dpad.button_index = JOY_BUTTON_DPAD_DOWN
		if not InputMap.action_has_event("p%d_down" % p, down_dpad):
			InputMap.action_add_event("p%d_down" % p, down_dpad)

		var pad_buttons := {
			"lp": JOY_BUTTON_X,
			"rp": JOY_BUTTON_Y,
			"lk": JOY_BUTTON_A,
			"rk": JOY_BUTTON_B,
			"josh": JOY_BUTTON_RIGHT_SHOULDER,
			"guard": JOY_BUTTON_LEFT_SHOULDER,
		}
		for suffix in pad_buttons:
			var btn := InputEventJoypadButton.new()
			btn.device = player
			btn.button_index = pad_buttons[suffix]
			var act := "p%d_%s" % [p, suffix]
			if not InputMap.action_has_event(act, btn):
				InputMap.action_add_event(act, btn)

func _make_environment() -> void:
	world_env = WorldEnvironment.new()
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
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.name = "AfternoonSun"
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff0db")
	sun.light_energy = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 32.0
	add_child(sun)

func reset() -> void:
	paused = false
	demo = false
	demo_time = 0.0
	if asim_demo != null:
		asim_demo.active = false
		asim_demo.banner_text = ""
	wins = [0, 0]
	round_number = 1
	_start_round()


func toggle_asim_demo(force_enable: int = -1) -> void:
	if force_enable == 1 or (force_enable == -1 and not asim_demo.active):
		asim_demo.start(self)
	else:
		asim_demo.stop(self, "LIVE FIGHT READY")

func _start_round() -> void:
	round_state = "fight" if testing else "ready"
	round_ready_total = 75 if (legacy_testing or testing) else 180
	round_ticks = round_ready_total
	ko_winner = -1
	round_time_ticks = ROUND_DURATION
	result_text = ""
	event_text = ""
	event_ticks = 0
	hitstop_ticks = 0
	pending_attacks = ["", ""]
	pending_ticks = [0, 0]
	active_throw = {}
	rock_proj = {}
	bullet_proj = {}
	_prev_actions.clear()
	_prev_junoon = [false, false]
	_prev_attack_kind = ["", ""]
	_prev_states = ["", ""]
	feedback.clear()
	for i in range(2):
		fighters[i].reset_combat()
		fighters[i].neutral_guard_enabled = (not legacy_testing and dummy_mode == "tekken_auto")
		fighters[i].position = Vector3(-3.0 if i == 0 else 3.0, 0.025, 0)
		fighters[i].velocity = Vector3(0.0, -Fighter.GRAVITY / 60.0, 0.0)
		fighters[i].move_and_slide()
		fighters[i].velocity = Vector3.ZERO
		fighters[i].facing = 1.0 if i == 0 else -1.0
		if round_state == "ready" and not demo and not testing:
			fighters[i].entry_progress = 0.0
			fighters[i]._pose(0.0)
	camera.position.x = 0.0
	camera.position.z = 13.2
	camera.fov = 39.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	_apply_super_environment()

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
		ko_winner = -1
		result_text = "TIME UP — DRAW" if timeout else "DOUBLE K.O."
		round_state = "round_over"
	else:
		ko_winner = winner if (not timeout and fighters[1 - winner].health <= 0) else -1
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
			if testing:
				dummy_guard = not dummy_guard
			else:
				var modes := ["tekken_auto", "stand", "always_guard", "crouch_guard"]
				var next_idx := (modes.find(dummy_mode) + 1) % modes.size()
				dummy_mode = modes[next_idx]
				dummy_guard = (dummy_mode == "always_guard")
				fighters[0].neutral_guard_enabled = (dummy_mode == "tekken_auto")
				fighters[1].neutral_guard_enabled = (dummy_mode == "tekken_auto")
				event_text = "DUMMY: " + dummy_mode.replace("_", " ").to_upper()
				event_ticks = 45
		KEY_M:
			feedback.muted = not feedback.muted
		KEY_H:
			hud.show_help = not hud.show_help
		KEY_F3:
			hud.show_debug = not hud.show_debug
		KEY_F4:
			sun.shadow_enabled = not sun.shadow_enabled
		KEY_F5:
			GraphicsPresetsScript.apply(self, GraphicsPresetsScript.next_preset(quality_preset))
		KEY_F6:
			for i in range(2):
				fighters[i].josh_meter = 100
				fighters[i].junoon_active = true
				_prev_junoon[i] = true
			feedback.trigger_junoon_burst(fighters[0].position, false)
			event_text = "FULL JOSH + JUNOON! PRESS O FOR JALWA"
			event_ticks = 60
		KEY_F7:
			toggle_asim_demo()

func _poll_just_pressed(actions: Array[String]) -> Dictionary:
	var just := {}
	for action in actions:
		var now_down := Input.is_action_pressed(action)
		just[action] = now_down and not bool(_prev_actions.get(action, false))
		_prev_actions[action] = now_down
	return just

func _read_player_held_mask(player: int) -> int:
	var mask := 0
	if Input.is_action_pressed("p%d_lp" % player) or Input.is_action_pressed("p%d_punch" % player):
		mask |= InputBufferScript.BTN_LP
	if Input.is_action_pressed("p%d_rp" % player):
		mask |= InputBufferScript.BTN_RP
	if Input.is_action_pressed("p%d_lk" % player):
		mask |= InputBufferScript.BTN_LK
	if Input.is_action_pressed("p%d_rk" % player) or Input.is_action_pressed("p%d_kick" % player):
		mask |= InputBufferScript.BTN_RK
	if Input.is_action_pressed("p%d_josh" % player):
		mask |= InputBufferScript.BTN_JOSH
	if Input.is_action_pressed("p%d_guard" % player):
		mask |= InputBufferScript.BTN_GUARD
	return mask

func _physics_process(delta: float) -> void:
	if paused:
		return
	var demo_active: bool = asim_demo != null and asim_demo.active
	if demo_active and hitstop_ticks > 0:
		hitstop_ticks -= 1
		return

	var axes := [Input.get_axis("p1_left", "p1_right"), Input.get_axis("p2_left", "p2_right")]
	var jumps := [false, false]
	var ups := [
		Input.is_action_pressed("p1_up") or Input.is_action_pressed("p1_jump"),
		Input.is_action_pressed("p2_up") or Input.is_action_pressed("p2_jump"),
	]
	var downs := [Input.is_action_pressed("p1_down"), Input.is_action_pressed("p2_down")]
	var demo_guards := [false, false]
	var masks := [0, 0]
	if demo_active:
		var demo_in: Dictionary = asim_demo.step_frame(self)
		if asim_demo.active:
			axes = demo_in.axes
			jumps = demo_in.jumps
			ups = demo_in.ups
			downs = demo_in.downs
			demo_guards = demo_in.guards
			masks = demo_in.masks
		else:
			demo_active = false
	if not demo_active:
		var just_pressed := _poll_just_pressed(["p1_jump", "p2_jump"])
		jumps = [bool(just_pressed.get("p1_jump", false)), bool(just_pressed.get("p2_jump", false))]
		masks = [_read_player_held_mask(1), _read_player_held_mask(2)]
	var gestures := ["", ""]

	for i in range(2):
		var up_btn: bool = bool(ups[i])
		var axis_y := (1.0 if up_btn else 0.0) - (1.0 if bool(downs[i]) else 0.0)
		var held_mask := int(masks[i])
		fighters[i].input_buffer.push_frame(axes[i], axis_y, fighters[i].facing, held_mask)
		if round_state == "fight" and not demo:
			var can_super: bool = bool(fighters[i].josh_meter >= 100) or bool(fighters[i].junoon_active)
			var cmd: String = CommandParserScript.resolve_command(fighters[i].input_buffer, can_super)
			if not cmd.is_empty():
				pending_attacks[i] = cmd
				pending_ticks[i] = 5
			gestures[i] = CommandParserScript.resolve_movement_gesture(fighters[i].input_buffer)

	if hitstop_ticks > 0:
		hitstop_ticks -= 1
		return
	feedback.step(delta)
	event_ticks = maxi(0, event_ticks - 1)
	demo_time += delta

	if not active_throw.is_empty() and round_state == "fight" and not demo:
		_step_active_throw()
		return

	if demo:
		var middle = sin(demo_time * 0.38) * 10.5
		for i in range(2):
			var goal = middle + (-2.0 if i == 0 else 2.0)
			axes[i] = clampf((goal - fighters[i].position.x) * 2.0, -1.0, 1.0)
			jumps[i] = false
			downs[i] = false
	elif round_state != "fight":
		axes = [0.0, 0.0]
		jumps = [false, false]
		downs = [false, false]
		gestures = ["", ""]

	var in_ready_entry: bool = not demo and not testing and round_state == "ready"
	var ready_prog := clampf(float(round_ready_total - round_ticks) / float(maxi(1, round_ready_total)), 0.0, 1.0) if in_ready_entry else -1.0
	_update_facing()
	for i in range(2):
		fighters[i].entry_progress = ready_prog
		var dummy_crouch: bool = (i == 1 and dummy_mode == "crouch_guard")
		var dummy_stand_guard: bool = (i == 1 and (dummy_guard or dummy_mode == "always_guard"))
		var guard: bool = not demo and round_state == "fight" and (bool(demo_guards[i]) if demo_active else (Input.is_action_pressed("p%d_guard" % [i + 1]) or dummy_stand_guard or dummy_crouch))
		var crouch_in: bool = not demo and round_state == "fight" and (bool(downs[i]) or dummy_crouch)
		var attack := ""
		if not demo and round_state == "fight" and not guard:
			if (i == 0 and Input.is_action_just_pressed("p1_shoot")) or (i == 1 and (Input.is_action_just_pressed("p2_shoot") or Input.is_action_just_pressed("p1_shoot"))):
				var fi_who := fighters[i]
				if fi_who.get("character_def") != null and fi_who.character_def.id == "asim" and fi_who._has_move("pistol_shoot"):
					attack = "pistol_shoot"
				elif fi_who.get("character_def") != null and fi_who.character_def.id == "khan" and fi_who._has_move("rock_throw"):
					attack = "rock_throw"
		if attack.is_empty() and not demo and round_state == "fight" and pending_ticks[i] > 0:
			var f := fighters[i]
			if f.state in ["idle", "crouch", "crouch_guard", "knockdown"] and not guard:
				attack = pending_attacks[i]
				pending_ticks[i] = 0
				pending_attacks[i] = ""
			elif f.state == "attack":
				attack = pending_attacks[i]
				pending_ticks[i] = 0
				pending_attacks[i] = ""
			elif f.state == "guard" and not guard:
				attack = pending_attacks[i]
				pending_ticks[i] = 0
				pending_attacks[i] = ""
			else:
				pending_ticks[i] -= 1
				if pending_ticks[i] <= 0:
					pending_attacks[i] = ""
		var fi_cur := fighters[i]
		if attack == "throw_front" and fi_cur.is_on_floor() and fi_cur.get("character_def") != null and fi_cur.character_def.id == "khan" and fi_cur._has_move("rock_throw"):
			var opp := fighters[1 - i]
			var dist := absf(opp.position.x - fi_cur.position.x)
			if dist > 1.70 or opp.state in ["crouch", "crouch_guard"] or (opp.state == "attack" and opp.attack_kind in ["crouch_jab", "low_sweep"]) or not opp.is_on_floor():
				attack = "rock_throw"
		elif attack == "throw_front" and fi_cur.is_on_floor() and fi_cur.get("character_def") != null and fi_cur.character_def.id == "asim" and fi_cur._has_move("pistol_shoot"):
			var opp := fighters[1 - i]
			var dist := absf(opp.position.x - fi_cur.position.x)
			if dist > 1.70 or opp.state in ["crouch", "crouch_guard"] or (opp.state == "attack" and opp.attack_kind in ["crouch_jab", "low_sweep"]) or not opp.is_on_floor():
				attack = "pistol_shoot"
		fighters[i].step(delta, axes[i], jumps[i], guard, attack, crouch_in, gestures[i])
		var fi := fighters[i]
		if bool(fi.junoon_active) and not _prev_junoon[i]:
			feedback.trigger_junoon_burst(fi.position, false)
			if not testing:
				event_text = "JUNOON UNLEASHED!"
				event_ticks = 36
		_prev_junoon[i] = bool(fi.junoon_active)

		var cur_atk := String(fi.attack_kind) if fi.state == "attack" else ""
		if cur_atk == "super_jalwa" and _prev_attack_kind[i] != "super_jalwa":
			feedback.trigger_junoon_burst(fi.position, true)
			if not testing:
				event_text = "JALWA!"
				event_ticks = 40
		_prev_attack_kind[i] = cur_atk

		if fi.state == "taunt" and _prev_states[i] != "taunt":
			var is_khan_taunt: bool = fi.get("character_def") != null and fi.character_def.id == "khan"
			event_text = "ABSOLUTELY NOT!" if is_khan_taunt else "SALUTE!"
			event_ticks = 60
			if fi.get("character_def") != null and feedback.has_method("play_voice_path"):
				feedback.play_voice_path(String(fi.character_def.voice_bank.get("taunt", "")))
		_prev_states[i] = String(fi.state)

		if fi.state == "attack" and fi.attack_kind == "rock_throw" and fi.get("character_def") != null and fi.character_def.id == "khan":
			if fi.attack_tick == 11:
				var pick_p: Vector3 = fi.get_right_hand_world_pos() if fi.has_method("get_right_hand_world_pos") else (fi.position + Vector3(fi.facing * 0.55, 0.08, 0.0))
				feedback.trigger_pickup_dust(Vector3(pick_p.x, 0.08, pick_p.z))
			elif fi.attack_tick == 44 and active_throw.is_empty() and rock_proj.is_empty():
				var hand_p: Vector3 = fi.get_right_hand_world_pos() if fi.has_method("get_right_hand_world_pos") else (fi.position + Vector3(fi.facing * 0.6, 2.55, 0.0))
				rock_proj = {
					"attacker": i,
					"target": 1 - i,
					"pos": Vector3(hand_p.x, maxf(2.55, hand_p.y), 0.0),
					"vel_x": fi.facing * 16.5,
					"vel_y": 0.45,
					"active": true,
					"ticks": 0,
					"direction": fi.facing,
				}
		elif fi.state == "attack" and fi.attack_kind == "pistol_shoot" and fi.get("character_def") != null and fi.character_def.id == "asim":
			if fi.attack_tick == 18 and active_throw.is_empty() and bullet_proj.is_empty():
				var muzzle_p: Vector3 = fi.get_pistol_muzzle_world_pos() if fi.has_method("get_pistol_muzzle_world_pos") else (fi.position + Vector3(fi.facing * 0.9, 2.40, 0.0))
				var spawn_pos := Vector3(muzzle_p.x, clampf(muzzle_p.y, 2.38, 2.55), muzzle_p.z)
				bullet_proj = {
					"attacker": i,
					"target": 1 - i,
					"pos": spawn_pos,
					"vel_x": fi.facing * 26.0,
					"vel_y": 0.0,
					"active": true,
					"ticks": 0,
					"direction": fi.facing,
				}
				feedback.trigger_muzzle_flash(spawn_pos, fi.facing)
				feedback.set_bullet_visual(bullet_proj)
	_resolve_spacing()
	if not demo:
		if round_state == "ready":
			round_ticks -= 1
			if round_ticks <= 0:
				round_state = "fight"
				for i in range(2):
					fighters[i].entry_progress = -1.0
				event_text = "FIGHT"
				event_ticks = 40
		elif round_state == "fight":
			_resolve_hits()
			if not rock_proj.is_empty():
				_step_rock_projectile(delta)
			if not bullet_proj.is_empty():
				_step_bullet_projectile(delta)
			round_time_ticks = maxi(0, round_time_ticks - 1)
			if not demo_active and (fighters[0].health <= 0 or fighters[1].health <= 0):
				_finish_round()
			elif not demo_active and round_time_ticks == 0:
				_finish_round(true)
		elif round_state in ["round_over", "match_over"] and ko_winner >= 0:
			var winner_f := fighters[ko_winner]
			var loser_f := fighters[1 - ko_winner]
			if loser_f.state == "ko" and int(loser_f.state_ticks) >= Fighter.KO_FALL_TICKS and winner_f.state == "idle":
				winner_f.state = "victory"
				winner_f.state_ticks = 0
				winner_f.velocity = Vector3.ZERO
				winner_f._pose(0.0)
	_track_camera(delta)

func _update_facing() -> void:
	var direction = signf(fighters[1].position.x - fighters[0].position.x)
	if direction != 0:
		for i in range(2):
			if fighters[i].state in ["idle", "guard", "crouch", "crouch_guard"]:
				fighters[i].trigger_turn(direction if i == 0 else -direction)

func _apply_super_environment() -> void:
	if feedback == null:
		return
	var dim := clampf(float(feedback.get("sky_dim_factor")), 0.0, 1.0)
	if is_equal_approx(dim, _last_sky_dim):
		return
	_last_sky_dim = dim
	if is_instance_valid(world_env) and world_env.environment != null:
		world_env.environment.ambient_light_energy = lerpf(0.65, 0.24, dim)
	if is_instance_valid(sun):
		sun.light_energy = lerpf(0.80, 0.28, dim)


func _track_camera(delta: float) -> void:
	var midpoint = (fighters[0].position.x + fighters[1].position.x) * 0.5
	var target = clampf(midpoint, -CAMERA_LIMIT, CAMERA_LIMIT)
	camera.position.x = lerpf(camera.position.x, target, 1.0 - exp(-7.0 * delta))
	if not legacy_testing:
		var dist := absf(fighters[1].position.x - fighters[0].position.x)
		var target_z := clampf(12.4 + dist * 0.22, 12.6, 14.8)
		camera.position.z = lerpf(camera.position.z, target_z, 1.0 - exp(-5.0 * delta))
		var super_active: bool = (fighters[0].state == "attack" and fighters[0].attack_kind == "super_jalwa") or (fighters[1].state == "attack" and fighters[1].attack_kind == "super_jalwa") or (feedback != null and float(feedback.get("finisher_age")) < 0.45)
		var target_fov := 30.0 if super_active else 39.0
		camera.fov = lerpf(camera.fov, target_fov, 1.0 - exp(-6.5 * delta))
		if feedback != null and feedback.has_method("get_camera_shake_offset"):
			var sh: Vector2 = feedback.get_camera_shake_offset()
			camera.h_offset = sh.x
			camera.v_offset = sh.y
		_apply_super_environment()
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
	camera_extents.x = minf(camera_extents.x, camera.position.x)
	camera_extents.y = maxf(camera_extents.y, camera.position.x)

func _step_rock_projectile(delta: float) -> void:
	var p: Vector3 = rock_proj.pos
	p.x += float(rock_proj.vel_x) * delta
	p.y += float(rock_proj.vel_y) * delta
	rock_proj.pos = p
	rock_proj.vel_y = float(rock_proj.vel_y) - 2.2 * delta
	rock_proj.ticks = int(rock_proj.ticks) + 1
	feedback.set_rock_visual(rock_proj)

	var target = fighters[int(rock_proj.target)]
	var attacker = fighters[int(rock_proj.attacker)]
	var rock_box := Rect2(Vector2(p.x - 0.18, p.y - 0.18), Vector2(0.36, 0.36))
	var hurtbox: Rect2 = target.get_hurt_box()
	var evaded: bool = target.state == "sidestep" and int(target.state_ticks) >= 5 and int(target.state_ticks) <= 17
	if target.health > 0 and not evaded and hurtbox.has_area() and rock_box.intersects(hurtbox):
		var move_stub := {"knockback": 8.5, "hitstun": 34, "blockstun": 14, "hit_level": "high", "tracking": "linear"}
		var outcome := str(target.evaluate_defense(p.x - float(rock_proj.direction) * 1.5, move_stub))
		if outcome != "whiff":
			var blocked := outcome == "blocked"
			target.receive_hit(18, float(rock_proj.direction), blocked, "rock_throw", {
				"move": move_stub,
				"hit_level": "head",
				"chip": 3 if blocked else 0,
			})
			attacker.josh_meter = mini(100, attacker.josh_meter + (4 if blocked else 12))
			hitstop_ticks = maxi(hitstop_ticks, 3 if blocked else 5)
			event_text = "BLOCKED ROCK!" if blocked else "PATTHAR HEAD HIT!"
			event_ticks = 34
			feedback.shatter_rock(p, float(rock_proj.direction))
			feedback.impact(p, blocked, "rock_throw", false)
			rock_proj.clear()
			return

	if absf(p.x) > Fighter.STAGE_LIMIT + 0.5 or p.y <= 0.1 or int(rock_proj.ticks) >= 70:
		feedback.shatter_rock(p, float(rock_proj.direction))
		rock_proj.clear()


func _step_bullet_projectile(delta: float) -> void:
	var prev_x: float = float(bullet_proj.pos.x)
	var p: Vector3 = bullet_proj.pos
	p.x += float(bullet_proj.vel_x) * delta
	p.z = move_toward(p.z, 0.0, 4.0 * delta)
	bullet_proj.pos = p
	bullet_proj.ticks = int(bullet_proj.ticks) + 1
	feedback.set_bullet_visual(bullet_proj)

	var target = fighters[int(bullet_proj.target)]
	var attacker = fighters[int(bullet_proj.attacker)]
	var swept_min_x := minf(prev_x, p.x) - 0.14
	var swept_w := absf(p.x - prev_x) + 0.28
	var bullet_box := Rect2(Vector2(swept_min_x, p.y - 0.10), Vector2(swept_w, 0.20))
	var hurtbox: Rect2 = target.get_hurt_box()
	var evaded: bool = target.state == "sidestep" and int(target.state_ticks) >= 5 and int(target.state_ticks) <= 17
	if target.health > 0 and not evaded and hurtbox.has_area() and bullet_box.intersects(hurtbox):
		var move_stub := {"knockback": 7.0, "hitstun": 28, "blockstun": 14, "hit_level": "high", "tracking": "linear"}
		var outcome := str(target.evaluate_defense(p.x - float(bullet_proj.direction) * 1.5, move_stub))
		if outcome != "whiff":
			var blocked := outcome == "blocked"
			target.receive_hit(16, float(bullet_proj.direction), blocked, "pistol_shoot", {
				"move": move_stub,
				"hit_level": "body",
				"chip": 3 if blocked else 0,
			})
			attacker.josh_meter = mini(100, attacker.josh_meter + (4 if blocked else 11))
			hitstop_ticks = maxi(hitstop_ticks, 3 if blocked else 4)
			event_text = "BLOCKED SHOT!" if blocked else "PISTOL HIT!"
			event_ticks = 32
			feedback.bullet_impact(Vector3(target.position.x - float(bullet_proj.direction) * 0.28, p.y, 0.0), blocked, float(bullet_proj.direction))
			bullet_proj.clear()
			return

	if absf(p.x) > Fighter.STAGE_LIMIT + 0.5 or int(bullet_proj.ticks) >= 50:
		bullet_proj.clear()
		feedback.set_bullet_visual(bullet_proj)

func _step_active_throw() -> void:
	var att_idx := int(active_throw.attacker)
	var def_idx := int(active_throw.defender)
	var att := fighters[att_idx]
	var def := fighters[def_idx]
	var hist: Array[Dictionary] = def.input_buffer.history
	var def_pressed := int(hist[hist.size() - 1].pressed) if not hist.is_empty() else 0
	var tech_mask: int = InputBufferScript.BTN_LP | InputBufferScript.BTN_RP | InputBufferScript.BTN_LK | InputBufferScript.BTN_RK
	if (def_pressed & tech_mask) != 0:
		var dir := float(active_throw.direction)
		att.state = "thrown_tech"
		att.state_ticks = 6
		att.attack_kind = ""
		att.velocity.x = -dir * 4.5
		def.state = "thrown_tech"
		def.state_ticks = 6
		def.velocity.x = dir * 4.5
		event_text = "CHHURAAO! THROW BREAK"
		event_ticks = 36
		feedback.impact((att.position + def.position) * 0.5 + Vector3(0, 1.8, 0.48), true, "block")
		active_throw.clear()
		return

	active_throw.ticks_left = int(active_throw.ticks_left) - 1
	if int(active_throw.ticks_left) <= 0:
		var dir := float(active_throw.direction)
		var dmg := int(active_throw.damage)
		var move: Dictionary = active_throw.move
		att.state = "idle"
		att.attack_kind = ""
		def.receive_hit(dmg, dir, false, "throw_front", {"move": move, "scale": 1.0, "hit_level": "head"})
		att.josh_meter = mini(100, att.josh_meter + 14)
		hitstop_ticks = int(move.get("hitstop", 6))
		event_text = "PAKAD THROW!"
		event_ticks = 32
		feedback.impact(def.position + Vector3(0, 2.4, 0.48), false, "throw_front")
		active_throw.clear()
		if fighters[0].health <= 0 or fighters[1].health <= 0:
			_finish_round()

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
			var move: Dictionary = attacker.attack_data().duplicate()
			var outcome: String = str(defender.evaluate_defense(attacker.position.x, move))
			if outcome == "whiff":
				continue
			contacts.append({
				"attacker": i,
				"outcome": outcome,
				"blocked": outcome == "blocked",
				"direction": attacker.facing,
				"kind": attacker.attack_kind,
				"data": move,
				"point": hitbox.intersection(hurtbox).get_center(),
			})

	for contact in contacts:
		fighters[contact.attacker].mark_connected()

	for contact in contacts:
		var attacker = fighters[contact.attacker]
		var target = fighters[1 - contact.attacker]
		if contact.outcome == "throw":
			if contacts.size() == 1:
				attacker.state = "throw_hold"
				attacker.state_ticks = 14
				attacker.velocity.x = 0.0
				target.state = "thrown_tech"
				target.state_ticks = 14
				target.velocity.x = 0.0
				active_throw = {
					"attacker": contact.attacker,
					"defender": 1 - contact.attacker,
					"ticks_left": 14,
					"damage": int(contact.data.damage),
					"direction": contact.direction,
					"move": contact.data,
				}
				event_text = "THROW!"
				event_ticks = 14
			continue

		var blocked: bool = bool(contact.blocked)
		var is_counter: bool = (not blocked) and target.state == "attack" and int(target.attack_tick) < int(target.attack_data().startup)
		var base_dmg: int = int(contact.data.damage)
		if not blocked:
			var mult: float = (1.2 if is_counter else 1.0) * (1.15 if bool(attacker.junoon_active) else 1.0)
			base_dmg = int(round(float(base_dmg) * mult))

		var combo_idx: int = mini(int(target.combo_hits), COMBO_SCALING.size() - 1)
		var scale: float = COMBO_SCALING[combo_idx]
		var at_wall: bool = absf(target.position.x) >= Fighter.STAGE_LIMIT - 0.5 and (target.position.x * float(contact.direction)) > 0.0
		var is_wall_splat: bool = (not blocked) and bool(contact.data.get("wall_splat", false)) and at_wall and not bool(target.wall_splatted_in_combo)
		var chip: int = int(contact.data.get("chip_damage", 0)) if blocked else 0

		target.receive_hit(base_dmg, contact.direction, blocked, contact.kind, {
			"move": contact.data,
			"is_counter": is_counter,
			"is_wall_splat": is_wall_splat,
			"scale": scale,
			"chip": chip,
		})

		var attacker_rem := maxi(0, attacker.state_ticks)
		attacker.last_frame_advantage = target.state_ticks - attacker_rem
		target.last_frame_advantage = -attacker.last_frame_advantage
		if contact.kind != "super_jalwa":
			attacker.josh_meter = mini(100, attacker.josh_meter + (5 if blocked else 12))

		hitstop_ticks = maxi(hitstop_ticks, 3 if blocked else int(contact.data.hitstop))
		if blocked:
			event_text = "BLOCK"
		elif is_wall_splat:
			event_text = "WALL SPLAT!"
		elif is_counter:
			event_text = "COUNTER — ULTA PAD GAYA!"
		elif contact.kind == "super_jalwa":
			event_text = "JALWA!"
		else:
			event_text = contact.kind.replace("_", " ").to_upper() + " HIT"
		event_ticks = 30
		feedback.impact(Vector3(contact.point.x, contact.point.y, 0.48), blocked, contact.kind, is_counter)
		if contact.kind == "super_jalwa" and feedback.has_method("trigger_super_finisher"):
			feedback.trigger_super_finisher(attacker.position, target.position, contact.direction, blocked)

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

func _validate_combat_v2() -> void:
	var suite = CombatV2Validation.new()
	await suite.run(self)

func snapshot_match() -> Dictionary:
	return {
		"round_state": round_state,
		"round_ready_total": round_ready_total,
		"round_ticks": round_ticks,
		"ko_winner": ko_winner,
		"round_time_ticks": round_time_ticks,
		"round_number": round_number,
		"wins": wins.duplicate(),
		"result_text": result_text,
		"dummy_guard": dummy_guard,
		"dummy_mode": dummy_mode,
		"event_text": event_text,
		"event_ticks": event_ticks,
		"hitstop_ticks": hitstop_ticks,
		"pending_attacks": pending_attacks.duplicate(),
		"pending_ticks": pending_ticks.duplicate(),
		"active_throw": active_throw.duplicate(true),
		"rock_proj": rock_proj.duplicate(true),
		"bullet_proj": bullet_proj.duplicate(true),
		"prev_actions": _prev_actions.duplicate(),
		"prev_junoon": _prev_junoon.duplicate(),
		"prev_attack_kind": _prev_attack_kind.duplicate(),
		"prev_states": _prev_states.duplicate(),
		"camera_x": camera.position.x,
		"camera_z": camera.position.z,
		"camera_fov": camera.fov,
		"fighters": [fighters[0].snapshot_state(), fighters[1].snapshot_state()],
	}

func restore_match(snap: Dictionary) -> void:
	round_state = String(snap.round_state)
	round_ready_total = int(snap.get("round_ready_total", 75))
	round_ticks = int(snap.round_ticks)
	ko_winner = int(snap.get("ko_winner", -1))
	round_time_ticks = int(snap.round_time_ticks)
	round_number = int(snap.round_number)
	wins = [int(snap.wins[0]), int(snap.wins[1])]
	result_text = String(snap.result_text)
	dummy_guard = bool(snap.dummy_guard)
	dummy_mode = String(snap.get("dummy_mode", "stand"))
	event_text = String(snap.event_text)
	event_ticks = int(snap.event_ticks)
	hitstop_ticks = int(snap.hitstop_ticks)
	pending_attacks = [String(snap.pending_attacks[0]), String(snap.pending_attacks[1])]
	pending_ticks = [int(snap.pending_ticks[0]), int(snap.pending_ticks[1])]
	active_throw = snap.get("active_throw", {}).duplicate(true)
	rock_proj = snap.get("rock_proj", {}).duplicate(true)
	bullet_proj = snap.get("bullet_proj", {}).duplicate(true)
	_prev_actions = snap.get("prev_actions", {}).duplicate()
	var pj: Array = snap.get("prev_junoon", [false, false])
	_prev_junoon = [bool(pj[0]), bool(pj[1])]
	var pa: Array = snap.get("prev_attack_kind", ["", ""])
	_prev_attack_kind = [String(pa[0]), String(pa[1])]
	var ps: Array = snap.get("prev_states", ["", ""])
	_prev_states = [String(ps[0]), String(ps[1])]
	camera.position.x = float(snap.camera_x)
	camera.position.z = float(snap.get("camera_z", 13.2))
	camera.fov = float(snap.get("camera_fov", 39.0))
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	feedback.clear()
	_last_sky_dim = -1.0
	_apply_super_environment()
	feedback.set_rock_visual(rock_proj)
	feedback.set_bullet_visual(bullet_proj)
	for i in range(2):
		fighters[i].restore_state(snap.fighters[i])

func _run_perf_benchmark() -> void:
	var out_path := capture_dir.path_join("perf-bench.json") if not capture_dir.is_empty() else ""
	var cap_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bench-out="):
			out_path = arg.trim_prefix("--bench-out=")
		elif arg.begins_with("--bench-capture="):
			cap_path = arg.trim_prefix("--bench-capture=")
	var bench = PerfBenchmarkScript.new()
	await bench.run(self, out_path, cap_path)

func _run_determinism_test() -> void:
	var suite = DeterminismCheckScript.new()
	await suite.run(self)

func _quit_zero() -> void:
	get_tree().quit(0)
