extends CharacterBody3D
## Deliberately abstract costume proxies. Final likenesses and rigs come later.

const InputBufferScript = preload("res://scripts/input_buffer.gd")
const SPEED = 4.8
const GRAVITY = 23.0
const JUMP_SPEED = 8.0
const STAGE_LIMIT = 14.0
const TURN_TICKS = 24
const KNOCKDOWN_TICKS = 76
const WAKEUP_STAND_TICKS = 72
const KO_FALL_TICKS = 108
const MOVES = {
	"punch": {"startup": 6, "active": 3, "recovery": 14, "damage": 10, "reach": 1.8, "knockback": 4.5, "hitstun": 18, "blockstun": 12, "hitstop": 5, "low": 1.95, "height": 0.8, "hit_level": "high", "tracking": "linear", "cancel_routes": {"rp": "heavy_punch", "lp": "light_combo"}},
	"light_combo": {"startup": 5, "active": 3, "recovery": 14, "damage": 8, "reach": 1.85, "knockback": 4.0, "hitstun": 18, "blockstun": 12, "hitstop": 5, "low": 1.95, "height": 0.8, "hit_level": "high", "tracking": "linear", "cancel_routes": {"rp": "heavy_punch"}},
	"heavy_punch": {"startup": 13, "active": 4, "recovery": 25, "damage": 14, "reach": 1.95, "knockback": 4.2, "hitstun": 21, "blockstun": 14, "hitstop": 6, "low": 1.75, "height": 0.9, "hit_level": "mid", "tracking": "linear", "advance_speed": 1.4, "cancel_routes": {"rk": "kick"}},
	"quick_kick": {"startup": 10, "active": 3, "recovery": 18, "damage": 11, "reach": 2.05, "knockback": 3.8, "hitstun": 19, "blockstun": 13, "hitstop": 5, "low": 0.35, "height": 0.75, "hit_level": "low", "tracking": "linear"},
	"kick": {"startup": 12, "active": 4, "recovery": 22, "damage": 17, "reach": 2.4, "knockback": 6.0, "hitstun": 25, "blockstun": 17, "hitstop": 7, "low": 1.15, "height": 0.95, "hit_level": "mid", "tracking": "linear"},
	"crouch_jab": {"startup": 7, "active": 3, "recovery": 13, "damage": 8, "reach": 1.75, "knockback": 3.2, "hitstun": 16, "blockstun": 11, "hitstop": 4, "low": 1.0, "height": 0.75, "hit_level": "mid", "tracking": "linear"},
	"low_sweep": {"startup": 18, "active": 5, "recovery": 32, "damage": 16, "reach": 2.25, "knockback": 4.5, "hitstun": 30, "blockstun": 22, "hitstop": 7, "low": 0.25, "height": 0.75, "hit_level": "low", "tracking": "linear", "knockdown": true},
	"launcher": {"startup": 18, "active": 5, "recovery": 32, "damage": 15, "reach": 2.10, "knockback": 2.2, "hitstun": 38, "blockstun": 16, "hitstop": 8, "low": 1.2, "height": 1.25, "hit_level": "mid", "tracking": "linear", "launcher": true, "launch_velocity": Vector2(2.2, 8.8), "advance_speed": 1.4},
	"command_heavy": {"startup": 14, "active": 4, "recovery": 20, "damage": 20, "reach": 2.1, "knockback": 8.2, "hitstun": 27, "blockstun": 16, "hitstop": 8, "low": 1.5, "height": 1.0, "hit_level": "mid", "tracking": "homing", "wall_splat": true, "advance_speed": 3.5},
	"power_kick": {"startup": 15, "active": 5, "recovery": 24, "damage": 22, "reach": 2.55, "knockback": 9.5, "hitstun": 29, "blockstun": 18, "hitstop": 9, "low": 1.2, "height": 1.05, "hit_level": "mid", "tracking": "homing", "wall_splat": true},
	"throw_front": {"startup": 10, "active": 3, "recovery": 22, "damage": 22, "reach": 1.55, "knockback": 7.0, "hitstun": 30, "blockstun": 0, "hitstop": 6, "low": 1.0, "height": 1.5, "hit_level": "throw", "tracking": "linear", "knockdown": true},
	"rock_throw": {"startup": 44, "active": 4, "recovery": 32, "damage": 18, "reach": 10.0, "knockback": 8.5, "hitstun": 34, "blockstun": 14, "hitstop": 5, "low": 1.6, "height": 1.2, "hit_level": "high", "tracking": "linear"},
	"pistol_shoot": {"startup": 18, "active": 4, "recovery": 30, "damage": 16, "reach": 12.0, "knockback": 7.0, "hitstun": 28, "blockstun": 14, "hitstop": 4, "low": 1.65, "height": 1.0, "hit_level": "high", "tracking": "linear", "chip_damage": 3},
	"air_punch": {"startup": 7, "active": 6, "recovery": 14, "damage": 13, "reach": 2.15, "knockback": 4.2, "hitstun": 24, "blockstun": 14, "hitstop": 6, "low": 0.45, "height": 1.25, "hit_level": "mid", "tracking": "linear"},
	"air_kick": {"startup": 9, "active": 7, "recovery": 16, "damage": 16, "reach": 2.45, "knockback": 7.2, "hitstun": 28, "blockstun": 16, "hitstop": 8, "low": 0.25, "height": 1.20, "hit_level": "mid", "tracking": "linear", "knockdown": true},
	"signature": {"startup": 20, "active": 6, "recovery": 32, "damage": 24, "reach": 2.35, "knockback": 9.2, "hitstun": 32, "blockstun": 18, "hitstop": 9, "low": 1.3, "height": 1.1, "hit_level": "mid", "tracking": "linear", "knockdown": true, "wall_splat": true, "advance_speed": 3.0},
	"super_jalwa": {"startup": 11, "active": 6, "recovery": 26, "damage": 34, "reach": 2.65, "knockback": 11.0, "hitstun": 40, "blockstun": 20, "hitstop": 12, "low": 1.0, "height": 1.4, "hit_level": "mid", "tracking": "homing", "knockdown": true, "wall_splat": true, "chip_damage": 8, "josh_cost": 100, "advance_speed": 5.0},
}
var costume := 0
var facing := 1.0
var health: int = 100
var state: String = "idle"
## Remaining ticks for attacks/stun; elapsed ticks for the KO fall.
var state_ticks: int = 0
var attack_kind: String = ""
## Zero-based age: punch is active at 6–8, kick at 12–15.
var attack_tick: int = 0
var attack_connected: bool = false
var josh_meter: int = 0
var junoon_used: bool = false
var junoon_active: bool = false
var crouching: bool = false
var walking_back: bool = false
var neutral_guard_enabled: bool = false
var _explicit_guard: bool = false
var air_ticks: int = 0
var air_attack_used: bool = false
var sidestep_dir: float = 0.0
var sidestep_z: float = 0.0
var combo_hits: int = 0
var combo_damage: int = 0
var wall_splatted_in_combo: bool = false
var armour_remaining: int = 0
var buffered_cancel: String = ""
var last_frame_advantage: int = 0
var last_hit_level: String = "mid"
var state_total_ticks: int = 0
var entry_progress: float = -1.0
var turn_ticks: int = 0
var turn_from_facing: float = 1.0
var pending_turn_from: float = 0.0
var input_buffer = InputBufferScript.new()
var visual: Node3D
var limbs: Array[MeshInstance3D] = []
var gait := 0.0
var time := 0.0
var cloth: StandardMaterial3D
var skin: StandardMaterial3D
var cloth_color: Color
var skin_color := Color("c99a77")
var flash_ticks := 0
var flash_color := Color.WHITE

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape = CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 3.15
	var collider = CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 1.575
	add_child(collider)
	visual = Node3D.new()
	add_child(visual)
	cloth_color = Color("eee2c6") if costume == 0 else Color("9b9c72")
	cloth = _material(cloth_color)
	skin = _material(skin_color)
	var dark = _material(Color("29383b"))
	var gold = _material(Color("d9ad55"))
	var torso = CapsuleMesh.new()
	torso.radius = 0.47
	torso.height = 1.32
	_make(torso, Vector3(0, 2.02, 0), Vector3(0.92, 1, 0.69), cloth)
	if costume == 0:
		var tunic = CylinderMesh.new()
		tunic.top_radius = 0.38
		tunic.bottom_radius = 0.54
		tunic.height = 1.05
		tunic.radial_segments = 16
		_make(tunic, Vector3(0, 1.56, 0), Vector3(1, 1, 0.78), cloth)
	else:
		_box(Vector3(0, 1.66, 0), Vector3(0.79, 0.13, 0.66), gold)
		_box(Vector3(0.025, 2.08, 0.335), Vector3(0.095, 0.92, 0.035), gold)
		_box(Vector3(-0.2, 2.28, 0.34), Vector3(0.2, 0.14, 0.035), _material(Color("bd6250")))
	_sphere(Vector3(0, 2.76, 0), Vector3(0.25, 0.3, 0.25), skin)
	_sphere(Vector3(0.03, 3.09, 0), Vector3(0.7, 0.8, 0.66), skin)
	_sphere(Vector3(0.35, 3.09, 0), Vector3(0.19, 0.16, 0.18), skin)
	_sphere(Vector3(0.23, 3.22, 0.255), Vector3(0.065, 0.055, 0.025), dark)
	if costume == 0:
		_sphere(Vector3(-0.065, 3.38, 0), Vector3(0.76, 0.35, 0.7), dark)
	else:
		_box(Vector3(0.02, 3.47, 0), Vector3(0.77, 0.17, 0.74), dark)
		_box(Vector3(0.04, 3.37, 0), Vector3(0.72, 0.09, 0.7), _material(Color("b85646")))
		_box(Vector3(0.35, 3.4, 0), Vector3(0.35, 0.07, 0.75), dark)
	for i in range(8):
		var bone = CapsuleMesh.new()
		bone.radius = 0.5
		bone.height = 2.0
		bone.radial_segments = 10
		bone.rings = 4
		limbs.append(_make(bone, Vector3.ZERO, Vector3.ONE, cloth))
	for i in range(2):
		limbs.append(_sphere(Vector3.ZERO, Vector3(0.25, 0.29, 0.25), skin))
	for i in range(2):
		limbs.append(_box(Vector3.ZERO, Vector3(0.48, 0.19, 0.32), dark))
	_pose(0.0)

