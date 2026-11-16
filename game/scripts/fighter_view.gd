class_name FighterView
extends "res://scripts/proxy_fighter.gd"
## Generic data-driven rigged fighter view backed by CharacterDef and MoveData resources.

@export var character_def: CharacterDef

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var fighter_materials: Array[Dictionary] = []
var khan_materials: Array[Dictionary] = []
var current_anim_state := ""
var _advance_dt := 0.0
var _move_axis := 0.0
var _has_walk_clip := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CapsuleShape3D.new()
	shape.radius = 0.38
	shape.height = 3.15
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 1.575
	add_child(collider)

	if character_def == null:
		character_def = CharacterDef.load_or_default("khan" if costume == 0 else "asim")
	health = character_def.max_health

	var prefix := character_def.id.capitalize() if not character_def.id.is_empty() else "Fighter"
	visual = Node3D.new()
	visual.name = prefix + "Visual"
	add_child(visual)

	var proxy_limb := MeshInstance3D.new()
	proxy_limb.visible = false
	visual.add_child(proxy_limb)
	limbs.append(proxy_limb)

	model = character_def.instantiate_model()
	assert(model != null, "Failed to instantiate model for CharacterDef: " + character_def.id)
	model.name = prefix + "Model"
	model.scale = Vector3.ONE * character_def.model_scale
	model.rotation.y = character_def.model_yaw_rad
	visual.add_child(model)

	skeleton = _find_node_of_type(model, "Skeleton3D") as Skeleton3D
	anim_player = _find_node_of_type(model, "AnimationPlayer") as AnimationPlayer
	assert(skeleton != null, "Missing Skeleton3D on fighter model: " + character_def.id)
	assert(anim_player != null, "Missing AnimationPlayer on fighter model: " + character_def.id)

	_collect_materials(model)
	khan_materials = fighter_materials
	_setup_animation_tree()
	_pose(0.0)
	_snap_to_idle()


func get_display_name() -> String:
	if character_def != null and not character_def.display_name.is_empty():
		return character_def.display_name
	return super.get_display_name()


func _has_move(move_id: String) -> bool:
	if character_def != null and character_def.get_move(move_id) != null:
		return true
	return super._has_move(move_id)


func attack_data() -> Dictionary:
	if character_def != null:
		var md := character_def.get_move(attack_kind)
		if md != null:
			return md.to_legacy_dict()
	return super.attack_data()


func step(delta: float, axis: float, jump: bool, guard: bool = false, attack: String = "") -> void:
	_move_axis = clampf(axis, -1.0, 1.0)
	_advance_dt = delta
	super.step(delta, axis, jump, guard, attack)


func reset_combat() -> void:
	_move_axis = 0.0
	_advance_dt = 0.0
	super.reset_combat()
	if character_def != null:
		health = character_def.max_health
	if is_instance_valid(anim_tree):
		_snap_to_idle()


func snapshot_state() -> Dictionary:
	var snap := super.snapshot_state()
	snap["current_anim_state"] = current_anim_state
	snap["move_axis"] = _move_axis
	snap["advance_dt"] = _advance_dt
	return snap


func restore_state(snap: Dictionary) -> void:
	_move_axis = float(snap.get("move_axis", 0.0))
	_advance_dt = float(snap.get("advance_dt", 0.0))
	var saved_anim := String(snap.get("current_anim_state", "idle"))
	super.restore_state(snap)
	if is_instance_valid(anim_tree) and not saved_anim.is_empty():
		current_anim_state = saved_anim
		anim_tree.set("parameters/state/transition_request", saved_anim)
		anim_tree.advance(0.0)


func _resolve_clip(state_key: String, fallback: StringName) -> StringName:
	var clip := character_def.get_clip(state_key)
	if not clip.is_empty() and anim_player.has_animation(clip):
		return clip
	if not fallback.is_empty() and anim_player.has_animation(fallback):
		return fallback
	return &""


func _setup_animation_tree() -> void:
	for clip in character_def.loop_clips:
		if anim_player.has_animation(clip):
			anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for move_key in character_def.moves:
		var md := character_def.get_move(str(move_key))
		if md != null and anim_player.has_animation(md.animation_clip):
			anim_player.get_animation(md.animation_clip).loop_mode = Animation.LOOP_NONE

	var idle_clip := _resolve_clip("idle", &"Idle")
	var guard_clip := _resolve_clip("guard", idle_clip)
	var punch_md := character_def.get_move("punch")
	var punch_clip := punch_md.animation_clip if punch_md != null else _resolve_clip("punch", &"Punch")
	var kick_md := character_def.get_move("kick")
	var kick_clip := kick_md.animation_clip if kick_md != null else _resolve_clip("kick", &"MmaKick")
	var walk_clip := _resolve_clip("walk", &"")
	_has_walk_clip = not walk_clip.is_empty()

	var bt := AnimationNodeBlendTree.new()
	var idle_n := AnimationNodeAnimation.new()
	idle_n.animation = idle_clip
	var guard_n := AnimationNodeAnimation.new()
	guard_n.animation = guard_clip
	var punch_n := AnimationNodeAnimation.new()
	punch_n.animation = punch_clip
	var kick_n := AnimationNodeAnimation.new()
	kick_n.animation = kick_clip

	var punch_ts := AnimationNodeTimeScale.new()
	var punch_seek := AnimationNodeTimeSeek.new()
	var kick_ts := AnimationNodeTimeScale.new()
	var kick_seek := AnimationNodeTimeSeek.new()

	var trans := AnimationNodeTransition.new()
	trans.xfade_time = character_def.xfade_time
	trans.input_count = 5 if _has_walk_clip else 4
	trans.set_input_name(0, &"idle")
	trans.set_input_name(1, &"guard")
	trans.set_input_name(2, &"punch")
	trans.set_input_name(3, &"kick")

	bt.add_node(&"idle", idle_n)
	bt.add_node(&"guard", guard_n)
	bt.add_node(&"punch", punch_n)
	bt.add_node(&"punch_ts", punch_ts)
	bt.add_node(&"punch_seek", punch_seek)
	bt.add_node(&"kick", kick_n)
	bt.add_node(&"kick_ts", kick_ts)
	bt.add_node(&"kick_seek", kick_seek)
	bt.add_node(&"state", trans)

	bt.connect_node(&"punch_ts", 0, &"punch")
	bt.connect_node(&"punch_seek", 0, &"punch_ts")
	bt.connect_node(&"kick_ts", 0, &"kick")
	bt.connect_node(&"kick_seek", 0, &"kick_ts")
	bt.connect_node(&"state", 0, &"idle")
	bt.connect_node(&"state", 1, &"guard")
	bt.connect_node(&"state", 2, &"punch_seek")
	bt.connect_node(&"state", 3, &"kick_seek")

	if _has_walk_clip:
		var walk_n := AnimationNodeAnimation.new()
		walk_n.animation = walk_clip
		trans.set_input_name(4, &"walk")
		bt.add_node(&"walk", walk_n)
		bt.connect_node(&"state", 4, &"walk")

	bt.connect_node(&"output", 0, &"state")

	anim_tree = AnimationTree.new()
	anim_tree.name = "CombatAnimTree"
	model.add_child(anim_tree)
	anim_tree.tree_root = bt
	anim_tree.anim_player = NodePath("../" + String(model.get_path_to(anim_player)))
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	anim_tree.set("parameters/punch_ts/scale", 0.0)
	anim_tree.set("parameters/kick_ts/scale", 0.0)


