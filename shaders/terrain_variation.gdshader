shader_type canvas_item;
render_mode unshaded;

// RGB is sampled in absolute world space. The masked atlas stores both the
// original alpha and its scalar contour field. Organic mode perturbs that one
// shared field in world space, so every compositing layer remains nested.
uniform sampler2D base_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D variant_texture_1 : source_color, filter_nearest, repeat_enable;
uniform sampler2D variant_texture_2 : source_color, filter_nearest, repeat_enable;
uniform sampler2D variant_texture_3 : source_color, filter_nearest, repeat_enable;
uniform float variation_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.65;
uniform float variation_frequency = 0.0025;
uniform vec2 seed_offset = vec2(0.0);
uniform float organic_boundaries_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float organic_edge_strength : hint_range(0.0, 0.18) = 0.08;
uniform float organic_edge_frequency = 0.035;
uniform vec2 organic_seed_offset = vec2(0.0);
// Grass-only presentation controls. The source texture remains authoritative
// for the legacy appearance; this branch selectively replaces its dark blade
// pixels according to a continuous world-space cluster field.
uniform float clustered_grass_detail_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float grass_clear_area_coverage : hint_range(0.0, 1.0) = 0.70;
uniform float grass_detail_density : hint_range(0.0, 1.0) = 0.35;
uniform float grass_cluster_scale = 0.004;
uniform float grass_transition_softness : hint_range(0.0, 0.4) = 0.12;
uniform float grass_clear_area_residual_density : hint_range(0.0, 1.0) = 0.04;
uniform vec2 grass_detail_seed_offset = vec2(0.0);
uniform float grass_detail_luma_threshold : hint_range(0.0, 1.0) = 0.50;
uniform vec3 grass_clear_color : source_color = vec3(0.467, 0.682, 0.345);
// Grass-only world-space correction. A continuous coordinate warp breaks the
// repeated 32px phase; two smooth fields add restrained seed-specific colour
// variation without introducing cell-aligned blocks.
uniform float organic_grass_color_variation_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float grass_broad_variation_scale = 0.0015;
uniform float grass_color_variation_strength : hint_range(0.0, 0.15) = 0.055;
uniform float grass_fine_variation_strength : hint_range(0.0, 0.08) = 0.018;
uniform vec2 grass_color_seed_offset = vec2(0.0);
// G3 replaces only the repeating source background with a restrained,
// deterministic sample of the same grass palette. Dark G1 marks remain source
// art. Disabling this uniform restores the exact G2 output path.
uniform float grass_texture_repetition_correction_enabled
    : hint_range(0.0, 1.0) = 0.0;
// G4 decorrelates ordinary terrain motifs with a continuous world-space warp.
// Material-specific eligibility and strength are supplied by the shared
// factory. Grass retains its G3 branch and liquid retains its water branch.
uniform float terrain_texture_repetition_correction_enabled
    : hint_range(0.0, 1.0) = 0.0;
uniform float terrain_texture_repetition_correction_strength
    : hint_range(0.0, 1.0) = 0.0;
