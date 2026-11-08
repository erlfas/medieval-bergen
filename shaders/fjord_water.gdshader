shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// Bergen 1360 - Realistic Norwegian Fjord Water Shader
// WebGL 2.0 / GL Compatibility Compliant
// Features:
// 1. Multi-harmonic Gerstner wave vertex displacement for realistic swells and surface chop.
// 2. Analytic surface normal calculation for accurate sunlight specular reflection.
// 3. Two-tone Beer-Lambert depth absorption (shallow turquoise shoreline to deep cold Byfjorden navy).
// 4. Contact shoreline foam and wave crest white-caps.
// 5. Dual scrolling ripple normal maps for micro-turbulence.
// 6. Schlick Fresnel reflection for grazing-angle sky sheen.

uniform vec4 shallow_color : source_color = vec4(0.12, 0.40, 0.44, 0.80);
uniform vec4 deep_color : source_color = vec4(0.03, 0.09, 0.16, 0.95);
uniform vec4 foam_color : source_color = vec4(0.88, 0.93, 0.96, 0.85);

uniform float wave_speed : hint_range(0.1, 4.0) = 0.9;
uniform float wave_amplitude : hint_range(0.01, 1.0) = 0.22;
uniform float wave_frequency : hint_range(0.01, 0.2) = 0.045;
uniform float foam_distance : hint_range(0.1, 3.0) = 0.75;
uniform float water_roughness : hint_range(0.0, 1.0) = 0.08;
uniform float water_metallic : hint_range(0.0, 1.0) = 0.12;

uniform sampler2D wave_normal1 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_normal2 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 v_world_pos;
varying float v_wave_height;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float time = TIME * wave_speed;

	// Multi-harmonic Gerstner wave displacement
	vec2 dir1 = vec2(0.8, 0.6);
	float k1 = wave_frequency;
	float phase1 = dot(dir1, world_pos.xz) * k1 + time * 1.2;
	float w1 = sin(phase1);

	vec2 dir2 = vec2(-0.6, 0.8);
	float k2 = wave_frequency * 1.7;
	float phase2 = dot(dir2, world_pos.xz) * k2 + time * 1.5;
	float w2 = sin(phase2);

	vec2 dir3 = vec2(0.35, -0.93);
	float k3 = wave_frequency * 3.2;
	float phase3 = dot(dir3, world_pos.xz) * k3 + time * 2.1;
	float w3 = sin(phase3);

	float wave_h = (w1 * 0.55 + w2 * 0.30 + w3 * 0.15) * wave_amplitude;
	VERTEX.y += wave_h;
	v_wave_height = wave_h;

	// Analytic wave normal derivatives (model space; Godot transforms NORMAL to view space)
	float dw_dx = (cos(phase1) * dir1.x * k1 * 0.55 + cos(phase2) * dir2.x * k2 * 0.30 + cos(phase3) * dir3.x * k3 * 0.15) * wave_amplitude;
	float dw_dz = (cos(phase1) * dir1.y * k1 * 0.55 + cos(phase2) * dir2.y * k2 * 0.30 + cos(phase3) * dir3.y * k3 * 0.15) * wave_amplitude;
	vec3 wave_normal = normalize(vec3(-dw_dx, 1.0, -dw_dz));
	NORMAL = wave_normal;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Reconstruct linear eye depth from depth texture (WebGL 2.0 / GL Compatibility uses [-1, 1] NDC Z)
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw * 2.0 - 1.0);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= view_pos.w;
	float linear_depth = -view_pos.z;
	float water_depth = max(linear_depth - (-VERTEX.z), 0.0);

	// Beer-Lambert depth absorption (shallow turquoise -> deep Byfjorden Atlantic navy)
	float depth_factor = clamp(water_depth / 4.5, 0.0, 1.0);
	vec3 water_col = mix(shallow_color.rgb, deep_color.rgb, depth_factor);
	float water_alpha = mix(shallow_color.a, deep_color.a, depth_factor);

	// Dual scrolling micro-ripple normal maps transformed into view space
	vec2 uv_scroll1 = v_world_pos.xz * 0.06 + vec2(TIME * 0.025, TIME * 0.015);
	vec2 uv_scroll2 = v_world_pos.xz * 0.11 - vec2(TIME * 0.018, TIME * 0.030);
	vec3 n1 = texture(wave_normal1, uv_scroll1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal2, uv_scroll2).rgb * 2.0 - 1.0;
	vec3 world_ripple = vec3(n1.x + n2.x, 0.0, n1.y + n2.y) * 0.35;
	vec3 view_ripple = mat3(VIEW_MATRIX) * world_ripple;
	NORMAL = normalize(NORMAL + view_ripple);

	// Shoreline & contact foam
	float foam_edge = 1.0 - smoothstep(0.0, foam_distance, water_depth);
	// Wave crest foam
	float crest_foam = clamp((v_wave_height - wave_amplitude * 0.55) * 6.0, 0.0, 1.0);
	float total_foam = clamp(foam_edge * 1.1 + crest_foam * 0.7, 0.0, 1.0);

	// Fresnel reflectance
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
	vec3 final_color = mix(water_col, foam_color.rgb, total_foam * foam_color.a);
	final_color = mix(final_color, vec3(0.55, 0.70, 0.82), fresnel * 0.40);

	ALBEDO = final_color;
	ALPHA = mix(water_alpha, 1.0, total_foam * 0.85);
	ROUGHNESS = mix(water_roughness, 0.7, total_foam);
	METALLIC = water_metallic;
	SPECULAR = 0.5;
}