func _attack_button_key(move_id: String) -> String:
	match move_id:
		"punch", "crouch_jab":
			return "lp"
		"heavy_punch":
			return "rp"
		"quick_kick", "low_sweep":
			return "lk"
		"kick":
			return "rk"
	return ""


func _resolve_air_move(cmd: String) -> String:
	if cmd in ["punch", "heavy_punch", "light_combo", "crouch_jab", "command_heavy", "air_punch"]:
		return "air_punch"
	if cmd in ["kick", "quick_kick", "low_sweep", "power_kick", "launcher", "air_kick"]:
		return "air_kick"
	return ""


func _start_attack(move_id: String) -> void:
	state = "attack"
	attack_kind = move_id
	attack_tick = 0
	attack_connected = false
	buffered_cancel = ""
	var move: Dictionary = attack_data()
	state_ticks = int(move.startup) + int(move.active) + int(move.recovery)
	armour_remaining = int(move.get("armour_hits", 0))
	if is_on_floor():
		velocity.x = 0.0
	var cost := int(move.get("josh_cost", 0))
	if cost > 0:
		if josh_meter >= cost:
			josh_meter = maxi(0, josh_meter - cost)
		elif junoon_active:
			junoon_active = false


func step(delta: float, axis: float, jump: bool, guard: bool = false, attack: String = "", crouch_input: bool = false, gesture: String = "") -> void:
	time += delta
	_explicit_guard = guard
	if is_on_floor():
		air_ticks = 0
		air_attack_used = false
	else:
		air_ticks += 1

	_advance_state(axis, jump, attack)

	if state == "attack" and not attack.is_empty():
		var kara_targets := ["throw_front", "rock_throw", "pistol_shoot", "signature", "super_jalwa", "taunt"]
		var kara_sources := ["punch", "heavy_punch", "quick_kick", "kick"]
		if attack_tick <= 2 and attack in kara_targets and (attack_kind in kara_sources or (attack == "super_jalwa" and attack_kind in ["throw_front", "signature"])) and attack_kind != attack:
			if attack == "taunt":
				state = "taunt"
				state_ticks = 96
				state_total_ticks = 96
				attack_kind = ""
				armour_remaining = 0
				buffered_cancel = ""
				velocity.x = 0.0
			elif _has_move(attack) and (attack != "super_jalwa" or josh_meter >= 100 or junoon_active):
				_start_attack(attack)
		else:
			var cur_move: Dictionary = attack_data()
			var routes: Dictionary = cur_move.get("cancel_routes", {})
			var next_move := ""
			if attack in routes.values():
				next_move = attack
			else:
				var btn_key := _attack_button_key(attack)
				if not btn_key.is_empty() and routes.has(btn_key):
					next_move = String(routes[btn_key])
			if not next_move.is_empty() and _has_move(next_move):
				buffered_cancel = next_move
				var active_end := int(cur_move.startup) + int(cur_move.active)
				if attack_tick >= active_end and attack_tick <= active_end + 8:
					_start_attack(buffered_cancel)

	if state in ["idle", "guard", "crouch", "crouch_guard"]:
		if gesture == "sidestep_bg" and not is_on_floor() and air_ticks <= 8 and state == "idle":
			position.y = 0.025
			velocity.y = 0.0
			state = "sidestep"
			state_ticks = 20
			sidestep_dir = -1.0
			sidestep_z = 0.0
			crouching = false
		elif not is_on_floor() and state == "idle" and not attack.is_empty() and not air_attack_used and not guard:
			var air_move := _resolve_air_move(attack)
			if not air_move.is_empty() and _has_move(air_move):
				air_attack_used = true
				_start_attack(air_move)
		elif is_on_floor():
			crouching = crouch_input
			if guard and not crouch_input:
				state = "guard"
				crouching = false
			elif crouch_input:
				state = "crouch_guard" if (_explicit_guard or (axis * facing) < -0.05 or (neutral_guard_enabled and absf(axis) <= 0.05)) else "crouch"
			else:
				state = "idle"

			if not guard and not gesture.is_empty() and state in ["idle", "crouch", "crouch_guard"]:
				if gesture == "dash_forward" and state in ["idle", "crouch"]:
					state = "dash_forward"
					state_ticks = 26
					state_total_ticks = 26
					velocity.x = facing * 6.4
					crouching = false
				elif gesture == "backdash":
					state = "backdash"
					state_ticks = 24
					state_total_ticks = 24
					velocity.x = -facing * 5.8
					crouching = false
				elif gesture == "sidestep_fg" or gesture == "sidestep_bg":
					state = "sidestep"
					state_ticks = 20
					state_total_ticks = 20
					sidestep_dir = 1.0 if gesture == "sidestep_fg" else -1.0
					sidestep_z = 0.0
					crouching = false
			elif not guard and not attack.is_empty() and state in ["idle", "crouch", "crouch_guard"]:
				if attack == "taunt":
					state = "taunt"
					state_ticks = 96
					state_total_ticks = 96
					velocity.x = 0.0
				elif attack == "josh_burst":
					if josh_meter >= 50:
						josh_meter -= 50
						junoon_active = true
						flash_color = Color("ffd25a")
						flash_ticks = 10
				elif _has_move(attack):
					if attack != "super_jalwa" or josh_meter >= 100 or junoon_active:
						_start_attack(attack)

	walking_back = (state == "idle") and is_on_floor() and ((axis * facing) < -0.15)
	if state == "idle":
		var walk_mult := 0.72 if ((axis * facing) < -0.05) else 1.0
		velocity.x = move_toward(velocity.x, clampf(axis, -1.0, 1.0) * (SPEED * walk_mult), 35.0 * delta)
	elif state == "crouch" or (state == "crouch_guard" and not _explicit_guard):
		var crouch_mult := 0.35 if ((axis * facing) < -0.05) else 0.42
		velocity.x = move_toward(velocity.x, clampf(axis, -1.0, 1.0) * (SPEED * crouch_mult), 35.0 * delta)
	elif state == "dash_forward" or state == "backdash" or state == "wakeup_roll":
		velocity.x = move_toward(velocity.x, 0.0, 4.5 * delta)
	elif state == "attack":
		var cur_m: Dictionary = attack_data()
		var adv := float(cur_m.get("advance_speed", 0.0))
		if adv > 0.0 and attack_tick < int(cur_m.startup):
			velocity.x = facing * adv
		elif not is_on_floor() and attack_kind in ["air_punch", "air_kick"]:
			pass
		else:
			velocity.x = move_toward(velocity.x, 0.0, 35.0 * delta)
	elif state == "juggle":
		velocity.x = move_toward(velocity.x, 0.0, 2.5 * delta)
	elif state in ["hitstun", "blockstun", "wall_splat", "thrown_tech", "ko"]:
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 35.0 * delta)

	if state == "juggle" and velocity.y > 0.0:
		velocity.y -= GRAVITY * 0.85 * delta
	elif is_on_floor():
		velocity.y = JUMP_SPEED if (jump and state in ["idle", "crouch"]) else -GRAVITY * delta
		if jump and state == "crouch":
			crouching = false
			state = "idle"
	else:
		var grav := GRAVITY * (0.85 if state == "juggle" else 1.0)
		velocity.y -= grav * delta

	velocity.z = 0
	move_and_slide()
	position.x = clampf(position.x, -STAGE_LIMIT, STAGE_LIMIT)
	position.z = 0.0
	if absf(position.x) >= STAGE_LIMIT - 0.001:
		velocity.x = 0.0
	gait += absf(velocity.x) * delta * 2.8
	if is_on_floor() and not is_zero_approx(pending_turn_from):
		if state in ["idle", "guard"] and not crouching:
			turn_from_facing = pending_turn_from
			turn_ticks = TURN_TICKS
		pending_turn_from = 0.0
	if turn_ticks > 0 and (not (state in ["idle", "guard"]) or not is_on_floor() or crouching):
		turn_ticks = 0
	flash_ticks = maxi(0, flash_ticks - 1)
	_update_flash()
	_pose(absf(velocity.x) / SPEED)
	if turn_ticks > 0:
		turn_ticks -= 1


