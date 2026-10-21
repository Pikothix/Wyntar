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
// Negative uses Godot's global TIME. Tests may provide a fixed non-negative
// time so before/after captures compare the same animation instant.
uniform float water_animation_time_override = -1.0;

varying vec2 world_position;


float hash_value(vec2 point) {
    return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
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
    // The +16 phase matches the original half-tile-shifted dual-grid texture.
    vec2 tiled_uv = (world_position + vec2(16.0)) / 32.0;
    vec4 original = texture(base_texture, tiled_uv);
    float noise_value = smooth_value_noise(world_position * variation_frequency + seed_offset);
    vec4 varied = sample_variant_ramp(tiled_uv, noise_value);
    float blend_amount = clamp(variation_enabled * variation_strength, 0.0, 1.0);
    // Quantising the lookup to world pixels keeps magnified edges crisp. A
    // single signed offset is applied to the encoded scalar field for every
    // material; subset masks therefore remain subsets after deformation.
    vec2 world_pixel = floor(world_position) + vec2(0.5);
    float organic_noise = smooth_value_noise(
        world_pixel * organic_edge_frequency + organic_seed_offset) * 2.0 - 1.0;
    float organic_alpha = smoothstep(
        0.43, 0.57, masked_atlas.r + organic_noise * organic_edge_strength) * original.a;
    float mask_alpha = mix(
        masked_atlas.a, organic_alpha, clamp(organic_boundaries_enabled, 0.0, 1.0));
    vec3 surface_rgb = mix(original.rgb, varied.rgb, blend_amount);
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
        float source_luma = dot(original.rgb, vec3(0.2126, 0.7152, 0.0722));
        float dark_mark = 1.0 - smoothstep(
            grass_detail_luma_threshold - 0.035,
            grass_detail_luma_threshold + 0.025,
            source_luma);
        float suppress_mark = dark_mark * step(retention_probability, detail_roll);
        // Preserve the active tint/variation delta while replacing only the
        // suppressed source mark with the grass definition's clear palette.
        vec3 clear_surface = clamp(
            surface_rgb + grass_clear_color - original.rgb,
            vec3(0.0), vec3(1.0));
        surface_rgb = mix(surface_rgb, clear_surface, suppress_mark);
    }
    if (liquid_enabled > 0.5) {
        // Broad world-space bands break tile repetition without per-cell nodes.
        // Motion is a single optional phase term and is quantised to retain the
        // nearest-neighbour pixel-art character at high zoom.
        float water_time = water_animation_time_override >= 0.0
            ? water_animation_time_override : TIME;
        float motion_phase = water_time * liquid_motion_speed * liquid_motion_enabled;
        vec2 liquid_pixel = floor(world_position) + vec2(0.5);
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