uniform float terrain_texture_repetition_correction_scale = 0.005;
// G5 replaces the repetitive fine-detail pixels of selected ordinary surfaces
// with deterministic world-pixel grain. When disabled, the exact G4 sampling
// path is retained.
uniform float stochastic_terrain_detail_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float stochastic_terrain_detail_intensity : hint_range(0.0, 1.0) = 1.0;
uniform float stochastic_detail_style = 0.0;
uniform vec3 stochastic_base_color : source_color = vec3(1.0);
uniform vec3 stochastic_detail_color : source_color = vec3(0.5);
uniform float stochastic_detail_density : hint_range(0.0, 0.12) = 0.02;
uniform float stochastic_palette_variation : hint_range(0.0, 0.10) = 0.04;
// G6 gives snow and gravel separate reconstruction styles. Snow receives only
// restrained grain; gravel receives sparse, irregular multi-pixel fragments.
uniform float remaining_terrain_detail_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float remaining_terrain_detail_strength : hint_range(0.0, 1.0) = 1.0;
uniform float remaining_detail_style = 0.0;
uniform vec3 remaining_base_color : source_color = vec3(1.0);
uniform vec3 remaining_detail_color : source_color = vec3(0.5);
// G7 refines only the distribution and contrast of existing G5/G6 marks.
// Disabling it leaves those branches on their exact original calculations.
uniform float terrain_noise_refinement_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float terrain_detail_density_scale : hint_range(0.0, 1.0) = 1.0;
uniform float terrain_detail_contrast : hint_range(0.0, 1.0) = 1.0;
uniform float terrain_clear_area_coverage : hint_range(0.0, 1.0) = 0.0;
uniform float terrain_detail_cluster_scale = 0.006;
// Liquid parameters are inert for ordinary terrain. They keep liquid styling
// data-driven and leave authoritative material/height ownership in scripts.
uniform float liquid_enabled : hint_range(0.0, 1.0) = 0.0;
uniform vec3 liquid_surface_tint : source_color = vec3(0.4, 0.68, 0.79);
uniform vec3 liquid_highlight_tint : source_color = vec3(0.72, 0.93, 0.94);
uniform float liquid_calmness : hint_range(0.0, 1.0) = 0.8;
uniform float liquid_pattern_frequency = 0.01;
uniform float liquid_shimmer_strength : hint_range(0.0, 0.2) = 0.06;
uniform float liquid_motion_enabled : hint_range(0.0, 1.0) = 1.0;
uniform float liquid_motion_speed = 0.18;
uniform float shoreline_width : hint_range(0.02, 0.3) = 0.16;
uniform float liquid_depth_effect_strength : hint_range(0.0, 0.35) = 0.1;
uniform float liquid_emissive_strength : hint_range(0.0, 1.0) = 0.0;
// Phase A is an optional extension of the existing liquid branch. Keeping one
// branch and one shared material preserves liquid identity and avoids per-cell
// presentation state.
uniform float experimental_water_enhancement_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float water_ripple_strength : hint_range(0.0, 1.0) = 0.32;
uniform float water_secondary_ripple_scale : hint_range(0.5, 6.0) = 2.4;
uniform float water_ripple_drift_speed : hint_range(0.0, 2.0) = 0.55;
uniform float water_glint_density : hint_range(0.0, 1.0) = 0.14;
uniform float water_glint_brightness : hint_range(0.0, 1.0) = 0.38;
uniform float water_repetition_correction_enabled : hint_range(0.0, 1.0) = 0.0;
uniform float water_repetition_correction_strength : hint_range(0.0, 1.0) = 1.0;
// Negative uses Godot's global TIME. Tests may provide a fixed non-negative
// time so before/after captures compare the same animation instant.
uniform float water_animation_time_override = -1.0;

varying vec2 world_position;


float hash_value(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}


float stochastic_hash_value(vec2 point) {
    // Polynomial hash avoids the broad diagonal precision bands produced by
    // sine hashes on large Compatibility-renderer fragment coordinates.
    vec3 point3 = fract(vec3(point.x, point.y, point.x) * vec3(0.1031, 0.1030, 0.0973));
    point3 += dot(point3, point3.yxz + vec3(33.33));
    return fract((point3.x + point3.y) * point3.z);
}


float smooth_value_noise(vec2 point) {
    vec2 cell = floor(point);
    vec2 fraction = fract(point);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    float top = mix(hash_value(cell), hash_value(cell + vec2(1.0, 0.0)), fraction.x);
    float bottom = mix(hash_value(cell + vec2(0.0, 1.0)), hash_value(cell + vec2(1.0, 1.0)), fraction.x);
    return mix(top, bottom, fraction.y);
}