func _advance_state(axis: float = 0.0, jump: bool = false, attack: String = "") -> void:
	if state == "attack":
		attack_tick += 1
		state_ticks -= 1
		var move: Dictionary = attack_data()
		var active_end := int(move.startup) + int(move.active)
		if attack_kind in ["air_punch", "air_kick"] and is_on_floor() and attack_tick >= 2:
			state = "idle"
			attack_kind = ""
			state_ticks = 0
			armour_remaining = 0
			buffered_cancel = ""
		elif not buffered_cancel.is_empty() and attack_tick >= active_end and attack_tick <= active_end + 8:
			_start_attack(buffered_cancel)
		elif state_ticks <= 0:
			state = "crouch" if crouching else "idle"
			attack_kind = ""
			armour_remaining = 0
			buffered_cancel = ""
	elif state in ["hitstun", "blockstun", "wall_splat", "thrown_tech"]:
		state_ticks -= 1
		if state_ticks <= 0:
			state = "idle"
			combo_hits = 0
			combo_damage = 0
			wall_splatted_in_combo = false
	elif state == "juggle":
		state_ticks = maxi(0, state_ticks - 1)
		if is_on_floor() and velocity.y <= 0.0:
			state = "knockdown"
			state_ticks = KNOCKDOWN_TICKS
			state_total_ticks = KNOCKDOWN_TICKS
			velocity.x = 0.0
	elif state == "knockdown":
		state_ticks -= 1
		if (attack == "taunt" or jump) and state_ticks <= KNOCKDOWN_TICKS - 10:
			state = "wakeup_quick"
			state_ticks = 16
			state_total_ticks = 16
			velocity.x = 0.0
		elif (axis * facing) < -0.35 and state_ticks <= KNOCKDOWN_TICKS - 18:
			state = "wakeup_roll"
			state_ticks = 16
			state_total_ticks = 16
			velocity.x = -facing * 6.5
		elif state_ticks <= 0:
			state = "wakeup_stand"
			state_ticks = WAKEUP_STAND_TICKS
			state_total_ticks = WAKEUP_STAND_TICKS
			velocity.x = 0.0
	elif state in ["wakeup_stand", "wakeup_quick", "wakeup_roll"]:
		state_ticks -= 1
		if state_ticks <= 0:
			state = "idle"
			combo_hits = 0
			combo_damage = 0
			wall_splatted_in_combo = false
	elif state in ["dash_forward", "backdash", "taunt"]:
		state_ticks -= 1
		if state_ticks <= 0:
			state = "idle"
	elif state == "sidestep":
		state_ticks -= 1
		sidestep_z = sin(clampf(float(20 - state_ticks) / 20.0, 0.0, 1.0) * PI) * 0.85 * sidestep_dir
		if state_ticks <= 0:
			state = "idle"
			sidestep_dir = 0.0
			sidestep_z = 0.0
	elif state == "ko" or state == "victory":
		state_ticks += 1

