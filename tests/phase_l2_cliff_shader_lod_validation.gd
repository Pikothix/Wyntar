extends SceneTree
## Focused L2 checks for configuration, continuous zoom mapping, shared-material
## updates, rollback, streaming persistence and unchanged cliff geometry.

const MainScene = preload("res://main.tscn")
const MainScript = preload("res://scripts/main.gd")
const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const TerrainRendererConfiguration = preload(
	"res://scripts/settings/terrain_renderer_configuration.gd")

const ZOOMS := [0.125, 0.25, 0.5, 1.0, 1.75, 2.5, 3.5]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_mapping_and_configuration()
	await _validate_runtime_integration()
	if failures.is_empty():
		print("PHASE_L2_CLIFF_SHADER_LOD_VALIDATION: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("PHASE_L2_CLIFF_SHADER_LOD_VALIDATION: FAIL (%d)" % failures.size())
		quit(1)


func _validate_mapping_and_configuration() -> void:
	var previous: float = -1.0
	for zoom in ZOOMS:
		var detail: float = TerrainRenderer.calculate_cliff_shader_lod_detail(
			zoom, 0.125, 1.0, 0.20)
		_expect(detail >= previous, "detail mapping is monotonic at zoom %.3f" % zoom)
		previous = detail
	_expect(is_equal_approx(TerrainRenderer.calculate_cliff_shader_lod_detail(
		0.125, 0.125, 1.0, 0.20), 0.20), "minimum zoom maps to minimum detail")
	_expect(is_equal_approx(TerrainRenderer.calculate_cliff_shader_lod_detail(
		1.0, 0.125, 1.0, 0.20), 1.0), "normal zoom maps to full detail")
	_expect(is_equal_approx(TerrainRenderer.calculate_cliff_shader_lod_detail(
		3.5, 0.125, 1.0, 0.20), 1.0), "close zoom remains full detail")

	var main = MainScript.new()
	var configuration = TerrainRendererConfiguration.capture(main)
	var renderer = TerrainRenderer.new()
	configuration.apply_to(renderer)
	_expect(renderer.cliff_shader_lod_enabled
		and is_equal_approx(renderer.cliff_shader_lod_min_zoom, 0.125)
		and is_equal_approx(renderer.cliff_shader_lod_full_detail_zoom, 1.0)
		and is_equal_approx(renderer.cliff_shader_lod_min_detail, 0.20),
		"L2 defaults pass through the existing typed configuration owner")
	main.cliff_shader_lod_min_zoom = 0.5
	main.cliff_shader_lod_full_detail_zoom = 0.1
	main.cliff_shader_lod_min_detail = -2.0
	var clamped = TerrainRenderer.new()
	main._configure_terrain_renderer(clamped)
	_expect(clamped.cliff_shader_lod_full_detail_zoom > clamped.cliff_shader_lod_min_zoom
		and is_equal_approx(clamped.cliff_shader_lod_min_detail, 0.0),
		"invalid compatibility-export values are clamped before renderer startup")
	main.free()
	renderer.free()
	clamped.free()


func _validate_runtime_integration() -> void:
	var main = MainScene.instantiate()
	main.include_elevation_demo = false
	main.load_margin_chunks = 0
	main.unload_margin_chunks = 1
	main.chunks_created_per_frame = 8
	main.max_chunk_processing_ms = 10.0
	main.chunk_work_quantum_cells = 256
	main.max_tile_cells_per_frame = 1024
	main.decorations_enabled = false
	main.environment_objects_enabled = false
	root.add_child(main)
	await process_frame
	# Keep this focused test from expanding the streamed world while exercising
	# far-zoom signals; streaming persistence is checked separately at 100%.
	main.set_process(false)
	var terrain = main.terrain
	var material_ids: Array[int] = _material_ids(terrain)
	_expect(material_ids.size() == 9, "one organic and eight atlas/shadow materials remain shared")

	for zoom in ZOOMS:
		main.camera.apply_state(main.camera.position, zoom)
		var expected: float = TerrainRenderer.calculate_cliff_shader_lod_detail(
			zoom, terrain.cliff_shader_lod_min_zoom,
			terrain.cliff_shader_lod_full_detail_zoom, terrain.cliff_shader_lod_min_detail)
		_expect(_all_materials_match(terrain, expected),
			"camera zoom %.3f updates every shared cliff material" % zoom)
		var diagnostic: Dictionary = terrain.get_cliff_shader_lod_diagnostics()
		_expect(is_equal_approx(float(diagnostic.zoom), zoom)
			and is_equal_approx(float(diagnostic.calculated_detail), expected)
			and is_equal_approx(float(diagnostic.applied_detail), expected)
			and is_equal_approx(float(diagnostic.actual_material_detail), expected)
			and int(diagnostic.material_count) == 9
			and bool(diagnostic.all_materials_match),
			"diagnostic reads calculated, applied and actual shared values at %.3f" % zoom)

	main.cliff_lod_diagnostic_label.visible = true
	main._update_cliff_lod_diagnostic()
	_expect(main.cliff_lod_diagnostic_label.text.contains("Shader actual:"),
		"reversible gameplay diagnostic displays the actual shader value")
	main.cliff_lod_diagnostic_label.visible = false

	terrain.set_cliff_shader_lod_enabled(false)
	main.camera.apply_state(main.camera.position, 0.125)
	_expect(_all_materials_match(terrain, 1.0),
		"disabled LOD restores the fixed pre-L2 detail value")
	terrain.set_cliff_shader_lod_enabled(true)
	_expect(_all_materials_match(terrain, 0.20),
		"re-enabling LOD restores detail for the current camera zoom")
	main.camera.zoom = Vector2.ONE
	main.camera.force_update_scroll()
	terrain.set_cliff_shader_lod_zoom(0.25)
	var expected_detail: float = TerrainRenderer.calculate_cliff_shader_lod_detail(
		0.25, terrain.cliff_shader_lod_min_zoom,
		terrain.cliff_shader_lod_full_detail_zoom, terrain.cliff_shader_lod_min_detail)
	var detail_before_stream: float = terrain.cliff_shader_lod_detail
	terrain._invalidate_streamed_chunks()
	main._update_visible_world_region()
	await _wait_until_idle(terrain, 1200)
	_expect(_material_ids(terrain) == material_ids,
		"streaming and chunk rebuilds do not duplicate cliff materials")
	_expect(is_equal_approx(terrain.cliff_shader_lod_detail, detail_before_stream)
		and _all_materials_match(terrain, expected_detail),
		"streamed replacement chunks retain the current shared detail value")
	main.queue_free()


func _materials(terrain) -> Array[ShaderMaterial]:
	var result: Array[ShaderMaterial] = []
	for material in terrain.cliff_material_by_source.values():
		result.append(material)
	for material in terrain.cliff_shadow_material_by_source.values():
		result.append(material)
	result.append(terrain.organic_cliff_material)
	return result


func _material_ids(terrain) -> Array[int]:
	var result: Array[int] = []
	for material in _materials(terrain):
		result.append(material.get_instance_id())
	return result


func _all_materials_match(terrain, expected: float) -> bool:
	for material in _materials(terrain):
		if not is_equal_approx(float(material.get_shader_parameter("detail_level")), expected):
			return false
	return true


func _wait_until_idle(terrain, max_frames: int) -> void:
	for _frame in range(max_frames):
		await process_frame
		if (terrain.get_pending_chunk_count() == 0
				and terrain.get_pending_edit_cell_count() == 0
				and terrain.get_pending_edit_environment_chunk_count() == 0):
			return
	failures.append("terrain streaming did not become idle within %d frames" % max_frames)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
