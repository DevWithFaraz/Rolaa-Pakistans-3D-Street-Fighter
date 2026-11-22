class_name FighterView
extends "res://scripts/proxy_fighter.gd"
## Generic data-driven rigged fighter view backed by CharacterDef and MoveData resources.

const ROCK_PROP_PATH := "res://assets/props/cliff_rock.glb"
const PISTOL_PROP_PATH := "res://assets/props/m1911_pistol.glb"
const PISTOL_HAND_SCALE := 0.92
const AURA_TEX_PATH := "res://assets/vfx/junoon_aura_ring.png"
const FLAME_TEX_PATH := "res://assets/vfx/junoon_flame_particle.png"
const BODY_FIRE_SHADER_PATH := "res://assets/vfx/shaders/junoon_body_fire.gdshader"
const FIRE_SHROUD_SHADER_PATH := "res://assets/vfx/shaders/volumetric_fire_aura.gdshader"
const MAGIC_CIRCLE_SHADER_PATH := "res://assets/vfx/shaders/magic_rune_circle.gdshader"
const VORONOI_TEX_PATH := "res://assets/vfx/voronoi_noise.png"
const FIRE_FLOW_TEX_PATH := "res://assets/vfx/fire_noise_flow.png"
const SLASH_NOISE_TEX_PATH := "res://assets/vfx/slash_noise.png"
const MAGIC_OUTER_TEX_PATH := "res://assets/vfx/magic_circle_outer.png"
const MAGIC_INNER_TEX_PATH := "res://assets/vfx/magic_rune_inner.png"
const FIRE_RING_TEX_PATH := "res://assets/vfx/fire_ring.png"
const CROUCH_TRANSITION_XFADE := 0.28
const STAND_STATES := ["idle", "guard", "walk", "walk_back"]
const CROUCH_STATES := ["st_crouch", "st_crouch_walk", "st_crouch_walk_back"]

@export var character_def: CharacterDef

var model: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var _state_trans: AnimationNodeTransition
var fighter_materials: Array[Dictionary] = []
var khan_materials: Array[Dictionary] = []
var current_anim_state := ""
var _advance_dt := 0.0
var _move_axis := 0.0
var _has_walk_clip := false
var _has_walk_back_clip := false
var _clip_state_map: Dictionary = {}
var _state_clip_map: Dictionary = {}
var _hand_rock: Node3D
var _hand_pistol: Node3D
var _pistol_muzzle: Node3D
var _pistol_base_basis := Basis.IDENTITY
var _junoon_aura: MeshInstance3D
var _fire_shroud_inner: MeshInstance3D
var _fire_shroud_outer: MeshInstance3D
var _junoon_flames: CPUParticles3D
var _junoon_embers: CPUParticles3D
var _body_fire_overlay_mat: ShaderMaterial
var _fighter_meshes: Array[MeshInstance3D] = []
var _body_fire_attached := false
var _last_fire_intensity := -1.0
var _last_flash_blend := -1.0
var _last_flash_color := Color.BLACK
var _last_flash_emission := Color(-1.0, -1.0, -1.0, -1.0)
var _last_flash_energy := -1.0
var _prewarm_stage := 0
var _prewarm_frames := 0
var _prewarm_elapsed := 0.0


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
	_setup_hand_rock()
	_setup_hand_pistol()
	_setup_junoon_vfx()
	_pose(0.0)
	_snap_to_idle()
	set_process(DisplayServer.get_name() != "headless")


func is_full_junoon_aura() -> bool:
	return josh_meter >= 100 or junoon_active