func get_display_name() -> String:
	return "KHAN SAHAB" if costume == 0 else "ASIM JANI"

func _has_move(move_id: String) -> bool:
	return MOVES.has(move_id)

func attack_data() -> Dictionary:
	return MOVES.get(attack_kind, MOVES.punch).duplicate()

func get_attack_box() -> Rect2:
	if state != "attack" or attack_connected or attack_kind in ["rock_throw", "pistol_shoot"]:
		return Rect2()
	var move: Dictionary = attack_data()
	if attack_tick < int(move.startup) or attack_tick >= int(move.startup) + int(move.active):
		return Rect2()
	var reach: float = float(move.reach)
	var left: float = global_position.x + 0.28 if facing > 0.0 else global_position.x - reach
	var low: float = float(move.get("low", 1.95 if attack_kind == "punch" else 1.15))
	var height: float = float(move.get("height", 0.8 if attack_kind == "punch" else 0.95))
	return Rect2(Vector2(left, global_position.y + low), Vector2(reach - 0.28, height))

func get_hurt_box() -> Rect2:
	if state in ["ko", "knockdown", "wakeup_stand", "wakeup_quick", "wakeup_roll", "thrown_tech"]:
		return Rect2()
	var is_crouch_pose := (state in ["crouch", "crouch_guard"]) or (state == "attack" and attack_kind in ["crouch_jab", "low_sweep"]) or (crouching and state != "attack")
	var height := 2.05 if is_crouch_pose else 3.25
	return Rect2(Vector2(global_position.x - 0.42, global_position.y + 0.2), Vector2(0.84, height))


