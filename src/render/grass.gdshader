shader_type spatial;

// Original grass shader: mowing stripes, layered detail noise, goal-mouth wear
// and a subtle wind shimmer. All colors are procedural; no third-party assets.

uniform vec4 color_a : source_color = vec4(0.12, 0.42, 0.10, 1.0);
uniform vec4 color_b : source_color = vec4(0.17, 0.52, 0.13, 1.0);
uniform vec4 wear_color : source_color = vec4(0.38, 0.30, 0.14, 1.0);
uniform sampler2D detail_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float wear_strength = 1.0;
uniform float wind_strength = 0.015;
uniform float stripe_count = 16.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Subtle wind: a slow travelling shimmer in the vertex positions.
	float wind = sin(TIME * 1.6 + world_pos.z * 0.35 + world_pos.x * 0.22) * wind_strength;
	VERTEX.x += wind;
	VERTEX.z += wind * 0.6;
}

void fragment() {
	float stripes = step(0.5, fract(world_pos.x * stripe_count / 105.0));
	vec3 base = mix(color_a.rgb, color_b.rgb, stripes);
	float detail = texture(detail_tex, UV * 28.0).r;
	float detail2 = texture(detail_tex, UV * 90.0).g;
	base *= mix(0.86, 1.10, detail);
	base *= mix(0.95, 1.05, detail2);
	// Wear: heavy use in front of both goals and along the centre corridor.
	float gx = max(abs(world_pos.x) - 38.0, 0.0) / 14.0;
	float gz = abs(world_pos.z) / 34.0;
	float centre_wear = max(1.0 - abs(world_pos.x) / 8.0, 0.0) * 0.25;
	float wear = clamp(gx * 1.3 + max(gz - 0.45, 0.0) * 1.8 + centre_wear, 0.0, 1.0) * wear_strength;
	base = mix(base, wear_color.rgb, wear * 0.6);
	ALBEDO = base;
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}
