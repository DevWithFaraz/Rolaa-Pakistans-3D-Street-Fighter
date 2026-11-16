extends CharacterBody3D
## Deliberately abstract costume proxies. Final likenesses and rigs come later.

const SPEED = 4.8
const GRAVITY = 23.0
const JUMP_SPEED = 8.0
const STAGE_LIMIT = 14.0
const MOVES = {
	"punch": {"startup": 6, "active": 3, "recovery": 14, "damage": 10, "reach": 1.8, "knockback": 4.5, "hitstun": 18, "blockstun": 12, "hitstop": 5},
	"kick": {"startup": 12, "active": 4, "recovery": 22, "damage": 17, "reach": 2.4, "knockback": 6.0, "hitstun": 25, "blockstun": 17, "hitstop": 7},
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

func step(delta: float, axis: float, jump: bool, guard: bool = false, attack: String = "") -> void:
	time += delta
	_advance_state()
	if state == "idle" or state == "guard":
		state = "guard" if guard and is_on_floor() else "idle"
		if state == "idle" and is_on_floor() and _has_move(attack):
			state = "attack"
			attack_kind = attack
			attack_tick = 0
			attack_connected = false
			var move: Dictionary = attack_data()
			state_ticks = int(move.startup) + int(move.active) + int(move.recovery)
			velocity.x = 0.0
	if state == "idle":
		velocity.x = move_toward(velocity.x, clampf(axis, -1.0, 1.0) * SPEED, 35.0 * delta)
	elif state == "hitstun" or state == "blockstun" or state == "ko":
		velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 35.0 * delta)
	if is_on_floor():
		velocity.y = JUMP_SPEED if (jump and state == "idle") else -GRAVITY * delta
	else:
		velocity.y -= GRAVITY * delta
	velocity.z = 0
	move_and_slide()
	position.x = clampf(position.x, -STAGE_LIMIT, STAGE_LIMIT)
	position.z = 0.0
	if absf(position.x) >= STAGE_LIMIT - 0.001:
		velocity.x = 0.0
	gait += absf(velocity.x) * delta * 2.8
	flash_ticks = maxi(0, flash_ticks - 1)
	_update_flash()
	_pose(absf(velocity.x) / SPEED)

func _advance_state() -> void:
	if state == "attack":
		attack_tick += 1
		state_ticks -= 1
		if state_ticks <= 0:
			state = "idle"
			attack_kind = ""
	elif state == "hitstun" or state == "blockstun":
		state_ticks -= 1
		if state_ticks <= 0:
			state = "idle"
	elif state == "ko":
		state_ticks += 1

func get_display_name() -> String:
	return "KHAN SAHAB" if costume == 0 else "ASIM JANI"

func _has_move(move_id: String) -> bool:
	return MOVES.has(move_id)

func attack_data() -> Dictionary:
	return MOVES.get(attack_kind, MOVES.punch).duplicate()

func get_attack_box() -> Rect2:
	if state != "attack" or attack_connected:
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
	if state == "ko":
		return Rect2()
	return Rect2(Vector2(global_position.x - 0.42, global_position.y + 0.2), Vector2(0.84, 3.25))

func can_block(attacker_x: float) -> bool:
	return (state == "guard" or state == "blockstun") and is_on_floor() and (attacker_x - global_position.x) * facing > 0.0

func receive_hit(damage: int, direction: float, blocked: bool, kind: String) -> void:
	if state == "ko":
		return
	var move: Dictionary = MOVES.get(kind, MOVES.punch)
	attack_kind = ""
	attack_tick = 0
	attack_connected = false
	velocity.x = signf(direction) * float(move.knockback) * (0.45 if blocked else 1.0)
	if blocked:
		state = "blockstun"
		state_ticks = int(move.blockstun)
		flash_color = Color("88e5ff")
		flash_ticks = 8
	else:
		health = maxi(0, health - maxi(0, damage))
		state = "ko" if health == 0 else "hitstun"
		state_ticks = 0 if health == 0 else int(move.hitstun)
		flash_color = Color("ff8053")
		flash_ticks = 12
	_update_flash()
	_pose(0.0)

func mark_connected() -> void:
	attack_connected = true

func reset_combat() -> void:
	health = 100
	state = "idle"
	state_ticks = 0
	attack_kind = ""
	attack_tick = 0
	attack_connected = false
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
	gait = float(snap.gait)
	time = float(snap.time)
	flash_ticks = int(snap.flash_ticks)
	if is_instance_valid(visual):
		_update_flash()
		_pose(0.0)

func _update_flash() -> void:
	var amount: float = clampf(float(flash_ticks) / 10.0, 0.0, 0.8)
	cloth.albedo_color = cloth_color.lerp(flash_color, amount)
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
	var guarded: bool = state == "guard" or state == "blockstun"
	var struck: bool = state == "hitstun"
	var knocked_out: bool = state == "ko"
	var lean := 0.0
	if state == "attack":
		lean = -0.08 * extension if attack_kind == "punch" else 0.11 * extension
	elif guarded:
		lean = 0.06
	elif struck:
		lean = 0.19
	elif knocked_out:
		lean = smoothstep(0.0, 22.0, float(state_ticks)) * PI * 0.5
	visual.rotation = Vector3(0.0, 0.0 if facing > 0 else PI, lean)
	visual.position = Vector3(0.0, 0.25 if knocked_out else bob, 0.0)
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