func can_block(attacker_x: float) -> bool:
	return (state in ["guard", "blockstun", "crouch_guard"]) and is_on_floor() and (attacker_x - global_position.x) * facing > 0.0


func evaluate_defense(attacker_x: float, move: Dictionary) -> String:
	if state == "sidestep" and state_ticks >= 5 and state_ticks <= 17 and String(move.get("tracking", "linear")) == "linear":
		return "whiff"

	var lvl := String(move.get("hit_level", "mid"))
	if lvl == "throw":
		if not is_on_floor() or state in ["crouch", "crouch_guard", "hitstun", "blockstun", "juggle", "knockdown", "wakeup_stand", "wakeup_quick", "wakeup_roll", "wall_splat", "sidestep", "ko", "thrown_tech"] or crouching:
			return "whiff"
		return "throw"

	if (state in ["crouch", "crouch_guard"] or crouching) and lvl == "high":
		return "whiff"

	if lvl == "unblockable":
		return "hit"

	var facing_attacker := (attacker_x - global_position.x) * facing > 0.0
	if not facing_attacker or not is_on_floor():
		return "hit"

	if state in ["crouch_guard", "crouch"]:
		var crouch_guards := state == "crouch_guard" or walking_back or neutral_guard_enabled
		if crouch_guards and lvl == "low":
			return "blocked"
		return "hit"

	if state in ["guard", "blockstun"] or (state == "idle" and (walking_back or neutral_guard_enabled)):
		if lvl in ["high", "mid"]:
			return "blocked"
		return "hit"

	return "hit"


