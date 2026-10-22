extends SceneTree
## Verifies Main applies one complete pre-ready renderer configuration during
## startup and save-world replacement without mutating authoritative save data.

const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")

const SHARED_PROPERTIES: Array[StringName] = [
	&"world_seed", &"biome_frequency", &"detail_frequency", &"include_origin_demo",
	&"procedural_elevation_enabled", &"max_generated_elevation", &"elevation_frequency",
	&"elevation_detail_frequency", &"elevation_detail_strength", &"elevation_threshold_1",
	&"elevation_threshold_2", &"elevation_threshold_3", &"elevation_flatness_bias", &"sea_level",
	&"load_margin_chunks", &"unload_margin_chunks", &"chunks_created_per_frame",
	&"max_chunk_processing_ms", &"chunk_work_quantum_cells", &"max_tile_cells_per_frame",
	&"texture_variation_enabled", &"texture_variation_strength", &"texture_variation_frequency",
	&"clustered_grass_detail_enabled", &"grass_clear_area_coverage",
	&"grass_detail_density", &"grass_cluster_scale", &"grass_transition_softness",
	&"grass_clear_area_residual_density", &"grass_detail_seed_offset",
	&"organic_grass_color_variation_enabled", &"grass_broad_variation_scale",
	&"grass_color_variation_strength", &"grass_fine_variation_strength",
	&"grass_texture_repetition_correction_enabled",
	&"terrain_texture_repetition_correction_enabled",
	&"stochastic_terrain_detail_enabled",
	&"remaining_terrain_detail_enabled", &"water_repetition_correction_enabled",
	&"water_repetition_correction_strength", &"cliff_repetition_correction_enabled",
	&"cliff_repetition_correction_strength",
	&"organic_boundaries_enabled", &"organic_edge_strength", &"organic_edge_frequency",
	&"experimental_water_enhancement_enabled", &"water_ripple_strength",
	&"water_secondary_ripple_scale", &"water_ripple_drift_speed", &"water_glint_density",
	&"water_glint_brightness", &"procedural_cliff_materials_enabled",
	&"organic_cliff_geometry_enabled", &"unified_cliff_components_enabled",
	&"refined_cliff_silhouettes_enabled", &"connected_cliff_contours_enabled",
	&"unified_cliff_contours_enabled", &"directional_cliff_projection_enabled",
	&"cliff_height_profile", &"cliff_edge_overlays_visible", &"cliff_shadows_visible",
	&"decorations_enabled", &"decoration_density", &"decoration_clustering_strength",
	&"decoration_seed_offset", &"environment_objects_enabled",
	&"procedural_vegetation_enabled", &"environment_object_density",
	&"environment_object_seed_offset", &"berry_regrowth_seconds",
]

