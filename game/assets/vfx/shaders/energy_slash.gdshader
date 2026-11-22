shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D slash_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D erosion_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 color_edge : source_color = vec4(0.25, 0.82, 1.0, 1.0);
uniform vec4 color_core : source_color = vec4(1.0, 0.88, 0.35, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.25;
uniform float intensity : hint_range(0.0, 3.0) = 1.8;

void fragment() {
	vec2 uv_s = vec2(UV.x * 1.4 - progress * 1.6, UV.y);
	float s_n = texture(slash_tex, uv_s).r;
	float e_n = texture(erosion_tex, vec2(UV.x * 2.2 - progress * 1.2, UV.y * 1.8)).r;

	float edge_fade = smoothstep(0.0, 0.18, UV.y) * smoothstep(1.0, 0.72, UV.y);
	float life_fade = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.55, 1.0, progress));
	float mask = smoothstep(0.18 + progress * 0.45, 0.72, s_n * 0.65 + e_n * 0.55) * edge_fade * life_fade;

	vec3 col = mix(color_edge.rgb, color_core.rgb, smoothstep(0.25, 0.78, s_n));
	ALBEDO = col * intensity;
	ALPHA = clamp(mask * 1.35, 0.0, 1.0);
}
