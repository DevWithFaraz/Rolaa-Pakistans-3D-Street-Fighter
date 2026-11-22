extends Node3D
## Pre-allocated pooled mesh sparks (zero runtime node/material allocation), 3D rock projectile/shards, Junoon/Jalwa burst VFX, and synthesized audio.

const POOL_SIZE := 48
const SPARK_LIFE := 0.22
const ROCK_PROP_PATH := "res://assets/props/cliff_rock.glb"
const ROCK_SHARDS_PATH := "res://assets/props/cliff_rock_shards.glb"
const BULLET_PROP_PATH := "res://assets/props/bullet_45acp.glb"
const LIGHTNING_GLB_PATH := "res://assets/vfx/lightning_bolts.glb"
const SLASH_GLB_PATH := "res://assets/vfx/slash_arc.glb"
const LIGHTNING_SHADER_PATH := "res://assets/vfx/shaders/lightning_arc.gdshader"
const SLASH_SHADER_PATH := "res://assets/vfx/shaders/energy_slash.gdshader"
const CRACK_SHADER_PATH := "res://assets/vfx/shaders/ground_crack.gdshader"
const MAGIC_SHADER_PATH := "res://assets/vfx/shaders/magic_rune_circle.gdshader"
const LIGHTNING_CORE_TEX_PATH := "res://assets/vfx/lightning_core.png"
const SLASH_NOISE_TEX_PATH := "res://assets/vfx/slash_noise.png"
const VORONOI_TEX_PATH := "res://assets/vfx/voronoi_noise.png"
const CRACK_TEX_PATH := "res://assets/vfx/ground_crack.png"
const CRACK_VEINS_TEX_PATH := "res://assets/vfx/ground_crack_veins.png"
const MAGIC_OUTER_TEX_PATH := "res://assets/vfx/magic_circle_outer.png"
const MAGIC_INNER_TEX_PATH := "res://assets/vfx/magic_rune_inner.png"
const STAR_FLARE_TEX_PATH := "res://assets/vfx/star_flare.png"
const AURA_TEX_PATH := "res://assets/vfx/junoon_aura_ring.png"
const FLAME_TEX_PATH := "res://assets/vfx/junoon_flame_particle.png"
const BURST_TEX_PATH := "res://assets/vfx/hit_spark_burst.png"
const DUST_TEX_PATH := "res://assets/vfx/dust_puff.png"

var pool: Array[Dictionary] = []
var pool_cursor := 0
var hit_mesh: SphereMesh
var block_mesh: SphereMesh
var hit_mat: StandardMaterial3D
var block_mat: StandardMaterial3D
var counter_mat: StandardMaterial3D
var super_mat: StandardMaterial3D

var vfx_layer: Node3D
var flash_quad: MeshInstance3D
var flash_quad_mat: StandardMaterial3D
var flash_quad_age := 1.0
var shockwave_ring: MeshInstance3D
var shockwave_mat: StandardMaterial3D
var light_pillar: MeshInstance3D
var pillar_mat: StandardMaterial3D
var shockwave_age := 1.0
var burst_particles: CPUParticles3D
var dust_particles: CPUParticles3D
var flying_rock: Node3D
var rock_shards: Array[Dictionary] = []
var flying_bullet: Node3D
var muzzle_flash: Node3D
var muzzle_flash_mat: StandardMaterial3D
var muzzle_flash_age := 1.0
var shell_casing: MeshInstance3D
var shell_vel := Vector3.ZERO
var shell_ang_vel := Vector3.ZERO
var shell_age := 2.0
var shell_active := false
var lightning_sky_bolts: Array[MeshInstance3D] = []
var lightning_sky_mats: Array[ShaderMaterial] = []
var lightning_arc_bolt: MeshInstance3D
var lightning_arc_mat: ShaderMaterial
var slash_wave: Node3D
var slash_mat: ShaderMaterial
var ground_crack: MeshInstance3D
var ground_crack_mat: ShaderMaterial
var super_rune_circle: MeshInstance3D
var super_rune_mat: ShaderMaterial
var impact_flare: MeshInstance3D
var impact_flare_mat: StandardMaterial3D
var ember_burst: CPUParticles3D
var lightning_startup_age := 2.0
var finisher_age := 2.0
var slash_age := 2.0
var crack_age := 3.0
var flare_age := 2.0
var super_rune_age := 2.0
var sky_dim_factor := 0.0
var camera_shake_amp := 0.0
var _shake_phase := 0.0
var super_flash_ticks := 0
var _any_sparks_active := false
var _any_shards_active := false
var _prewarm_stage := 0
var _prewarm_frames := 0
var _prewarm_elapsed := 0.0

var sounds: Dictionary = {}
var voice_cache: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var voice_index := 0
var muted := false


func _make_spark_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = false
	return mat


func _ready() -> void:
	hit_mesh = SphereMesh.new()
	hit_mesh.radius = 0.06
	hit_mesh.height = 0.12
	hit_mesh.radial_segments = 6
	hit_mesh.rings = 3

	block_mesh = SphereMesh.new()
	block_mesh.radius = 0.045
	block_mesh.height = 0.09
	block_mesh.radial_segments = 6
	block_mesh.rings = 3

	hit_mat = _make_spark_mat(Color("ffbf53"))
	block_mat = _make_spark_mat(Color("7cdeee"))
	counter_mat = _make_spark_mat(Color("ff5a36"))
	super_mat = _make_spark_mat(Color("ffe66d"))

	for i in range(POOL_SIZE):
		var spark := MeshInstance3D.new()
		spark.name = "Spark_%d" % i
		spark.mesh = hit_mesh
		spark.material_override = hit_mat
		spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		spark.visible = false
		add_child(spark)
		pool.append({
			"node": spark,
			"velocity": Vector3.ZERO,
			"age": 0.0,
			"active": false,
		})

	vfx_layer = Node3D.new()
	vfx_layer.name = "VfxLayer"
	add_child(vfx_layer)
	_setup_vfx_layer()

	for kind in ["punch", "kick", "block", "round", "junoon", "rock", "gunshot", "thunder", "super_finisher"]:
		sounds[kind] = _make_sound(kind)
	for i in range(4):
		var voice = AudioStreamPlayer.new()
		voice.volume_db = -19.0
		add_child(voice)
		voices.append(voice)
	set_process(DisplayServer.get_name() != "headless")