func _snap_to_idle() -> void:
	current_anim_state = "idle"
	anim_tree.set("parameters/state/transition_request", "idle")
	anim_tree.advance(0.15)
	anim_tree.advance(0.0)


func _collect_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(s)
				if mat is BaseMaterial3D:
					var copy := mat.duplicate() as BaseMaterial3D
					mi.set_surface_override_material(s, copy)
					fighter_materials.append({"material": copy, "base_albedo": copy.albedo_color})
	for child in node.get_children():
		_collect_materials(child)


func _update_flash() -> void:
	var amount := clampf(float(flash_ticks) / 10.0, 0.0, 0.8)
	for entry in fighter_materials:
		var mat: BaseMaterial3D = entry.material
		var base: Color = entry.base_albedo
		if amount > 0.001:
			mat.albedo_color = base.lerp(flash_color, amount * 0.55)
			mat.emission_enabled = true
			mat.emission = flash_color
			mat.emission_energy_multiplier = amount * 0.35
		else:
			mat.albedo_color = base
			mat.emission_enabled = false


func _attack_seek_time(kind: String, tick: int) -> float:
	if character_def == null:
		return 0.0
	var md := character_def.get_move(kind)
	if md == null:
		return 0.0
	var clip_len := 0.0
	if is_instance_valid(anim_player) and anim_player.has_animation(md.animation_clip):
		clip_len = anim_player.get_animation(md.animation_clip).length
	return md.sample_clip_time(tick, clip_len)


func _pose(moving: float) -> void:
	var dt := _advance_dt
	_advance_dt = 0.0
	if not is_instance_valid(visual) or not is_instance_valid(anim_tree):
		return

	var lean := 0.0
	var y_offset := 0.0
	var target_anim := "idle"
	var rate := 1.0
	var airborne := not is_on_floor() and position.y > 0.08

	if state == "attack":
		if attack_kind == "kick":
			target_anim = "kick"
			anim_tree.set("parameters/kick_seek/seek_request", _attack_seek_time("kick", attack_tick))
		else:
			target_anim = "punch"
			anim_tree.set("parameters/punch_seek/seek_request", _attack_seek_time("punch", attack_tick))
	elif state == "guard" or state == "blockstun":
		target_anim = "guard"
		lean = 0.11 if state == "blockstun" else 0.06
	elif state == "hitstun":
		target_anim = "guard"
		lean = 0.21
	elif state == "ko":
		target_anim = "guard"
		var fall_t := smoothstep(0.0, 22.0, float(state_ticks))
		lean = fall_t * PI * 0.5
		y_offset = lerpf(0.0, 0.32, fall_t)
	elif airborne:
		target_anim = "guard"
		lean = -0.06
	else:
		if absf(_move_axis) > 0.05 and _has_walk_clip:
			target_anim = "walk"
			var forward_dir := clampf(_move_axis * facing, -1.0, 1.0)
			lean = -0.04 * forward_dir * clampf(moving, 0.2, 1.0)
			rate = maxf(0.85, moving * 1.15)
		else:
			target_anim = "idle"
			if moving > 0.05:
				var forward_dir := clampf(_move_axis * facing, -1.0, 1.0)
				lean = -0.055 * forward_dir * moving
				y_offset = absf(sin(gait * 1.4)) * 0.045 * moving
				rate = 1.0 + moving * 0.35

	if target_anim != current_anim_state:
		current_anim_state = target_anim
		anim_tree.set("parameters/state/transition_request", target_anim)

	anim_tree.advance(dt * rate)
	visual.rotation = Vector3(0.0, 0.0 if facing > 0.0 else PI, lean)
	visual.position = Vector3(0.0, y_offset, 0.0)


func has_finite_bones() -> bool:
	if not is_instance_valid(skeleton):
		return false
	for bone in range(skeleton.get_bone_count()):
		if not skeleton.get_bone_global_pose(bone).is_finite():
			return false
	return true


func _find_node_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_node_of_type(child, type_name)
		if found:
			return found
	return null
