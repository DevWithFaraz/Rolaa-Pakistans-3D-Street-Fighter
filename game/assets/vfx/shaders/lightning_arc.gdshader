shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform sampler2D core_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.92, 1.0);
uniform vec4 halo_color : source_color = vec4(0.28, 0.82, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.6;
uniform float flicker_phase = 0.0;

void fragment() {
	float ndv = clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0);
	float core_mask = smoothstep(0.28, 0.82, ndv);
	float surge = texture(core_tex, vec2(UV.x * 2.0, UV.y * 3.0 - TIME * 14.0)).r;
	float strobe = 0.72 + 0.28 * sin(TIME * 75.0 + flicker_phase) * cos(TIME * 37.0 + UV.y * 10.0);

	vec3 col = mix(halo_color.rgb, core_color.rgb, clamp(core_mask + surge * 0.45, 0.0, 1.0));
	ALBEDO = col * (intensity * strobe * (1.05 + surge * 0.55));
	ALPHA = clamp((0.68 + 0.32 * surge) * min(intensity, 1.0) * strobe, 0.0, 1.0);
}