func _finish_flame_prewarm() -> void:
	var aura_on := is_full_junoon_aura() or (state == "attack" and attack_kind == "super_jalwa")
	if is_instance_valid(_junoon_flames):
		_junoon_flames.explosiveness = 0.0
		_junoon_flames.lifetime = 0.72
		_junoon_flames.scale_amount_min = 0.34
		_junoon_flames.scale_amount_max = 0.76
		_junoon_flames.visible = aura_on
		_junoon_flames.emitting = aura_on
		if aura_on:
			_junoon_flames.restart()
	if is_instance_valid(_junoon_embers):
		_junoon_embers.explosiveness = 0.0
		_junoon_embers.lifetime = 0.95
		_junoon_embers.scale_amount_min = 0.7
		_junoon_embers.scale_amount_max = 1.4
		_junoon_embers.visible = aura_on
		_junoon_embers.emitting = aura_on
		if aura_on:
			_junoon_embers.restart()
	_prewarm_stage = 3
	set_process(false)


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		_prewarm_stage = 3
		set_process(false)
		return
	if _prewarm_stage == 0:
		# Render hidden P3 props/particles at sub-pixel scale for 2 frames to compile GL shaders at load time.
		if is_instance_valid(_hand_rock) and not _hand_rock.visible:
			_hand_rock.scale = Vector3.ONE * 0.002
			_hand_rock.visible = true
		if is_instance_valid(_hand_pistol) and not _hand_pistol.visible:
			_hand_pistol.basis = _pistol_base_basis.scaled(Vector3.ONE * 0.002)
			_hand_pistol.visible = true
		if is_instance_valid(_junoon_aura) and not _junoon_aura.visible:
			_junoon_aura.scale = Vector3.ONE * 0.002
			_junoon_aura.visible = true
		if is_instance_valid(_fire_shroud_inner) and not _fire_shroud_inner.visible:
			_fire_shroud_inner.scale = Vector3.ONE * 0.002
			_fire_shroud_inner.visible = true
		if is_instance_valid(_fire_shroud_outer) and not _fire_shroud_outer.visible:
			_fire_shroud_outer.scale = Vector3.ONE * 0.002
			_fire_shroud_outer.visible = true
		if is_instance_valid(_junoon_flames) and not _junoon_flames.emitting:
			_junoon_flames.explosiveness = 1.0
			_junoon_flames.lifetime = 0.5
			_junoon_flames.scale_amount_min = 0.002
			_junoon_flames.scale_amount_max = 0.002
			_junoon_flames.visible = true
			_junoon_flames.emitting = true
			_junoon_flames.restart()
		if is_instance_valid(_junoon_embers) and not _junoon_embers.emitting:
			_junoon_embers.explosiveness = 1.0
			_junoon_embers.lifetime = 0.5
			_junoon_embers.scale_amount_min = 0.002
			_junoon_embers.scale_amount_max = 0.002
			_junoon_embers.visible = true
			_junoon_embers.emitting = true
			_junoon_embers.restart()
		_prewarm_stage = 1
		_prewarm_frames = 0
		_prewarm_elapsed = 0.0
	elif _prewarm_stage == 1:
		_prewarm_frames += 1
		if _prewarm_frames >= 2:
			var aura_on := is_full_junoon_aura() or (state == "attack" and attack_kind == "super_jalwa")
			if is_instance_valid(_hand_rock):
				_hand_rock.scale = Vector3.ONE * 0.52
				_hand_rock.visible = (state == "attack" and attack_kind == "rock_throw" and attack_tick >= 11 and attack_tick < 44)
			if is_instance_valid(_hand_pistol):
				_hand_pistol.basis = _pistol_base_basis.scaled(Vector3.ONE * PISTOL_HAND_SCALE)
				_hand_pistol.visible = (state == "attack" and attack_kind == "pistol_shoot")
			if is_instance_valid(_junoon_aura):
				_junoon_aura.scale = Vector3.ONE
				_junoon_aura.visible = aura_on
			if is_instance_valid(_fire_shroud_inner):
				_fire_shroud_inner.scale = Vector3.ONE
				_fire_shroud_inner.visible = aura_on
			if is_instance_valid(_fire_shroud_outer):
				_fire_shroud_outer.scale = Vector3.ONE
				_fire_shroud_outer.visible = aura_on
			if is_instance_valid(_junoon_flames) and not aura_on:
				_junoon_flames.visible = false
				_junoon_flames.emitting = false
				_junoon_flames.lifetime = 0.01
			if is_instance_valid(_junoon_embers) and not aura_on:
				_junoon_embers.visible = false
				_junoon_embers.emitting = false
				_junoon_embers.lifetime = 0.01
			_set_body_fire_overlay_attached(_last_fire_intensity > 0.001)
			_prewarm_stage = 2
			_prewarm_elapsed = 0.0
	elif _prewarm_stage == 2:
		_prewarm_elapsed += delta
		var aura_on := is_full_junoon_aura() or (state == "attack" and attack_kind == "super_jalwa")
		if aura_on or _prewarm_elapsed >= 0.025:
			_finish_flame_prewarm()


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


func step(delta: float, axis: float, jump: bool, guard: bool = false, attack: String = "", crouch_input: bool = false, gesture: String = "") -> void:
	_move_axis = clampf(axis, -1.0, 1.0)
	_advance_dt = delta
	super.step(delta, axis, jump, guard, attack, crouch_input, gesture)


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


