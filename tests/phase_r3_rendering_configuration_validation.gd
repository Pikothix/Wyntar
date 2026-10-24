extends SceneTree
## Focused R3 checks for compatibility exports, typed grouping, defaults,
## protected scene overrides, clamp parity and pre-ready renderer application.

const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const TerrainRendererConfiguration = preload(
	"res://scripts/settings/terrain_renderer_configuration.gd")

const PROTECTED_SCENE_OVERRIDES := {
	"include_elevation_demo": true,
	"experimental_water_enhancement_enabled": true,
	"water_ripple_strength": 0.63,
	"water_ripple_drift_speed": 0.25,
	"water_glint_density": 0.6,
	"water_glint_brightness": 0.7,
	"unified_cliff_contours_enabled": true,
	"directional_cliff_projection_enabled": true,
	# C4H established the scene's moderate profile as the accepted LEGACY view.
	"cliff_height_profile": 1,
	"cliff_edge_overlays_visible": false,
	"cliff_shadows_visible": false,
	"decoration_density": 2.0,
	"decoration_clustering_strength": 1.0,
	"environment_object_density": 2.0,
}

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_legacy_defaults_and_grouping()
	await _validate_scene_overrides_and_startup()
	if failures.is_empty():
		print("PHASE_R3_RENDERING_CONFIGURATION_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_R3_RENDERING_CONFIGURATION_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _validate_legacy_defaults_and_grouping() -> void:
	var main = MainScript.new()
	var property_names: Dictionary = {}
	for property in main.get_property_list():
		property_names[String(property["name"])] = true
	for property_name in PROTECTED_SCENE_OVERRIDES:
		_expect(property_names.has(property_name),
			"legacy export remains available: %s" % property_name)

	_expect(main.world_seed == 84521 and is_equal_approx(main.biome_frequency, 0.012)
		and main.procedural_elevation_enabled and main.max_generated_elevation == 3,
		"world-generation defaults remain unchanged")
	_expect(main.load_margin_chunks == 1 and main.unload_margin_chunks == 2
		and main.chunks_created_per_frame == 2
		and is_equal_approx(main.max_chunk_processing_ms, 2.5),
		"streaming defaults remain unchanged")
	_expect(main.texture_variation_enabled and main.clustered_grass_detail_enabled
		and main.terrain_texture_repetition_correction_enabled
		and main.stochastic_terrain_detail_enabled and main.remaining_terrain_detail_enabled,
		"terrain and grass defaults remain enabled")
	_expect(not main.experimental_water_enhancement_enabled
		and main.cliff_shader_lod_enabled
		and is_equal_approx(main.cliff_shader_lod_min_zoom, 0.125)
		and is_equal_approx(main.cliff_shader_lod_full_detail_zoom, 1.0)
		and is_equal_approx(main.cliff_shader_lod_min_detail, 0.20)
		and not main.unified_cliff_contours_enabled
		and not main.grid_aligned_cliff_rim_enabled
		and main.cliff_rendering_mode == TerrainRenderer.CliffRenderingMode.LEGACY
		and not main.directional_cliff_projection_enabled,
		"experimental defaults remain disabled")
	_expect(main.legacy_cliff_coverage_repair_enabled
		and main.legacy_cliff_sidewall_occlusion_repair_enabled,
		"accepted LEGACY coverage repairs remain enabled by default")

	var configuration = TerrainRendererConfiguration.capture(main)
	_expect(configuration.world_generation != null and configuration.chunk_streaming != null
		and configuration.terrain_rendering != null and configuration.water_rendering != null
		and configuration.cliff_rendering != null
		and configuration.environment_rendering != null,
		"configuration is grouped by explicit ownership")

	main.world_seed = -999
	main.water_ripple_strength = 0.25
	var renderer = TerrainRenderer.new()
	configuration.apply_to(renderer)
	_expect(renderer.generator == null and renderer.world == null,
		"configuration applies before renderer initialization")
	_expect(renderer.world_seed == 84521 and is_equal_approx(renderer.water_ripple_strength, 0.32),
		"captured configuration is independent from later compatibility-export changes")
	_expect(renderer.cliff_shader_lod_enabled
		and is_equal_approx(renderer.cliff_shader_lod_min_zoom, 0.125)
		and is_equal_approx(renderer.cliff_shader_lod_full_detail_zoom, 1.0)
		and is_equal_approx(renderer.cliff_shader_lod_min_detail, 0.20),
		"L2 cliff shader settings use the existing typed configuration path")
	_expect(renderer.legacy_cliff_sidewall_occlusion_repair_enabled,
		"C4K sidewall repair uses the existing typed configuration path")

	main.water_ripple_strength = 4.0
	main.water_secondary_ripple_scale = 0.1
	main.cliff_repetition_correction_strength = -2.0
	var clamped_renderer = TerrainRenderer.new()
	main._configure_terrain_renderer(clamped_renderer)
	_expect(is_equal_approx(clamped_renderer.water_ripple_strength, 1.0)
		and is_equal_approx(clamped_renderer.water_secondary_ripple_scale, 0.5)
		and is_equal_approx(clamped_renderer.cliff_repetition_correction_strength, 0.0),
		"legacy clamp behavior remains unchanged")
	renderer.free()
	clamped_renderer.free()
	main.free()


func _validate_scene_overrides_and_startup() -> void:
	var main = MainScene.instantiate()
	for property_name in PROTECTED_SCENE_OVERRIDES:
		var expected: Variant = PROTECTED_SCENE_OVERRIDES[property_name]
		var actual: Variant = main.get(property_name)
		_expect(actual == expected,
			"protected main.tscn override remains effective: %s" % property_name)
	main.organic_cliff_geometry_enabled = false
	main.decorations_enabled = false
	main.environment_objects_enabled = false
	root.add_child(main)
	await process_frame
	_expect(main.terrain.experimental_water_enhancement_enabled
		and is_equal_approx(main.terrain.water_ripple_strength, 0.63)
		and is_equal_approx(main.terrain.water_ripple_drift_speed, 0.25)
		and is_equal_approx(main.terrain.water_glint_density, 0.6)
		and is_equal_approx(main.terrain.water_glint_brightness, 0.7),
		"protected water overrides reach the startup renderer")
	_expect(main.terrain.unified_cliff_contours_enabled
		and main.terrain.directional_cliff_projection_enabled
		and main.terrain.cliff_height_profile == 1
		and not main.terrain.cliff_edge_overlays_visible
		and not main.terrain.cliff_shadows_visible,
		"protected cliff overrides reach the startup renderer")
	_expect(is_equal_approx(main.terrain.decoration_density, 2.0)
		and is_equal_approx(main.terrain.decoration_clustering_strength, 1.0)
		and is_equal_approx(main.terrain.environment_object_density, 2.0),
		"protected placement overrides reach the startup renderer")
	main.queue_free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