func receive_hit(damage: int, direction: float, blocked: bool, kind: String, options: Dictionary = {}) -> void:
	if state == "ko":
		return
	var move: Dictionary = options.get("move", MOVES.get(kind, MOVES.punch))
	var is_counter := bool(options.get("is_counter", false))
	var is_wall_splat := bool(options.get("is_wall_splat", false))
	var is_juggle_hit := bool(options.get("is_juggle_hit", false))
	var scale := float(options.get("scale", 1.0))
	var chip := int(options.get("chip", 0))

	if not blocked and state == "attack" and armour_remaining > 0 and String(move.get("hit_level", "mid")) != "throw":
		armour_remaining -= 1
		health = maxi(1, health - maxi(1, int(round(float(damage) * 0.5))))
		flash_color = Color("fff2a6")
		flash_ticks = 8
		_update_flash()
		return

	attack_kind = ""
	attack_tick = 0
	attack_connected = false
	buffered_cancel = ""
	armour_remaining = 0
	sidestep_dir = 0.0
	sidestep_z = 0.0

	if blocked:
		velocity.x = signf(direction) * float(move.knockback) * 0.45
		if chip > 0:
			health = maxi(1, health - chip)
		state = "blockstun"
		state_ticks = int(move.blockstun)
		state_total_ticks = state_ticks
		flash_color = Color("88e5ff")
		flash_ticks = 8
	else:
		crouching = false
		last_hit_level = String(options.get("hit_level", move.get("hit_level", "mid")))
		var final_dmg := maxi(1, int(round(float(damage) * scale)))
		health = maxi(0, health - final_dmg)
		combo_hits += 1
		combo_damage += final_dmg
		if health > 0 and health <= 25 and not junoon_used:
			junoon_used = true
			junoon_active = true
		josh_meter = mini(100, josh_meter + maxi(4, int(round(float(final_dmg) * 0.6))))
		if health == 0:
			state = "ko"
			state_ticks = 0
			state_total_ticks = KO_FALL_TICKS
			velocity.x = signf(direction) * float(move.knockback)
		elif is_wall_splat:
			state = "wall_splat"
			state_ticks = 30
			state_total_ticks = 30
			wall_splatted_in_combo = true
			velocity.x = -signf(direction) * 1.5
			velocity.y = 3.0
		elif bool(move.get("launcher", false)) or is_juggle_hit or not is_on_floor() or state == "juggle":
			state = "juggle"
			state_ticks = 45
			state_total_ticks = 45
			var lv: Vector2 = move.get("launch_velocity", Vector2(2.2, 8.8))
			if not bool(move.get("launcher", false)):
				lv = Vector2(maxf(2.0, float(move.knockback) * 0.45), 6.2)
			velocity.x = signf(direction) * lv.x
			velocity.y = lv.y
		elif bool(move.get("knockdown", false)):
			state = "knockdown"
			state_ticks = KNOCKDOWN_TICKS
			state_total_ticks = KNOCKDOWN_TICKS
			velocity.x = signf(direction) * float(move.knockback)
		else:
			state = "hitstun"
			state_ticks = int(move.hitstun) + (6 if is_counter else 0)
			state_total_ticks = state_ticks
			velocity.x = signf(direction) * float(move.knockback)
		flash_color = Color("ffd966") if is_counter else Color("ff8053")
		flash_ticks = 12
	_update_flash()
	_pose(0.0)

func mark_connected() -> void:
	attack_connected = true


func trigger_turn(new_facing: float) -> void:
	var nf := 1.0 if new_facing >= 0.0 else -1.0
	if is_equal_approx(facing, nf):
		return
	var prev := facing if (turn_ticks <= 0 and is_zero_approx(pending_turn_from)) else (pending_turn_from if not is_zero_approx(pending_turn_from) else turn_from_facing)
	facing = nf
	if is_equal_approx(prev, nf):
		turn_ticks = 0
		pending_turn_from = 0.0
		return
	if not is_on_floor():
		pending_turn_from = prev
		turn_ticks = 0
	elif state in ["idle", "guard"] and not crouching:
		turn_from_facing = prev
		turn_ticks = TURN_TICKS
		pending_turn_from = 0.0


