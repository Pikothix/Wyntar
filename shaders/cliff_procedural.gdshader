shader_type canvas_item;
render_mode unshaded;

// Presentation-only cliff material. The generated atlas remains the sole owner
// of opacity and silhouette; this shader replaces RGB only when enabled.
uniform sampler2D source_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D stone_texture : source_color, filter_nearest, repeat_enable;
uniform bool procedural_enabled = true;
uniform bool stone_style = false;
uniform bool shoreline = false;
uniform bool contact_shadow = false;
uniform bool geometry_mesh = false;
uniform bool combined_geometry = false;
// G6 replaces only the repeated 32px source pigment. The atlas continues to
// own silhouette/opacity and the existing world-space geology remains intact.
uniform bool texture_detail_reconstruction_enabled = false;
uniform float texture_detail_reconstruction_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec2 seed_offset = vec2(0.0);
// Reserved for camera integration. Broad planes and beds remain at every LOD;
// only cracks and fine weathering respond to this value.
uniform float detail_level : hint_range(0.0, 1.0) = 1.0;

varying vec2 world_position;


float hash_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}


float smooth_value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float top = mix(
		hash_value(cell), hash_value(cell + vec2(1.0, 0.0)), fraction.x);
	float bottom = mix(
		hash_value(cell + vec2(0.0, 1.0)),
		hash_value(cell + vec2(1.0, 1.0)), fraction.x);
	return mix(top, bottom, fraction.y);
}


float broad_facet_field(vec2 point) {
	// Large rotated plane groups replace the previous dense box-cell pattern.
	// The irregular rotation keeps the low-cost lattice from following tiles.
	vec2 plane_space = vec2(
		point.x * 0.017 + point.y * 0.010,
		-point.x * 0.008 + point.y * 0.019);
	return hash_value(floor(plane_space) + seed_offset * 0.11);
}


float geological_crack(vec2 point) {
	// One short, bent fracture and an occasional branch exist in each selected
	// large absolute-world cell. Line distances avoid neighbourhood searches and
	// remain identical when a fracture crosses a terrain chunk boundary.
	vec2 cell_size = vec2(112.0, 96.0);
	vec2 cell = floor(point / cell_size);
	float selection = hash_value(cell + seed_offset * 0.07 + vec2(41.0, 13.0));
	vec2 local = point - cell * cell_size;
	float shape = hash_value(cell + seed_offset * 0.17 + vec2(23.0, 5.0));
	float bend = hash_value(cell + seed_offset * 0.23 + vec2(61.0, 47.0));
	float principal_x = mix(27.0, 85.0, shape);
	principal_x += (bend - 0.5) * 0.46 * (local.y - 12.0);
	principal_x += (shape - 0.5) * 13.0 * step(43.0, local.y);
	float vertical_gate = step(9.0, local.y) * step(local.y, mix(55.0, 76.0, bend));
	float selected_gate = step(0.79, selection);
	float thickness = mix(0.65, 1.15, shape);
	float principal = 1.0 - smoothstep(
		thickness, thickness + 0.85, abs(local.x - principal_x));

	float branch_y = local.y - 43.0;
	float branch_x = principal_x + (shape - 0.5) * 1.25 * branch_y;
	float branch_gate = step(0.91, selection) * step(0.0, branch_y) * step(branch_y, 17.0);
	float branch = 1.0 - smoothstep(
		thickness * 0.7, thickness * 0.7 + 0.85, abs(local.x - branch_x));
	return max(principal * vertical_gate, branch * branch_gate) * selected_gate;
}


