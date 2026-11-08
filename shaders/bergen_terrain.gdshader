shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// Bergen 1360 - Atmospheric Medieval Norwegian Terrain Shader
// Features:
// 1. Lush Bergen meadow grass with multi-octave procedural variation, fine turf noise, and moss highlights.
// 2. Fløyen & Sandviksfjellet granite cliffs with slope-based triplanar projection, strata banding, and crag normals.
// 3. Mountain scree / talus slopes at cliff bases.
// 4. Macro world noise to eliminate tiling repetition across the 2km map.
// 5. Shoreline wetness and Bryggen wharf soil integration.
// 6. Compatible with GL Compatibility / WebGL 2.0.

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D scree_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D scree_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_noise : hint_default_white, filter_linear_mipmap, repeat_enable;

// UV Scale controls
uniform float grass_uv_scale : hint_range(0.01, 1.0) = 0.22;
uniform float rock_uv_scale : hint_range(0.01, 0.5) = 0.075;
uniform float scree_uv_scale : hint_range(0.01, 0.5) = 0.16;
uniform float macro_uv_scale : hint_range(0.0005, 0.01) = 0.0022;

// Slope & Elevation controls
uniform float cliff_slope_threshold : hint_range(0.1, 0.8) = 0.40;
uniform float cliff_slope_softness : hint_range(0.02, 0.3) = 0.12;
uniform float mountain_elevation_start : hint_range(50.0, 200.0) = 110.0;
uniform float mountain_elevation_peak : hint_range(200.0, 400.0) = 280.0;

// Color tints for medieval atmospheric tuning
uniform vec3 grass_lush_tint : source_color = vec3(0.92, 1.05, 0.90);
uniform vec3 grass_moss_tint : source_color = vec3(1.08, 1.12, 0.82);
uniform vec3 rock_slate_tint : source_color = vec3(0.95, 0.96, 1.0);
uniform vec3 wharf_dirt_tint : source_color = vec3(0.44, 0.39, 0.31);
uniform vec3 shore_wet_tint : source_color = vec3(0.20, 0.22, 0.21);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_vertex_color;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	v_vertex_color = COLOR;
}

