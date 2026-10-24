extends "res://tests/phase_c4j_legacy_cliff_coverage_benchmark.gd"
## Matched C4K measurements for the accepted dense and typical fixtures.

const C4K_OUTPUT_PATH := "res://.artifacts/c4k_sidewall_occlusion_benchmark.json"


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo = load("res://main.tscn").instantiate()
	demo.chunk_profiling_enabled = true
	root.add_child(demo)
	await _wait_frames(8)
	terrain = demo.terrain
	demo.hud.visible = false
	demo.editor_panel.visible = false
	demo.cursor.visible = false
	terrain.set_water_animation_time_override(0.0)
	terrain.set_decoration_generation_enabled(false)
	terrain.set_environment_object_generation_enabled(false)
	terrain.set_procedural_cliff_materials_enabled(true)
	terrain.set_organic_cliff_geometry_enabled(true)
	terrain.set_unified_cliff_components_enabled(true)
	terrain.set_refined_cliff_silhouettes_enabled(true)
	terrain.set_connected_cliff_contours_enabled(true)
	terrain.set_unified_cliff_contours_enabled(true)
	terrain.set_directional_cliff_projection_enabled(true)
	terrain.set_grid_aligned_cliff_rim_enabled(false)
	terrain.set_cliff_rendering_mode(TerrainRenderer.CliffRenderingMode.LEGACY)
	terrain.set_cliff_height_profile(TerrainRenderer.CliffHeightProfile.PROMINENT)
	terrain.set_legacy_cliff_coverage_repair_enabled(true)
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)

	var dense_center := Vector2i(10200, 5100)
	_build_fixture(dense_center)
	var dense: Dictionary = await _measure_c4k_fixture("dense", dense_center)
	var dense_chunks: Array = terrain.loaded_chunks.keys()

	var typical_center := Vector2i(15400, 7700)
	_build_typical_fixture(typical_center)
	var typical: Dictionary = await _measure_c4k_fixture("typical", typical_center)
	var retired_dense_chunks := true
	for chunk_coord in dense_chunks:
		if terrain.loaded_chunks.has(chunk_coord):
			retired_dense_chunks = false
			break

	var result := {
		"engine": Engine.get_version_info().get("string", "unknown"),
		"display_server": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"seed": terrain.world_seed,
		"viewport": [1280, 720],
		"repeat_count": REPEAT_COUNT,
		"dense": dense,
		"typical": typical,
		"dense_chunks_retired_after_move": retired_dense_chunks,
	}
	var file := FileAccess.open(C4K_OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null, "Could not write C4K benchmark")
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_C4K_BENCHMARK: PASS")
	quit(0)


func _measure_c4k_fixture(label: String, center: Vector2i) -> Dictionary:
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	terrain.set_legacy_cliff_sidewall_occlusion_repair_enabled(false)
	await _wait_until_idle()
	var reference: Dictionary = await _measure_c4k_rebuild()
	var reference_steady: Dictionary = await _sample_fixed_frames(STEADY_SAMPLE_FRAMES)
	terrain.set_legacy_cliff_sidewall_occlusion_repair_enabled(true)
	await _wait_until_idle()
	var runs: Array[Dictionary] = []
	for _repeat in range(REPEAT_COUNT):
		runs.append(await _measure_c4k_rebuild())
	var steady: Dictionary = await _sample_fixed_frames(STEADY_SAMPLE_FRAMES)
	return {
		"fixture": label,
		"repair_disabled_reference": reference,
		"repair_disabled_steady": reference_steady,
		"repair_enabled_runs": runs,
		"repair_enabled_summary": _summarize_runs(runs),
		"repair_enabled_steady": steady,
	}


func _measure_c4k_rebuild() -> Dictionary:
	terrain.reset_incremental_cliff_scheduler_metrics()
	terrain._invalidate_streamed_chunks()
	demo._update_visible_world_region()
	var streaming: Dictionary = await _sample_until_idle()
	var geometry: Dictionary = _geometry_totals()
	geometry.merge(_sidewall_geometry_totals(), true)
	return {"geometry": geometry, "streaming": streaming}


func _sidewall_geometry_totals() -> Dictionary:
	var vertices := 0
	var triangles := 0
	var meshes := 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		vertices += int(stats.sidewall_occlusion_vertex_count)
		triangles += int(stats.sidewall_occlusion_triangle_count)
		meshes += int(stats.sidewall_occlusion_mesh_count)
	return {
		"sidewall_occlusion_vertices": vertices,
		"sidewall_occlusion_triangles": triangles,
		"sidewall_occlusion_meshes": meshes,
	}