const WATER_PROPERTIES: Array[StringName] = [
	&"experimental_water_enhancement_enabled", &"water_ripple_strength",
	&"water_secondary_ripple_scale", &"water_ripple_drift_speed",
	&"water_glint_density", &"water_glint_brightness",
]
const GRASS_PROPERTIES: Array[StringName] = [
	&"clustered_grass_detail_enabled", &"grass_clear_area_coverage",
	&"grass_detail_density", &"grass_cluster_scale", &"grass_transition_softness",
	&"grass_clear_area_residual_density", &"grass_detail_seed_offset",
	&"organic_grass_color_variation_enabled", &"grass_broad_variation_scale",
	&"grass_color_variation_strength", &"grass_fine_variation_strength",
	&"grass_texture_repetition_correction_enabled",
]
const CLIFF_PROPERTIES: Array[StringName] = [
	&"procedural_cliff_materials_enabled", &"organic_cliff_geometry_enabled",
	&"unified_cliff_components_enabled", &"refined_cliff_silhouettes_enabled",
	&"connected_cliff_contours_enabled", &"unified_cliff_contours_enabled",
	&"directional_cliff_projection_enabled", &"cliff_height_profile",
	&"cliff_edge_overlays_visible", &"cliff_shadows_visible",
]
const PLACEMENT_PROPERTIES: Array[StringName] = [
	&"decorations_enabled", &"decoration_density", &"decoration_clustering_strength",
	&"decoration_seed_offset", &"environment_objects_enabled",
	&"procedural_vegetation_enabled", &"environment_object_density",
	&"environment_object_seed_offset",
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_pre_ready_configuration()

	var main = MainScene.instantiate()
	_configure_distinct_fixture(main)
	root.add_child(main)
	await process_frame

	_expect_configuration_matches_main(main, main.terrain, "startup")
	var startup_configuration: Dictionary = _capture_configuration(main.terrain)
	var snapshot: Dictionary = main.save_service.capture_snapshot(
		main.terrain, main.camera, main.world_identifier, main.world_display_name)
	_expect(bool(main.save_service.validate_snapshot(snapshot)["ok"]),
		"existing save schema accepts the focused fixture")

	var replacement_result: Dictionary = main._replace_world_from_snapshot(snapshot)
	_expect(bool(replacement_result.get("ok", false)), "save-world replacement succeeds")
	if bool(replacement_result.get("ok", false)):
		var replacement_configuration: Dictionary = _capture_configuration(main.terrain)
		_expect(startup_configuration == replacement_configuration,
			"replacement receives configuration identical to startup")
		_expect(_properties_match(startup_configuration, replacement_configuration, WATER_PROPERTIES),
			"water configuration survives replacement")
		_expect(_properties_match(startup_configuration, replacement_configuration, GRASS_PROPERTIES),
			"clustered grass configuration survives replacement")
		_expect(_properties_match(startup_configuration, replacement_configuration, CLIFF_PROPERTIES),
			"cliff configuration survives replacement")
		_expect(_properties_match(startup_configuration, replacement_configuration, PLACEMENT_PROPERTIES),
			"decoration and environment configuration survives replacement")
		_expect_configuration_matches_main(main, main.terrain, "replacement")

	main.queue_free()
	if failures.is_empty():
		print("PHASE_C4A_RENDERER_CONFIGURATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_C4A_RENDERER_CONFIGURATION: FAIL (%d)" % failures.size())
		quit(1)


func _validate_pre_ready_configuration() -> void:
	var main = MainScript.new()
	_configure_distinct_fixture(main)
	var renderer = TerrainRenderer.new()
	main._configure_terrain_renderer(renderer)
	_expect(renderer.generator == null and renderer.world == null
		and renderer.resource_state_manager == null,
		"shared configuration runs before renderer initialization")
	_expect(renderer.get_pending_chunk_count() == 0 and renderer.loaded_chunks.is_empty(),
		"shared configuration does not schedule chunks or rebuilds")
	_expect_configuration_matches_main(main, renderer, "detached pre-ready renderer")
	renderer.free()
	main.free()


func _configure_distinct_fixture(main) -> void:
	main.world_seed = -246810
	main.biome_frequency = 0.019
	main.detail_frequency = 0.071
	main.include_origin_demo = false
	main.procedural_elevation_enabled = true
	main.max_generated_elevation = 2
	main.elevation_frequency = 0.009
	main.elevation_detail_frequency = 0.033
	main.elevation_detail_strength = 0.27
	main.elevation_threshold_1 = -0.21
	main.elevation_threshold_2 = 0.24
	main.elevation_threshold_3 = 0.51
	main.elevation_flatness_bias = -0.03
	main.sea_level = 1
	main.load_margin_chunks = 2
	main.unload_margin_chunks = 3
	main.chunks_created_per_frame = 3
	main.chunk_profiling_enabled = true
	main.max_chunk_processing_ms = 3.75
	main.chunk_work_quantum_cells = 40
	main.max_tile_cells_per_frame = 320
	main.texture_variation_enabled = false
	main.texture_variation_strength = 0.4
	main.texture_variation_frequency = 0.0041
	main.clustered_grass_detail_enabled = true
	main.grass_clear_area_coverage = 0.63
	main.grass_detail_density = 0.42
	main.grass_cluster_scale = 0.0065
	main.grass_transition_softness = 0.19
	main.grass_clear_area_residual_density = 0.08
	main.grass_detail_seed_offset = -3571
	main.organic_grass_color_variation_enabled = true
	main.grass_broad_variation_scale = 0.0035
	main.grass_color_variation_strength = 0.085
	main.grass_fine_variation_strength = 0.026
	main.grass_texture_repetition_correction_enabled = false
	main.terrain_texture_repetition_correction_enabled = false
	main.sand_texture_repetition_correction_enabled = false
	main.sand_texture_repetition_correction_strength = 0.15
	main.dirt_texture_repetition_correction_strength = 0.25
	main.stone_texture_repetition_correction_enabled = false
	main.stone_texture_repetition_correction_strength = 0.35
	main.snow_texture_repetition_correction_strength = 0.45
	main.mud_texture_repetition_correction_enabled = false
	main.mud_texture_repetition_correction_strength = 0.55
	main.gravel_texture_repetition_correction_strength = 0.65
	main.stochastic_terrain_detail_enabled = false
	main.sand_stochastic_detail_enabled = false
	main.sand_stochastic_detail_intensity = 0.25
	main.dirt_stochastic_detail_intensity = 0.35
	main.stone_stochastic_detail_enabled = false
	main.stone_stochastic_detail_intensity = 0.45
	main.mud_stochastic_detail_intensity = 0.55
	main.remaining_terrain_detail_enabled = false
	main.snow_remaining_detail_enabled = false
	main.snow_remaining_detail_strength = 0.62
	main.gravel_remaining_detail_enabled = true
	main.gravel_remaining_detail_strength = 0.73
	main.water_repetition_correction_enabled = false
	main.water_repetition_correction_strength = 0.44
	main.cliff_repetition_correction_enabled = false
	main.cliff_repetition_correction_strength = 0.81
	main.organic_boundaries_enabled = false
	main.organic_edge_strength = 0.11
	main.organic_edge_frequency = 0.047
	main.experimental_water_enhancement_enabled = true
	main.water_ripple_strength = 0.47
	main.water_secondary_ripple_scale = 3.1
	main.water_ripple_drift_speed = 0.8
	main.water_glint_density = 0.23
	main.water_glint_brightness = 0.61
	main.procedural_cliff_materials_enabled = false
	main.organic_cliff_geometry_enabled = true
	main.unified_cliff_components_enabled = false
	main.refined_cliff_silhouettes_enabled = true
	main.connected_cliff_contours_enabled = false
	main.unified_cliff_contours_enabled = true
	main.directional_cliff_projection_enabled = true
	main.cliff_height_profile = 1
	main.cliff_edge_overlays_visible = false
	main.cliff_shadows_visible = false
	main.decorations_enabled = false
	main.decoration_density = 1.35
	main.decoration_clustering_strength = 0.43
	main.decoration_seed_offset = 4567
	main.environment_objects_enabled = false
	main.procedural_vegetation_enabled = false
	main.environment_object_density = 1.45
	main.environment_object_seed_offset = 7654
	main.berry_regrowth_seconds = 37.0
	main.include_elevation_demo = false


func _expect_configuration_matches_main(main, renderer, stage: String) -> void:
	for property_name in SHARED_PROPERTIES:
		_expect(renderer.get(property_name) == main.get(property_name),
			"%s applies %s from Main exports" % [stage, property_name])
	_expect(renderer.profiling_enabled == main.chunk_profiling_enabled,
		"%s applies chunk_profiling_enabled" % stage)
	var expected_material_settings := {
		1: {"enabled": main.sand_texture_repetition_correction_enabled,
			"strength": main.sand_texture_repetition_correction_strength},
		2: {"enabled": main.dirt_texture_repetition_correction_enabled,
			"strength": main.dirt_texture_repetition_correction_strength},
		4: {"enabled": main.stone_texture_repetition_correction_enabled,
			"strength": main.stone_texture_repetition_correction_strength},
		5: {"enabled": main.snow_texture_repetition_correction_enabled,
			"strength": main.snow_texture_repetition_correction_strength},
		6: {"enabled": main.mud_texture_repetition_correction_enabled,
			"strength": main.mud_texture_repetition_correction_strength},
		7: {"enabled": main.gravel_texture_repetition_correction_enabled,
			"strength": main.gravel_texture_repetition_correction_strength},
	}
	_expect(renderer.terrain_texture_repetition_material_settings == expected_material_settings,
		"%s applies material-specific G4 settings" % stage)
	var expected_stochastic_settings := {
		1: {"enabled": main.sand_stochastic_detail_enabled,
			"intensity": main.sand_stochastic_detail_intensity},
		2: {"enabled": main.dirt_stochastic_detail_enabled,
			"intensity": main.dirt_stochastic_detail_intensity},
		4: {"enabled": main.stone_stochastic_detail_enabled,
			"intensity": main.stone_stochastic_detail_intensity},
		6: {"enabled": main.mud_stochastic_detail_enabled,
			"intensity": main.mud_stochastic_detail_intensity},
	}
	_expect(renderer.stochastic_terrain_detail_material_settings == expected_stochastic_settings,
		"%s applies material-specific G5 settings" % stage)
	var expected_remaining_settings := {
		5: {"enabled": main.snow_remaining_detail_enabled,
			"strength": main.snow_remaining_detail_strength},
		7: {"enabled": main.gravel_remaining_detail_enabled,
			"strength": main.gravel_remaining_detail_strength},
	}
	_expect(renderer.remaining_terrain_detail_material_settings == expected_remaining_settings,
		"%s applies material-specific G6 settings" % stage)


func _capture_configuration(renderer) -> Dictionary:
	var result: Dictionary = {
		&"profiling_enabled": renderer.profiling_enabled,
		&"terrain_texture_repetition_material_settings":
			renderer.terrain_texture_repetition_material_settings.duplicate(true),
		&"stochastic_terrain_detail_material_settings":
			renderer.stochastic_terrain_detail_material_settings.duplicate(true),
		&"remaining_terrain_detail_material_settings":
			renderer.remaining_terrain_detail_material_settings.duplicate(true),
	}
	for property_name in SHARED_PROPERTIES:
		result[property_name] = renderer.get(property_name)
	return result


func _properties_match(
		before: Dictionary, after: Dictionary, property_names: Array[StringName]) -> bool:
	for property_name in property_names:
		if before[property_name] != after[property_name]:
			return false
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