void fragment() {
	// 1. World-Space Coordinate Sampling
	vec2 uv_macro = v_world_pos.xz * macro_uv_scale;
	vec3 macro_sample = texture(macro_noise, uv_macro).rgb;

	// Macro modulation channels:
	// R: moisture / lushness gradient across valleys
	// G: moss / lichen coverage (higher on north-facing slopes and damp hollows)
	// B: geological strata & stone weathering
	float moisture = macro_sample.r;
	float moss_density = macro_sample.g;
	float stone_weathering = macro_sample.b;

	// Boost moss on north-facing slopes (negative Z in Bergen topography)
	float north_facing = clamp(-v_world_normal.z * 0.7 + 0.3, 0.0, 1.0);
	moss_density = clamp(moss_density + north_facing * 0.25, 0.0, 1.0);

	// 2. Slope & Biome Weight Calculation (computed prior to texture fetches to skip unused lookups)
	// Flat ground has v_world_normal.y ~ 1.0 (slope = 0.0)
	// Sheer cliff face has v_world_normal.y ~ 0.0 (slope = 1.0)
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);

	// Scree forms on moderate slopes (25 to 45 deg) at the base of Fløyen's cliffs
	float scree_slope_mask = smoothstep(0.24, 0.36, slope) * (1.0 - smoothstep(0.48, 0.62, slope));
	float scree_elevation_mask = smoothstep(20.0, 65.0, v_world_pos.y) * (1.0 - smoothstep(180.0, 260.0, v_world_pos.y));
	float scree_weight = clamp(scree_slope_mask * scree_elevation_mask * (0.6 + 0.4 * stone_weathering), 0.0, 0.85);

	// Steep slopes always expose granite rock; high altitude fell terrain exposes rock on moderate slopes
	float cliff_weight = smoothstep(cliff_slope_threshold - cliff_slope_softness, cliff_slope_threshold + cliff_slope_softness, slope);
	float summit_rock_weight = smoothstep(mountain_elevation_start, mountain_elevation_peak, v_world_pos.y) * 0.75;
	float rock_weight = clamp(max(cliff_weight, summit_rock_weight), 0.0, 1.0);

	vec3 surface_albedo = vec3(0.35, 0.45, 0.25);
	vec3 surface_normal = vec3(0.0, 0.0, 1.0);
	float surface_roughness = 0.86;

	// 3. Multi-Octave Grass Texture Calculation (skipped on 100% sheer rock cliffs)
	if (rock_weight < 0.999) {
		// Primary octave: fine turf blades and clumping (repeats ~4.5m)
		vec2 uv_grass1 = v_world_pos.xz * grass_uv_scale;
		vec3 grass_col1 = texture(grass_albedo, uv_grass1).rgb;
		vec3 grass_norm1 = texture(grass_normal, uv_grass1).rgb;

		// Secondary octave: rotated 45 deg, slightly different scale (~9m) to eliminate repeating grid patterns
		vec2 uv_grass2 = vec2(
			v_world_pos.x * 0.7071 - v_world_pos.z * 0.7071,
			v_world_pos.x * 0.7071 + v_world_pos.z * 0.7071
		) * (grass_uv_scale * 0.51) + vec2(19.4, 37.1);
		vec3 grass_col2 = texture(grass_albedo, uv_grass2).rgb;
		vec3 grass_norm2 = texture(grass_normal, uv_grass2).rgb;

		// Composite grass albedo & normal
		vec3 grass_albedo_final = mix(grass_col1, grass_col2, 0.38) * grass_lush_tint;
		vec3 grass_normal_final = normalize(mix(grass_norm1, grass_norm2, 0.35) * 2.0 - 1.0);

		// Apply moisture & moss variation
		vec3 deep_emerald = grass_albedo_final * vec3(0.85, 1.08, 0.88);
		vec3 dry_golden = grass_albedo_final * vec3(1.10, 1.02, 0.85);
		grass_albedo_final = mix(deep_emerald, dry_golden, moisture * 0.6);

		// Add vibrant moss highlights in sheltered pockets
		if (moss_density > 0.45) {
			float moss_factor = smoothstep(0.45, 0.85, moss_density);
			vec3 moss_color = grass_albedo_final * grass_moss_tint * 1.15;
			grass_albedo_final = mix(grass_albedo_final, moss_color, moss_factor * 0.55);
		}

		surface_albedo = grass_albedo_final;
		surface_normal = grass_normal_final;
	}

	// 4. Mountain Scree / Talus Calculation (only sampled where scree_weight > 0.001)
	if (scree_weight > 0.001 && rock_weight < 0.999) {
		vec2 uv_scree = v_world_pos.xz * scree_uv_scale;
		vec3 scree_col = texture(scree_albedo, uv_scree).rgb;
		vec3 scree_norm = texture(scree_normal, uv_scree).rgb * 2.0 - 1.0;

		surface_albedo = mix(surface_albedo, scree_col, scree_weight);
		surface_normal = normalize(mix(surface_normal, scree_norm, scree_weight));
		surface_roughness = mix(surface_roughness, 0.92, scree_weight);
	}

	// 5. Triplanar Mountain Rock Calculation (only sampled where rock_weight > 0.001)
	if (rock_weight > 0.001) {
		vec3 tri_weights = pow(abs(v_world_normal), vec3(5.0));
		tri_weights /= max(tri_weights.x + tri_weights.y + tri_weights.z, 0.0001);

		vec2 uv_rock_x = v_world_pos.zy * rock_uv_scale;
		vec2 uv_rock_y = v_world_pos.xz * rock_uv_scale;
		vec2 uv_rock_z = v_world_pos.xy * rock_uv_scale;

		vec3 rock_col_x = texture(rock_albedo, uv_rock_x).rgb;
		vec3 rock_col_y = texture(rock_albedo, uv_rock_y).rgb;
		vec3 rock_col_z = texture(rock_albedo, uv_rock_z).rgb;
		vec3 rock_albedo_final = (rock_col_x * tri_weights.x + rock_col_y * tri_weights.y + rock_col_z * tri_weights.z) * rock_slate_tint;

		vec3 rock_norm_x = texture(rock_normal, uv_rock_x).rgb;
		vec3 rock_norm_y = texture(rock_normal, uv_rock_y).rgb;
		vec3 rock_norm_z = texture(rock_normal, uv_rock_z).rgb;
		vec3 rock_normal_final = normalize(
			(rock_norm_x * tri_weights.x + rock_norm_y * tri_weights.y + rock_norm_z * tri_weights.z) * 2.0 - 1.0
		);

		// Geological Metamorphic Strata (gneiss banding) along elevation
		float strata_band = sin(v_world_pos.y * 0.45 + stone_weathering * 3.5) * 0.5 + 0.5;
		rock_albedo_final = mix(rock_albedo_final, rock_albedo_final * 1.18 + vec3(0.03, 0.035, 0.03), strata_band * 0.35);

		// Weathered alpine lichen on high mountain crags
		float alt_progress = clamp((v_world_pos.y - mountain_elevation_start) / (mountain_elevation_peak - mountain_elevation_start), 0.0, 1.0);
		if (alt_progress > 0.2) {
			vec3 lichen_tint = vec3(0.92, 1.02, 0.88);
			rock_albedo_final = mix(rock_albedo_final, rock_albedo_final * lichen_tint, alt_progress * moss_density * 0.4);
		}

		surface_albedo = mix(surface_albedo, rock_albedo_final, rock_weight);
		surface_normal = normalize(mix(surface_normal, rock_normal_final, rock_weight));
		surface_roughness = mix(surface_roughness, 0.74, rock_weight);
	}

	// 8. Shoreline and Lowland Wharf Adjustments
	// Shoreline wet sand / fjord silt (below y = 1.0)
	if (v_world_pos.y < 1.0) {
		float shore_factor = 1.0 - smoothstep(-2.0, 0.8, v_world_pos.y);
		surface_albedo = mix(surface_albedo, shore_wet_tint, shore_factor * 0.9);
		surface_roughness = mix(surface_roughness, 0.28, shore_factor); // Wet sheen
	}

	// Bryggen wharf flat zone (timber and compacted earth foundations)
	if (v_world_pos.y >= 0.5 && v_world_pos.y <= 4.2 && v_world_pos.x >= 35.0 && v_world_pos.x <= 140.0 && v_world_pos.z >= -100.0 && v_world_pos.z <= 650.0) {
		float wharf_factor = clamp((1.0 - abs((v_world_pos.x - 85.0) / 55.0)) * (1.0 - abs((v_world_pos.z - 265.0) / 385.0)), 0.0, 1.0);
		surface_albedo = mix(surface_albedo, wharf_dirt_tint, wharf_factor * 0.75);
		surface_roughness = mix(surface_roughness, 0.88, wharf_factor);
	}

	// 9. Output PBR Material
	ALBEDO = surface_albedo;
	NORMAL_MAP = (surface_normal + 1.0) * 0.5;
	NORMAL_MAP_DEPTH = 0.75;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.35;
}