func _resolve_move_clip(move_id: String) -> StringName:
	if character_def != null:
		var md := character_def.get_move(move_id)
		if md != null and not md.animation_clip.is_empty() and anim_player.has_animation(md.animation_clip):
			return md.animation_clip
	return &"MmaKick" if "kick" in move_id or "sweep" in move_id else &"Punch"


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
	var walk_back_clip := _resolve_clip("walk_back", &"")
	_has_walk_back_clip = not walk_back_clip.is_empty()
	if _has_walk_back_clip:
		anim_player.get_animation(walk_back_clip).loop_mode = Animation.LOOP_LINEAR

	var state_loop_keys := ["crouch", "crouch_walk", "crouch_walk_back", "victory"]
	var state_seek_keys := ["entry", "turn_180", "jump", "dash_forward", "backdash", "sidestep", "block_hit", "taunt", "hit_head", "hit_body", "knockdown", "ko", "wakeup"]
	_state_clip_map.clear()
	var resolved_loop_states: Array[Dictionary] = []
	for key in state_loop_keys:
		var cname := _resolve_clip(key, &"")
		if not cname.is_empty():
			anim_player.get_animation(cname).loop_mode = Animation.LOOP_LINEAR
			resolved_loop_states.append({"key": key, "clip": cname})
			_state_clip_map[key] = {"state_name": "st_" + key, "seek_param": "", "clip": cname}

	var resolved_seek_states: Array[Dictionary] = []
	for key in state_seek_keys:
		var cname := _resolve_clip(key, &"")
		if not cname.is_empty():
			anim_player.get_animation(cname).loop_mode = Animation.LOOP_NONE
			resolved_seek_states.append({"key": key, "clip": cname})
			_state_clip_map[key] = {"state_name": "st_" + key, "seek_param": "parameters/st_seek_%s/seek_request" % key, "clip": cname}

	var attack_clips: Array[StringName] = []
	for base_clip in [punch_clip, kick_clip]:
		if not base_clip.is_empty() and anim_player.has_animation(base_clip) and not base_clip in attack_clips:
			attack_clips.append(base_clip)
	for move_key in character_def.moves:
		var md := character_def.get_move(str(move_key))
		if md != null and not md.animation_clip.is_empty() and anim_player.has_animation(md.animation_clip):
			if not md.animation_clip in attack_clips:
				attack_clips.append(md.animation_clip)

	var bt := AnimationNodeBlendTree.new()
	var idle_n := AnimationNodeAnimation.new()
	idle_n.animation = idle_clip
	var guard_n := AnimationNodeAnimation.new()
	guard_n.animation = guard_clip

	bt.add_node(&"idle", idle_n)
	bt.add_node(&"guard", guard_n)

	var extra_inputs := (1 if _has_walk_clip else 0) + (1 if _has_walk_back_clip else 0) + resolved_loop_states.size() + resolved_seek_states.size()
	var trans := AnimationNodeTransition.new()
	trans.xfade_time = character_def.xfade_time
	trans.input_count = 2 + extra_inputs + attack_clips.size()
	_state_trans = trans
	trans.set_input_name(0, &"idle")
	trans.set_input_name(1, &"guard")

	bt.add_node(&"state", trans)
	bt.connect_node(&"state", 0, &"idle")
	bt.connect_node(&"state", 1, &"guard")

	var slot_idx := 2
	if _has_walk_clip:
		var walk_n := AnimationNodeAnimation.new()
		walk_n.animation = walk_clip
		trans.set_input_name(slot_idx, &"walk")
		bt.add_node(&"walk", walk_n)
		bt.connect_node(&"state", slot_idx, &"walk")
		slot_idx += 1

	if _has_walk_back_clip:
		var walk_back_n := AnimationNodeAnimation.new()
		walk_back_n.animation = walk_back_clip
		trans.set_input_name(slot_idx, &"walk_back")
		bt.add_node(&"walk_back", walk_back_n)
		bt.connect_node(&"state", slot_idx, &"walk_back")
		slot_idx += 1

	for item in resolved_loop_states:
		var key := String(item.key)
		var st_name := "st_" + key
		var n := AnimationNodeAnimation.new()
		n.animation = item.clip
		trans.set_input_name(slot_idx, StringName(st_name))
		bt.add_node(StringName(st_name), n)
		bt.connect_node(&"state", slot_idx, StringName(st_name))
		slot_idx += 1

	var ts_defaults: Array[String] = []
	for item in resolved_seek_states:
		var key := String(item.key)
		var st_name := "st_" + key
		var anim_n_name := "st_anim_" + key
		var ts_n_name := "st_ts_" + key
		var seek_n_name := "st_seek_" + key
		var n := AnimationNodeAnimation.new()
		n.animation = item.clip
		var ts := AnimationNodeTimeScale.new()
		var sk := AnimationNodeTimeSeek.new()
		bt.add_node(StringName(anim_n_name), n)
		bt.add_node(StringName(ts_n_name), ts)
		bt.add_node(StringName(seek_n_name), sk)
		bt.connect_node(StringName(ts_n_name), 0, StringName(anim_n_name))
		bt.connect_node(StringName(seek_n_name), 0, StringName(ts_n_name))
		trans.set_input_name(slot_idx, StringName(st_name))
		bt.connect_node(&"state", slot_idx, StringName(seek_n_name))
		slot_idx += 1
		ts_defaults.append("parameters/%s/scale" % ts_n_name)

	_clip_state_map.clear()
	for clip_name in attack_clips:
		var state_name := ""
		var anim_node_name := ""
		var ts_name := ""
		var seek_name := ""
		if clip_name == punch_clip:
			state_name = "punch"
			anim_node_name = "punch"
			ts_name = "punch_ts"
			seek_name = "punch_seek"
		elif clip_name == kick_clip:
			state_name = "kick"
			anim_node_name = "kick"
			ts_name = "kick_ts"
			seek_name = "kick_seek"
		else:
			var clean := String(clip_name).to_lower().replace(" ", "_")
			state_name = "clip_" + clean
			anim_node_name = "anim_" + clean
			ts_name = "ts_" + clean
			seek_name = "seek_" + clean

		var clip_n := AnimationNodeAnimation.new()
		clip_n.animation = clip_name
		var clip_ts := AnimationNodeTimeScale.new()
		var clip_seek := AnimationNodeTimeSeek.new()

		bt.add_node(StringName(anim_node_name), clip_n)
		bt.add_node(StringName(ts_name), clip_ts)
		bt.add_node(StringName(seek_name), clip_seek)
		bt.connect_node(StringName(ts_name), 0, StringName(anim_node_name))
		bt.connect_node(StringName(seek_name), 0, StringName(ts_name))

		trans.set_input_name(slot_idx, StringName(state_name))
		bt.connect_node(&"state", slot_idx, StringName(seek_name))
		slot_idx += 1

		ts_defaults.append("parameters/%s/scale" % ts_name)
		_clip_state_map[clip_name] = {
			"state_name": state_name,
			"seek_param": "parameters/%s/seek_request" % seek_name,
		}

	bt.connect_node(&"output", 0, &"state")

	anim_tree = AnimationTree.new()
	anim_tree.name = "CombatAnimTree"
	model.add_child(anim_tree)
	anim_tree.tree_root = bt
	anim_tree.anim_player = NodePath("../" + String(model.get_path_to(anim_player)))
	anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	anim_tree.active = true
	for ts_param in ts_defaults:
		anim_tree.set(ts_param, 0.0)


func _find_right_hand_bone_name() -> String:
	if skeleton == null:
		return ""
	for candidate in ["mixamorig_RightHand", "mixamorig:RightHand"]:
		if skeleton.find_bone(candidate) >= 0:
			return candidate
	return ""


func _setup_hand_rock() -> void:
	if character_def == null or character_def.id != "khan" or skeleton == null:
		return
	var hand_bone := _find_right_hand_bone_name()
	if hand_bone.is_empty() or not ResourceLoader.exists(ROCK_PROP_PATH):
		return
	var packed := load(ROCK_PROP_PATH) as PackedScene
	if packed == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "RightHandRockAttach"
	attach.bone_name = hand_bone
	skeleton.add_child(attach)
	_hand_rock = packed.instantiate() as Node3D
	_hand_rock.name = "HandRockProp"
	_hand_rock.scale = Vector3.ONE * 0.52
	_hand_rock.position = Vector3(0.0, 0.05, 0.03)
	_hand_rock.visible = false
	attach.add_child(_hand_rock)


