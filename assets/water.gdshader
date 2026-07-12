shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.12, 0.22);
uniform vec3 crest_color : source_color = vec3(0.12, 0.34, 0.45);

varying float wave_h;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float w = sin(wp.x * 0.045 + t * 1.2) * 0.55
		+ cos(wp.z * 0.038 + t * 0.9) * 0.45
		+ sin((wp.x + wp.z) * 0.018 + t * 0.5) * 0.75;
	VERTEX.y += w;
	wave_h = w;
}

void fragment() {
	float f = clamp(wave_h * 0.35 + 0.45, 0.0, 1.0);
	ALBEDO = mix(deep_color, crest_color, f);
	ROUGHNESS = 0.12;
	SPECULAR = 0.7;
}
