extends RefCounted
## Typed pre-ready snapshot of terrain-surface and grass presentation settings.

var texture_variation_enabled: bool
var texture_variation_strength: float
var texture_variation_frequency: float
var clustered_grass_detail_enabled: bool
var grass_clear_area_coverage: float
var grass_detail_density: float
var grass_cluster_scale: float
var grass_transition_softness: float
var grass_clear_area_residual_density: float
var grass_detail_seed_offset: int
var organic_grass_color_variation_enabled: bool
var grass_broad_variation_scale: float
var grass_color_variation_strength: float
var grass_fine_variation_strength: float
var grass_texture_repetition_correction_enabled: bool
var terrain_texture_repetition_correction_enabled: bool
var terrain_texture_repetition_material_settings: Dictionary
var stochastic_terrain_detail_enabled: bool
var stochastic_terrain_detail_material_settings: Dictionary
var remaining_terrain_detail_enabled: bool
var remaining_terrain_detail_material_settings: Dictionary
var terrain_noise_refinement_enabled: bool
var terrain_noise_refinement_material_settings: Dictionary
var organic_boundaries_enabled: bool
var organic_edge_strength: float
var organic_edge_frequency: float


static func capture(source):
	var settings = new()
	settings.texture_variation_enabled = source.texture_variation_enabled
	settings.texture_variation_strength = source.texture_variation_strength
	settings.texture_variation_frequency = source.texture_variation_frequency
	settings.clustered_grass_detail_enabled = source.clustered_grass_detail_enabled
	settings.grass_clear_area_coverage = source.grass_clear_area_coverage
	settings.grass_detail_density = source.grass_detail_density
	settings.grass_cluster_scale = source.grass_cluster_scale
	settings.grass_transition_softness = source.grass_transition_softness
	settings.grass_clear_area_residual_density = source.grass_clear_area_residual_density
	settings.grass_detail_seed_offset = source.grass_detail_seed_offset
	settings.organic_grass_color_variation_enabled = source.organic_grass_color_variation_enabled
	settings.grass_broad_variation_scale = source.grass_broad_variation_scale
	settings.grass_color_variation_strength = source.grass_color_variation_strength
	settings.grass_fine_variation_strength = source.grass_fine_variation_strength
	settings.grass_texture_repetition_correction_enabled = \
		source.grass_texture_repetition_correction_enabled
	settings.terrain_texture_repetition_correction_enabled = \
		source.terrain_texture_repetition_correction_enabled
	settings.terrain_texture_repetition_material_settings = {
		1: {"enabled": source.sand_texture_repetition_correction_enabled,
			"strength": source.sand_texture_repetition_correction_strength},
		2: {"enabled": source.dirt_texture_repetition_correction_enabled,
			"strength": source.dirt_texture_repetition_correction_strength},
		4: {"enabled": source.stone_texture_repetition_correction_enabled,
			"strength": source.stone_texture_repetition_correction_strength},
		5: {"enabled": source.snow_texture_repetition_correction_enabled,
			"strength": source.snow_texture_repetition_correction_strength},
		6: {"enabled": source.mud_texture_repetition_correction_enabled,
			"strength": source.mud_texture_repetition_correction_strength},
		7: {"enabled": source.gravel_texture_repetition_correction_enabled,
			"strength": source.gravel_texture_repetition_correction_strength},
	}
	settings.stochastic_terrain_detail_enabled = source.stochastic_terrain_detail_enabled
	settings.stochastic_terrain_detail_material_settings = {
		1: {"enabled": source.sand_stochastic_detail_enabled,
			"intensity": source.sand_stochastic_detail_intensity},
		2: {"enabled": source.dirt_stochastic_detail_enabled,
			"intensity": source.dirt_stochastic_detail_intensity},
		4: {"enabled": source.stone_stochastic_detail_enabled,
			"intensity": source.stone_stochastic_detail_intensity},
		6: {"enabled": source.mud_stochastic_detail_enabled,
			"intensity": source.mud_stochastic_detail_intensity},
	}
	settings.remaining_terrain_detail_enabled = source.remaining_terrain_detail_enabled
	settings.remaining_terrain_detail_material_settings = {
		5: {"enabled": source.snow_remaining_detail_enabled,
			"strength": source.snow_remaining_detail_strength},
		7: {"enabled": source.gravel_remaining_detail_enabled,
			"strength": source.gravel_remaining_detail_strength},
	}
	settings.terrain_noise_refinement_enabled = source.terrain_noise_refinement_enabled
	settings.terrain_noise_refinement_material_settings = {
		2: {"density": source.dirt_detail_density,
			"contrast": source.dirt_detail_contrast,
			"clear_area": source.dirt_clear_area_coverage,
			"cluster_scale": source.dirt_detail_cluster_scale},
		4: {"density": source.stone_detail_density,
			"contrast": source.stone_detail_contrast,
			"clear_area": source.stone_clear_area_coverage,
			"cluster_scale": source.stone_detail_cluster_scale},
		6: {"density": source.mud_detail_density,
			"contrast": source.mud_detail_contrast,
			"clear_area": source.mud_clear_area_coverage,
			"cluster_scale": source.mud_detail_cluster_scale},
		7: {"density": source.gravel_detail_density,
			"contrast": source.gravel_detail_contrast,
			"clear_area": source.gravel_clear_area_coverage,
			"cluster_scale": source.gravel_detail_cluster_scale},
	}
	settings.organic_boundaries_enabled = source.organic_boundaries_enabled
	settings.organic_edge_strength = source.organic_edge_strength
	settings.organic_edge_frequency = source.organic_edge_frequency
	return settings


func apply_to(renderer) -> void:
	renderer.texture_variation_enabled = texture_variation_enabled
	renderer.texture_variation_strength = texture_variation_strength
	renderer.texture_variation_frequency = texture_variation_frequency
	renderer.clustered_grass_detail_enabled = clustered_grass_detail_enabled
	renderer.grass_clear_area_coverage = grass_clear_area_coverage
	renderer.grass_detail_density = grass_detail_density
	renderer.grass_cluster_scale = grass_cluster_scale
	renderer.grass_transition_softness = grass_transition_softness
	renderer.grass_clear_area_residual_density = grass_clear_area_residual_density
	renderer.grass_detail_seed_offset = grass_detail_seed_offset
	renderer.organic_grass_color_variation_enabled = organic_grass_color_variation_enabled
	renderer.grass_broad_variation_scale = grass_broad_variation_scale
	renderer.grass_color_variation_strength = grass_color_variation_strength
	renderer.grass_fine_variation_strength = grass_fine_variation_strength
	renderer.grass_texture_repetition_correction_enabled = grass_texture_repetition_correction_enabled
	renderer.terrain_texture_repetition_correction_enabled = \
		terrain_texture_repetition_correction_enabled
	renderer.terrain_texture_repetition_material_settings = \
		terrain_texture_repetition_material_settings
	renderer.stochastic_terrain_detail_enabled = stochastic_terrain_detail_enabled
	renderer.stochastic_terrain_detail_material_settings = \
		stochastic_terrain_detail_material_settings
	renderer.remaining_terrain_detail_enabled = remaining_terrain_detail_enabled
	renderer.remaining_terrain_detail_material_settings = \
		remaining_terrain_detail_material_settings
	renderer.terrain_noise_refinement_enabled = terrain_noise_refinement_enabled
	renderer.terrain_noise_refinement_material_settings = \
		terrain_noise_refinement_material_settings
	renderer.organic_boundaries_enabled = organic_boundaries_enabled
	renderer.organic_edge_strength = organic_edge_strength
	renderer.organic_edge_frequency = organic_edge_frequency
