extends "res://tests/phase1f_benchmark.gd"
## Repeated matched C4J measurements for dense and typical terrain fixtures.

const TerrainRenderer = preload("res://scripts/terrain_renderer.gd")
const C4J_OUTPUT_PATH := "res://.artifacts/c4j_legacy_cliff_coverage_benchmark.json"
const REPEAT_COUNT := 3
const STEADY_SAMPLE_FRAMES := 180


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
	terrain.set_cliff_edge_overlays_visible(false)
	terrain.set_cliff_shadows_visible(false)

	var dense_center := Vector2i(10200, 5100)
	_build_fixture(dense_center)
	var dense: Dictionary = await _measure_fixture("dense", dense_center)
	var dense_chunks: Array = terrain.loaded_chunks.keys()

	var typical_center := Vector2i(15400, 7700)
	_build_typical_fixture(typical_center)
	var typical: Dictionary = await _measure_fixture("typical", typical_center)
	var retired_dense_chunks: bool = true
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
	var file := FileAccess.open(C4J_OUTPUT_PATH, FileAccess.WRITE)
	assert(file != null, "Could not write C4J benchmark")
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("PHASE_C4J_BENCHMARK: PASS")
	quit(0)


func _measure_fixture(label: String, center: Vector2i) -> Dictionary:
	demo.camera.position = Vector2(center * terrain.TILE_SIZE) + Vector2(16, 16)
	demo.camera.zoom = Vector2.ONE
	demo.camera.force_update_scroll()
	demo._update_visible_world_region()
	terrain.set_legacy_cliff_coverage_repair_enabled(false)
	await _wait_until_idle()
	var reference: Dictionary = await _measure_rebuild()
	terrain.set_legacy_cliff_coverage_repair_enabled(true)
	await _wait_until_idle()
	var runs: Array[Dictionary] = []
	for _repeat in range(REPEAT_COUNT):
		runs.append(await _measure_rebuild())
	var steady: Dictionary = await _sample_fixed_frames(STEADY_SAMPLE_FRAMES)
	return {
		"fixture": label,
		"coverage_disabled_reference": reference,
		"coverage_enabled_runs": runs,
		"coverage_enabled_summary": _summarize_runs(runs),
		"coverage_enabled_steady": steady,
	}


func _measure_rebuild() -> Dictionary:
	terrain.reset_incremental_cliff_scheduler_metrics()
	terrain._invalidate_streamed_chunks()
	demo._update_visible_world_region()
	var streaming: Dictionary = await _sample_until_idle()
	var geometry: Dictionary = _geometry_totals()
	geometry.merge(_coverage_geometry_totals(), true)
	return {"geometry": geometry, "streaming": streaming}


func _coverage_geometry_totals() -> Dictionary:
	var vertices: int = 0
	var triangles: int = 0
	var meshes: int = 0
	for chunk in terrain.loaded_chunks.values():
		var stats: Dictionary = chunk.get_organic_cliff_geometry_stats()
		vertices += int(stats.coverage_vertex_count)
		triangles += int(stats.coverage_triangle_count)
		meshes += int(stats.coverage_mesh_count)
	return {
		"coverage_vertices": vertices,
		"coverage_triangles": triangles,
		"coverage_meshes": meshes,
	}


func _summarize_runs(runs: Array[Dictionary]) -> Dictionary:
	var build_values: Array[float] = []
	var frame_values: Array[float] = []
	var streaming_values: Array[float] = []
	for run in runs:
		build_values.append(float(run.geometry.build_ms))
		frame_values.append(float(run.streaming.average_frame_ms))
		streaming_values.append(float(run.streaming.elapsed_ms))
	return {
		"build_ms": _range_summary(build_values),
		"streaming_average_frame_ms": _range_summary(frame_values),
		"streaming_elapsed_ms": _range_summary(streaming_values),
	}


func _range_summary(values: Array[float]) -> Dictionary:
	var total: float = 0.0
	var minimum: float = INF
	var maximum: float = -INF
	for value in values:
		total += value
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return {
		"mean": total / values.size(),
		"minimum": minimum,
		"maximum": maximum,
		"range": maximum - minimum,
	}


func _build_typical_fixture(center: Vector2i) -> void:
	_fill(center - Vector2i(42, 30), Vector2i(84, 60), 3, 0)
	for y in range(-24, 25):
		for x in range(-36, 37):
			var ridge: float = sin(float(x) * 0.13) + cos(float(y) * 0.17)
			if ridge > 0.75:
				var height: int = 2 if ridge > 1.55 else 1
				_set_cell(center + Vector2i(x, y), 4 if (x + y) % 5 else 2, height)