func _setup_hand_pistol() -> void:
	if character_def == null or character_def.id != "asim" or skeleton == null:
		return
	var hand_bone := _find_right_hand_bone_name()
	if hand_bone.is_empty() or not ResourceLoader.exists(PISTOL_PROP_PATH):
		return
	var packed := load(PISTOL_PROP_PATH) as PackedScene
	if packed == null:
		return
	var attach := BoneAttachment3D.new()
	attach.name = "RightHandPistolAttach"
	attach.bone_name = hand_bone
	skeleton.add_child(attach)
	_hand_pistol = packed.instantiate() as Node3D
	_hand_pistol.name = "HandPistolProp"
	# Exact bone-local orientation aligning M1911 barrel (-Z) along facing & slide (+Y) upright in ShootPistol's two-handed grip.
	_pistol_base_basis = Basis(
		Vector3(-0.1214, 0.3990, -0.9089),
		Vector3(0.9846, -0.0676, -0.1612),
		Vector3(-0.1257, -0.9145, -0.3847)
	).orthonormalized()
	_hand_pistol.basis = _pistol_base_basis.scaled(Vector3.ONE * PISTOL_HAND_SCALE)
	_hand_pistol.position = Vector3(0.008, 0.161, 0.069)
	_hand_pistol.visible = false
	attach.add_child(_hand_pistol)
	_pistol_muzzle = _find_node_by_name(_hand_pistol, "MuzzlePoint") as Node3D


func _find_node_by_name(node: Node, target_name: String) -> Node:
	if String(node.name) == target_name or String(node.name).begins_with(target_name):
		return node
	for child in node.get_children():
		var found := _find_node_by_name(child, target_name)
		if found != null:
			return found
	return null


func _setup_junoon_vfx() -> void:
	# 1. Ground rotating fiery blaze ring (Circle Fire + Junoon ring — pure flame, no pentagram)
	_junoon_aura = MeshInstance3D.new()
	_junoon_aura.name = "JunoonAuraRing"
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.65, 2.65)
	_junoon_aura.mesh = plane
	_junoon_aura.position = Vector3(0.0, 0.045, 0.0)
	_junoon_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(MAGIC_CIRCLE_SHADER_PATH) and ResourceLoader.exists(FIRE_RING_TEX_PATH):
		var circle_mat := ShaderMaterial.new()
		circle_mat.shader = load(MAGIC_CIRCLE_SHADER_PATH) as Shader
		circle_mat.set_shader_parameter("outer_tex", load(FIRE_RING_TEX_PATH) as Texture2D)
		circle_mat.set_shader_parameter("inner_tex", load(AURA_TEX_PATH) as Texture2D if ResourceLoader.exists(AURA_TEX_PATH) else load(FIRE_RING_TEX_PATH) as Texture2D)
		circle_mat.set_shader_parameter("tint_outer", Color(0.95, 0.22, 0.02, 1.0))
		circle_mat.set_shader_parameter("tint_inner", Color(1.0, 0.72, 0.14, 1.0))
		circle_mat.set_shader_parameter("opacity", 1.15)
		circle_mat.set_shader_parameter("spin_speed", 1.6)
		_junoon_aura.material_override = circle_mat
	else:
		var aura_mat := StandardMaterial3D.new()
		aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		aura_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		aura_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		aura_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		aura_mat.albedo_color = Color(1.0, 0.85, 0.35, 0.9)
		if ResourceLoader.exists(AURA_TEX_PATH):
			aura_mat.albedo_texture = load(AURA_TEX_PATH) as Texture2D
		_junoon_aura.material_override = aura_mat
	_junoon_aura.visible = false
	add_child(_junoon_aura)

	# 2. Concentric volumetric rising flame shrouds hugging torso, arms, shoulders & head
	var shroud_shader: Shader = load(FIRE_SHROUD_SHADER_PATH) as Shader if ResourceLoader.exists(FIRE_SHROUD_SHADER_PATH) else null
	var slash_tex: Texture2D = load(SLASH_NOISE_TEX_PATH) as Texture2D if ResourceLoader.exists(SLASH_NOISE_TEX_PATH) else null
	var flow_tex: Texture2D = load(FIRE_FLOW_TEX_PATH) as Texture2D if ResourceLoader.exists(FIRE_FLOW_TEX_PATH) else null
	if shroud_shader != null and slash_tex != null and flow_tex != null:
		for layer_idx in range(2):
			var shroud := MeshInstance3D.new()
			shroud.name = "JunoonFireShroudInner" if layer_idx == 0 else "JunoonFireShroudOuter"
			var cyl := CylinderMesh.new()
			cyl.cap_top = false
			cyl.cap_bottom = false
			cyl.radial_segments = 24
			cyl.rings = 10
			if layer_idx == 0:
				cyl.bottom_radius = 0.50
				cyl.top_radius = 0.38
				cyl.height = 3.15
				shroud.position = Vector3(0.0, 1.60, 0.0)
			else:
				cyl.bottom_radius = 0.72
				cyl.top_radius = 0.58
				cyl.height = 3.55
				shroud.position = Vector3(0.0, 1.76, 0.0)
			shroud.mesh = cyl
			shroud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var smat := ShaderMaterial.new()
			smat.shader = shroud_shader
			smat.set_shader_parameter("flow_tex", slash_tex)
			smat.set_shader_parameter("noise_tex", flow_tex)
			smat.set_shader_parameter("intensity", 1.15 if layer_idx == 0 else 0.90)
			smat.set_shader_parameter("scroll_speed", 2.35 if layer_idx == 0 else 1.75)
			smat.set_shader_parameter("uv_tiles_x", 2.4 if layer_idx == 0 else 3.2)
			smat.set_shader_parameter("color_outer", Color(1.0, 0.16, 0.02, 1.0))
			smat.set_shader_parameter("color_mid", Color(1.0, 0.55, 0.07, 1.0))
			smat.set_shader_parameter("color_core", Color(1.0, 0.96, 0.70, 1.0))
			shroud.material_override = smat
			shroud.visible = false
			add_child(shroud)
			if layer_idx == 0:
				_fire_shroud_inner = shroud
			else:
				_fire_shroud_outer = shroud

	# 3. Full-body distributed rising flame plumes
	_junoon_flames = CPUParticles3D.new()
	_junoon_flames.name = "JunoonFlames"
	_junoon_flames.amount = 42
	_junoon_flames.lifetime = 0.72
	_junoon_flames.emitting = false
	_junoon_flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_junoon_flames.position = Vector3(0.0, 1.62, 0.0)
	_junoon_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_junoon_flames.emission_box_extents = Vector3(0.46, 1.42, 0.44)
	_junoon_flames.direction = Vector3(0.0, 1.0, 0.0)
	_junoon_flames.spread = 22.0
	_junoon_flames.gravity = Vector3(0.0, 2.2, 0.0)
	_junoon_flames.initial_velocity_min = 1.1
	_junoon_flames.initial_velocity_max = 2.4
	_junoon_flames.scale_amount_min = 0.34
	_junoon_flames.scale_amount_max = 0.76
	var qm := QuadMesh.new()
	qm.size = Vector2(0.72, 0.98)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fmat.billboard_keep_scale = true
	fmat.albedo_color = Color(1.0, 0.44, 0.06, 0.88)
	if ResourceLoader.exists(FLAME_TEX_PATH):
		fmat.albedo_texture = load(FLAME_TEX_PATH) as Texture2D
	elif ResourceLoader.exists(FIRE_RING_TEX_PATH):
		fmat.albedo_texture = load(FIRE_RING_TEX_PATH) as Texture2D
	qm.material = fmat
	_junoon_flames.mesh = qm
	_junoon_flames.visible = false
	add_child(_junoon_flames)

	# 4. Rising incandescent cinders / sparks (soft star-flare textured — no square boxes)
	_junoon_embers = CPUParticles3D.new()
	_junoon_embers.name = "JunoonEmbers"
	_junoon_embers.amount = 36
	_junoon_embers.lifetime = 0.95
	_junoon_embers.emitting = false
	_junoon_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_junoon_embers.position = Vector3(0.0, 1.55, 0.0)
	_junoon_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_junoon_embers.emission_box_extents = Vector3(0.56, 1.48, 0.56)
	_junoon_embers.direction = Vector3(0.0, 1.0, 0.0)
	_junoon_embers.spread = 32.0
	_junoon_embers.gravity = Vector3(0.0, 1.6, 0.0)
	_junoon_embers.initial_velocity_min = 1.6
	_junoon_embers.initial_velocity_max = 3.5
	_junoon_embers.scale_amount_min = 0.65
	_junoon_embers.scale_amount_max = 1.25
	var em_quad := QuadMesh.new()
	em_quad.size = Vector2(0.18, 0.24)
	var em_mat := StandardMaterial3D.new()
	em_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	em_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	em_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	em_mat.billboard_keep_scale = true
	em_mat.albedo_color = Color(1.0, 0.68, 0.16, 0.95)
	if ResourceLoader.exists("res://assets/vfx/star_flare.png"):
		em_mat.albedo_texture = load("res://assets/vfx/star_flare.png") as Texture2D
	em_quad.material = em_mat
	_junoon_embers.mesh = em_quad
	_junoon_embers.visible = false
	add_child(_junoon_embers)


