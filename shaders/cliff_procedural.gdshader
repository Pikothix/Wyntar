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
uniform vec2 seed_offset = vec2(0.0);

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


float facet_field(vec2 point) {
	// Two rotated box lattices make stable, irregular regions without Voronoi
	// loops. Coordinates are absolute, so the regions cross chunk boundaries.
	vec2 first = vec2(
		point.x * 0.079 + point.y * 0.047,
		-point.x * 0.039 + point.y * 0.091);
	vec2 second = vec2(
		point.x * 0.121 - point.y * 0.063,
		point.x * 0.052 + point.y * 0.108) + vec2(17.0, 31.0);
	float a = hash_value(floor(first));
	float b = hash_value(floor(second));
	return fract(a + b * 0.61803398875);
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

		float macro = smooth_value_noise(pixel * 0.018 + seed_offset);
		float fine = smooth_value_noise(pixel * 0.071 + seed_offset * 0.37);
		float facet = facet_field(pixel + seed_offset * 5.0) - 0.5;

		// Bands use absolute world Y and a broad X warp. They therefore continue
		// through adjacent tiles and vertically stacked cliff segments.
		float warp = (smooth_value_noise(
			vec2(pixel.x * 0.018, pixel.y * 0.003) + seed_offset * 0.13) - 0.5) * 5.5;
		float band_coordinate = (pixel.y + warp) / (fragment_stone ? 10.5 : 13.0);
		float band_distance = abs(fract(band_coordinate) - 0.5);
		float band = 1.0 - smoothstep(0.055, 0.19, band_distance);
		float band_identity = hash_value(
			vec2(floor(band_coordinate), floor(pixel.x / 192.0)));
		float strata = band * mix(0.035, 0.105, band_identity);

		float tone = 0.5 + (macro - 0.5) * 0.34 + (fine - 0.5) * 0.14;
		float facet_strength = 0.14;
		float strata_strength = 0.58;
		if (fragment_stone) {
			facet_strength = 0.48;
			strata_strength = 1.0;
		}
		tone += facet * facet_strength;
		tone -= strata * strata_strength;
		float ramp = five_step_ramp(tone);

		// Broad damp variation complements the existing contact-shadow atlas row;
		// it never uses tile-local Y, so internal stack boundaries stay invisible.
		float weather = smooth_value_noise(
			vec2(pixel.x * 0.011, pixel.y * 0.006) + seed_offset * 0.23);
		pigment *= ramp * mix(0.95, 1.025, weather);

		if (fragment_shoreline) {
			float wetness = 0.14 + (1.0 - weather) * 0.10;
			pigment = mix(pigment, vec3(0.48, 0.61, 0.60), wetness);
			pigment *= 0.94;
		}
		if (combined_geometry && geometry_role == 1) {
			// A compact upper ramp lets the generated lip read as the same rock
			// mass catching light, rather than a separate painted border.
			pigment *= mix(0.96, 1.08, smoothstep(0.35, 0.75, fine));
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