func _restore_prewarm_meshes() -> void:
	for i in range(mini(4, pool.size())):
		if not bool(pool[i].active):
			var spark: MeshInstance3D = pool[i].node
			spark.mesh = hit_mesh
			spark.material_override = hit_mat
			spark.scale = Vector3.ONE
			spark.visible = false
	if is_instance_valid(flash_quad) and flash_quad_age >= 0.14:
		flash_quad.scale = Vector3.ONE
		flash_quad.visible = false
	if is_instance_valid(shockwave_ring) and shockwave_age >= 0.45:
		shockwave_ring.scale = Vector3.ONE
		shockwave_ring.visible = false
	if is_instance_valid(light_pillar) and shockwave_age >= 0.45:
		light_pillar.scale = Vector3.ONE
		light_pillar.visible = false
	if is_instance_valid(flying_rock):
		flying_rock.scale = Vector3.ONE * 1.1
		flying_rock.visible = false
	if is_instance_valid(flying_bullet):
		flying_bullet.scale = Vector3.ONE
		flying_bullet.visible = false
	if is_instance_valid(muzzle_flash) and muzzle_flash_age >= 0.09:
		muzzle_flash.scale = Vector3.ONE
		muzzle_flash.visible = false
	if is_instance_valid(shell_casing) and not shell_active:
		shell_casing.scale = Vector3.ONE
		shell_casing.visible = false
	for bolt in lightning_sky_bolts:
		if is_instance_valid(bolt):
			bolt.scale = Vector3.ONE
			bolt.visible = false
	if is_instance_valid(lightning_arc_bolt):
		lightning_arc_bolt.scale = Vector3.ONE
		lightning_arc_bolt.visible = false
	if is_instance_valid(slash_wave) and slash_age >= 0.40:
		slash_wave.scale = Vector3.ONE
		slash_wave.visible = false
	if is_instance_valid(ground_crack) and crack_age >= 1.65:
		ground_crack.scale = Vector3.ONE
		ground_crack.visible = false
	if is_instance_valid(super_rune_circle) and super_rune_age >= 0.65:
		super_rune_circle.scale = Vector3.ONE
		super_rune_circle.visible = false
	if is_instance_valid(impact_flare) and flare_age >= 0.24:
		impact_flare.scale = Vector3.ONE
		impact_flare.visible = false
	if not rock_shards.is_empty() and not bool(rock_shards[0].active):
		var sh_node: MeshInstance3D = rock_shards[0].node
		sh_node.scale = Vector3.ONE * float(rock_shards[0].get("base_scale", 1.0))
		sh_node.visible = false


func _restore_prewarm_particles() -> void:
	if is_instance_valid(burst_particles):
		burst_particles.explosiveness = 0.92
		burst_particles.lifetime = 0.55
		burst_particles.scale_amount_min = 1.0
		burst_particles.scale_amount_max = 1.0
		burst_particles.visible = false
		burst_particles.emitting = false
	if is_instance_valid(dust_particles):
		dust_particles.explosiveness = 0.95
		dust_particles.lifetime = 0.55
		dust_particles.scale_amount_min = 0.6
		dust_particles.scale_amount_max = 1.1
		dust_particles.visible = false
		dust_particles.emitting = false
	if is_instance_valid(ember_burst):
		ember_burst.explosiveness = 0.92
		ember_burst.lifetime = 0.72
		ember_burst.scale_amount_min = 0.8
		ember_burst.scale_amount_max = 1.6
		ember_burst.visible = false
		ember_burst.emitting = false
	_prewarm_stage = 3
	set_process(false)


func _ensure_prewarm_cleared() -> void:
	if _prewarm_stage == 1:
		_restore_prewarm_meshes()
		_restore_prewarm_particles()
	elif _prewarm_stage == 2:
		_restore_prewarm_particles()


func _process(delta: float) -> void:
	if DisplayServer.get_name() == "headless":
		_prewarm_stage = 3
		set_process(false)
		return
	if _prewarm_stage == 0:
		# Render all spark variants and VfxLayer primitives/particles at sub-pixel scale during warmup.
		var warm_pos := Vector3(0.0, 1.0, 0.0)
		var warm_scale := Vector3.ONE * 0.002
		var spark_configs := [
			[hit_mesh, hit_mat],
			[block_mesh, block_mat],
			[hit_mesh, counter_mat],
			[hit_mesh, super_mat],
		]
		for i in range(mini(4, pool.size())):
			var spark: MeshInstance3D = pool[i].node
			spark.mesh = spark_configs[i][0]
			spark.material_override = spark_configs[i][1]
			spark.position = warm_pos
			spark.scale = warm_scale
			spark.visible = true
		for node in [flash_quad, shockwave_ring, light_pillar, flying_rock, flying_bullet, muzzle_flash, shell_casing, lightning_arc_bolt, slash_wave, ground_crack, super_rune_circle, impact_flare]:
			if is_instance_valid(node):
				node.position = warm_pos
				node.scale = warm_scale
				node.visible = true
		for bolt in lightning_sky_bolts:
			if is_instance_valid(bolt):
				bolt.position = warm_pos
				bolt.scale = warm_scale
				bolt.visible = true
		if not rock_shards.is_empty():
			var sh_node: MeshInstance3D = rock_shards[0].node
			sh_node.position = warm_pos
			sh_node.scale = warm_scale
			sh_node.visible = true
		if is_instance_valid(burst_particles):
			burst_particles.position = warm_pos
			burst_particles.explosiveness = 1.0
			burst_particles.lifetime = 0.5
			burst_particles.scale_amount_min = 0.002
			burst_particles.scale_amount_max = 0.002
			burst_particles.visible = true
			burst_particles.emitting = true
			burst_particles.restart()
		if is_instance_valid(dust_particles):
			dust_particles.position = warm_pos
			dust_particles.explosiveness = 1.0
			dust_particles.lifetime = 0.5
			dust_particles.scale_amount_min = 0.002
			dust_particles.scale_amount_max = 0.002
			dust_particles.visible = true
			dust_particles.emitting = true
			dust_particles.restart()
		if is_instance_valid(ember_burst):
			ember_burst.position = warm_pos
			ember_burst.explosiveness = 1.0
			ember_burst.lifetime = 0.5
			ember_burst.scale_amount_min = 0.002
			ember_burst.scale_amount_max = 0.002
			ember_burst.visible = true
			ember_burst.emitting = true
			ember_burst.restart()
		_prewarm_stage = 1
		_prewarm_frames = 0
		_prewarm_elapsed = 0.0
	elif _prewarm_stage == 1:
		_prewarm_frames += 1
		if _prewarm_frames >= 2:
			_restore_prewarm_meshes()
			if is_instance_valid(burst_particles):
				burst_particles.visible = false
				burst_particles.emitting = false
				burst_particles.lifetime = 0.01
			if is_instance_valid(dust_particles):
				dust_particles.visible = false
				dust_particles.emitting = false
				dust_particles.lifetime = 0.01
			if is_instance_valid(ember_burst):
				ember_burst.visible = false
				ember_burst.emitting = false
				ember_burst.lifetime = 0.01
			_prewarm_stage = 2
			_prewarm_elapsed = 0.0
	elif _prewarm_stage == 2:
		_prewarm_elapsed += delta
		if _prewarm_elapsed >= 0.025:
			_restore_prewarm_particles()