vec4 sample_variant_ramp(vec2 tiled_uv, float value) {
    float ramp = clamp(value, 0.0, 0.999999) * 3.0;
    if (ramp < 1.0) {
        return mix(texture(base_texture, tiled_uv), texture(variant_texture_1, tiled_uv), smoothstep(0.0, 1.0, ramp));
    }
    if (ramp < 2.0) {
        return mix(texture(variant_texture_1, tiled_uv), texture(variant_texture_2, tiled_uv), smoothstep(0.0, 1.0, ramp - 1.0));
    }
    return mix(texture(variant_texture_2, tiled_uv), texture(variant_texture_3, tiled_uv), smoothstep(0.0, 1.0, ramp - 2.0));
}


void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
    vec4 masked_atlas = COLOR;
    vec2 world_pixel = floor(world_position) + vec2(0.5);
    vec2 grass_texture_warp = vec2(0.0);
    if (organic_grass_color_variation_enabled > 0.5) {
        // A slowly changing coordinate warp breaks the exact 32px source
        // phase while retaining its pixel-art marks. It is continuous in
        // world space, unlike choosing a random phase per tile or chunk.
        vec2 warp_coordinate = world_pixel * grass_broad_variation_scale * 2.4;
        grass_texture_warp = (vec2(
            smooth_value_noise(warp_coordinate + grass_color_seed_offset * 0.71),
            smooth_value_noise(warp_coordinate + grass_color_seed_offset * 0.37
                + vec2(83.0, -59.0))) - 0.5) * 16.0;
    }
    // The +16 phase matches the original half-tile-shifted dual-grid texture.
    vec2 terrain_texture_warp = vec2(0.0);
    if (terrain_texture_repetition_correction_enabled > 0.5
            && stochastic_terrain_detail_enabled <= 0.5
            && remaining_terrain_detail_enabled <= 0.5) {
        // Smooth coordinates preserve continuity across tiles, chunks, and
        // material masks. Quantised world pixels retain the pixel-art sample.
        vec2 terrain_warp_coordinate = world_pixel
            * terrain_texture_repetition_correction_scale;
        terrain_texture_warp = (vec2(
            smooth_value_noise(terrain_warp_coordinate + seed_offset * 0.023),
            smooth_value_noise(terrain_warp_coordinate * 1.37
                + seed_offset * 0.041 + vec2(47.0, -73.0))) - 0.5)
            * (28.0 * terrain_texture_repetition_correction_strength);
    }
    vec2 texture_position = world_position + vec2(16.0)
        + grass_texture_warp + terrain_texture_warp;
    vec2 tiled_uv = texture_position / 32.0;
    vec4 original = texture(base_texture, tiled_uv);
    float noise_value = smooth_value_noise(world_position * variation_frequency + seed_offset);
    vec4 varied = sample_variant_ramp(tiled_uv, noise_value);
    float blend_amount = clamp(variation_enabled * variation_strength, 0.0, 1.0);
    // Quantising the lookup to world pixels keeps magnified edges crisp. A
    // single signed offset is applied to the encoded scalar field for every
    // material; subset masks therefore remain subsets after deformation.
    float organic_noise = smooth_value_noise(
        world_pixel * organic_edge_frequency + organic_seed_offset) * 2.0 - 1.0;
    float organic_alpha = smoothstep(
        0.43, 0.57, masked_atlas.r + organic_noise * organic_edge_strength) * original.a;
    float mask_alpha = mix(
        masked_atlas.a, organic_alpha, clamp(organic_boundaries_enabled, 0.0, 1.0));
    vec3 surface_rgb = mix(original.rgb, varied.rgb, blend_amount);
	if (stochastic_terrain_detail_enabled > 0.5) {
		// Preserve the existing broad variant tint while discarding the source
		// tile's repeated fine-detail coordinates. Hashes operate on bounded
		// world pixels for stable precision in large streamed worlds.
		vec2 detail_pixel = mod(world_pixel, vec2(2039.0, 2029.0));
		vec2 detail_seed = mod(seed_offset, vec2(997.0, 991.0));
		float pixel_roll = stochastic_hash_value(detail_pixel + detail_seed * 0.053
			+ vec2(stochastic_detail_style * 31.0, -17.0));
		float left_roll = stochastic_hash_value(detail_pixel - vec2(1.0, 0.0)
			+ detail_seed * 0.053 + vec2(stochastic_detail_style * 31.0, -17.0));
		float left_two_roll = stochastic_hash_value(detail_pixel - vec2(2.0, 0.0)
			+ detail_seed * 0.053 + vec2(stochastic_detail_style * 31.0, -17.0));
		float upper_roll = stochastic_hash_value(detail_pixel - vec2(0.0, 1.0)
			+ detail_seed * 0.053 + vec2(stochastic_detail_style * 31.0, -17.0));
		float link_roll = stochastic_hash_value(detail_pixel + detail_seed * 0.097
			+ vec2(-53.0, 79.0));
		float refined_density = stochastic_detail_density;
		float refined_contrast = 1.0;
		float dense_region = 1.0;
		if (terrain_noise_refinement_enabled > 0.5) {
			float cluster_field = smooth_value_noise(
				world_pixel * terrain_detail_cluster_scale + detail_seed * 0.037
				+ vec2(stochastic_detail_style * 17.0, -29.0));
			float cluster_rank = smoothstep(0.0, 1.0, cluster_field);
			dense_region = smoothstep(
				terrain_clear_area_coverage - 0.08,
				terrain_clear_area_coverage + 0.08, cluster_rank);
			refined_density *= terrain_detail_density_scale
				* mix(0.10, 1.0, dense_region);
			refined_contrast = terrain_detail_contrast;
		}
		float detail_mask = step(1.0 - refined_density, pixel_roll);
		if (stochastic_detail_style > 1.5 && stochastic_detail_style < 2.5) {
			// Dirt gains occasional two-pixel grains in either axis.
			detail_mask = max(detail_mask,
				step(1.0 - refined_density * 0.55, left_roll)
				* step(0.46, link_roll));
			detail_mask = max(detail_mask,
				step(1.0 - refined_density * 0.40, upper_roll)
				* step(0.63, link_roll));
		} else if (stochastic_detail_style > 2.5
				&& stochastic_detail_style < 3.5) {
			// Stone keeps sparse horizontal mineral flecks without fixed rows.
			detail_mask = max(detail_mask,
				step(1.0 - refined_density * 0.80, left_roll)
				* step(0.32, link_roll));
			detail_mask = max(detail_mask,
				step(1.0 - refined_density * 0.40, left_two_roll)
				* step(0.71, link_roll));
		} else if (stochastic_detail_style > 3.5) {
			// Mud uses fewer, softer paired pores than dirt.
			detail_mask = max(detail_mask,
				step(1.0 - refined_density * 0.35, left_roll)
				* step(0.58, link_roll));
		}
		float broad_grain = smooth_value_noise(
			world_pixel * 0.013 + detail_seed * 0.021) - 0.5;
		float fine_grain = stochastic_hash_value(detail_pixel + detail_seed * 0.071
			+ vec2(89.0, -37.0)) - 0.5;
		float palette_shift = broad_grain * stochastic_palette_variation
			+ fine_grain * stochastic_palette_variation * 0.42;
		vec3 variant_delta = surface_rgb - original.rgb;
		vec3 procedural_base = clamp(
			stochastic_base_color * (1.0 + palette_shift) + variant_delta,
			vec3(0.0), vec3(1.0));
		if (terrain_noise_refinement_enabled > 0.5
				&& stochastic_detail_style > 3.5) {
			// Mud carries a restrained broad darkening inside its irregular wet
			// patches, while isolated pore pixels remain uncommon.
			procedural_base *= 1.0 - dense_region * 0.035 * refined_contrast;
		}
		vec3 refined_detail_color = mix(
			procedural_base, stochastic_detail_color + variant_delta,
			refined_contrast);
		vec3 procedural_surface = mix(
			procedural_base, refined_detail_color, detail_mask);
		surface_rgb = mix(surface_rgb, procedural_surface,
			stochastic_terrain_detail_intensity);
	}
	if (remaining_terrain_detail_enabled > 0.5) {
		vec2 detail_pixel = mod(world_pixel, vec2(2039.0, 2029.0));
		vec2 detail_seed = mod(seed_offset, vec2(997.0, 991.0));
		vec3 variant_delta = surface_rgb - original.rgb;
		float broad = smooth_value_noise(
			world_pixel * 0.021 + detail_seed * 0.031) - 0.5;
		float fine = stochastic_hash_value(detail_pixel + detail_seed * 0.067
			+ vec2(71.0, -43.0)) - 0.5;
		vec3 procedural_surface;
		if (remaining_detail_style < 1.5) {
			// Snow stays bright and smooth: broad drift carries most of the
			// variation and the pixel grain is deliberately low contrast.
			float snow_shift = broad * 0.038 + fine * 0.010;
			procedural_surface = clamp(
				remaining_base_color * (1.0 + snow_shift) + variant_delta,
				vec3(0.0), vec3(1.0));
			float snow_grain = step(0.986, fine + 0.5);
			procedural_surface = mix(
				procedural_surface, remaining_detail_color + variant_delta,
				snow_grain * 0.22);
		} else {
			// Independent world-pixel anchors grow into short fragments. Their
			// orientation and length are hash-selected, so no placement grid or
			// repeated diagonal survives from the source tile.
			vec2 anchor_seed = detail_seed * 0.049 + vec2(-37.0, 83.0);
			float here = stochastic_hash_value(detail_pixel + anchor_seed);
			float left = stochastic_hash_value(detail_pixel - vec2(1.0, 0.0) + anchor_seed);
			float left_two = stochastic_hash_value(detail_pixel - vec2(2.0, 0.0) + anchor_seed);
			float above = stochastic_hash_value(detail_pixel - vec2(0.0, 1.0) + anchor_seed);
			float diagonal = stochastic_hash_value(detail_pixel - vec2(1.0, 1.0) + anchor_seed);
			float gravel_density_scale = 1.0;
			float gravel_contrast = 1.0;
			if (terrain_noise_refinement_enabled > 0.5) {
				float gravel_cluster = smooth_value_noise(
					world_pixel * terrain_detail_cluster_scale + detail_seed * 0.037
					+ vec2(113.0, -47.0));
				float gravel_rank = smoothstep(0.0, 1.0, gravel_cluster);
				float gravel_region = smoothstep(
					terrain_clear_area_coverage - 0.08,
					terrain_clear_area_coverage + 0.08, gravel_rank);
				gravel_density_scale = terrain_detail_density_scale
					* mix(0.25, 1.0, gravel_region);
				gravel_contrast = terrain_detail_contrast;
			}
			float fragment;
			if (terrain_noise_refinement_enabled > 0.5) {
				fragment = step(1.0 - 0.053 * gravel_density_scale, here);
				fragment = max(fragment, step(1.0 - 0.035 * gravel_density_scale, left)
					* step(0.48, stochastic_hash_value(detail_pixel + anchor_seed + vec2(19.0, 41.0))));
				fragment = max(fragment, step(1.0 - 0.018 * gravel_density_scale, left_two)
					* step(0.70, stochastic_hash_value(detail_pixel + anchor_seed + vec2(-61.0, 23.0))));
				fragment = max(fragment, step(1.0 - 0.028 * gravel_density_scale, above)
					* step(0.58, stochastic_hash_value(detail_pixel + anchor_seed + vec2(47.0, -29.0))));
				fragment = max(fragment, step(1.0 - 0.014 * gravel_density_scale, diagonal));
			} else {
				// Keep the original G6 constants and operations for exact rollback.
				fragment = step(0.947, here);
				fragment = max(fragment, step(0.965, left)
					* step(0.48, stochastic_hash_value(detail_pixel + anchor_seed + vec2(19.0, 41.0))));
				fragment = max(fragment, step(0.982, left_two)
					* step(0.70, stochastic_hash_value(detail_pixel + anchor_seed + vec2(-61.0, 23.0))));
				fragment = max(fragment, step(0.972, above)
					* step(0.58, stochastic_hash_value(detail_pixel + anchor_seed + vec2(47.0, -29.0))));
				fragment = max(fragment, step(0.986, diagonal));
			}
			float gravel_shift = broad * 0.075 + fine * 0.025;
			vec3 gravel_base = clamp(
				remaining_base_color * (1.0 + gravel_shift) + variant_delta,
				vec3(0.0), vec3(1.0));
			float fragment_tone = stochastic_hash_value(
				detail_pixel + anchor_seed + vec2(101.0, -73.0));
			vec3 fragment_color = mix(
				remaining_detail_color * 0.82,
				remaining_detail_color * 1.24, fragment_tone) + variant_delta;
			fragment_color = mix(gravel_base, fragment_color, gravel_contrast);
			procedural_surface = mix(gravel_base, fragment_color, fragment);
		}
		surface_rgb = mix(surface_rgb, procedural_surface,
			remaining_terrain_detail_strength);
	}
	float grass_source_luma = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
	float grass_dark_mark = 1.0 - smoothstep(
		grass_detail_luma_threshold - 0.035,
		grass_detail_luma_threshold + 0.025,
		grass_source_luma);
	float grass_suppress_mark = 0.0;
    if (clustered_grass_detail_enabled > 0.5) {
        // Smooth value noise defines broad meadow regions. Its smoothstep
        // remap makes the coverage control approximately percentile-like over
        // representative areas while retaining continuous organic borders.
        vec2 grass_pixel = floor(world_position) + vec2(0.5);
        float cluster_noise = smooth_value_noise(
            grass_pixel * grass_cluster_scale + grass_detail_seed_offset);
        float cluster_rank = smoothstep(0.0, 1.0, cluster_noise);
        float half_softness = max(grass_transition_softness * 0.5, 0.0001);
        float dense_region = smoothstep(
            grass_clear_area_coverage - half_softness,
            grass_clear_area_coverage + half_softness,
            cluster_rank);

        // Density means retention relative to dark marks in the existing
        // grass texture, not a percentage of all grass pixels. Grouping the
        // roll into small world-space cells keeps surviving marks clustered.
        float retention_probability = mix(
            grass_clear_area_residual_density, grass_detail_density, dense_region);
        vec2 detail_cell = floor(grass_pixel / vec2(4.0, 3.0));
        // Bound the sine-hash input before its dot product. Large absolute
        // world coordinates otherwise lose fractional precision on 32-bit
        // Compatibility shaders and collapse the roll to zero. The paired
        // prime periods remain much larger than the view and do not affect
        // chunk-boundary continuity.
        vec2 detail_hash_coordinate = mod(detail_cell, vec2(2039.0, 2029.0))
            + mod(grass_detail_seed_offset, vec2(997.0, 991.0)) * 0.019
            + vec2(37.0, -53.0);
        float detail_roll = hash_value(detail_hash_coordinate);
		grass_suppress_mark = grass_dark_mark * step(retention_probability, detail_roll);
        // Preserve the active tint/variation delta while replacing only the
        // suppressed source mark with the grass definition's clear palette.
        vec3 clear_surface = clamp(
            surface_rgb + grass_clear_color - original.rgb,
            vec3(0.0), vec3(1.0));
		surface_rgb = mix(surface_rgb, clear_surface, grass_suppress_mark);
	}
	if (grass_texture_repetition_correction_enabled > 0.5) {
		// The source tile's light pixels form the visible diagonal lattice. G3
		// resynthesises those background pixels from their established clear
		// colour while keeping all retained dark marks untouched. Pixel-quantised
		// world coordinates make the grain stable under camera motion and zoom.
		float background_weight = 1.0
			- grass_dark_mark * (1.0 - grass_suppress_mark);
		vec2 grain_coordinate = mod(world_pixel, vec2(2039.0, 2029.0))
			+ mod(grass_color_seed_offset, vec2(997.0, 991.0)) * 0.071;
		float clustered_grain = smooth_value_noise(
			grain_coordinate * 0.31 + vec2(17.0, -43.0));
		float pixel_grain = hash_value(grain_coordinate + vec2(-29.0, 61.0));
		float palette_shift = (clustered_grain - 0.5) * 0.10
			+ (pixel_grain - 0.5) * 0.035;
		vec3 stochastic_background = clamp(
			grass_clear_color * (1.0 + palette_shift), vec3(0.0), vec3(1.0));
		surface_rgb = mix(
			surface_rgb, stochastic_background, 0.86 * background_weight);
	}
	if (organic_grass_color_variation_enabled > 0.5) {
		// Retained G1 dark marks are left intact. Suppressed marks count as
		// background, keeping G1's density and cluster controls independent.
		float background_weight = 1.0
			- grass_dark_mark * (1.0 - grass_suppress_mark);
		float broad_primary = smooth_value_noise(
			world_pixel * grass_broad_variation_scale + grass_color_seed_offset);
		float broad_secondary = smooth_value_noise(
			world_pixel * grass_broad_variation_scale * 2.17
			+ grass_color_seed_offset * 0.43 + vec2(19.0, -31.0));
		float broad_field = (broad_primary * 0.72
			+ broad_secondary * 0.28 - 0.5) * 2.0;
		float fine_field = (smooth_value_noise(
			world_pixel * grass_broad_variation_scale * 7.3
			+ grass_color_seed_offset * 0.19 + vec2(-47.0, 23.0)) - 0.5) * 2.0;
		vec3 color_shift = broad_field * grass_color_variation_strength
			* vec3(0.55, 1.0, 0.42)
			+ fine_field * grass_fine_variation_strength
			* vec3(0.35, 0.70, 0.28);
		surface_rgb += color_shift * background_weight;
    }
    if (liquid_enabled > 0.5) {
        // Broad world-space bands break tile repetition without per-cell nodes.
        // Motion is a single optional phase term and is quantised to retain the
        // nearest-neighbour pixel-art character at high zoom.
        float water_time = water_animation_time_override >= 0.0
            ? water_animation_time_override : TIME;
        float motion_phase = water_time * liquid_motion_speed * liquid_motion_enabled;
        vec2 liquid_pixel = floor(world_position) + vec2(0.5);
		if (water_repetition_correction_enabled > 0.5) {
			// Static world-space colour replaces only the tiled source pigment.
			// Existing wave phases below remain the sole animated component.
			float water_broad = smooth_value_noise(
				liquid_pixel * 0.018 + seed_offset * 0.043) - 0.5;
			float water_fine = smooth_value_noise(
				liquid_pixel * 0.071 + seed_offset * 0.019 + vec2(29.0, -53.0)) - 0.5;
			vec3 reconstructed_water = clamp(liquid_surface_tint
				* (1.0 + water_broad * 0.10 + water_fine * 0.035),
				vec3(0.0), vec3(1.0));
			surface_rgb = mix(surface_rgb, reconstructed_water,
				water_repetition_correction_strength);
		}
        float band = sin(
            dot(liquid_pixel, vec2(liquid_pattern_frequency, liquid_pattern_frequency * 0.43))
            + motion_phase);
        float macro = smooth_value_noise(
            liquid_pixel * variation_frequency * 0.42 + seed_offset * 0.37);
        float shimmer = (band * 0.5 + macro - 0.5) * liquid_shimmer_strength;
        vec3 calm_surface = mix(surface_rgb, liquid_surface_tint, liquid_calmness * 0.74);
        surface_rgb = calm_surface + liquid_highlight_tint * shimmer;

        // Only partial universal masks have a 0.5 contour, so this produces a
        // restrained inner shoreline ripple and leaves open water calm.
        float inner_distance = max(masked_atlas.r - 0.5, 0.0);
        float shoreline = (1.0 - smoothstep(0.0, shoreline_width, inner_distance))
            * mask_alpha;
        surface_rgb = mix(surface_rgb, liquid_highlight_tint, shoreline * 0.34);
        surface_rgb *= 1.0 - liquid_depth_effect_strength * (1.0 - macro) * 0.28;
        surface_rgb += liquid_highlight_tint * liquid_emissive_strength * 0.18;

        if (experimental_water_enhancement_enabled > 0.5) {
            // A second, differently directed field is stepped at eight beats
            // per second. World-pixel coordinates and whole-pixel drift keep
            // the result crisp under camera motion and continuous at seams.
            float water_beat = floor(water_time * 8.0) / 8.0;
            vec2 secondary_drift = floor(vec2(13.0, -7.0)
                * water_beat * water_ripple_drift_speed);
            vec2 secondary_coordinate = (liquid_pixel + secondary_drift)
                * liquid_pattern_frequency * water_secondary_ripple_scale;
            float secondary_ripple = sin(dot(
                secondary_coordinate, vec2(0.61, 1.27)) + 1.73);
            float secondary_crest = secondary_ripple * 0.5 + 0.5;
            float secondary_shimmer = (secondary_crest - 0.5)
                * liquid_shimmer_strength * water_ripple_strength;
            surface_rgb += liquid_highlight_tint * secondary_shimmer;

            // Candidate dashes are fixed to a world-space lattice. Each one
            // receives a deterministic short beat and appears only on a crest.
            vec2 glint_pixel = floor(liquid_pixel);
            vec2 glint_cell = floor(glint_pixel / vec2(12.0, 7.0));
            vec2 glint_local = glint_pixel - glint_cell * vec2(12.0, 7.0);
            float placement = hash_value(glint_cell + seed_offset * 0.013);
            if (placement < water_glint_density && secondary_crest > 0.67) {
                float shape_hash = hash_value(glint_cell + vec2(41.0, -19.0));
                float glint_row = 1.0 + floor(shape_hash * 4.0);
                float glint_start = 1.0 + floor(hash_value(
                    glint_cell + vec2(-7.0, 29.0)) * 5.0);
                float glint_length = 2.0 + floor(hash_value(
                    glint_cell + vec2(17.0, 53.0)) * 3.0);
                float glint_slope = shape_hash > 0.72 ? 1.0 : 0.0;
                float beat_offset = floor(hash_value(
                    glint_cell + vec2(73.0, 11.0)) * 12.0);
                float glint_beat = mod(floor(water_time * 4.0) + beat_offset, 12.0);
                bool horizontal = abs(glint_local.y - glint_row) < 0.25
                    && glint_local.x >= glint_start
                    && glint_local.x < glint_start + glint_length;
                bool angled_tip = glint_slope > 0.5
                    && abs(glint_local.y - glint_row - 1.0) < 0.25
                    && abs(glint_local.x - glint_start - glint_length) < 0.25;
                if (glint_beat < 1.0 && (horizontal || angled_tip)) {
                    surface_rgb = mix(
                        surface_rgb, liquid_highlight_tint,
                        water_glint_brightness);
                }
            }
        }
    }
    COLOR = vec4(clamp(surface_rgb, vec3(0.0), vec3(1.0)), mask_alpha);
}
