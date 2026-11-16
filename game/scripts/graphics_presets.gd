class_name GraphicsPresets
extends RefCounted
## Low / Medium / High quality presets for gl_compatibility and forward_plus.

const PRESETS := ["low", "medium", "high"]


static func normalize_name(preset_name: String) -> String:
	var key := preset_name.strip_edges().to_lower()
	if key in PRESETS:
		return key
	return "medium"


static func next_preset(current: String) -> String:
	var norm := normalize_name(current)
	var idx := PRESETS.find(norm)
	return PRESETS[(idx + 1) % PRESETS.size()]


static func apply(stage: Node, preset_name: String) -> String:
	var preset := normalize_name(preset_name)
	var renderer := RenderingServer.get_current_rendering_method()
	var is_forward := renderer == "forward_plus"

	var sun: DirectionalLight3D = stage.get("sun") as DirectionalLight3D
	var world_env: WorldEnvironment = stage.get("world_env") as WorldEnvironment
	var env: Environment = world_env.environment if world_env != null else null
	var vp: Viewport = stage.get_viewport()

	if preset == "low":
		if sun != null:
			sun.shadow_enabled = false
		if vp != null:
			vp.msaa_3d = Viewport.MSAA_DISABLED
		if env != null:
			env.ssao_enabled = false
			env.glow_enabled = false
			env.fog_enabled = false
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	elif preset == "medium":
		if sun != null:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 38.0
		if vp != null:
			vp.msaa_3d = Viewport.MSAA_2X
		if env != null:
			env.ssao_enabled = false
			env.glow_enabled = true
			env.glow_intensity = 0.22
			env.glow_bloom = 0.06
			env.glow_hdr_threshold = 1.15
			env.fog_enabled = is_forward
			env.fog_light_color = Color("edd5ac")
			env.fog_density = 0.004
			env.tonemap_mode = Environment.TONE_MAPPER_AGX if is_forward else Environment.TONE_MAPPER_LINEAR
	else:  # "high"
		if sun != null:
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 45.0
		if vp != null:
			vp.msaa_3d = Viewport.MSAA_4X
		if env != null:
			env.ssao_enabled = is_forward
			env.ssao_radius = 1.0
			env.ssao_intensity = 1.4
			env.glow_enabled = true
			env.glow_intensity = 0.28
			env.glow_bloom = 0.08
			env.glow_hdr_threshold = 1.1
			env.fog_enabled = true
			env.fog_light_color = Color("edd5ac")
			env.fog_density = 0.005
			env.tonemap_mode = Environment.TONE_MAPPER_AGX if is_forward else Environment.TONE_MAPPER_ACES

	if "quality_preset" in stage:
		stage.set("quality_preset", preset)
	return preset