func _setup_vfx_layer() -> void:
	flash_quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.4, 1.4)
	flash_quad.mesh = qm
	flash_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash_quad_mat = StandardMaterial3D.new()
	flash_quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_quad_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if ResourceLoader.exists(BURST_TEX_PATH):
		flash_quad_mat.albedo_texture = load(BURST_TEX_PATH) as Texture2D
	flash_quad.material_override = flash_quad_mat
	flash_quad.visible = false
	vfx_layer.add_child(flash_quad)

	shockwave_ring = MeshInstance3D.new()
	var rmesh := PlaneMesh.new()
	rmesh.size = Vector2(2.0, 2.0)
	shockwave_ring.mesh = rmesh
	shockwave_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shockwave_mat = StandardMaterial3D.new()
	shockwave_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	shockwave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(AURA_TEX_PATH):
		shockwave_mat.albedo_texture = load(AURA_TEX_PATH) as Texture2D
	shockwave_ring.material_override = shockwave_mat
	shockwave_ring.visible = false
	vfx_layer.add_child(shockwave_ring)

	light_pillar = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.85
	cyl.bottom_radius = 1.25
	cyl.height = 8.0
	cyl.radial_segments = 16
	light_pillar.mesh = cyl
	light_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pillar_mat = StandardMaterial3D.new()
	pillar_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pillar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pillar_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	pillar_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pillar_mat.albedo_color = Color(1.0, 0.78, 0.22, 0.45)
	light_pillar.material_override = pillar_mat
	light_pillar.visible = false
	vfx_layer.add_child(light_pillar)

	burst_particles = CPUParticles3D.new()
	burst_particles.one_shot = true
	burst_particles.explosiveness = 0.92
	burst_particles.amount = 24
	burst_particles.lifetime = 0.55
	burst_particles.emitting = false
	burst_particles.direction = Vector3(0, 1, 0)
	burst_particles.spread = 75.0
	burst_particles.initial_velocity_min = 3.2
	burst_particles.initial_velocity_max = 6.5
	burst_particles.gravity = Vector3(0, -4.0, 0)
	var bp_quad := QuadMesh.new()
	bp_quad.size = Vector2(0.5, 0.65)
	var bp_mat := StandardMaterial3D.new()
	bp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bp_mat.billboard_keep_scale = true
	bp_mat.albedo_color = Color(1.0, 0.84, 0.28, 0.95)
	if ResourceLoader.exists(FLAME_TEX_PATH):
		bp_mat.albedo_texture = load(FLAME_TEX_PATH) as Texture2D
	bp_quad.material = bp_mat
	burst_particles.mesh = bp_quad
	burst_particles.visible = false
	vfx_layer.add_child(burst_particles)

	dust_particles = CPUParticles3D.new()
	dust_particles.one_shot = true
	dust_particles.explosiveness = 0.95
	dust_particles.amount = 14
	dust_particles.lifetime = 0.55
	dust_particles.emitting = false
	dust_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust_particles.direction = Vector3(0, 1, 0)
	dust_particles.spread = 80.0
	dust_particles.initial_velocity_min = 1.4
	dust_particles.initial_velocity_max = 3.0
	dust_particles.gravity = Vector3(0, -1.8, 0)
	dust_particles.scale_amount_min = 0.6
	dust_particles.scale_amount_max = 1.1
	var dp_quad := QuadMesh.new()
	dp_quad.size = Vector2(0.65, 0.65)
	var dp_mat := StandardMaterial3D.new()
	dp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dp_mat.billboard_keep_scale = true
	dp_mat.albedo_color = Color(0.86, 0.80, 0.70, 0.62)
	if ResourceLoader.exists(DUST_TEX_PATH):
		dp_mat.albedo_texture = load(DUST_TEX_PATH) as Texture2D
	dp_quad.material = dp_mat
	dust_particles.mesh = dp_quad
	dust_particles.visible = false
	vfx_layer.add_child(dust_particles)

	if ResourceLoader.exists(ROCK_PROP_PATH):
		var rock_scene := load(ROCK_PROP_PATH) as PackedScene
		if rock_scene != null:
			flying_rock = rock_scene.instantiate() as Node3D
			flying_rock.name = "FlyingRock"
			flying_rock.scale = Vector3.ONE * 1.1
			flying_rock.visible = false
			vfx_layer.add_child(flying_rock)

	var shard_templates: Array[MeshInstance3D] = []
	var temp_shards_root: Node = null
	if ResourceLoader.exists(ROCK_SHARDS_PATH):
		var shards_scene := load(ROCK_SHARDS_PATH) as PackedScene
		if shards_scene != null:
			temp_shards_root = shards_scene.instantiate()
			_collect_mesh_instances(temp_shards_root, shard_templates)

	if not shard_templates.is_empty():
		for i in range(12):
			var tmpl: MeshInstance3D = shard_templates[i % shard_templates.size()]
			var sh := tmpl.duplicate() as MeshInstance3D
			sh.name = "RockShard_%d" % i
			sh.transform = Transform3D.IDENTITY
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sh.visible = false
			vfx_layer.add_child(sh)
			rock_shards.append({
				"node": sh,
				"vel": Vector3.ZERO,
				"ang_vel": Vector3.ZERO,
				"base_scale": 0.85 + float(i % 4) * 0.14,
				"age": 1.5,
				"active": false,
			})
		temp_shards_root.free()
	else:
		var shard_mesh := BoxMesh.new()
		shard_mesh.size = Vector3(0.11, 0.09, 0.09)
		var shard_mat := StandardMaterial3D.new()
		shard_mat.albedo_color = Color("7b7062")
		shard_mat.roughness = 0.92
		for i in range(12):
			var sh := MeshInstance3D.new()
			sh.name = "RockShard_%d" % i
			sh.mesh = shard_mesh
			sh.material_override = shard_mat
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sh.visible = false
			vfx_layer.add_child(sh)
			rock_shards.append({
				"node": sh,
				"vel": Vector3.ZERO,
				"ang_vel": Vector3.ZERO,
				"base_scale": 0.85 + float(i % 4) * 0.14,
				"age": 1.5,
				"active": false,
			})

	# Pistol bullet, glowing tracer, muzzle flash, and brass shell casing live under vfx_layer (never direct children of CombatFeedback).
	flying_bullet = Node3D.new()
	flying_bullet.name = "FlyingBullet"
	flying_bullet.visible = false
	vfx_layer.add_child(flying_bullet)
	if ResourceLoader.exists(BULLET_PROP_PATH):
		var b_scene := load(BULLET_PROP_PATH) as PackedScene
		if b_scene != null:
			var b_node := b_scene.instantiate() as Node3D
			b_node.name = "Bullet45Mesh"
			b_node.scale = Vector3.ONE
			flying_bullet.add_child(b_node)
	else:
		var fb_mesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.028
		cap.height = 0.14
		fb_mesh.mesh = cap
		fb_mesh.rotation_degrees.z = 90.0
		var fb_mat := StandardMaterial3D.new()
		fb_mat.albedo_color = Color(0.95, 0.68, 0.22, 1.0)
		fb_mat.metallic = 0.90
		fb_mat.roughness = 0.20
		fb_mesh.material_override = fb_mat
		flying_bullet.add_child(fb_mesh)

	var tracer := MeshInstance3D.new()
	tracer.name = "BulletTracer"
	var t_box := BoxMesh.new()
	t_box.size = Vector3(0.42, 0.028, 0.028)
	tracer.mesh = t_box
	tracer.position = Vector3(-0.26, 0.0, 0.0)
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var t_mat := StandardMaterial3D.new()
	t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	t_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	t_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	t_mat.albedo_color = Color(1.0, 0.78, 0.28, 0.85)
	tracer.material_override = t_mat
	flying_bullet.add_child(tracer)

	muzzle_flash = Node3D.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.visible = false
	vfx_layer.add_child(muzzle_flash)
	muzzle_flash_mat = StandardMaterial3D.new()
	muzzle_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	muzzle_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	muzzle_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	muzzle_flash_mat.albedo_color = Color(1.0, 0.90, 0.45, 1.0)
	if ResourceLoader.exists(BURST_TEX_PATH):
		muzzle_flash_mat.albedo_texture = load(BURST_TEX_PATH) as Texture2D
	var mf_quad := QuadMesh.new()
	mf_quad.size = Vector2(0.55, 0.55)
	for rot_x in [0.0, 90.0]:
		var mq := MeshInstance3D.new()
		mq.mesh = mf_quad
		mq.rotation_degrees.x = rot_x
		mq.material_override = muzzle_flash_mat
		mq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		muzzle_flash.add_child(mq)

	shell_casing = MeshInstance3D.new()
	shell_casing.name = "ShellCasing"
	var sh_cyl := CylinderMesh.new()
	sh_cyl.top_radius = 0.014
	sh_cyl.bottom_radius = 0.014
	sh_cyl.height = 0.055
	sh_cyl.radial_segments = 10
	sh_cyl.rings = 1
	shell_casing.mesh = sh_cyl
	var sh_mat := StandardMaterial3D.new()
	sh_mat.albedo_color = Color(0.92, 0.72, 0.26, 1.0)
	sh_mat.metallic = 0.88
	sh_mat.roughness = 0.25
	shell_casing.material_override = sh_mat
	shell_casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell_casing.visible = false
	vfx_layer.add_child(shell_casing)

	# Super Finisher 3D Lightning Bolts (p_150_lighting.blend), 3D Energy Slash (Free Slash VFX), Magic Rune Circle & Ground Crack Decal
	var l_shader: Shader = load(LIGHTNING_SHADER_PATH) as Shader if ResourceLoader.exists(LIGHTNING_SHADER_PATH) else null
	var l_core_tex: Texture2D = load(LIGHTNING_CORE_TEX_PATH) as Texture2D if ResourceLoader.exists(LIGHTNING_CORE_TEX_PATH) else null
	if ResourceLoader.exists(LIGHTNING_GLB_PATH):
		var l_scene := load(LIGHTNING_GLB_PATH) as PackedScene
		if l_scene != null:
			var l_root := l_scene.instantiate()
			var sky_names := ["BoltSky_0", "BoltSky_1", "BoltSky_2"]
			var sky_halos := [
				Color(1.0, 0.78, 0.22, 1.0),
				Color(0.26, 0.84, 1.0, 1.0),
				Color(1.0, 0.74, 0.20, 1.0),
			]
			for bi in range(sky_names.size()):
				var found_m := _find_mesh_by_name(l_root, sky_names[bi])
				if found_m != null:
					var bolt := found_m.duplicate() as MeshInstance3D
					bolt.name = sky_names[bi]
					bolt.transform = Transform3D.IDENTITY
					bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					bolt.visible = false
					if l_shader != null and l_core_tex != null:
						var bmat := ShaderMaterial.new()
						bmat.shader = l_shader
						bmat.set_shader_parameter("core_tex", l_core_tex)
						bmat.set_shader_parameter("core_color", Color(1.0, 0.99, 0.92, 1.0))
						bmat.set_shader_parameter("halo_color", sky_halos[bi])
						bmat.set_shader_parameter("intensity", 2.0)
						bmat.set_shader_parameter("flicker_phase", float(bi) * 2.1)
						bolt.material_override = bmat
						lightning_sky_mats.append(bmat)
					else:
						lightning_sky_mats.append(null)
					vfx_layer.add_child(bolt)
					lightning_sky_bolts.append(bolt)
			var arc_m := _find_mesh_by_name(l_root, "BoltArc_0")
			if arc_m != null:
				lightning_arc_bolt = arc_m.duplicate() as MeshInstance3D
				lightning_arc_bolt.name = "BoltArc_0"
				lightning_arc_bolt.transform = Transform3D.IDENTITY
				lightning_arc_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				lightning_arc_bolt.visible = false
				if l_shader != null and l_core_tex != null:
					lightning_arc_mat = ShaderMaterial.new()
					lightning_arc_mat.shader = l_shader
					lightning_arc_mat.set_shader_parameter("core_tex", l_core_tex)
					lightning_arc_mat.set_shader_parameter("core_color", Color(1.0, 0.96, 0.80, 1.0))
					lightning_arc_mat.set_shader_parameter("halo_color", Color(0.32, 0.85, 1.0, 1.0))
					lightning_arc_mat.set_shader_parameter("intensity", 2.1)
					lightning_arc_mat.set_shader_parameter("flicker_phase", 4.3)
					lightning_arc_bolt.material_override = lightning_arc_mat
				vfx_layer.add_child(lightning_arc_bolt)
			l_root.free()

	slash_wave = Node3D.new()
	slash_wave.name = "SuperSlashWave"
	slash_wave.visible = false
	vfx_layer.add_child(slash_wave)
	if ResourceLoader.exists(SLASH_SHADER_PATH) and ResourceLoader.exists(SLASH_NOISE_TEX_PATH) and ResourceLoader.exists(VORONOI_TEX_PATH):
		slash_mat = ShaderMaterial.new()
		slash_mat.shader = load(SLASH_SHADER_PATH) as Shader
		slash_mat.set_shader_parameter("slash_tex", load(SLASH_NOISE_TEX_PATH) as Texture2D)
		slash_mat.set_shader_parameter("erosion_tex", load(VORONOI_TEX_PATH) as Texture2D)
		slash_mat.set_shader_parameter("color_edge", Color(0.24, 0.82, 1.0, 1.0))
		slash_mat.set_shader_parameter("color_core", Color(1.0, 0.86, 0.28, 1.0))
		slash_mat.set_shader_parameter("progress", 0.2)
		slash_mat.set_shader_parameter("intensity", 2.1)
	if ResourceLoader.exists(SLASH_GLB_PATH):
		var s_scene := load(SLASH_GLB_PATH) as PackedScene
		if s_scene != null:
			var s_node := s_scene.instantiate() as Node3D
			var s_meshes: Array[MeshInstance3D] = []
			_collect_mesh_instances(s_node, s_meshes)
			for sm in s_meshes:
				sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if slash_mat != null:
					sm.material_override = slash_mat
			slash_wave.add_child(s_node)

	ground_crack = MeshInstance3D.new()
	ground_crack.name = "SuperGroundCrack"
	var gc_plane := PlaneMesh.new()
	gc_plane.size = Vector2(5.2, 5.2)
	ground_crack.mesh = gc_plane
	ground_crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(CRACK_SHADER_PATH) and ResourceLoader.exists(CRACK_TEX_PATH) and ResourceLoader.exists(CRACK_VEINS_TEX_PATH):
		ground_crack_mat = ShaderMaterial.new()
		ground_crack_mat.shader = load(CRACK_SHADER_PATH) as Shader
		ground_crack_mat.set_shader_parameter("crack_tex", load(CRACK_TEX_PATH) as Texture2D)
		ground_crack_mat.set_shader_parameter("veins_tex", load(CRACK_VEINS_TEX_PATH) as Texture2D)
		ground_crack_mat.set_shader_parameter("glow_color", Color(1.0, 0.48, 0.08, 1.0))
		ground_crack_mat.set_shader_parameter("hot_color", Color(0.65, 0.95, 1.0, 1.0))
		ground_crack_mat.set_shader_parameter("heat", 1.0)
		ground_crack.material_override = ground_crack_mat
	ground_crack.visible = false
	vfx_layer.add_child(ground_crack)

	super_rune_circle = MeshInstance3D.new()
	super_rune_circle.name = "SuperMagicRuneCircle"
	var sr_plane := PlaneMesh.new()
	sr_plane.size = Vector2(4.6, 4.6)
	super_rune_circle.mesh = sr_plane
	super_rune_circle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(MAGIC_SHADER_PATH) and ResourceLoader.exists("res://assets/vfx/impact_ring.png") and ResourceLoader.exists(MAGIC_INNER_TEX_PATH):
		super_rune_mat = ShaderMaterial.new()
		super_rune_mat.shader = load(MAGIC_SHADER_PATH) as Shader
		super_rune_mat.set_shader_parameter("outer_tex", load("res://assets/vfx/impact_ring.png") as Texture2D)
		super_rune_mat.set_shader_parameter("inner_tex", load(MAGIC_INNER_TEX_PATH) as Texture2D)
		super_rune_mat.set_shader_parameter("tint_outer", Color(0.24, 0.80, 1.0, 1.0))
		super_rune_mat.set_shader_parameter("tint_inner", Color(1.0, 0.72, 0.16, 1.0))
		super_rune_mat.set_shader_parameter("opacity", 0.92)
		super_rune_mat.set_shader_parameter("spin_speed", 2.8)
		super_rune_circle.material_override = super_rune_mat
	super_rune_circle.visible = false
	vfx_layer.add_child(super_rune_circle)

	impact_flare = MeshInstance3D.new()
	impact_flare.name = "SuperImpactFlare"
	var fl_quad := QuadMesh.new()
	fl_quad.size = Vector2(4.4, 4.4)
	impact_flare.mesh = fl_quad
	impact_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	impact_flare_mat = StandardMaterial3D.new()
	impact_flare_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	impact_flare_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	impact_flare_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	impact_flare_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	impact_flare_mat.albedo_color = Color(1.0, 0.95, 0.72, 1.0)
	if ResourceLoader.exists(STAR_FLARE_TEX_PATH):
		impact_flare_mat.albedo_texture = load(STAR_FLARE_TEX_PATH) as Texture2D
	impact_flare.material_override = impact_flare_mat
	impact_flare.visible = false
	vfx_layer.add_child(impact_flare)

	ember_burst = CPUParticles3D.new()
	ember_burst.name = "SuperEmberBurst"
	ember_burst.one_shot = true
	ember_burst.explosiveness = 0.92
	ember_burst.amount = 40
	ember_burst.lifetime = 0.72
	ember_burst.emitting = false
	ember_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ember_burst.direction = Vector3(0.0, 1.0, 0.0)
	ember_burst.spread = 115.0
	ember_burst.initial_velocity_min = 4.5
	ember_burst.initial_velocity_max = 11.5
	ember_burst.gravity = Vector3(0.0, -9.5, 0.0)
	ember_burst.scale_amount_min = 0.8
	ember_burst.scale_amount_max = 1.6
	var eb_quad := QuadMesh.new()
	eb_quad.size = Vector2(0.32, 0.32)
	var eb_mat := StandardMaterial3D.new()
	eb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eb_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	eb_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	eb_mat.billboard_keep_scale = true
	eb_mat.albedo_color = Color(1.0, 0.78, 0.26, 1.0)
	if ResourceLoader.exists(STAR_FLARE_TEX_PATH):
		eb_mat.albedo_texture = load(STAR_FLARE_TEX_PATH) as Texture2D
	eb_quad.material = eb_mat
	ember_burst.mesh = eb_quad
	ember_burst.visible = false
	vfx_layer.add_child(ember_burst)