func get_right_hand_world_pos() -> Vector3:
	if is_instance_valid(skeleton):
		var hand_bone := _find_right_hand_bone_name()
		if not hand_bone.is_empty():
			var idx := skeleton.find_bone(hand_bone)
			if idx >= 0:
				return skeleton.to_global(skeleton.get_bone_global_pose(idx).origin)
	return global_position + Vector3(facing * 0.6, 2.3, 0.0)


func get_pistol_muzzle_world_pos() -> Vector3:
	if is_instance_valid(_pistol_muzzle):
		return _pistol_muzzle.global_position
	return get_right_hand_world_pos() + Vector3(facing * 0.35, 0.12, 0.0)


func _snap_to_idle() -> void:
	current_anim_state = "idle"
	anim_tree.set("parameters/state/transition_request", "idle")
	anim_tree.advance(0.15)
	anim_tree.advance(0.0)


func _ensure_body_fire_overlay() -> void:
	if _body_fire_overlay_mat != null:
		return
	if ResourceLoader.exists(BODY_FIRE_SHADER_PATH) and ResourceLoader.exists(VORONOI_TEX_PATH) and ResourceLoader.exists(FIRE_FLOW_TEX_PATH):
		_body_fire_overlay_mat = ShaderMaterial.new()
		_body_fire_overlay_mat.shader = load(BODY_FIRE_SHADER_PATH) as Shader
		_body_fire_overlay_mat.set_shader_parameter("noise_tex", load(VORONOI_TEX_PATH) as Texture2D)
		_body_fire_overlay_mat.set_shader_parameter("flow_tex", load(FIRE_FLOW_TEX_PATH) as Texture2D)
		_body_fire_overlay_mat.set_shader_parameter("intensity", 0.0)
		_body_fire_overlay_mat.set_shader_parameter("scroll_speed", 2.5)


func _set_body_fire_overlay_attached(attached: bool) -> void:
	if _body_fire_overlay_mat == null or attached == _body_fire_attached:
		return
	_body_fire_attached = attached
	var mat: Material = _body_fire_overlay_mat if attached else null
	for mi in _fighter_meshes:
		if is_instance_valid(mi):
			mi.material_overlay = mat