func reset_combat() -> void:
	health = 100
	state = "idle"
	state_ticks = 0
	attack_kind = ""
	attack_tick = 0
	attack_connected = false
	josh_meter = 0
	junoon_used = false
	junoon_active = false
	crouching = false
	walking_back = false
	_explicit_guard = false
	air_ticks = 0
	air_attack_used = false
	sidestep_dir = 0.0
	sidestep_z = 0.0
	combo_hits = 0
	combo_damage = 0
	wall_splatted_in_combo = false
	armour_remaining = 0
	buffered_cancel = ""
	last_frame_advantage = 0
	last_hit_level = "mid"
	state_total_ticks = 0
	entry_progress = -1.0
	turn_ticks = 0
	turn_from_facing = facing
	pending_turn_from = 0.0
	input_buffer.clear()
	velocity = Vector3.ZERO
	flash_ticks = 0
	time = 0.0
	gait = 0.0
	if is_instance_valid(visual):
		_update_flash()
		_pose(0.0)

func snapshot_state() -> Dictionary:
	return {
		"px": position.x,
		"py": position.y,
		"pz": position.z,
		"vx": velocity.x,
		"vy": velocity.y,
		"vz": velocity.z,
		"facing": facing,
		"health": health,
		"state": state,
		"state_ticks": state_ticks,
		"attack_kind": attack_kind,
		"attack_tick": attack_tick,
		"attack_connected": attack_connected,
		"josh_meter": josh_meter,
		"junoon_used": junoon_used,
		"junoon_active": junoon_active,
		"crouching": crouching,
		"walking_back": walking_back,
		"neutral_guard_enabled": neutral_guard_enabled,
		"explicit_guard": _explicit_guard,
		"air_ticks": air_ticks,
		"air_attack_used": air_attack_used,
		"sidestep_dir": sidestep_dir,
		"sidestep_z": sidestep_z,
		"combo_hits": combo_hits,
		"combo_damage": combo_damage,
		"wall_splatted_in_combo": wall_splatted_in_combo,
		"armour_remaining": armour_remaining,
		"buffered_cancel": buffered_cancel,
		"last_frame_advantage": last_frame_advantage,
		"last_hit_level": last_hit_level,
		"state_total_ticks": state_total_ticks,
		"entry_progress": entry_progress,
		"turn_ticks": turn_ticks,
		"turn_from_facing": turn_from_facing,
		"pending_turn_from": pending_turn_from,
		"input_buffer": input_buffer.snapshot(),
		"gait": gait,
		"time": time,
		"flash_ticks": flash_ticks,
	}

func restore_state(snap: Dictionary) -> void:
	position = Vector3(float(snap.px), float(snap.py), float(snap.pz))
	velocity = Vector3(float(snap.vx), float(snap.vy), float(snap.vz))
	facing = float(snap.facing)
	health = int(snap.health)
	state = String(snap.state)
	state_ticks = int(snap.state_ticks)
	attack_kind = String(snap.attack_kind)
	attack_tick = int(snap.attack_tick)
	attack_connected = bool(snap.attack_connected)
	josh_meter = int(snap.get("josh_meter", 0))
	junoon_used = bool(snap.get("junoon_used", false))
	junoon_active = bool(snap.get("junoon_active", false))
	crouching = bool(snap.get("crouching", false))
	walking_back = bool(snap.get("walking_back", false))
	neutral_guard_enabled = bool(snap.get("neutral_guard_enabled", false))
	_explicit_guard = bool(snap.get("explicit_guard", false))
	air_ticks = int(snap.get("air_ticks", 0))
	air_attack_used = bool(snap.get("air_attack_used", false))
	sidestep_dir = float(snap.get("sidestep_dir", 0.0))
	sidestep_z = float(snap.get("sidestep_z", 0.0))
	combo_hits = int(snap.get("combo_hits", 0))
	combo_damage = int(snap.get("combo_damage", 0))
	wall_splatted_in_combo = bool(snap.get("wall_splatted_in_combo", false))
	armour_remaining = int(snap.get("armour_remaining", 0))
	buffered_cancel = String(snap.get("buffered_cancel", ""))
	last_frame_advantage = int(snap.get("last_frame_advantage", 0))
	last_hit_level = String(snap.get("last_hit_level", "mid"))
	state_total_ticks = int(snap.get("state_total_ticks", 0))
	entry_progress = float(snap.get("entry_progress", -1.0))
	turn_ticks = int(snap.get("turn_ticks", 0))
	turn_from_facing = float(snap.get("turn_from_facing", facing))
	pending_turn_from = float(snap.get("pending_turn_from", 0.0))
	if snap.has("input_buffer"):
		input_buffer.restore(snap.input_buffer)
	gait = float(snap.gait)
	time = float(snap.time)
	flash_ticks = int(snap.flash_ticks)
	if is_instance_valid(visual):
		_update_flash()
		_pose(0.0)

func _update_flash() -> void:
	var amount: float = clampf(float(flash_ticks) / 10.0, 0.0, 0.8)
	var target_cloth := cloth_color
	if junoon_active:
		target_cloth = cloth_color.lerp(Color("f4a63a"), 0.25)
	cloth.albedo_color = target_cloth.lerp(flash_color, amount)
	skin.albedo_color = skin_color.lerp(flash_color, amount)

