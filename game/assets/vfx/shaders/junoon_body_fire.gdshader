shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_tex : filter_linear_mipmap, repeat_enable;
uniform float intensity : hint_range(0.0, 2.0) = 0.0;
uniform float scroll_speed = 2.4;
uniform vec4 color_outer : source_color = vec4(0.88, 0.10, 0.01, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.44, 0.03, 1.0);
uniform vec4 color_core : source_color = vec4(1.0, 0.90, 0.36, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (intensity <= 0.001) {
		ALPHA = 0.0;
		ALBEDO = vec3(0.0);
	} else {
		vec3 n = normalize(NORMAL);
		vec3 v = normalize(VIEW);
		float fresnel = pow(1.0 - clamp(abs(dot(n, v)), 0.0, 1.0), 1.9);

		vec2 uv_a = vec2(world_pos.x * 0.65 + world_pos.z * 0.65, world_pos.y * 0.55 - TIME * scroll_speed);
		vec2 uv_b = vec2(world_pos.x * 1.15 - world_pos.z * 0.95, world_pos.y * 0.92 - TIME * (scroll_speed * 1.45));
		float n1 = texture(noise_tex, uv_a).r;
		float n2 = texture(flow_tex, uv_b + vec2(n1 * 0.22, -n1 * 0.14)).r;
		float flame = clamp(n1 * 0.52 + n2 * 0.68, 0.0, 1.0);

		float rim_lick = smoothstep(0.24, 0.72, flame + fresnel * 0.48) * (fresnel * 1.25 + 0.12 * smoothstep(0.62, 0.94, flame));
		float flicker = 0.88 + 0.12 * sin(TIME * 26.0 + world_pos.y * 5.0);
		float heat = clamp(rim_lick * flicker, 0.0, 1.0);

		vec3 col = mix(color_outer.rgb, color_mid.rgb, smoothstep(0.15, 0.55, heat));
		col = mix(col, color_core.rgb, smoothstep(0.62, 0.94, heat));

		ALBEDO = col;
		ALPHA = clamp(heat * intensity * 0.85, 0.0, 0.88);
	}
}