float five_step_ramp(float value) {
	value = clamp(value, 0.0, 0.999999);
	if (value < 0.2) {
		return 0.72;
	}
	if (value < 0.4) {
		return 0.84;
	}
	if (value < 0.6) {
		return 0.96;
	}
	if (value < 0.8) {
		return 1.06;
	}
	return 1.14;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec4 atlas = COLOR;
	if (!procedural_enabled || atlas.a <= 0.0) {
		COLOR = atlas;
	} else if (contact_shadow) {
		float foot_weather = smooth_value_noise(
			floor(world_position) * 0.025 + seed_offset * 0.17);
		COLOR = vec4(atlas.rgb * mix(0.78, 0.96, foot_weather), atlas.a);
	} else {
		vec2 pixel = floor(world_position) + vec2(0.5);
		vec2 source_uv = (pixel + vec2(16.0)) / 32.0;
		vec3 pigment = texture(source_texture, source_uv).rgb;
		bool fragment_stone = stone_style;
		bool fragment_shoreline = shoreline;
		float geometry_shade = 1.0;
		int geometry_role = 0;
		if (combined_geometry) {
			int source_id = int(floor(atlas.g * 3.0 + 0.5));
			geometry_role = int(floor(atlas.b * 3.0 + 0.5));
			fragment_stone = source_id == 1 || source_id == 3;
			fragment_shoreline = source_id >= 2;
			geometry_shade = atlas.r;
			if (fragment_stone) {
				pigment = texture(stone_texture, source_uv).rgb;
			} else {
				pigment = texture(dirt_texture, source_uv).rgb;
			}
		}
		if (texture_detail_reconstruction_enabled) {
			vec2 bounded_pixel = mod(pixel, vec2(2039.0, 2029.0));
			float pigment_macro = smooth_value_noise(
				pixel * 0.026 + seed_offset * 0.031) - 0.5;
			float pigment_fine = hash_value(
				bounded_pixel + mod(seed_offset, vec2(997.0, 991.0)) * 0.047) - 0.5;
			vec3 pigment_base = fragment_stone
				? vec3(0.565, 0.608, 0.627) : vec3(0.541, 0.388, 0.263);
			vec3 reconstructed_pigment = pigment_base
				* (1.0 + pigment_macro * 0.11 + pigment_fine * 0.035);
			pigment = mix(pigment, reconstructed_pigment,
				texture_detail_reconstruction_strength);
		}

		float macro = smooth_value_noise(pixel * 0.018 + seed_offset);
		float fine = smooth_value_noise(pixel * 0.071 + seed_offset * 0.37);
		float facet = broad_facet_field(pixel + seed_offset * 5.0) - 0.5;

		// Beds use absolute coordinates, a slowly changing thickness and rare
		// deterministic offsets. Break noise removes short portions without
		// restarting the layer at a tile or chunk edge.
		float warp = (smooth_value_noise(
			vec2(pixel.x * 0.012, pixel.y * 0.002) + seed_offset * 0.13) - 0.5) * 8.0;
		float thickness_region = floor((pixel.x + 53.0) / 176.0);
		float thickness_field = hash_value(
			vec2(thickness_region, 19.0) + seed_offset * 0.09);
		float layer_thickness = mix(
			fragment_stone ? 11.0 : 14.0,
			fragment_stone ? 17.0 : 21.0, thickness_field);
		float fault_region = floor((pixel.x + 37.0) / 144.0);
		float fault_seed = hash_value(
			vec2(fault_region, 73.0) + seed_offset * 0.19);
		float fault_offset = step(0.82, fault_seed) * (fault_seed - 0.82) * 38.0;
		float band_coordinate = (pixel.y + warp + fault_offset) / layer_thickness;
		float band_index = floor(band_coordinate);
		float band_distance = min(fract(band_coordinate), 1.0 - fract(band_coordinate));
		float band = 1.0 - smoothstep(0.045, 0.145, band_distance);
		float break_field = hash_value(vec2(
			floor((pixel.x + 19.0) / 88.0), band_index * 0.71) + seed_offset * 0.41);
		band *= step(0.19, break_field);
		float bed_identity = hash_value(
			vec2(band_index, 101.0) + seed_offset * 0.27) - 0.5;

		float tone = 0.5 + (macro - 0.5) * 0.34 + (fine - 0.5) * 0.14;
		float facet_strength = 0.13;
		float strata_strength = 0.045;
		if (fragment_stone) {
			facet_strength = 0.43;
			strata_strength = 0.105;
		}
		tone += facet * facet_strength;
		tone += bed_identity * (fragment_stone ? 0.085 : 0.035);
		tone -= band * strata_strength;
		float ramp = five_step_ramp(tone);

		// The source art remains micrograin while world-space planes and beds carry
		// the primary form read. Reuse the macro field for weathering so the added
		// geological hierarchy does not multiply fragment-noise cost.
		float weather = macro;
		float weather_strength = mix(0.0, 1.0, detail_level);
		pigment *= ramp * mix(0.965, 1.02, mix(0.5, weather, weather_strength));

		if (fragment_stone && geometry_role == 0) {
			float crack = geological_crack(pixel + seed_offset * 3.0) * detail_level;
			vec3 fracture_tone = vec3(0.20, 0.235, 0.26);
			pigment = mix(pigment, fracture_tone, crack * 0.58);
		} else if (!fragment_stone && geometry_role == 0) {
			float streak_field = fine * 0.72 + macro * 0.28;
			float erosion_streak = smoothstep(0.72, 0.94, streak_field) * detail_level;
			pigment *= 1.0 - erosion_streak * 0.065;
		}

		if (fragment_shoreline) {
			float wet_patch = smoothstep(0.47, 0.78, 1.0 - weather);
			float wetness = 0.045 + wet_patch * 0.095;
			pigment = mix(pigment, vec3(0.40, 0.52, 0.54), wetness);
			pigment *= mix(0.97, 0.93, wet_patch);
		}
		if (combined_geometry && geometry_role == 1) {
			// The existing 3-5 px lip is the crest accent. Keeping it dark brown
			// rather than black separates the upper surface without outlining every
			// internal facet.
			pigment = mix(pigment, vec3(0.19, 0.17, 0.145), 0.16);
			pigment *= mix(0.94, 1.02, smoothstep(0.35, 0.75, fine));
		} else if (combined_geometry && geometry_role == 2) {
			// Side returns use the same strata field but turn slightly away from
			// the notional top-left light.
			pigment *= mix(0.88, 0.98, macro);
		} else if (combined_geometry && geometry_role == 3) {
			// Geometry follows the actual foot contour; alpha supplied by the
			// mesh keeps this contact shadow deliberately restrained.
			pigment = mix(pigment, vec3(0.08, 0.075, 0.07), 0.76);
			pigment *= mix(0.88, 1.0, weather);
		}
		if (geometry_mesh) {
			pigment *= atlas.rgb;
		}
		pigment *= geometry_shade;

		COLOR = vec4(clamp(pigment, vec3(0.0), vec3(1.0)), atlas.a);
	}
}