func _attack_extension() -> float:
	if state != "attack":
		return 0.0
	var move: Dictionary = attack_data()
	var startup: int = int(move.startup)
	var active: int = int(move.active)
	if attack_tick < startup:
		return -0.16 * sin(float(attack_tick) / float(startup) * PI)
	if attack_tick < startup + active:
		return 1.0
	return 1.0 - smoothstep(0.0, float(move.recovery) * 0.7, float(attack_tick - startup - active))

func _pose(moving: float) -> void:
	var bob = sin(time * 3.0) * 0.025
	var extension: float = _attack_extension()
	var guarded: bool = state == "guard" or state == "blockstun" or state == "crouch_guard"
	var struck: bool = state == "hitstun" or state == "wall_splat" or state == "thrown_tech"
	var knocked_out: bool = state == "ko"
	var lean: float = 0.0
	var y_off: float = float(bob)
	if state == "attack":
		lean = -0.08 * extension if attack_kind == "punch" else 0.11 * extension
		if crouching:
			y_off = -0.45
	elif guarded:
		lean = 0.06
		if crouching or state == "crouch_guard":
			y_off = -0.55
	elif state == "crouch":
		lean = -0.12
		y_off = -0.55
	elif state == "juggle":
		lean = 0.42
		y_off = 0.15
	elif state == "knockdown":
		lean = smoothstep(0.0, 28.0, float(maxi(0, KNOCKDOWN_TICKS - state_ticks))) * PI * 0.48
		y_off = 0.25
	elif struck:
		lean = 0.19
	elif knocked_out:
		lean = smoothstep(0.0, 22.0, float(state_ticks)) * PI * 0.5
		y_off = 0.25
	visual.rotation = Vector3(0.0, 0.0 if facing > 0 else PI, lean)
	visual.position = Vector3(0.0, y_off, sidestep_z)
	if state != "idle":
		moving = 0.0
	for side in range(2):
		var z = -0.25 if side == 0 else 0.25
		var phase = gait + side * PI
		var swing = sin(phase) * 0.48 * moving
		var lift = maxf(0, cos(phase)) * 0.19 * moving
		if not is_on_floor() and position.y > 0.08:
			swing = -0.16 if side == 0 else 0.3
			lift = 0.23
		var hip = Vector3(-0.08, 1.49, z)
		var knee = Vector3(swing * 0.7 + 0.08, 0.8 + lift, z)
		var foot = Vector3(swing, 0.16 + lift, z)
		if state == "attack" and attack_kind == "kick" and side == 1:
			knee = Vector3(lerpf(0.08, 1.03, extension), lerpf(0.8, 1.82, extension), z)
			foot = Vector3(lerpf(0.0, 2.16, extension), lerpf(0.16, 1.66, extension), z)
		elif guarded:
			knee.x -= 0.09
			foot.x += -0.22 if side == 0 else 0.12
		elif struck or knocked_out:
			foot.x += -0.15 if side == 0 else 0.22
		_segment(limbs[side * 2], hip, knee, 0.18)
		_segment(limbs[side * 2 + 1], knee, foot, 0.15)
		limbs[10 + side].position = foot + Vector3(0.08, -0.045, 0)
		var shoulder = Vector3(0, 2.4, z * 1.3)
		var elbow = Vector3(0.32, 2.0 + bob, z * 1.55)
		var hand = Vector3(0.65 + side * 0.1, 2.47 + bob + side * 0.08, z * 1.25)
		if guarded:
			elbow = Vector3(0.37, 2.35, z * 1.55)
			hand = Vector3(0.42 + side * 0.13, 2.92 - side * 0.13, z)
		elif state == "attack" and attack_kind == "punch" and side == 1:
			elbow = Vector3(lerpf(0.25, 0.96, extension), lerpf(2.0, 2.46, extension), z * 1.3)
			hand = Vector3(lerpf(0.72, 1.72, extension), 2.5, z * 1.1)
		elif state == "attack" and attack_kind == "kick":
			hand.x -= 0.25 * extension
			hand.y += 0.15 * extension
		elif struck or knocked_out:
			elbow = Vector3(-0.22, 2.15, z * 1.8)
			hand = Vector3(0.05, 2.68 if struck else 1.75, z * 2.0)
		_segment(limbs[4 + side * 2], shoulder, elbow, 0.14)
		_segment(limbs[5 + side * 2], elbow, hand, 0.12)
		limbs[8 + side].position = hand

func _segment(instance: MeshInstance3D, a: Vector3, b: Vector3, radius: float) -> void:
	var direction = b - a
	# Scale the capsule in its local axes before rotating it along the limb.
	instance.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())).scaled_local(Vector3(radius * 2, direction.length() * 0.5, radius * 2)), (a + b) * 0.5)

func _material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material

func _make(mesh: Mesh, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = at
	instance.scale = size
	visual.add_child(instance)
	return instance

func _sphere(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	return _make(mesh, at, size, material)

func _box(at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	return _make(BoxMesh.new(), at, size, material)
