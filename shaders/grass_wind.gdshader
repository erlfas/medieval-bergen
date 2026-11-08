shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;

// Medieval Bergen 1360 - High-Performance WebGL 2.0 Spatial Wind Grass Shader
// Designed for dense MultiMesh instancing with zero draw call stalls.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D pbr_texture : hint_default_white, filter_linear_mipmap, repeat_disable;

// Wind dynamic controls
uniform vec3 wind_direction = vec3(0.707, 0.0, 0.707); // North-West to South-East fjord wind
uniform float wind_speed : hint_range(0.2, 8.0) = 2.2;
uniform float wind_strength : hint_range(0.0, 1.5) = 0.35;
uniform float gust_frequency : hint_range(0.01, 0.2) = 0.045;
uniform float gust_strength : hint_range(0.0, 1.0) = 0.45;

// Color gradients for Bergen meadow realism
uniform vec3 grass_base_tint : source_color = vec3(0.22, 0.38, 0.14); // Damp root soil green
uniform vec3 grass_tip_tint : source_color = vec3(0.44, 0.64, 0.22);  // Sunlit tip lime-emerald
uniform float roughness_mult : hint_range(0.1, 1.5) = 0.88;

varying vec3 v_world_pos;
varying float v_height_factor;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Normalized height factor (0.0 at ground root, 1.0 at blade tips)
	// Anchors root to terrain while allowing tips to sway freely
	float blade_h = max(0.001, MODEL_MATRIX[1][1] * 0.78);
	v_height_factor = clamp(VERTEX.y / blade_h, 0.0, 1.0);
	float bend_weight = v_height_factor * v_height_factor; // Quadratic cantilever bending

	// 1. Ambient undulating Norwegian breeze
	float wave1 = sin(TIME * wind_speed + dot(v_world_pos.xz, wind_direction.xz) * 0.45);

	// 2. Traveling gust fronts (pulsed positive wave)
	float wave2 = sin(TIME * (wind_speed * 1.5) + dot(v_world_pos.xz, wind_direction.xz) * gust_frequency);
	wave2 = max(0.0, wave2) * gust_strength;

	// 3. High-frequency micro-blade flutter
	float flutter = sin(TIME * 8.0 + (v_world_pos.x * 3.4 + v_world_pos.z * 2.8)) * 0.06;

	// Combined lateral displacement
	vec3 displacement = wind_direction * ((wave1 * 0.28 + wave2 + flutter) * wind_strength * bend_weight);

	// Conserve blade length so tall grass doesn't stretch artificially when bending
	float orig_y = max(0.0, VERTEX.y);
	VERTEX.xz += displacement.xz;
	VERTEX.y = sqrt(max(0.0, orig_y * orig_y - dot(displacement.xz, displacement.xz)));
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);

	// Alpha cutout support (for LOD1 billboard planes)
	if (tex.a < 0.35) {
		discard;
	}

	// Smooth root-to-tip color gradient modulated by MultiMesh instance color
	vec3 gradient_color = mix(grass_base_tint, grass_tip_tint, v_height_factor);
	ALBEDO = tex.rgb * gradient_color * COLOR.rgb;

	// PBR channels
	vec3 norm_sample = texture(normal_texture, UV).rgb;
	NORMAL_MAP = norm_sample;
	NORMAL_MAP_DEPTH = 0.65;

	vec3 pbr_sample = texture(pbr_texture, UV).rgb;
	ROUGHNESS = clamp(pbr_sample.g * roughness_mult, 0.4, 0.95);
	SPECULAR = 0.25;
}