func _collect_materials(node: Node) -> void:
	_ensure_body_fire_overlay()
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			_fighter_meshes.append(mi)
			if _body_fire_overlay_mat != null and DisplayServer.get_name() != "headless":
				mi.material_overlay = _body_fire_overlay_mat
				_body_fire_attached = true
			for s in range(mi.mesh.get_surface_count()):
				var mat := mi.get_active_material(s)
				if mat is BaseMaterial3D:
					var copy := mat.duplicate() as BaseMaterial3D
					# Keep emission always enabled so GL Compatibility never recompiles shader variants on hit/junoon.
					copy.emission_enabled = true
					copy.emission = Color.BLACK
					copy.emission_energy_multiplier = 0.0
					mi.set_surface_override_material(s, copy)
					fighter_materials.append({"material": copy, "base_albedo": copy.albedo_color})
	for child in node.get_children():
		_collect_materials(child)


func _update_flash() -> void:
	var amount := clampf(float(flash_ticks) / 10.0, 0.0, 0.8)
	var aura_on := is_full_junoon_aura()
	var in_super := state == "attack" and attack_kind == "super_jalwa"
	var albedo_blend := 0.0
	var target_emission := Color.BLACK
	var target_energy := 0.0
	if amount > 0.001:
		albedo_blend = amount * 0.55
		target_emission = flash_color
		target_energy = amount * 0.35
	elif in_super:
		target_emission = Color("ffbb44")
		target_energy = 0.24
	elif aura_on:
		target_emission = Color("eb7822")
		target_energy = 0.16 if junoon_active else 0.12

	if _body_fire_overlay_mat != null:
		var fire_target := 1.25 if in_super else (1.02 if junoon_active else (0.84 if josh_meter >= 100 else 0.0))
		if not is_equal_approx(fire_target, _last_fire_intensity):
			_last_fire_intensity = fire_target
			_body_fire_overlay_mat.set_shader_parameter("intensity", fire_target)
		if _prewarm_stage >= 2 or DisplayServer.get_name() == "headless":
			_set_body_fire_overlay_attached(fire_target > 0.001)

	if (
		is_equal_approx(albedo_blend, _last_flash_blend)
		and target_emission == _last_flash_emission
		and is_equal_approx(target_energy, _last_flash_energy)
		and (albedo_blend == 0.0 or flash_color == _last_flash_color)
	):
		return
	_last_flash_blend = albedo_blend
	_last_flash_color = flash_color
	_last_flash_emission = target_emission
	_last_flash_energy = target_energy

	for entry in fighter_materials:
		var mat: BaseMaterial3D = entry.material
		var base: Color = entry.base_albedo
		mat.albedo_color = base.lerp(flash_color, albedo_blend) if albedo_blend > 0.0 else base
		mat.emission = target_emission
		mat.emission_energy_multiplier = target_energy


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


func _seek_clip_window(key: String, total_ticks: int, remaining_ticks: int, t_start: float, t_end: float) -> String:
	var info: Dictionary = _state_clip_map.get(key, {})
	if info.is_empty():
		return ""
	var seek_param := String(info.seek_param)
	if not seek_param.is_empty():
		var clip_name: StringName = info.clip
		var clip_len := anim_player.get_animation(clip_name).length if anim_player.has_animation(clip_name) else t_end
		var denom := maxi(1, total_ticks)
		var elapsed := clampf(float(denom - remaining_ticks) / float(denom), 0.0, 1.0)
		var hi := minf(t_end, maxf(0.01, clip_len - 0.01))
		var lo := minf(t_start, hi * 0.5)
		anim_tree.set(seek_param, lerpf(lo, hi, elapsed))
	return String(info.state_name)


func _seek_state_clip(key: String, total_ticks: int, remaining_ticks: int, max_fraction: float = 0.98) -> String:
	var info: Dictionary = _state_clip_map.get(key, {})
	if info.is_empty():
		return ""
	var seek_param := String(info.seek_param)
	if not seek_param.is_empty():
		var clip_name: StringName = info.clip
		var clip_len := anim_player.get_animation(clip_name).length if anim_player.has_animation(clip_name) else 1.0
		var denom := maxi(1, total_ticks)
		var elapsed := clampf(float(denom - remaining_ticks) / float(denom), 0.0, 1.0)
		anim_tree.set(seek_param, elapsed * clip_len * max_fraction)
	return String(info.state_name)


