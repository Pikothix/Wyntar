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
    if (liquid_enabled > 0.5) {
        // Broad world-space bands break tile repetition without per-cell nodes.
        // Motion is a single optional phase term and is quantised to retain the
        // nearest-neighbour pixel-art character at high zoom.
        float motion_phase = TIME * liquid_motion_speed * liquid_motion_enabled;
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
    }
    COLOR = vec4(clamp(surface_rgb, vec3(0.0), vec3(1.0)), mask_alpha);
}
