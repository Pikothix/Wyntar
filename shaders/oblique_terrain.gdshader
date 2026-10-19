shader_type canvas_item;
render_mode unshaded;

// Phase 2A presentation-only atlas material. Geometry owns silhouettes and
// encoded vertex colours own bounded tonal/facing information.
uniform sampler2D material_atlas : source_color, filter_nearest;
uniform sampler2D material_palette : source_color, filter_nearest;
uniform vec2 seed_offset = vec2(0.0);
uniform bool refinement_enabled = false;

varying vec2 world_position;


float hash_value(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}


float five_step_ramp(float value) {
	value = clamp(value, 0.0, 0.999999);
	if (value < 0.2) { return 0.72; }
	if (value < 0.4) { return 0.84; }
	if (value < 0.6) { return 0.96; }
	if (value < 0.8) { return 1.06; }
	return 1.14;
}


float surface_five_step_ramp(float value) {
	value = clamp(value, 0.0, 0.999999);
	if (value < 0.2) { return 0.94; }
	if (value < 0.4) { return 0.97; }
	if (value < 0.6) { return 1.00; }
	if (value < 0.8) { return 1.03; }
	return 1.06;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


void fragment() {
	vec4 pigment = texture(material_atlas, UV);
	float material_id = floor(UV.x * 8.0);
	float face_amount = COLOR.g;
	float shoreline = COLOR.b;
	float shade = COLOR.r;
	if (refinement_enabled) {
		vec2 continuous_uv = fract((world_position + seed_offset * 0.19) / 96.0);
		vec2 atlas_uv = vec2(
			(material_id + 0.02 + continuous_uv.x * 0.96) / 8.0,
			0.02 + continuous_uv.y * 0.96);
		vec4 broad_detail = texture(material_atlas, atlas_uv);
		vec4 base = texture(material_palette, vec2((material_id + 0.5) / 8.0, 0.5));
		float detail_amount = 0.42;
		if (material_id < 0.5) { detail_amount = 0.66; }
		else if (material_id < 1.5) { detail_amount = 0.34; }
		else if (material_id < 2.5) { detail_amount = 0.40; }
		else if (material_id < 3.5) { detail_amount = 0.36; }
		pigment.rgb = mix(base.rgb, broad_detail.rgb, detail_amount);
		if (face_amount < 0.5) {
			shade = surface_five_step_ramp(shade);
		}
	}
	if (face_amount > 0.5) {
		vec2 pixel = floor(world_position) + vec2(0.5);
		vec2 coarse_scale = refinement_enabled ? vec2(76.0, 48.0) : vec2(19.0, 13.0);
		vec2 fine_scale = refinement_enabled ? vec2(31.0, 23.0) : vec2(7.0, 6.0);
		float coarse = hash_value(floor((pixel + seed_offset) / coarse_scale));
		float fine = hash_value(floor((pixel + seed_offset * 0.37) / fine_scale));
		float facet = hash_value(floor(vec2(
			pixel.x + pixel.y * 0.55, pixel.y - pixel.x * 0.24) /
			(refinement_enabled ? 64.0 : 18.0)));
		float strata_scale = refinement_enabled ? 15.0 : 11.0;
		float strata_warp = refinement_enabled ? 8.0 : 5.0;
		float strata_coordinate = (
			pixel.y + (coarse - 0.5) * strata_warp) / strata_scale;
		float strata = 1.0 - smoothstep(
			0.06, 0.18, abs(fract(strata_coordinate) - 0.5));
		shade *= five_step_ramp(
			0.43 + (coarse - 0.5) * 0.25
			+ (fine - 0.5) * 0.12 + (facet - 0.5) * 0.16);
		shade *= 1.0 - strata * (refinement_enabled ? 0.065 : 0.085);
		if (shoreline > 0.5) {
			pigment.rgb = mix(pigment.rgb, vec3(0.48, 0.61, 0.60), 0.20);
			shade *= 0.94;
		}
	}
	COLOR = vec4(clamp(pigment.rgb * shade, vec3(0.0), vec3(1.0)), pigment.a);
}
