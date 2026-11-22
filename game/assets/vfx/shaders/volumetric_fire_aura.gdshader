shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D flow_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float scroll_speed = 2.2;
uniform float uv_tiles_x = 2.6;
uniform vec4 color_outer : source_color = vec4(0.86, 0.10, 0.01, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.44, 0.03, 1.0);
uniform vec4 color_core : source_color = vec4(1.0, 0.92, 0.42, 1.0);

void vertex() {
	float height_t = 1.0 - UV.y;
	float wave = sin(VERTEX.y * 4.5 - TIME * 11.0 + UV.x * 12.566) * 0.065;
	float wave2 = cos(VERTEX.y * 7.5 - TIME * 15.0 - UV.x * 6.283) * 0.032;
	VERTEX.xz += NORMAL.xz * (wave + wave2) * clamp(height_t * 1.4, 0.0, 1.0);
}

void fragment() {
	vec2 uv1 = vec2(UV.x * uv_tiles_x, UV.y * 1.25 + TIME * scroll_speed);
	vec2 uv2 = vec2(UV.x * (uv_tiles_x * 1.65) + 0.37, UV.y * 2.0 + TIME * (scroll_speed * 1.4));
	float base_n = texture(noise_tex, uv2).r;
	float streak = texture(flow_tex, uv1 + vec2((base_n - 0.5) * 0.28, -base_n * 0.16)).r;

	// Godot CylinderMesh: UV.y = 1.0 at bottom, 0.0 at top.
	float bottom_fade = smoothstep(1.0, 0.82, UV.y);
	float top_fade = smoothstep(0.02, 0.56, UV.y);
	float height_mask = bottom_fade * top_fade;

	// Emphasize fiery silhouettes around the character's sides/shoulders while leaving face/chest readable!
	float ndv = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim_bias = mix(1.25, 0.45, smoothstep(0.15, 0.85, ndv));
	float edge_soft = smoothstep(0.04, 0.30, ndv);

	float raw_fire = (streak * 0.62 + base_n * 0.56) * height_mask * rim_bias;
	float flame_alpha = smoothstep(0.26, 0.64, raw_fire) * edge_soft;
	float flicker = 0.88 + 0.12 * sin(TIME * 24.0 + UV.x * 18.0);

	vec3 col = mix(color_outer.rgb, color_mid.rgb, smoothstep(0.24, 0.56, raw_fire));
	col = mix(col, color_core.rgb, smoothstep(0.58, 0.88, raw_fire));

	ALBEDO = col * (1.10 * flicker);
	ALPHA = clamp(flame_alpha * intensity * 0.82, 0.0, 0.88);
}
