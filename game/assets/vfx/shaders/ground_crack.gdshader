shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D crack_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D veins_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 glow_color : source_color = vec4(1.0, 0.46, 0.06, 1.0);
uniform vec4 hot_color : source_color = vec4(0.55, 0.94, 1.0, 1.0);
uniform float heat : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 c1 = texture(crack_tex, UV);
	vec4 c2 = texture(veins_tex, UV);
	float l1 = max(c1.r, max(c1.g, c1.b)) * c1.a;
	float l2 = max(c2.r, max(c2.g, c2.b)) * c2.a;
	float dist = length(UV - vec2(0.5));
	float radial = 1.0 - smoothstep(0.28, 0.48, dist);

	float crack_mask = clamp((l1 * 0.95 + l2 * 0.70) * radial, 0.0, 1.0);
	float char_ring = smoothstep(0.08, 0.35, crack_mask) * (1.0 - smoothstep(0.32, 0.48, dist));
	float vein_glow = smoothstep(0.32, 0.78, crack_mask) * heat;

	float flicker = 0.88 + 0.12 * sin(TIME * 22.0 + l2 * 9.0);
	vec3 dark_asphalt = vec3(0.05, 0.05, 0.06);
	vec3 emissive_vein = mix(glow_color.rgb, hot_color.rgb, smoothstep(0.42, 0.88, vein_glow));
	vec3 col = mix(dark_asphalt, emissive_vein * (1.5 * flicker), vein_glow);

	ALBEDO = col;
	ALPHA = clamp((char_ring * 0.82 + vein_glow * 0.95) * smoothstep(0.0, 0.25, heat + 0.15), 0.0, 0.95);
}