func _find_mesh_by_name(node: Node, target_name: String) -> MeshInstance3D:
	if node is MeshInstance3D and (String(node.name) == target_name or String(node.name).begins_with(target_name)):
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_by_name(child, target_name)
		if found != null:
			return found
	return null


func _collect_mesh_instances(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_mesh_instances(child, out)


func get_pool_size() -> int:
	return pool.size()


func get_total_child_mesh_count() -> int:
	var count := 0
	for child in get_children():
		if child is MeshInstance3D:
			count += 1
	return count


func _acquire_spark() -> Dictionary:
	for entry in pool:
		if not bool(entry.active):
			return entry
	var recycled: Dictionary = pool[pool_cursor % pool.size()]
	pool_cursor += 1
	return recycled


func impact(at: Vector3, blocked: bool, kind: String, is_counter: bool = false) -> void:
	_ensure_prewarm_cleared()
	_any_sparks_active = true
	var chosen_mesh := block_mesh if blocked else hit_mesh
	var chosen_mat := block_mat
	if not blocked:
		if kind == "super_jalwa":
			chosen_mat = super_mat
		elif is_counter:
			chosen_mat = counter_mat
		else:
			chosen_mat = hit_mat

	for i in range(8):
		var entry := _acquire_spark()
		var spark: MeshInstance3D = entry.node
		spark.mesh = chosen_mesh
		spark.material_override = chosen_mat
		spark.position = at
		spark.scale = Vector3.ONE
		spark.visible = true
		var angle := float(i) / 8.0 * TAU
		entry.velocity = Vector3(cos(angle), sin(angle), 0) * (4.2 if is_counter else 3.5)
		entry.age = 0.0
		entry.active = true

	if is_instance_valid(flash_quad):
		flash_quad.position = at + Vector3(0, 0, 0.15)
		flash_quad_mat.albedo_color = Color("7cdeee") if blocked else (Color("ffe66d") if kind == "super_jalwa" else Color("ff9e3d"))
		flash_quad.scale = Vector3.ONE * (1.8 if kind == "super_jalwa" else (1.3 if is_counter else 0.85))
		flash_quad.visible = true
		flash_quad_age = 0.0

	var cue := "block" if blocked else ("kick" if ("kick" in kind or "sweep" in kind or "super" in kind) else "punch")
	play_cue(cue)


func trigger_junoon_burst(at: Vector3, is_jalwa: bool = false) -> void:
	_ensure_prewarm_cleared()
	super_flash_ticks = 26 if is_jalwa else 18
	shockwave_age = 1.0 if is_jalwa else 0.0
	if is_instance_valid(shockwave_ring):
		if is_jalwa:
			shockwave_ring.visible = false
		else:
			shockwave_ring.position = Vector3(at.x, 0.06, at.z)
			shockwave_ring.scale = Vector3(0.6, 1.0, 0.6)
			shockwave_mat.albedo_color = Color(1.0, 0.68, 0.18, 0.95)
			shockwave_ring.visible = true
	if is_instance_valid(light_pillar):
		if is_jalwa:
			# Keep Khan's sky-summon pose and real 3D jagged lightning bolt razor-sharp (no solid pillar washout).
			light_pillar.visible = false
		else:
			light_pillar.position = Vector3(at.x, 4.0, at.z)
			light_pillar.scale = Vector3(0.85, 1.0, 0.85)
			pillar_mat.albedo_color = Color(1.0, 0.84, 0.24, 0.42)
			light_pillar.visible = true
	if is_instance_valid(burst_particles):
		burst_particles.position = at + Vector3(0.0, 1.3, 0.0)
		burst_particles.visible = true
		burst_particles.restart()
		burst_particles.emitting = true
	if is_jalwa:
		sky_dim_factor = 1.0
		camera_shake_amp = maxf(camera_shake_amp, 0.16)
		lightning_startup_age = 0.0
		super_rune_age = 0.0
		if lightning_sky_bolts.size() >= 1 and is_instance_valid(lightning_sky_bolts[0]):
			var b0 := lightning_sky_bolts[0]
			b0.position = Vector3(at.x, 0.05, at.z)
			b0.rotation = Vector3(0.0, 0.35, 0.0)
			b0.scale = Vector3(0.68, 1.0, 0.68)
			b0.visible = true
			if lightning_sky_mats.size() >= 1 and lightning_sky_mats[0] != null:
				lightning_sky_mats[0].set_shader_parameter("intensity", 2.4)
		if is_instance_valid(super_rune_circle):
			super_rune_circle.position = Vector3(at.x, 0.045, at.z)
			super_rune_circle.scale = Vector3(0.35, 1.0, 0.35)
			super_rune_circle.visible = true
			if super_rune_mat != null:
				super_rune_mat.set_shader_parameter("opacity", 1.55)
		play_cue("thunder")
	play_cue("junoon")


func trigger_super_finisher(attacker_pos: Vector3, target_pos: Vector3, dir: float = 1.0, blocked: bool = false) -> void:
	_ensure_prewarm_cleared()
	var d := 1.0 if absf(dir) < 0.01 else signf(dir)
	finisher_age = 0.0
	slash_age = 0.0
	crack_age = 0.0
	flare_age = 0.0
	sky_dim_factor = 1.0
	super_flash_ticks = maxi(super_flash_ticks, 18 if blocked else 26)
	camera_shake_amp = maxf(camera_shake_amp, 0.24 if blocked else 0.42)

	# Twin 3D sky lightning bolts slamming down onto the impact zone
	if lightning_sky_bolts.size() >= 2 and is_instance_valid(lightning_sky_bolts[1]):
		var b1 := lightning_sky_bolts[1]
		b1.position = Vector3(target_pos.x, 0.04, 0.05)
		b1.rotation = Vector3(0.0, 0.4, 0.0)
		b1.scale = Vector3(0.88, 1.05, 0.88)
		b1.visible = true
		if lightning_sky_mats.size() >= 2 and lightning_sky_mats[1] != null:
			lightning_sky_mats[1].set_shader_parameter("intensity", 2.6)
	if lightning_sky_bolts.size() >= 3 and is_instance_valid(lightning_sky_bolts[2]):
		var b2 := lightning_sky_bolts[2]
		b2.position = Vector3(target_pos.x + d * 0.45, 0.04, -0.30)
		b2.rotation = Vector3(0.0, 2.2, 0.0)
		b2.scale = Vector3(0.75, 1.0, 0.75)
		b2.visible = true
		if lightning_sky_mats.size() >= 3 and lightning_sky_mats[2] != null:
			lightning_sky_mats[2].set_shader_parameter("intensity", 2.3)

	# Horizontal discharge arc bridging attacker to target
	if is_instance_valid(lightning_arc_bolt):
		var mid := (attacker_pos + target_pos) * 0.5
		var span := maxf(1.2, absf(target_pos.x - attacker_pos.x))
		lightning_arc_bolt.position = Vector3(mid.x, 1.85, 0.15)
		lightning_arc_bolt.rotation = Vector3(0.0, 0.0 if d > 0.0 else PI, 0.0)
		lightning_arc_bolt.scale = Vector3(span / 3.8, 0.32, 0.32)
		lightning_arc_bolt.visible = true
		if lightning_arc_mat != null:
			lightning_arc_mat.set_shader_parameter("intensity", 2.4)

	# 3D curved energy slash wave sweeping across target
	if is_instance_valid(slash_wave):
		slash_wave.position = Vector3(target_pos.x - d * 0.15, 1.75, 0.18)
		slash_wave.rotation = Vector3(0.22, 0.0 if d > 0.0 else PI, -0.35 * d)
		slash_wave.scale = Vector3.ONE * 0.82
		slash_wave.visible = true
		if slash_mat != null:
			slash_mat.set_shader_parameter("progress", 0.05)
			slash_mat.set_shader_parameter("intensity", 2.3)

	# Glowing molten-electric crater crack decal on Mall Road
	if is_instance_valid(ground_crack):
		ground_crack.position = Vector3(target_pos.x, 0.035, 0.0)
		ground_crack.rotation = Vector3(0.0, 0.45 if d > 0.0 else -0.45, 0.0)
		ground_crack.scale = Vector3(0.65, 1.0, 0.65)
		ground_crack.visible = true
		if ground_crack_mat != null:
			ground_crack_mat.set_shader_parameter("heat", 1.0)

	# Blinding impact star flare + outward ember burst
	if is_instance_valid(impact_flare):
		impact_flare.position = Vector3(target_pos.x, 1.90, 0.45)
		impact_flare.scale = Vector3.ONE * 0.85
		if impact_flare_mat != null:
			impact_flare_mat.albedo_color = Color(0.70, 0.94, 1.0, 1.0) if blocked else Color(1.0, 0.96, 0.72, 1.0)
		impact_flare.visible = true
	if is_instance_valid(ember_burst):
		ember_burst.position = Vector3(target_pos.x, 1.55, 0.1)
		ember_burst.visible = true
		ember_burst.restart()
		ember_burst.emitting = true
	play_cue("super_finisher")


func get_camera_shake_offset() -> Vector2:
	if camera_shake_amp <= 0.002:
		return Vector2.ZERO
	return Vector2(
		sin(_shake_phase * 58.0) * camera_shake_amp,
		cos(_shake_phase * 73.0) * camera_shake_amp * 0.75
	)


func trigger_pickup_dust(at: Vector3) -> void:
	_ensure_prewarm_cleared()
	if is_instance_valid(dust_particles):
		dust_particles.position = at
		dust_particles.visible = true
		dust_particles.restart()
		dust_particles.emitting = true


func set_rock_visual(proj: Dictionary) -> void:
	_ensure_prewarm_cleared()
	if not is_instance_valid(flying_rock):
		return
	if proj.is_empty() or not bool(proj.get("active", false)):
		flying_rock.visible = false
		return
	flying_rock.visible = true
	flying_rock.position = proj.pos
	flying_rock.rotation = Vector3(float(proj.ticks) * 0.45, float(proj.ticks) * 0.32, 0.0)


func shatter_rock(at: Vector3, dir: float = 1.0) -> void:
	_ensure_prewarm_cleared()
	_any_shards_active = true
	if is_instance_valid(flying_rock):
		flying_rock.visible = false
	var d := 1.0 if absf(dir) < 0.01 else signf(dir)
	for i in range(rock_shards.size()):
		var sh: Dictionary = rock_shards[i]
		var node: MeshInstance3D = sh.node
		var angle := float(i) / float(rock_shards.size()) * TAU + 0.27 * float(i % 3)
		var base_s := float(sh.get("base_scale", 1.0))
		node.position = at + Vector3(cos(angle) * 0.08, float(i % 3) * 0.05, sin(angle) * 0.08)
		node.rotation = Vector3(i * 0.7, i * 1.1, i * 0.4)
		node.scale = Vector3.ONE * base_s
		node.visible = true
		var fwd := d * (1.2 + float(i % 4) * 0.85)
		sh.vel = Vector3(fwd + cos(angle) * 2.6, 2.2 + float(i % 4) * 1.05, sin(angle) * 2.4)
		sh.ang_vel = Vector3(7.0 + float(i % 3) * 3.0, 9.0 - float(i % 2) * 4.0, 6.0 + float(i % 4) * 2.5)
		sh.age = 0.0
		sh.active = true
	trigger_pickup_dust(at)
	play_cue("rock")


func trigger_muzzle_flash(at: Vector3, dir: float = 1.0) -> void:
	_ensure_prewarm_cleared()
	var d := 1.0 if absf(dir) < 0.01 else signf(dir)
	if is_instance_valid(muzzle_flash):
		muzzle_flash.position = at + Vector3(d * 0.06, 0.0, 0.0)
		muzzle_flash.rotation = Vector3(0.0, 0.0 if d > 0.0 else PI, 0.0)
		muzzle_flash.scale = Vector3.ONE * 0.95
		if muzzle_flash_mat != null:
			muzzle_flash_mat.albedo_color.a = 1.0
		muzzle_flash.visible = true
		muzzle_flash_age = 0.0
	if is_instance_valid(shell_casing):
		shell_casing.position = at - Vector3(d * 0.16, 0.0, 0.0)
		shell_casing.rotation = Vector3(0.2, 0.4, 0.8)
		shell_casing.scale = Vector3.ONE
		shell_casing.visible = true
		shell_vel = Vector3(-d * 1.4, 3.2, 1.8)
		shell_ang_vel = Vector3(14.0, 18.0, 11.0)
		shell_age = 0.0
		shell_active = true
	play_cue("gunshot")


func set_bullet_visual(proj: Dictionary) -> void:
	_ensure_prewarm_cleared()
	if not is_instance_valid(flying_bullet):
		return
	if proj.is_empty() or not bool(proj.get("active", false)):
		flying_bullet.visible = false
		return
	var d := float(proj.get("direction", 1.0))
	flying_bullet.visible = true
	flying_bullet.position = proj.pos
	flying_bullet.scale = Vector3.ONE
	flying_bullet.rotation = Vector3(float(proj.ticks) * 0.65, 0.0 if d > 0.0 else PI, 0.0)


func bullet_impact(at: Vector3, blocked: bool, _dir: float = 1.0) -> void:
	_ensure_prewarm_cleared()
	if is_instance_valid(flying_bullet):
		flying_bullet.visible = false
	impact(at, blocked, "pistol_shoot", false)


func step(delta: float) -> void:
	super_flash_ticks = maxi(0, super_flash_ticks - 1)
	if _any_sparks_active:
		var any_spark := false
		for entry in pool:
			if not bool(entry.active):
				continue
			entry.age = float(entry.age) + delta
			var spark: MeshInstance3D = entry.node
			if float(entry.age) >= SPARK_LIFE:
				entry.active = false
				spark.visible = false
			else:
				any_spark = true
				spark.position += (entry.velocity as Vector3) * delta
				spark.scale = Vector3.ONE * (1.0 - float(entry.age) / SPARK_LIFE)
		_any_sparks_active = any_spark

	if is_instance_valid(flash_quad) and flash_quad.visible and _prewarm_stage != 1:
		flash_quad_age += delta
		if flash_quad_age >= 0.14:
			flash_quad.visible = false
		else:
			var t := flash_quad_age / 0.14
			flash_quad_mat.albedo_color.a = 1.0 - t
			flash_quad.scale *= (1.0 + delta * 3.5)

	if shockwave_age < 0.45:
		shockwave_age += delta
		var t := clampf(shockwave_age / 0.45, 0.0, 1.0)
		if is_instance_valid(shockwave_ring):
			var s := lerpf(0.6, 4.8, t)
			shockwave_ring.scale = Vector3(s, 1.0, s)
			shockwave_ring.rotation.y += delta * 5.0
			shockwave_mat.albedo_color.a = (1.0 - t) * 0.95
			shockwave_ring.visible = t < 1.0
		if is_instance_valid(light_pillar):
			var ps := lerpf(1.1, 0.1, t)
			light_pillar.scale = Vector3(ps, 1.0 + t * 0.4, ps)
			pillar_mat.albedo_color.a = (1.0 - t) * 0.55
			light_pillar.visible = t < 1.0

	if _any_shards_active:
		var any_shard := false
		for sh in rock_shards:
			if not bool(sh.active):
				continue
			sh.age = float(sh.age) + delta
			var node: MeshInstance3D = sh.node
			if float(sh.age) >= 1.15:
				sh.active = false
				node.visible = false
			else:
				any_shard = true
				var vel: Vector3 = sh.vel
				vel.y -= 18.0 * delta
				var next_pos := node.position + vel * delta
				if next_pos.y <= 0.06:
					next_pos.y = 0.06
					if vel.y < -0.35:
						vel.y = -vel.y * 0.38
						vel.x *= 0.76
						vel.z *= 0.76
						sh.ang_vel = (sh.ang_vel as Vector3) * 0.65
					else:
						vel.y = 0.0
						vel.x *= 0.85
						vel.z *= 0.85
				sh.vel = vel
				node.position = next_pos
				node.rotation += (sh.ang_vel as Vector3) * delta
				var base_s := float(sh.get("base_scale", 1.0))
				var life_frac := float(sh.age) / 1.15
				node.scale = Vector3.ONE * maxf(0.01, base_s * (1.0 - smoothstep(0.75, 1.0, life_frac)))
		_any_shards_active = any_shard

	if is_instance_valid(muzzle_flash) and muzzle_flash.visible and _prewarm_stage != 1:
		muzzle_flash_age += delta
		if muzzle_flash_age >= 0.09:
			muzzle_flash.visible = false
		else:
			var mt := muzzle_flash_age / 0.09
			if muzzle_flash_mat != null:
				muzzle_flash_mat.albedo_color.a = 1.0 - mt
			var ms := lerpf(0.95, 1.55, mt)
			muzzle_flash.scale = Vector3.ONE * ms

	if shell_active and is_instance_valid(shell_casing):
		shell_age += delta
		if shell_age >= 0.85:
			shell_active = false
			shell_casing.visible = false
		else:
			shell_vel.y -= 18.0 * delta
			var next_sp := shell_casing.position + shell_vel * delta
			if next_sp.y <= 0.03:
				next_sp.y = 0.03
				if shell_vel.y < -0.25:
					shell_vel.y = -shell_vel.y * 0.42
					shell_vel.x *= 0.72
					shell_vel.z *= 0.72
				else:
					shell_vel.y = 0.0
					shell_vel.x *= 0.85
					shell_vel.z *= 0.85
			shell_casing.position = next_sp
			shell_casing.rotation += shell_ang_vel * delta

	_shake_phase += delta
	camera_shake_amp = move_toward(camera_shake_amp, 0.0, delta * 1.45)
	sky_dim_factor = move_toward(sky_dim_factor, 0.0, delta * 1.85)

	if lightning_startup_age < 0.34:
		lightning_startup_age += delta
		var lt := clampf(lightning_startup_age / 0.34, 0.0, 1.0)
		if lightning_sky_bolts.size() >= 1 and is_instance_valid(lightning_sky_bolts[0]):
			lightning_sky_bolts[0].visible = lt < 1.0
			lightning_sky_bolts[0].rotation.y += delta * 14.0
			if lightning_sky_mats.size() >= 1 and lightning_sky_mats[0] != null:
				lightning_sky_mats[0].set_shader_parameter("intensity", lerpf(2.4, 0.0, lt))

	if super_rune_age < 0.65:
		super_rune_age += delta
		var rt := clampf(super_rune_age / 0.65, 0.0, 1.0)
		if is_instance_valid(super_rune_circle):
			var rs := lerpf(0.35, 1.35, smoothstep(0.0, 0.45, rt))
			super_rune_circle.scale = Vector3(rs, 1.0, rs)
			super_rune_circle.visible = rt < 1.0
			if super_rune_mat != null:
				super_rune_mat.set_shader_parameter("opacity", (1.0 - smoothstep(0.55, 1.0, rt)) * 1.5)

	if finisher_age < 0.46:
		finisher_age += delta
		var ft := clampf(finisher_age / 0.46, 0.0, 1.0)
		for bi in [1, 2]:
			if lightning_sky_bolts.size() > bi and is_instance_valid(lightning_sky_bolts[bi]):
				lightning_sky_bolts[bi].visible = ft < 1.0
				lightning_sky_bolts[bi].rotation.y += delta * (18.0 if bi == 1 else -15.0)
				if lightning_sky_mats.size() > bi and lightning_sky_mats[bi] != null:
					lightning_sky_mats[bi].set_shader_parameter("intensity", lerpf(2.6, 0.0, ft))
		if is_instance_valid(lightning_arc_bolt):
			lightning_arc_bolt.visible = ft < 0.85
			if lightning_arc_mat != null:
				lightning_arc_mat.set_shader_parameter("intensity", lerpf(2.4, 0.0, clampf(ft / 0.85, 0.0, 1.0)))

	if slash_age < 0.38:
		slash_age += delta
		var st := clampf(slash_age / 0.38, 0.0, 1.0)
		if is_instance_valid(slash_wave):
			slash_wave.visible = st < 1.0
			slash_wave.scale = Vector3.ONE * lerpf(0.82, 1.38, st)
			slash_wave.rotation.y += delta * 5.2
			if slash_mat != null:
				slash_mat.set_shader_parameter("progress", st)
				slash_mat.set_shader_parameter("intensity", lerpf(2.4, 0.4, st))

	if crack_age < 1.65:
		crack_age += delta
		var ct := clampf(crack_age / 1.65, 0.0, 1.0)
		if is_instance_valid(ground_crack):
			ground_crack.visible = ct < 1.0
			var cs := lerpf(0.65, 1.08, smoothstep(0.0, 0.14, ct))
			ground_crack.scale = Vector3(cs, 1.0, cs)
			if ground_crack_mat != null:
				ground_crack_mat.set_shader_parameter("heat", 1.0 - smoothstep(0.25, 1.0, ct))

	if flare_age < 0.24:
		flare_age += delta
		var flt := clampf(flare_age / 0.24, 0.0, 1.0)
		if is_instance_valid(impact_flare):
			impact_flare.visible = flt < 1.0
			impact_flare.scale = Vector3.ONE * lerpf(0.85, 1.95, flt)
			if impact_flare_mat != null:
				impact_flare_mat.albedo_color.a = 1.0 - flt


func clear() -> void:
	_ensure_prewarm_cleared()
	super_flash_ticks = 0
	shockwave_age = 1.0
	flash_quad_age = 1.0
	muzzle_flash_age = 1.0
	shell_active = false
	shell_age = 2.0
	lightning_startup_age = 2.0
	finisher_age = 2.0
	slash_age = 2.0
	crack_age = 3.0
	flare_age = 2.0
	super_rune_age = 2.0
	sky_dim_factor = 0.0
	camera_shake_amp = 0.0
	_shake_phase = 0.0
	_any_sparks_active = false
	_any_shards_active = false
	if is_instance_valid(flash_quad):
		flash_quad.visible = false
	if is_instance_valid(shockwave_ring):
		shockwave_ring.visible = false
	if is_instance_valid(light_pillar):
		light_pillar.visible = false
	if is_instance_valid(flying_rock):
		flying_rock.visible = false
	if is_instance_valid(flying_bullet):
		flying_bullet.visible = false
	if is_instance_valid(muzzle_flash):
		muzzle_flash.visible = false
	if is_instance_valid(shell_casing):
		shell_casing.visible = false
	for bolt in lightning_sky_bolts:
		if is_instance_valid(bolt):
			bolt.visible = false
	if is_instance_valid(lightning_arc_bolt):
		lightning_arc_bolt.visible = false
	if is_instance_valid(slash_wave):
		slash_wave.visible = false
	if is_instance_valid(ground_crack):
		ground_crack.visible = false
	if is_instance_valid(super_rune_circle):
		super_rune_circle.visible = false
	if is_instance_valid(impact_flare):
		impact_flare.visible = false
	if is_instance_valid(ember_burst):
		ember_burst.emitting = false
		ember_burst.visible = false
	if is_instance_valid(burst_particles):
		burst_particles.emitting = false
		burst_particles.visible = false
	if is_instance_valid(dust_particles):
		dust_particles.emitting = false
		dust_particles.visible = false
	for sh in rock_shards:
		sh.active = false
		sh.node.visible = false
	for entry in pool:
		entry.active = false
		entry.age = 0.0
		var spark: MeshInstance3D = entry.node
		spark.visible = false
	for voice in voices:
		voice.stop()

func play_cue(kind: String) -> void:
	if muted or not sounds.has(kind):
		return
	var voice = voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = sounds[kind]
	voice.play()


func play_voice_path(path: String) -> void:
	if muted or path.is_empty():
		return
	var stream: AudioStream = voice_cache.get(path, null) as AudioStream
	if stream == null and ResourceLoader.exists(path):
		stream = load(path) as AudioStream
		if stream != null:
			voice_cache[path] = stream
	if stream == null:
		return
	var voice = voices[voice_index % voices.size()]
	voice_index += 1
	voice.stream = stream
	voice.play()

func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	if kind == "gunshot":
		var g_len := 0.22
		var g_frames := int(rate * g_len)
		var g_data := PackedByteArray()
		g_data.resize(g_frames * 2)
		var g_rng := RandomNumberGenerator.new()
		g_rng.seed = 1911
		for i in range(g_frames):
			var t := float(i) / float(rate)
			var env := minf(t / 0.0015, 1.0)
			var crack := g_rng.randf_range(-1.0, 1.0) * exp(-t * 28.0) * 0.88
			var punch := sin(TAU * 155.0 * t) * exp(-t * 22.0) * 0.52
			var slide_click := sin(TAU * 1650.0 * maxf(0.0, t - 0.035)) * exp(-maxf(0.0, t - 0.035) * 95.0) * (0.24 if t >= 0.035 else 0.0)
			var s := int(clampf((crack + punch + slide_click) * env, -1.0, 1.0) * 32767.0)
			g_data.encode_s16(i * 2, s)
		var gs := AudioStreamWAV.new()
		gs.format = AudioStreamWAV.FORMAT_16_BITS
		gs.mix_rate = rate
		gs.data = g_data
		return gs
	if kind == "thunder" or kind == "super_finisher":
		var is_fin := kind == "super_finisher"
		var t_len := 0.65 if is_fin else 0.55
		var t_frames := int(rate * t_len)
		var t_data := PackedByteArray()
		t_data.resize(t_frames * 2)
		var t_rng := RandomNumberGenerator.new()
		t_rng.seed = 4096 if is_fin else 2048
		var lp_noise := 0.0
		for i in range(t_frames):
			var t := float(i) / float(rate)
			var attack := minf(t / 0.002, 1.0)
			var raw_n := t_rng.randf_range(-1.0, 1.0)
			lp_noise = lerpf(lp_noise, raw_n, 0.12)
			var zap := raw_n * exp(-t * 24.0) * 0.72
			var rumble := lp_noise * exp(-t * 3.8) * 0.75
			var sub_freq := lerpf(92.0, 44.0, clampf(t / t_len, 0.0, 1.0))
			var sub := sin(TAU * sub_freq * t) * exp(-t * (4.2 if is_fin else 5.5)) * (0.68 if is_fin else 0.48)
			var ring := sin(TAU * 410.0 * t) * exp(-t * 14.0) * (0.28 if is_fin else 0.14)
			var s := int(clampf((zap + rumble + sub + ring) * attack, -1.0, 1.0) * 32767.0)
			t_data.encode_s16(i * 2, s)
		var ts := AudioStreamWAV.new()
		ts.format = AudioStreamWAV.FORMAT_16_BITS
		ts.mix_rate = rate
		ts.data = t_data
		return ts
	var length := 0.35 if kind in ["round", "junoon"] else (0.18 if kind == "rock" else 0.13)
	var frames := int(rate * length)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng = RandomNumberGenerator.new()
	rng.seed = 810
	var low_noise := 0.0
	var freq_map := {"punch": 95.0, "kick": 65.0, "block": 520.0, "round": 330.0, "junoon": 220.0, "rock": 78.0}
	var frequency: float = float(freq_map.get(kind, 120.0))
	for i in range(frames):
		var time = float(i) / rate
		var envelope = pow(1.0 - float(i) / frames, 2.2 if kind == "junoon" else 3.0) * minf(time * 1000.0, 1.0)
		low_noise = lerpf(low_noise, rng.randf_range(-1.0, 1.0), 0.4)
		var tone = sin(TAU * frequency * time) * (0.7 if kind in ["round", "junoon"] else 0.45)
		if kind == "junoon":
			tone += sin(TAU * frequency * 1.5 * time) * 0.35 + sin(TAU * frequency * 2.0 * time) * 0.25
		var sample = int(clampf((tone + low_noise * 0.5) * envelope, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	return stream
