shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D noise_tex;
uniform vec3 deep_color : source_color = vec3(0.008, 0.09, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.32, 0.42);
uniform vec3 foam_color : source_color = vec3(0.92, 0.96, 1.0);

varying vec3 world_pos;
varying float wave_h;

float dir_wave(vec2 p, vec2 dir, float freq, float speed, float t) {
	return sin(dot(p, normalize(dir)) * freq + t * speed);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	vec2 p = world_pos.xz;
	// A few crossing swells plus low-frequency noise chop.
	float h = 0.0;
	h += dir_wave(p, vec2(1.0, 0.35), 0.030, 1.1, t) * 0.55;
	h += dir_wave(p, vec2(-0.4, 1.0), 0.052, 0.9, t) * 0.35;
	h += dir_wave(p, vec2(0.7, -0.8), 0.085, 1.6, t) * 0.18;
	h += (texture(noise_tex, p * 0.0016 + vec2(t * 0.008)).r - 0.5) * 1.0;
	VERTEX.y += h;
	wave_h = h;
}

void fragment() {
	vec2 p = world_pos.xz;
	// Two scrolling noise samples fake small ripple normals.
	float n1 = texture(noise_tex, p * 0.020 + vec2(TIME * 0.021, TIME * 0.014)).r;
	float n2 = texture(noise_tex, p * 0.043 - vec2(TIME * 0.016, TIME * 0.024)).r;
	vec3 nm_world = normalize(vec3((n1 - 0.5) * 0.55, 1.0, (n2 - 0.5) * 0.55));
	NORMAL = normalize((VIEW_MATRIX * vec4(nm_world, 0.0)).xyz);

	float depth_mix = clamp(wave_h * 0.30 + 0.45, 0.0, 1.0);
	vec3 col = mix(deep_color, shallow_color, depth_mix);
	// Whitecaps only on the very highest crests.
	float foam = smoothstep(1.25, 1.75, wave_h + (n2 - 0.5) * 0.5);
	col = mix(col, foam_color, foam * 0.4);

	ALBEDO = col;
	ROUGHNESS = mix(0.04, 0.30, foam);
	SPECULAR = 0.75;
}