func _pose(moving: float) -> void:
	var dt := _advance_dt
	_advance_dt = 0.0
	if not is_instance_valid(visual) or not is_instance_valid(anim_tree):
		return

	var show_rock := (state == "attack" and attack_kind == "rock_throw" and attack_tick >= 11 and attack_tick < 44)
	if is_instance_valid(_hand_rock):
		if show_rock:
			_hand_rock.scale = Vector3.ONE * 0.52
			_hand_rock.visible = true
		elif _prewarm_stage != 1:
			_hand_rock.visible = false
	var show_pistol := (state == "attack" and attack_kind == "pistol_shoot")
	if is_instance_valid(_hand_pistol):
		if show_pistol:
			_hand_pistol.basis = _pistol_base_basis.scaled(Vector3.ONE * PISTOL_HAND_SCALE)
			_hand_pistol.visible = true
		elif _prewarm_stage != 1:
			_hand_pistol.visible = false
	var aura_on := is_full_junoon_aura() or (state == "attack" and attack_kind == "super_jalwa")
	var aura_scale_boost := 1.18 if (state == "attack" and attack_kind == "super_jalwa") else 1.0
	if is_instance_valid(_junoon_aura):
		if aura_on:
			_junoon_aura.visible = true
			_junoon_aura.rotation.y = time * 2.2
			var pulse := (1.0 + 0.08 * sin(time * 8.0)) * aura_scale_boost
			_junoon_aura.scale = Vector3(pulse, 1.0, pulse)
		elif _prewarm_stage != 1:
			_junoon_aura.visible = false
	if is_instance_valid(_fire_shroud_inner):
		if aura_on:
			_fire_shroud_inner.visible = true
			_fire_shroud_inner.rotation.y = time * 1.9
			var sp1 := (1.0 + 0.05 * sin(time * 11.0)) * aura_scale_boost
			_fire_shroud_inner.scale = Vector3(sp1, 1.0, sp1)
		elif _prewarm_stage != 1:
			_fire_shroud_inner.visible = false
	if is_instance_valid(_fire_shroud_outer):
		if aura_on:
			_fire_shroud_outer.visible = true
			_fire_shroud_outer.rotation.y = -time * 1.35
			var sp2 := (1.0 + 0.07 * cos(time * 9.0)) * aura_scale_boost
			_fire_shroud_outer.scale = Vector3(sp2, 1.0, sp2)
		elif _prewarm_stage != 1:
			_fire_shroud_outer.visible = false
	if is_instance_valid(_junoon_flames):
		if aura_on:
			if _prewarm_stage == 1 or _prewarm_stage == 2:
				_finish_flame_prewarm()
			if not _junoon_flames.visible:
				_junoon_flames.visible = true
				_junoon_flames.restart()
			_junoon_flames.emitting = true
		elif _prewarm_stage == 0 or _prewarm_stage >= 3:
			_junoon_flames.emitting = false
			_junoon_flames.visible = false
	if is_instance_valid(_junoon_embers):
		if aura_on:
			if not _junoon_embers.visible:
				_junoon_embers.visible = true
				_junoon_embers.restart()
			_junoon_embers.emitting = true
		elif _prewarm_stage == 0 or _prewarm_stage >= 3:
			_junoon_embers.emitting = false
			_junoon_embers.visible = false

	var lean := 0.0
	var y_offset := 0.0
	var z_offset := sidestep_z
	var target_anim := "idle"
	var rate := 1.0
	var airborne := not is_on_floor() and position.y > 0.08

	if state == "attack":
		var clip_name := _resolve_move_clip(attack_kind)
		var clip_info: Dictionary = _clip_state_map.get(clip_name, {})
		if not clip_info.is_empty():
			target_anim = String(clip_info.state_name)
			anim_tree.set(String(clip_info.seek_param), _attack_seek_time(attack_kind, attack_tick))
		elif attack_kind == "kick":
			target_anim = "kick"
			anim_tree.set("parameters/kick_seek/seek_request", _attack_seek_time("kick", attack_tick))
		else:
			target_anim = "punch"
			anim_tree.set("parameters/punch_seek/seek_request", _attack_seek_time("punch", attack_tick))
		if crouching and attack_kind == "crouch_jab":
			y_offset = -0.35
	elif state == "guard":
		target_anim = "guard"
		lean = 0.0
	elif state == "blockstun":
		if _state_clip_map.has("block_hit"):
			target_anim = _seek_clip_window("block_hit", maxi(10, state_total_ticks), state_ticks, 0.22, 1.35)
		else:
			target_anim = "guard"
			lean = 0.05
	elif state == "crouch" or state == "crouch_guard":
		var forward_dir := _move_axis * facing
		if forward_dir < -0.05 and not _explicit_guard and _state_clip_map.has("crouch_walk_back"):
			target_anim = _state_clip_map["crouch_walk_back"].state_name
			rate = maxf(0.75, moving * 1.15)
		elif forward_dir > 0.05 and not _explicit_guard and _state_clip_map.has("crouch_walk"):
			target_anim = _state_clip_map["crouch_walk"].state_name
			rate = maxf(0.85, moving * 1.35)
		elif absf(_move_axis) > 0.05 and not _explicit_guard and _state_clip_map.has("crouch_walk"):
			target_anim = _state_clip_map["crouch_walk"].state_name
			rate = maxf(0.85, moving * 1.35)
		elif _state_clip_map.has("crouch"):
			target_anim = _state_clip_map["crouch"].state_name
		else:
			target_anim = "guard"
			y_offset = -0.52
			lean = -0.14 if state == "crouch" else -0.04
	elif state == "dash_forward":
		if _state_clip_map.has("dash_forward"):
			target_anim = _seek_state_clip("dash_forward", maxi(26, state_total_ticks), state_ticks, 0.96)
		else:
			target_anim = "walk" if _has_walk_clip else "idle"
			lean = -0.15
	elif state == "backdash":
		if _state_clip_map.has("backdash"):
			target_anim = _seek_state_clip("backdash", maxi(24, state_total_ticks), state_ticks, 0.96)
		else:
			target_anim = "walk" if _has_walk_clip else "idle"
			lean = 0.14
	elif state == "sidestep":
		if _state_clip_map.has("sidestep"):
			target_anim = _seek_state_clip("sidestep", maxi(20, state_total_ticks), state_ticks)
		else:
			target_anim = "walk" if _has_walk_clip else "idle"
			lean = -0.05
	elif state == "hitstun" or state == "thrown_tech":
		var hit_key := "hit_head" if last_hit_level in ["high", "throw", "rock", "head"] else "hit_body"
		if hit_key == "hit_head" and _state_clip_map.has("hit_head"):
			var info: Dictionary = _state_clip_map["hit_head"]
			var clip_name: StringName = info.clip
			var clip_len := anim_player.get_animation(clip_name).length if anim_player.has_animation(clip_name) else 1.0
			var denom := maxi(18, state_total_ticks)
			var elapsed := clampf(float(denom - state_ticks) / float(denom), 0.0, 1.0)
			var eased := pow(elapsed, 0.55)
			var end_t := minf(0.95, maxf(0.17, clip_len - 0.01))
			var start_t := minf(0.16, end_t * 0.5)
			anim_tree.set(String(info.seek_param), lerpf(start_t, end_t, eased))
			target_anim = String(info.state_name)
		elif _state_clip_map.has(hit_key):
			target_anim = _seek_state_clip(hit_key, maxi(18, state_total_ticks), state_ticks)
		elif _state_clip_map.has("hit_body"):
			target_anim = _seek_state_clip("hit_body", maxi(18, state_total_ticks), state_ticks)
		else:
			target_anim = "guard"
			lean = 0.21
	elif state == "juggle":
		if _state_clip_map.has("hit_body"):
			target_anim = _seek_state_clip("hit_body", maxi(30, state_total_ticks), state_ticks, 0.75)
			lean = 0.18
		else:
			target_anim = "guard"
			lean = 0.42
			y_offset = 0.14
	elif state == "wall_splat":
		if _state_clip_map.has("hit_body"):
			target_anim = _seek_state_clip("hit_body", maxi(30, state_total_ticks), state_ticks, 0.85)
		else:
			target_anim = "guard"
			lean = 0.26
			y_offset = 0.12
	elif state == "knockdown":
		if _state_clip_map.has("knockdown"):
			target_anim = _seek_clip_window("knockdown", maxi(KNOCKDOWN_TICKS, state_total_ticks), state_ticks, 0.85, 2.30)
		else:
			target_anim = "guard"
			var fall_t := smoothstep(0.0, 28.0, float(maxi(0, KNOCKDOWN_TICKS - state_ticks)))
			lean = fall_t * PI * 0.48
			y_offset = lerpf(0.0, 0.30, fall_t)
	elif state == "wakeup_stand" or state == "wakeup_quick" or state == "wakeup_roll":
		if _state_clip_map.has("wakeup"):
			var wake_start := 0.05 if state == "wakeup_stand" else 2.35
			target_anim = _seek_clip_window("wakeup", maxi(10, state_total_ticks), state_ticks, wake_start, 4.95)
		else:
			target_anim = "guard"
			var rise_t := clampf(float(state_ticks) / 10.0, 0.0, 1.0)
			lean = rise_t * PI * 0.35
			y_offset = lerpf(0.0, 0.22, rise_t)
	elif state == "taunt":
		if _state_clip_map.has("taunt"):
			var is_khan_t := character_def != null and character_def.id == "khan"
			var t_start := 0.12 if is_khan_t else 0.25
			var t_end := 2.65 if is_khan_t else 2.45
			target_anim = _seek_clip_window("taunt", maxi(24, state_total_ticks), state_ticks, t_start, t_end)
		else:
			target_anim = "idle"
			lean = -0.06
	elif state == "victory":
		if _state_clip_map.has("victory"):
			target_anim = _state_clip_map["victory"].state_name
		else:
			target_anim = "idle"
	elif state == "ko":
		var ko_key := "ko" if _state_clip_map.has("ko") else "knockdown"
		if _state_clip_map.has(ko_key):
			target_anim = _seek_clip_window(ko_key, KO_FALL_TICKS, maxi(0, KO_FALL_TICKS - state_ticks), 0.25, 2.65)
		else:
			target_anim = "guard"
			var fall_t := smoothstep(0.0, 34.0, float(state_ticks))
			lean = fall_t * PI * 0.5
			y_offset = lerpf(0.0, 0.32, fall_t)
	elif airborne:
		if _state_clip_map.has("jump"):
			var info: Dictionary = _state_clip_map["jump"]
			var clip_name: StringName = info.clip
			var clip_len := anim_player.get_animation(clip_name).length if anim_player.has_animation(clip_name) else 1.2
			var jump_frac := clampf(float(air_ticks) / 42.0, 0.0, 1.0)
			var seek_t := minf(lerpf(0.44, 1.16, jump_frac), maxf(0.0, clip_len - 0.01))
			anim_tree.set(String(info.seek_param), seek_t)
			target_anim = String(info.state_name)
		else:
			target_anim = "guard"
			lean = -0.06
	elif entry_progress >= 0.0 and _state_clip_map.has("entry"):
		var info: Dictionary = _state_clip_map["entry"]
		var clip_name: StringName = info.clip
		var clip_len := anim_player.get_animation(clip_name).length if anim_player.has_animation(clip_name) else 2.5
		var e_start := 0.05
		var e_end := maxf(e_start + 0.1, clip_len - 0.02)
		anim_tree.set(String(info.seek_param), lerpf(e_start, e_end, clampf(entry_progress, 0.0, 1.0)))
		target_anim = String(info.state_name)
	elif turn_ticks > 0 and state in ["idle", "guard"] and not crouching and _state_clip_map.has("turn_180"):
		target_anim = _seek_state_clip("turn_180", TURN_TICKS, turn_ticks, 0.98)
	else:
		var forward_dir := _move_axis * facing
		if forward_dir < -0.05 and _has_walk_back_clip:
			target_anim = "walk_back"
			rate = maxf(0.70, moving * 0.95)
		elif absf(_move_axis) > 0.05 and _has_walk_clip:
			target_anim = "walk"
			lean = -0.04 * clampf(forward_dir, -1.0, 1.0) * clampf(moving, 0.2, 1.0)
			rate = maxf(0.85, moving * 1.15)
		else:
			target_anim = "idle"
			if moving > 0.05:
				lean = -0.055 * clampf(forward_dir, -1.0, 1.0) * moving
				y_offset = absf(sin(gait * 1.4)) * 0.045 * moving
				rate = 1.0 + moving * 0.35

	if target_anim != current_anim_state:
		if _state_trans != null:
			_state_trans.xfade_time = CROUCH_TRANSITION_XFADE if _is_crouch_stance_transition(current_anim_state, target_anim) else character_def.xfade_time
		current_anim_state = target_anim
		anim_tree.set("parameters/state/transition_request", target_anim)

	var vis_facing := facing
	if target_anim == "st_turn_180":
		vis_facing = turn_from_facing
	elif airborne and not is_zero_approx(pending_turn_from):
		vis_facing = pending_turn_from

	anim_tree.advance(dt * rate)
	visual.rotation = Vector3(0.0, 0.0 if vis_facing > 0.0 else PI, lean)
	visual.position = Vector3(0.0, y_offset, z_offset)


func _is_crouch_stance_transition(from_state: String, to_state: String) -> bool:
	return (from_state in STAND_STATES and to_state in CROUCH_STATES) or (from_state in CROUCH_STATES and to_state in STAND_STATES)


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
