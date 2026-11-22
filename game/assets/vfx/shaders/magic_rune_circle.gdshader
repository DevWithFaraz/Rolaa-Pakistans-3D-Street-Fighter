shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform sampler2D outer_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D inner_tex : filter_linear_mipmap, repeat_disable;
uniform vec4 tint_outer : source_color = vec4(0.95, 0.24, 0.02, 1.0);
uniform vec4 tint_inner : source_color = vec4(1.0, 0.72, 0.14, 1.0);
uniform float opacity : hint_range(0.0, 2.0) = 1.0;
uniform float spin_speed = 1.4;

vec2 rotate_uv(vec2 uv, float angle) {
	vec2 c = uv - vec2(0.5);
	float s = sin(angle);
	float co = cos(angle);
	return vec2(c.x * co - c.y * s, c.x * s + c.y * co) + vec2(0.5);
}

void fragment() {
	vec2 uv_o = rotate_uv(UV, TIME * spin_speed);
	vec2 uv_i = rotate_uv(UV, -TIME * (spin_speed * 1.45));
	vec4 o_samp = texture(outer_tex, uv_o);
	vec4 i_samp = texture(inner_tex, uv_i);

	float o_luma = max(o_samp.r, max(o_samp.g, o_samp.b)) * o_samp.a;
	float i_luma = max(i_samp.r, max(i_samp.g, i_samp.b)) * i_samp.a;
	float dist = length(UV - vec2(0.5));
	float radial = (1.0 - smoothstep(0.40, 0.49, dist)) * smoothstep(0.06, 0.22, dist);
	float pulse = 0.86 + 0.14 * sin(TIME * 10.0);

	float energy = clamp((o_luma * 0.85 + i_luma * 0.75) * radial * pulse, 0.0, 1.0);
	vec3 col = mix(tint_outer.rgb, tint_inner.rgb, smoothstep(0.25, 0.78, i_luma + o_luma * 0.4));

	ALBEDO = col * (1.15 * pulse);
	ALPHA = clamp(energy * opacity * 0.92, 0.0, 0.92);
}
